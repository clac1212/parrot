import XCTest
@testable import ParrotCore

final class StatusPopoverTests: XCTestCase {
    func testStatusInFrench() {
        XCTAssertEqual(StatusPanelModel.french(status: "idle · hold fn to dictate"), "Prêt · maintiens fn pour dicter")
        XCTAssertEqual(StatusPanelModel.french(status: "● recording"), "● Enregistrement…")
        XCTAssertEqual(StatusPanelModel.french(status: "loading model…"), "Chargement du modèle…")
        XCTAssertEqual(StatusPanelModel.french(status: "something new"), "something new")
    }

    func testModelLineInFrench() {
        XCTAssertEqual(StatusPanelModel.french(modelLine: "model: parakeet-ultra"), "Parakeet Ultra")
        XCTAssertEqual(
            StatusPanelModel.french(modelLine: "model: parakeet-ultra · loading whisper-small…"),
            "Parakeet Ultra · chargement de Whisper Small…"
        )
        XCTAssertEqual(
            StatusPanelModel.french(modelLine: "model: parakeet-ultra · downloading whisper-small… 42%"),
            "Parakeet Ultra · téléchargement de Whisper Small… 42%"
        )
    }
}
