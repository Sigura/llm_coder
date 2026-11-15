#!/usr/bin/env python3
"""Usage: warm_read.py <file>...   |   warm_read.py --check <file>...

Reads files into the page cache with one reader process per NUMA node; reader n is pinned to node n and reads
pieces n, n+N, n+2N, ... (PIECE bytes each), so pages are interleaved finely across nodes (first-touch placement)
while the disk sees a single sequential region at queue depth ~N. Readers pause while the NVMe is hot.

--check reads nothing from disk: it samples pages, prints how much is cached and how the cached pages spread over
the NUMA nodes, and exits 0 only if nearly everything is cached and every node holds a fair share.
"""
import ctypes
import glob
import os
import sys
import time

PIECE = 256 << 10
PAGE = os.sysconf("SC_PAGE_SIZE")
SAMPLE_EVERY = 509  # pages; prime, so the samples don't line up with tensor or piece boundaries
MIN_CACHED = 0.98
MIN_NODE_SHARE = 0.6  # of an even 1/N share
TEMP_HI = int(os.environ.get("TEMP_HI", 65))
TEMP_LO = int(os.environ.get("TEMP_LO", 55))
COOL_PLATEAU = 120


def cpulist(text):
    cpus = set()
    for part in text.strip().split(","):
        a, _, b = part.partition("-")
        cpus.update(range(int(a), int(b or a) + 1))
    return cpus


def nvme_temp_path():
    for h in glob.glob("/sys/class/hwmon/hwmon*"):
        with open(f"{h}/name") as f:
            if f.read().strip() == "nvme":
                return f"{h}/temp1_input"
    sys.exit("no nvme hwmon found")


def temp(path):
    with open(path) as f:
        return int(f.read()) // 1000


def cool_wait(tpath):
    # The drive's idle temperature can sit above TEMP_LO (warm room, after a reboot), so also resume once it has
    # stopped falling for COOL_PLATEAU seconds instead of waiting forever.
    lowest, since = temp(tpath), time.time()
    while (t := temp(tpath)) > TEMP_LO and time.time() - since < COOL_PLATEAU:
        if t < lowest:
            lowest, since = t, time.time()
        time.sleep(5)


def reader(node, nodes, cpus, files, tpath):
    os.sched_setaffinity(0, cpus)
    for name in files:
        fd = os.open(name, os.O_RDONLY)
        size = os.fstat(fd).st_size
        off = node * PIECE
        since_check = 0
        while off < size:
            if since_check >= 1 << 30:
                since_check = 0
                if temp(tpath) >= TEMP_HI:
                    cool_wait(tpath)
            os.pread(fd, PIECE, off)
            off += nodes * PIECE
            since_check += PIECE
        os.close(fd)


def check(files, n_nodes):
    libc = ctypes.CDLL(None, use_errno=True)
    libc.mmap.restype = ctypes.c_void_p
    libc.mmap.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_long]
    libc.munmap.argtypes = [ctypes.c_void_p, ctypes.c_size_t]
    libc.mincore.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_char_p]
    sampled = cached = 0
    per_node = [0] * n_nodes
    for name in files:
        fd = os.open(name, os.O_RDONLY)
        size = os.fstat(fd).st_size
        addr = libc.mmap(None, size, 1, 1, fd, 0)  # PROT_READ, MAP_SHARED
        os.close(fd)
        if addr in (None, ctypes.c_void_p(-1).value):
            sys.exit(f"mmap failed for {name}: errno {ctypes.get_errno()}")
        n_pages = (size + PAGE - 1) // PAGE
        vec = ctypes.create_string_buffer(n_pages)
        if libc.mincore(ctypes.c_void_p(addr), size, vec):
            sys.exit(f"mincore failed for {name}: errno {ctypes.get_errno()}")
        raw = vec.raw
        resident = [p for p in range(0, n_pages, SAMPLE_EVERY) if raw[p] & 1]
        sampled += len(range(0, n_pages, SAMPLE_EVERY))
        cached += len(resident)
        # Only cached pages are touched (a minor fault maps the cached page, no disk read); numa_maps then counts the
        # mapped pages per node. move_pages would be direct but needs CAP_SYS_NICE in a container.
        for p in resident:
            ctypes.c_char.from_address(addr + p * PAGE).value
        with open("/proc/self/numa_maps") as f:
            line = next(l for l in f if int(l.split()[0], 16) == addr)
        for field in line.split():
            if field[0] == "N" and "=" in field:
                node, count = field[1:].split("=")
                per_node[int(node)] += int(count)
        libc.munmap(ctypes.c_void_p(addr), size)
    frac = cached / sampled if sampled else 0
    total = sum(per_node) or 1
    shares = [c / total for c in per_node]
    print(f"   cached {frac:.1%} of sampled pages; per NUMA node: " + " ".join(f"{s:.1%}" for s in shares))
    return frac >= MIN_CACHED and min(shares) >= MIN_NODE_SHARE / n_nodes


def main():
    files = sys.argv[1:]
    if files and files[0] == "--check":
        n_nodes = len(glob.glob("/sys/devices/system/node/node[0-9]*"))
        sys.exit(0 if check(files[1:], n_nodes) else 1)
    tpath = nvme_temp_path()
    node_dirs = sorted(glob.glob("/sys/devices/system/node/node[0-9]*"), key=lambda p: int(p.rsplit("node", 1)[1]))
    nodes = [cpulist(open(f"{d}/cpulist").read()) for d in node_dirs]
    t0 = time.time()
    pids = []
    for n, cpus in enumerate(nodes):
        pid = os.fork()
        if pid == 0:
            reader(n, len(nodes), cpus, files, tpath)
            os._exit(0)
        pids.append(pid)
    for pid in pids:
        _, status = os.waitpid(pid, 0)
        if status:
            sys.exit(f"reader {pid} failed: {status}")
    total = sum(os.path.getsize(f) for f in files)
    print(f"   read {total >> 30} GiB in {time.time() - t0:.0f} s with {len(nodes)} node-pinned readers, nvme {temp(tpath)}C")


if __name__ == "__main__":
    main()
