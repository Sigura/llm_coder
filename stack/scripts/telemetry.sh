#!/usr/bin/env bash
# Usage: telemetry.sh <log file>
# Appends one line per second (NVMe temp, max CPU Tctl, CPU busy %, disk read/write MB/s, GPU power, util and max
# temp, load, free/cached GB) and fsyncs it,
# so after a host hang the tail shows the last state.
set -euo pipefail
log=$1
hwmon=""
for h in /sys/class/hwmon/hwmon*; do [[ $(cat "$h/name") == nvme ]] && { hwmon=$h; break; }; done
[[ -n $hwmon ]] || { echo "no nvme hwmon found" >&2; exit 1; }
cpu_temps=()
for h in /sys/class/hwmon/hwmon*; do [[ $(cat "$h/name") == k10temp ]] && cpu_temps+=("$h/temp1_input"); done
echo "time nvme_C cpu_C cpu_busy% rd_MBs wr_MBs gpu_W gpu_util gpu_C load1 free_GB cached_GB" >>"$log"
read -r r0 w0 < <(awk '$3=="nvme0n1"{print $6, $10}' /proc/diskstats)
read -r b0 t0 < <(awk '/^cpu /{print $2+$3+$4+$7+$8, $2+$3+$4+$5+$6+$7+$8}' /proc/stat)
while true; do
    sleep 1
    read -r r1 w1 < <(awk '$3=="nvme0n1"{print $6, $10}' /proc/diskstats)
    read -r b1 t1 < <(awk '/^cpu /{print $2+$3+$4+$7+$8, $2+$3+$4+$5+$6+$7+$8}' /proc/stat)
    cpu_c=$(cat "${cpu_temps[@]}" | sort -n | tail -1)
    gpu=$(nvidia-smi --query-gpu=power.draw,utilization.gpu,temperature.gpu --format=csv,noheader,nounits |
        awk -F', ' '{p += $1; u = u (u ? "/" : "") $2; if ($3 > t) t = $3} END {printf "%.0f %s %d", p, u, t}')
    mem=$(awk '/^MemFree:/{f=$2} /^Cached:/{c=$2} END {printf "%.0f %.0f", f/1048576, c/1048576}' /proc/meminfo)
    echo "$(date +%T) $(($(cat "$hwmon/temp1_input") / 1000)) $((cpu_c / 1000)) $((100 * (b1 - b0) / (t1 - t0))) $(((r1 - r0) / 2048)) $(((w1 - w0) / 2048)) $gpu $(cut -d' ' -f1 /proc/loadavg) $mem" >>"$log"
    sync "$log"
    r0=$r1 w0=$w1 b0=$b1 t0=$t1
done
