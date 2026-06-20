import { writeFileSync } from "node:fs";
import { performance } from "node:perf_hooks";
import os from "node:os";
import { assertBenchResult, median, parseJsonStdout, run } from "./common.js";

const expected = {
  sample_count: 16384,
  steps_per_sample: 8,
  jump_count: 16,
  dp_bits: 4,
  distance_checksum: "0xa45f471493cace2f",
  dp_count: 1000,
  dp_checksum: "0x30a7914972cba014"
};

run("make", ["macos-build"]);

const samples = [];
for (let index = 0; index < 3; index += 1) {
  const started = performance.now();
  const result = run("./macos/rck_macos", [
    "metal-jacobian-jump-walk-bench",
    "--iterations", "16384",
    "--steps", "8",
    "--jumps", "16",
    "--dp-bits", "4",
    "--min-ms", "50"
  ]);
  const elapsedMs = performance.now() - started;
  const parsed = parseJsonStdout(result);
  assertBenchResult(parsed, expected);
  samples.push({ ...parsed, external_ms: elapsedMs });
}

const opsSamples = samples.map((sample) => sample.ops_per_sec);
const score = median(opsSamples);
const best = samples.reduce((current, sample) => sample.ops_per_sec > current.ops_per_sec ? sample : current, samples[0]);

writeFileSync("score.json", JSON.stringify({
  score,
  metrics: {
    ops_per_sec: score,
    ops_per_sec_samples: opsSamples,
    sample_runs: samples.length,
    correctness: true,
    distance_checksum: best.distance_checksum,
    dp_count: best.dp_count,
    dp_checksum: best.dp_checksum,
    iterations: best.iterations,
    sample_count: best.sample_count,
    steps_per_sample: best.steps_per_sample,
    jump_count: best.jump_count,
    dp_bits: best.dp_bits,
    threadgroup_limit: best.threadgroup_limit,
    thread_execution_width: best.thread_execution_width,
    max_threads_per_threadgroup: best.max_threads_per_threadgroup,
    threads_per_threadgroup: best.threads_per_threadgroup,
    min_ms: best.min_ms,
    external_ms_samples: samples.map((sample) => sample.external_ms),
    platform: os.platform(),
    arch: os.arch(),
    cpus: os.cpus().map((cpu) => cpu.model)[0] ?? "unknown"
  }
}, null, 2));
