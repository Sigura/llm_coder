#!/usr/bin/env bash
set -euo pipefail

access() (
    OPTIND=1
    for f in "$@"; do
        [[ $f == - || -r $f ]] || { echo "cannot read $f" >&2; exit 1; }
    done
    export LC_ALL=C
    for f in "$@"; do
        case $f in
            -) cat ;;
            *.gz) zcat -- "$f" ;;
            *) cat -- "$f" ;;
        esac
    done | awk '
        match($0, /^[^ ]+ [^ ]+ [^ ]+ \[[^]]+\] "[A-Z]+ [^ "]+ [^ "]+" [0-9][0-9][0-9] ([0-9]+|-) "[^"]*" "[^"]*"$/) {
            split($0, q, "\"")
            split(q[2], req, " ")
            path = req[2]; sub(/\?.*/, "", path)
            n = split(q[3], ss, " ")
            code = ss[1]; size = (ss[2] == "-") ? 0 : ss[2]
            ok++; st[code]++; ipb[$1] += size; pc[path]++
            next
        }
        { bad++ }
        END {
            print "requests: " ok + 0
            print "malformed: " bad + 0
            for (c in st) print "S", c, st[c]
            for (i in ipb) print "I", i, ipb[i]
            for (p in pc) print "P", p, pc[p]
        }' > "${TMPDIR:-/tmp}/al.$$"
    head -2 "${TMPDIR:-/tmp}/al.$$"
    echo "status:"
    awk '$1 == "S"' "${TMPDIR:-/tmp}/al.$$" | sort -k2,2n | awk '{print "  " $2, $3}'
    echo "top_ips:"
    awk '$1 == "I"' "${TMPDIR:-/tmp}/al.$$" | sort -k3,3nr -k2,2 | head -3 | awk '{print "  " $2, $3}'
    echo "top_paths:"
    awk '$1 == "P"' "${TMPDIR:-/tmp}/al.$$" | sort -k3,3nr -k2,2 | head -3 | awk '{print "  " $2, $3}'
    rm -f "${TMPDIR:-/tmp}/al.$$"
)

words() (
    OPTIND=1
    usage() { echo "usage: $0 [-n N] [-i]" >&2; exit 2; }
    n=10 ci=0
    while getopts ":n:i" opt; do
        case $opt in
            n) n=$OPTARG ;;
            i) ci=1 ;;
            *) usage ;;
        esac
    done
    [[ $n =~ ^[0-9]+$ ]] && (( n > 0 )) || usage
    export LC_ALL=C
    tr -c "A-Za-z0-9'" '\n' | sed "s/^'*//; s/'*\$//" | grep -v '^$' \
        | { if (( ci )); then tr 'A-Z' 'a-z'; else cat; fi; } \
        | sort | uniq -c | awk '{print $1, $2}' | sort -k1,1nr -k2,2 | head -n "$n" || true
)

csv() (
    OPTIND=1
    delim=, stats=0
    while getopts ":d:s" o; do
        case $o in
            d) delim=$OPTARG ;;
            s) stats=1 ;;
            *) echo "usage: $0 [-d DELIM] [-s] COLUMN [FILE]" >&2; exit 2 ;;
        esac
    done
    shift $((OPTIND - 1))
    col=${1:?usage}
    file=${2:--}
    out=$(cat -- "$file" | awk -v D="$delim" -v COL="$col" -v STATS="$stats" '
    BEGIN { RS = "\001"; }
    {
        s = $0; n = length(s); i = 1; row = 0; nf = 0; f = ""; inq = 0; started = 0
        while (i <= n) {
            c = substr(s, i, 1)
            if (inq) {
                if (c == "\"") {
                    if (substr(s, i + 1, 1) == "\"") { f = f "\""; i += 2; continue }
                    inq = 0; i++; continue
                }
                if (c == "\r" && substr(s, i + 1, 1) == "\n") { f = f "\\n"; i += 2; continue }
                if (c == "\n") { f = f "\\n"; i++; continue }
                f = f c; i++; continue
            }
            if (c == "\"") { inq = 1; started = 1; i++; continue }
            if (c == D) { fld[++nf] = f; f = ""; started = 1; i++; continue }
            if (c == "\r" && substr(s, i + 1, 1) == "\n") { i++; continue }
            if (c == "\n") { fld[++nf] = f; endrow(); f = ""; nf = 0; started = 0; i++; continue }
            f = f c; started = 1; i++
        }
        if (inq) exit 4
        if (started || nf > 0) { fld[++nf] = f; endrow() }
        finish()
    }
    function endrow(   k) {
        row++
        if (row == 1) {
            idx = 0
            if (COL ~ /^#[0-9]+$/) idx = substr(COL, 2) + 0
            else for (k = 1; k <= nf; k++) if (fld[k] == COL) { idx = k; break }
            if (idx < 1 || idx > nf) { bad = 1; exit 3 }
            return
        }
        v = (idx <= nf) ? fld[idx] : ""
        for (k = 1; k <= nf; k++) delete fld[k]
        if (!STATS) { vals[++nv] = v; return }
        if (v ~ /^[-+]?([0-9]+([.][0-9]*)?|[.][0-9]+)$/) {
            x = v + 0; cnt++; sum += x
            if (cnt == 1 || x < mn) mn = x
            if (cnt == 1 || x > mx) mx = x
        }
    }
    function finish(   k) {
        if (!STATS) { for (k = 1; k <= nv; k++) print vals[k]; return }
        if (cnt == 0) print "count=0"
        else printf "count=%d sum=%g min=%g max=%g\n", cnt, sum, mn, mx
    }
    ') || rc=$?
    case ${rc:-0} in
        0) printf '%s\n' "$out" ;;
        3) echo "unknown column: $col" >&2; exit 3 ;;
        4) echo "unterminated quote" >&2; exit 4 ;;
        *) exit "$rc" ;;
    esac
)

paths() {
    local f
    for f in "$@"; do
        case $f in
            *.gz) zcat -- "$f" ;;
            *) cat -- "$f" ;;
        esac
    done | LC_ALL=C awk '
        /^[^ ]+ [^ ]+ [^ ]+ \[[^]]+\] "[A-Z]+ [^ "]+ [^ "]+" [0-9][0-9][0-9] ([0-9]+|-) "[^"]*" "[^"]*"$/ {
            split($0, q, "\""); split(q[2], req, " "); p = req[2]; sub(/\?.*/, "", p); print p
        }'
}

report() (
    OPTIND=1
    n=3
    while getopts ":n:" o; do
        case $o in
            n) n=$OPTARG ;;
            *) echo "usage: solution.sh report [-n N] MANIFEST" >&2; exit 2 ;;
        esac
    done
    shift $((OPTIND - 1))
    [[ $n =~ ^[0-9]+$ ]] && (( n > 0 )) || { echo "bad N: $n" >&2; exit 2; }
    (( $# == 1 )) || { echo "usage: solution.sh report [-n N] MANIFEST" >&2; exit 2; }
    [[ -r $1 ]] || { echo "cannot read $1" >&2; exit 1; }
    logs=$(csv log "$1") || exit $?
    en=$(csv enabled "$1" 2>/dev/null) || en=$(sed 's/.*/yes/' <<<"$logs")
    used=()
    while IFS=$'\t' read -r l e; do
        [[ -n $l && $e == yes ]] && used+=("$l")
    done < <(paste <(printf '%s\n' "$logs") <(printf '%s\n' "$en"))
    for f in ${used[@]+"${used[@]}"}; do
        [[ -r $f ]] || { echo "cannot read $f" >&2; exit 1; }
    done
    if (( ${#used[@]} )); then
        access "${used[@]}"
        echo "top_words:"
        paths "${used[@]}" | words -i -n "$n" | sed 's/^/  /'
    else
        access - </dev/null
        echo "top_words:"
    fi
)

cmd=${1:-}
case $cmd in
    access | words | csv | report) shift; "$cmd" "$@" ;;
    *) echo "usage: solution.sh access|words|csv|report ARGS..." >&2; exit 2 ;;
esac
