#!/bin/bash
# Validate generated ufw user rules files before they replace the live ones.
# Used as file.managed check_cmd: Salt appends the temp file with the new contents as the last argument,
# so the state passes extra files (the other generated rules file) first and every file given is checked.
# Prints nothing and exits 0 when all files look like ufw writes them: *filter ... ### RULES ### ... COMMIT, no CR.
rc=0
for f in "$@"; do
  if [ ! -s "$f" ]; then echo "invalid: $f is missing or empty" >&2; rc=1; continue; fi
  head -n 1 "$f" | grep -qx '\*filter' || { echo "invalid: $f does not start with *filter" >&2; rc=1; }
  grep -qx '### RULES ###' "$f" || { echo "invalid: $f has no ### RULES ### line" >&2; rc=1; }
  tail -n 1 "$f" | grep -qx 'COMMIT' || { echo "invalid: $f does not end with COMMIT" >&2; rc=1; }
  if grep -q $'\r' "$f"; then echo "invalid: $f contains CR characters (CRLF)" >&2; rc=1; fi
done
exit $rc
