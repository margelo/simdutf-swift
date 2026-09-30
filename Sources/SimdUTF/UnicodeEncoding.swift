#if DetectEncoding
/// Unicode encodings reported by simdutf's byte-buffer detection.
/// More than one encoding may match the same bytes.
public struct UnicodeEncoding: OptionSet, Sendable {
  public let rawValue: Int32

  public init(rawValue: Int32) {
    self.rawValue = rawValue
  }

  public static let utf8 = Self(rawValue: Int32(SIMDUTF_ENCODING_UTF8.rawValue))
  public static let utf16LE = Self(rawValue: Int32(SIMDUTF_ENCODING_UTF16_LE.rawValue))
  public static let utf16BE = Self(rawValue: Int32(SIMDUTF_ENCODING_UTF16_BE.rawValue))
  public static let utf32LE = Self(rawValue: Int32(SIMDUTF_ENCODING_UTF32_LE.rawValue))
  public static let utf32BE = Self(rawValue: Int32(SIMDUTF_ENCODING_UTF32_BE.rawValue))
}

extension UnsafeBufferPointer where Element == UInt8 {
  /// Reports candidate Unicode encodings for this counted byte buffer.
  /// A byte-order mark takes precedence; without one, multiple encodings may
  /// match. This does not establish the intended encoding or validate a payload
  /// following a byte-order mark. An empty set means no encoding was detected.
  public var detectedUnicodeEncodings: UnicodeEncoding {
    guard let baseAddress else {
      return UnicodeEncoding(rawValue: simdutf_detect_encodings(nil, 0))
    }
    return baseAddress.withMemoryRebound(to: CChar.self, capacity: count) {
      UnicodeEncoding(rawValue: simdutf_detect_encodings($0, count))
    }
  }
}
#endif
