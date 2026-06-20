#!/bin/sh
set -eu

docs="docs/QUALITY_GATES.md docs/QUALITY_GATES.it.md"
required_terms='target allowed edits correctness oracle performance metric baseline gate hidden tests reproducibility logging submission rollback'

for doc in $docs; do
	if [ ! -f "$doc" ]; then
		printf 'missing quality gate doc: %s\n' "$doc"
		exit 1
	fi

	for term in $required_terms; do
		if ! grep -qi "$term" "$doc"; then
			printf 'quality gate doc %s missing required term: %s\n' "$doc" "$term"
			exit 1
		fi
	done
done

if ! grep -q "check-quality-gates" Makefile; then
	printf '%s\n' "Makefile should expose check-quality-gates"
	exit 1
fi

if ! grep -q "check-quality-gates" Makefile || ! grep -q "macos-check:.*check-quality-gates" Makefile; then
	printf '%s\n' "macos-check should depend on check-quality-gates"
	exit 1
fi
