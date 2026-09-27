import XCTest
@testable import SwingCoach

@MainActor
final class CoachingContractTests: XCTestCase {
    func testLegacyAnalysisStillDecodes() throws {
        let json = #"{"analysis_id":"old","summary":"Old notes","metrics":[{"key":"tempo","name":"Tempo","value":"3:1"}],"drills":[]}"#
        let response = try JSONDecoder().decode(SwingCoachAPI.AnalysisResponse.self, from: Data(json.utf8))
        XCTAssertNil(response.coaching)
        XCTAssertNil(response.metrics[0].confidence)
    }

    func testGroundedCoachingSurvivesPersistence() throws {
        let json = #"{"analysis_id":"new","summary":"One focus","metrics":[],"drills":[],"coaching":{"version":1,"status":"need_evidence","focus":"Check the view","rationale":"The face is hidden","cue":null,"reassess":"Record another view","questions":["What was the miss?"],"evidence":[{"id":"V01","description":"Hands visible","kind":"visual_interpretation","confidence":0.7,"timestamps":[1.25]}],"sources":[{"case_id":"case","title":"Lesson","publisher":"Coach","url":"https://example.com/lesson","start_seconds":123,"end_seconds":146,"review_status":"source_checked_not_expert_validated"}],"limitations":["No face measurement"]}}"#
        let response = try JSONDecoder().decode(SwingCoachAPI.AnalysisResponse.self, from: Data(json.utf8))
        let saved = SavedAnalysis(id: UUID(), swingID: UUID(), analysisID: response.analysisID, createdAt: Date(),
                                  summary: response.summary, metrics: [], annotatedVideo: nil, drills: [], coaching: response.coaching)
        let roundTrip = try JSONDecoder().decode(SavedAnalysis.self, from: JSONEncoder().encode(saved))
        XCTAssertEqual(roundTrip, saved)
        XCTAssertEqual(roundTrip.coaching?.sources.first?.startSeconds, 123)
        XCTAssertEqual(roundTrip.coaching?.evidence.first?.timestamps, [1.25])
    }
}
