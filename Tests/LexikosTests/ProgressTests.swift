import XCTest
@testable import Lexikos

final class ProgressTests: XCTestCase {
    private var root: URL!
    private let deck = Deck(name: "t", cards: (0..<6).map { Card(front: "f\($0)", back: "b\($0)") })
    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    override func setUp() {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: root.appendingPathComponent("decks"), withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: root) }
    private var progressDir: URL { root.appendingPathComponent("progress") }

    func testGradingMatchesDirectScheduler() {
        let p = ProgressStore(dir: progressDir)
        p.introduce(deck, card: 0, now: t0)
        p.grade(deck, card: 0, .remembered, now: t0 + 90)
        p.grade(deck, card: 0, .remembered, now: t0 + 4 * 86400)
        let direct = CardState.next(CardState.next(CardState.introduce(nil, now: t0), .remembered, now: t0 + 90),
                                    .remembered, now: t0 + 4 * 86400)
        XCTAssertEqual(p.states(deck)[0], direct)
        // And the log on disk replays to the same thing.
        XCTAssertEqual(ProgressStore(dir: progressDir).states(deck), p.states(deck))
    }

    func testMergeIsOrderIndependent() {
        let mac = ProgressStore(dir: progressDir.appendingPathComponent("mac"))
        let phone = ProgressStore(dir: progressDir.appendingPathComponent("phone"))
        mac.grade(deck, card: 1, .remembered, now: t0)
        phone.grade(deck, card: 1, .forgot, now: t0 + 60)
        phone.grade(deck, card: 2, .vague, now: t0 + 120)
        mac.grade(deck, card: 1, .vague, now: t0 + 600)
        let m = mac.events[deck.id]!, ph = phone.events[deck.id]!
        XCTAssertEqual(mac.merge(ph), 2)
        XCTAssertEqual(phone.merge(m), 2)
        XCTAssertEqual(mac.merge(ph), 0, "duplicates are ignored")
        XCTAssertEqual(mac.states(deck), phone.states(deck))
        XCTAssertEqual(mac.states(deck)[1]?.reviews.map(\.grade), [.remembered, .forgot, .vague])
    }

    func testProgressFollowsCardsAcrossReorder() {
        let p = ProgressStore(dir: progressDir)
        p.grade(deck, card: 4, .remembered, now: t0)
        var shuffled = deck
        shuffled.cards.reverse()
        XCTAssertEqual(Array(p.states(shuffled).keys), [1])
    }

    func testDuplicateCardsKeepSeparateProgress() {
        let dup = Deck(name: "d", cards: [Card(front: "a", back: "b"), Card(front: "a", back: "b")])
        let p = ProgressStore(dir: progressDir)
        p.grade(dup, card: 1, .remembered, now: t0)
        XCTAssertEqual(Array(p.states(dup).keys), [1])
    }

    func testForgetResetsOnlyEarlierEvents() {
        let p = ProgressStore(dir: progressDir)
        p.grade(deck, card: 0, .remembered, now: t0)
        p.forget(deck, now: t0 + 10)
        XCTAssertTrue(p.states(deck).isEmpty)
        p.grade(deck, card: 3, .remembered, now: t0 + 20)
        XCTAssertEqual(Array(p.states(deck).keys), [3])
    }

    func testLegacySnapshotMigratesLosslessly() throws {
        var old: [Int: CardState] = [:]
        old[0] = CardState.next(CardState.next(nil, .remembered, now: t0), .forgot, now: t0 + 3 * 86400)
        old[5] = CardState.introduce(nil, now: t0)
        try FileManager.default.createDirectory(at: progressDir, withIntermediateDirectories: true)
        try JSONEncoder().encode(deck).write(to: root.appendingPathComponent("decks/\(deck.id.uuidString).json"))
        try JSONEncoder().encode(old).write(to: progressDir.appendingPathComponent("\(deck.id.uuidString).json"))

        XCTAssertEqual(ProgressStore(dir: progressDir).states(deck), old)
        XCTAssertTrue(FileManager.default.fileExists(atPath: progressDir.appendingPathComponent("\(deck.id.uuidString).json.legacy").path))
        XCTAssertEqual(ProgressStore(dir: progressDir).states(deck), old, "second launch reads the log, not the snapshot")
    }
}
