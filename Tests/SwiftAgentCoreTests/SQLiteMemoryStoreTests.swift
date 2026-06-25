import Foundation
import XCTest
@testable import SwiftAgentCore

// MARK: - Codable struct for roundtrip testing

struct TestRecord: Codable, Sendable, Equatable {
    let id: String
    let count: Int
    let tags: [String]
}

// MARK: - SQLiteMemoryStoreTests

final class SQLiteMemoryStoreTests: XCTestCase {
    private var dbPaths: [URL] = []

    override func tearDown() {
        for path in dbPaths {
            try? FileManager.default.removeItem(at: path)
        }
        dbPaths.removeAll()
    }

    private func makeTempDBPath() -> URL {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_memory_\(UUID().uuidString).db")
        dbPaths.append(path)
        return path
    }

    // MARK: - Test 1: Init creates database and schema

    func testInitCreatesDatabaseAndSchema() async throws {
        let dbPath = makeTempDBPath()
        let store = try SQLiteMemoryStore(location: dbPath.path)

        // Verify the database file exists
        XCTAssertTrue(FileManager.default.fileExists(atPath: dbPath.path))

        // Verify we can list namespaces (empty initially)
        let namespaces = try await store.listNamespaces()
        XCTAssertEqual(namespaces, [], "Should have no namespaces on fresh DB")
    }

    // MARK: - Test 2: store + retrieve roundtrip (String)

    func testStoreAndRetrieveString() async throws {
        let dbPath = makeTempDBPath()
        let store = try SQLiteMemoryStore(location: dbPath.path)

        try await store.store(key: "k1", namespace: "default", value: "hello")

        let retrieved: String? = try await store.retrieve(key: "k1", namespace: "default")

        XCTAssertEqual(retrieved, "hello")
    }

    // MARK: - Test 3: Store with same key overwrites

    func testStoreOverwritesExistingKey() async throws {
        let dbPath = makeTempDBPath()
        let store = try SQLiteMemoryStore(location: dbPath.path)

        try await store.store(key: "k1", namespace: "default", value: "first")
        let first: String? = try await store.retrieve(key: "k1", namespace: "default")
        XCTAssertEqual(first, "first")

        // Overwrite with new value
        try await store.store(key: "k1", namespace: "default", value: "second")
        let second: String? = try await store.retrieve(key: "k1", namespace: "default")
        XCTAssertEqual(second, "second")
    }

    // MARK: - Test 4: Retrieve non-existent key returns nil

    func testRetrieveNonExistentKeyReturnsNil() async throws {
        let dbPath = makeTempDBPath()
        let store = try SQLiteMemoryStore(location: dbPath.path)

        let retrieved: String? = try await store.retrieve(key: "nonexistent", namespace: "default")

        XCTAssertNil(retrieved)
    }

    // MARK: - Test 5: search finds matching entries

    func testSearchFindsMatchingEntries() async throws {
        let dbPath = makeTempDBPath()
        let store = try SQLiteMemoryStore(location: dbPath.path)

        try await store.store(key: "hello_world", namespace: "default", value: "greeting")
        try await store.store(key: "goodbye", namespace: "default", value: "farewell hello")
        try await store.store(key: "sunny_day", namespace: "default", value: "weather")

        let results = try await store.search(query: "hello", namespace: "default")

        XCTAssertEqual(results.count, 2, "Should find 2 entries matching 'hello'")
        let keys = results.map(\.key).sorted()
        XCTAssertEqual(keys, ["goodbye", "hello_world"])
    }

    // MARK: - Test 6: search with no matches returns empty

    func testSearchNoMatchesReturnsEmpty() async throws {
        let dbPath = makeTempDBPath()
        let store = try SQLiteMemoryStore(location: dbPath.path)

        try await store.store(key: "hello", namespace: "default", value: "world")

        let results = try await store.search(query: "nonexistent", namespace: "default")

        XCTAssertEqual(results.count, 0)
    }

    // MARK: - Test 7: summarize returns entry count and key listing

    func testSummarizeReturnsCountAndKeyListing() async throws {
        let dbPath = makeTempDBPath()
        let store = try SQLiteMemoryStore(location: dbPath.path)

        try await store.store(key: "k1", namespace: "default", value: "val1")
        try await store.store(key: "k2", namespace: "default", value: "val2")

        let summary = try await store.summarize(namespace: "default")

        XCTAssertTrue(summary.contains("2 entries"), "Summary should mention entry count")
        XCTAssertTrue(summary.contains("k1"), "Summary should list keys")
        XCTAssertTrue(summary.contains("k2"), "Summary should list all keys")
    }

    // MARK: - Test 8: forget removes entry

    func testForgetRemovesEntry() async throws {
        let dbPath = makeTempDBPath()
        let store = try SQLiteMemoryStore(location: dbPath.path)

        try await store.store(key: "k1", namespace: "default", value: "value1")

        // Verify stored
        let before: String? = try await store.retrieve(key: "k1", namespace: "default")
        XCTAssertEqual(before, "value1")

        // Forget
        try await store.forget(key: "k1", namespace: "default")

        // Verify removed
        let after: String? = try await store.retrieve(key: "k1", namespace: "default")
        XCTAssertNil(after)
    }

    // MARK: - Test 9: listNamespaces returns distinct namespaces

    func testListNamespacesReturnsDistinctNamespaces() async throws {
        let dbPath = makeTempDBPath()
        let store = try SQLiteMemoryStore(location: dbPath.path)

        try await store.store(key: "a", namespace: "ns1", value: "x")
        try await store.store(key: "b", namespace: "ns2", value: "y")
        try await store.store(key: "c", namespace: "ns1", value: "z")

        let namespaces = try await store.listNamespaces()

        XCTAssertEqual(namespaces.sorted(), ["ns1", "ns2"])
    }

    // MARK: - Test 10: Codable roundtrip preserves all fields

    func testCodableRoundtripPreservesAllFields() async throws {
        let dbPath = makeTempDBPath()
        let store = try SQLiteMemoryStore(location: dbPath.path)

        let record = TestRecord(id: "record1", count: 42, tags: ["important", "urgent"])

        try await store.store(key: "testRecord", namespace: "records", value: record)

        let retrieved: TestRecord? = try await store.retrieve(key: "testRecord", namespace: "records")

        XCTAssertEqual(retrieved, record)
    }

    // MARK: - Test 11: Schema migration applies all steps on fresh DB

    func testSchemaMigrationAppliesAllSteps() async throws {
        let dbPath = makeTempDBPath()

        // First init: fresh DB, should migrate from v0 -> v4
        let store1 = try SQLiteMemoryStore(location: dbPath.path)

        // Verify we can use all operations after migration
        try await store1.store(key: "k1", namespace: "default", value: "test")

        let retrieved1: String? = try await store1.retrieve(key: "k1", namespace: "default")
        XCTAssertEqual(retrieved1, "test")

        // Second init: same DB, already at latest version, should be no-op
        let store2 = try SQLiteMemoryStore(location: dbPath.path)

        let retrieved2: String? = try await store2.retrieve(key: "k1", namespace: "default")
        XCTAssertEqual(retrieved2, "test", "Data should survive second init")
    }

    // MARK: - Test 12: Persistence across store instances

    func testPersistenceAcrossInstances() async throws {
        let dbPath = makeTempDBPath()

        // Write via first store instance
        let store1 = try SQLiteMemoryStore(location: dbPath.path)
        try await store1.store(key: "persistent", namespace: "test", value: "survives")

        // Deinit store1 by letting it go out of this scope
        // Create a new store instance pointing at the same DB
        let store2 = try SQLiteMemoryStore(location: dbPath.path)

        let retrieved: String? = try await store2.retrieve(key: "persistent", namespace: "test")

        XCTAssertEqual(retrieved, "survives", "Data should persist across store instances")
    }
}
