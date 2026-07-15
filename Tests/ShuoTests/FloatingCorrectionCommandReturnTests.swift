import XCTest
@testable import Shuo

final class FloatingCorrectionCommandReturnTests: XCTestCase {
    func testPolicyOnlyConfirmsCommandReturnWithNonemptyDraft() {
        XCTAssertTrue(
            FloatingCorrectionKeyboardConfirmationPolicy.shouldConfirm(
                hasCommandModifier: true,
                hasConfirmableDraft: true
            )
        )
        XCTAssertFalse(
            FloatingCorrectionKeyboardConfirmationPolicy.shouldConfirm(
                hasCommandModifier: false,
                hasConfirmableDraft: true
            )
        )
        XCTAssertFalse(
            FloatingCorrectionKeyboardConfirmationPolicy.shouldConfirm(
                hasCommandModifier: true,
                hasConfirmableDraft: false
            )
        )
    }
}
