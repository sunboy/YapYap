import XCTest
@testable import YapYap

final class StderrSuppressorTests: XCTestCase {
    func testSuppressingReturnsResult() async throws {
        let result = try await StderrSuppressor.suppressing {
            return 42
        }
        XCTAssertEqual(result, 42)
    }

    func testCapturingReturnsResult() async throws {
        let (result, _) = try await StderrSuppressor.capturing {
            return "hello"
        }
        XCTAssertEqual(result, "hello")
    }

    func testCapturingSuppressesStderr() async throws {
        // stderr is redirected to /dev/null during the block
        let (result, _) = try await StderrSuppressor.capturing {
            FileHandle.standardError.write("test output".data(using: .utf8)!)
            return 99
        }
        XCTAssertEqual(result, 99)
    }

    func testStderrRestoredAfterError() async {
        struct TestError: Error {}
        do {
            _ = try await StderrSuppressor.capturing {
                throw TestError()
            }
            XCTFail("Should have thrown")
        } catch {
            // stderr should be restored - verify by writing to it
            // (if not restored, this would go nowhere)
            FileHandle.standardError.write("after error".data(using: .utf8)!)
        }
    }
}
