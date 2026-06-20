#!/usr/bin/env node
import { access } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(here, "../../..");
process.env.BENCHFORGE_CHALLENGE_ROOT = repoRoot;

const coreCandidates = [
  resolve(repoRoot, "tools/benchforge/packages/core/src/cli.js"),
  process.env.BENCHFORGE_CORE_CLI
].filter(Boolean);

let lastError = null;
for (const candidate of coreCandidates) {
  try {
    await access(candidate);
    await import(pathToFileURL(candidate).href);
    lastError = null;
    break;
  } catch (error) {
    lastError = error;
  }
}

if (lastError) {
  throw new Error("Could not find Benchforge core CLI. Run `git submodule update --init tools/benchforge` or set BENCHFORGE_CORE_CLI.");
}
