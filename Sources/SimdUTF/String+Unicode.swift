// Handwritten Swift conveniences. The generated low-level bindings remain separate.

#if UTF8 || ASCII
private func withSimdUTFChars<R>(
  _ bytes: UnsafeBufferPointer<UInt8>,
  _ body: (UnsafePointer<CChar>?) throws -> R
) rethrows -> R {
  guard let baseAddress = bytes.baseAddress else { return try body(nil) }
  return try baseAddress.withMemoryRebound(to: CChar.self, capacity: bytes.count) {
    try body($0)
  }
}

private func stringCopyingValidUTF8(
  _ bytes: UnsafeBufferPointer<UInt8>, isKnownASCII: Bool = false
) -> String {
  guard !bytes.isEmpty else { return "" }
  // The standard initializer keeps short ASCII copies inexpensive.
  if isKnownASCII && bytes.count <= 128 {
    return String(decoding: bytes, as: UTF8.self)
  }
  #if compiler(>=6.2)
  if #available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *) {
    return String(
      copying: UTF8Span(unchecked: Span(_unsafeElements: bytes), isKnownASCII: isKnownASCII))
  }
  #endif
  return String(decoding: bytes, as: UTF8.self)
}

extension String {
  private mutating func appendSimdUTFChunk(_ chunk: String) {
    if isEmpty {
      self = chunk
    } else {
      append(chunk)
    }
  }
}
#endif

#if UTF8
extension String {
  /// Copies counted UTF-8, replacing ill-formed sequences with U+FFFD.
  /// Embedded nulls are preserved. The input is borrowed only during this call.
  public init(decodingUTF8 bytes: UnsafeBufferPointer<UInt8>) {
    self.init(decoding: bytes, as: UTF8.self)
  }

  /// Copies counted UTF-8 after SIMD validation, or returns nil for malformed input.
  /// Embedded nulls are preserved; an empty buffer creates an empty string.
  public init?(validatingUTF8 bytes: UnsafeBufferPointer<UInt8>) {
    guard bytes.isEmpty || withSimdUTFChars(bytes, { simdutf_validate_utf8($0, bytes.count) }) else {
      return nil
    }
    self.init(uncheckedUTF8: bytes)
  }

  /// Copies already-valid counted UTF-8 into owned String storage.
  /// Embedded nulls are preserved. The input is borrowed only during this call.
  /// - Precondition: The buffer contains well-formed UTF-8.
  public init(uncheckedUTF8 bytes: UnsafeBufferPointer<UInt8>) {
    self = stringCopyingValidUTF8(bytes)
  }

  /// Appends counted UTF-8, replacing ill-formed sequences with U+FFFD.
  /// Embedded nulls are preserved. The input is borrowed only during this call.
  public mutating func append(decodingUTF8 bytes: UnsafeBufferPointer<UInt8>) {
    appendSimdUTFChunk(String(decodingUTF8: bytes))
  }
}
#endif

#if ASCII
extension String {
  /// Copies counted ASCII after SIMD validation, or returns nil if a byte exceeds 0x7F.
  /// Embedded nulls are preserved; an empty buffer creates an empty string.
  public init?(validatingASCII bytes: UnsafeBufferPointer<UInt8>) {
    guard bytes.isEmpty || withSimdUTFChars(bytes, { simdutf_validate_ascii($0, bytes.count) }) else {
      return nil
    }
    self.init(uncheckedASCII: bytes)
  }

  /// Copies already-valid counted ASCII into owned String storage.
  /// Embedded nulls are preserved. The input is borrowed only during this call.
  /// - Precondition: Every byte is at most 0x7F.
  public init(uncheckedASCII bytes: UnsafeBufferPointer<UInt8>) {
    self = stringCopyingValidUTF8(bytes, isKnownASCII: true)
  }

  /// Appends already-valid counted ASCII, preserving embedded nulls.
  /// The input is borrowed only during this call.
  /// - Precondition: Every byte is at most 0x7F.
  public mutating func append(uncheckedASCII bytes: UnsafeBufferPointer<UInt8>) {
    appendSimdUTFChunk(String(uncheckedASCII: bytes))
  }

  /// Whether every Unicode scalar in this string is ASCII.
  /// Uses SIMD validation of the UTF-8 storage; empty strings are ASCII.
  public var isASCII: Bool {
    var copy = self
    return copy.withUTF8 { bytes in
      bytes.isEmpty || withSimdUTFChars(bytes, { simdutf_validate_ascii($0, bytes.count) })
    }
  }
}
#endif

#if UTF8 && UTF16
extension String {
  /// Transcodes counted native-endian UTF-16 using SIMD, replacing unpaired surrogates with U+FFFD.
  /// Embedded nulls are preserved. The input is borrowed only during this call.
  public init(decodingUTF16 units: UnsafeBufferPointer<UInt16>) {
    guard !units.isEmpty else {
      self = ""
      return
    }
    // UTF-16 needs at most three UTF-8 bytes per unit, including replacements.
    if units.count <= 128 {
      self = withUnsafeTemporaryAllocation(of: UInt8.self, capacity: 384) { output in
        let count = simdutf_swift_utf16_to_utf8(units.baseAddress, units.count, output.baseAddress)
        return stringCopyingValidUTF8(UnsafeBufferPointer(start: output.baseAddress, count: count))
      }
    } else {
      self = String(unsafeUninitializedCapacity: units.count * 3) { output in
        simdutf_swift_utf16_to_utf8(units.baseAddress, units.count, output.baseAddress)
      }
    }
  }

  /// Copies native-endian UTF-16 after SIMD validation, or returns nil for unpaired surrogates.
  /// Embedded nulls are preserved; an empty buffer creates an empty string.
  public init?(validatingUTF16 units: UnsafeBufferPointer<UInt16>) {
    guard simdutf_swift_validate_utf16(units.baseAddress, units.count) else { return nil }
    self.init(decodingUTF16: units)
  }

  /// Appends counted native-endian UTF-16, replacing unpaired surrogates with U+FFFD.
  /// Embedded nulls are preserved. The input is borrowed only during this call.
  public mutating func append(decodingUTF16 units: UnsafeBufferPointer<UInt16>) {
    appendSimdUTFChunk(String(decodingUTF16: units))
  }

  /// Calls `body` once with contiguous native-endian UTF-16 transcoded using SIMD.
  /// The counted buffer preserves embedded nulls and has no required null terminator.
  /// It is borrowed only until `body` returns and must not escape the closure.
  /// Unlike the `utf16` view, this method supplies contiguous temporary storage.
  public func withUTF16<R>(
    _ body: (UnsafeBufferPointer<UInt16>) throws -> R
  ) rethrows -> R {
    var copy = self
    return try copy.withUTF8 { try $0.withUTF16(body) }
  }
}

extension UnsafeBufferPointer where Element == UInt8 {
  /// Calls `body` once with contiguous native-endian UTF-16 transcoded using SIMD.
  /// The output preserves embedded nulls and has no required null terminator.
  /// It is borrowed only until `body` returns and must not escape the closure.
  /// An empty input calls `body` with an empty buffer whose base address is nil.
  /// - Precondition: The input contains well-formed UTF-8 and stays valid throughout the call.
  public func withUTF16<R>(
    _ body: (UnsafeBufferPointer<UInt16>) throws -> R
  ) rethrows -> R {
    guard !isEmpty else { return try body(UnsafeBufferPointer<UInt16>(start: nil, count: 0)) }
    return try withUnsafeTemporaryAllocation(of: UInt16.self, capacity: count) { output in
      let written = simdutf_swift_valid_utf8_to_utf16(baseAddress, count, output.baseAddress)
      return try body(UnsafeBufferPointer<UInt16>(start: output.baseAddress, count: written))
    }
  }
}
#endif

#if UTF8 && UTF32
private func stringFromValidUTF32(_ units: UnsafeBufferPointer<UInt32>) -> String {
  guard !units.isEmpty else { return "" }
  if units.count <= 128 {
    return withUnsafeTemporaryAllocation(of: UInt8.self, capacity: 512) { output in
      let count = output.baseAddress!.withMemoryRebound(to: CChar.self, capacity: output.count) {
        simdutf_convert_valid_utf32_to_utf8(units.baseAddress, units.count, $0)
      }
      return stringCopyingValidUTF8(UnsafeBufferPointer(start: output.baseAddress, count: count))
    }
  }
  return String(unsafeUninitializedCapacity: units.count * 4) { output in
    output.baseAddress!.withMemoryRebound(to: CChar.self, capacity: output.count) {
      simdutf_convert_valid_utf32_to_utf8(units.baseAddress, units.count, $0)
    }
  }
}

extension String {
  /// Transcodes counted native-endian UTF-32 using SIMD when well-formed.
  /// Invalid code points are replaced with U+FFFD using Swift's standard decoder.
  /// Embedded nulls are preserved. The input is borrowed only during this call.
  public init(decodingUTF32 units: UnsafeBufferPointer<UInt32>) {
    if let validated = String(validatingUTF32: units) {
      self = validated
    } else {
      self.init(decoding: units, as: UTF32.self)
    }
  }

  /// Copies native-endian UTF-32 after SIMD validation, or returns nil for invalid code points.
  /// Embedded nulls are preserved; an empty buffer creates an empty string.
  public init?(validatingUTF32 units: UnsafeBufferPointer<UInt32>) {
    guard units.isEmpty || simdutf_validate_utf32(units.baseAddress, units.count) else { return nil }
    self = stringFromValidUTF32(units)
  }

  /// Appends counted native-endian UTF-32, replacing invalid code points with U+FFFD.
  /// Embedded nulls are preserved. The input is borrowed only during this call.
  public mutating func append(decodingUTF32 units: UnsafeBufferPointer<UInt32>) {
    appendSimdUTFChunk(String(decodingUTF32: units))
  }

  /// Calls `body` once with contiguous native-endian UTF-32 transcoded using SIMD.
  /// The counted buffer preserves embedded nulls and has no required null terminator.
  /// It is borrowed only until `body` returns and must not escape the closure.
  public func withUTF32<R>(
    _ body: (UnsafeBufferPointer<UInt32>) throws -> R
  ) rethrows -> R {
    var copy = self
    return try copy.withUTF8 { try $0.withUTF32(body) }
  }
}

extension UnsafeBufferPointer where Element == UInt8 {
  /// Calls `body` once with contiguous native-endian UTF-32 transcoded using SIMD.
  /// The output preserves embedded nulls and has no required null terminator.
  /// It is borrowed only until `body` returns and must not escape the closure.
  /// An empty input calls `body` with an empty buffer whose base address is nil.
  /// - Precondition: The input contains well-formed UTF-8 and stays valid throughout the call.
  public func withUTF32<R>(
    _ body: (UnsafeBufferPointer<UInt32>) throws -> R
  ) rethrows -> R {
    guard !isEmpty else { return try body(UnsafeBufferPointer<UInt32>(start: nil, count: 0)) }
    return try withUnsafeTemporaryAllocation(of: UInt32.self, capacity: count) { output in
      let written = withSimdUTFChars(self) {
        simdutf_convert_valid_utf8_to_utf32($0, count, output.baseAddress)
      }
      return try body(UnsafeBufferPointer<UInt32>(start: output.baseAddress, count: written))
    }
  }
}
#endif
