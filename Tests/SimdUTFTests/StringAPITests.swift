import SimdUTF
import XCTest

final class StringAPITests: XCTestCase {
    private enum BufferError: Error { case expected }

    #if UTF8
    func testUTF8StringConstructionAndAppendPreserveUnicodeAndNulls() {
        let text = String(repeating: "Swift\0 café 中文 😀", count: 193)
        let input = Array(text.utf8)
        input.withUnsafeBufferPointer { buffer in
            XCTAssertEqual(String(validatingUTF8: buffer), text)
            XCTAssertEqual(String(decodingUTF8: buffer), text)
            XCTAssertEqual(String(uncheckedUTF8: buffer), text)
            var appended = "prefix:"
            appended.append(decodingUTF8: buffer)
            XCTAssertEqual(appended, "prefix:" + text)
        }
        let empty = UnsafeBufferPointer<UInt8>(start: nil, count: 0)
        XCTAssertEqual(String(validatingUTF8: empty), "")
        XCTAssertEqual(String(decodingUTF8: empty), "")
        XCTAssertEqual(String(uncheckedUTF8: empty), "")
        var appended = "unchanged"
        appended.append(decodingUTF8: empty)
        XCTAssertEqual(appended, "unchanged")
    }

    func testUTF8RejectingAndRepairingInitializersHaveDifferentContracts() {
        let malformed: [[UInt8]] = [
            [0x61, 0xC0, 0xAF, 0x62],
            [0xF0, 0x9F, 0x98],
            [0xED, 0xA0, 0x80, 0],
            Array(repeating: 0x61, count: 129) + [0xFF, 0x62],
        ]
        for input in malformed {
            let repaired = String(decoding: input, as: UTF8.self)
            input.withUnsafeBufferPointer { buffer in
                XCTAssertNil(String(validatingUTF8: buffer))
                XCTAssertEqual(String(decodingUTF8: buffer), repaired)
                var appended = "prefix:"
                appended.append(decodingUTF8: buffer)
                XCTAssertEqual(appended, "prefix:" + repaired)
            }
        }
    }

    func testUTF8StringCopiesBorrowedStorage() {
        var input = Array(String(repeating: "owned\0é😀", count: 193).utf8)
        let expected = String(decoding: input, as: UTF8.self)
        let owned = input.withUnsafeBufferPointer { String(uncheckedUTF8: $0) }
        input = [0x61]
        XCTAssertEqual(owned, expected)
    }
    #endif

    #if UTF8 && UTF16
    func testUTF16ConstructionAppendAndMalformedRepair() {
        let text = String(repeating: "A\0é中😀", count: 193)
        Array(text.utf16).withUnsafeBufferPointer { buffer in
            XCTAssertEqual(String(validatingUTF16: buffer), text)
            XCTAssertEqual(String(decodingUTF16: buffer), text)
            var appended = "prefix:"
            appended.append(decodingUTF16: buffer)
            XCTAssertEqual(appended, "prefix:" + text)
        }
        let malformed: [UInt16] = [0xD800, 0x61, 0, 0xDC00, 0xD83D, 0xDE00, 0xD800]
        malformed.withUnsafeBufferPointer { buffer in
            XCTAssertNil(String(validatingUTF16: buffer))
            XCTAssertEqual(String(decodingUTF16: buffer), "�a\0�😀�")
            var appended = "prefix:"
            appended.append(decodingUTF16: buffer)
            XCTAssertEqual(appended, "prefix:�a\0�😀�")
        }
        let longMalformed = Array(repeating: UInt16(0x61), count: 129) + malformed
        longMalformed.withUnsafeBufferPointer {
            XCTAssertNil(String(validatingUTF16: $0))
            XCTAssertEqual(String(decodingUTF16: $0), String(decoding: longMalformed, as: UTF16.self))
        }
        let empty = UnsafeBufferPointer<UInt16>(start: nil, count: 0)
        XCTAssertEqual(String(validatingUTF16: empty), "")
        XCTAssertEqual(String(decodingUTF16: empty), "")
        var appended = "unchanged"
        appended.append(decodingUTF16: empty)
        XCTAssertEqual(appended, "unchanged")
    }

    func testScopedUTF16BuffersPreserveValuesAndPropagateThrownErrors() {
        let text = String(repeating: "A\0é中😀", count: 193)
        let expected = Array(text.utf16)
        XCTAssertEqual(text.withUTF16 { Array($0) }, expected)
        XCTAssertEqual("".withUTF16 { $0.count }, 0)
        var invocations = 0
        XCTAssertThrowsError(try text.withUTF16 { _ -> Void in
            invocations += 1
            throw BufferError.expected
        }) { XCTAssertTrue($0 is BufferError) }
        XCTAssertEqual(invocations, 1)
        var input = Array(text.utf8)
        let copied = input.withUnsafeBufferPointer { $0.withUTF16 { Array($0) } }
        input = [0x61]
        XCTAssertEqual(copied, expected)
        XCTAssertThrowsError(try input.withUnsafeBufferPointer { buffer in
            try buffer.withUTF16 { _ -> Void in throw BufferError.expected }
        })
        XCTAssertEqual(UnsafeBufferPointer<UInt8>(start: nil, count: 0).withUTF16 { $0.count }, 0)
    }
    #endif

    #if UTF8 && UTF32
    func testUTF32ConstructionAppendAndMalformedRepair() {
        let text = String(repeating: "A\0é中😀", count: 193)
        text.unicodeScalars.map(\.value).withUnsafeBufferPointer { buffer in
            XCTAssertEqual(String(validatingUTF32: buffer), text)
            XCTAssertEqual(String(decodingUTF32: buffer), text)
            var appended = "prefix:"
            appended.append(decodingUTF32: buffer)
            XCTAssertEqual(appended, "prefix:" + text)
        }
        let malformed: [UInt32] = [0xD800, 0x61, 0, 0x110000, 0x1F600, 0xFFFFFFFF]
        malformed.withUnsafeBufferPointer { buffer in
            XCTAssertNil(String(validatingUTF32: buffer))
            XCTAssertEqual(String(decodingUTF32: buffer), "�a\0�😀�")
            var appended = "prefix:"
            appended.append(decodingUTF32: buffer)
            XCTAssertEqual(appended, "prefix:�a\0�😀�")
        }
        let longMalformed = Array(repeating: UInt32(0x61), count: 129) + malformed
        longMalformed.withUnsafeBufferPointer {
            XCTAssertNil(String(validatingUTF32: $0))
            XCTAssertEqual(String(decodingUTF32: $0), String(repeating: "a", count: 129) + "�a\0�😀�")
        }
        let empty = UnsafeBufferPointer<UInt32>(start: nil, count: 0)
        XCTAssertEqual(String(validatingUTF32: empty), "")
        XCTAssertEqual(String(decodingUTF32: empty), "")
        var appended = "unchanged"
        appended.append(decodingUTF32: empty)
        XCTAssertEqual(appended, "unchanged")
    }

    func testScopedUTF32BuffersPreserveValuesAndPropagateThrownErrors() {
        let text = String(repeating: "A\0é中😀", count: 193)
        let expected = text.unicodeScalars.map(\.value)
        XCTAssertEqual(text.withUTF32 { Array($0) }, expected)
        XCTAssertEqual("".withUTF32 { $0.count }, 0)
        var invocations = 0
        XCTAssertThrowsError(try text.withUTF32 { _ -> Void in
            invocations += 1
            throw BufferError.expected
        }) { XCTAssertTrue($0 is BufferError) }
        XCTAssertEqual(invocations, 1)
        var input = Array(text.utf8)
        let copied = input.withUnsafeBufferPointer { $0.withUTF32 { Array($0) } }
        input = [0x61]
        XCTAssertEqual(copied, expected)
        XCTAssertThrowsError(try input.withUnsafeBufferPointer { buffer in
            try buffer.withUTF32 { _ -> Void in throw BufferError.expected }
        })
        XCTAssertEqual(UnsafeBufferPointer<UInt8>(start: nil, count: 0).withUTF32 { $0.count }, 0)
    }
    #endif

    #if ASCII
    func testASCIIStringValidationConstructionAndAppend() {
        let text = String(repeating: "ASCII\0", count: 193)
        Array(text.utf8).withUnsafeBufferPointer { buffer in
            XCTAssertEqual(String(validatingASCII: buffer), text)
            XCTAssertEqual(String(uncheckedASCII: buffer), text)
            var appended = "prefix:"
            appended.append(uncheckedASCII: buffer)
            XCTAssertEqual(appended, "prefix:" + text)
        }
        XCTAssertTrue(text.isASCII)
        XCTAssertTrue("".isASCII)
        XCTAssertFalse("café".isASCII)
        XCTAssertFalse("😀".isASCII)
        [UInt8(0x61), 0x80].withUnsafeBufferPointer { XCTAssertNil(String(validatingASCII: $0)) }
        (Array(text.utf8) + [UInt8(0x80)]).withUnsafeBufferPointer {
            XCTAssertNil(String(validatingASCII: $0))
        }
        let empty = UnsafeBufferPointer<UInt8>(start: nil, count: 0)
        XCTAssertEqual(String(validatingASCII: empty), "")
        XCTAssertEqual(String(uncheckedASCII: empty), "")
        var appended = "unchanged"
        appended.append(uncheckedASCII: empty)
        XCTAssertEqual(appended, "unchanged")
    }
    #endif

    #if UTF8 && Latin1
    func testLatin1RoundTripRepresentabilityAppendAndEmptyInput() {
        let input = (0..<256).map(UInt8.init)
        let expected = String(String.UnicodeScalarView((0..<256).map { UnicodeScalar($0)! }))
        input.withUnsafeBufferPointer { buffer in
            let text = String(decodingLatin1: buffer)
            XCTAssertEqual(text, expected)
            XCTAssertEqual(text.latin1Encoded(), input)
            var appended = "prefix:"
            appended.append(decodingLatin1: buffer)
            XCTAssertEqual(appended, "prefix:" + expected)
        }
        XCTAssertNil("中文".latin1Encoded())
        XCTAssertNil("😀".latin1Encoded())
        XCTAssertEqual("".latin1Encoded(), [])
        let empty = UnsafeBufferPointer<UInt8>(start: nil, count: 0)
        XCTAssertEqual(String(decodingLatin1: empty), "")
        var appended = "unchanged"
        appended.append(decodingLatin1: empty)
        XCTAssertEqual(appended, "unchanged")
    }
    #endif

    #if Base64
    func testBase64StringRoundTripOptionsAndMalformedInput() {
        let input = (0..<513).map { UInt8($0 % 256) }
        let encoded = input.withUnsafeBufferPointer { $0.base64EncodedString() }
        XCTAssertEqual(encoded.base64DecodedBytes(), input)
        XCTAssertEqual("TWFuAA==".base64DecodedBytes(), [0x4D, 0x61, 0x6E, 0])
        XCTAssertEqual(" T W F u\n".base64DecodedBytes(), [0x4D, 0x61, 0x6E])
        XCTAssertEqual(" \t\r\n".base64DecodedBytes(), [])
        XCTAssertNil("!!!!".base64DecodedBytes())
        XCTAssertNil("A".base64DecodedBytes())
        XCTAssertNil("TWFu\0".base64DecodedBytes())
        let urlInput: [UInt8] = [0xFB, 0xFF]
        let urlEncoded = urlInput.withUnsafeBufferPointer { $0.base64EncodedString(options: SIMDUTF_BASE64_URL) }
        XCTAssertEqual(urlEncoded, "-_8")
        XCTAssertEqual(urlEncoded.base64DecodedBytes(options: SIMDUTF_BASE64_URL), urlInput)
        XCTAssertNil("Zh==".base64DecodedBytes(lastChunkHandling: SIMDUTF_LAST_CHUNK_STRICT))
        XCTAssertEqual("".base64DecodedBytes(), [])
        XCTAssertEqual(UnsafeBufferPointer<UInt8>(start: nil, count: 0).base64EncodedString(), "")
    }
    #endif

    #if DetectEncoding
    func testUnicodeEncodingDetectionUsesAnOptionSet() {
        let utf8 = Array("Swift 😀".utf8)
        utf8.withUnsafeBufferPointer { XCTAssertTrue($0.detectedUnicodeEncodings.contains(.utf8)) }
        let utf16: [UInt8] = [0xFF, 0xFE, 0x41, 0, 0x3D, 0xD8, 0, 0xDE]
        utf16.withUnsafeBufferPointer {
            XCTAssertTrue($0.detectedUnicodeEncodings.contains(.utf16LE))
            XCTAssertFalse($0.detectedUnicodeEncodings.contains(.utf8))
        }
        let selected: UnicodeEncoding = [.utf8, .utf16LE]
        XCTAssertTrue(selected.contains(.utf8))
        XCTAssertTrue(selected.contains(.utf16LE))
        XCTAssertFalse(selected.contains(.utf32BE))
        XCTAssertTrue(UnsafeBufferPointer<UInt8>(start: nil, count: 0).detectedUnicodeEncodings.contains(.utf8))
    }
    #endif
}
