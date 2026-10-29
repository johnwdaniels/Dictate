import XCTest
@testable import Dictate

final class InworldAPIKeyStoreTests: XCTestCase {
    private var savedDirectory: URL!
    private var temporary: URL!

    override func setUp() {
        super.setUp()
        savedDirectory = InworldAPIKeyStore.directory
        temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        InworldAPIKeyStore.directory = temporary
        InworldAPIKeyStore.migratesFromKeychain = false
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: temporary)
        InworldAPIKeyStore.directory = savedDirectory
        InworldAPIKeyStore.migratesFromKeychain = true
        super.tearDown()
    }

    func testSavesLoadsAndDeletes() throws {
        XCTAssertNil(try InworldAPIKeyStore.load())
        try InworldAPIKeyStore.save("  test-key\n")
        XCTAssertEqual(try InworldAPIKeyStore.load(), "test-key")
        try InworldAPIKeyStore.save("second-key")
        XCTAssertEqual(try InworldAPIKeyStore.load(), "second-key")
        try InworldAPIKeyStore.delete()
        XCTAssertNil(try InworldAPIKeyStore.load())
    }

    func testOnlyTheUserCanReadTheKey() throws {
        try InworldAPIKeyStore.save("test-key")
        let file = try FileManager.default.attributesOfItem(atPath: InworldAPIKeyStore.fileURL.path)
        let folder = try FileManager.default.attributesOfItem(atPath: temporary.path)
        XCTAssertEqual((file[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertEqual((folder[.posixPermissions] as? NSNumber)?.intValue, 0o700)
    }
}
