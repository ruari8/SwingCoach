import XCTest
@testable import SwingCoach

final class FootageCameraTests: XCTestCase {
    func testLaunchOptionsReadFoldersInNameOrderWithDefaults() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for name in ["000020.000.mov", "000000.000.mov", "notes.txt", "clip.MP4"] {
            FileManager.default.createFile(atPath: folder.appendingPathComponent(name).path, contents: Data())
        }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "FootageCameraTests"))
        defer { defaults.removePersistentDomain(forName: "FootageCameraTests") }

        XCTAssertNil(FootageCamera.Configuration.fromLaunchArguments(defaults), "off without -footage-camera")

        defaults.set(folder.path, forKey: "footage-camera")
        let folderConfiguration = try XCTUnwrap(FootageCamera.Configuration.fromLaunchArguments(defaults))
        XCTAssertEqual(folderConfiguration.urls.map(\.lastPathComponent), ["000000.000.mov", "000020.000.mov", "clip.MP4"])
        XCTAssertEqual(folderConfiguration.timeScale, 1)
        XCTAssertEqual(folderConfiguration.bufferCount, 15)
        XCTAssertEqual(folderConfiguration.impacts, [])

        defaults.set(folder.appendingPathComponent("clip.MP4").path + "," + folder.appendingPathComponent("missing.mov").path,
                     forKey: "footage-camera")
        defaults.set("8", forKey: "footage-camera-time-scale")
        defaults.set("6", forKey: "footage-camera-buffers")
        defaults.set("41.3, 19.5,bad", forKey: "footage-camera-impacts")
        let fileConfiguration = try XCTUnwrap(FootageCamera.Configuration.fromLaunchArguments(defaults))
        XCTAssertEqual(fileConfiguration.urls.map(\.lastPathComponent), ["clip.MP4"], "missing files are skipped")
        XCTAssertEqual(fileConfiguration.timeScale, 8)
        XCTAssertEqual(fileConfiguration.bufferCount, 6)
        XCTAssertEqual(fileConfiguration.impacts, [19.5, 41.3])
    }
}
