import AppKit
import SwiftUI
import XCTest
@testable import ParrotCore

final class CorrectionOfferTests: XCTestCase {
    private func offer(_ pasted: String, _ edited: String, dictionary: String = "", refusals: Refusals = Refusals()) -> String? {
        let dictionary = try! UserDictionary.parse(Data(dictionary.utf8))
        return CorrectionOffer.offer(pasted: pasted, edited: edited, dictionary: dictionary, refusals: refusals)
            .map { "\($0.wrong) → \($0.right)" }
    }

    func testOffersAWordFixedByHand() {
        XCTAssertEqual(offer("je teste pip demain", "je teste Peep demain"), "pip → Peep")
        XCTAssertEqual(offer("on lance ce paro ce soir", "on lance Sparrow ce soir"), "ce paro → Sparrow")
        // A real word too: only the user knows whether they ever say it.
        XCTAssertEqual(offer("un vert d'eau", "un verre d'eau"), "vert → verre")
    }

    func testACapitalThatOnlyStartsTheSentenceIsDropped() {
        XCTAssertEqual(offer("Vert d'eau.", "Verre d'eau."), "Vert → verre")
        // Capitals inside a word are the user's spelling.
        XCTAssertEqual(offer("Post hog marche.", "PostHog marche."), "Post hog → PostHog")
    }

    func testTheDictionarySpellingWins() {
        XCTAssertEqual(offer("demande à cloud", "demande à claude", dictionary: "Claude  Cloude"), "cloud → Claude")
    }

    func testNothingAlreadyInTheDictionary() {
        XCTAssertNil(offer("demande à cloude", "demande à Claude", dictionary: "Claude  Cloude"))
    }

    func testNeverReplacesOneOfTheUsersWords() {
        XCTAssertNil(offer("demande à Claude", "demande à Cloud", dictionary: "Claude"))
    }

    func testNotARewriteNorAWordBeingRetyped() {
        XCTAssertNil(offer("un deux trois quatre cinq six", "one deux two quatre three six"))
        XCTAssertNil(offer("mais oui", "m oui"))
        XCTAssertNil(offer("c'est bon", "c'est bo"))
        XCTAssertNil(offer("en effet", "on effet"), "two-letter words are grammar")
        XCTAssertEqual(offer("un bébé", "un BB"), "bébé → BB")
        XCTAssertNil(offer("même texte", "même texte"))
    }

    func testAPairLetGoTwiceIsNotOfferedAgain() {
        var refusals = Refusals()
        let key = NightlyReview.key(wrong: "vert", right: "verre")
        refusals.note(key)
        XCTAssertEqual(offer("un vert", "un verre", refusals: refusals), "vert → verre")
        refusals.note(key)
        XCTAssertTrue(refusals.dropped(key))
        XCTAssertNil(offer("un vert", "un verre", refusals: refusals))
    }

    func testRefusalsRoundTrip() throws {
        var refusals = Refusals()
        refusals.note("a→b")
        let back = try JSONDecoder().decode(Refusals.self, from: JSONEncoder().encode(refusals))
        XCTAssertEqual(back, refusals)
    }

    @MainActor
    func testThePanelHugsItsContent() {
        let short = NSHostingView(rootView: CorrectionOfferView(wrong: "pip", right: "Peep")).fittingSize
        let long = NSHostingView(rootView: CorrectionOfferView(wrong: "Ambroise-Parais Anneuillie", right: "Ambroise-Paré")).fittingSize
        XCTAssertGreaterThan(short.width, 200)
        XCTAssertLessThan(short.height, 70)
        XCTAssertGreaterThan(long.width, short.width)
        XCTAssertEqual(long.height, short.height, accuracy: 1)
    }

    /// Renders the panel to $OFFER_SNAPSHOT (a PNG path) when set.
    @MainActor
    func testSnapshot() throws {
        guard let path = ProcessInfo.processInfo.environment["OFFER_SNAPSHOT"] else { throw XCTSkip("no OFFER_SNAPSHOT") }
        let view = NSHostingView(rootView: CorrectionOfferView(wrong: "pip", right: "Peep")
            .environment(\.colorScheme, .dark).background(Color(nsColor: .windowBackgroundColor)))
        view.appearance = NSAppearance(named: .darkAqua)
        view.frame = NSRect(origin: .zero, size: view.fittingSize)
        // SwiftUI draws this one only inside a window.
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        view.display()
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: path))
    }
}
