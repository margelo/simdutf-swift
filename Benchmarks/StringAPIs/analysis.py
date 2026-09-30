#!/usr/bin/env python3
"""Summarize UnicodeBench JSON without third-party dependencies.

Default inputs are default-run1/2.json and o3-run1/2.json in Results/local.
Select another collection with --results-dir, or override inputs with repeated
--input BUILD=FILE arguments. Outputs are summary.json and cases.csv in the
results directory unless --output-dir is supplied. Each case pools every sample from its repeated runs; ratios are
comparator median / simdutf median, so values above 1 favor simdutf.
"""

import argparse
import csv
import json
import math
from pathlib import Path
import statistics
import sys


ROOT = Path(__file__).resolve().parent
METADATA = ("inputBytes", "utf16Units", "utf32Units")
UNICODE_PROFILES = {"Latin", "CJK", "Emoji", "Mixed"}
NORMAL_BASELINES = {
    "UTF8->String": "swift-decoding",
    "UTF16->String": "swift-decoding",
    "UTF32->String": "swift-decoding",
    "String->UTF16": "swift-array",
    "String->UTF32": "swift-array",
}


def geometric_mean(values):
    return math.exp(statistics.fmean(math.log(value) for value in values))


def is_foundation(name):
    return name.startswith("foundation")


def is_malformed(profile):
    return profile.lower().startswith("malformed")


def portable_input_path(path):
    try:
        return str(path.resolve().relative_to(ROOT))
    except ValueError:
        return path.name


def load_cases(inputs):
    builds = {}
    for build, path in inputs:
        rows = json.loads(path.read_text())
        if not isinstance(rows, list) or not rows:
            raise ValueError(f"{path}: expected a nonempty list of benchmark rows")
        state = builds.setdefault(build, {"files": [], "cases": {}, "signatures": []})
        run = path.stem
        if run in [item["run"] for item in state["files"]]:
            raise ValueError(f"{build}: duplicate run name {run}")
        state["files"].append({"run": run, "path": portable_input_path(path)})
        signature = set()
        for row in rows:
            key = (row["operation"], row["profile"], row["nominalSize"])
            if any(not isinstance(row[field], int) or row[field] < 0
                   for field in ("nominalSize", *METADATA)):
                raise ValueError(f"{path}: invalid size/count in {key}")
            implementation = row["implementation"]
            entry = (*key, implementation)
            if entry in signature:
                raise ValueError(f"{path}: duplicate benchmark row {entry}")
            signature.add(entry)
            samples = [float(value) for value in row["samplesNs"]]
            if not samples or any(not math.isfinite(value) or value <= 0 for value in samples):
                raise ValueError(f"{path}: expected finite positive samples in {entry}")
            if not isinstance(row["iterations"], int) or row["iterations"] <= 0:
                raise ValueError(f"{path}: invalid iteration count in {entry}")
            metadata = {field: row[field] for field in METADATA}
            case = state["cases"].setdefault(key, {
                "operation": key[0], "profile": key[1], "nominalSize": key[2],
                **metadata, "implementations": {},
            })
            if any(case[field] != metadata[field] for field in METADATA):
                raise ValueError(f"{path}: repeated case {key} changed its actual input sizes")
            data = case["implementations"].setdefault(implementation, {"samples": [], "runs": {}})
            data["samples"].extend(samples)
            data["runs"][run] = {
                "median_ns": statistics.median(samples),
                "iterations": row["iterations"], "sample_count": len(samples),
            }
        state["signatures"].append(signature)
    for build, state in builds.items():
        if any(signature != state["signatures"][0] for signature in state["signatures"][1:]):
            raise ValueError(f"{build}: repeated runs contain different cases/variants; do not pool pilot data")
        for case in state["cases"].values():
            if "simdutf" not in case["implementations"]:
                raise ValueError(f"{build}: no simdutf result for {case['operation']}/{case['profile']}/{case['nominalSize']}")
            for data in case["implementations"].values():
                data["median_ns"] = statistics.median(data["samples"])
                data["min_ns"] = min(data["samples"])
                data["max_ns"] = max(data["samples"])
            names = case["implementations"]
            normal = NORMAL_BASELINES.get(case["operation"])
            case["normal"] = normal if normal in names else None
            standard = [name for name in names if name != "simdutf" and not is_foundation(name)]
            foundation = [name for name in names if is_foundation(name)]
            case["strongest_standard"] = min(standard, key=lambda name: names[name]["median_ns"]) if standard else None
            case["foundation"] = min(foundation, key=lambda name: names[name]["median_ns"]) if foundation else None
    return builds


def comparison(case, comparator):
    if comparator is None:
        return None
    baseline = case["implementations"][comparator]
    simd = case["implementations"]["simdutf"]
    per_run = {
        run: {
            "comparator_median_ns": result["median_ns"],
            "simdutf_median_ns": simd["runs"][run]["median_ns"],
            "speedup": result["median_ns"] / simd["runs"][run]["median_ns"],
        }
        for run, result in baseline["runs"].items()
    }
    return {
        **{field: case[field] for field in ("operation", "profile", "nominalSize", *METADATA)},
        "comparator": comparator,
        "comparator_median_ns": baseline["median_ns"],
        "simdutf_median_ns": simd["median_ns"],
        "simdutf_speedup": baseline["median_ns"] / simd["median_ns"],
        "per_run": per_run,
    }


def summarize(cases, kind):
    comparisons = [comparison(case, case[kind]) for case in cases if case[kind] is not None]
    if not comparisons:
        return None
    ratios = [item["simdutf_speedup"] for item in comparisons]
    fastest = max(comparisons, key=lambda item: item["simdutf_speedup"])
    slowest = min(comparisons, key=lambda item: item["simdutf_speedup"])
    run_names = comparisons[0]["per_run"]
    per_run = {
        run: {
            "geometric_mean_speedup": geometric_mean([item["per_run"][run]["speedup"] for item in comparisons]),
            "min_speedup": min(item["per_run"][run]["speedup"] for item in comparisons),
            "max_speedup": max(item["per_run"][run]["speedup"] for item in comparisons),
        }
        for run in run_names
    }
    counts = {}
    for item in comparisons:
        counts[item["comparator"]] = counts.get(item["comparator"], 0) + 1
    return {
        "case_count": len(comparisons),
        "geometric_mean_speedup": geometric_mean(ratios),
        "min_speedup": min(ratios), "max_speedup": max(ratios),
        "simdutf_faster_cases": sum(value > 1 for value in ratios),
        "simdutf_median_ns_range": [min(item["simdutf_median_ns"] for item in comparisons),
                                   max(item["simdutf_median_ns"] for item in comparisons)],
        "comparator_case_counts": counts,
        "slowest_case": slowest, "fastest_case": fastest,
        "per_run": per_run,
        "max_repeat_speedup_spread": max(
            max(run["speedup"] for run in item["per_run"].values()) /
            min(run["speedup"] for run in item["per_run"].values())
            for item in comparisons
        ),
    }


def build_summary(builds):
    result = {
        "schema_version": 1,
        "methodology": {
            "pooled_median": "Median of all raw ns/conversion samples across repeated runs, not a median of run medians.",
            "speedup": "Comparator median / simdutf median; above 1 favors simdutf.",
            "normal_baselines": NORMAL_BASELINES,
            "strongest_standard": "Fastest pooled-median variant per case, excluding simdutf and foundation* variants.",
            "per_run_comparators": "Per-run ratios retain the comparator selected from pooled medians for each case.",
            "geometric_mean": "Equal weight for each case; not a workload-weighted real-world average.",
            "representative_unicode": "Latin/CJK/Emoji/Mixed, nominal UTF16-unit sizes 1024 through 1048576, valid input only.",
            "small": "Nonempty nominal sizes below 128; empty cases are separate.",
            "scope": "String APIs, including timed allocation/destruction and opaque buffer consumption; not raw-transcode-only timings.",
        },
        "builds": {},
    }
    for build, state in builds.items():
        cases = list(state["cases"].values())
        operations = {}
        for operation in sorted({case["operation"] for case in cases}):
            selected = [case for case in cases if case["operation"] == operation]
            valid = [case for case in selected if not is_malformed(case["profile"])]
            groups = {
                "representative_unicode": [case for case in valid if case["profile"] in UNICODE_PROFILES and 1024 <= case["nominalSize"] <= 1048576],
                "ascii": [case for case in valid if case["profile"] == "ASCII" and case["nominalSize"] > 0],
                "valid_peak_candidates": [case for case in valid if case["nominalSize"] > 0],
                "small_nonempty": [case for case in valid if 0 < case["nominalSize"] < 128],
                "empty": [case for case in valid if case["nominalSize"] == 0],
                "malformed": [case for case in selected if is_malformed(case["profile"]) and case["nominalSize"] > 0],
            }
            operations[operation] = {
                "case_count": len(selected),
                "implementations": sorted({name for case in selected for name in case["implementations"]}),
                **{group: {kind: summarize(group_cases, kind)
                           for kind in ("normal", "strongest_standard", "foundation")}
                   for group, group_cases in groups.items()},
            }
        result["builds"][build] = {
            "inputs": state["files"], "case_count": len(cases),
            "row_count": sum(len(case["implementations"]) for case in cases),
            "sample_count": sum(len(data["samples"]) for case in cases for data in case["implementations"].values()),
            "operations": operations,
        }
    return result


def write_csv(path, builds):
    fields = ["build", "operation", "profile", "nominal_size", "input_bytes", "utf16_units", "utf32_units",
              "implementation", "sample_count", "median_ns", "min_ns", "max_ns",
              "simdutf_speedup_vs_implementation", "normal_baseline", "normal_speedup",
              "strongest_standard_baseline", "strongest_standard_speedup",
              "per_run_medians_ns", "per_run_speedups"]
    with path.open("w", newline="") as output:
        writer = csv.DictWriter(output, fieldnames=fields, lineterminator="\n")
        writer.writeheader()
        for build, state in builds.items():
            for key in sorted(state["cases"]):
                case = state["cases"][key]
                normal = comparison(case, case["normal"])
                strongest = comparison(case, case["strongest_standard"])
                for name, data in sorted(case["implementations"].items()):
                    ratio = comparison(case, name)
                    writer.writerow({
                        "build": build, "operation": case["operation"], "profile": case["profile"],
                        "nominal_size": case["nominalSize"], "input_bytes": case["inputBytes"],
                        "utf16_units": case["utf16Units"], "utf32_units": case["utf32Units"],
                        "implementation": name, "sample_count": len(data["samples"]),
                        "median_ns": data["median_ns"], "min_ns": data["min_ns"], "max_ns": data["max_ns"],
                        "simdutf_speedup_vs_implementation": ratio["simdutf_speedup"],
                        "normal_baseline": case["normal"], "normal_speedup": normal["simdutf_speedup"] if normal else "",
                        "strongest_standard_baseline": case["strongest_standard"],
                        "strongest_standard_speedup": strongest["simdutf_speedup"] if strongest else "",
                        "per_run_medians_ns": json.dumps({run: item["median_ns"] for run, item in data["runs"].items()}, sort_keys=True),
                        "per_run_speedups": json.dumps({run: item["speedup"] for run, item in ratio["per_run"].items()}, sort_keys=True),
                    })


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", action="append", metavar="BUILD=FILE", help="Repeated benchmark input; overrides all defaults.")
    parser.add_argument("--results-dir", type=Path, default=ROOT / "Results" / "local")
    parser.add_argument("--output-dir", type=Path, help="Defaults to --results-dir.")
    args = parser.parse_args()
    output_dir = args.output_dir if args.output_dir is not None else args.results_dir
    if args.input:
        inputs = []
        for item in args.input:
            build, separator, filename = item.partition("=")
            if not separator or not build or not filename:
                parser.error("--input requires BUILD=FILE")
            inputs.append((build, Path(filename)))
    else:
        inputs = [(build, args.results_dir / f"{build}-run{run}.json") for build in ("default", "o3") for run in (1, 2)]
    try:
        builds = load_cases(inputs)
        summary = build_summary(builds)
        output_dir.mkdir(parents=True, exist_ok=True)
        summary_path = output_dir / "summary.json"
        summary_path.write_text(json.dumps(summary, indent=2, sort_keys=True, allow_nan=False) + "\n")
        csv_path = output_dir / "cases.csv"
        write_csv(csv_path, builds)
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f"analysis: {error}", file=sys.stderr)
        return 1
    print(f"Wrote {summary_path} and {csv_path}")
    for build, state in summary["builds"].items():
        for operation, data in state["operations"].items():
            stats = data["representative_unicode"]["strongest_standard"]
            if stats:
                print(f"{build} {operation}: representative Unicode {stats['min_speedup']:.2f}–{stats['max_speedup']:.2f}x, geometric mean {stats['geometric_mean_speedup']:.2f}x ({stats['case_count']} cases)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
