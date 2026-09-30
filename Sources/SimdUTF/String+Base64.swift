#if Base64
extension UnsafeBufferPointer where Element == UInt8 {
  /// Encodes these bytes using simdutf. The returned string owns its storage.
  /// Defaults to the standard alphabet with padding; `SIMDUTF_BASE64_URL` uses
  /// the URL alphabet without padding. Use encoding options, rather than the
  /// decoding-only `DEFAULT_OR_URL` options.
  public func base64EncodedString(
    options: simdutf_base64_options = SIMDUTF_BASE64_DEFAULT
  ) -> String {
    guard !isEmpty else { return "" }
    return baseAddress!.withMemoryRebound(to: CChar.self, capacity: count) { input in
      let capacity = simdutf_base64_length_from_binary(count, options)
      return String(unsafeUninitializedCapacity: capacity) { output in
        output.baseAddress!.withMemoryRebound(to: CChar.self, capacity: output.count) {
          simdutf_binary_to_base64(input, count, $0, options)
        }
      }
    }
  }
}

extension String {
  /// Decodes Base64 into owned bytes, or returns `nil` for invalid input.
  /// ASCII whitespace is ignored. The default final-chunk policy accepts
  /// unpadded input; `SIMDUTF_LAST_CHUNK_STRICT` rejects partial unpadded final
  /// chunks and nonzero unused bits. Other policies and alphabets follow simdutf semantics.
  public func base64DecodedBytes(
    options: simdutf_base64_options = SIMDUTF_BASE64_DEFAULT,
    lastChunkHandling: simdutf_last_chunk_handling_options = SIMDUTF_LAST_CHUNK_LOOSE
  ) -> [UInt8]? {
    guard !isEmpty else { return [] }
    var copy = self
    return copy.withUTF8 { bytes in
      bytes.baseAddress!.withMemoryRebound(to: CChar.self, capacity: bytes.count) { input in
        // Keep a non-null output for nonempty whitespace-only input as well.
        let capacity = max(1, simdutf_maximal_binary_length_from_base64(input, bytes.count))
        var succeeded = false
        let result = [UInt8](unsafeUninitializedCapacity: capacity) { output, initializedCount in
          let conversion = output.baseAddress!.withMemoryRebound(to: CChar.self, capacity: output.count) {
            simdutf_base64_to_binary(input, bytes.count, $0, options, lastChunkHandling)
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
