import CoreAudio
import XCTest
@testable import ParrotCore

final class PreferredInputTests: XCTestCase {
    func testABluetoothDefaultGivesWayToTheBuiltInMicrophone() {
        XCTAssertEqual(PreferredInput.choose(defaultIsBluetooth: true, builtIn: 42), 42)
    }

    func testOtherDefaultsAreKept() {
        XCTAssertNil(PreferredInput.choose(defaultIsBluetooth: false, builtIn: 42))
    }

    func testWithoutABuiltInMicrophoneBluetoothIsKept() {
        XCTAssertNil(PreferredInput.choose(defaultIsBluetooth: true, builtIn: nil))
    }

    func testBluetoothTransports() {
        XCTAssertTrue(PreferredInput.isBluetooth(kAudioDeviceTransportTypeBluetooth))
        XCTAssertTrue(PreferredInput.isBluetooth(kAudioDeviceTransportTypeBluetoothLE))
        XCTAssertFalse(PreferredInput.isBluetooth(kAudioDeviceTransportTypeUSB))
        XCTAssertFalse(PreferredInput.isBluetooth(kAudioDeviceTransportTypeBuiltIn))
    }
}
