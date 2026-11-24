#!/usr/bin/env bash
set -euo pipefail

dotenv() (
    OPTIND=1
    file=${1:?usage: $0 FILE}
    declare -A val=() last=()
    order=()
    n=0
    fail() { echo "$file:$n: invalid line" >&2; exit 1; }
    rest_ok() { [[ $1 =~ ^[[:blank:]]*(#.*)?$ ]]; }
    while IFS= read -r line || [[ -n $line ]]; do
        n=$((n + 1))
        [[ $line =~ ^[[:blank:]]*(#.*)?$ ]] && continue
        line=${line#export }
        [[ $line =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]] || fail
        key=${BASH_REMATCH[1]} v=${BASH_REMATCH[2]}
        if [[ $v == \'* ]]; then
            [[ $v =~ ^\'([^\']*)\'(.*)$ ]] || fail
            v=${BASH_REMATCH[1]}
            rest_ok "${BASH_REMATCH[2]}" || fail
        elif [[ $v == \"* ]]; then
            body=${v:1} out= i=0 closed=0
            while (( i < ${#body} )); do
                c=${body:i:1}
                if [[ $c == '\' && $((i + 1)) -lt ${#body} ]]; then
                    nx=${body:i+1:1}
                    case $nx in
                        n) out+=$'\n' ;;
                        '"') out+='"' ;;
                        '\') out+='\' ;;
                        *) out+="\\$nx" ;;
                    esac
                    i=$((i + 2))
                elif [[ $c == '"' ]]; then
                    closed=1; break
                else
                    out+=$c; i=$((i + 1))
                fi
            done
            (( closed )) || fail
            rest_ok "${body:i+1}" || fail
            v=$out
        else
            v=${v%%[[:blank:]]#*}
            v=${v%"${v##*[![:blank:]]}"}
        fi
        val[$key]=$v
        last[$key]=$n
        order+=("$key")
    done < "$file"
    for i in "${!order[@]}"; do
        k=${order[i]}
        printf '%s\n' "$k"
    done | awk '{ pos[$0] = NR; keys[NR] = $0 } END { for (i = 1; i <= NR; i++) if (pos[keys[i]] == i) print keys[i] }' \
    | while IFS= read -r k; do
        v=${val[$k]}
        printf "export %s='%s'\n" "$k" "${v//\'/\'\\\'\'}"
    done
)

retry() (
    OPTIND=1
    set +e
    usage() { echo "usage: $0 [-n N] [-d DELAY] [-b FACTOR] [-r CODES] -- COMMAND [ARGS...]" >&2; exit 64; }
    n=3 d=1 b=2 codes=
    num='^[0-9]+([.][0-9]+)?$|^[.][0-9]+$'
    while (( $# )); do
        case $1 in
            -n) [[ ${2-} =~ ^[1-9][0-9]*$ ]] || usage; n=$2; shift 2 ;;
            -d) [[ ${2-} =~ $num ]] || usage; d=$2; shift 2 ;;
            -b) [[ ${2-} =~ $num ]] || usage; b=$2; shift 2 ;;
            -r) [[ ${2-} =~ ^[0-9]+(,[0-9]+)*$ ]] || usage; codes=",$2,"; shift 2 ;;
            --) shift; break ;;
            *) usage ;;
        esac
    done
    (( $# )) || usage
    k=1
    while :; do
        if (( k == 1 )); then "$@"; else "$@" </dev/null; fi
        rc=$?
        (( rc == 0 )) && exit 0
        (( k >= n )) && exit "$rc"
        [[ -z $codes || $codes == *",$rc,"* ]] || exit "$rc"
        s=$(awk -v d="$d" 'BEGIN { printf "%g", d }')
        echo "retry: attempt $k/$n failed with exit code $rc, sleeping $s s" >&2
        sleep "$d"
        d=$(awk -v d="$d" -v b="$b" 'BEGIN { printf "%.10g", d * b }')
        k=$((k + 1))
    done
)

rotate() (
    OPTIND=1
    die() { echo "$*" >&2; exit 2; }
    dry=0 keep=7
    while getopts ":nk:" o; do
        case $o in
            n) dry=1 ;;
            k) keep=$OPTARG ;;
            *) die "usage: $0 [-n] [-k KEEP] DIR PREFIX" ;;
        esac
    done
    shift $((OPTIND - 1))
    (( $# == 2 )) || die "usage: $0 [-n] [-k KEEP] DIR PREFIX"
    [[ $keep =~ ^[0-9]+$ ]] || die "bad KEEP"
    dir=$1 prefix=$2
    [[ -d $dir ]] || die "no such dir: $dir"
    names=()
    for f in "$dir"/*; do
        b=${f##*/}
        [[ -f $f && ! -L $f ]] || continue
        [[ ${b:0:${#prefix}} == "$prefix" ]] || continue
        rest=${b:${#prefix}}
        [[ $rest =~ ^-[0-9]{8}-[0-9]{6}\.tar\.gz$ ]] || continue
        names+=("${rest:1:15} $b")
    done
    (( ${#names[@]} )) || exit 0
    mapfile -t sorted < <(printf '%s\n' "${names[@]}" | LC_ALL=C sort -r)
    declare -A keepset=() months=()
    i=0
    for line in "${sorted[@]}"; do
        ts=${line%% *} b=${line#* }
        (( i < keep )) && keepset[$b]=1
        m=${ts:0:6}
        if [[ -z ${months[$m]-} ]] && (( ${#months[@]} < 4 )); then
            months[$m]=1; keepset[$b]=1
        fi
        i=$((i + 1))
    done
    for (( j = ${#sorted[@]} - 1; j >= 0; j-- )); do
        b=${sorted[j]#* }
        [[ -n ${keepset[$b]-} ]] && continue
        echo "delete $b"
        (( dry )) || rm -- "$dir/$b"
    done
)

backup() (
    (( $# >= 3 )) && [[ $2 == -- ]] || { echo "usage: solution.sh backup ENVFILE -- COMMAND [ARGS...]" >&2; exit 2; }
    file=$1
    shift 2
    code=$(dotenv "$file") || exit $?
    eval "$code"
    [[ -n ${BACKUP_DIR-} && -n ${BACKUP_PREFIX-} ]] || { echo "$file: BACKUP_DIR and BACKUP_PREFIX are required" >&2; exit 2; }
    rc=0
    retry -n "${RETRIES:-3}" -d "${RETRY_DELAY:-1}" -- "$@" || rc=$?
    (( rc == 0 )) || exit "$rc"
    rotate -k "${KEEP:-7}" "$BACKUP_DIR" "$BACKUP_PREFIX"
)

cmd=${1:-}
case $cmd in
    dotenv | retry | rotate | backup) shift; "$cmd" "$@" ;;
    *) echo "usage: solution.sh dotenv|retry|rotate|backup ARGS..." >&2; exit 2 ;;
esac
