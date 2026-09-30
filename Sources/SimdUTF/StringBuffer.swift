#if UTF8 || Base64
/// Builds an owned string from counted UTF-8 written into temporary storage.
/// The initializer must write valid UTF-8 within `capacity`, return its byte count,
/// and finish using the borrowed output buffer before returning.
func stringFromSimdUTF(
  capacity: Int,
  initializingWith initialize: (UnsafeMutableBufferPointer<UInt8>) -> Int
) -> String {
  if #available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *) {
    return String(unsafeUninitializedCapacity: capacity, initializingUTF8With: initialize)
  }
  return withUnsafeTemporaryAllocation(of: UInt8.self, capacity: capacity) { output in
    let count = initialize(output)
    return String(decoding: UnsafeBufferPointer(start: output.baseAddress, count: count), as: UTF8.self)
  }
}
#endif
