export RUST_BACKTRACE=full

alias gpu="git push origin -u \$(git symbolic-ref --short HEAD)"
alias flush-dns-mac="sudo dscacheutil -flushcache;sudo killall -HUP mDNSResponder"

#
# Run a command N times.
#
# ## Examples
# 
# Echoes "1" 5 times:
# ```shell
#   runx 5 echo "1"
# ```
#
function runx() {
  for ((i = 0; i < $1; i++)) {
    # echo "\n-- runx: $i\n";
    ${*:2}; 
  }
}

#
# Same as `runx` but exits if command run yields unsuccessful exit code
#
# ## Examples
# 
# Runs `cargo t -- dns_map::tests::resolve::removes_expired_records_while_adds` command
# 5 times and exits on first unsuccessful ruslt:
# ```shell
#   testx 5 cargo t -- dns_map::tests::resolve::removes_expired_records_while_adds
# ```
#
function testx() {
  echo -e "\n 🏁 $1 times\n";
  for ((i = 1; i <= $1; i++)) {
    echo -e " 🏃 $i \n";
    # execute command on current iteration
    ${*:2};
    TESTX_EXIT_CODE=$?;
    # if the current execution was unsuccessful,
    # exit with the same exit code
    if [[ $TESTX_EXIT_CODE != 0 ]]; then
      echo -e "\n 💣 $i \n";
      return $TESTX_EXIT_CODE;
    fi
  }

  echo -e "✅ all $1 done";
}
