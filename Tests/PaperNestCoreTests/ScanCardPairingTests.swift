import Testing
@testable import PaperNestCore

@Suite struct ScanCardPairingTests {
    @Test func theFirstCaptureIsAFrontAndItsBackIsOffered() {
        var pairing = ScanCardPairing<String>()
        #expect(pairing.nextSide == .front)
        let kept = pairing.keep("a")
        #expect(kept.side == .front && kept.front == nil)
        #expect(pairing.offer == "a", "the question is about this front")
        #expect(pairing.nextSide == .front, "nothing is a back until the person says so")
        #expect(pairing.side(of: "a") == .front)
    }

    @Test func choosingScanBackMakesTheNextCaptureThatFrontsBack() {
        var pairing = ScanCardPairing<String>()
        _ = pairing.keep("a")
        pairing.scanBack()
        #expect(pairing.offer == nil)
        #expect(pairing.nextSide == .back)
        let kept = pairing.keep("b")
        #expect(kept.side == .back && kept.front == "a")
        #expect(pairing.side(of: "b") == .back)
        #expect(pairing.partner(of: "a") == "b" && pairing.partner(of: "b") == "a")
        #expect(pairing.nextSide == .front, "the card is done; the next capture starts another")
        #expect(pairing.offer == nil, "a back is not asked about")
    }

    @Test func continuingLeavesAFrontOnItsOwn() {
        var pairing = ScanCardPairing<String>()
        _ = pairing.keep("a")
        pairing.continueWithFrontOnly()
        #expect(pairing.offer == nil && pairing.nextSide == .front)
        let next = pairing.keep("b")
        #expect(next.side == .front && next.front == nil)
        #expect(pairing.partner(of: "a") == nil)
        #expect(pairing.offer == "b")
    }

    /// The question can be left unanswered by simply taking another picture.
    /// That is another card, not the back of the first.
    @Test func capturingAgainWithoutAnsweringStartsAnotherCard() {
        var pairing = ScanCardPairing<String>()
        _ = pairing.keep("a")
        let next = pairing.keep("b")
        #expect(next.side == .front && next.front == nil)
        #expect(pairing.partner(of: "a") == nil && pairing.offer == "b")
    }

    @Test func aBackThatIsNotKeptIsStillOwed() {
        var pairing = ScanCardPairing<String>()
        _ = pairing.keep("a")
        pairing.scanBack()
        // The capture was looked at and deleted: nothing was kept.
        #expect(pairing.nextSide == .back)
        #expect(pairing.keep("b").front == "a")
    }

    @Test func deletingAFrontStopsWaitingForItsBack() {
        var pairing = ScanCardPairing<String>()
        _ = pairing.keep("a")
        pairing.scanBack()
        pairing.forget(["a"])
        #expect(pairing.nextSide == .front)
        #expect(pairing.side(of: "a") == nil)
        #expect(pairing.keep("b").side == .front)
    }

    @Test func deletingOneSideLeavesTheOtherUnpaired() {
        var pairing = ScanCardPairing<String>()
        _ = pairing.keep("a"); pairing.scanBack(); _ = pairing.keep("b")
        pairing.forget(["b"])
        #expect(pairing.side(of: "a") == .front && pairing.partner(of: "a") == nil)
        #expect(pairing.side(of: "b") == nil)
    }

    @Test func deletingTheFrontBeingAskedAboutWithdrawsTheQuestion() {
        var pairing = ScanCardPairing<String>()
        _ = pairing.keep("a")
        pairing.forget(["a"])
        #expect(pairing.offer == nil)
    }

    /// Leaving Card mode: the pages keep their labels, but no back is owed
    /// and no question is left on screen.
    @Test func leavingCardModeEndsWhatWasPending() {
        var pairing = ScanCardPairing<String>()
        _ = pairing.keep("a"); pairing.scanBack(); _ = pairing.keep("b")
        _ = pairing.keep("c")
        pairing.scanBack()
        pairing.cancelPending()
        #expect(pairing.nextSide == .front && pairing.offer == nil)
        #expect(pairing.side(of: "a") == .front && pairing.side(of: "b") == .back && pairing.side(of: "c") == .front)
    }
}
