// swift-tools-version: 6.4
import PackageDescription

let package = Package(
  name: "SimdUTFBenchmarks",
  platforms: [.macOS(.v13)],
  dependencies: [
    .package(url: "https://github.com/margelo/simdutf-swift.git", exact: "1.0.1",
             traits: ["UTF8", "UTF16", "UTF32", "ASCII"])
  ],
  targets: [
    .target(name: "BenchmarkSupport"),
    .executableTarget(name: "UnicodeBench", dependencies: [
      "BenchmarkSupport", .product(name: "SimdUTF", package: "simdutf-swift")
    ])
  ]
)
