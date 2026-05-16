import XCTest
@testable import NFCPlugin

class NFCTests: XCTestCase {
    func testEcho() {
        // This is an example of a functional test case for a plugin.
        // Use XCTAssert and related functions to verify your tests produce the correct results.

        let implementation = NFC()
        let value = "Hello, World!"
        let result = implementation.echo(value)

        XCTAssertEqual(value, result)
    }

    func testEmptyNDEFReadErrorIsClassifiedAsEmptyTagResult() {
        let error = NSError(
            domain: "com.apple.NFCError",
            code: 0,
            userInfo: [NSLocalizedDescriptionKey: "NDEF tag does not contain any NDEF message"]
        )

        XCTAssertTrue(NFCReader.isEmptyNDEFMessageReadError(error))
    }

    func testNonEmptyNDEFReadErrorIsNotClassifiedAsEmptyTagResult() {
        let error = NSError(
            domain: "com.apple.NFCError",
            code: 0,
            userInfo: [NSLocalizedDescriptionKey: "Failed to read NDEF message"]
        )

        XCTAssertFalse(NFCReader.isEmptyNDEFMessageReadError(error))
    }
}
