#!/bin/zsh
# Stage the committed AP test fixtures into /tmp so the SANDBOXED medit build can
# open them. medit's sandbox (files.user-selected only) blocks opening files from
# the repo path even via LaunchServices, but /tmp is reachable. Run before the
# keyboard-scroll plans. One job: stage fixtures.
set -e
SRC="${0:A:h}/fixtures"
for f in long.txt long.md mw-a.txt mw-b.txt open-a.txt open-b.txt open-c.txt table-test.md; do
  cp "$SRC/$f" "/tmp/medit-ap-$f"
done
cp "$SRC/table-test.md" /tmp/table-test.md
# Folder fixture for the sidebar/open-into-tabs plans: a clean copy in /tmp so the
# tree is deterministic (and reachable by the Debug build).
rm -rf /tmp/medit-ap-folder
cp -R "$SRC/open-folder" /tmp/medit-ap-folder
echo "staged: /tmp/medit-ap-{long.txt,long.md,mw-a.txt,mw-b.txt,open-a.txt,open-b.txt,open-c.txt} + /tmp/medit-ap-folder/"
