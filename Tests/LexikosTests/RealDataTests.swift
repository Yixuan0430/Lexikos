import XCTest
@testable import Lexikos

/// Run with LEXIKOS_DATA=<copy of Application Support/Lexikos> to check migration against real progress.
final class RealDataTests: XCTestCase {
    func testRealSnapshotsMigrateLosslessly() throws {
        guard let path = ProcessInfo.processInfo.environment["LEXIKOS_DATA"] else { throw XCTSkip("LEXIKOS_DATA not set") }
        let root = URL(fileURLWithPath: path), progressDir = root.appendingPathComponent("progress")
        let decks = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("decks"), includingPropertiesForKeys: nil)
            .map { try JSONDecoder().decode(Deck.self, from: Data(contentsOf: $0)) }
        var before: [UUID: [Int: CardState]] = [:]
        for d in decks {
            let f = progressDir.appendingPathComponent("\(d.id.uuidString).json")
            before[d.id] = try JSONDecoder().decode([Int: CardState].self, from: Data(contentsOf: f))
                .filter { d.cards.indices.contains($0.key) }
        }
        let store = ProgressStore(dir: progressDir)
        for d in decks {
            XCTAssertEqual(store.states(d), before[d.id], d.name)
            print(d.name, before[d.id]!.count, "cards with progress")
        }
    }
}
