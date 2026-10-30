import XCTest
@testable import Lexikos

final class ImportTests: XCTestCase {
    func testCleanStripsMarkup() {
        XCTAssertEqual(Importer.clean("un<br>deux&nbsp;[sound:x.mp3]"), "un\ndeux")
    }
}
