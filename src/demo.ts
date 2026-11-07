import { execFileSync } from "node:child_process";
import { rmSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const DEMO_DIR = join(REPO_ROOT, "demo-inbox");

rmSync(DEMO_DIR, { recursive: true, force: true });
execFileSync("swift", [join(REPO_ROOT, "swift", "MakeDemoSamples.swift"), DEMO_DIR], {
  stdio: "inherit",
});

execFileSync(process.execPath, ["run", join(REPO_ROOT, "src", "cli.ts"), DEMO_DIR], {
  stdio: "inherit",
});
