#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

usage() {
    cat <<EOF
Usage: sudo $0 [--dry-run] [--source <git url|path>] [--allow-drop-caches]

One-time host setup (root). Idempotent; each step is skipped when already done.
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
require_root "$@"
LOGS_DIR=/var/log/llm-stack
init_logging bootstrap

APT_PKGS=(build-essential cmake ninja-build git jq curl numactl python3-venv shellcheck util-linux iproute2)
missing=()
for p in "${APT_PKGS[@]}"; do dpkg -s "$p" >/dev/null 2>&1 || missing+=("$p"); done
if ((${#missing[@]})); then
    run apt-get update
    run env DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}"
else
    info "apt packages present"
fi

if id "$LLM_USER" >/dev/null 2>&1; then
    info "user $LLM_USER exists"
else
    run useradd --system --home-dir "$LLM_ROOT" --no-create-home --shell /usr/sbin/nologin "$LLM_USER"
fi
for g in video render; do
    if getent group "$g" >/dev/null && ! id -nG "$LLM_USER" 2>/dev/null | grep -qw "$g"; then
        run usermod -aG "$g" "$LLM_USER"
    fi
done

for d in "" engines models secrets results logs state cache hf-cache; do
    path=$LLM_ROOT${d:+/$d}
    if [[ ! -d $path ]]; then
        run install -d -o "$LLM_USER" -g "$LLM_USER" -m 755 "$path"
    fi
done
[[ $(stat -c %a "$LLM_ROOT/secrets" 2>/dev/null) == 700 ]] || run chmod 700 "$LLM_ROOT/secrets"
[[ $(stat -c %U "$LLM_ROOT" 2>/dev/null) == "$LLM_USER" ]] || run chown "$LLM_USER:$LLM_USER" "$LLM_ROOT"

if [[ -d $LLM_ROOT/stack/.git ]]; then
    info "$LLM_ROOT/stack already cloned"
elif [[ -n $SOURCE ]]; then
    run runuser -u "$LLM_USER" -- git clone "$SOURCE" "$LLM_ROOT/stack"
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
    [[ -d $venv ]] || run runuser -u "$LLM_USER" -- python3 -m venv "$venv"
    run runuser -u "$LLM_USER" -- "$venv/bin/pip" install -q -r "$req"
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
