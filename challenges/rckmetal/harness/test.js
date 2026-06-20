import { run } from "./common.js";

run("make", ["macos-build"]);
run("./macos/rck_macos", ["metal-smoke"]);
run("./macos/rck_macos", ["metal-jacobian-jump-walk-test"]);

console.log("rckmetal: public Metal smoke and jump-walk correctness checks passed");
