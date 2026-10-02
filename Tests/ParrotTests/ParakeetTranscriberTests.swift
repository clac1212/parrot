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

    func testUnknownTokensAreDropped() {
        XCTAssertEqual(
            ParakeetTranscriber.clean("Et aussi j'aime bien <unk> je te disais dans mon message là <unk> mais l'interface."),
            "Et aussi j'aime bien je te disais dans mon message là mais l'interface."
        )
        XCTAssertEqual(ParakeetTranscriber.clean("blablabla <unk>, en fonction"), "blablabla, en fonction")
        XCTAssertEqual(ParakeetTranscriber.clean(" <unk> "), "")
        // French spacing before ? and ! stays as Parakeet wrote it.
        XCTAssertEqual(ParakeetTranscriber.clean("Bonjour, ça va ? Super !"), "Bonjour, ça va ? Super !")
        XCTAssertEqual(ParakeetTranscriber.clean("tu viens <unk> ?"), "tu viens ?")
    }
}
