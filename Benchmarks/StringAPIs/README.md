# simdutf-swift 1.0.1 String API benchmarks

> **DO NOT MERGE:** This draft PR is an archive of benchmark code and measurements. It is intended to remain draft and unmerged. The harness benchmarks the released 1.0.1 dependency, independently of changes to the parent package.

Measured on 2026-09-30: Apple M2 Pro, macOS 27.0 (26A428), Swift 6.4, Xcode 27.0. The exact remote 1.0.1 tag resolves to `4f98b5b16c8b1d9c7d77d88395c2a50b74be0607`, using simdutf 9.2.1 and its ARM NEON backend.

Across 64 valid, non-ASCII UTF-16/UTF-32 conversion cases, the geometric-mean speedup over ordinary Swift APIs was **4.24×** with the default Swift Build release settings, and **4.63×** with C++ `-O3`. These are equally weighted microbenchmark cases, not a prediction of any application's average speedup.

The representative Unicode range below covers Latin text, CJK, emoji, and mixed text at nominal sizes of 1,024 through 1,048,576 UTF-16 code units. Each operation has 16 such cases. The peak column considers every nonempty valid case, including ASCII, and names the winning input. A factor of 2× means half the conversion time. Ranges are minimum and maximum case-median speedups across the listed corpora and sizes, not confidence intervals.

## Default release: Swift `-O`, C++ `-Os`

| Conversion | Unicode geometric mean | Unicode range | Peak | Peak input |
|---|---:|---:|---:|---|
| UTF-16 buffer → String | 1.52× | 1.13–2.43× | 19.03× | ASCII, 262,144 UTF-16 units / 262,144 UTF-32 units |
| UTF-32 buffer → String | 7.61× | 4.16–18.97× | 55.70× | ASCII, 262,144 UTF-16 units / 262,144 UTF-32 units |
| String → UTF-16 buffer | 2.95× | 2.40–3.90× | 45.12× | ASCII, 16,384 UTF-16 units / 16,384 UTF-32 units |
| String → UTF-32 buffer | 9.51× | 6.19–13.71× | 62.74× | ASCII, 16,384 UTF-16 units / 16,384 UTF-32 units |

The ordinary baseline is `String(decoding:as:)` for constructors, `Array(string.utf16)` for UTF-16 output, and `string.unicodeScalars.map { $0.value }` for UTF-32 output, followed by borrowing the resulting contiguous buffer.

## Opt-in comparison: Swift `-O`, C++ `-O3`

| Conversion | Unicode geometric mean | Unicode range | Peak | Peak input |
|---|---:|---:|---:|---|
| UTF-16 buffer → String | 1.60× | 1.27–2.52× | 24.01× | ASCII, 262,144 UTF-16 units / 262,144 UTF-32 units |
| UTF-32 buffer → String | 7.60× | 4.13–18.83× | 54.79× | ASCII, 1,048,576 UTF-16 units / 1,048,576 UTF-32 units |
| String → UTF-16 buffer | 3.66× | 3.05–4.17× | 69.58× | ASCII, 1,048,576 UTF-16 units / 1,048,576 UTF-32 units |
| String → UTF-32 buffer | 10.35× | 6.70–15.22× | 71.85× | ASCII, 16,384 UTF-16 units / 16,384 UTF-32 units |

The ordinary baseline is `String(decoding:as:)` for constructors, `Array(string.utf16)` for UTF-16 output, and `string.unicodeScalars.map { $0.value }` for UTF-32 output, followed by borrowing the resulting contiguous buffer.

## Comparison with stronger Swift alternatives

Outgoing conversions also include temporary storage filled from the UTF-16/scalar views, Swift's public `transcode`, and a known-valid `UTF8Span` scalar iterator. For each case, this comparison chooses whichever measured standard-library implementation was fastest. Constructor standard-library comparisons remain `String(decoding:as:)`. Foundation's UTF-16 constructor is reported separately below.

| Conversion | Default Unicode range | Default geometric mean | `-O3` Unicode range | `-O3` geometric mean |
|---|---:|---:|---:|---:|
| UTF-16 buffer → String | 1.13–2.43× | 1.52× | 1.27–2.52× | 1.60× |
| UTF-32 buffer → String | 4.16–18.97× | 7.61× | 4.13–18.83× | 7.60× |
| String → UTF-16 buffer | 1.87–3.90× | 2.71× | 2.98–4.15× | 3.37× |
| String → UTF-32 buffer | 2.21–4.03× | 2.86× | 2.58–4.65× | 3.31× |

Across the same 64 cases, the geometric means against these stronger alternatives are 3.08× and 3.41×, respectively. Array comparisons are useful for ordinary calling code, but their larger gains include differences in allocation and view iteration as well as SIMD transcoding.

## Exact peak timings against ordinary APIs

| Build | Conversion | Input profile / bytes | Swift median | simdutf-swift median | Speedup | Ratio in each repeat |
|---|---|---|---:|---:|---:|---|
| default | UTF-16 buffer → String | ASCII / 524,288 B | 357.061 µs | 18.765 µs | 19.03× | 18.84×, 18.99× |
| default | UTF-32 buffer → String | ASCII / 1,048,576 B | 3692.281 µs | 66.291 µs | 55.70× | 54.74×, 54.48× |
| default | String → UTF-16 buffer | ASCII / 16,384 B | 35.398 µs | 0.785 µs | 45.12× | 45.89×, 43.30× |
| default | String → UTF-32 buffer | ASCII / 16,384 B | 61.870 µs | 0.986 µs | 62.74× | 62.42×, 62.21× |
| o3 | UTF-16 buffer → String | ASCII / 524,288 B | 357.425 µs | 14.885 µs | 24.01× | 23.95×, 23.78× |
| o3 | UTF-32 buffer → String | ASCII / 4,194,304 B | 15040.688 µs | 274.531 µs | 54.79× | 55.57×, 54.32× |
| o3 | String → UTF-16 buffer | ASCII / 1,048,576 B | 2220.701 µs | 31.915 µs | 69.58× | 69.65×, 69.53× |
| o3 | String → UTF-32 buffer | ASCII / 16,384 B | 65.044 µs | 0.905 µs | 71.85× | 72.82×, 69.68× |

Input bytes count the incoming C-style buffer or the native String's UTF-8 storage. The source String's storage need not have the same size as its destination UTF-16/UTF-32 buffer.

## Small inputs, UTF-8, Foundation, and malformed input

| Build | Outgoing conversion | Fastest Swift comparison, 7/16 nominal units |
|---|---|---:|
| default | String → UTF-16 buffer | 0.35–1.15× |
| default | String → UTF-32 buffer | 0.39–1.15× |
| o3 | String → UTF-16 buffer | 0.36–1.12× |
| o3 | String → UTF-32 buffer | 0.41–1.30× |

Values below 1× mean simdutf-swift was slower. Tiny strings can favor a standard Swift temporary-buffer loop; the package does not win every case. Empty strings are recorded separately in the data and excluded from headline figures.

- **default:** UTF-8 decoding control 0.95–1.02×. `String(decodingUTF8:)` forwards to the same standard Swift decoder; this is no SIMD speedup claim.
- **default:** Compared with Foundation's `String(utf16CodeUnits:count:)` followed by UTF-8 materialization, representative Unicode speedups are 21.85–39.26×, with an ASCII peak of 8.78×. This comparison includes conversion that Foundation can defer until UTF-8 is borrowed.
- **default:** Deliberately malformed UTF-16 1.00–3.90×; malformed UTF-32 0.98–1.00×. The latter uses the package's standard Swift replacement fallback; it is excluded from the valid-input headline.
- **o3:** UTF-8 decoding control 0.96–1.00×. `String(decodingUTF8:)` forwards to the same standard Swift decoder; this is no SIMD speedup claim.
- **o3:** Compared with Foundation's `String(utf16CodeUnits:count:)` followed by UTF-8 materialization, representative Unicode speedups are 22.27–40.32×, with an ASCII peak of 11.05×. This comparison includes conversion that Foundation can defer until UTF-8 is borrowed.
- **o3:** Deliberately malformed UTF-16 1.02–4.01×; malformed UTF-32 0.98–1.00×. The latter uses the package's standard Swift replacement fallback; it is excluded from the valid-input headline.

## What is timed

Each constructor creates an owned Swift String, borrows its UTF-8 storage into an opaque C sink, and destroys the output. This includes any Foundation-backed String's deferred UTF-8 materialization. Each outgoing API creates contiguous UTF-16/UTF-32 storage, borrows it into that sink, and releases the storage. The sink does not scan or retain the bytes.

Input preparation and reference-output checks are outside timing. Outgoing inputs are prebuilt native Swift Strings. Strings contain counted data, including embedded nulls. No JavaScript, JSI, Hermes, React Native, network traffic, or engine allocation is involved. The benchmark does not cover Foundation-backed outgoing Strings, streaming ropes, cold caches, Latin-1/Base64 helpers, or every validation/append API.

The five valid corpora repeat the exact patterns in `Sources/UnicodeBench/main.swift`. Nominal sizes are 0, 7, 16, 128, 1,024, 16,384, 262,144, and 1,048,576 UTF-16 units. A final high surrogate is removed when truncating a valid corpus; recorded byte/unit counts are authoritative. Malformed inputs are separate deterministic corpora. The same input is reused, so these are warm repeated-conversion measurements.

There are 2 fresh processes per build configuration, 11 samples per variant per process, and 16 warmup iterations before adaptive iteration calibration. Samples target 8 ms; calibration accepts half that duration and caps the iteration count at 1,000,000. Variant order rotates per sample, alternate repeats reverse that order, and configuration order alternates between repeats. Measurements run serially. Medians pool all 22 ns/op samples per variant; per-run medians and ratios remain in the data. Each process passed 491 full-output checks, including both package and comparison algorithms, outside timing.

Swift code uses `-O` and whole-module optimization in both builds. This machine's default SwiftPM backend is Swift Build, whose C++ release setting was `-Os`. The second build adds `-Xcxx -O3`, so the final C++ optimization option is `-O3`. These results do not imply that every SwiftPM/Xcode integration chooses the same default C++ optimization level. The package dependency enables UTF8, UTF16, UTF32, and ASCII traits. See the recorded `metadata.json` for exact environment, revisions, and effective flags.

## Reproduce

With the same Xcode/Swift toolchain, run from the repository root:

```sh
cd Benchmarks/StringAPIs
python3 run.py
python3 report.py
```

The runner pins remote 1.0.1, builds both configurations before any timing, and invokes the analysis script when all measurement processes finish. It explicitly selects the Swift Build backend. Fresh measurements, build logs, summaries, and their generated report go into ignored `Results/local/`, so rerunning does not overwrite the recorded measurements. Results on other machines, OS releases, toolchains, optimizations, or storage representations can differ.

To regenerate the archived tables from the recorded samples without rerunning timings:

```sh
python3 analysis.py --results-dir Results/1.0.1-m2-pro-swift6.4
python3 report.py --results-dir Results/1.0.1-m2-pro-swift6.4 --output README.md
```

To check all outputs without timing:

```sh
<path-to-UnicodeBench> 11 8 --check-only
```

## Files

- `Package.swift` / `Package.resolved`: exact dependency and feature selection.
- `Sources/`: complete harness and opaque C sink.
- `run.py`: serial measurement runner.
- [Results](Results/1.0.1-m2-pro-swift6.4/): raw samples, logs, derived tables, and recorded environment metadata when available.
- Corresponding `.log` files: preflight pass counts and process timings.
- `analysis.py`: reproducible aggregation into `summary.json` and `cases.csv` within a results directory.
- `report.py`: this report's generator.
- `metadata.json`, `runs.json`: build/environment metadata and executed measurement commands.
