#!/usr/bin/env bash
export LC_ALL=C

die() { echo "$*" >&2; exit 2; }

human() {
    [[ $# -eq 1 && $1 =~ ^[0-9]{1,16}$ ]] || die "usage: human BYTES"
    local b=$((10#$1)) units=(K M G T) u=1 i=-1 tenths n
    if ((b < 1024)); then echo "${b}B"; return; fi
    while ((i < 3 && b >= u * 1024)); do u=$((u * 1024)); i=$((i + 1)); done
    tenths=$(((b * 10 + u / 2) / u))
    if ((tenths < 100)); then
        echo "$((tenths / 10)).$((tenths % 10))${units[i]}"
        return
    fi
    n=$(((b + u / 2) / u))
    if ((n == 1024 && i < 3)); then
        u=$((u * 1024)); i=$((i + 1))
        tenths=$(((b * 10 + u / 2) / u))
        echo "$((tenths / 10)).$((tenths % 10))${units[i]}"
        return
    fi
    echo "${n}${units[i]}"
}

dupes() {
    [[ $# -eq 1 && -d $1 ]] || die "usage: dupes DIR"
    local dir=$1
    (cd "$dir" && find . -type f -size +0 -printf '%s\t%P\0' |
        while IFS=$'\t' read -r -d '' size path; do
            printf '%s\t%s\t%s\n' "$size" "$(sha256sum <"$path" | cut -d' ' -f1)" "$path"
        done) |
        sort -t $'\t' -k2,2 -k3,3 |
        awk -F'\t' '
            { key = $2; if (key != prev) { flush(); n = 0 } prev = key; n++; sz[n] = $1; p[n] = $3 }
            function flush(   i) { if (n >= 2) { for (i = 1; i <= n; i++) print sz[i] "\t" p[1] "\t" p[i] } }
            END { flush() }' |
        sort -t $'\t' -k1,1nr -k2,2 -k3,3 |
        awk -F'\t' '{ if (NR > 1 && $2 != g) print ""; g = $2; print $1 " " $3 }'
}

tree_cmd() {
    local depth=0
    if [[ ${1:-} == -L ]]; then
        [[ ${2:-} =~ ^[1-9][0-9]*$ ]] || die "tree: bad depth"
        depth=$2; shift 2
    fi
    [[ $# -eq 1 && -d $1 ]] || die "usage: tree [-L DEPTH] DIR"
    ndirs=0 nfiles=0
    echo "$1"
    walk "$1" "" 1 "$depth"
    echo
    echo "$ndirs directories, $nfiles files"
}

walk() {
    local dir=$1 prefix=$2 level=$3 depth=$4 names=() name i last branch
    while IFS= read -r -d '' name; do names+=("$name"); done < <(
        find "$dir" -mindepth 1 -maxdepth 1 ! -name '.*' -printf '%f\0' | sort -z)
    for ((i = 0; i < ${#names[@]}; i++)); do
        name=${names[i]}
        last=$((i == ${#names[@]} - 1))
        branch='├── '; ((last)) && branch='└── '
        if [[ -L $dir/$name ]]; then
            echo "$prefix$branch$name -> $(readlink "$dir/$name")"
            nfiles=$((nfiles + 1))
        elif [[ -d $dir/$name ]]; then
            echo "$prefix$branch$name/"
            ndirs=$((ndirs + 1))
            if ((depth == 0 || level < depth)); then
                if ((last)); then walk "$dir/$name" "$prefix    " $((level + 1)) "$depth"
                else walk "$dir/$name" "$prefix│   " $((level + 1)) "$depth"; fi
            fi
        else
            echo "$prefix$branch$name"
            nfiles=$((nfiles + 1))
        fi
    done
}

report() {
    local out total=0 count size paths
    tree_cmd "$@"
    echo
    out=$(dupes "${@: -1}")
    if [[ -z $out ]]; then
        echo "duplicates: none"
    else
        echo "duplicates:"
        while IFS=$'\t' read -r count size paths; do
            echo "  $count x $(human "$size"): $paths"
            total=$((total + size * (count - 1)))
        done < <(awk 'BEGIN { RS = ""; FS = "\n" }
            { paths = ""; for (i = 1; i <= NF; i++) paths = paths (i > 1 ? ", " : "") substr($i, index($i, " ") + 1)
              split($1, a, " "); print NF "\t" a[1] "\t" paths }' <<<"$out")
    fi
    echo "reclaimable: $(human "$total")"
}

cmd=${1:-}
[[ $# -gt 0 ]] && shift
case $cmd in
human) human "$@" ;;
dupes) dupes "$@" ;;
tree) tree_cmd "$@" ;;
report) report "$@" ;;
*) die "usage: solution.sh human|dupes|tree|report ARGS..." ;;
esac
