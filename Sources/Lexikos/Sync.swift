import CloudKit
import Foundation
import os

/// iCloud sync of decks and review events through the user's private CloudKit database.
/// Decks are "Deck" records (name + cards as an asset); every review event is an immutable "Event" record,
/// so the only possible conflict is two devices re-importing the same deck, where the server copy wins.
@MainActor final class Sync {
    static let container = "iCloud.com.yixuanwu.lexikos"
    private static let zone = CKRecordZone.ID(zoneName: "Lexikos")
    private static let log = Logger(subsystem: "com.yixuanwu.lexikos", category: "sync")

    private let decks: DeckStore, progress: ProgressStore
    private var engine: CKSyncEngine!
    private let stateFile = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Lexikos/sync-state.json")
    /// Record names the server is known to hold. Anything local that is missing gets queued on launch,
    /// so a failed or dropped upload is retried instead of lost.
    private var onServer: Set<String>
    private let onServerFile = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Lexikos/sync-uploaded.json")

    init(decks: DeckStore, progress: ProgressStore) {
        self.decks = decks
        self.progress = progress
        onServer = (try? JSONDecoder().decode(Set<String>.self, from: Data(contentsOf: onServerFile))) ?? []
        let saved = try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: Data(contentsOf: stateFile))
        let delegate = Delegate(owner: self)
        engine = CKSyncEngine(.init(database: CKContainer(identifier: Self.container).privateCloudDatabase,
                                    stateSerialization: saved, delegate: delegate))
        self.delegate = delegate
        decks.onSave = { [weak self] in self?.enqueue(.saveRecord(Self.id(deck: $0.id))) }
        decks.onDelete = { [weak self] in self?.enqueue(.deleteRecord(Self.id(deck: $0))) }
        progress.onRecord = { [weak self] in self?.enqueue(.saveRecord(Self.id(event: $0.id))) }
        enqueueAll()
    }
    private var delegate: Delegate?

    /// Pull and push now (on launch and when returning to the foreground; pushes from other devices also trigger fetches).
    func syncNow() async {
        do {
            try await engine.fetchChanges()
            try await engine.sendChanges()
        } catch { Self.log.error("sync: \(error, privacy: .public)") }
    }

    private func enqueue(_ change: CKSyncEngine.PendingRecordZoneChange) {
        engine.state.add(pendingRecordZoneChanges: [change])
    }

    /// Everything stored on this device that the server is not known to hold.
    private func enqueueAll() {
        let ids = decks.decks.map { Self.id(deck: $0.id) } + progress.byID.keys.map { Self.id(event: $0) }
        let missing = ids.filter { !onServer.contains($0.recordName) }
        guard !missing.isEmpty else { return }
        if onServer.isEmpty { engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zone))]) }
        engine.state.add(pendingRecordZoneChanges: missing.map { .saveRecord($0) })
    }

    private func markOnServer(_ names: [String]) {
        guard !names.isEmpty else { return }
        onServer.formUnion(names)
        try? JSONEncoder().encode(onServer).write(to: onServerFile)
    }

    // MARK: Records

    private static func id(deck: UUID) -> CKRecord.ID { CKRecord.ID(recordName: "deck-\(deck.uuidString)", zoneID: zone) }
    private static func id(event: UUID) -> CKRecord.ID { CKRecord.ID(recordName: "event-\(event.uuidString)", zoneID: zone) }

    fileprivate func record(for id: CKRecord.ID) -> CKRecord? {
        let name = id.recordName
        if name.hasPrefix("deck-"), let uuid = UUID(uuidString: String(name.dropFirst(5))), let deck = decks.deck(uuid) {
            let r = CKRecord(recordType: "Deck", recordID: id)
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).json")
            guard (try? JSONEncoder().encode(deck.cards).write(to: file)) != nil else { return nil }
            r["name"] = deck.name
            r["cards"] = CKAsset(fileURL: file)
            return r
        }
        if name.hasPrefix("event-"), let uuid = UUID(uuidString: String(name.dropFirst(6))), let e = progress.byID[uuid],
           let payload = try? JSONEncoder().encode(e) {
            let r = CKRecord(recordType: "Event", recordID: id)
            r["deck"] = e.deck.uuidString
            r["payload"] = payload
            return r
        }
        return nil // gone locally (e.g. deck deleted before upload): drop the change
    }

    fileprivate func apply(_ records: [CKRecord], deleted: [CKRecord.ID]) {
        var events: [ReviewEvent] = []
        for r in records {
            switch r.recordType {
            case "Deck":
                guard let uuid = UUID(uuidString: String(r.recordID.recordName.dropFirst(5))),
                      let name = r["name"] as? String, let url = (r["cards"] as? CKAsset)?.fileURL,
                      let cards = try? JSONDecoder().decode([Card].self, from: Data(contentsOf: url)) else { continue }
                decks.upsert(Deck(id: uuid, name: name, cards: cards))
            case "Event":
                if let data = r["payload"] as? Data, let e = try? JSONDecoder().decode(ReviewEvent.self, from: data) { events.append(e) }
            default: break
            }
        }
        if !events.isEmpty { progress.merge(events) }
        for id in deleted where id.recordName.hasPrefix("deck-") {
            if let uuid = UUID(uuidString: String(id.recordName.dropFirst(5))) { decks.remove(uuid) }
        }
    }

    // MARK: Engine events

    fileprivate func handle(_ event: CKSyncEngine.Event) {
        switch event {
        case .stateUpdate(let u):
            try? JSONEncoder().encode(u.stateSerialization).write(to: stateFile)
        case .accountChange(let c):
            switch c.changeType {
            case .signIn: enqueueAll()
            case .switchAccounts, .signOut:
                // Local data stays; it will upload to whichever account signs in next.
                try? FileManager.default.removeItem(at: stateFile)
                try? FileManager.default.removeItem(at: onServerFile)
                onServer = []
            @unknown default: break
            }
        case .fetchedRecordZoneChanges(let f):
            apply(f.modifications.map(\.record), deleted: f.deletions.map(\.recordID))
            markOnServer(f.modifications.map(\.record.recordID.recordName))
        case .sentRecordZoneChanges(let s):
            markOnServer(s.savedRecords.map(\.recordID.recordName))
            for failure in s.failedRecordSaves {
                switch failure.error.code {
                case .serverRecordChanged:
                    if let server = failure.error.serverRecord { apply([server], deleted: []) }
                    markOnServer([failure.record.recordID.recordName])
                case .zoneNotFound:
                    engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zone))])
                    enqueue(.saveRecord(failure.record.recordID))
                case .batchRequestFailed, .networkFailure, .networkUnavailable, .serviceUnavailable, .requestRateLimited, .zoneBusy:
                    enqueue(.saveRecord(failure.record.recordID))
                default:
                    Self.log.error("save \(failure.record.recordID.recordName, privacy: .public): \(failure.error, privacy: .public)")
                }
            }
        case .fetchedDatabaseChanges(let f):
            // The zone was deleted elsewhere (e.g. iCloud data reset): upload everything again.
            if f.deletions.contains(where: { $0.zoneID == Self.zone }) {
                onServer = []
                try? FileManager.default.removeItem(at: onServerFile)
                enqueueAll()
            }
        default: break
        }
    }

    fileprivate func nextBatch(_ context: CKSyncEngine.SendChangesContext) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let pending = engine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: Array(pending.prefix(300))) { id in
            await self.record(for: id)
        }
    }

    /// CKSyncEngine holds its delegate weakly and calls it off the main actor.
    private final class Delegate: CKSyncEngineDelegate, @unchecked Sendable {
        weak var owner: Sync?
        init(owner: Sync) { self.owner = owner }

        func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
            await owner?.handle(event)
        }

        func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
            await owner?.nextBatch(context)
        }
    }
}

/// Study settings follow the user across devices through iCloud key-value storage.
/// Appearance and accent stay per device.
@MainActor final class SettingsSync {
    private static let keys = ["lang", "newPerDay", "groupSize", "autoSpeak", "startDeck"]
    private let cloud = NSUbiquitousKeyValueStore.default
    private var observers: [NSObjectProtocol] = []

    init() {
        observers.append(NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: cloud, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.pull() }
            })
        observers.append(NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.push() }
            })
        cloud.synchronize()
        pull()
    }

    private func pull() {
        let d = UserDefaults.standard
        for k in Self.keys {
            if let v = cloud.object(forKey: k), !(d.object(forKey: k) as AnyObject).isEqual(v) { d.set(v, forKey: k) }
        }
    }

    private func push() {
        let d = UserDefaults.standard
        for k in Self.keys {
            if let v = d.object(forKey: k), !(cloud.object(forKey: k) as AnyObject).isEqual(v) { cloud.set(v, forKey: k) }
        }
    }
}
