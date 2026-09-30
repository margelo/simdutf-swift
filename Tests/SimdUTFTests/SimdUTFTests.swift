import SimdUTF
import XCTest

final class SimdUTFTests: XCTestCase {
    private func bytes(_ text: String) -> [CChar] {
        text.utf8.map { CChar(bitPattern: $0) }
    }

    func testErrorCodesRemainAvailableWithoutOptionalFeatures() {
        XCTAssertEqual(SIMDUTF_ERROR_SUCCESS.rawValue, 0)
        XCTAssertNotEqual(SIMDUTF_ERROR_SURROGATE, SIMDUTF_ERROR_SUCCESS)
    }

    #if UTF8
    func testUTF8ValidationAndCountingPreserveEmbeddedNulls() {
        let text = String(repeating: "A\0é中😀", count: 257)
        let input = bytes(text)
        input.withUnsafeBufferPointer {
            XCTAssertTrue(simdutf_validate_utf8($0.baseAddress, $0.count))
            XCTAssertEqual(simdutf_count_utf8($0.baseAddress, $0.count), text.unicodeScalars.count)
            let result = simdutf_validate_utf8_with_errors($0.baseAddress, $0.count)
            XCTAssertEqual(result.error, SIMDUTF_ERROR_SUCCESS)
            XCTAssertEqual(result.count, input.count)
        }
    }

    func testUTF8RejectsOverlongTruncatedAndSurrogateSequences() {
        for input: [UInt8] in [[0x61, 0xC0, 0xAF], [0xF0, 0x9F, 0x98], [0xED, 0xA0, 0x80]] {
            input.map { CChar(bitPattern: $0) }.withUnsafeBufferPointer {
                XCTAssertFalse(simdutf_validate_utf8($0.baseAddress, $0.count))
                XCTAssertNotEqual(simdutf_validate_utf8_with_errors($0.baseAddress, $0.count).error, SIMDUTF_ERROR_SUCCESS)
            }
        }
        let input = bytes(String(repeating: "a", count: 129)) + [CChar(bitPattern: 0xFF)]
        input.withUnsafeBufferPointer {
            XCTAssertEqual(simdutf_validate_utf8_with_errors($0.baseAddress, $0.count).count, 129)
        }
    }
    #endif

    #if UTF16
    func testUTF16ValidationCountingAndRepair() {
        let text = String(repeating: "A\0é中😀", count: 257)
        let input = Array(text.utf16)
        input.withUnsafeBufferPointer {
            XCTAssertTrue(simdutf_validate_utf16($0.baseAddress, $0.count))
            XCTAssertTrue(simdutf_swift_validate_utf16($0.baseAddress, $0.count))
            XCTAssertEqual(simdutf_count_utf16($0.baseAddress, $0.count), text.unicodeScalars.count)
        }
        let malformed: [UInt16] = [0x61, 0xD800, 0x62, 0xDC00, 0xD83D, 0xDE00]
        var repaired = [UInt16](repeating: 0, count: malformed.count)
        malformed.withUnsafeBufferPointer { source in
            XCTAssertFalse(simdutf_swift_validate_utf16(source.baseAddress, source.count))
            let result = simdutf_validate_utf16_with_errors(source.baseAddress, source.count)
            XCTAssertEqual(result.error, SIMDUTF_ERROR_SURROGATE)
            XCTAssertEqual(result.count, 1)
            repaired.withUnsafeMutableBufferPointer {
                simdutf_swift_repair_utf16(source.baseAddress, source.count, $0.baseAddress)
            }
        }
        XCTAssertEqual(repaired, [0x61, 0xFFFD, 0x62, 0xFFFD, 0xD83D, 0xDE00])
        var inPlace = malformed
        inPlace.withUnsafeMutableBufferPointer {
            simdutf_swift_repair_utf16($0.baseAddress, $0.count, $0.baseAddress)
        }
        XCTAssertEqual(inPlace, repaired)
    }

    func testUTF16CompatibilityFunctionsAcceptNullEmptyBuffers() {
        XCTAssertTrue(simdutf_swift_validate_utf16(nil, 0))
        simdutf_swift_repair_utf16(nil, 0, nil)
    }
    #endif

    #if UTF8 && UTF16
    func testUnicodeRoundTripThroughCompatibilityFunctions() {
        let text = String(repeating: "Swift\0 café 中文 😀", count: 193)
        let input = text.utf8.map { $0 }
        var utf16 = [UInt16](repeating: 0, count: input.count)
        let units = input.withUnsafeBufferPointer { source in
            utf16.withUnsafeMutableBufferPointer {
                simdutf_swift_valid_utf8_to_utf16(source.baseAddress, source.count, $0.baseAddress)
            }
        }
        XCTAssertEqual(Array(utf16.prefix(units)), Array(text.utf16))
        var utf8 = [UInt8](repeating: 0, count: units * 3)
        let count = utf16.withUnsafeBufferPointer { source in
            utf8.withUnsafeMutableBufferPointer {
                simdutf_swift_utf16_to_utf8(source.baseAddress, units, $0.baseAddress)
            }
        }
        XCTAssertEqual(Array(utf8.prefix(count)), input)
    }

    func testMalformedUTF16ConversionReplacesEveryUnpairedSurrogate() {
        let input: [UInt16] = [0xD800, 0x61, 0, 0xDC00, 0xD83D, 0xDE00, 0xD800]
        var output = [UInt8](repeating: 0, count: input.count * 3)
        let count = input.withUnsafeBufferPointer { source in
            output.withUnsafeMutableBufferPointer {
                simdutf_swift_utf16_to_utf8(source.baseAddress, source.count, $0.baseAddress)
            }
        }
        XCTAssertEqual(Array(output.prefix(count)), Array("�a\0�😀�".utf8))
        XCTAssertEqual(simdutf_swift_utf16_to_utf8(nil, 0, nil), 0)
        XCTAssertEqual(simdutf_swift_valid_utf8_to_utf16(nil, 0, nil), 0)
    }
    #endif

    #if ASCII
    func testASCIIValidationReportsTheFirstNonASCIIByte() {
        let input = bytes(String(repeating: "ASCII\0", count: 257))
        input.withUnsafeBufferPointer {
            XCTAssertTrue(simdutf_validate_ascii($0.baseAddress, $0.count))
        }
        let invalid = input + [CChar(bitPattern: 0x80)]
        invalid.withUnsafeBufferPointer {
            XCTAssertFalse(simdutf_validate_ascii($0.baseAddress, $0.count))
            let result = simdutf_validate_ascii_with_errors($0.baseAddress, $0.count)
            XCTAssertNotEqual(result.error, SIMDUTF_ERROR_SUCCESS)
            XCTAssertEqual(result.count, input.count)
        }
    }
    #endif

    #if UTF32
    func testUTF32AcceptsUnicodeScalarsAndRejectsInvalidCodePoints() {
        let input = Array(String(repeating: "A\0é中😀", count: 257).unicodeScalars).map(\.value)
        input.withUnsafeBufferPointer {
            XCTAssertTrue(simdutf_validate_utf32($0.baseAddress, $0.count))
        }
        for codePoint: UInt32 in [0xD800, 0x110000] {
            let invalid: [UInt32] = [0x61, codePoint]
            invalid.withUnsafeBufferPointer {
                XCTAssertFalse(simdutf_validate_utf32($0.baseAddress, $0.count))
                let result = simdutf_validate_utf32_with_errors($0.baseAddress, $0.count)
                XCTAssertNotEqual(result.error, SIMDUTF_ERROR_SUCCESS)
                XCTAssertEqual(result.count, 1)
            }
        }
    }
    #endif

    #if UTF8 && UTF32
    func testUTF32ToUTF8PreservesSupplementaryCharacters() {
        let text = String(repeating: "A\0é中😀", count: 193)
        let input = text.unicodeScalars.map(\.value)
        var output = [CChar](repeating: 0, count: input.count * 4)
        let count = input.withUnsafeBufferPointer { source in
            output.withUnsafeMutableBufferPointer {
                simdutf_convert_utf32_to_utf8(source.baseAddress, source.count, $0.baseAddress)
            }
        }
        XCTAssertEqual(Array(output.prefix(count)), bytes(text))
    }
    #endif

    #if UTF16 && UTF32
    func testUTF32ToUTF16ProducesSurrogatePairs() {
        let text = String(repeating: "A\0é中😀", count: 193)
        let input = text.unicodeScalars.map(\.value)
        var output = [UInt16](repeating: 0, count: input.count * 2)
        let count = input.withUnsafeBufferPointer { source in
            output.withUnsafeMutableBufferPointer {
                simdutf_convert_utf32_to_utf16(source.baseAddress, source.count, $0.baseAddress)
            }
        }
        XCTAssertEqual(Array(output.prefix(count)), Array(text.utf16))
    }
    #endif

    #if Latin1 && UTF8
    func testLatin1UTF8RoundTripAndUnrepresentableInput() {
        let input = (0..<256).map { CChar(bitPattern: UInt8($0)) }
        var utf8 = [CChar](repeating: 0, count: input.count * 2)
        let count = input.withUnsafeBufferPointer { source in
            utf8.withUnsafeMutableBufferPointer {
                simdutf_convert_latin1_to_utf8(source.baseAddress, source.count, $0.baseAddress)
            }
        }
        XCTAssertEqual(count, 384)
        var latin1 = [CChar](repeating: 0, count: input.count)
        let roundTrip = utf8.withUnsafeBufferPointer { source in
            latin1.withUnsafeMutableBufferPointer {
                simdutf_convert_utf8_to_latin1(source.baseAddress, count, $0.baseAddress)
            }
        }
        XCTAssertEqual(roundTrip, input.count)
        XCTAssertEqual(latin1, input)
        bytes("😀").withUnsafeBufferPointer { source in
            latin1.withUnsafeMutableBufferPointer {
                XCTAssertNotEqual(simdutf_convert_utf8_to_latin1_with_errors(source.baseAddress, source.count, $0.baseAddress).error, SIMDUTF_ERROR_SUCCESS)
            }
        }
    }
    #endif

    #if Latin1 && UTF16
    func testLatin1ToUTF16PreservesEveryByteValue() {
        let input = (0..<256).map { CChar(bitPattern: UInt8($0)) }
        var output = [UInt16](repeating: 0, count: input.count)
        let count = input.withUnsafeBufferPointer { source in
            output.withUnsafeMutableBufferPointer {
                simdutf_convert_latin1_to_utf16(source.baseAddress, source.count, $0.baseAddress)
            }
        }
        XCTAssertEqual(count, input.count)
        XCTAssertEqual(output, (0..<256).map(UInt16.init))
    }
    #endif

    #if Latin1 && UTF32
    func testLatin1ToUTF32PreservesEveryByteValue() {
        let input = (0..<256).map { CChar(bitPattern: UInt8($0)) }
        var output = [UInt32](repeating: 0, count: input.count)
        let count = input.withUnsafeBufferPointer { source in
            output.withUnsafeMutableBufferPointer {
                simdutf_convert_latin1_to_utf32(source.baseAddress, source.count, $0.baseAddress)
            }
        }
        XCTAssertEqual(count, input.count)
        XCTAssertEqual(output, (0..<256).map(UInt32.init))
    }
    #endif

    #if Base64
    func testBase64RoundTripForBinaryDataAndUTF16Input() {
        let input = (0..<513).map { CChar(bitPattern: UInt8($0 % 256)) }
        let capacity = simdutf_base64_length_from_binary(input.count, SIMDUTF_BASE64_DEFAULT)
        var encoded = [CChar](repeating: 0, count: capacity)
        let encodedCount = input.withUnsafeBufferPointer { source in
            encoded.withUnsafeMutableBufferPointer {
                simdutf_binary_to_base64(source.baseAddress, source.count, $0.baseAddress, SIMDUTF_BASE64_DEFAULT)
            }
        }
        XCTAssertEqual(encodedCount, capacity)
        var output = [CChar](repeating: 0, count: input.count + 3)
        encoded.withUnsafeBufferPointer { source in
            output.withUnsafeMutableBufferPointer {
                let result = simdutf_base64_to_binary(source.baseAddress, encodedCount, $0.baseAddress, SIMDUTF_BASE64_DEFAULT, SIMDUTF_LAST_CHUNK_STRICT)
                XCTAssertEqual(result.error, SIMDUTF_ERROR_SUCCESS)
                XCTAssertEqual(result.count, input.count)
            }
        }
        XCTAssertEqual(Array(output.prefix(input.count)), input)
        let utf16 = encoded.map { UInt16(UInt8(bitPattern: $0)) }
        utf16.withUnsafeBufferPointer { source in
            output.withUnsafeMutableBufferPointer {
                let result = simdutf_base64_to_binary_utf16(source.baseAddress, encodedCount, $0.baseAddress, SIMDUTF_BASE64_DEFAULT, SIMDUTF_LAST_CHUNK_STRICT)
                XCTAssertEqual(result.error, SIMDUTF_ERROR_SUCCESS)
                XCTAssertEqual(result.count, input.count)
            }
        }
        XCTAssertEqual(Array(output.prefix(input.count)), input)
    }

    func testBase64RejectsInvalidCharactersAndRespectsOutputCapacity() {
        var output = [CChar](repeating: 0, count: 8)
        bytes("!!!!").withUnsafeBufferPointer { source in
            output.withUnsafeMutableBufferPointer {
                let result = simdutf_base64_to_binary(source.baseAddress, source.count, $0.baseAddress, SIMDUTF_BASE64_DEFAULT, SIMDUTF_LAST_CHUNK_STRICT)
                XCTAssertEqual(result.error, SIMDUTF_ERROR_INVALID_BASE64_CHARACTER)
                XCTAssertEqual(result.count, 0)
            }
        }
        var capacity = 2
        bytes("TWFu").withUnsafeBufferPointer { source in
            output.withUnsafeMutableBufferPointer {
                let result = simdutf_base64_to_binary_safe(source.baseAddress, source.count, $0.baseAddress, &capacity, SIMDUTF_BASE64_DEFAULT, SIMDUTF_LAST_CHUNK_STRICT, false)
                XCTAssertEqual(result.error, SIMDUTF_ERROR_OUTPUT_BUFFER_TOO_SMALL)
            }
        }
    }
    #endif

    #if DetectEncoding
    func testEncodingDetectionRecognizesUTF8AndUTF16BOM() {
        bytes("Swift 😀").withUnsafeBufferPointer {
            XCTAssertEqual(simdutf_autodetect_encoding($0.baseAddress, $0.count), SIMDUTF_ENCODING_UTF8)
            XCTAssertNotEqual(simdutf_detect_encodings($0.baseAddress, $0.count) & Int32(SIMDUTF_ENCODING_UTF8.rawValue), 0)
        }
        let utf16LE: [UInt8] = [0xFF, 0xFE, 0x41, 0x00, 0x3D, 0xD8, 0x00, 0xDE]
        utf16LE.map { CChar(bitPattern: $0) }.withUnsafeBufferPointer {
            XCTAssertEqual(simdutf_autodetect_encoding($0.baseAddress, $0.count), SIMDUTF_ENCODING_UTF16_LE)
        }
    }
    #endif
}
