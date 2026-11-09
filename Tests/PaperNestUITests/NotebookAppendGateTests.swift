import Testing
@testable import PaperNestUI

@Suite struct NotebookAppendGateTests {
    @Test func requiresGestureTravelAndEndAndOnlyFiresOnce() {
        var gate = NotebookAppendGate()
        let result1 = gate.update(downward: 100, offset: 112, maximum: 112, enabled: true)
        #expect(!result1)
        gate.begin()
        let result2 = gate.update(downward: 30, offset: 30, maximum: 112, enabled: true)
        #expect(!result2)
        let result3 = gate.update(downward: 50, offset: 80, maximum: 112, enabled: true)
        #expect(!result3)
        let result4 = gate.update(downward: 32, offset: 112, maximum: 112, enabled: true)
        #expect(result4)
        let result5 = gate.update(downward: 200, offset: 112, maximum: 112, enabled: true)
        #expect(!result5)
        gate.begin()
        let result6 = gate.update(downward: 60, offset: 112, maximum: 112, enabled: true)
        #expect(result6)
    }
    @Test func disabledOrLayoutOnlyChangesCannotAppend() {
        var gate = NotebookAppendGate()
        gate.begin()
        let result7 = gate.update(downward: 0, offset: 112, maximum: 112, enabled: true)
        #expect(!result7)
        let result8 = gate.update(downward: 100, offset: 112, maximum: 112, enabled: false)
        #expect(!result8)
        let result9 = gate.update(downward: 100, offset: 112, maximum: 112, enabled: true)
        #expect(!result9)
        gate.begin()
        let result10 = gate.update(downward: 100, offset: 0, maximum: 0, enabled: true)
        #expect(!result10)
    }
}
