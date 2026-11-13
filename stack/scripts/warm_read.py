#!/usr/bin/env python3
"""Usage: warm_read.py <file>...

Reads files into the page cache with one reader process per NUMA node; reader n is pinned to node n and reads
pieces n, n+N, n+2N, ... (PIECE bytes each), so pages are interleaved finely across nodes (first-touch placement)
while the disk sees a single sequential region at queue depth ~N. Readers pause while the NVMe is hot.
"""
import glob
import os
import sys
import time

PIECE = 256 << 10
TEMP_HI = int(os.environ.get("TEMP_HI", 65))
TEMP_LO = int(os.environ.get("TEMP_LO", 55))


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
                    while temp(tpath) > TEMP_LO:
                        time.sleep(5)
            os.pread(fd, PIECE, off)
            off += nodes * PIECE
            since_check += PIECE
        os.close(fd)


def main():
    files = sys.argv[1:]
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
