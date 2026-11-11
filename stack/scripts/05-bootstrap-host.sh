#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

usage() {
    cat <<EOF
Usage: sudo $0 [--dry-run] [--source <git url|path>] [--allow-drop-caches]

One-time host setup (root). Idempotent; each step is skipped when already done.
Run as LLM_USER instead of root (user mode, e.g. in a container): no apt, groups or
drop-caches; only the layout, the clone and the venv.
  - installs missing apt packages (build tools, numactl, jq, python3-venv, shellcheck)
  - creates system user LLM_USER and the LLM_ROOT layout (secrets/ mode 700)
  - clones this repo to LLM_ROOT/stack when --source is given and it is absent
  - creates LLM_ROOT/venv with the pinned huggingface_hub (requirements.txt)
  --allow-drop-caches  also install /usr/local/sbin/llm-drop-caches and a sudoers
                       rule letting LLM_USER run it, so 30-benchmark.sh can compare
                       NUMA modes from a cold page cache.
Never touches the NVIDIA driver or CUDA toolkit; 00-check-host.sh reports on them.
EOF
}

SOURCE=""
DROP_CACHES=0
while (($#)); do
    case $1 in
    -h | --help) usage; exit 0 ;;
    -n | --dry-run) DRY_RUN=1 ;;
    --source) SOURCE=$2; shift ;;
    --allow-drop-caches) DROP_CACHES=1 ;;
    *) die "unknown argument $1" ;;
    esac
    shift
done

load_global
# User mode: LLM_USER is the current login (e.g. inside a container); root-only steps are skipped.
if ((EUID == 0)); then
    USER_MODE=0
elif [[ $(id -un) == "$LLM_USER" ]]; then
    USER_MODE=1
    ((DROP_CACHES == 0)) || die "--allow-drop-caches needs root"
else
    die "run as root, or as LLM_USER ($LLM_USER) for user mode"
fi

# User and layout come first so that this run can already log to LOGS_DIR.
if id "$LLM_USER" >/dev/null 2>&1; then
    info "user $LLM_USER exists"
else
    run useradd --system --home-dir "$LLM_ROOT" --no-create-home --shell /usr/sbin/nologin "$LLM_USER"
fi
if ((USER_MODE == 0)); then
    for g in video render; do
        if getent group "$g" >/dev/null && ! id -nG "$LLM_USER" 2>/dev/null | grep -qw "$g"; then
            run usermod -aG "$g" "$LLM_USER"
        fi
    done
fi

for d in "" engines models secrets results logs state cache hf-cache; do
    path=$LLM_ROOT${d:+/$d}
    if [[ ! -d $path ]]; then
        if ((USER_MODE)); then run install -d -m 755 "$path"; else run install -d -o "$LLM_USER" -g "$LLM_USER" -m 755 "$path"; fi
    elif [[ $(stat -c %U "$path") != "$LLM_USER" ]]; then
        ((USER_MODE == 0)) || die "$path is owned by $(stat -c %U "$path"), not $LLM_USER; chown it as root"
        run chown "$LLM_USER:$LLM_USER" "$path"
    fi
done
[[ $(stat -c %a "$LLM_ROOT/secrets" 2>/dev/null) == 700 ]] || run chmod 700 "$LLM_ROOT/secrets"
if ! ((DRY_RUN)) && ! as_llm test -w "$LLM_ROOT"; then
    die "$LLM_USER cannot reach $LLM_ROOT: every parent directory needs o+x (namei -l $LLM_ROOT), or pick another LLM_ROOT"
fi

init_logging bootstrap

APT_PKGS=(build-essential cmake ninja-build git jq curl numactl python3-venv shellcheck util-linux iproute2)
missing=()
for p in "${APT_PKGS[@]}"; do dpkg -s "$p" >/dev/null 2>&1 || missing+=("$p"); done
if ((USER_MODE)); then
    info "user mode: apt packages not managed; 00-check-host.sh reports missing tools"
elif ((${#missing[@]})); then
    run apt-get update
    run env DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}"
else
    info "apt packages present"
fi

if [[ -d $LLM_ROOT/stack/.git ]]; then
    info "$LLM_ROOT/stack already cloned"
elif [[ -n $SOURCE ]] && ((USER_MODE)); then
    run git clone "$SOURCE" "$LLM_ROOT/stack"
elif [[ -n $SOURCE ]]; then
    safe=()
    # A local source owned by another user fails git's ownership check ("dubious ownership").
    if [[ -d $SOURCE ]]; then
        src=$(cd "$SOURCE" && pwd)
        safe=(-c "safe.directory=$src" -c "safe.directory=$src/.git")
    fi
    # Cloned as root because LLM_USER usually cannot read the source (e.g. under a 750 home).
    # --no-hardlinks: the chown below must not reach the source repo's object files.
    run git "${safe[@]}" clone --no-hardlinks "$SOURCE" "$LLM_ROOT/stack"
    run chown -R "$LLM_USER:$LLM_USER" "$LLM_ROOT/stack"
else
    warn "$LLM_ROOT/stack missing; re-run with --source <repo> or clone it there as $LLM_USER"
fi

venv=$LLM_ROOT/venv
req=$STACK_DIR/requirements.txt
want_ver=$(sed -n 's/^huggingface_hub[^=]*==//p' "$req")
have_ver=$("$venv/bin/python" -c 'import importlib.metadata as m; print(m.version("huggingface_hub"))' 2>/dev/null || true)
if [[ -n $want_ver && $have_ver == "$want_ver" ]]; then
    info "venv $venv has huggingface_hub $have_ver"
else
    [[ -d $venv ]] || run as_llm python3 -m venv "$venv"
    run as_llm "$venv/bin/pip" install -q -r "$req"
fi

if ((DROP_CACHES)); then
    helper=/usr/local/sbin/llm-drop-caches
    want=$'#!/bin/sh\nsync\necho 3 > /proc/sys/vm/drop_caches\n'
    if [[ $(cat "$helper" 2>/dev/null) != "${want%$'\n'}" ]]; then
        if ((DRY_RUN)); then info "[dry-run] would write $helper"; else
            printf '%s' "$want" >"$helper" && chmod 755 "$helper" && info "wrote $helper"
        fi
    fi
    rule="$LLM_USER ALL=(root) NOPASSWD: $helper"
    sudoers=/etc/sudoers.d/llm-drop-caches
    if [[ $(cat "$sudoers" 2>/dev/null) != "$rule" ]]; then
        if ((DRY_RUN)); then info "[dry-run] would write $sudoers: $rule"; else
            tmp=$(mktemp)
            echo "$rule" >"$tmp"
            visudo -cf "$tmp" >/dev/null || die "sudoers rule failed validation"
            install -m 440 "$tmp" "$sudoers"
            rm -f "$tmp"
            info "wrote $sudoers"
        fi
    fi
fi

info "bootstrap done; next: sudo -u $LLM_USER make -C $LLM_ROOT/stack check"
