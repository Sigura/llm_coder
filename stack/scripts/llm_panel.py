#!/usr/bin/env python3
"""Usage: llm_panel.py [--once] [--interval SEC] [--residency-every SEC] --model 'ID|PORT|MODEL_DIR|GPUS'...
       llm_panel.py --status MODEL_ID [--log FILE]

Console panel for the served models (started by llm-panel.sh, which resolves the model configs): one box per model
with the serve phase read from its devbox serve log, and a host box with RAM per NUMA node, page faults and reclaim,
NVMe temperature, CPU load per node and the GPUs. llama-server runs in other containers, so logs, /proc and /sys
are all there is. Page-cache residency (warm_read.py --check) runs in a background thread, at most once per
--residency-every seconds per model, because a scan of a 320 GB model costs ~15 s of system CPU.

--status prints the phase of one model from its serve log as text (used by llm-status.sh).
"""
import argparse
import curses
import glob
import locale
import math
import os
import re
import shutil
import subprocess
import sys
import threading
import time
from datetime import datetime

SCRIPTS = os.path.dirname(os.path.realpath(__file__))
sys.dont_write_bytecode = True
sys.path.insert(0, SCRIPTS)
import warm_read

LOGS_DIR = os.path.join(os.path.dirname(os.path.dirname(SCRIPTS)), ".devbox", "logs")
LOG_REFIND = 30

START = re.compile(r"^--- (\S+) started$")
ISO = re.compile(r"^(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d[+-]\d{4}) ")
# llama-server prints minutes.seconds.ms.us since its own start; a child instance's lines carry "[port] ".
REL = re.compile(r"^(?:\[(\d+)\] )?(\d+)\.(\d\d)\.(\d{3})\.(\d{3}) ")
WARMING = re.compile(r"^   warming: (\d+)/(\d+) GiB \((\d+)%\) in (\d+) s, nvme (\d+)C")
CACHED = re.compile(r"cached ([\d.]+)% of sampled pages; per NUMA node: ([\d.% ]*)")
SPAWN = re.compile(r"spawning server instance with name=\S+ on port (\d+)")
EXITED = re.compile(r"exited with status (\S+)")
LOAD_ARG = re.compile(r"\bload: +(\S+)$")
N_SLOTS = re.compile(r"n_slots = (\d+)")
SLOT = re.compile(r": id +(\d+) \| task ")
PROMPT = re.compile(r"prompt processing, n_tokens = +(\d+), progress = ([\d.]+), t = +([\d.]+) s / +([\d.]+) tokens per")
NGEN = re.compile(r"n_gen = +(\d+), tg = +([\d.]+) t/s")
EVAL = re.compile(r"(prompt eval|\| +eval) time = +([\d.]+) ms / +(\d+) tokens \(.*?, +([\d.]+) tokens per second\)")


class ServeLog:
    """Phase of one model, fed line by line from its serve log; a '--- <time> started' line starts over."""

    def __init__(self):
        self.reset(None)

    def reset(self, start):
        self.start = self.t = start
        self.router_t0 = None
        self.child_t0 = {}
        self.phase, self.detail, self.progress, self.since = "starting", "", None, start
        self.slots = {}
        self.last_prompt = self.last_gen = None  # (tokens, seconds, tok/s, time)
        self.warn = ""
        self.cache = None  # (fraction, per-node shares, time, after warm-up) from warm_read lines in the log
        self.warmup = {}  # start, end, read (warm_read's summary), skipped
        self.n_slots = self.batch = None
        self.prev_arg = ""
        self.history = []  # (time, event)
        if start:
            self.event("service started")

    def set(self, phase, detail="", progress=None):
        if phase != self.phase:
            self.phase, self.since = phase, self.t
        self.detail, self.progress = detail, progress

    def event(self, what):
        self.history = self.history[-49:] + [(self.t, what)]

    def feed(self, line):
        line = line.rstrip("\n")
        if m := START.match(line):
            self.reset(datetime.fromisoformat(m[1]).timestamp())
            return
        if m := ISO.match(line):
            self.t = datetime.strptime(m[1], "%Y-%m-%dT%H:%M:%S%z").timestamp()
        elif m := REL.match(line):
            base = self.child_t0.get(m[1]) if m[1] else self.router_t0
            if base is not None:
                self.t = base + int(m[2]) * 60 + int(m[3]) + int(m[4]) / 1e3 + int(m[5]) / 1e6

        if "25-warm-cache: checking" in line:
            self.set("warm-up: checking the page cache")
            self.warmup = {"start": self.t}
            self.event("warm-up started")
        elif "25-warm-cache: warming" in line:
            self.set("warm-up: reading the model", progress=0.0)
            self.event("warm-up reading the model")
        elif m := WARMING.match(line):
            self.set("warm-up: reading the model", f"{m[1]}/{m[2]} GiB in {m[4]} s, nvme {m[5]}C", int(m[3]) / 100)
        elif line.startswith("   read ") and " GiB in " in line:
            self.set(self.phase, line.strip(), 1.0)
            self.warmup["read"] = line.strip()
        elif "25-warm-cache: done" in line:
            self.warmup["end"] = self.t
            self.event("warm-up done")
        elif "25-warm-cache: residency after warming" in line:
            self.set("warm-up: checking residency")
        elif "already warm and even" in line:
            self.set("warm-up: skipped, already cached")
            self.warmup["skipped"] = True
        elif "is not fully cached or not NUMA-even" in line:
            self.warn = "warm-up ended with the model partly evicted"
        elif m := CACHED.search(line):
            after = self.phase == "warm-up: checking residency"
            self.cache = (float(m[1]) / 100, [float(s) for s in m[2].replace("%", " ").split()], self.t, after)
        elif "llm-serve: exec:" in line:
            self.router_t0 = self.t
            self.set("router up, model not loaded", "loads on the first request")
            self.event("router up")
        elif m := SPAWN.search(line):
            self.child_t0[m[1]] = self.t
            self.slots = {}
            self.set("loading weights")
            self.event("model loading start")
        elif m := LOAD_ARG.search(line):
            if self.prev_arg in ("-b", "--batch-size"):
                self.batch = int(m[1])
            self.prev_arg = m[1]
        elif "model loaded" in line:
            self.set("idle")
            self.event("model in RAM")
        elif m := N_SLOTS.search(line):
            self.n_slots = int(m[1])
        elif "entering sleeping state" in line:
            if self.phase != "sleeping":
                self.event("sleeping")
            self.slots = {}
            self.set("sleeping", "weights unloaded after idle")
        elif "exiting sleeping state" in line:
            if self.phase != "waking up":
                self.event("waking up")
            self.set("waking up")
        elif m := EXITED.search(line):
            self.slots = {}
            self.set("model instance exited", f"status {m[1]}")
            self.event(f"model instance exited, status {m[1]}")
        elif m := SLOT.search(line):
            self.slot_event(m[1], line)

    def slot_event(self, sid, line):
        if m := EVAL.search(line):
            last = (int(m[3]), float(m[2]) / 1000, float(m[4]), self.t)
            if m[1] == "prompt eval":
                self.last_prompt = last
            else:
                self.last_gen = last
            return
        if "stop processing" in line:
            self.slots.pop(sid, None)
            self.event(f"request finished (slot {sid})")
            if not self.slots:
                self.set("idle")
            return
        if "processing task" in line:
            self.slots[sid] = {"phase": "prompt processing", "since": self.t, "started": self.t, "n": 0,
                               "progress": 0.0, "avg": None, "now": None, "mark": (0, 0.0), "tg": None, "chunks": 0}
            self.set("busy")
            self.event(f"request started (slot {sid})")
            return
        s = self.slots.get(sid)
        if s is None:
            return
        phase = s["phase"]
        if m := PROMPT.search(line):
            n, p, elapsed = int(m[1]), float(m[2]), float(m[3])
            n0, e0 = s["mark"]
            if elapsed > e0:
                s["now"] = (n - n0) / (elapsed - e0)
            s.update(n=n, progress=p, avg=float(m[4]), mark=(n, elapsed), chunks=s["chunks"] + 1)
            phase = "generating" if p >= 1 else "prompt processing"
            if phase == "generating" and s["phase"] != phase:
                self.event(f"prompt processed (slot {sid}), {n} tokens")
        elif m := NGEN.search(line):
            s["tg"] = float(m[2])
            phase = "generating"
        if phase != s["phase"]:
            s["phase"], s["since"] = phase, self.t

    def chunks(self, s):
        """'done/total' prompt chunks of a slot; llama-server logs progress once per --batch-size chunk."""
        total = "?"
        if s["progress"] and self.batch:
            total = max(math.ceil(s["n"] / s["progress"] / self.batch), s["chunks"])
        return f"{min(s['chunks'], total) if total != '?' else s['chunks']}/{total}"


def find_log(model_id):
    """Newest devbox serve log that started the model. Only llm-serve's start line counts: warm-up also names the
    other models' directories when it evicts them."""
    started = re.compile(rf"llm-serve: engine \S+, model \S*/models/{re.escape(model_id)}/")
    found = []
    for path in glob.glob(os.path.join(LOGS_DIR, "*serve*.log")):
        with open(path, errors="replace") as f:
            if started.search(f.read()):
                found.append((os.path.getmtime(path), path))
    return max(found)[1] if found else None


def age(seconds):
    if seconds is None:
        return "?"
    s = int(max(seconds, 0))
    if s < 60:
        return f"{s}s"
    if s < 3600:
        return f"{s // 60}m{s % 60:02d}s"
    if s < 86400:
        return f"{s // 3600}h{s % 3600 // 60:02d}m"
    return f"{s // 86400}d{s % 86400 // 3600:02d}h"


def hms(t):
    return time.strftime("%H:%M:%S", time.localtime(t)) if t else "?"


def phase_entries(lg, now):
    """(name, progress or None, detail, color) per busy slot, or one for the model when no slot is busy."""
    if lg.slots:
        yield f"prompts in inference: {len(lg.slots)} (slot {', '.join(sorted(lg.slots))})" + \
            (f" of {lg.n_slots} slots" if lg.n_slots else ""), None, "", "busy"
        for sid, s in sorted(lg.slots.items()):
            chunks = f"chunks done {lg.chunks(s)} ({lg.batch or '?'} tokens each)"
            progress = s["progress"] if s["phase"] == "prompt processing" else None
            yield f"slot {sid} {s['phase']}", progress, chunks if progress is not None else "", "busy"
            parts = []
            if s["n"]:
                parts.append(f"{s['n']} tok, {s['now']:.1f} tok/s now, {s['avg']:.1f} avg")
            if s["tg"] is not None:
                parts.append(f"{s['tg']:.1f} t/s")
            parts.append(f"for {age(now - s['since'])}, request {age(now - s['started'])}")
            yield "      ", None, ", ".join(parts), "busy"
        return
    color = {"idle": "ok", "sleeping": "ok", "router up, model not loaded": "ok", "model instance exited": "bad"}
    detail = ", ".join(p for p in (lg.detail, f"for {age(now - lg.since) if lg.since else '?'}") if p)
    yield lg.phase, lg.progress, detail, color.get(lg.phase, "busy")


def last_text(lg):
    out = []
    for name, last in (("prompt", lg.last_prompt), ("gen", lg.last_gen)):
        if last:
            n, secs, tps, t = last
            out.append(f"{name} {n} tok in {secs:.1f} s, {tps:.2f} tok/s at {hms(t)}")
    return out


def warmup_text(lg):
    w = lg.warmup
    if not w:
        return "warm-up none since the service start"
    if w.get("skipped"):
        return f"warm-up skipped at {hms(w['start'])}: already cached and NUMA-even"
    span = f"{hms(w['start'])} - {hms(w['end'])}" if "end" in w else f"since {hms(w['start'])}, running"
    return f"warm-up {span}" + (f": {w['read']}" if "read" in w else "")


def history_lines(lg, now, n=6):
    return [f"{what:<44} {age(now - t) + ' ago':>12}  {hms(t)}" for t, what in reversed(lg.history[-n:])]


def status(model_id, log_path):
    path = log_path or find_log(model_id)
    if not path:
        sys.exit(f"no serve log started {model_id} under {LOGS_DIR}; pass --log FILE")
    lg = ServeLog()
    with open(path, errors="replace") as f:
        for line in f:
            lg.feed(line)
    now = time.time()
    print(f"== {model_id}  ({path}, last write {hms(os.path.getmtime(path))}, now {hms(now)})")
    for i, (name, progress, detail, _) in enumerate(phase_entries(lg, now)):
        pct = f" {progress:.0%}" if progress is not None else ""
        if not name.strip():
            print(f"        {name}{detail}")
            continue
        print(f"{'phase:  ' if i == 0 else '        '}{name}{pct}" + (f"  ({detail})" if detail else ""))
    if lg.start:
        print(f"started: {datetime.fromtimestamp(lg.start).astimezone().isoformat(timespec='seconds')}")
    for i, text in enumerate(last_text(lg)):
        print(f"{'last:   ' if i == 0 else '        '}{text}")
    print(warmup_text(lg))
    if lg.warn:
        print(f"WARN:   {lg.warn}")
    for i, text in enumerate(history_lines(lg, now)):
        print(f"{'history: ' if i == 0 else '         '}{text}")


class Model:
    def __init__(self, spec):
        self.id, self.port, self.dir, gpus = spec.split("|")
        self.gpus = [int(g) for g in gpus.split(",") if g]
        self.log_path, self.offset, self.found_at = None, 0, 0.0
        self.log = ServeLog()
        self.res = None  # (fraction, shares, ok, finished at, seconds taken)
        self.res_err = ""
        self.scanning = False
        self.scan_at = float("-inf")

    def update(self):
        now = time.time()
        if now - self.found_at >= LOG_REFIND:
            self.found_at = now
            path = find_log(self.id)
            if path != self.log_path:
                self.log_path, self.offset, self.log = path, 0, ServeLog()
        if not self.log_path:
            return
        if os.path.getsize(self.log_path) < self.offset:
            self.offset, self.log = 0, ServeLog()
        with open(self.log_path, "rb") as f:
            f.seek(self.offset)
            data = f.read()
        end = data.rfind(b"\n") + 1
        self.offset += end
        for line in data[:end].decode(errors="replace").splitlines():
            self.log.feed(line)

    def gguf_files(self):
        files = set()
        for root, _, names in os.walk(self.dir, followlinks=True):
            files.update(os.path.realpath(os.path.join(root, n)) for n in names if n.endswith(".gguf"))
        return sorted(files)

    def scan(self):
        self.scan_at = time.time()
        files = self.gguf_files()
        if not files:
            self.res_err = f"no GGUF files under {self.dir}"
            return
        self.scanning = True
        t0 = time.time()
        r = subprocess.run([sys.executable, "-I", os.path.join(SCRIPTS, "warm_read.py"), "--check", *files],
                           capture_output=True, text=True)
        self.scanning = False
        m = CACHED.search(r.stdout)
        if r.returncode not in (0, 1) or not m:
            self.res_err = f"warm_read.py --check exit {r.returncode}: {(r.stderr or r.stdout).strip()[-200:]}"
            return
        shares = [float(s) for s in m[2].replace("%", " ").split()]
        self.res, self.res_err = (float(m[1]) / 100, shares, r.returncode == 0, time.time(), time.time() - t0), ""


def residency_loop(models, every):
    while True:
        for m in models:
            if time.time() - m.scan_at >= every:
                m.scan()
        time.sleep(1)


def nvme_temp_path():
    for h in glob.glob("/sys/class/hwmon/hwmon*"):
        with open(f"{h}/name") as f:
            if f.read().strip() == "nvme":
                return f"{h}/temp1_input"
    return None


def read_kv(path, keys, field=1):
    out = {}
    with open(path) as f:
        for line in f:
            parts = line.split()
            key = parts[field - 1].rstrip(":")
            if key in keys:
                out[key] = int(parts[field])
    return out


class Host:
    def __init__(self):
        dirs = glob.glob("/sys/devices/system/node/node[0-9]*")
        self.nodes = sorted(int(d.rsplit("node", 1)[1]) for d in dirs)
        self.node_of_cpu = {}
        for n in self.nodes:
            with open(f"/sys/devices/system/node/node{n}/cpulist") as f:
                for cpu in warm_read.cpulist(f.read()):
                    self.node_of_cpu[cpu] = n
        self.nvme = nvme_temp_path()
        self.prev = None

    def cpu_ticks(self):
        ticks = {n: [0, 0] for n in self.nodes}
        with open("/proc/stat") as f:
            for line in f:
                if line.startswith("cpu") and line[3].isdigit():
                    name, *v = line.split()
                    vals = [int(x) for x in v[:8]]
                    t = ticks[self.node_of_cpu[int(name[3:])]]
                    t[0] += sum(vals) - vals[3] - vals[4]
                    t[1] += sum(vals)
        return ticks

    def sample(self):
        now = time.monotonic()
        vm = read_kv("/proc/vmstat", {"pgmajfault", "pgsteal_kswapd", "pgsteal_direct", "pgsteal_khugepaged"})
        cur = {"t": now, "majflt": vm["pgmajfault"], "steal": sum(v for k, v in vm.items() if k.startswith("pgsteal")),
               "cpu": self.cpu_ticks()}
        s = {"mem": read_kv("/proc/meminfo", {"MemTotal", "MemFree", "Buffers", "Cached", "SReclaimable"}), "node_mem": {}, "rates": None,
             "cpu": None, "nvme": warm_read.temp(self.nvme) if self.nvme else None}
        for n in self.nodes:
            s["node_mem"][n] = read_kv(f"/sys/devices/system/node/node{n}/meminfo", {"MemFree", "FilePages"}, 3)
        if self.prev:
            dt = now - self.prev["t"]
            s["rates"] = ((cur["majflt"] - self.prev["majflt"]) / dt, (cur["steal"] - self.prev["steal"]) / dt)
            s["cpu"] = {n: 100 * (cur["cpu"][n][0] - self.prev["cpu"][n][0]) /
                        max(cur["cpu"][n][1] - self.prev["cpu"][n][1], 1) for n in self.nodes}
        self.prev = cur
        return s


GPU_FIELDS = "index,utilization.gpu,memory.used,memory.total,power.draw,power.limit,clocks.sm,temperature.gpu"


def gpu_rows():
    try:
        r = subprocess.run(["nvidia-smi", f"--query-gpu={GPU_FIELDS}", "--format=csv,noheader,nounits"],
                           capture_output=True, text=True, timeout=10)
    except (FileNotFoundError, subprocess.TimeoutExpired) as e:
        return None, f"nvidia-smi: {e}"
    if r.returncode:
        return None, f"nvidia-smi exit {r.returncode}: {r.stderr.strip()[-200:]}"
    return [[c.strip() for c in line.split(",")] for line in r.stdout.splitlines() if line.strip()], ""


def num(text, fmt):
    try:
        return format(float(text), fmt)
    except ValueError:
        return text


def bar(frac, width=20):
    k = round(max(0.0, min(frac, 1.0)) * width)
    return "█" * k + "░" * (width - k)


GIB_KB = 1 << 20
FAULTS_HOT = 1000  # per second; a warm model takes almost none


def host_lines(h, gpus, gpu_err, owners):
    mem = h["mem"]
    nvme = f"nvme {h['nvme']}C" if h["nvme"] is not None else "nvme ?"
    # Host monitors report "used" like free(1): page cache does not count, although the mmapped weights live there.
    cache = mem["Buffers"] + mem["Cached"] + mem["SReclaimable"]
    used = mem["MemTotal"] - mem["MemFree"] - cache
    lines = [(f"RAM {mem['MemTotal'] / GIB_KB:.0f} GiB: used by programs {used / GIB_KB:.0f}, "
              f"page cache {cache / GIB_KB:.0f} (files incl. mmapped model weights, evictable), "
              f"free {mem['MemFree'] / GIB_KB:.1f}   {nvme}", None)]
    faults, freed = h["rates"] or (None, None)
    lines.append((f"pages read from disk (major faults) {'-' if faults is None else f'{faults:,.0f}'}/s: "
                  "a mmapped page (model weights) was not in RAM", "bad" if faults and faults >= FAULTS_HOT else None))
    lines.append((f"page cache freed (pgsteal) {'-' if freed is None else f'{freed:,.0f}'} pages/s: "
                  "the kernel evicts cached files, model weights too, to make room", "bad" if freed and freed >= FAULTS_HOT else None))
    nodes = sorted(h["node_mem"])
    lines.append(("node        " + "".join(f"{n:>7}" for n in nodes), "dim"))
    lines.append(("free GiB    " + "".join(f"{h['node_mem'][n]['MemFree'] / GIB_KB:7.1f}" for n in nodes), None))
    lines.append(("file GiB    " + "".join(f"{h['node_mem'][n]['FilePages'] / GIB_KB:7.1f}" for n in nodes), None))
    cpu = "".join(f"{h['cpu'][n]:7.0f}" for n in nodes) if h["cpu"] else "".join(f"{'-':>7}" for _ in nodes)
    lines.append(("cpu busy %  " + cpu, None))
    if gpus is None:
        lines.append((gpu_err, "bad"))
    for g in gpus or []:
        idx, util, used, total, power, limit, clock, temp = g
        lines.append((f"GPU{idx}  {num(util, '>3.0f')}%  mem {num(used, '>6.0f')}/{num(total, '.0f')} MiB  "
                      f"{num(power, '>4.0f')}/{num(limit, '.0f')} W  {num(clock, '>4.0f')} MHz  {temp}C  "
                      f"{owners.get(int(idx), '')}", None))
    return lines


def model_lines(m, now):
    if not m.log_path:
        return [(f"no serve log started {m.id} in {LOGS_DIR}", "dim")]
    lg = m.log
    lines = []
    for name, progress, detail, color in phase_entries(lg, now):
        pb = f"  {bar(progress)} {progress:4.0%}" if progress is not None else ""
        lines.append((f"{name}{pb}  {detail}", color))
    lines.append((warmup_text(lg), None))
    lines.append(cache_line(m, now))
    if lg.warn:
        lines.append((f"WARN  {lg.warn}", "bad"))
    last = last_text(lg)
    lines.append(("last  " + "   ".join(last) if last else "last  no finished request since start", None))
    for i, text in enumerate(history_lines(lg, now)):
        lines.append((("history " if i == 0 else " " * 8) + text, "dim" if i else None))
    lines.append((f"log   {m.log_path}, last write {age(now - os.path.getmtime(m.log_path))} ago", "dim"))
    return lines


def cache_line(m, now):
    """How much of the model is in RAM: the last scan, else warm_read's last check in the log. Anything below
    warm_read.MIN_CACHED is red: the missing part is read from the NVMe on every prompt chunk."""
    scanning = f"scanning for {age(now - m.scan_at)}" if m.scanning else ""
    if m.res:
        frac, shares, ok, at, took = m.res
        source = f"scanned {age(now - at)} ago in {took:.0f} s" + (f", {scanning}" if scanning else "")
    elif m.log.cache:
        frac, shares, at, after = m.log.cache
        ok = None
        source = f"from the warm-up log at {hms(at)}{'' if after else ', before reading'}; " + \
            (scanning or m.res_err or "not scanned yet")
    else:
        return (f"cache {scanning or m.res_err or 'not scanned yet'}", "bad" if m.res_err else "dim")
    if frac < warm_read.MIN_CACHED:
        verdict, color = f"EVICTED: {1 - frac:.0%} of the model is read from disk", "bad"
    elif ok is False:
        verdict, color = "uneven over NUMA nodes", "busy"
    else:
        verdict, color = "in RAM", "ok"
    return (f"cache {frac:.1%} in RAM  {verdict}  ({source})  per node " +
            " ".join(f"{s:.0f}" for s in shares) + " %", color)


def frame(models, host, gpus, gpu_err, width, interval):
    w = max(60, min(width - 1, 140))
    out = []

    def box(title, lines):
        top = f"┌─ {title} "
        out.append(((top + "─" * w)[:w - 1] + "┐", "title"))
        for text, color in lines:
            out.append(("│ " + text[:w - 4].ljust(w - 4) + " │", color))
        out.append(("└" + "─" * (w - 2) + "┘", None))

    now = time.time()
    owners = {}
    for m in models:
        for g in m.gpus:
            owners[g] = (owners[g] + ", " if g in owners else "") + m.id
    out.append((f"llm-panel  {hms(now)}  refresh {interval:g} s  q quits", "title"))
    for m in models:
        box(f"{m.id}  :{m.port}  GPU {','.join(map(str, m.gpus)) or '-'}", model_lines(m, now))
    box("host", host_lines(host, gpus, gpu_err, owners))
    return out


def collect(models, host):
    for m in models:
        m.update()
    gpus, err = gpu_rows()
    return host.sample(), gpus, err


def print_frame(models, sample, interval):
    width = shutil.get_terminal_size((120, 50)).columns
    print("\n".join(text for text, _ in frame(models, *sample, width, interval)))


def run_curses(models, host, interval):
    """Runs until q or Ctrl-C, then leaves the last frame on the terminal as --once would print it."""
    last = []

    def loop(scr):
        curses.curs_set(0)
        attrs = {None: curses.A_NORMAL, "title": curses.A_BOLD, "dim": curses.A_DIM}
        if curses.has_colors():
            curses.use_default_colors()
            for i, (name, fg) in enumerate((("ok", curses.COLOR_GREEN), ("busy", curses.COLOR_YELLOW),
                                            ("bad", curses.COLOR_RED), ("title", curses.COLOR_CYAN)), 1):
                curses.init_pair(i, fg, -1)
                attrs[name] = curses.color_pair(i) | (curses.A_BOLD if name in ("bad", "title") else 0)
        scr.timeout(int(interval * 1000))
        next_sample = 0.0
        while True:
            if time.monotonic() >= next_sample:
                next_sample = time.monotonic() + interval
                last[:] = [collect(models, host)]
            rows, cols = scr.getmaxyx()
            scr.erase()
            for y, (text, color) in enumerate(frame(models, *last[0], cols, interval)[:rows]):
                scr.addnstr(y, 0, text, cols - 1, attrs.get(color, curses.A_NORMAL))
            scr.refresh()
            scr.timeout(max(int((next_sample - time.monotonic()) * 1000), 1))
            if scr.getch() in (ord("q"), ord("Q")):
                return

    try:
        curses.wrapper(loop)
    except KeyboardInterrupt:
        pass
    if last:
        print_frame(models, last[0], interval)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[1], usage=__doc__.split("\n\n")[0])
    ap.add_argument("--status", metavar="MODEL_ID")
    ap.add_argument("--log")
    ap.add_argument("--model", action="append", default=[])
    ap.add_argument("--once", action="store_true", help="print one frame to stdout (no residency scan)")
    ap.add_argument("--interval", type=float, default=2.0)
    ap.add_argument("--residency-every", type=float, default=60.0, help="0 disables the residency scan")
    a = ap.parse_args()
    if a.status:
        status(a.status, a.log)
        return
    if not a.model:
        ap.error("no --model given (llm-panel.sh passes them)")
    locale.setlocale(locale.LC_ALL, "")
    models = [Model(s) for s in a.model]
    host = Host()
    if a.once:
        host.sample()
        time.sleep(1)
        print_frame(models, collect(models, host), a.interval)
        return
    if a.residency_every > 0:
        threading.Thread(target=residency_loop, args=(models, a.residency_every), daemon=True).start()
    run_curses(models, host, a.interval)


if __name__ == "__main__":
    main()
