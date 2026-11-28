#!/usr/bin/env bash
OCTET='(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]|[0-9])'
ADDR_RE="^$OCTET\.$OCTET\.$OCTET\.$OCTET$"
PREFIX_RE='^(3[0-2]|[12][0-9]|[0-9])$'
MAX=4294967295

die() { echo "$*" >&2; exit 2; }

to_int() { # ADDR -> echo int; fails if invalid
    [[ $1 =~ $ADDR_RE ]] || return 1
    local IFS=.
    set -- $1
    echo $((($1 << 24) | ($2 << 16) | ($3 << 8) | $4))
}

to_addr() { echo "$((($1 >> 24) & 255)).$((($1 >> 16) & 255)).$((($1 >> 8) & 255)).$(($1 & 255))"; }

# SPEC -> "LO HI"; fails if invalid
spec_range() {
    local s=$1 a b p lo hi size
    if [[ $s == */* ]]; then
        a=${s%%/*} p=${s#*/}
        [[ $p =~ $PREFIX_RE ]] || return 1
        a=$(to_int "$a") || return 1
        size=$((1 << (32 - p)))
        lo=$((a / size * size)); hi=$((lo + size - 1))
    elif [[ $s == *-* ]]; then
        lo=$(to_int "${s%%-*}") || return 1
        hi=$(to_int "${s#*-}") || return 1
        ((lo <= hi)) || return 1
    else
        lo=$(to_int "$s") || return 1
        hi=$lo
    fi
    echo "$lo $hi"
}

fmt_range() { if (($1 == $2)); then to_addr "$1"; else echo "$(to_addr "$1")-$(to_addr "$2")"; fi; }

merge_ranges() { # stdin "LO HI" lines -> merged "LO HI" lines
    sort -n -k1,1 -k2,2 | {
        local lo hi clo= chi=
        while read -r lo hi; do
            if [[ -n $clo ]] && ((lo <= chi + 1)); then
                ((hi > chi)) && chi=$hi
            else
                [[ -n $clo ]] && echo "$clo $chi"
                clo=$lo chi=$hi
            fi
        done
        [[ -n $clo ]] && echo "$clo $chi"
    }
    return 0
}

cidrs() { # LO HI -> CIDR lines
    local lo=$1 hi=$2 size p
    while ((lo <= hi)); do
        size=1 p=32
        while ((p > 0 && lo % (size * 2) == 0 && lo + size * 2 - 1 <= hi)); do size=$((size * 2)); p=$((p - 1)); done
        echo "$(to_addr "$lo")/$p"
        lo=$((lo + size))
    done
}

cmd_cidr() {
    [[ $# -eq 1 && $1 == */* ]] || die "usage: cidr ADDR/PREFIX"
    local r lo hi p=${1#*/}
    r=$(spec_range "$1") || die "cidr: invalid $1"
    read -r lo hi <<<"$r"
    echo "network $(to_addr "$lo")/$p"
    echo "broadcast $(to_addr "$hi")"
    if ((p == 32)); then
        echo "first $(to_addr "$lo")"; echo "last $(to_addr "$hi")"; echo "hosts 1"
    elif ((p == 31)); then
        echo "first $(to_addr "$lo")"; echo "last $(to_addr "$hi")"; echo "hosts 2"
    else
        echo "first $(to_addr $((lo + 1)))"; echo "last $(to_addr $((hi - 1)))"; echo "hosts $((hi - lo - 1))"
    fi
}

trim() { local s=$1; s=${s#"${s%%[![:blank:]]*}"}; s=${s%"${s##*[![:blank:]]}"}; printf '%s' "$s"; }

cmd_merge() {
    local line n=0 ranges=() r
    while IFS= read -r line || [[ -n $line ]]; do
        n=$((n + 1))
        line=$(trim "$line")
        [[ -z $line || $line == '#'* ]] && continue
        r=$(spec_range "$line") || { echo "line $n: invalid" >&2; exit 1; }
        ranges+=("$r")
    done
    ((${#ranges[@]})) || return 0
    printf '%s\n' "${ranges[@]}" | merge_ranges | while read -r lo hi; do fmt_range "$lo" "$hi"; done
}

cmd_tocidr() {
    [[ $# -eq 1 ]] || die "usage: tocidr SPEC"
    local r
    r=$(spec_range "$1") || die "tocidr: invalid $1"
    cidrs $r
}

cmd_acl() {
    [[ $# -ge 1 && -f $1 ]] || die "usage: acl RULES [ADDR...]"
    local rules=$1 line n=0 act spec r lo hi acts=() los=() his=() nums=() a i x
    shift
    while IFS= read -r line || [[ -n $line ]]; do
        n=$((n + 1))
        line=$(trim "$line")
        [[ -z $line || $line == '#'* ]] && continue
        if [[ $line =~ ^(allow|deny)[[:blank:]]+([^[:blank:]]+)$ ]]; then
            act=${BASH_REMATCH[1]} spec=${BASH_REMATCH[2]}
            if [[ $spec == any ]]; then r="0 $MAX"; else r=$(spec_range "$spec") || r=; fi
        else
            r=
        fi
        [[ -n $r ]] || { echo "$rules:$n: invalid rule" >&2; exit 1; }
        read -r lo hi <<<"$r"
        acts+=("$act") los+=("$lo") his+=("$hi") nums+=("$n")
    done <"$rules"
    decide() { # INT -> "allow N" | "deny N" | "deny default"
        local i
        for i in "${!acts[@]}"; do
            if ((los[i] <= $1 && $1 <= his[i])); then echo "${acts[i]} ${nums[i]}"; return; fi
        done
        echo "deny default"
    }
    if (($#)); then
        for a in "$@"; do to_int "$a" >/dev/null || die "acl: invalid address $a"; done
        for a in "$@"; do echo "$a $(decide "$(to_int "$a")")"; done
        return
    fi
    local points
    points=$( { echo 0; for i in "${!acts[@]}"; do echo "${los[i]}"; echo $((his[i] + 1)); done; } | sort -nu)
    local starts=() ends=()
    mapfile -t starts <<<"$points"
    for ((i = 0; i < ${#starts[@]}; i++)); do
        x=${starts[i]}
        ((x > MAX)) && continue
        hi=$MAX; ((i + 1 < ${#starts[@]})) && hi=$((starts[i + 1] - 1))
        [[ $(decide "$x") == allow* ]] && echo "$x $hi"
    done | merge_ranges | while read -r lo hi; do cidrs "$lo" "$hi"; done
}

cmd=${1:-}
[[ $# -gt 0 ]] && shift
case $cmd in
cidr) cmd_cidr "$@" ;;
merge) cmd_merge "$@" ;;
tocidr) cmd_tocidr "$@" ;;
acl) cmd_acl "$@" ;;
*) die "usage: solution.sh cidr|merge|tocidr|acl ARGS..." ;;
esac
