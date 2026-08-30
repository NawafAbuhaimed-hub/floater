import XCTest
import SwiftData
@testable import FloaterCore

@MainActor
final class StoreTests: XCTestCase {
    private func makeStore() throws -> Store {
        try Store(inMemory: true)
    }

    func testAddCreatesAnOpenTaskInOrder() throws {
        let store = try makeStore()
        store.add(title: "First")
        store.add(title: "Second")
        XCTAssertEqual(store.openTasks.map(\.title), ["First", "Second"])
        XCTAssertEqual(store.openTasks.map(\.order), [0, 1])
    }

    func testAddIgnoresBlankTitlesAndTrimsWhitespace() throws {
        let store = try makeStore()
        XCTAssertNil(store.add(title: "   "))
        XCTAssertNil(store.add(title: "\n"))
        store.add(title: "  padded  ")
        XCTAssertEqual(store.openTasks.map(\.title), ["padded"])
    }

    func testCompleteMovesTheTaskOutOfTheOpenListAndBanksTime() throws {
        let store = try makeStore()
        let task = store.add(title: "Ship it")!
        store.complete(task, addingSeconds: 900)

        XCTAssertTrue(store.openTasks.isEmpty)
        XCTAssertEqual(store.tasks.count, 1)
        XCTAssertNotNil(store.tasks[0].completedAt)
        XCTAssertEqual(store.tasks[0].secondsSpent, 900, accuracy: 0.001)
        XCTAssertEqual(store.completedOn(Date()).map(\.title), ["Ship it"])
    }

    func testReopenPutsTheTaskBackWithoutLosingTime() throws {
        let store = try makeStore()
        let task = store.add(title: "Oops")!
        store.complete(task, addingSeconds: 300)
        store.reopen(task)
        XCTAssertEqual(store.openTasks.map(\.title), ["Oops"])
        XCTAssertEqual(store.tasks[0].secondsSpent, 300, accuracy: 0.001)
    }

    func testFocusTimeAccumulatesAcrossSessions() throws {
        let store = try makeStore()
        let task = store.add(title: "Long haul")!
        store.addFocusTime(900, toTaskWith: task.id)
        store.addFocusTime(1800, toTaskWith: task.id)
        store.addFocusTime(-50, toTaskWith: task.id) // ignored
        XCTAssertEqual(store.task(id: task.id)?.secondsSpent ?? 0, 2700, accuracy: 0.001)
    }

    func testDeleteRemovesTheTask() throws {
        let store = try makeStore()
        let task = store.add(title: "Nope")!
        store.delete(task)
        XCTAssertTrue(store.tasks.isEmpty)
    }

    func testClearCompletedLeavesOpenTasksAlone() throws {
        let store = try makeStore()
        let done = store.add(title: "Done")!
        store.add(title: "Not done")
        store.complete(done)
        store.clearCompleted()
        XCTAssertEqual(store.tasks.map(\.title), ["Not done"])
    }

    func testRememberPlanStoresTheLastChosenLength() throws {
        let store = try makeStore()
        let task = store.add(title: "Deep work")!
        store.rememberPlan(minutes: 45, forTaskWith: task.id)
        XCTAssertEqual(store.task(id: task.id)?.plannedMinutes, 45)
    }

    func testSessionRecordsPersist() throws {
        let store = try makeStore()
        let task = store.add(title: "Tracked")!
        store.record(
            FocusSessionRecord(
                taskID: task.id,
                taskTitle: task.title,
                startedAt: Date(),
                endedAt: Date(),
                plannedMinutes: 15,
                secondsFocused: 900,
                completedTask: true
            )
        )
        let records = try store.context.fetch(FetchDescriptor<FocusSessionRecord>())
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].plannedMinutes, 15)
    }
}
