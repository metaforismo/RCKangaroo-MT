import { assertBenchResult, parseJsonStdout, run } from "./common.js";

run("make", ["macos-check"]);

const result = run("./macos/rck_macos", [
  "metal-jacobian-jump-walk-bench",
  "--iterations", "2048",
  "--steps", "7",
  "--jumps", "9",
  "--dp-bits", "3",
  "--min-ms", "20"
]);

assertBenchResult(parseJsonStdout(result), {
  sample_count: 2048,
  steps_per_sample: 7,
  jump_count: 9,
  dp_bits: 3,
  distance_checksum: "0xbab72b58ebefa9dc",
  dp_count: 249,
  dp_checksum: "0x4a7f2853a4a9f546"
});

console.log("rckmetal: verifier checks passed");
