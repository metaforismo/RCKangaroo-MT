#!/bin/sh
set -eu

challenge="challenges/rckmetal"

if [ ! -f ".gitmodules" ] || ! grep -q "tools/benchforge" ".gitmodules"; then
	printf '%s\n' "Benchforge submodule is not configured at tools/benchforge"
	exit 1
fi

for path in \
	"challenge.json" \
	"$challenge/package.json" \
	"$challenge/bin/rckmetal.js" \
	"$challenge/harness/test.js" \
	"$challenge/harness/score.js" \
	"$challenge/harness/verify.js" \
	"$challenge/README.md" \
	"$challenge/SKILL.md"
do
	if [ ! -f "$path" ]; then
		printf 'missing %s\n' "$path"
		exit 1
	fi
done

node <<'NODE'
const fs = require("fs");
const spec = JSON.parse(fs.readFileSync("challenge.json", "utf8"));
function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}
assert(spec.id === "rckmetal", "challenge id must be rckmetal");
assert(spec.cli === "rckmetal", "challenge cli must be rckmetal");
assert(spec.score?.direction === "maximize", "score must maximize throughput");
assert(spec.score?.primaryMetric === "ops_per_sec", "primary metric must be ops_per_sec");
assert(spec.commands?.test === "node challenges/rckmetal/harness/test.js", "public test command mismatch");
assert(spec.commands?.score === "node challenges/rckmetal/harness/score.js", "score command mismatch");
assert(spec.commands?.verify === "node challenges/rckmetal/harness/verify.js", "verifier command mismatch");
assert(Array.isArray(spec.editablePaths) && spec.editablePaths.includes("macos/MetalField.mm"), "MetalField.mm editable path missing");
assert(Array.isArray(spec.editablePaths) && !spec.editablePaths.includes("macos/**"), "editable paths must not bundle generated macos/rck_macos");
assert(Array.isArray(spec.forbiddenPaths) && spec.forbiddenPaths.includes(".benchforge/**"), "benchforge store must be forbidden");
assert(Array.isArray(spec.forbiddenPaths) && spec.forbiddenPaths.includes("challenges/rckmetal/harness/**"), "harness must be forbidden");
assert(spec.source?.repository === "https://github.com/metaforismo/RCKangaroo-MT", "source repository mismatch");
NODE

if ! grep -q "BENCHFORGE_CORE_CLI" "$challenge/bin/rckmetal.js"; then
	printf '%s\n' "rckmetal wrapper must support BENCHFORGE_CORE_CLI fallback"
	exit 1
fi

if ! grep -q "tools/benchforge/packages/core/src/cli.js" "$challenge/bin/rckmetal.js"; then
	printf '%s\n' "rckmetal wrapper must use the tools/benchforge submodule"
	exit 1
fi

if ! grep -q "benchforge-rckmetal-run" Makefile; then
	printf '%s\n' "Makefile must expose benchforge-rckmetal-run"
	exit 1
fi

if ! grep -q "^/.benchforge/" .gitignore; then
	printf '%s\n' "challenge-local Benchforge store must be ignored"
	exit 1
fi

printf '%s\n' "benchforge rckmetal challenge layout ok"
