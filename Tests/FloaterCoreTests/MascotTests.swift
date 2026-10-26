import XCTest
import Combine
@testable import FloaterCore

final class MascotMoodTests: XCTestCase {
    private func mood(_ input: MascotInput) -> MascotMood { MascotMood.current(input) }

    // MARK: - Each mood, on its own

    func testAFreshRunIsGearUp() {
        XCTAssertEqual(mood(MascotInput(phase: .running, progress: 0.1, remaining: 1500)), .gearUp)
    }

    func testPastHalfwayIsLockedIn() {
        XCTAssertEqual(mood(MascotInput(phase: .running, progress: 0.6, remaining: 600)), .lockedIn)
    }

    func testUnderTwoMinutesIsFinalStretch() {
        XCTAssertEqual(mood(MascotInput(phase: .running, progress: 0.95, remaining: 90)), .finalStretch)
    }

    func testAFreshFinishIsVictory() {
        XCTAssertEqual(mood(MascotInput(secondsSinceCompletion: 10)), .victory)
    }

    func testAStreakIsOnFire() {
        XCTAssertEqual(mood(MascotInput(streakDays: MascotMood.onFireDays)), .onFire)
        XCTAssertNotEqual(mood(MascotInput(streakDays: MascotMood.onFireDays - 1)), .onFire)
    }

    func testAMetGoalIsLegend() {
        XCTAssertEqual(mood(MascotInput(goalMet: true)), .legend)
    }

    func testAPausedTimerIsPaused() {
        XCTAssertEqual(mood(MascotInput(phase: .paused, progress: 0.3, remaining: 900)), .paused)
    }

    func testOverdueWorkIsNagging() {
        XCTAssertEqual(mood(MascotInput(overdue: 2)), .nagging)
    }

    func testBlockedWorkIsStuck() {
        XCTAssertEqual(mood(MascotInput(blocked: 1)), .stuck)
    }

    func testEarlyMorningAndLateEveningAreSleepy() {
        for hour in [0, 3, 6, 21, 23] {
            XCTAssertEqual(mood(MascotInput(hour: hour)), .sleepy, "hour \(hour)")
        }
        for hour in [7, 12, 20] {
            XCTAssertNotEqual(mood(MascotInput(hour: hour)), .sleepy, "hour \(hour)")
        }
    }

    func testAnIdleDeskWithWorkWaitingGetsBored() {
        XCTAssertEqual(
            mood(MascotInput(secondsSinceActivity: MascotMood.boredAfter, openTasks: 3)), .bored)
    }

    func testBoredNeedsWorkWaitingAndEnoughTime() {
        XCTAssertNotEqual(
            mood(MascotInput(secondsSinceActivity: MascotMood.boredAfter, openTasks: 0)), .bored,
            "nothing to do is not boredom")
        XCTAssertNotEqual(
            mood(MascotInput(secondsSinceActivity: MascotMood.boredAfter - 1, openTasks: 3)), .bored)
    }

    func testNothingToReportIsChilling() {
        XCTAssertEqual(mood(MascotInput()), .chilling)
    }

    func testVictoryFadesAfterItsWindow() {
        XCTAssertEqual(mood(MascotInput(secondsSinceCompletion: MascotMood.victoryWindow)), .victory)
        XCTAssertEqual(mood(MascotInput(secondsSinceCompletion: MascotMood.victoryWindow + 1)), .chilling)
    }

    // MARK: - Precedence

    func testVictoryBeatsARunningTimer() {
        XCTAssertEqual(
            mood(MascotInput(phase: .running, progress: 0.99, remaining: 10, secondsSinceCompletion: 5)),
            .victory)
    }

    func testFinalStretchBeatsLockedIn() {
        XCTAssertEqual(mood(MascotInput(phase: .running, progress: 0.9, remaining: 60)), .finalStretch)
    }

    func testRunningMoodsBeatLegendOnFireAndNagging() {
        let busy = MascotInput(phase: .running, progress: 0.7, remaining: 600,
                               streakDays: 10, goalMet: true, overdue: 2, blocked: 1)
        XCTAssertEqual(mood(busy), .lockedIn)
        var early = busy
        early.progress = 0.1
        XCTAssertEqual(mood(early), .gearUp)
    }

    func testPausedBeatsTheIdleMoods() {
        XCTAssertEqual(
            mood(MascotInput(phase: .paused, streakDays: 10, goalMet: true, overdue: 2)), .paused)
    }

    func testLegendBeatsOnFire() {
        XCTAssertEqual(mood(MascotInput(streakDays: 10, goalMet: true)), .legend)
    }

    func testOnFireBeatsNagging() {
        XCTAssertEqual(mood(MascotInput(streakDays: 5, overdue: 1)), .onFire)
    }

    func testNaggingBeatsStuck() {
        XCTAssertEqual(mood(MascotInput(overdue: 1, blocked: 4)), .nagging)
    }

    func testOverdueBeatsSleepy() {
        XCTAssertEqual(mood(MascotInput(overdue: 1, hour: 23)), .nagging)
    }

    func testSleepyBeatsBored() {
        XCTAssertEqual(
            mood(MascotInput(secondsSinceActivity: 99_999, openTasks: 5, hour: 2)), .sleepy)
    }

    // MARK: - Running versus idle

    func testARunningTimerNeverYieldsAnIdleMood() {
        let idleMoods: Set<MascotMood> = [.legend, .onFire, .nagging, .stuck, .sleepy, .bored, .chilling]
        for progress in stride(from: 0.0, through: 1.0, by: 0.25) {
            for remaining in [0.0, 60, 119, 120, 600, 3000] {
                for goalMet in [false, true] {
                    let input = MascotInput(phase: .running, progress: progress, remaining: remaining,
                                            secondsSinceActivity: 99_999, streakDays: 9, goalMet: goalMet,
                                            overdue: 1, blocked: 1, openTasks: 4, hour: 2)
                    XCTAssertFalse(idleMoods.contains(mood(input)), "\(input)")
                }
            }
        }
    }

    func testAnIdleDeskNeverClaimsToBeRunning() {
        let runMoods: Set<MascotMood> = [.lockedIn, .gearUp, .finalStretch]
        for progress in [0.0, 0.6, 1.0] {
            for remaining in [0.0, 60, 600] {
                for phase in [TimerPhase.idle, .elapsed, .paused] {
                    let input = MascotInput(phase: phase, progress: progress, remaining: remaining,
                                            streakDays: 9, goalMet: true, overdue: 1, blocked: 1)
                    XCTAssertFalse(runMoods.contains(mood(input)), "\(input)")
                }
            }
        }
        XCTAssertNotEqual(mood(MascotInput(phase: .idle, progress: 0.8, remaining: 30)), .lockedIn)
    }

    func testATimerThatHitZeroFallsThroughToTheIdleMoods() {
        XCTAssertEqual(mood(MascotInput(phase: .elapsed, progress: 1, remaining: 0)), .chilling)
        XCTAssertEqual(mood(MascotInput(phase: .elapsed, progress: 1, remaining: 0, overdue: 1)), .nagging)
        XCTAssertEqual(mood(MascotInput(phase: .elapsed, progress: 1, remaining: 0, goalMet: true)), .legend)
        XCTAssertEqual(
            mood(MascotInput(phase: .elapsed, progress: 1, remaining: 0, secondsSinceCompletion: 3)),
            .victory, "a finish is still celebrated")
    }

    // MARK: - The cast

    func testThereAreTwelveMoodsEachWithALineAndAName() {
        XCTAssertEqual(MascotMood.allCases.count, 12)
        for mood in MascotMood.allCases {
            XCTAssertFalse(mood.line.isEmpty, "\(mood) has no line")
            XCTAssertFalse(mood.name.isEmpty, "\(mood) has no name")
        }
    }

    func testEveryMoodCanBeReached() {
        let inputs: [MascotInput] = [
            MascotInput(phase: .running, progress: 0.1, remaining: 1500),
            MascotInput(phase: .running, progress: 0.6, remaining: 600),
            MascotInput(phase: .running, progress: 0.95, remaining: 30),
            MascotInput(secondsSinceCompletion: 1),
            MascotInput(streakDays: 3),
            MascotInput(goalMet: true),
            MascotInput(phase: .paused),
            MascotInput(overdue: 1),
            MascotInput(blocked: 1),
            MascotInput(hour: 3),
            MascotInput(secondsSinceActivity: 99_999, openTasks: 2),
            MascotInput(),
        ]
        XCTAssertEqual(Set(inputs.map { MascotMood.current($0) }), Set(MascotMood.allCases))
    }
}

/// The wiring: the model builds the input and only republishes a real change.
@MainActor
final class MascotWiringTests: XCTestCase {
    private var model: AppModel!
    private var clock: TestClock!

    override func setUpWithError() throws {
        try super.setUpWithError()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        // 2026-03-10 14:32 London: mid-afternoon, so never sleepy.
        clock = TestClock(now: Date(timeIntervalSince1970: 1_773_153_120))
        model = AppModel(store: try Store(inMemory: true),
                         prefs: Preferences(store: InMemoryStore()),
                         clock: clock, calendar: calendar, autoTick: false)
        model.logCompletions = false
    }

    func testAQuietModelIsChilling() {
        XCTAssertEqual(model.mood, .chilling)
    }

    func testStartingATimerGearsUpAndStoppingItEndsTheMood() {
        model.draft = "Write the report"
        model.addDraftTask()
        model.start(model.tasks[0], minutes: 30)
        XCTAssertEqual(model.mood, .gearUp)

        model.stopTimer()
        XCTAssertNotEqual(model.mood, .gearUp)
    }

    func testFinishingATaskCelebratesThenFades() {
        model.draft = "Ship it"
        model.addDraftTask()
        model.complete(model.tasks[0])
        XCTAssertEqual(model.mood, .victory)

        clock.advance(MascotMood.victoryWindow + 1)
        model.tick()
        XCTAssertNotEqual(model.mood, .victory)
    }

    func testAnIdleDeskGetsBoredOnlyWithWorkWaiting() {
        model.tick()
        XCTAssertEqual(model.mood, .chilling, "no tasks, nothing to be bored about")

        model.draft = "Something to do"
        model.addDraftTask()
        clock.advance(MascotMood.boredAfter + 1)
        model.tick()
        XCTAssertEqual(model.mood, .bored)
    }

    func testABlockedTaskLooksStuck() {
        model.draft = "Waiting on legal"
        model.addDraftTask()
        model.setStatus(.blocked, for: model.tasks[0])
        XCTAssertEqual(model.mood, .stuck)
    }

    // MARK: - QA fixes (all on in-memory stores)

    /// Bug 1: a run that times out is 25 minutes of work, not 25 idle minutes.
    func testALongRunThatElapsesIsNotBored() {
        model.draft = "Deep work"
        model.addDraftTask()
        model.start(model.tasks[0], minutes: 25)
        clock.advance(25 * 60 + 1)
        model.onTick()
        XCTAssertEqual(model.phase, .elapsed)
        XCTAssertNotEqual(model.mood, .bored)

        // The clock for boredom starts at the moment it elapsed, not before.
        clock.advance(MascotMood.boredAfter - 5)
        model.tick()
        XCTAssertNotEqual(model.mood, .bored)
        clock.advance(10)
        model.tick()
        XCTAssertEqual(model.mood, .bored)
    }

    /// Bug 2: through the real onTick path, a fading victory shows within the
    /// idle cadence (8 ticks), not 30 seconds later.
    func testTheIdleFaceCatchesUpThroughTheRealTickPath() {
        model.draft = "Ship it"
        model.addDraftTask()
        model.complete(model.tasks[0])
        XCTAssertEqual(model.mood, .victory)

        clock.advance(MascotMood.victoryWindow + 1)
        model.onTick()
        XCTAssertEqual(model.mood, .victory, "not every tick re-checks the face")

        for _ in 0..<7 { model.onTick() }
        XCTAssertNotEqual(model.mood, .victory, "within 8 ticks (2s) the face has updated")
    }

    /// Bug 3: things the user does keep Groot from getting bored.
    private func assertNotBored(afterDoing action: (TaskItem) -> Void,
                                _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        model.draft = "Target"
        model.addDraftTask()
        model.draft = "Bystander"
        model.addDraftTask()
        let target = model.tasks.first { $0.title == "Target" }!
        clock.advance(MascotMood.boredAfter - 60)
        action(target)
        clock.advance(120)
        model.tick()
        XCTAssertNotEqual(model.mood, .bored, label, file: file, line: line)
    }

    func testControlWithoutAnyActionTheDeskGetsBored() {
        model.draft = "Target"
        model.addDraftTask()
        clock.advance(MascotMood.boredAfter - 60)
        clock.advance(120)
        model.tick()
        XCTAssertEqual(model.mood, .bored)
    }

    func testUserActionsCountAsActivity() {
        assertNotBored(afterDoing: { self.model.delete($0) }, "delete")
        tearDownAndResetModel()
        assertNotBored(afterDoing: { self.model.setDueDate(Date(timeIntervalSince1970: 2_000_000_000), for: $0) }, "setDueDate")
        tearDownAndResetModel()
        assertNotBored(afterDoing: { self.model.setCategory(nil, for: $0) }, "setCategory")
        tearDownAndResetModel()
        assertNotBored(afterDoing: { _ in self.model.clearCompleted() }, "clearCompleted")
        tearDownAndResetModel()
        assertNotBored(afterDoing: { self.model.noteChanged("typing", for: $0) }, "note edit")
        tearDownAndResetModel()
        assertNotBored(afterDoing: { _ in _ = self.model.addCategory(name: "New") }, "addCategory")
    }

    func testReopeningATaskCountsAsActivity() {
        assertNotBored(afterDoing: { task in
            self.model.complete(task)
            self.clock.advance(MascotMood.victoryWindow + 1)
            self.model.reopen(task)
        }, "reopen")
    }

    func testExtendingARunCountsAsActivity() {
        model.draft = "Deep work"
        model.addDraftTask()
        model.start(model.tasks[0], minutes: 5)
        clock.advance(5 * 60 + 1)
        model.onTick()
        XCTAssertEqual(model.phase, .elapsed)
        clock.advance(MascotMood.boredAfter - 60)
        model.extend(minutes: 10)
        clock.advance(120)
        model.tick()
        XCTAssertNotEqual(model.mood, .bored)
    }

    func testScratchpadEditsCountAsActivityAfterTheDebounce() {
        model.draft = "Target"
        model.addDraftTask()
        clock.advance(MascotMood.boredAfter - 60)
        model.scratchpad = "jotting"
        // Let the 400ms debounce fire on the main run loop.
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        clock.advance(120)
        model.tick()
        XCTAssertNotEqual(model.mood, .bored)
    }

    /// Typing must not cost a publish: noting activity changes no @Published value.
    func testNoteChangedDoesNotPublishPerKeystroke() {
        model.draft = "Target"
        model.addDraftTask()
        var publishes = 0
        let sub = model.objectWillChange.sink { publishes += 1 }
        for i in 0..<50 { model.noteChanged("text \(i)", for: model.tasks[0]) }
        XCTAssertEqual(publishes, 0)
        sub.cancel()
    }

    /// A system clock set backwards must not read as a fresh win.
    func testAClockSetBackwardsIsNotVictory() {
        model.draft = "Ship it"
        model.addDraftTask()
        model.complete(model.tasks[0])
        XCTAssertEqual(model.mood, .victory)

        clock.advance(-3600)
        model.tick()
        XCTAssertNotEqual(model.mood, .victory)
    }

    private func tearDownAndResetModel() {
        try? setUpWithError()
    }
}
