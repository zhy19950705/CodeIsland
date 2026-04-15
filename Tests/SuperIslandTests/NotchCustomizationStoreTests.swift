import XCTest
@testable import SuperIsland

@MainActor
final class NotchCustomizationStoreTests: XCTestCase {
    private let defaultsKey = NotchCustomizationStore.defaultsKey

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        UserDefaults.standard.removeObject(forKey: SettingsKey.notchWidthOverride)
        UserDefaults.standard.removeObject(forKey: SettingsKey.panelHorizontalOffset)
        UserDefaults.standard.removeObject(forKey: SettingsKey.hardwareNotchMode)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        UserDefaults.standard.removeObject(forKey: SettingsKey.notchWidthOverride)
        UserDefaults.standard.removeObject(forKey: SettingsKey.panelHorizontalOffset)
        UserDefaults.standard.removeObject(forKey: SettingsKey.hardwareNotchMode)
        super.tearDown()
    }

    func testInitMigratesLegacyWidthAndOffsetSettings() {
        UserDefaults.standard.set(228, forKey: SettingsKey.notchWidthOverride)
        UserDefaults.standard.set(42.0, forKey: SettingsKey.panelHorizontalOffset)
        UserDefaults.standard.set(HardwareNotchMode.forceVirtual.rawValue, forKey: SettingsKey.hardwareNotchMode)

        let store = NotchCustomizationStore()

        XCTAssertEqual(store.customization.defaultGeometry.customWidth, 228, accuracy: 0.001)
        XCTAssertEqual(store.customization.defaultGeometry.horizontalOffset, 42, accuracy: 0.001)
        XCTAssertEqual(store.customization.hardwareNotchMode, .forceVirtual)
    }

    func testUpdateGeometryPersistsPerScreenState() throws {
        let store = NotchCustomizationStore()
        store.updateGeometry(for: "display-1") { geometry in
            geometry.customWidth = 244
            geometry.horizontalOffset = 16
            geometry.notchHeight = 52
        }

        let data = try XCTUnwrap(UserDefaults.standard.data(forKey: defaultsKey))
        let decoded = try JSONDecoder().decode(NotchCustomization.self, from: data)
        let geometry = decoded.geometry(for: "display-1")
        XCTAssertEqual(geometry.customWidth, 244, accuracy: 0.001)
        XCTAssertEqual(geometry.horizontalOffset, 16, accuracy: 0.001)
        XCTAssertEqual(geometry.notchHeight, 52, accuracy: 0.001)
    }

    func testCancelEditRestoresSnapshot() {
        let store = NotchCustomizationStore()
        store.updateGeometry(for: "display-1") { $0.customWidth = 200 }
        store.enterEditMode()
        store.updateGeometry(for: "display-1") { $0.customWidth = 320 }

        store.cancelEdit()

        XCTAssertEqual(store.customization.geometry(for: "display-1").customWidth, 200, accuracy: 0.001)
        XCTAssertFalse(store.isEditing)
    }

    func testCommitEditKeepsChanges() {
        let store = NotchCustomizationStore()
        store.enterEditMode()
        store.updateGeometry(for: "display-1") { $0.horizontalOffset = 88 }

        store.commitEdit()

        XCTAssertEqual(store.customization.geometry(for: "display-1").horizontalOffset, 88, accuracy: 0.001)
        XCTAssertFalse(store.isEditing)
    }
}
