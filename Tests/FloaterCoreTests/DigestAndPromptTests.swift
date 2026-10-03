import XCTest
@testable import FloaterCore

/// Hands back a fixed project context so prompts can be checked without a repo.
final class FakeProjectContext: ProjectContextReading, @unchecked Sendable {
    var result: ProjectContext = .empty
    private(set) var requestedPaths: [String] = []
    private(set) var requestedKeywords: [[String]] = []

    func context(forRepoAt path: String, projectName: String, matching keywords: [String]) async -> ProjectContext {
        requestedPaths.append(path)
        requestedKeywords.append(keywords)
        return result
    }
}

@MainActor
final class DigestTests: XCTestCase {
    private var clock: TestClock!
    private var store: Store!
    private var model: AppModel!
    private var calendar: Calendar!

    override func setUpWithError() throws {
        try super.setUpWithError()
        calendar = {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(identifier: "Europe/London")!
            return cal
        }()
        clock = TestClock(now: Date(timeIntervalSince1970: 1_773_153_120)) // 2026-03-10 14:32
        store = try Store(inMemory: true)
        model = AppModel(store: store, prefs: Preferences(store: InMemoryStore()),
                         clock: clock, calendar: calendar, autoTick: false)
        model.logCompletions = false
    }

    @discardableResult
    private func finish(_ title: String, daysAgo: Int, minutes: Int, category: String? = nil) -> TaskItem {
        model.draft = title
        model.addDraftTask()
        var task = model.tasks.first { $0.title == title }!
        if let category, let match = model.categories.first(where: { $0.name == category }) {
            model.setCategory(match, for: task)
            task = model.tasks.first { $0.id == task.id }!
        }
        if minutes > 0 {
            model.start(task, minutes: minutes)
            clock.advance(TimeInterval(minutes * 60))
            // Stopping is what banks the focused time against the task; leaving
            // the timer running means it is only banked when the next one starts.
            model.stopTimer()
        }
        let completedAt = calendar.date(byAdding: .day, value: -daysAgo, to: clock.now)!
        store.complete(model.tasks.first { $0.id == task.id }!, at: completedAt,
                       addingSeconds: minutes > 0 ? 0 : 0)
        model.refresh()
        return model.tasks.first { $0.id == task.id }!
    }

    func testTheDigestCountsOnlyWhatFellInTheWindow() {
        finish("Inside", daysAgo: 2, minutes: 0)
        finish("Also inside", daysAgo: 6, minutes: 0)
        finish("Too old", daysAgo: 30, minutes: 0)

        let digest = model.digest(days: 7)

        XCTAssertEqual(digest.completed.map(\.title).sorted(), ["Also inside", "Inside"])
        XCTAssertEqual(digest.days, 7)
    }

    func testFocusedTimeIsTotalledAndSplitByProject() {
        finish("CRM thing", daysAgo: 1, minutes: 45, category: "MNZIL CRM")
        finish("Another CRM thing", daysAgo: 1, minutes: 15, category: "MNZIL CRM")
        finish("Floater thing", daysAgo: 1, minutes: 30, category: "Floater")

        let digest = model.digest(days: 7)

        XCTAssertEqual(digest.totalFocused, 90 * 60, accuracy: 1)
        XCTAssertEqual(digest.byCategory.first?.name, "MNZIL CRM", "the biggest slice leads")
        XCTAssertEqual(digest.byCategory.first?.completed, 2)
        XCTAssertEqual(digest.byCategory.first?.secondsFocused ?? 0, 60 * 60, accuracy: 1)
    }

    func testUncategorisedWorkIsStillCounted() {
        finish("No project", daysAgo: 1, minutes: 20)
        let digest = model.digest(days: 7)
        XCTAssertEqual(digest.byCategory.map(\.name), [Digest.uncategorised])
    }

    func testOpenBlockedAndOverdueAreReported() {
        model.draft = "Open one"
        model.addDraftTask()
        model.draft = "Blocked one"
        model.addDraftTask()
        let blocked = model.tasks.first { $0.title == "Blocked one" }!
        model.setStatus(.blocked, for: blocked)
        model.draft = "Late one"
        model.addDraftTask()
        let late = model.tasks.first { $0.title == "Late one" }!
        model.setDueDate(clock.now.addingTimeInterval(-3 * 86400), for: late)

        let digest = model.digest(days: 7)

        XCTAssertTrue(digest.stillOpen.contains("Open one"))
        XCTAssertEqual(digest.blocked, ["Blocked one"])
        XCTAssertEqual(digest.overdue, ["Late one"])
        XCTAssertFalse(digest.stillOpen.contains("Blocked one"), "blocked is listed separately")
    }

    func testAnEmptyWindowSaysSoRatherThanFabricating() {
        let digest = model.digest(days: 7)
        XCTAssertTrue(digest.isEmpty)
        let sheet = digest.factSheet(calendar: calendar)
        XCTAssertTrue(sheet.contains("Tasks finished: 0"), sheet)
        XCTAssertTrue(sheet.contains("No finished work in this window."), sheet)
    }

    func testTheFactSheetCarriesEveryFigureTheWriteUpMayUse() {
        finish("Ship the deck", daysAgo: 1, minutes: 45, category: "MNZIL CRM")
        let sheet = model.digest(days: 7).factSheet(calendar: calendar)

        XCTAssertTrue(sheet.contains("Window: last 7 days"), sheet)
        XCTAssertTrue(sheet.contains("Tasks finished: 1"), sheet)
        XCTAssertTrue(sheet.contains("Ship the deck"), sheet)
        XCTAssertTrue(sheet.contains("MNZIL CRM"), sheet)
        XCTAssertTrue(sheet.contains("45m"), sheet)
    }

    func testZeroOrNegativeDaysStillProducesOneDay() {
        XCTAssertEqual(model.digest(days: 0).days, 1)
        XCTAssertEqual(model.digest(days: -5).days, 1)
    }
}

@MainActor
final class PromptGenerationTests: XCTestCase {
    private var store: Store!
    private var model: AppModel!
    private var client: FakeClaudeClient!
    private var context: FakeProjectContext!

    override func setUpWithError() throws {
        try super.setUpWithError()
        store = try Store(inMemory: true)
        client = FakeClaudeClient()
        context = FakeProjectContext()
        let fake = client!
        model = AppModel(store: store, prefs: Preferences(store: InMemoryStore()),
                         clock: TestClock(), keyStore: InMemoryAPIKeyStore(value: "sk-test"),
                         makeChatEngine: { _ in ChatEngine(client: fake) }, autoTick: false)
        model.projectContext = context
        model.logCompletions = false
    }

    private func task(_ title: String, note: String = "", category: String? = nil) -> TaskItem {
        model.draft = title
        model.addDraftTask()
        var item = model.tasks.first { $0.title == title }!
        if !note.isEmpty { store.updateNote(note, forTaskWith: item.id) }
        if let category, let match = model.categories.first(where: { $0.name == category }) {
            model.setCategory(match, for: item)
        }
        model.refresh()
        item = model.tasks.first { $0.id == item.id }!
        return item
    }

    func testKeywordsDropFillerAndKeepTheRealWords() {
        let item = task("Fix the lost reason tree in the CRM", note: "it should cascade")
        let words = PromptBuilder.keywords(for: item, categoryName: "MNZIL CRM")
        XCTAssertTrue(words.contains("lost"))
        XCTAssertTrue(words.contains("reason"))
        XCTAssertTrue(words.contains("cascade"))
        XCTAssertFalse(words.contains("the"))
        XCTAssertFalse(words.contains("fix"), "a verb every task shares is not a signal")
        XCTAssertEqual(words.count, Set(words).count, "no duplicates")
    }

    func testItAsksForContextFromTheCategorysRepository() async {
        let item = task("Fix the qualifier filter", category: "MNZIL CRM")
        await model.generateClaudeCodePrompt(for: item)

        XCTAssertEqual(context.requestedPaths.count, 1)
        XCTAssertTrue(context.requestedPaths[0].hasSuffix("/mnzilpostsales"), context.requestedPaths[0])
        XCTAssertTrue(context.requestedKeywords[0].contains("qualifier"))
    }

    func testATaskWithNoProjectSkipsTheDiskEntirely() async {
        let item = task("Something personal")
        await model.generateClaudeCodePrompt(for: item)
        XCTAssertTrue(context.requestedPaths.isEmpty, "no repo means nothing to read")
    }

    func testTheBriefCarriesTheProjectsConventionsAndNotes() {
        let item = task("Fix the filter", note: "only on Closing", category: "MNZIL CRM")
        let brief = PromptBuilder.brief(
            task: item, categoryName: "MNZIL CRM", dueDescription: "Fri 20 Mar",
            context: ProjectContext(
                projectName: "MNZIL CRM", repoPath: "/Users/x/mnzilpostsales", branch: "main",
                documents: [.init(name: "CLAUDE.md", body: "Use bun, never npm.")],
                recentCommits: ["2026-03-09 CRM: add qualifier filter"],
                notes: ["Lovable silently reverts pushes to main"]
            )
        )
        XCTAssertTrue(brief.contains("Fix the filter"))
        XCTAssertTrue(brief.contains("only on Closing"))
        XCTAssertTrue(brief.contains("Due: Fri 20 Mar"))
        XCTAssertTrue(brief.contains("/Users/x/mnzilpostsales"))
        XCTAssertTrue(brief.contains("Use bun, never npm."))
        XCTAssertTrue(brief.contains("Lovable silently reverts pushes"), "the gotchas are the point")
        XCTAssertTrue(brief.contains("CRM: add qualifier filter"))
    }

    func testAnEmptyContextSaysSoInsteadOfPretending() {
        let item = task("Loose end")
        let brief = PromptBuilder.brief(task: item, categoryName: nil, dueDescription: nil, context: .empty)
        XCTAssertTrue(brief.contains("do not assume a repository"), brief)
    }

    func testTheBriefIsCappedSoOneGenerationCannotBalloon() {
        let item = task("Big project")
        let huge = String(repeating: "x", count: 100_000)
        let brief = PromptBuilder.brief(
            task: item, categoryName: "Big", dueDescription: nil,
            context: ProjectContext(projectName: "Big", repoPath: "/tmp/big",
                                    documents: [.init(name: "HUGE.md", body: huge)])
        )
        XCTAssertLessThanOrEqual(brief.count, PromptBuilder.totalLimit + 32)
        XCTAssertTrue(brief.contains("[truncated]"))
    }

    func testTheGeneratedPromptLandsInTheTranscriptAndIsKept() async {
        client.queued = [.success(MessagesResponse(
            id: "m", model: "claude-haiku-4-5", stop_reason: "end_turn",
            content: [.text("Open the repo and fix the filter. Verify with bun test.")]
        ))]
        let item = task("Fix the filter", category: "MNZIL CRM")

        await model.generateClaudeCodePrompt(for: item)

        XCTAssertEqual(model.chatMessages.count, 2)
        XCTAssertTrue(model.chatMessages[0].text.contains("Write a Claude Code prompt"))
        XCTAssertEqual(model.lastGenerated, "Open the repo and fix the filter. Verify with bun test.")
        XCTAssertNil(model.chatError)
    }

    func testAFailureIsReportedAndNothingIsClaimed() async {
        client.queued = [.failure(ClaudeError.rateLimited)]
        let item = task("Fix the filter", category: "MNZIL CRM")
        await model.generateClaudeCodePrompt(for: item)
        XCTAssertEqual(model.chatError, ClaudeError.rateLimited.message)
        XCTAssertNil(model.lastGenerated)
    }

    func testGenerationIsNotMixedIntoTheChatConversation() async {
        client.queued = [.success(MessagesResponse(id: "m", model: "m", stop_reason: "end_turn",
                                                   content: [.text("a prompt")]))]
        let item = task("Fix the filter", category: "MNZIL CRM")
        await model.generateClaudeCodePrompt(for: item)

        let request = client.requests.last!
        XCTAssertNil(request.tools, "a one-off generation must not offer the task tools")
        XCTAssertEqual(request.messages.count, 1, "and must not replay the chat history")
    }
}
