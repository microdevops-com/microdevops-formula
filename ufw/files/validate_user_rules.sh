#!/bin/bash
# Validate generated ufw user rules files before they replace the live ones.
# Used as file.managed check_cmd: Salt appends the temp file with the new contents as the last argument,
# so the state passes extra files (the other generated rules file) first and every file given is checked.
# Prints nothing and exits 0 when all files look like ufw writes them: *filter ... ### RULES ### ... COMMIT, no CR.
# On failure it prints "ERROR: ..." to stderr: Salt puts it into the state comment, so salt_cmd.sh (grep ERROR)
# flags the run even without the red failed state. A clean run prints nothing, hence no false ERROR.
rc=0
for f in "$@"; do
  if [ ! -s "$f" ]; then echo "ERROR: $f is missing or empty" >&2; rc=1; continue; fi
  head -n 1 "$f" | grep -qx '\*filter' || { echo "ERROR: $f does not start with *filter" >&2; rc=1; }
  grep -qx '### RULES ###' "$f" || { echo "ERROR: $f has no ### RULES ### line" >&2; rc=1; }
  tail -n 1 "$f" | grep -qx 'COMMIT' || { echo "ERROR: $f does not end with COMMIT" >&2; rc=1; }
  if grep -q $'\r' "$f"; then echo "ERROR: $f contains CR characters (CRLF)" >&2; rc=1; fi
done
exit $rc
