import XCTest

@testable import Codogotchi

final class ConfigFileWriterTests: XCTestCase {
  private var tmp: URL!

  override func setUp() {
    super.setUp()
    tmp = FileManager.default.temporaryDirectory
      .appendingPathComponent("ConfigFileWriterTests-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
  }

  override func tearDown() {
    try? FileManager.default.removeItem(at: tmp)
    super.tearDown()
  }

  private func read(_ url: URL) throws -> [String: Any] {
    let data = try Data(contentsOf: url)
    return try JSONSerialization.jsonObject(with: data) as! [String: Any]
  }

  // MARK: - New file

  func testCreatesNewFileWithMergedKeysAndSchemaVersion() throws {
    let url = tmp.appendingPathComponent("out.json")
    try ConfigFileWriter.merge(["foo": "bar"], into: url)
    let obj = try read(url)
    XCTAssertEqual(obj["foo"] as? String, "bar")
    XCTAssertEqual(obj["schema_version"] as? Int, 1)
  }

  // MARK: - Merge preserves unmanaged keys

  func testSecondMergePreservesKeysFromFirstWrite() throws {
    let url = tmp.appendingPathComponent("out.json")
    try ConfigFileWriter.merge(["alpha": 1], into: url)
    try ConfigFileWriter.merge(["beta": 2], into: url)
    let obj = try read(url)
    XCTAssertEqual(obj["alpha"] as? Int, 1)
    XCTAssertEqual(obj["beta"] as? Int, 2)
  }

  // MARK: - NSNull removes key

  func testNSNullRemovesKey() throws {
    let url = tmp.appendingPathComponent("out.json")
    try ConfigFileWriter.merge(["keep": "yes", "drop": "no"], into: url)
    try ConfigFileWriter.merge(["drop": NSNull()], into: url)
    let obj = try read(url)
    XCTAssertEqual(obj["keep"] as? String, "yes")
    XCTAssertNil(obj["drop"])
  }

  // MARK: - Existing schema_version is preserved

  func testExistingSchemaVersionIsNotReset() throws {
    let url = tmp.appendingPathComponent("out.json")
    try #"{"schema_version": 3, "x": 1}"#.write(to: url, atomically: true, encoding: .utf8)
    try ConfigFileWriter.merge(["y": 2], into: url)
    let obj = try read(url)
    XCTAssertEqual(obj["schema_version"] as? Int, 3)
  }

  // MARK: - Corrupt existing file throws

  func testThrowsWhenExistingFileIsCorrupt() throws {
    let url = tmp.appendingPathComponent("out.json")
    try "not json {{{".write(to: url, atomically: true, encoding: .utf8)
    XCTAssertThrowsError(try ConfigFileWriter.merge(["x": 1], into: url))
  }

  func testDoesNotOverwriteCorruptFile() throws {
    let url = tmp.appendingPathComponent("out.json")
    let original = "not json {{{"
    try original.write(to: url, atomically: true, encoding: .utf8)
    _ = try? ConfigFileWriter.merge(["x": 1], into: url)
    let after = try String(contentsOf: url, encoding: .utf8)
    XCTAssertEqual(after, original, "corrupt file must not be clobbered on failure")
  }
}
