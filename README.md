# simdutf for Swift

[simdutf](https://github.com/simdutf/simdutf) provides SIMD-accelerated Unicode
validation, transcoding, and Base64. This package makes its C API available to
Swift, together with counted-buffer `String` conveniences, with **compile-time
feature selection through SwiftPM traits**.

```swift
import SimdUTF

let bytes = Array("Hello, 世界 🌍".utf8)
let isValid = bytes.withUnsafeBytes { buffer in
    simdutf_validate_utf8(
        buffer.baseAddress?.assumingMemoryBound(to: CChar.self),
        buffer.count
    )
}
```

Requires **Swift 6.1 or later**. No C++ interoperability setting is needed.
The native implementation uses C++17 and upstream's architecture detection and
runtime dispatch to select supported SIMD instructions. Swift bindings are thin,
inlinable forwards to the C bridge, with caller-owned buffers.

## Installation

Add the package and its `SimdUTF` product to your `Package.swift`:

```swift
dependencies: [
    .package(
        url: "https://github.com/margelo/simdutf-swift.git",
        from: "1.0.0",
        traits: ["UTF8", "ASCII"]
    ),
],
targets: [
    .target(
        name: "MyApp",
        dependencies: [
            .product(name: "SimdUTF", package: "simdutf-swift"),
        ]
    ),
]
```

In Xcode, add `https://github.com/margelo/simdutf-swift.git` as a package
dependency and select the `SimdUTF` product. Xcode 26.4 and later expose traits
in the Package Dependencies view. Earlier Xcode versions with Swift 6.1 can
configure traits through a consuming package's manifest.

## Features

Omitting `traits` enables **UTF8 and UTF16**. An explicit set replaces those
defaults. Use `traits: [.defaults, "Base64"]` to extend the defaults,
`traits: ["All"]` to enable every feature, or `traits: []` to disable all features.

| Trait | Operations | Upstream compile-time gate |
| --- | --- | --- |
| `UTF8` | UTF-8 validation, counting, and conversion | `SIMDUTF_FEATURE_UTF8` |
| `UTF16` | UTF-16 validation, repair, counting, and conversion | `SIMDUTF_FEATURE_UTF16` |
| `UTF32` | UTF-32 validation and conversion | `SIMDUTF_FEATURE_UTF32` |
| `ASCII` | ASCII validation | `SIMDUTF_FEATURE_ASCII` |
| `Latin1` | Latin-1 conversion | `SIMDUTF_FEATURE_LATIN1` |
| `Base64` | Base64 encoding and decoding | `SIMDUTF_FEATURE_BASE64` |
| `DetectEncoding` | Encoding detection; also enables `UTF8`, `UTF16`, `UTF32` | `SIMDUTF_FEATURE_DETECT_ENCODING` |
| `All` | All seven features above | All seven gates |

Conversions require both encodings: UTF-8 → UTF-16 needs `UTF8` and `UTF16`.
UTF-16 ASCII checks need `UTF16` and `ASCII`. Encoding detection uses Unicode
validators internally, so its trait enables the three Unicode traits explicitly.
The feature conditions follow upstream, including helpers available under a
single encoding trait.

Disabled features are set to `0` before compiling upstream source. Their C bridge
implementations and public Swift functions are also excluded. This is build
configuration; a runtime `OptionSet` cannot remove compiled code.

SwiftPM **unions traits across the dependency graph**. A feature requested by
another dependency will be enabled for the shared package, even if your own
dependency declaration omits it. See
[SwiftPM package traits](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0450-swiftpm-package-traits.md).

CPU backends such as ARM NEON and x86 AVX2/AVX-512 are selected by upstream for
the build architecture and dispatched according to available CPU instructions.
The traits select operations, rather than forcing a particular CPU instruction set.

## API and buffers

### Swift conveniences

```swift
import SimdUTF

let units: [UInt16] = [0x0048, 0x0069, 0x0020, 0xD83D, 0xDE0A]
var text = units.withUnsafeBufferPointer { String(decodingUTF16: $0) }
units.withUnsafeBufferPointer { text.append(decodingUTF16: $0) }

text.withUTF16 { buffer in
    // Call a native API synchronously with buffer.baseAddress and buffer.count.
}

let valid = units.withUnsafeBufferPointer { String(validatingUTF16: $0) }
```

`decodingUTF8`, `decodingUTF16`, and `decodingUTF32` replace malformed input
with U+FFFD. Their `validating…` counterparts return `nil` for malformed input.
`uncheckedUTF8` and `uncheckedASCII` require already valid input and avoid a
separate validation pass. All initializers copy their input and preserve embedded
NULs; buffers need no terminator. UTF-16 and UTF-32 use native-endian units.
Appends have the same decoding semantics as their matching initializer.

`withUTF16` and `withUTF32` provide temporary, counted buffers valid only for the
closure. They return the closure's result and rethrow its errors. Do not save or
return pointers into these buffers. The UTF-8 buffer's `withUTF16` additionally
requires valid UTF-8 input; it can transcode bytes already borrowed from a string
without copying that string first.

| Swift convenience | Required traits |
| --- | --- |
| `String(decodingUTF8:)`, `String(validatingUTF8:)`, `String(uncheckedUTF8:)`, `append(decodingUTF8:)` | `UTF8` |
| `String(decodingUTF16:)`, `String(validatingUTF16:)`, `append(decodingUTF16:)`, `String.withUTF16`, `UnsafeBufferPointer<UInt8>.withUTF16` | `UTF8`, `UTF16` |
| `String(decodingUTF32:)`, `String(validatingUTF32:)`, `append(decodingUTF32:)`, `String.withUTF32`, `UnsafeBufferPointer<UInt8>.withUTF32` | `UTF8`, `UTF32` |
| `String(validatingASCII:)`, `String(uncheckedASCII:)`, `append(uncheckedASCII:)`, `String.isASCII` | `ASCII` |
| `String(decodingLatin1:)`, `append(decodingLatin1:)`, `String.latin1Encoded()` | `UTF8`, `Latin1` |
| `UnsafeBufferPointer<UInt8>.base64EncodedString(options:)`, `String.base64DecodedBytes(options:lastChunkHandling:)` | `Base64` |
| `UnsafeBufferPointer<UInt8>.detectedUnicodeEncodings`, `UnicodeEncoding` | `DetectEncoding` |

Latin-1 decoding accepts every byte; encoding returns `nil` if a scalar cannot
be represented without loss. Base64 decoding returns `nil` for invalid input and
supports the existing `SIMDUTF_BASE64_*` and `SIMDUTF_LAST_CHUNK_*` options:

```swift
let bytes: [UInt8] = [0, 1, 2, 255]
let encoded = bytes.withUnsafeBufferPointer {
    $0.base64EncodedString(options: SIMDUTF_BASE64_URL)
}
let decoded = encoded.base64DecodedBytes(options: SIMDUTF_BASE64_URL)
```

`detectedUnicodeEncodings` returns an `OptionSet` of `.utf8`, `.utf16LE`,
`.utf16BE`, `.utf32LE`, and `.utf32BE` candidates. A BOM takes precedence;
otherwise multiple encodings can match. Detection does not establish the
intended encoding or validate a payload after a BOM.

These conveniences are included in the next package release. Version `1.0.0`
provides the low-level functions below; use this change's Git revision to try
the new methods before that release.

### Low-level functions

The public functions retain upstream's C names, such as
`simdutf_validate_utf8`, `simdutf_convert_utf8_to_utf16`,
`simdutf_convert_utf32_to_utf8`, and `simdutf_base64_to_binary`.
Results, errors, encoding types, and Base64 options are available through public
type aliases and constants. See the
[C bridge header](Sources/CSimdUTF/include/CSimdUTF.h) and
[upstream API documentation](https://simdutf.github.io/simdutf/) for each function's
buffer capacities, validity requirements, and error semantics.

Pointers are borrowed for the duration of each call. Functions work on counted
buffers and preserve embedded nulls. Counts and capacities must be nonnegative.
Allocate sufficient output capacity before
calling a conversion; where available, use its matching length estimator or safe
conversion variant. UTF-16 and UTF-32 buffers use `UInt16` and `UInt32` pointers;
native-endian and explicit little-/big-endian operations follow upstream semantics.
Functions whose names contain `valid` require already validated input.

Four compatibility helpers are also provided:

- `simdutf_swift_utf16_to_utf8`: replaces unpaired surrogates with U+FFFD;
  output capacity must be at least `count * 3` bytes.
- `simdutf_swift_valid_utf8_to_utf16`: converts valid UTF-8 into native-endian
  UTF-16; output capacity must be at least `count` units.
- `simdutf_swift_validate_utf16`: validates native-endian UTF-16.
- `simdutf_swift_repair_utf16`: replaces unpaired surrogates with U+FFFD into
  `count` output units, permitting exact in-place repair.

These helpers allow null pointers for a zero count and never allocate or retain
memory. Their input and output must not overlap except for exact in-place repair.
The conversion helpers require `UTF8` and `UTF16`; validation and repair require
`UTF16`.

This package exposes upstream's C API, compatibility helpers, and Swift conveniences. C++-only
APIs, including experimental atomic Base64 operations, are outside the Swift API.

## Optimization and distribution

The package ships **source**, pinned to simdutf **v9.2.1**
(`dc3f7a8fa291f2ce793c7b0ddd458f4e67542f14`). SwiftPM fetches the pinned submodule
when resolving a Git dependency. Source distribution lets each consumer compile
its selected features for its platform and toolchain. A precompiled framework
would bake in a feature set and require separate platform/architecture builds.

Use your application's Release configuration. The manifest does not force `-O3`:
SwiftPM requires `unsafeFlags` for that override, which can make a versioned
package ineligible as a dependency. See
[SwiftPM's unsafe-flags restriction](https://developer.apple.com/documentation/packagedescription/cxxsetting/unsafeflags(_:_:)).
For command-line builds, an application can choose to benchmark `-O3` itself:

```sh
swift build -c release -Xcxx -O3
```

That option applies to the consuming build's C++ targets. Xcode's build
configuration controls optimization when building through Xcode. This package
has no unsafe compiler flags.

## Development

```sh
git clone --recurse-submodules https://github.com/margelo/simdutf-swift.git
cd simdutf-swift
swift test -c release
swift test -c release --traits All
python3 Scripts/test-features.py
```

The feature checks exercise representative subsets, check that disabled native
symbols are absent, and verify that disabled Swift APIs cannot be called.
The upstream submodule remains unchanged; generated bridge files adapt its C API
to per-function feature guards. Handwritten Swift conveniences are kept in
separate files and survive regeneration. After updating to a tagged upstream release,
run `python3 Scripts/generate-bindings.py`, inspect its feature conditions, and
rerun the checks.

## Upstream updates

Dependabot checks the `simdutf` submodule every Monday at 09:00 Europe/Vienna and
opens an update PR when a newer upstream revision is available. It keeps at most
one update PR open. Each update remains pinned to a specific commit.

The companion `Update simdutf bindings` workflow adds regenerated C/Swift bindings
and refreshed upstream version information to Dependabot's PR, then starts CI on
the resulting commit. Review the diff and checks before merging. Incompatible
upstream API changes can still require a binding-generator change; CI should
flag those rather than silently accepting them.

Dependabot's update jobs run separately from GitHub Actions. If an organization
policy disables Actions, the companion workflow and CI cannot run; upstream PRs
then need manual regeneration and local checks:

```sh
git submodule update --init
git -C simdutf fetch --tags origin
python3 Scripts/update-upstream.py
python3 Scripts/test-features.py
```

Merging an upstream update changes `main`; publish a new package version tag
when that update should become available to versioned SwiftPM consumers.

## License

The package is MIT licensed. simdutf is available under either Apache 2.0 or MIT;
see [NOTICE](NOTICE), [LICENSE](LICENSE),
[simdutf's MIT license](simdutf/LICENSE-MIT), and
[simdutf's Apache license](simdutf/LICENSE-APACHE).
