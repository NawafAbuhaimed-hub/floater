import XCTest
@testable import FloaterCore

/// Returns canned API responses so the suite never makes a network call.
final class FakeClaudeClient: ClaudeClient, @unchecked Sendable {
    var queued: [Result<MessagesResponse, Error>] = []
    private(set) var requests: [MessagesRequest] = []

    func send(_ request: MessagesRequest) async throws -> MessagesResponse {
        requests.append(request)
        guard !queued.isEmpty else {
            return MessagesResponse(id: "msg_default", model: "fake", stop_reason: "end_turn", content: [.text("ok")])
        }
        return try queued.removeFirst().get()
    }
}

private func response(
    text: String? = nil,
    tools: [(String, [String: JSONValue])] = [],
    stop: String = "end_turn"
) -> MessagesResponse {
    var blocks: [ContentBlock] = []
    if let text { blocks.append(.text(text)) }
    for (index, tool) in tools.enumerated() {
        blocks.append(.toolUse(id: "toolu_\(index)", name: tool.0, input: .object(tool.1)))
    }
    return MessagesResponse(id: "msg_1", model: "claude-haiku-4-5",
                            stop_reason: tools.isEmpty ? stop : "tool_use", content: blocks)
}

// MARK: - Wire format

final class ClaudeAPICodingTests: XCTestCase {
    func testToolSchemasAreStrictAndListEveryPropertyAsRequired() throws {
        for tool in ChatEngine.tools {
            XCTAssertTrue(tool.strict, "\(tool.name) must be strict")
            let schema = tool.input_schema
            XCTAssertEqual(schema["additionalProperties"], .bool(false), "\(tool.name)")
            let properties = schema["properties"]?.objectValue ?? [:]
            let required = Set((schema["required"]?.arrayValue ?? []).compactMap(\.stringValue))
            XCTAssertFalse(properties.isEmpty, "\(tool.name) has no properties")
            XCTAssertEqual(required, Set(properties.keys),
                           "strict tool use requires every property of \(tool.name) to be required")
        }
    }

    func testRequestEncodesTheDocumentedWireShape() throws {
        let request = MessagesRequest(
            model: "claude-haiku-4-5", maxTokens: 4096, system: "sys",
            messages: [.user("hi")], tools: [ChatEngine.tools[0]]
        )
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as! [String: Any]
        XCTAssertEqual(json["model"] as? String, "claude-haiku-4-5")
        XCTAssertEqual(json["max_tokens"] as? Int, 4096)
        XCTAssertEqual(json["system"] as? String, "sys")
        let messages = json["messages"] as! [[String: Any]]
        XCTAssertEqual(messages[0]["role"] as? String, "user")
        let content = messages[0]["content"] as! [[String: Any]]
        XCTAssertEqual(content[0]["type"] as? String, "text")
        XCTAssertEqual(content[0]["text"] as? String, "hi")
        let tools = json["tools"] as! [[String: Any]]
        XCTAssertEqual(tools[0]["name"] as? String, "create_task")
        XCTAssertNotNil(tools[0]["input_schema"])
    }

    func testIntegersEncodeWithoutATrailingDecimal() throws {
        let encoded = String(data: try JSONEncoder().encode(JSONValue.number(15)), encoding: .utf8)
        XCTAssertEqual(encoded, "15")
    }

    func testResponseDecodesTextToolUseAndUnknownBlocks() throws {
        let payload = """
        {"id":"msg_1","model":"claude-haiku-4-5","stop_reason":"tool_use","content":[
          {"type":"thinking","thinking":""},
          {"type":"text","text":"Proposing two tasks."},
          {"type":"tool_use","id":"toolu_1","name":"create_task",
           "input":{"ref":"new-1","title":"Call Omar","note":"","status":"notStarted"}}
        ]}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(MessagesResponse.self, from: payload)
        XCTAssertEqual(decoded.text, "Proposing two tasks.")
        XCTAssertEqual(decoded.toolUses.count, 1)
        XCTAssertEqual(decoded.toolUses[0].name, "create_task")
        XCTAssertEqual(decoded.toolUses[0].input["title"]?.stringValue, "Call Omar")
        XCTAssertEqual(decoded.content.count, 3, "an unknown block type must not break decoding")
    }

    func testErrorBodiesMapToUsefulMessages() {
        let body = #"{"type":"error","error":{"type":"invalid_request_error","message":"bad thing"}}"#.data(using: .utf8)!
        XCTAssertEqual(AnthropicClient.error(status: 401, body: body), .unauthorized)
        XCTAssertEqual(AnthropicClient.error(status: 429, body: body), .rateLimited)
        XCTAssertEqual(AnthropicClient.error(status: 400, body: body), .server(status: 400, message: "bad thing"))
    }

    func testDateParsingAcceptsBothZonedAndBareLocalForms() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"

        for raw in ["2026-09-01T09:00:00", "2026-09-01T09:00", "2026-09-01 09:00"] {
            let parsed = ChatEngine.parseDate(raw, calendar: calendar)
            XCTAssertNotNil(parsed, raw)
            XCTAssertEqual(parsed.map { formatter.string(from: $0) }, "2026-09-01 09:00", raw)
        }
        XCTAssertNil(ChatEngine.parseDate("next tuesday", calendar: calendar))
    }
}

// MARK: - Proposals and applying them

@MainActor
final class ChatProposalTests: XCTestCase {
    private var clock: TestClock!
    private var store: Store!
    private var model: AppModel!
    private var client: FakeClaudeClient!
    private var scheduler: FakeScheduler!

    override func setUpWithError() throws {
        try super.setUpWithError()
        clock = TestClock()
        store = try Store(inMemory: true)
        client = FakeClaudeClient()
        scheduler = FakeScheduler()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        let fake = client!
        model = AppModel(
            store: store, prefs: Preferences(store: InMemoryStore()), clock: clock,
            calendar: calendar, scheduler: scheduler,
            keyStore: InMemoryAPIKeyStore(value: "sk-test"),
            makeChatEngine: { _ in ChatEngine(client: fake, clock: self.clock, calendar: calendar) },
            autoTick: false
        )
    }

    private func send(_ text: String) async {
        model.chatDraft = text
        await model.sendChat()
    }

    private func task(_ title: String) -> TaskItem? {
        model.tasks.first { $0.title == title }
    }

    // MARK: Nothing happens without confirmation

    func testProposalsDoNotTouchTheTaskListUntilApplied() async {
        client.queued = [.success(response(text: "Two tasks?", tools: [
            ("create_task", ["ref": .string("new-1"), "title": .string("Call Omar"),
                             "note": .string(""), "status": .string("notStarted")]),
        ]))]
        await send("call omar")

        XCTAssertEqual(model.pendingActions.count, 1)
        XCTAssertTrue(model.tasks.isEmpty, "nothing may be created before Apply")

        await model.applyProposals()
        XCTAssertEqual(model.tasks.map(\.title), ["Call Omar"])
        XCTAssertTrue(model.pendingActions.isEmpty)
    }

    func testDiscardingThrowsTheChangesAway() async {
        client.queued = [.success(response(tools: [
            ("create_task", ["ref": .string("new-1"), "title": .string("Nope"),
                             "note": .string(""), "status": .string("notStarted")]),
        ]))]
        await send("add nope")
        model.discardProposals()

        XCTAssertTrue(model.pendingActions.isEmpty)
        XCTAssertTrue(model.tasks.isEmpty)
    }

    // MARK: Mapping

    func testACreateWithANoteAndStatusIsAppliedInFull() async {
        client.queued = [.success(response(tools: [
            ("create_task", ["ref": .string("new-1"), "title": .string("Draft Q3 deck"),
                             "note": .string("waiting on legal"), "status": .string("blocked")]),
        ]))]
        await send("draft the q3 deck, blocked on legal")
        await model.applyProposals()

        let created = task("Draft Q3 deck")
        XCTAssertEqual(created?.status, .blocked)
        XCTAssertEqual(created?.note, "waiting on legal")
    }

    func testAnActionCanTargetATaskCreatedInTheSameTurn() async {
        client.queued = [.success(response(tools: [
            ("create_task", ["ref": .string("new-1"), "title": .string("Write the brief"),
                             "note": .string(""), "status": .string("notStarted")]),
            ("start_timer", ["task_id": .string("new-1"), "minutes": .number(45)]),
        ]))]
        await send("write the brief and start 45 minutes on it")
        XCTAssertEqual(model.pendingActions.count, 2)

        await model.applyProposals()

        XCTAssertEqual(model.activeTitle, "Write the brief")
        XCTAssertEqual(model.remainingText, "45:00")
        XCTAssertEqual(task("Write the brief")?.status, .inProgress)
    }

    func testExistingTasksAreAddressedByHandle() async {
        model.draft = "Existing work"
        model.addDraftTask()
        client.queued = [.success(response(tools: [
            ("set_task_status", ["task_id": .string("t1"), "status": .string("blocked")]),
        ]))]
        await send("existing work is blocked")
        await model.applyProposals()

        XCTAssertEqual(task("Existing work")?.status, .blocked)
    }

    func testTheTaskSnapshotIsSentToTheModel() async {
        model.draft = "Existing work"
        model.addDraftTask()
        await send("what's on my list?")

        let system = client.requests.last?.system ?? ""
        XCTAssertTrue(system.contains("t1 [notStarted] Existing work"), system)
        XCTAssertTrue(system.contains("PROPOSAL"), "the model must be told nothing applies until confirmed")
    }

    func testAnUnknownHandleIsDroppedRatherThanGuessed() async {
        client.queued = [.success(response(tools: [
            ("set_task_status", ["task_id": .string("t9"), "status": .string("done")]),
        ]))]
        await send("finish the ninth thing")
        XCTAssertTrue(model.pendingActions.isEmpty, "a handle that maps to nothing must not become an action")
    }

    func testAnOutOfRangeTimerIsRejected() async {
        model.draft = "Something"
        model.addDraftTask()
        client.queued = [.success(response(tools: [
            ("start_timer", ["task_id": .string("t1"), "minutes": .number(9000)]),
        ]))]
        await send("start a very long timer")
        XCTAssertTrue(model.pendingActions.isEmpty)
    }

    func testDeletionIsFlaggedDestructive() async {
        model.draft = "Old thing"
        model.addDraftTask()
        client.queued = [.success(response(tools: [("delete_task", ["task_id": .string("t1")])]))]
        await send("delete old thing")

        XCTAssertEqual(model.pendingActions.count, 1)
        XCTAssertTrue(model.pendingActions[0].isDestructive)
        XCTAssertFalse(model.tasks.isEmpty, "still not deleted before Apply")

        await model.applyProposals()
        XCTAssertTrue(model.tasks.isEmpty)
    }

    func testAFollowUpProposalReachesTheScheduler() async {
        model.draft = "Chase the invoice"
        model.addDraftTask()
        client.queued = [.success(response(tools: [
            ("schedule_follow_up", ["task_id": .string("t1"), "when": .string("2026-09-01T09:00:00"),
                                    "destination": .string("reminders")]),
        ]))]
        await send("remind me about the invoice on sept 1")
        await model.applyProposals()

        XCTAssertEqual(scheduler.scheduled.count, 1)
        XCTAssertEqual(scheduler.scheduled[0].destination, .reminders)
        XCTAssertEqual(scheduler.scheduled[0].title, "Follow up: Chase the invoice")
    }

    // MARK: Conversation and errors

    func testTheTranscriptRecordsBothSides() async {
        client.queued = [.success(response(text: "Sure."))]
        await send("hello")
        XCTAssertEqual(model.chatMessages.map(\.text), ["hello", "Sure."])
        XCTAssertEqual(model.chatMessages.map(\.isUser), [true, false])
        XCTAssertEqual(model.chatDraft, "", "the draft clears once sent")
    }

    func testAToolOnlyResponseStillGetsAReply() async {
        client.queued = [.success(response(tools: [
            ("create_task", ["ref": .string("new-1"), "title": .string("Quiet task"),
                             "note": .string(""), "status": .string("notStarted")]),
        ]))]
        await send("add quiet task")
        XCTAssertEqual(model.chatMessages.last?.text, "Proposed 1 change.")
    }

    func testHistoryIsReplayedAsPlainTextOnTheNextTurn() async {
        client.queued = [.success(response(text: "First reply")), .success(response(text: "Second reply"))]
        await send("one")
        await send("two")

        let messages = client.requests.last?.messages ?? []
        XCTAssertEqual(messages.count, 3)
        XCTAssertEqual(messages.map(\.role), ["user", "assistant", "user"])
        for message in messages {
            for block in message.content {
                XCTAssertNotNil(block.textValue, "replayed history must be plain text, never a dangling tool_use")
            }
        }
    }

    func testAnAPIFailureIsShownAndTheListIsUntouched() async {
        client.queued = [.failure(ClaudeError.unauthorized)]
        await send("do something")
        XCTAssertEqual(model.chatError, ClaudeError.unauthorized.message)
        XCTAssertTrue(model.pendingActions.isEmpty)
        XCTAssertTrue(model.tasks.isEmpty)
    }

    func testARefusalIsReportedRatherThanTreatedAsAReply() async {
        client.queued = [.success(response(text: "", stop: "refusal"))]
        await send("something disallowed")
        XCTAssertEqual(model.chatError, ClaudeError.refused.message)
    }

    func testChatIsUnavailableWithoutAKey() async throws {
        let bare = AppModel(store: try Store(inMemory: true),
                            prefs: Preferences(store: InMemoryStore()), clock: clock,
                            keyStore: InMemoryAPIKeyStore(), autoTick: false)
        XCTAssertFalse(bare.hasAPIKey)
        bare.chatDraft = "hi"
        await bare.sendChat()
        XCTAssertEqual(bare.chatError, ClaudeError.missingAPIKey.message)
    }

    func testSavingAKeyEnablesChat() throws {
        let keyStore = InMemoryAPIKeyStore()
        let bare = AppModel(store: try Store(inMemory: true),
                            prefs: Preferences(store: InMemoryStore()), clock: clock,
                            keyStore: keyStore,
                            makeChatEngine: { _ in ChatEngine(client: FakeClaudeClient()) },
                            autoTick: false)
        XCTAssertFalse(bare.hasAPIKey)
        bare.saveAPIKey("  sk-ant-test  ")
        XCTAssertTrue(bare.hasAPIKey)
        XCTAssertEqual(keyStore.read(), "sk-ant-test", "the key is trimmed before storage")
    }

    func testClearingChatEmptiesTheTranscript() async {
        client.queued = [.success(response(text: "hi"))]
        await send("hello")
        model.clearChat()
        XCTAssertTrue(model.chatMessages.isEmpty)
        XCTAssertTrue(model.pendingActions.isEmpty)
    }
}

@MainActor
final class ChatCategoryAndDueTests: XCTestCase {
    private var clock: TestClock!
    private var store: Store!
    private var model: AppModel!
    private var client: FakeClaudeClient!
    private var calendar: Calendar!

    override func setUpWithError() throws {
        try super.setUpWithError()
        clock = TestClock(now: Date(timeIntervalSince1970: 1_773_153_120)) // 2026-03-10 London
        store = try Store(inMemory: true)
        client = FakeClaudeClient()
        calendar = {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(identifier: "Europe/London")!
            return cal
        }()
        let fake = client!
        let cal = calendar!
        let tick = clock!
        model = AppModel(
            store: store, prefs: Preferences(store: InMemoryStore()), clock: clock,
            calendar: cal, keyStore: InMemoryAPIKeyStore(value: "sk-test"),
            makeChatEngine: { _ in ChatEngine(client: fake, clock: tick, calendar: cal) },
            autoTick: false
        )
        model.logCompletions = false
    }

    private func send(_ text: String) async {
        model.chatDraft = text
        await model.sendChat()
    }

    private func addTask(_ title: String) -> TaskItem {
        model.draft = title
        model.addDraftTask()
        return model.tasks.first { $0.title == title }!
    }

    private func reread(_ task: TaskItem) -> TaskItem { model.tasks.first { $0.id == task.id }! }

    func testTheSnapshotListsCategoriesSoTheModelCanUseTheirNames() async {
        _ = addTask("Something")
        await send("what categories do I have?")
        let system = client.requests.last?.system ?? ""
        XCTAssertTrue(system.contains("Categories"), system)
        XCTAssertTrue(system.contains("MNZIL CRM"), "the seeded projects must be offered by name")
    }

    func testItCanPutATaskInACategory() async {
        let task = addTask("Fix the lost reason tree")
        client.queued = [.success(response(tools: [
            ("set_category", ["task_id": .string("t1"), "category": .string("MNZIL CRM")]),
        ]))]
        await send("that one is MNZIL CRM")
        XCTAssertEqual(model.pendingActions.count, 1)

        await model.applyProposals()

        let category = model.category(of: reread(task))
        XCTAssertEqual(category?.name, "MNZIL CRM")
        XCTAssertEqual(category?.repoPath.hasSuffix("/mnzilpostsales"), true,
                       "the category is what later tells the prompt generator which repo to read")
    }

    func testAnUnknownCategoryIsDroppedRatherThanInvented() async {
        _ = addTask("Something")
        client.queued = [.success(response(tools: [
            ("set_category", ["task_id": .string("t1"), "category": .string("Nonexistent")]),
        ]))]
        await send("put it in Nonexistent")
        XCTAssertTrue(model.pendingActions.isEmpty)
    }

    func testClearingACategoryIsAllowed() async {
        let task = addTask("Categorised")
        model.setCategory(model.categories.first, for: task)
        client.queued = [.success(response(tools: [
            ("set_category", ["task_id": .string("t1"), "category": .string("")]),
        ]))]
        await send("take it out of that project")
        await model.applyProposals()
        XCTAssertNil(reread(task).categoryID)
    }

    func testItCanSetADueDate() async {
        let task = addTask("Ship it")
        client.queued = [.success(response(tools: [
            ("set_due_date", ["task_id": .string("t1"), "due": .string("2026-03-20")]),
        ]))]
        await send("due on the 20th")
        await model.applyProposals()

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        XCTAssertEqual(reread(task).dueDate.map { formatter.string(from: $0) }, "2026-03-20")
    }

    func testItCanClearADueDate() async {
        let task = addTask("No longer urgent")
        model.setDueDate(Date(), for: task)
        client.queued = [.success(response(tools: [
            ("set_due_date", ["task_id": .string("t1"), "due": .string("")]),
        ]))]
        await send("drop the deadline")
        await model.applyProposals()
        XCTAssertNil(reread(task).dueDate)
    }

    func testAnUnparseableDueDateIsDropped() async {
        _ = addTask("Vague")
        client.queued = [.success(response(tools: [
            ("set_due_date", ["task_id": .string("t1"), "due": .string("sometime soon")]),
        ]))]
        await send("due sometime soon")
        XCTAssertTrue(model.pendingActions.isEmpty)
    }
}

@MainActor
final class ChatCreateWithCategoryTests: XCTestCase {
    func testCreatingATaskCanSetItsCategoryAndDueDateInOneGo() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        let clock = TestClock(now: Date(timeIntervalSince1970: 1_773_153_120))
        let store = try Store(inMemory: true)
        let client = FakeClaudeClient()
        let model = AppModel(
            store: store, prefs: Preferences(store: InMemoryStore()), clock: clock,
            calendar: calendar, keyStore: InMemoryAPIKeyStore(value: "sk-test"),
            makeChatEngine: { _ in ChatEngine(client: client, clock: clock, calendar: calendar) },
            autoTick: false
        )
        model.logCompletions = false

        client.queued = [.success(response(tools: [
            ("create_task", [
                "ref": .string("new-1"),
                "title": .string("Fix the qualifier filter"),
                "note": .string(""),
                "status": .string("notStarted"),
                "category": .string("MNZIL CRM"),
                "due": .string("2026-03-18"),
            ]),
        ]))]
        model.chatDraft = "add: fix the qualifier filter for MNZIL CRM, due the 18th"
        await model.sendChat()

        XCTAssertEqual(model.pendingActions.count, 1)
        XCTAssertTrue(model.pendingActions[0].summary.contains("MNZIL CRM"), model.pendingActions[0].summary)

        await model.applyProposals()

        let task = model.tasks.first { $0.title == "Fix the qualifier filter" }!
        XCTAssertEqual(model.category(of: task)?.name, "MNZIL CRM")
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        XCTAssertEqual(task.dueDate.map { formatter.string(from: $0) }, "2026-03-18")
    }
}
