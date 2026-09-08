import XCTest
@testable import SwingCoach

@MainActor
final class AutoCaptureReviewSessionTests: XCTestCase {
    func testRestartIgnoresPreviousSessionRequestsAndCompletions() {
        let camera = CameraSession()
        let oldSession = UUID()
        camera.beginAutoReviewSession(id: oldSession)
        camera.beginAutoReviewRequest(sessionID: oldSession)
        let newSession = UUID()
        camera.beginAutoReviewSession(id: newSession)
        camera.beginAutoReviewRequest(sessionID: newSession)
        let swing = SavedSwing(id: UUID(), photoAssetID: "", vantage: .dtl, duration: 4,
                               createdAt: Date(), notes: nil, analyzed: false)

        // Old buffer/export callbacks may arrive after the next session starts.
        camera.beginAutoReviewRequest(sessionID: oldSession)
        camera.finishAutoReviewRequest(sessionID: oldSession, savedSwing: swing, errorMessage: nil)
        camera.finishAutoReviewRequest(sessionID: oldSession, savedSwing: nil, errorMessage: "Old export failed")
        XCTAssertEqual(camera.autoCaptureStatus.pendingSwingCount, 1)
        XCTAssertEqual(camera.autoCaptureStatus.savedSwingCount, 0)
        XCTAssertNil(camera.autoCaptureStatus.lastErrorMessage)
        XCTAssertTrue(camera.autoSessionSwings.isEmpty)

        camera.finishAutoReviewRequest(sessionID: newSession, savedSwing: swing, errorMessage: nil)
        XCTAssertEqual(camera.autoCaptureStatus.pendingSwingCount, 0)
        XCTAssertEqual(camera.autoCaptureStatus.savedSwingCount, 1)
        XCTAssertEqual(camera.autoSessionSwings.map(\.id), [swing.id])
    }
}
