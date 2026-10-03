import XCTest
@testable import FloaterCore

final class SecretStoreTests: XCTestCase {
    func testASecretRoundTrips() {
        let store = InMemorySecretStore()
        XCTAssertNil(store.secret(.anthropic))
        XCTAssertFalse(store.has(.anthropic))

        store.setSecret("sk-ant-abc", for: .anthropic)

        XCTAssertEqual(store.secret(.anthropic), "sk-ant-abc")
        XCTAssertTrue(store.has(.anthropic))
    }

    func testSecretsAreKeptApart() {
        let store = InMemorySecretStore()
        store.setSecret("sk-ant-abc", for: .anthropic)
        store.setSecret("xoxp-123", for: .slack)
        XCTAssertEqual(store.secret(.anthropic), "sk-ant-abc")
        XCTAssertEqual(store.secret(.slack), "xoxp-123")

        store.setSecret(nil, for: .slack)
        XCTAssertNil(store.secret(.slack))
        XCTAssertEqual(store.secret(.anthropic), "sk-ant-abc", "clearing one must not touch the other")
    }

    func testAnEmptySecretCountsAsAbsent() {
        let store = InMemorySecretStore()
        store.setSecret("", for: .anthropic)
        XCTAssertFalse(store.has(.anthropic))
    }

    func testSeedingWorksForTests() {
        let store = InMemorySecretStore([.anthropic: "seeded"])
        XCTAssertEqual(store.secret(.anthropic), "seeded")
    }
}
