import { spawnSync } from "node:child_process";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

export const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");

export function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    cwd: repoRoot,
    encoding: "utf8",
    env: { ...process.env, ...(options.env ?? {}) }
  });
  if (result.status !== 0) {
    const rendered = [result.stdout, result.stderr].filter(Boolean).join("\n");
    throw new Error(`${command} ${args.join(" ")} failed with status ${result.status}\n${rendered}`);
  }
  return result;
}

export function parseJsonStdout(result) {
  const lines = result.stdout.trim().split("\n").filter(Boolean);
  const jsonLine = [...lines].reverse().find((line) => line.trim().startsWith("{"));
  if (!jsonLine) {
    throw new Error(`command did not emit JSON\n${result.stdout}\n${result.stderr}`);
  }
  return JSON.parse(jsonLine);
}

export function median(values) {
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.floor(sorted.length / 2)];
}

export function assertBenchResult(result, expected) {
  if (result.backend !== "metal") throw new Error(`unexpected backend ${result.backend}`);
  if (result.operation !== "jacobian_affine_walk_jump_table") throw new Error(`unexpected operation ${result.operation}`);
  if (result.correctness !== true) throw new Error("benchmark correctness was not true");
  if (result.skipped !== false) throw new Error("Metal benchmark was skipped");
  if (result.distance_tracking !== "uint64") throw new Error("distance tracking missing");
  if (result.dp_tracking !== "projective_x_limb0") throw new Error("DP tracking missing");
  for (const [key, value] of Object.entries(expected)) {
    if (result[key] !== value) {
      throw new Error(`${key} mismatch: expected ${value}, got ${result[key]}`);
    }
  }
}
