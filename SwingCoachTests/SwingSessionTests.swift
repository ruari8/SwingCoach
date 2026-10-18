import XCTest
@testable import SwingCoach

final class SwingSessionTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }()

    private func swing(_ day: Int, _ hour: Int, _ minute: Int) -> SavedSwing {
        let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
        return SavedSwing(id: UUID(), photoAssetID: "", vantage: .dtl, duration: 3, createdAt: date, notes: nil, analyzed: false)
    }

    func testGroupsSwingsSplitByGapsAndDaysNewestFirst() {
        let warmUp = [swing(12, 8, 0), swing(12, 8, 1), swing(12, 8, 25)]
        let round = [swing(12, 9, 10), swing(12, 9, 30)]
        let lateNight = swing(11, 23, 50)
        let afterMidnight = swing(12, 0, 5)

        let sessions = SwingSession.group((warmUp + round + [lateNight, afterMidnight]).shuffled(), calendar: calendar)

        XCTAssertEqual(sessions.map { $0.swings.map(\.id) }, [
            round.reversed().map(\.id),
            warmUp.reversed().map(\.id),
            [afterMidnight.id],
            [lateNight.id],
        ])
        XCTAssertEqual(sessions[1].start, warmUp[0].createdAt)
        XCTAssertEqual(sessions[1].end, warmUp[2].createdAt)
    }

    func testDragFromUnselectedSwingAddsRangeAndRestoresPassedSwings() throws {
        let ids = (0..<6).map { _ in UUID() }
        let selection = try XCTUnwrap(SwingRangeSelection(orderedIDs: ids, anchor: ids[2], initialSelection: [ids[0]]))

        XCTAssertEqual(selection.selection(extendingTo: ids[4]), [ids[0], ids[2], ids[3], ids[4]])
        XCTAssertEqual(selection.selection(extendingTo: ids[3]), [ids[0], ids[2], ids[3]])
        XCTAssertEqual(selection.selection(extendingTo: ids[1]), [ids[0], ids[1], ids[2]])
    }

    func testDragFromSelectedSwingRemovesRange() throws {
        let ids = (0..<4).map { _ in UUID() }
        let selection = try XCTUnwrap(SwingRangeSelection(orderedIDs: ids, anchor: ids[1], initialSelection: Set(ids)))

        XCTAssertEqual(selection.selection(extendingTo: ids[2]), [ids[0], ids[3]])
    }
}
