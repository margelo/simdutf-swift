import CSimdUTF

#if UTF8 && UTF16
/// Converts native-endian UTF-16 to UTF-8, replacing unpaired surrogates with U+FFFD.
/// The output must hold at least `count * 3` bytes. A zero count allows nil pointers.
@inlinable
@inline(__always)
public func simdutf_swift_utf16_to_utf8(
  _ input: UnsafePointer<UInt16>?, _ count: Int, _ output: UnsafeMutablePointer<UInt8>?
) -> Int {
  CSimdUTF.simdutf_swift_utf16_to_utf8(input, count, output)
}

/// Converts valid UTF-8 to native-endian UTF-16.
/// The output must hold at least `count` units. A zero count allows nil pointers.
@inlinable
@inline(__always)
public func simdutf_swift_valid_utf8_to_utf16(
  _ input: UnsafePointer<UInt8>?, _ count: Int, _ output: UnsafeMutablePointer<UInt16>?
) -> Int {
  CSimdUTF.simdutf_swift_valid_utf8_to_utf16(input, count, output)
}
#endif

#if UTF16
/// Checks whether every native-endian UTF-16 surrogate belongs to a well-formed pair.
/// A zero count allows a nil pointer and validates successfully.
@inlinable
@inline(__always)
public func simdutf_swift_validate_utf16(_ input: UnsafePointer<UInt16>?, _ count: Int) -> Bool {
  CSimdUTF.simdutf_swift_validate_utf16(input, count)
}

/// Copies native-endian UTF-16 units, replacing unpaired surrogates with U+FFFD.
/// The output must hold `count` units. Exact in-place repair is allowed;
/// other overlapping buffers are unsupported. A zero count allows nil pointers.
@inlinable
@inline(__always)
public func simdutf_swift_repair_utf16(
  _ input: UnsafePointer<UInt16>?, _ count: Int, _ output: UnsafeMutablePointer<UInt16>?
) {
  CSimdUTF.simdutf_swift_repair_utf16(input, count, output)
}
#endif
