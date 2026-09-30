// swift-tools-version: 6.1

import PackageDescription

let features: [(String, String)] = [
    ("UTF8", "UTF8"),
    ("UTF16", "UTF16"),
    ("UTF32", "UTF32"),
    ("ASCII", "ASCII"),
    ("Latin1", "LATIN1"),
    ("Base64", "BASE64"),
    ("DetectEncoding", "DETECT_ENCODING"),
]

let package = Package(
    name: "SimdUTF",
    products: [
        .library(name: "SimdUTF", targets: ["SimdUTF"]),
    ],
    traits: [
        .default(enabledTraits: ["UTF8", "UTF16"]),
        .trait(name: "UTF8", description: "UTF-8 validation, counting, and conversion."),
        .trait(name: "UTF16", description: "UTF-16 validation, repair, counting, and conversion."),
        .trait(name: "UTF32", description: "UTF-32 validation and conversion."),
        .trait(name: "ASCII", description: "ASCII validation."),
        .trait(name: "Latin1", description: "Latin-1 conversion."),
        .trait(name: "Base64", description: "Base64 encoding and decoding."),
        .trait(
            name: "DetectEncoding",
            description: "Automatic Unicode encoding detection, including Unicode validators.",
            enabledTraits: ["UTF8", "UTF16", "UTF32"]
        ),
        .trait(
            name: "All",
            description: "Every simdutf feature.",
            enabledTraits: Set(features.map { $0.0 })
        ),
    ],
    targets: [
        .target(
            name: "CSimdUTF",
            cxxSettings: [
                .headerSearchPath("../../simdutf/include"),
                .headerSearchPath("../../simdutf/src"),
            ] + features.map { trait, macro in
                .define("SIMDUTF_SWIFT_ENABLE_" + macro, to: "1", .when(traits: [trait]))
            }
        ),
        .target(name: "SimdUTF", dependencies: ["CSimdUTF"]),
        .testTarget(name: "SimdUTFTests", dependencies: ["SimdUTF"]),
    ],
    cxxLanguageStandard: .cxx17
)
