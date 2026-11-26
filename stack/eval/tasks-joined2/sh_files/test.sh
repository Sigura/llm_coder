source ./assert.sh

# --- human
for pair in 0:0B 1:1B 1023:1023B 1024:1.0K 1075:1.0K 1076:1.1K 1536:1.5K 10188:9.9K 10189:10K 10239:10K \
    10240:10K 1023487:999K 1048063:1023K 1048064:1.0M 1048575:1.0M 1048576:1.0M 1572864:1.5M \
    1073741824:1.0G 1099511627776:1.0T 1125899906842624:1024T 2251799813685248:2048T 007:7B 0001024:1.0K; do
    check "human ${pair%%:*}" "${pair#*:}" "$(bash solution.sh human "${pair%%:*}" 2>&1)"
done
for bad in -1 1.5 '' 1K ' 12' 12345678901234567 0x10; do
    check "human bad [$bad]" 2 "$(bash solution.sh human "$bad" >/dev/null 2>&1; echo $?)"
done
check human_no_arg 2 "$(bash solution.sh human >/dev/null 2>&1; echo $?)"
check human_two_args 2 "$(bash solution.sh human 1 2 >/dev/null 2>&1; echo $?)"

# --- fixture
mk() { mkdir -p "$(dirname "$1")"; printf '%s' "$2" > "$1"; }
rm -rf proj && mkdir proj
mk proj/a.txt "hello"
mk "proj/my docs/b copy.txt" "hello"
mk proj/sub/deep/c.txt "hello"
mk proj/sub/x.bin "$(head -c 1536 /dev/zero | tr '\0' 'x')"
mk proj/y.bin "$(head -c 1536 /dev/zero | tr '\0' 'x')"
mk proj/z.bin "$(head -c 1536 /dev/zero | tr '\0' 'y')"
mk proj/.hidden/h.txt "hello"
mk proj/sub/empty1 ""
mk proj/empty2 ""
mk proj/uniq.txt "unique"
ln -s a.txt proj/link
ln -s sub proj/sublink
mkdir -p proj/emptydir

# --- dupes
expected="1536 sub/x.bin
1536 y.bin

5 .hidden/h.txt
5 a.txt
5 my docs/b copy.txt
5 sub/deep/c.txt"
out=$(bash solution.sh dupes proj); rc=$?
check dupes_rc 0 "$rc"
check dupes "$expected" "$out"
check dupes_trailing_slash "$expected" "$(bash solution.sh dupes proj/)"
rm -rf solo && mkdir solo && mk solo/a "1" && mk solo/b "2" && mk solo/e1 "" && mk solo/e2 ""
out=$(bash solution.sh dupes solo); rc=$?
check dupes_none "0:" "$rc:$out"
rm -rf ord && mkdir ord && mk ord/q "ab" && mk ord/r "ab" && mk ord/b "cd" && mk ord/p "cd" && mk ord/B "cd"
check dupes_group_order "2 B
2 b
2 p

2 q
2 r" "$(bash solution.sh dupes ord)"
check dupes_missing 2 "$(bash solution.sh dupes nope >/dev/null 2>&1; echo $?)"
check dupes_file_arg 2 "$(bash solution.sh dupes proj/a.txt >/dev/null 2>&1; echo $?)"

# --- tree
expected="proj
├── a.txt
├── empty2
├── emptydir/
├── link -> a.txt
├── my docs/
│   └── b copy.txt
├── sub/
│   ├── deep/
│   │   └── c.txt
│   ├── empty1
│   └── x.bin
├── sublink -> sub
├── uniq.txt
├── y.bin
└── z.bin

4 directories, 11 files"
check tree "$expected" "$(bash solution.sh tree proj)"
expected="proj
├── a.txt
├── empty2
├── emptydir/
├── link -> a.txt
├── my docs/
├── sub/
├── sublink -> sub
├── uniq.txt
├── y.bin
└── z.bin

3 directories, 7 files"
check tree_L1 "$expected" "$(bash solution.sh tree -L 1 proj)"
check tree_L2_count "4 directories, 10 files" "$(bash solution.sh tree -L 2 proj | tail -n 1)"
rm -rf t2 && mkdir -p t2/a/b t2/c && mk t2/a/b/f "1" && mk t2/a/g "1" && mk t2/c/h "1"
expected="./t2
├── a/
│   ├── b/
│   │   └── f
│   └── g
└── c/
    └── h

3 directories, 3 files"
check tree_last_prefix "$expected" "$(bash solution.sh tree ./t2)"
mkdir -p t3
check tree_empty "t3

0 directories, 0 files" "$(bash solution.sh tree t3)"
for bad in "-L 0 proj" "-L x proj" "-L proj" "nope" "proj/a.txt" ""; do
    check "tree bad [$bad]" 2 "$(bash solution.sh tree $bad >/dev/null 2>&1; echo $?)"
done

# --- report
expected="$(bash solution.sh tree -L 1 proj)

duplicates:
  2 x 1.5K: sub/x.bin, y.bin
  4 x 5B: .hidden/h.txt, a.txt, my docs/b copy.txt, sub/deep/c.txt
reclaimable: 1.5K"
check report "$expected" "$(bash solution.sh report -L 1 proj)"
check report_none "$(bash solution.sh tree solo)

duplicates: none
reclaimable: 0B" "$(bash solution.sh report solo)"
rm -rf big && mkdir big && head -c 700000 /dev/urandom > big/r1 && cp big/r1 big/r2 && cp big/r1 big/r3
check report_reclaim_sum "reclaimable: 1.3M" "$(bash solution.sh report big | tail -n 1)"
check report_bad 2 "$(bash solution.sh report -L 0 proj >/dev/null 2>&1; echo $?)"
check report_missing 2 "$(bash solution.sh report nope >/dev/null 2>&1; echo $?)"
check bad_subcommand 2 "$(bash solution.sh bogus >/dev/null 2>&1; echo $?)"
check no_subcommand 2 "$(bash solution.sh >/dev/null 2>&1; echo $?)"
finish
