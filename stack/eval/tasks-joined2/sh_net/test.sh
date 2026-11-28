source ./assert.sh

# --- cidr
check cidr_24 "network 192.168.1.0/24
broadcast 192.168.1.255
first 192.168.1.1
last 192.168.1.254
hosts 254" "$(bash solution.sh cidr 192.168.1.77/24)"
check cidr_odd "network 10.4.0.0/14
broadcast 10.7.255.255
first 10.4.0.1
last 10.7.255.254
hosts 262142" "$(bash solution.sh cidr 10.5.6.7/14)"
check cidr_31 "network 10.0.0.2/31
broadcast 10.0.0.3
first 10.0.0.2
last 10.0.0.3
hosts 2" "$(bash solution.sh cidr 10.0.0.3/31)"
check cidr_32 "network 1.2.3.4/32
broadcast 1.2.3.4
first 1.2.3.4
last 1.2.3.4
hosts 1" "$(bash solution.sh cidr 1.2.3.4/32)"
check cidr_0 "network 0.0.0.0/0
broadcast 255.255.255.255
first 0.0.0.1
last 255.255.255.254
hosts 4294967294" "$(bash solution.sh cidr 200.1.1.1/0)"
check cidr_30_hosts "hosts 2" "$(bash solution.sh cidr 10.0.0.9/30 | tail -n 1)"
for bad in 10.0.0.1 10.0.0.1/33 10.0.0.1/08 256.0.0.1/8 10.0.0/8 10.0.0.01/8 10.0.0.1/ /8 1.2.3.4.5/8 a.b.c.d/8 \
    "10.0.0.1/24 " 10.0.0.0-10.0.0.5 " 1.2.3.4/8" 1.2.3.-4/8; do
    check "cidr bad [$bad]" 2 "$(bash solution.sh cidr "$bad" >/dev/null 2>&1; echo $?)"
done
check cidr_extra 2 "$(bash solution.sh cidr 1.2.3.4/8 x >/dev/null 2>&1; echo $?)"

# --- merge
out=$(printf '%s\n' "# office" "10.0.0.10-10.0.0.20" "  10.0.0.0-10.0.0.9	" "" "10.0.1.0/24" \
    "10.0.0.255" "192.168.0.5" "192.168.0.7" "10.0.0.5" "172.16.0.0/12" "172.20.1.1-172.20.1.9" | bash solution.sh merge)
check merge "10.0.0.0-10.0.0.20
10.0.0.255-10.0.1.255
172.16.0.0-172.31.255.255
192.168.0.5
192.168.0.7" "$out"
check merge_numeric_order "1.0.0.0
9.0.0.0-9.0.0.1
10.0.0.0
100.0.0.0" "$(printf '100.0.0.0\n10.0.0.0\n9.0.0.1\n1.0.0.0\n9.0.0.0\n' | bash solution.sh merge)"
check merge_contained "1.0.0.0-1.0.0.100" "$(printf '1.0.0.0-1.0.0.100\n1.0.0.5-1.0.0.6\n1.0.0.7\n' | bash solution.sh merge)"
check merge_full "0.0.0.0-255.255.255.255" "$(printf '0.0.0.0/1\n128.0.0.0/1\n' | bash solution.sh merge)"
check merge_no_final_newline "1.1.1.1-1.1.1.2" "$(printf '1.1.1.1\n1.1.1.2' | bash solution.sh merge)"
check merge_empty "0:" "$(printf '# none\n\n' | bash solution.sh merge; echo "$?:")"
out=$(printf '1.1.1.1\n# x\n1.1.1.9-1.1.1.2\n2.2.2.2\n' | bash solution.sh merge 2>err); rc=$?
check merge_bad "1::line 3: invalid" "$rc:$out:$(cat err)"
for bad in "1.2.3.4 - 1.2.3.5" "1.2.3.4-" "300.1.1.1" "1.2.3.4/33" "1.2.3.4-1.2.3.5-1.2.3.6" "any"; do
    check "merge bad [$bad]" 1 "$(printf '%s\n' "$bad" | bash solution.sh merge >/dev/null 2>&1; echo $?)"
done

# --- tocidr
check tocidr_example "10.0.0.1/32
10.0.0.2/31
10.0.0.4/31
10.0.0.6/32" "$(bash solution.sh tocidr 10.0.0.1-10.0.0.6)"
check tocidr_all "0.0.0.0/0" "$(bash solution.sh tocidr 0.0.0.0-255.255.255.255)"
check tocidr_block "10.0.0.0/8" "$(bash solution.sh tocidr 10.20.30.40/8)"
check tocidr_single "8.8.8.8/32" "$(bash solution.sh tocidr 8.8.8.8)"
check tocidr_cross "10.0.0.255/32
10.0.1.0/24
10.0.2.0/23
10.0.4.0/32" "$(bash solution.sh tocidr 10.0.0.255-10.0.4.0)"
check tocidr_top "255.255.255.254/31" "$(bash solution.sh tocidr 255.255.255.254-255.255.255.255)"
check tocidr_bad 2 "$(bash solution.sh tocidr 1.2.3.5-1.2.3.4 >/dev/null 2>&1; echo $?)"
check tocidr_none 2 "$(bash solution.sh tocidr >/dev/null 2>&1; echo $?)"

# --- acl
cat > rules.txt <<'EOF'
# office network
deny 10.0.0.13
allow	10.0.0.0/28
  allow 10.0.0.16-10.0.0.20

deny 192.168.0.0/16
allow 192.168.1.1
allow 172.16.0.0/31
EOF
out=$(bash solution.sh acl rules.txt 10.0.0.13 10.0.0.1 10.0.0.20 10.0.0.21 192.168.1.1 172.16.0.1 8.8.8.8); rc=$?
check acl_rc 0 "$rc"
check acl_addrs "10.0.0.13 deny 2
10.0.0.1 allow 3
10.0.0.20 allow 4
10.0.0.21 deny default
192.168.1.1 deny 6
172.16.0.1 allow 8
8.8.8.8 deny default" "$out"
check acl_set "10.0.0.0/29
10.0.0.8/30
10.0.0.12/32
10.0.0.14/31
10.0.0.16/30
10.0.0.20/32
172.16.0.0/31" "$(bash solution.sh acl rules.txt)"
printf 'allow 1.0.0.0/8\ndeny any\nallow 2.0.0.0/8\n' > r2.txt
check acl_any "1.0.0.0/8" "$(bash solution.sh acl r2.txt)"
check acl_any_addr "2.3.4.5 deny 2" "$(bash solution.sh acl r2.txt 2.3.4.5)"
printf 'deny 0.0.0.0-9.255.255.255\nallow any\n' > r3.txt
check acl_allow_rest "10.0.0.0/7
12.0.0.0/6
16.0.0.0/4
32.0.0.0/3
64.0.0.0/2
128.0.0.0/1" "$(bash solution.sh acl r3.txt)"
printf 'allow 10.0.0.0-10.0.0.1\nallow 10.0.0.2/31\nallow 255.255.255.255\n' > r4.txt
check acl_adjacent_merge "10.0.0.0/30
255.255.255.255/32" "$(bash solution.sh acl r4.txt)"
printf 'deny any\n' > r5.txt
check acl_nothing "0:" "$(bash solution.sh acl r5.txt; echo "$?:")"
printf 'allow 1.1.1.1\npermit 2.2.2.2\n' > bad1.txt
out=$(bash solution.sh acl bad1.txt 1.1.1.1 2>err); rc=$?
check acl_bad_rule "1::bad1.txt:2: invalid rule" "$rc:$out:$(cat err)"
for bad in "allow" "allow 1.2.3.4 extra" "deny 1.2.3.4/40" "allow any 1.2.3.4" "Allow 1.2.3.4" "allow anything"; do
    printf '%s\n' "$bad" > bad.txt
    check "acl bad [$bad]" 1 "$(bash solution.sh acl bad.txt >/dev/null 2>&1; echo $?)"
done
check acl_bad_addr 2 "$(bash solution.sh acl rules.txt 10.0.0.1 10.0.0.256 >/dev/null 2>&1; echo $?)"
check acl_missing 2 "$(bash solution.sh acl nope.txt 1.1.1.1 >/dev/null 2>&1; echo $?)"
check bad_subcommand 2 "$(bash solution.sh bogus >/dev/null 2>&1; echo $?)"
finish
