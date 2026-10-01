import XCTest
@testable import ParrotCore

final class ParakeetTranscriberTests: XCTestCase {
    private let ultra = ModelRegistry.find("parakeet-ultra")!

    func testUltraIsAParakeetModelThatSpeaksFrench() {
        XCTAssertEqual(ultra.engine, .parakeet)
        XCTAssertTrue(ultra.supportedLanguages.contains("fr"))
        XCTAssertTrue(ultra.isMultilingual)
    }

    func testFixedLanguageIsPassed() {
        let context = TranscriptionContext(language: "fr")
        XCTAssertEqual(ParakeetTranscriber.language(for: context, model: ultra), "fr")
    }

    func testOneSpokenLanguageIsPassed() {
        let context = TranscriptionContext(language: nil, spokenLanguages: ["fr"])
        XCTAssertEqual(ParakeetTranscriber.language(for: context, model: ultra), "fr")
    }

    func testSeveralSpokenLanguagesLetParakeetChoose() {
        let context = TranscriptionContext(language: nil, spokenLanguages: ["fr", "en"])
        XCTAssertNil(ParakeetTranscriber.language(for: context, model: ultra))
    }
}
