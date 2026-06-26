#!/bin/zsh
# Stage the committed AP test fixtures into /tmp so the SANDBOXED medit build can
# open them. medit's sandbox (files.user-selected only) blocks opening files from
# the repo path even via LaunchServices, but /tmp is reachable. Run before the
# keyboard-scroll plans. One job: stage fixtures.
set -e
SRC="${0:A:h}/fixtures"
for f in long.txt long.md mw-a.txt mw-b.txt; do
  cp "$SRC/$f" "/tmp/medit-ap-$f"
done
echo "staged: /tmp/medit-ap-{long.txt,long.md,mw-a.txt,mw-b.txt}"
