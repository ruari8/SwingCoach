import XCTest

/// The built app permits only upright portrait, on iPhone and iPad.
final class InterfaceOrientationPolicyTests: XCTestCase {
    func testBuiltAppIsPortraitOnly() throws {
        // Read the built file: at runtime, infoDictionary folds the ~iphone
        // key into the plain one and drops ~ipad.
        let data = try Data(contentsOf: Bundle.main.bundleURL.appendingPathComponent("Info.plist"))
        let info = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        for key in ["UISupportedInterfaceOrientations~iphone", "UISupportedInterfaceOrientations~ipad"] {
            XCTAssertEqual(info[key] as? [String], ["UIInterfaceOrientationPortrait"], key)
        }
        XCTAssertEqual(info["UIRequiresFullScreen"] as? Bool, true)
    }
}
