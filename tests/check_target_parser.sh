#!/bin/sh
set -eu

fixture="${1:-tests/target_lines_sample.txt}"
count=$(awk '
{
	line=$0
	gsub(/^[ \t\r\n]+/, "", line)
	gsub(/[ \t\r\n]+$/, "", line)
	if (line == "") next
	if (substr(line, 1, 1) == "#") next
	count++
}
END { print count + 0 }
' "$fixture")

if [ "$count" != "2" ]; then
	echo "expected 2 target lines, got $count"
	exit 1
fi

tmp="${TMPDIR:-/tmp}/rckangaroo-mt-targets.$$"
python3 macos/prepare_targets.py "$fixture" -o "$tmp" >/dev/null
validated=$(wc -l < "$tmp" | tr -d ' ')
rm -f "$tmp"

if [ "$validated" != "2" ]; then
	echo "expected 2 validated targets, got $validated"
	exit 1
fi

echo "target parser fixture ok"
