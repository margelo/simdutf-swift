import BenchmarkSupport
import Dispatch
import Foundation
import SimdUTF

@inline(never) func consume(_ value: String) {
  var value = value
  value.withUTF8 { benchmark_blackhole($0.baseAddress, $0.count) }
}

@inline(never) func swiftUTF16String(_ input: UnsafeBufferPointer<UInt16>) {
  consume(String(decoding: input, as: UTF16.self))
}
@inline(never) func simdUTF16String(_ input: UnsafeBufferPointer<UInt16>) {
  consume(String(decodingUTF16: input))
}
@inline(never) func foundationUTF16String(_ input: UnsafeBufferPointer<UInt16>) {
  if input.isEmpty { consume(""); return }
  // consume() materializes UTF-8, including the work this initializer defers.
  consume(String(utf16CodeUnits: input.baseAddress!, count: input.count))
}
@inline(never) func swiftUTF32String(_ input: UnsafeBufferPointer<UInt32>) {
  consume(String(decoding: input, as: UTF32.self))
}
@inline(never) func simdUTF32String(_ input: UnsafeBufferPointer<UInt32>) {
  consume(String(decodingUTF32: input))
}
@inline(never) func swiftUTF8String(_ input: UnsafeBufferPointer<UInt8>) {
  consume(String(decoding: input, as: UTF8.self))
}
@inline(never) func simdUTF8String(_ input: UnsafeBufferPointer<UInt8>) {
  consume(String(decodingUTF8: input))
}

@inline(never) func simdTemporaryUTF16(_ value: String) {
  value.withUTF16 { benchmark_blackhole($0.baseAddress, $0.count * 2) }
}
@inline(never) func swiftArrayUTF16(_ value: String) {
  Array(value.utf16).withUnsafeBufferPointer {
    benchmark_blackhole($0.baseAddress, $0.count * 2)
  }
}
@inline(never) func swiftTemporaryUTF16(_ value: String) {
  let capacity = value.utf8.count
  guard capacity != 0 else { benchmark_blackhole(nil, 0); return }
  withUnsafeTemporaryAllocation(of: UInt16.self, capacity: capacity) { output in
    let written = output.initialize(fromContentsOf: value.utf16)
    benchmark_blackhole(output.baseAddress, written * 2)
  }
}
@inline(never) func swiftTranscodeUTF16(_ value: String) {
  var value = value
  value.withUTF8 { input in
    guard !input.isEmpty else { benchmark_blackhole(nil, 0); return }
    withUnsafeTemporaryAllocation(of: UInt16.self, capacity: input.count) { output in
      let destination = output.baseAddress!
      var written = 0
      _ = transcode(input.makeIterator(), from: UTF8.self, to: UTF16.self,
                    stoppingOnError: false) {
        destination[written] = $0
        written += 1
      }
      benchmark_blackhole(destination, written * 2)
    }
  }
}
@inline(never) func simdTemporaryUTF32(_ value: String) {
  value.withUTF32 { benchmark_blackhole($0.baseAddress, $0.count * 4) }
}
@inline(never) func swiftArrayUTF32(_ value: String) {
  value.unicodeScalars.map { $0.value }.withUnsafeBufferPointer {
    benchmark_blackhole($0.baseAddress, $0.count * 4)
  }
}
@inline(never) func swiftTemporaryUTF32(_ value: String) {
  let capacity = value.utf8.count
  guard capacity != 0 else { benchmark_blackhole(nil, 0); return }
  withUnsafeTemporaryAllocation(of: UInt32.self, capacity: capacity) { output in
    let written = output.initialize(fromContentsOf: value.unicodeScalars.lazy.map { $0.value })
    benchmark_blackhole(output.baseAddress, written * 4)
  }
}


@inline(never) func swiftTranscodeUTF32(_ value: String) {
  var value = value
  value.withUTF8 { input in
    guard !input.isEmpty else { benchmark_blackhole(nil, 0); return }
    withUnsafeTemporaryAllocation(of: UInt32.self, capacity: input.count) { output in
      let destination = output.baseAddress!
      var written = 0
      _ = transcode(input.makeIterator(), from: UTF8.self, to: UTF32.self,
                    stoppingOnError: false) {
        destination[written] = $0
        written += 1
      }
      benchmark_blackhole(destination, written * 4)
    }
  }
}

@available(macOS 26.0, iOS 26.0, *)
@inline(__always)
func withSwiftSpanUTF16<R>(
  _ value: String,
  _ body: (UnsafeBufferPointer<UInt16>) throws -> R
) rethrows -> R {
  let utf8 = value.utf8Span
  guard !utf8.isEmpty else {
    return try body(UnsafeBufferPointer(start: nil, count: 0))
  }
  return try withUnsafeTemporaryAllocation(of: UInt16.self, capacity: utf8.count) { output in
    var iterator = utf8.makeUnicodeScalarIterator()
    var written = 0
    while let scalar = iterator.next() {
      UTF16.encode(scalar) {
        output[written] = $0
        written += 1
      }
    }
    return try body(UnsafeBufferPointer(start: output.baseAddress, count: written))
  }
}

@available(macOS 26.0, iOS 26.0, *)
@inline(__always)
func withSwiftSpanUTF32<R>(
  _ value: String,
  _ body: (UnsafeBufferPointer<UInt32>) throws -> R
) rethrows -> R {
  let utf8 = value.utf8Span
  guard !utf8.isEmpty else {
    return try body(UnsafeBufferPointer(start: nil, count: 0))
  }
  return try withUnsafeTemporaryAllocation(of: UInt32.self, capacity: utf8.count) { output in
    var iterator = utf8.makeUnicodeScalarIterator()
    var written = 0
    while let scalar = iterator.next() {
      output[written] = scalar.value
      written += 1
    }
    return try body(UnsafeBufferPointer(start: output.baseAddress, count: written))
  }
}


@available(macOS 26.0, *)
@inline(never) func swiftSpanUTF16(_ value: String) {
  withSwiftSpanUTF16(value) { benchmark_blackhole($0.baseAddress, $0.count * 2) }
}
@available(macOS 26.0, *)
@inline(never) func swiftSpanUTF32(_ value: String) {
  withSwiftSpanUTF32(value) { benchmark_blackhole($0.baseAddress, $0.count * 4) }
}

struct Variant { let name: String; let run: () -> Void }
struct Row: Codable {
  let operation: String
  let profile: String
  let nominalSize: Int
  let inputBytes: Int
  let utf16Units: Int
  let utf32Units: Int
  let implementation: String
  let iterations: Int
  let samplesNs: [Double]
}
let args = CommandLine.arguments
let sampleCount = Int(args.dropFirst().first ?? "11")!
let sampleMillis = Double(args.dropFirst(2).first ?? "8")!
let reverse = args.contains("--reverse")
let onlyCheck = args.contains("--check-only")
let smallOnly = args.contains("--small-only")
let sizes = smallOnly ? [0, 7, 16, 128, 1024] : [0, 7, 16, 128, 1024, 16384, 262144, 1048576]
let profiles: [(String, String)] = [
  ("ASCII", "The quick brown fox jumps over the lazy dog. 0123456789\n"),
  ("Latin", "Les cafés de Montréal proposent crème brûlée, déjà vu et Noël.\n"),
  ("CJK", "你好，世界！日本語の文章と한국어 텍스트。\n"),
  ("Emoji", "😀🚀🌍🎉💡🔥✨🦀❤️👩‍💻\n"),
  ("Mixed", "Hello, café! 中文日本語 한국어 😀🚀 — e\u{301} 👩‍💻\0\n")
]
var rows = [Row]()
var checked = 0
let allStarted = DispatchTime.now().uptimeNanoseconds

func duration(_ variant: Variant, _ iterations: Int) -> Double {
  let start = DispatchTime.now().uptimeNanoseconds
  for _ in 0..<iterations { variant.run() }
  return Double(DispatchTime.now().uptimeNanoseconds - start)
}
@MainActor func benchmark(_ operation: String, _ profile: String, _ nominal: Int,
               _ bytes: Int, _ units16: Int, _ units32: Int, _ variants: [Variant]) {
  if onlyCheck { return }
  let target = sampleMillis * 1_000_000
  let iterations = variants.map { variant -> Int in
    for _ in 0..<16 { variant.run() }
    var n = 1
    for _ in 0..<5 {
      let elapsed = duration(variant, n)
      if elapsed >= target / 2 { return n }
      n = min(1_000_000, max(n + 1, Int(Double(n) * target / max(elapsed, 1))))
    }
    return n
  }
  var samples = variants.map { _ in [Double]() }
  for sample in 0..<sampleCount {
    let order = (0..<variants.count).map { (sample + $0) % variants.count }
    let scheduled = reverse ? Array(order.reversed()) : order
    for index in scheduled {
      samples[index].append(duration(variants[index], iterations[index]) / Double(iterations[index]))
    }
  }
  for i in variants.indices {
    rows.append(Row(operation: operation, profile: profile, nominalSize: nominal,
                    inputBytes: bytes, utf16Units: units16, utf32Units: units32,
                    implementation: variants[i].name, iterations: iterations[i], samplesNs: samples[i]))
  }
}
func progress(_ message: String) {
  FileHandle.standardError.write(Data((message + "\n").utf8))
}

for (profile, pattern) in profiles {
  for nominal in sizes {
    let patternUnits = Array(pattern.utf16)
    var units = (0..<nominal).map { patternUnits[$0 % patternUnits.count] }
    if let last = units.last, last >= 0xD800 && last <= 0xDBFF { units.removeLast() }
    let value = String(decoding: units, as: UTF16.self)
    let utf8 = Array(value.utf8)
    let utf32 = value.unicodeScalars.map { $0.value }
    units.withUnsafeBufferPointer { input in
      let actual = String(decodingUTF16: input)
      precondition(Array(actual.utf8) == utf8 && actual.isContiguousUTF8)
      if !input.isEmpty {
        var foreign = String(utf16CodeUnits: input.baseAddress!, count: input.count)
        foreign.withUTF8 { precondition(Array($0) == utf8) }
      }
      checked += input.isEmpty ? 1 : 2
      benchmark("UTF16->String", profile, nominal, units.count * 2, units.count, utf32.count, [
        Variant(name: "simdutf", run: { simdUTF16String(input) }),
        Variant(name: "swift-decoding", run: { swiftUTF16String(input) }),
        Variant(name: "foundation-materialized", run: { foundationUTF16String(input) })
      ])
    }
    utf32.withUnsafeBufferPointer { input in
      precondition(Array(String(decodingUTF32: input).utf8) == utf8)
      checked += 1
      benchmark("UTF32->String", profile, nominal, utf32.count * 4, units.count, utf32.count, [
        Variant(name: "simdutf", run: { simdUTF32String(input) }),
        Variant(name: "swift-decoding", run: { swiftUTF32String(input) })
      ])
    }
    utf8.withUnsafeBufferPointer { input in
      precondition(Array(String(decodingUTF8: input).utf8) == utf8)
      checked += 1
      // Control: decodingUTF8 is a convenience around the same Swift decoder.
      if nominal <= 1024 {
        benchmark("UTF8->String", profile, nominal, utf8.count, units.count, utf32.count, [
          Variant(name: "simdutf", run: { simdUTF8String(input) }),
          Variant(name: "swift-decoding", run: { swiftUTF8String(input) })
        ])
      }
    }
    value.withUTF16 { precondition(Array($0) == units) }
    value.withUTF32 { precondition(Array($0) == utf32) }
    withUnsafeTemporaryAllocation(of: UInt16.self, capacity: max(1, utf8.count)) { output in
      let written = output.initialize(fromContentsOf: value.utf16)
      precondition(Array(output.prefix(written)) == units)
    }
    withUnsafeTemporaryAllocation(of: UInt32.self, capacity: max(1, utf8.count)) { output in
      let written = output.initialize(fromContentsOf: value.unicodeScalars.lazy.map { $0.value })
      precondition(Array(output.prefix(written)) == utf32)
    }
    withUnsafeTemporaryAllocation(of: UInt16.self, capacity: max(1, utf8.count)) { output in
      var written = 0
      let repaired = transcode(utf8.makeIterator(), from: UTF8.self, to: UTF16.self,
                               stoppingOnError: false) {
        output[written] = $0
        written += 1
      }
      precondition(!repaired && Array(output.prefix(written)) == units)
    }
    withUnsafeTemporaryAllocation(of: UInt32.self, capacity: max(1, utf8.count)) { output in
      var written = 0
      let repaired = transcode(utf8.makeIterator(), from: UTF8.self, to: UTF32.self,
                               stoppingOnError: false) {
        output[written] = $0
        written += 1
      }
      precondition(!repaired && Array(output.prefix(written)) == utf32)
    }
    checked += 6
    var variants16 = [
      Variant(name: "simdutf", run: { simdTemporaryUTF16(value) }),
      Variant(name: "swift-array", run: { swiftArrayUTF16(value) }),
      Variant(name: "swift-temporary", run: { swiftTemporaryUTF16(value) }),
      Variant(name: "swift-transcode", run: { swiftTranscodeUTF16(value) })
    ]
    var variants32 = [
      Variant(name: "simdutf", run: { simdTemporaryUTF32(value) }),
      Variant(name: "swift-array", run: { swiftArrayUTF32(value) }),
      Variant(name: "swift-temporary", run: { swiftTemporaryUTF32(value) }),
      Variant(name: "swift-transcode", run: { swiftTranscodeUTF32(value) })
    ]
    if #available(macOS 26.0, *) {
      withSwiftSpanUTF16(value) { precondition(Array($0) == units) }
      withSwiftSpanUTF32(value) { precondition(Array($0) == utf32) }
      checked += 2
      variants16.append(Variant(name: "swift-span", run: { swiftSpanUTF16(value) }))
      variants32.append(Variant(name: "swift-span", run: { swiftSpanUTF32(value) }))
    }
    benchmark("String->UTF16", profile, nominal, utf8.count, units.count, utf32.count, variants16)
    benchmark("String->UTF32", profile, nominal, utf8.count, units.count, utf32.count, variants32)
    progress("Verified/measured \(profile) \(nominal) UTF16 units")
  }
}

// Malformed UTF-16 must repair to exactly the same UTF-8 as Swift's decoder.
for nominal in sizes {
  let pattern: [UInt16] = [65, 0xD800, 66, 0xDC00, 0, 0xDBFF, 0xDFFF, 0xD800]
  let units = (0..<nominal).map { pattern[$0 % pattern.count] }
  units.withUnsafeBufferPointer { input in
    let expected = String(decoding: input, as: UTF16.self)
    precondition(Array(String(decodingUTF16: input).utf8) == Array(expected.utf8))
    checked += 1
    benchmark("UTF16->String", "Malformed", nominal, units.count * 2,
              units.count, expected.unicodeScalars.count, [
      Variant(name: "simdutf", run: { simdUTF16String(input) }),
      Variant(name: "swift-decoding", run: { swiftUTF16String(input) })
    ])
  }
}
// Invalid UTF-32 uses the package's standard Swift fallback.
for nominal in sizes {
  let pattern: [UInt32] = [65, 0xD800, 66, 0x110000, 0, 0x10FFFF, 0xFFFFFFFF, 0xDFFF]
  let units = (0..<nominal).map { pattern[$0 % pattern.count] }
  units.withUnsafeBufferPointer { input in
    let expected = String(decoding: input, as: UTF32.self)
    precondition(Array(String(decodingUTF32: input).utf8) == Array(expected.utf8))
    checked += 1
    benchmark("UTF32->String", "Malformed", nominal, units.count * 4,
              expected.utf16.count, units.count, [
      Variant(name: "simdutf", run: { simdUTF32String(input) }),
      Variant(name: "swift-decoding", run: { swiftUTF32String(input) })
    ])
  }
}
progress("PASS \(checked) full-content checks; elapsed \(Double(DispatchTime.now().uptimeNanoseconds - allStarted) / 1e9)s")
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
FileHandle.standardOutput.write(try encoder.encode(rows))
FileHandle.standardOutput.write(Data("\n".utf8))
