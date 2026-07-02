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

tmpdir="${TMPDIR:-/tmp}/rckangaroo-mt-targets.$$"
mkdir "$tmpdir"
trap 'rm -rf "$tmpdir"' EXIT INT TERM

tmp="$tmpdir/targets.cleaned.txt"
python3 macos/prepare_targets.py "$fixture" -o "$tmp" >/dev/null
validated=$(wc -l < "$tmp" | tr -d ' ')

if [ "$validated" != "2" ]; then
	echo "expected 2 validated targets, got $validated"
	exit 1
fi

duplicate_fixture="$tmpdir/duplicates.txt"
printf '%s\n%s\n' \
	"0279BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798" \
	"0279BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798" \
	> "$duplicate_fixture"

deduped="$tmpdir/deduped.txt"
python3 macos/prepare_targets.py "$duplicate_fixture" -o "$deduped" >/dev/null
deduped_count=$(wc -l < "$deduped" | tr -d ' ')
if [ "$deduped_count" != "1" ]; then
	echo "expected duplicate target to be removed, got $deduped_count lines"
	exit 1
fi

kept="$tmpdir/kept.txt"
python3 macos/prepare_targets.py "$duplicate_fixture" -o "$kept" --keep-duplicates >/dev/null
kept_count=$(wc -l < "$kept" | tr -d ' ')
if [ "$kept_count" != "2" ]; then
	echo "expected --keep-duplicates to preserve 2 lines, got $kept_count"
	exit 1
fi

invalid_fixture="$tmpdir/invalid.txt"
printf '%s\n%s\n' \
	"0279BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798" \
	"not-a-key" \
	> "$invalid_fixture"

invalid_out="$tmpdir/invalid-out.txt"
if python3 macos/prepare_targets.py "$invalid_fixture" -o "$invalid_out" >"$tmpdir/invalid.stdout" 2>"$tmpdir/invalid.stderr"; then
	echo "expected invalid target file to fail"
	exit 1
fi

if [ -e "$invalid_out" ]; then
	echo "invalid target failure left an output file"
	exit 1
fi

if find "$tmpdir" -name ".invalid-out.txt.*.tmp" | grep -q .; then
	echo "invalid target failure left a temporary output file"
	exit 1
fi

echo "target parser fixture ok"
