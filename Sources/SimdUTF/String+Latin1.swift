#if UTF8 && Latin1
extension String {
  /// Copies ISO-8859-1 bytes into a string. Every byte is a valid Latin-1 scalar.
  /// The input is borrowed only for this call; embedded NUL bytes are preserved.
  public init(decodingLatin1 bytes: UnsafeBufferPointer<UInt8>) {
    guard !bytes.isEmpty else {
      self = ""
      return
    }
    self = bytes.baseAddress!.withMemoryRebound(to: CChar.self, capacity: bytes.count) { input in
      let capacity = simdutf_utf8_length_from_latin1(input, bytes.count)
      return stringFromSimdUTF(capacity: capacity) { output in
        output.baseAddress!.withMemoryRebound(to: CChar.self, capacity: output.count) {
          simdutf_convert_latin1_to_utf8(input, bytes.count, $0)
        }
      }
    }
  }

  /// Appends ISO-8859-1 bytes, preserving embedded NUL bytes.
  public mutating func append(decodingLatin1 bytes: UnsafeBufferPointer<UInt8>) {
    guard !bytes.isEmpty else { return }
    let suffix = String(decodingLatin1: bytes)
    if isEmpty {
      self = suffix
    } else {
      append(suffix)
    }
  }

  /// Returns ISO-8859-1 bytes, or `nil` if a scalar is outside U+0000...U+00FF.
  /// No lossy substitution is performed.
  public func latin1Encoded() -> [UInt8]? {
    guard !isEmpty else { return [] }
    var copy = self
    return copy.withUTF8 { bytes in
      bytes.baseAddress!.withMemoryRebound(to: CChar.self, capacity: bytes.count) { input in
        let capacity = simdutf_latin1_length_from_utf8(input, bytes.count)
        var succeeded = false
        let result = [UInt8](unsafeUninitializedCapacity: capacity) { output, initializedCount in
          let conversion = output.baseAddress!.withMemoryRebound(to: CChar.self, capacity: output.count) {
            simdutf_convert_utf8_to_latin1_with_errors(input, bytes.count, $0)
          }
          succeeded = conversion.error == SIMDUTF_ERROR_SUCCESS
          initializedCount = succeeded ? conversion.count : 0
        }
        return succeeded ? result : nil
      }
    }
  }
}
#endif
