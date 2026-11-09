import Foundation
import Testing
@testable import PaperNestUI

@Suite struct ScanCaptureEncodingTests {
    @Test func keepsEveryPageInCaptureOrder() {
        let expected = [Data([1]), Data([2]), Data([3])]
        let result = ScanCaptureEncoding.pages(count: expected.count) { expected[$0] }
        #expect(result == expected)
    }

    @Test(arguments: [0, 1, 2])
    func refusesTheWholeCaptureWhenAnyPageFails(failedIndex: Int) {
        var visited: [Int] = []
        let result = ScanCaptureEncoding.pages(count: 3) { index in
            visited.append(index)
            return index == failedIndex ? nil : Data([UInt8(index)])
        }
        #expect(result == nil, "Never report an incomplete capture as successful")
        #expect(visited == Array(0...failedIndex), "Stop encoding after the first failure")
    }

    @Test func refusesAnEmptyCaptureWithoutEncoding() {
        var called = false
        let result = ScanCaptureEncoding.pages(count: 0) { _ in
            called = true
            return Data([1])
        }
        #expect(result == nil)
        #expect(!called)
    }
}
