import Testing
@testable import PaperNestUI

@Suite struct NotebookTouchIntentTests {
    @Test func twoContactsBeforeMovementReserveNavigationAndNeverDrawing() {
        var intent = NotebookTouchIntent()
        intent.observe(fingers: 1, pencil: false, moved: false)
        #expect(intent.decision == .undecided)
        intent.observe(fingers: 2, pencil: false, moved: false)
        #expect(intent.decision == .navigation)
        intent.observe(fingers: 1, pencil: false, moved: true)
        #expect(intent.decision == .navigation)
    }
    @Test func pencilAndSingleFingerMovementRemainDrawing() {
        var pencil = NotebookTouchIntent()
        pencil.observe(fingers: 1, pencil: true, moved: false)
        #expect(pencil.decision == .drawing)
        var finger = NotebookTouchIntent()
        finger.observe(fingers: 1, pencil: false, moved: true)
        #expect(finger.decision == .drawing)
    }
}
