import XCTest
@testable import FloaterCore

@MainActor
final class CopyPasteTests: XCTestCase {
    private var store: Store!
    private var model: AppModel!

    override func setUpWithError() throws {
        try super.setUpWithError()
        store = try Store(inMemory: true)
        model = AppModel(store: store, prefs: Preferences(store: InMemoryStore()),
                         clock: TestClock(), autoTick: false)
    }

    // MARK: - Pasting a list in

    func testPastingSeveralLinesCreatesATaskPerLine() {
        model.draft = "call omar\ndraft the Q3 deck\nbook the flights"
        model.addDraftTask()

        XCTAssertEqual(model.tasks.map(\.title),
                       ["call omar", "draft the Q3 deck", "book the flights"])
        XCTAssertEqual(model.draft, "")
    }

    func testBlankLinesAndStrayWhitespaceAreDropped() {
        model.draft = "  first  \n\n\n   \nsecond\n"
        model.addDraftTask()
        XCTAssertEqual(model.tasks.map(\.title), ["first", "second"])
    }

    func testPastingOnlyWhitespaceCreatesNothingAndKeepsTheDraft() {
        model.draft = "\n   \n\n"
        model.addDraftTask()
        XCTAssertTrue(model.tasks.isEmpty)
        XCTAssertEqual(model.draft, "\n   \n\n", "nothing was consumed, so nothing is cleared")
    }

    func testASingleLineStillBehavesAsBefore() {
        model.draft = "just the one"
        model.addDraftTask()
        XCTAssertEqual(model.tasks.map(\.title), ["just the one"])
    }

    // MARK: - Copying a task out

    private func addTask(_ title: String, note: String = "") -> TaskItem {
        model.draft = title
        model.addDraftTask()
        let task = model.tasks.first { $0.title == title }!
        if !note.isEmpty { store.updateNote(note, forTaskWith: task.id) }
        return model.tasks.first { $0.id == task.id }!
    }

    func testCopyingATaskWithNoNoteGivesJustTheTitle() {
        let task = addTask("Ship the deck")
        XCTAssertEqual(model.clipboardText(for: task), "Ship the deck")
    }

    func testCopyingATaskWithANoteGivesBothSeparated() {
        let task = addTask("Ship the deck", note: "chase Omar for the numbers")
        XCTAssertEqual(model.clipboardText(for: task),
                       "Ship the deck\n\nchase Omar for the numbers")
    }

    func testAWhitespaceOnlyNoteIsTreatedAsNoNote() {
        let task = addTask("Clean", note: "   \n  ")
        XCTAssertEqual(model.clipboardText(for: task), "Clean")
    }

    func testNothingSelectedMeansNothingToCopy() {
        _ = addTask("Unselected")
        XCTAssertNil(model.selectedTaskID)
        XCTAssertNil(model.clipboardTextForSelection())
    }

    func testSelectingATaskMakesItTheCopyTarget() {
        _ = addTask("First")
        let second = addTask("Second", note: "the details")

        model.select(second)

        XCTAssertEqual(model.selectedTaskID, second.id)
        XCTAssertEqual(model.clipboardTextForSelection(), "Second\n\nthe details")
    }

    func testOpeningATasksNoteAlsoSelectsIt() {
        let task = addTask("Opened")
        model.toggleNote(for: task)
        XCTAssertEqual(model.selectedTaskID, task.id, "Cmd-C needs an obvious target")
        XCTAssertEqual(model.expandedTaskID, task.id)
    }

    func testClosingTheNoteKeepsTheTaskSelected() {
        let task = addTask("Still selected")
        model.toggleNote(for: task)
        model.toggleNote(for: task)
        XCTAssertNil(model.expandedTaskID)
        XCTAssertEqual(model.selectedTaskID, task.id)
    }

    func testDeletingTheSelectedTaskClearsTheSelection() {
        let task = addTask("Doomed")
        model.toggleNote(for: task)
        model.delete(model.tasks.first { $0.id == task.id }!)

        XCTAssertNil(model.selectedTaskID, "a dangling id would copy a task that no longer exists")
        XCTAssertNil(model.expandedTaskID)
        XCTAssertNil(model.clipboardTextForSelection())
    }

    func testSelectingNothingClearsIt() {
        let task = addTask("On then off")
        model.select(task)
        model.select(nil)
        XCTAssertNil(model.selectedTaskID)
    }
}
