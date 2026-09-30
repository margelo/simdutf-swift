#!/usr/bin/env python3
"""Build both variants, then run serial measurements with alternating build order."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--samples", type=int, default=11)
parser.add_argument("--sample-ms", type=float, default=8)
parser.add_argument("--repeats", type=int, default=2)
parser.add_argument("--skip-build", action="store_true")
parser.add_argument("--output-dir", type=Path, default=ROOT / "Results" / "local")
parser.add_argument("--scratch-root", type=Path,
                    default=Path(tempfile.gettempdir()) / "simdutf-public-bench")
args = parser.parse_args()
if args.samples < 1:
    parser.error("--samples must be at least 1")
if args.repeats < 1:
    parser.error("--repeats must be at least 1")
if not args.sample_ms > 0:
    parser.error("--sample-ms must be greater than 0")
OUTPUT = args.output_dir.resolve()
OUTPUT.mkdir(parents=True, exist_ok=True)

def build_command(mode):
    command = ["xcrun", "swift", "build", "--build-system", "swiftbuild", "--package-path", str(ROOT),
               "--scratch-path", str(args.scratch_root) + "-" + mode, "-c", "release"]
    if mode == "o3":
        command += ["-Xcxx", "-O3"]
    return command

executables = {}
for mode in ("default", "o3"):
    command = build_command(mode)
    if not args.skip_build:
        print("Building", mode, flush=True)
        with (OUTPUT / (mode + "-build.log")).open("w") as log:
            subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, check=True)
    output = subprocess.check_output(command + ["--show-bin-path"], text=True)
    executables[mode] = Path(output.strip().splitlines()[-1]) / "UnicodeBench"
    if not executables[mode].is_file():
        raise RuntimeError(f"Missing executable: {executables[mode]}")

manifest = []
for repeat in range(1, args.repeats + 1):
    order = ("default", "o3") if repeat % 2 else ("o3", "default")
    for mode in order:
        stem = f"{mode}-run{repeat}"
        command = [str(executables[mode]), str(args.samples), str(args.sample_ms)]
        if repeat % 2 == 0:
            command.append("--reverse")
        print("Measuring", stem, flush=True)
        start = time.time()
        with (OUTPUT / (stem + ".json")).open("w") as data:
            with (OUTPUT / (stem + ".log")).open("w") as log:
                subprocess.run(command, stdout=data, stderr=log, check=True)
        manifest.append({"mode": mode, "repeat": repeat, "command": command,
                         "startedUnix": start, "elapsedSeconds": time.time() - start})
        (OUTPUT / "runs.json").write_text(json.dumps(manifest, indent=2) + "\n")
        print("Finished", stem, "in", round(manifest[-1]["elapsedSeconds"], 1), "s", flush=True)

analysis = ROOT / "analysis.py"
if analysis.is_file():
    command = ["python3", str(analysis), "--results-dir", str(OUTPUT),
               "--output-dir", str(OUTPUT)]
    for run in manifest:
        stem = f"{run['mode']}-run{run['repeat']}"
        command += ["--input", f"{run['mode']}={OUTPUT / (stem + '.json')}"]
    subprocess.run(command, cwd=ROOT, check=True)
