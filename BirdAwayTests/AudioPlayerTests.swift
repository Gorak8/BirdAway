import XCTest
@testable import BirdAway

final class AudioPlayerTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Ensure a clean state before each test
        AudioPlayer.shared.resetToSystemDefault()
    }

    func testResetToSystemDefault() {
        // Given
        let player = AudioPlayer.shared

        // Mock the properties to simulate a running/custom state
        player.isPlaying = true
        player.selectedDeviceUID = "mock-device-uid"

        // When
        player.resetToSystemDefault()

        // Then
        XCTAssertFalse(player.isPlaying, "isPlaying should be reset to false")
        XCTAssertNil(player.selectedDeviceUID, "selectedDeviceUID should be reset to nil")
    }
}
