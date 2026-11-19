import AppKit
import SwiftUI
import XCTest
@testable import ParrotCore

final class CorrectionOfferTests: XCTestCase {
    /// The first correction offered, as « wrong → right ».
    private func offer(_ pasted: String, _ edited: String, dictionary: String = "", refusals: Refusals = Refusals()) -> String? {
        offers(pasted, edited, dictionary: dictionary, refusals: refusals).first
    }

    private func offers(_ pasted: String, _ edited: String, dictionary: String = "", refusals: Refusals = Refusals()) -> [String] {
        let dictionary = try! UserDictionary.parse(Data(dictionary.utf8))
        return CorrectionOffer.offers(pasted: pasted, edited: edited, dictionary: dictionary, refusals: refusals)
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

    func testEveryCorrectionOfTheEditIsOffered() {
        XCTAssertEqual(offers("je teste pip et le vert", "je teste Peep et le verre"), ["pip → Peep", "vert → verre"])
    }

    func testAPairClosedOnceIsNotOfferedAgain() {
        var refusals = Refusals()
        let key = NightlyReview.key(wrong: "vert", right: "verre")
        XCTAssertFalse(refusals.dropped(key))
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

    /// The views' sizes: the live offer and a row hug their content.
    @MainActor
    func testTheViewsHugTheirContent() {
        let pending = PendingCorrections(record: { _, _ in })
        let offers = NotchOffers(pending: pending)
        let short = pending.add([.init(wrong: "pip", right: "Peep")])[0]
        let long = pending.add([.init(wrong: "Ambroise-Parais Anneuillie", right: "Ambroise-Paré")])[0]
        let a = NSHostingView(rootView: LiveOfferView(item: short, offers: offers)).fittingSize
        let b = NSHostingView(rootView: LiveOfferView(item: long, offers: offers)).fittingSize
        XCTAssertGreaterThanOrEqual(a.width, 300)
        XCTAssertLessThan(a.height, 70)
        XCTAssertGreaterThan(b.width, a.width)
        XCTAssertEqual(a.height, b.height, accuracy: 1)
        let row = NSHostingView(rootView: PendingCorrectionRow(item: short) { _ in }).fittingSize
        XCTAssertLessThan(row.height, 40)
    }

    /// Renders the live offer, the list and the panel rows to
    /// $OFFER_SNAPSHOT (a PNG path; -list, -panel beside it) when set.
    @MainActor
    func testSnapshot() throws {
        guard let path = ProcessInfo.processInfo.environment["OFFER_SNAPSHOT"] else { throw XCTSkip("no OFFER_SNAPSHOT") }
        let pending = PendingCorrections(record: { _, _ in })
        let offers = NotchOffers(pending: pending)
        pending.add([.init(wrong: "vert", right: "verre"), .init(wrong: "cloud", right: "Claude")])
        let item = pending.add([.init(wrong: "pip", right: "Peep")])[0]
        offers.offer([item])
        try render(NotchExpandedView(clock: NotchClock(), offers: offers).padding(14).background(.black), to: path)
        offers.yield()
        offers.pointerOnNotch()
        try render(NotchExpandedView(clock: NotchClock(), offers: offers).padding(14).background(.black), to: path.replacingOccurrences(of: ".png", with: "-list.png"))
        try render(PanelCard { PendingCorrectionsRows(pending: pending) }.frame(width: 344).padding(8)
            .environment(\.colorScheme, .dark).background(Color(nsColor: .windowBackgroundColor)),
                   to: path.replacingOccurrences(of: ".png", with: "-panel.png"))
    }

    @MainActor
    private func render<V: View>(_ root: V, to path: String) throws {
        let view = NSHostingView(rootView: root)
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

@MainActor
final class PendingCorrectionsTests: XCTestCase {
    private var answers: [(String, Bool)] = []
    private var clock = Date(timeIntervalSince1970: 1_000_000)

    private func make() -> PendingCorrections {
        PendingCorrections(now: { [unowned self] in self.clock }, record: { [unowned self] in self.answers.append(($0.key, $1)) })
    }

    func testNewestFirstAndNoDuplicate() {
        let pending = make()
        pending.add([.init(wrong: "pip", right: "Peep"), .init(wrong: "vert", right: "verre")])
        XCTAssertEqual(pending.items.map(\.right), ["Peep", "verre"])
        let first = pending.items[1]
        let added = pending.add([.init(wrong: "vert", right: "verre")])
        XCTAssertTrue(added.isEmpty)
        XCTAssertEqual(pending.items.map(\.right), ["verre", "Peep"])
        XCTAssertEqual(pending.items[0].id, first.id, "the same item, moved up")
    }

    func testAnAnswerIsRecordedAndRemoved() {
        let pending = make()
        let item = pending.add([.init(wrong: "pip", right: "Peep")])[0]
        pending.answer(item, accepted: true)
        XCTAssertTrue(pending.items.isEmpty)
        XCTAssertEqual(answers.map(\.0), [item.key])
        XCTAssertEqual(answers.map(\.1), [true])
        pending.answer(item, accepted: false)
        XCTAssertEqual(answers.count, 1, "answered once")
    }

    func testUnansweredGoAwayAfterADay() {
        let pending = make()
        pending.add([.init(wrong: "pip", right: "Peep")])
        clock += PendingCorrections.lifetime + 1
        pending.prune()
        XCTAssertTrue(pending.items.isEmpty)
        XCTAssertTrue(answers.isEmpty, "expiry is no answer")
    }
}

@MainActor
final class NotchOffersTests: XCTestCase {
    func testLiveThenTheNextOfTheSameEdit() {
        let pending = PendingCorrections(record: { _, _ in })
        let offers = NotchOffers(pending: pending)
        var shown = 0, hidden = 0
        offers.present = { shown += 1 }
        offers.dismiss = { hidden += 1 }
        let items = pending.add([.init(wrong: "pip", right: "Peep"), .init(wrong: "vert", right: "verre")])
        offers.offer(items)
        XCTAssertEqual(offers.mode, .live(items[0]))
        XCTAssertEqual(offers.morePending, 1)
        offers.answer(items[0], accepted: true)
        XCTAssertEqual(offers.mode, .live(items[1]))
        offers.answer(items[1], accepted: false)
        XCTAssertEqual(offers.mode, .none)
        XCTAssertEqual(shown, 2)
        XCTAssertEqual(hidden, 1)
    }

    func testADictationTakesTheNotchBackAndAllStaysPending() {
        let pending = PendingCorrections(record: { _, _ in })
        let offers = NotchOffers(pending: pending)
        let items = pending.add([.init(wrong: "pip", right: "Peep")])
        offers.offer(items)
        offers.yield()
        XCTAssertEqual(offers.mode, .none)
        XCTAssertEqual(pending.items.count, 1)
        offers.isBusy = { true }
        offers.offer(items)
        offers.pointerOnNotch()
        XCTAssertEqual(offers.mode, .none, "nothing comes out while dictating")
    }

    func testTheListOnlyWhenSomethingWaits() {
        let pending = PendingCorrections(record: { _, _ in })
        let offers = NotchOffers(pending: pending)
        offers.pointerOnNotch()
        XCTAssertEqual(offers.mode, .none)
        let items = pending.add([.init(wrong: "pip", right: "Peep")])
        offers.pointerOnNotch()
        XCTAssertEqual(offers.mode, .list)
        offers.answer(items[0], accepted: true)
        XCTAssertEqual(offers.mode, .none, "the list folds once empty")
    }

    func testTheBarHoldsUnderThePointer() {
        let pending = PendingCorrections(record: { _, _ in })
        let offers = NotchOffers(pending: pending)
        offers.offer(pending.add([.init(wrong: "pip", right: "Peep")]))
        let now = Date()
        XCTAssertEqual(offers.fraction(at: now), 1, accuracy: 0.05)
        XCTAssertEqual(offers.fraction(at: now.addingTimeInterval(NotchOffers.duration / 2)), 0.5, accuracy: 0.05)
        offers.hover(true)
        XCTAssertNil(offers.endsAt)
        XCTAssertEqual(offers.fraction(at: now.addingTimeInterval(100)), 1, accuracy: 0.05, "held")
        offers.hover(false)
        XCTAssertNotNil(offers.endsAt)
    }
}
