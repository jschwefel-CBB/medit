#!/bin/zsh
# Stage the AP test fixtures into /tmp so the medit build can open them. medit's
# sandbox (files.user-selected only) blocks opening files from the repo path even
# via LaunchServices, but /tmp is reachable; the Debug build is unsandboxed but
# still opens the same /tmp paths for consistency. Run before the AP test suite.
# One job: stage fixtures.
#
# Two kinds of fixture:
#   1. Committed text fixtures in ./fixtures — copied to /tmp/medit-ap-<name>.
#   2. Adversarial fixtures GENERATED here at stage time and never committed
#      (they'd violate the no-large-files / transient-artifact rules): a zero-byte
#      file, a 1 MB "large" file, and a permission-denied (chmod 000) file. These
#      are recreated every run and can be removed with `stage-fixtures.sh --clean`.
set -e
SRC="${0:A:h}/fixtures"

if [[ "$1" == "--clean" ]]; then
  rm -f /tmp/medit-ap-*.txt /tmp/medit-ap-*.md /tmp/medit-ap-noext \
        /tmp/medit-ap-zero-byte.txt /tmp/medit-ap-large.txt /tmp/medit-ap-denied.txt \
        /tmp/table-test.md
  rm -rf /tmp/medit-ap-folder
  echo "cleaned staged fixtures"
  exit 0
fi

# 1. Committed text fixtures.
for f in long.txt long.md mw-a.txt mw-b.txt open-a.txt open-b.txt open-c.txt \
         table-test.md copy-test.md unicode-content.md invalid-utf8.txt \
         regex-metachars.txt noext noop.md autolink.md; do
  cp "$SRC/$f" "/tmp/medit-ap-$f"
done
# table-test.md also needs a bare /tmp/table-test.md path (used by markdown-table-preview.json)
cp "$SRC/table-test.md" /tmp/table-test.md
# Folder fixture for the sidebar/open-into-tabs plans: a clean copy in /tmp so the
# tree is deterministic (and reachable by the Debug build).
rm -rf /tmp/medit-ap-folder
cp -R "$SRC/open-folder" /tmp/medit-ap-folder

# 2. Generated adversarial fixtures (NOT committed — created fresh each run).
# Zero-byte file: opens empty, must not crash.
: > /tmp/medit-ap-zero-byte.txt
# 1 MB of text (~19k lines): a bounded "large" file that must open within the plan
# timeout without hanging (edge-open-large-file.json). Deterministic content (no
# randomness) for repeatability, kept out of git (transient artifact rule). NOTE:
# this is intentionally 1 MB, not 5 MB+ — medit's file open is synchronous on the
# main thread, so a 5 MB file batched with another stalls window creation past any
# reasonable timeout (tracked as medit perf defect M1 in docs/autopilot-feedback.md).
# 1 MB exercises the large-document load path while staying reliably under timeout.
yes 'the quick brown fox jumps over the lazy dog 0123456789' | head -c 1048576 > /tmp/medit-ap-large.txt
# Permission-denied file: chmod 000 so the read fails; medit must degrade gracefully.
# rm -f first: a leftover chmod-000 file from a prior run can't be truncated by the
# redirect (permission denied), which would abort the script under `set -e`. Unlinking
# it (the /tmp dir is writable) always succeeds, so re-staging is idempotent.
rm -f /tmp/medit-ap-denied.txt
printf 'you should not be able to read this\n' > /tmp/medit-ap-denied.txt
chmod 000 /tmp/medit-ap-denied.txt

echo "staged committed fixtures + generated: zero-byte, large (1MB), denied (chmod 000)"
echo "  clean up with: $0 --clean"
