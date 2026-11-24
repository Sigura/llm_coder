source ./assert.sh

# --- dotenv
out=$(bash solution.sh dotenv fixture.env); rc=$?
check rc 0 "$rc"
check lines "export A
export C
export D
export E
export F
export G
export B
export H
export I" "$(sed -n 's/^\(export [A-Z]*\)=.*/\1/p' <<<"$out")"
eval "$out"
check A "plain value" "$A"
check B "second" "$B"
check C "a  b " "$C"
check D 'single $HOME `x` "q"' "$D"
check E $'line1\nline2 "q" back\\slash \\t $HOME' "$E"
check F "" "$F"
check G "" "$G"
check H "x'y" "$H"
check I "	spaced" "$I"
check line_count 1 "$(grep -c '^export B=' <<<"$out")"
check quoting_single 1 "$(grep -c "^export H='x'\\\\''y'$" <<<"$out")"

printf 'OK=1\nexport\nX=2\n' > bad1.env
out=$(bash solution.sh dotenv bad1.env 2>err); rc=$?
check bad_rc 1 "$rc"
check bad_out "" "$out"
check bad_err "bad1.env:2: invalid line" "$(cat err)"
for bad in 'K = v' '1K=v' "K='open" 'K="open' "K='a' junk" 'K="a"b' 'K'; do
    printf 'A=1\n%s\n' "$bad" > bad.env
    check "bad[$bad]" 1 "$(bash solution.sh dotenv bad.env >/dev/null 2>&1; echo $?)"
done
printf 'K="a" # ok\nL=x # y # z\n' > ok.env
eval "$(bash solution.sh dotenv ok.env)"
check comment_after_quote "a" "$K"
check comment_unquoted "x" "$L"

# --- retry
cat > flaky.sh <<'X'
#!/usr/bin/env bash
n=$(cat count 2>/dev/null || echo 0); n=$((n + 1)); echo $n > count
echo "run $n"
[[ $n -ge ${SUCCEED_AT:-99} ]] && exit 0
exit ${CODE:-3}
X
chmod +x flaky.sh
reset() { rm -f count; }

reset; out=$(SUCCEED_AT=3 bash solution.sh retry -d 0.01 -- ./flaky.sh 2>err); rc=$?
check succeed_rc 0 "$rc"
check succeed_out "run 1
run 2
run 3" "$out"
check succeed_err "retry: attempt 1/3 failed with exit code 3, sleeping 0.01 s
retry: attempt 2/3 failed with exit code 3, sleeping 0.02 s" "$(cat err)"

reset; bash solution.sh retry -n 4 -d 0.01 -b 1.5 -- ./flaky.sh >/dev/null 2>err; rc=$?
check fail_rc 3 "$rc"
check fail_err "retry: attempt 1/4 failed with exit code 3, sleeping 0.01 s
retry: attempt 2/4 failed with exit code 3, sleeping 0.015 s
retry: attempt 3/4 failed with exit code 3, sleeping 0.0225 s" "$(cat err)"
check fail_runs 4 "$(cat count)"

reset; CODE=5 bash solution.sh retry -r 3,4 -d 0.01 -- ./flaky.sh >/dev/null 2>err; rc=$?
check nonretryable_rc 5 "$rc"
check nonretryable_runs 1 "$(cat count)"
check nonretryable_err "" "$(cat err)"

reset; CODE=4 bash solution.sh retry -n 2 -r 3,4 -d 0.01 -- ./flaky.sh >/dev/null 2>/dev/null
check retryable_listed 2 "$(cat count)"

check args_preserved "[a b] [] [*] [\$HOME]" "$(bash solution.sh retry -n 1 -- printf '[%s] ' 'a b' '' '*' '$HOME' | sed 's/ $//')"
check stdin_first_only "x||" "$(cat > rd.sh <<'X'
read -r line; printf '%s|' "$line"; exit 1
X
printf "x\ny\n" | bash solution.sh retry -n 2 -d 0.01 -- bash rd.sh 2>/dev/null)"

start=$(date +%s%N); reset; bash solution.sh retry -n 3 -d 0.2 -b 1 -- ./flaky.sh >/dev/null 2>&1; end=$(date +%s%N)
ms=$(( (end - start) / 1000000 ))
check sleeps_happen 1 "$(( ms >= 380 && ms < 2000 ))"

check no_command 64 "$(bash solution.sh retry -n 2 >/dev/null 2>&1; echo $?)"
check no_dashdash 64 "$(bash solution.sh retry -n 2 true >/dev/null 2>&1; echo $?)"
check bad_n 64 "$(bash solution.sh retry -n x -- true >/dev/null 2>&1; echo $?)"
check bad_d 64 "$(bash solution.sh retry -d abc -- true >/dev/null 2>&1; echo $?)"
check default_success 0 "$(bash solution.sh retry -- true >/dev/null 2>&1; echo $?)"

# --- rotate
D="my backups"
setup() {
    rm -rf "$D"; mkdir "$D"
    for ts in 20260105-010000 20260120-010000 20260203-010000 20260228-235959 20260301-000000 \
              20260415-120000 20260416-120000 20260417-120000 20260418-120000 20260419-120000; do
        touch "$D/db.main+1-$ts.tar.gz"
    done
    touch "$D/db.main+1-20251231-000000.tar.gz.part" "$D/dbXmain+1-20250101-000000.tar.gz" \
          "$D/other-20250101-000000.tar.gz" "$D/db.main+1-2026011-010000.tar.gz"
    mkdir "$D/db.main+1-20240101-000000.tar.gz"
    ln -s /etc/hostname "$D/db.main+1-20240102-000000.tar.gz"
    # mtimes deliberately inverted relative to names
    touch -d '2020-01-01' "$D/db.main+1-20260419-120000.tar.gz"
}
listing() { (cd "$D" && ls -1A | LC_ALL=C sort); }

setup; before=$(listing)
out=$(bash solution.sh rotate -n -k 3 "$D" 'db.main+1')
check dry_run_out "delete db.main+1-20260105-010000.tar.gz
delete db.main+1-20260203-010000.tar.gz
delete db.main+1-20260415-120000.tar.gz
delete db.main+1-20260416-120000.tar.gz" "$out"
check dry_run_untouched "$before" "$(listing)"

bash solution.sh rotate -k 3 "$D" 'db.main+1' >/dev/null
check deleted "$(LC_ALL=C sort <<<"db.main+1-2026011-010000.tar.gz
db.main+1-20240101-000000.tar.gz
db.main+1-20240102-000000.tar.gz
db.main+1-20251231-000000.tar.gz.part
db.main+1-20260120-010000.tar.gz
db.main+1-20260228-235959.tar.gz
db.main+1-20260301-000000.tar.gz
db.main+1-20260417-120000.tar.gz
db.main+1-20260418-120000.tar.gz
db.main+1-20260419-120000.tar.gz
dbXmain+1-20250101-000000.tar.gz
other-20250101-000000.tar.gz")" "$(listing)"
check symlink_target_intact 1 "$([[ -e /etc/hostname ]] && echo 1)"

setup
check default_keep "delete db.main+1-20260105-010000.tar.gz
delete db.main+1-20260203-010000.tar.gz" "$(bash solution.sh rotate -n "$D" 'db.main+1')"
check keep_zero "delete db.main+1-20260105-010000.tar.gz
delete db.main+1-20260203-010000.tar.gz
delete db.main+1-20260415-120000.tar.gz
delete db.main+1-20260416-120000.tar.gz
delete db.main+1-20260417-120000.tar.gz
delete db.main+1-20260418-120000.tar.gz" "$(bash solution.sh rotate -n -k 0 "$D" 'db.main+1')"
check nothing "" "$(bash solution.sh rotate -k 3 "$D" nomatch)"
check missing_dir 2 "$(bash solution.sh rotate -k 3 nodir x >/dev/null 2>&1; echo $?)"
check bad_keep 2 "$(bash solution.sh rotate -k -1 "$D" x >/dev/null 2>&1; echo $?)"
check missing_args 2 "$(bash solution.sh rotate "$D" >/dev/null 2>&1; echo $?)"

# --- backup
cat > mk.sh <<'X'
n=$(cat bcount 2>/dev/null || echo 0); n=$((n + 1)); echo $n > bcount
[[ $n -ge ${OK_AT:-1} ]] || { echo "try $n failed"; exit 7; }
touch "$BACKUP_DIR/$BACKUP_PREFIX-$STAMP.tar.gz"
echo "made $STAMP in $BACKUP_DIR"
X
BK="bk dir"
bsetup() {
    rm -rf "$BK" bcount; mkdir "$BK"
    for ts in 20260301-000000 20260401-000000 20260402-000000 20260403-000000; do touch "$BK/app's.db-$ts.tar.gz"; done
}
printf '%s\n' "export BACKUP_DIR='bk dir'" 'BACKUP_PREFIX="app'"'"'s.db"' 'KEEP=2 # newest two' 'RETRY_DELAY=0.01' \
    'STAMP=20260404-000000' 'OK_AT=2' > b1.env
bsetup; out=$(bash solution.sh backup b1.env -- bash mk.sh 2>err); rc=$?
check backup_rc 0 "$rc"
check backup_out "try 1 failed
made 20260404-000000 in bk dir
delete app's.db-20260401-000000.tar.gz
delete app's.db-20260402-000000.tar.gz" "$out"
check backup_err "retry: attempt 1/3 failed with exit code 7, sleeping 0.01 s" "$(cat err)"
check backup_left "app's.db-20260301-000000.tar.gz
app's.db-20260403-000000.tar.gz
app's.db-20260404-000000.tar.gz" "$(cd "$BK" && ls -1 | LC_ALL=C sort)"

printf '%s\n' "BACKUP_DIR='bk dir'" "BACKUP_PREFIX=app's" 'RETRIES=2' 'RETRY_DELAY=0.01' 'OK_AT=5' 'STAMP=x' > b2.env
bsetup; bash solution.sh backup b2.env -- bash mk.sh >/dev/null 2>err; rc=$?
check backup_fail_rc 7 "$rc"
check backup_fail_runs 2 "$(cat bcount)"
check backup_fail_no_prune 4 "$(ls "$BK" | wc -l)"
check backup_fail_err "retry: attempt 1/2 failed with exit code 7, sleeping 0.01 s" "$(cat err)"

printf 'BACKUP_DIR=bk\nBAD LINE\n' > b3.env
bsetup; out=$(bash solution.sh backup b3.env -- bash mk.sh 2>err); rc=$?
check backup_bad_env_rc 1 "$rc"
check backup_bad_env_out "" "$out"
check backup_bad_env_err "b3.env:2: invalid line" "$(cat err)"
check backup_bad_env_no_run "" "$(cat bcount 2>/dev/null)"

printf 'BACKUP_DIR=bk\n' > b4.env
check backup_no_prefix 2 "$(bash solution.sh backup b4.env -- true >/dev/null 2>&1; echo $?)"
printf "BACKUP_DIR='bk dir'\nBACKUP_PREFIX=x\nRETRIES=zero\n" > b5.env
check backup_bad_retries 64 "$(bash solution.sh backup b5.env -- true >/dev/null 2>&1; echo $?)"
printf "BACKUP_DIR=nodir\nBACKUP_PREFIX=x\n" > b6.env
check backup_prune_error 2 "$(bash solution.sh backup b6.env -- true >/dev/null 2>&1; echo $?)"
check backup_no_dashdash 2 "$(bash solution.sh backup b1.env bash mk.sh >/dev/null 2>&1; echo $?)"
check backup_no_command 2 "$(bash solution.sh backup b1.env -- >/dev/null 2>&1; echo $?)"
check bad_subcommand 2 "$(bash solution.sh bogus >/dev/null 2>&1; echo $?)"
finish
