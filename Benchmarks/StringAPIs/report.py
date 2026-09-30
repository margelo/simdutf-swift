#!/usr/bin/env python3
"""Generate a readable publication report from the raw-data summary."""
import argparse
import json
import math
import os
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--results-dir", type=Path, default=ROOT / "Results" / "local")
parser.add_argument("--output", type=Path)
args = parser.parse_args()
summary = json.loads((args.results_dir / "summary.json").read_text())
output = args.output or args.results_dir / "README.md"
metadata_path = args.results_dir / "metadata.json"
backend_note = ""
if metadata_path.is_file():
    metadata = json.loads(metadata_path.read_text())
    backend_note = " and its " + metadata["package"]["active_backend"]["description"] + " backend"
    provenance = (f"Measured on {metadata['date']}: {metadata['hardware']['cpu']}, "
                  f"macOS {metadata['operating_system']['version']} ({metadata['operating_system']['build']}), "
                  f"Swift {metadata['toolchain']['swift_version']}, Xcode {metadata['toolchain']['xcode_version']}.")
else:
    provenance = "Generated from local measurement samples; hardware and toolchain metadata were not recorded in this results directory."
results_link = os.path.relpath(args.results_dir.resolve(), output.resolve().parent)
repeat_count = len(summary["builds"]["default"]["inputs"])
pooled_samples = summary["builds"]["default"]["sample_count"] // summary["builds"]["default"]["row_count"]
samples_per_repeat = pooled_samples // repeat_count
runs_path = args.results_dir / "runs.json"
runs = json.loads(runs_path.read_text()) if runs_path.is_file() else []
target_ms = runs[0]["command"][2] if runs else "8 (the default)"
check_counts = []
for log in args.results_dir.glob("*-run*.log"):
    match = re.search(r"PASS (\d+) full-content checks", log.read_text())
    if match:
        check_counts.append(int(match.group(1)))
checks_text = (f"Each process passed {check_counts[0]} full-output checks" if check_counts and len(set(check_counts)) == 1
               else "The supplied process logs record full-output check counts")


operations = ["UTF16->String", "UTF32->String", "String->UTF16", "String->UTF32"]
labels = {"UTF16->String": "UTF-16 buffer → String", "UTF32->String": "UTF-32 buffer → String",
          "String->UTF16": "String → UTF-16 buffer", "String->UTF32": "String → UTF-32 buffer"}

def factor(value):
    return f"{value:.2f}×"

def span(stat):
    return f"{stat['min_speedup']:.2f}–{stat['max_speedup']:.2f}×"

def geometric_mean(values):
    return math.exp(sum(map(math.log, values)) / len(values))

def aggregate(mode, kind):
    stats = [summary["builds"][mode]["operations"][op]["representative_unicode"][kind] for op in operations]
    return geometric_mean([stat["geometric_mean_speedup"] for stat in stats])

lines = [
    "# simdutf-swift 1.0.1 String API benchmarks",
    "",
    "> **DO NOT MERGE:** This draft PR is an archive of benchmark code and measurements. "
    "It is intended to remain draft and unmerged. The harness benchmarks the released 1.0.1 dependency, independently of changes to the parent package.",
    "",
    provenance + " The exact remote 1.0.1 tag resolves to `4f98b5b16c8b1d9c7d77d88395c2a50b74be0607`, using simdutf 9.2.1" + backend_note + ".",
    "",
    f"Across 64 valid, non-ASCII UTF-16/UTF-32 conversion cases, the geometric-mean speedup over ordinary Swift APIs was **{factor(aggregate('default', 'normal'))}** "
    f"with the default Swift Build release settings, and **{factor(aggregate('o3', 'normal'))}** with C++ `-O3`. "
    "These are equally weighted microbenchmark cases, not a prediction of any application's average speedup.",
    "",
    "The representative Unicode range below covers Latin text, CJK, emoji, and mixed text at nominal sizes of 1,024 through 1,048,576 UTF-16 code units. "
    "Each operation has 16 such cases. The peak column considers every nonempty valid case, including ASCII, and names the winning input. "
    "A factor of 2× means half the conversion time. Ranges are minimum and maximum case-median speedups across the listed corpora and sizes, not confidence intervals.",
    "",
]

for mode, title in [("default", "Default release: Swift `-O`, C++ `-Os`"),
                    ("o3", "Opt-in comparison: Swift `-O`, C++ `-O3`")]:
    lines += [f"## {title}", "", "| Conversion | Unicode geometric mean | Unicode range | Peak | Peak input |",
              "|---|---:|---:|---:|---|"]
    for op in operations:
        data = summary["builds"][mode]["operations"][op]
        stat = data["representative_unicode"]["normal"]
        peak = data["valid_peak_candidates"]["normal"]["fastest_case"]
        lines.append(f"| {labels[op]} | {factor(stat['geometric_mean_speedup'])} | {span(stat)} | {factor(peak['simdutf_speedup'])} | "
                     f"{peak['profile']}, {peak['utf16Units']:,} UTF-16 units / {peak['utf32Units']:,} UTF-32 units |")
    lines += ["", "The ordinary baseline is `String(decoding:as:)` for constructors, `Array(string.utf16)` for UTF-16 output, "
              "and `string.unicodeScalars.map { $0.value }` for UTF-32 output, followed by borrowing the resulting contiguous buffer.", ""]

lines += ["## Comparison with stronger Swift alternatives", "",
          "Outgoing conversions also include temporary storage filled from the UTF-16/scalar views, Swift's public `transcode`, and a known-valid "
          "`UTF8Span` scalar iterator. For each case, this comparison chooses whichever measured standard-library implementation was fastest. "
          "Constructor standard-library comparisons remain `String(decoding:as:)`. Foundation's UTF-16 constructor is reported separately below.", "",
          "| Conversion | Default Unicode range | Default geometric mean | `-O3` Unicode range | `-O3` geometric mean |",
          "|---|---:|---:|---:|---:|"]
for op in operations:
    a = summary["builds"]["default"]["operations"][op]["representative_unicode"]["strongest_standard"]
    b = summary["builds"]["o3"]["operations"][op]["representative_unicode"]["strongest_standard"]
    lines.append(f"| {labels[op]} | {span(a)} | {factor(a['geometric_mean_speedup'])} | {span(b)} | {factor(b['geometric_mean_speedup'])} |")
lines += ["", f"Across the same 64 cases, the geometric means against these stronger alternatives are {factor(aggregate('default', 'strongest_standard'))} "
          f"and {factor(aggregate('o3', 'strongest_standard'))}, respectively. "
          "Array comparisons are useful for ordinary calling code, but their larger gains include differences in allocation and view iteration as well as SIMD transcoding.", ""]

lines += ["## Exact peak timings against ordinary APIs", "",
          "| Build | Conversion | Input profile / bytes | Swift median | simdutf-swift median | Speedup | Ratio in each repeat |",
          "|---|---|---|---:|---:|---:|---|"]
for mode in ("default", "o3"):
    for op in operations:
        peak = summary["builds"][mode]["operations"][op]["valid_peak_candidates"]["normal"]["fastest_case"]
        repeats = ", ".join(factor(run["speedup"]) for run in peak["per_run"].values())
        lines.append(f"| {mode} | {labels[op]} | {peak['profile']} / {peak['inputBytes']:,} B | "
                     f"{peak['comparator_median_ns']/1000:.3f} µs | {peak['simdutf_median_ns']/1000:.3f} µs | {factor(peak['simdutf_speedup'])} | {repeats} |")
lines += ["", "Input bytes count the incoming C-style buffer or the native String's UTF-8 storage. "
          "The source String's storage need not have the same size as its destination UTF-16/UTF-32 buffer.", ""]

lines += ["## Small inputs, UTF-8, Foundation, and malformed input", "",
          "| Build | Outgoing conversion | Fastest Swift comparison, 7/16 nominal units |",
          "|---|---|---:|"]
for mode in ("default", "o3"):
    for op in ("String->UTF16", "String->UTF32"):
        stat = summary["builds"][mode]["operations"][op]["small_nonempty"]["strongest_standard"]
        lines.append(f"| {mode} | {labels[op]} | {span(stat)} |")
lines += ["", "Values below 1× mean simdutf-swift was slower. Tiny strings can favor a standard Swift temporary-buffer loop; "
          "the package does not win every case. Empty strings are recorded separately in the data and excluded from headline figures.", ""]
for mode in ("default", "o3"):
    data = summary["builds"][mode]["operations"]
    utf8 = data["UTF8->String"]["valid_peak_candidates"]["normal"]
    f = data["UTF16->String"]["representative_unicode"]["foundation"]
    f_ascii = data["UTF16->String"]["ascii"]["foundation"]["fastest_case"]
    bad16 = data["UTF16->String"]["malformed"]["normal"]
    bad32 = data["UTF32->String"]["malformed"]["normal"]
    lines += [f"- **{mode}:** UTF-8 decoding control {span(utf8)}. `String(decodingUTF8:)` forwards to the same standard Swift decoder; this is no SIMD speedup claim.",
              f"- **{mode}:** Compared with Foundation's `String(utf16CodeUnits:count:)` followed by UTF-8 materialization, representative Unicode speedups are {span(f)}, "
              f"with an ASCII peak of {factor(f_ascii['simdutf_speedup'])}. This comparison includes conversion that Foundation can defer until UTF-8 is borrowed.",
              f"- **{mode}:** Deliberately malformed UTF-16 {span(bad16)}; malformed UTF-32 {span(bad32)}. "
              "The latter uses the package's standard Swift replacement fallback; it is excluded from the valid-input headline."]

lines += ["", "## What is timed", "",
          "Each constructor creates an owned Swift String, borrows its UTF-8 storage into an opaque C sink, and destroys the output. "
          "This includes any Foundation-backed String's deferred UTF-8 materialization. Each outgoing API creates contiguous UTF-16/UTF-32 storage, "
          "borrows it into that sink, and releases the storage. The sink does not scan or retain the bytes.", "",
          "Input preparation and reference-output checks are outside timing. Outgoing inputs are prebuilt native Swift Strings. "
          "Strings contain counted data, including embedded nulls. No JavaScript, JSI, Hermes, React Native, network traffic, or engine allocation is involved. "
          "The benchmark does not cover Foundation-backed outgoing Strings, streaming ropes, cold caches, Latin-1/Base64 helpers, or every validation/append API.", "",
          "The five valid corpora repeat the exact patterns in `Sources/UnicodeBench/main.swift`. Nominal sizes are 0, 7, 16, 128, 1,024, 16,384, 262,144, and 1,048,576 UTF-16 units. "
          "A final high surrogate is removed when truncating a valid corpus; recorded byte/unit counts are authoritative. "
          "Malformed inputs are separate deterministic corpora. The same input is reused, so these are warm repeated-conversion measurements.", "",
          f"There are {repeat_count} fresh processes per build configuration, {samples_per_repeat} samples per variant per process, and 16 warmup iterations before adaptive iteration calibration. "
          f"Samples target {target_ms} ms; calibration accepts half that duration and caps the iteration count at 1,000,000. "
          "Variant order rotates per sample, alternate repeats reverse that order, and configuration order alternates between repeats. "
          f"Measurements run serially. Medians pool all {pooled_samples} ns/op samples per variant; per-run medians and ratios remain in the data. "
          + checks_text + ", including both package and comparison algorithms, outside timing.", "",
          "Swift code uses `-O` and whole-module optimization in both builds. This machine's default SwiftPM backend is Swift Build, whose C++ release setting was `-Os`. "
          "The second build adds `-Xcxx -O3`, so the final C++ optimization option is `-O3`. "
          "These results do not imply that every SwiftPM/Xcode integration chooses the same default C++ optimization level. "
          "The package dependency enables UTF8, UTF16, UTF32, and ASCII traits. See the recorded `metadata.json` for exact environment, revisions, and effective flags.", "",
          "## Reproduce", "",
          "With the same Xcode/Swift toolchain, run from the repository root:", "",
          "```sh", "cd Benchmarks/StringAPIs", "python3 run.py", "python3 report.py", "```", "",
          "The runner pins remote 1.0.1, builds both configurations before any timing, and invokes the analysis script when all measurement processes finish. "
          "It explicitly selects the Swift Build backend. Fresh measurements, build logs, summaries, and their generated report go into ignored `Results/local/`, "
          "so rerunning does not overwrite the recorded measurements. Results on other machines, OS releases, toolchains, optimizations, or storage representations can differ.", "",
          "To regenerate the archived tables from the recorded samples without rerunning timings:", "",
          "```sh", "python3 analysis.py --results-dir Results/1.0.1-m2-pro-swift6.4",
          "python3 report.py --results-dir Results/1.0.1-m2-pro-swift6.4 --output README.md", "```", "",
          "To check all outputs without timing:", "",
          "```sh", "<path-to-UnicodeBench> 11 8 --check-only", "```", "",
          "## Files", "",
          "- `Package.swift` / `Package.resolved`: exact dependency and feature selection.",
          "- `Sources/`: complete harness and opaque C sink.",
          "- `run.py`: serial measurement runner.",
          f"- [Results]({results_link}/): raw samples, logs, derived tables, and recorded environment metadata when available.",
          "- Corresponding `.log` files: preflight pass counts and process timings.",
          "- `analysis.py`: reproducible aggregation into `summary.json` and `cases.csv` within a results directory.",
          "- `report.py`: this report's generator.",
          "- `metadata.json`, `runs.json`: build/environment metadata and executed measurement commands.",
          ""]
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text("\n".join(lines))
print("Wrote", output)
