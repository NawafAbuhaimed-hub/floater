# Floater — design

**Date:** 2026-08-30
**Status:** implemented

## Problem

A task list only helps if it is in front of you. Menu bar and Dock task apps are
one context switch away, so tasks get forgotten. Floater keeps the current task
and its countdown permanently visible, above every window, without interrupting
what you are doing.

## Decisions

| Decision | Choice | Why |
|---|---|---|
| Stack | Native SwiftUI + AppKit | Only raw `NSPanel` gives reliable above-fullscreen, cross-Space floating. ~5 MB, instant launch. |
| Resting form | Small floating pill | Always visible, minimal footprint; expands on demand. |
| Timer model | Attached to a task | Time is logged per task, so "45 minutes on X" is answerable. |
| Time-up | Chime + pulse + notification + full-screen takeover | User asked for all three; takeover is toggleable. |
| Celebration | Confetti burst + chime | ~1.9 s, then back to work. |
| Storage | Local SwiftData, persists | Same stack as the user's other apps; no sync complexity. |

## Architecture

`LSUIElement` accessory app — no Dock icon. A menu bar item carries the only
chrome: show/hide, sound, takeover toggle, quit.

Three windows, all `FloatingPanel` (a borderless `NSPanel`):

1. **Pill panel** — `.nonactivatingPanel`, level `.statusBar`, collection
   behavior `[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`. This
   combination is what puts it above every window on every Space including
   fullscreen, while letting it take keystrokes without activating the app.
2. **Celebration overlay** — full screen, click-through, confetti Canvas.
3. **Time-up takeover** — full screen, interactive, dimmed backdrop.

## Components

| Unit | Responsibility |
|---|---|
| `TimerEngine` | One focus run; deadline math; pause/resume/extend; fires `onElapsed` once |
| `Clock` | Injected time source; `TestClock` makes the engine deterministic |
| `Store` | SwiftData stack; task and session CRUD |
| `AppModel` | Publishes state to SwiftUI; banks focus time; owns the celebration/time-up hooks |
| `Preferences` | UserDefaults-backed settings and in-flight run persistence; injectable |
| `FloatingPanelController` | Panel size per mode, drag persistence, screen clamping |
| `OverlayWindowController` | Full-screen overlay lifecycle |

## Key design points

**Deadline-based countdown.** `remaining` is always `deadline - now`, never a
decremented counter. This is what makes the timer immune to dropped ticks,
machine sleep, and the app being quit — the three cases where tick-counting
timers silently lose time. Focus time is banked capped at the deadline, so a
machine that slept for eight hours does not report eight hours of focus.

**Focus time is banked exactly once.** `finishActiveRun(completedTask:)` returns
the seconds only when the caller is about to write them itself as part of the
completion save; otherwise it writes them directly. This was the sharpest edge
in the design and has a dedicated test.

**Screen clamping.** The panel's frame is clamped into the visible frame of the
display it most overlaps, on launch and on any display configuration change.
Covers unplugged monitors, resolution changes, and dragging off an edge.

## Testing

39 tests over `TimerEngine`, `Store`, and `AppModel`, all driven by `TestClock`
so no test waits on real time. They cover: countdown, pause/resume, extend from
each phase, sleep past the deadline, elapsed firing exactly once, banking time
once, relaunch with a live run, and relaunch with a run that expired while quit.

Window behaviour (level, size, position stability across launches) was verified
against the live window server rather than asserted.

## Addendum — statuses, notes, resizing

Added after the first build.

**Statuses.** `TaskStatus` (notStarted / inProgress / blocked / done) persisted
as a string so new cases never break an existing store. Status is the source of
truth; `completedAt` only records when it reached done and is cleared whenever
it leaves done, so "done today" cannot drift. Tasks written before statuses
existed are reconciled on load — a task with a `completedAt` comes back as done,
not as "Not started".

Transitions: starting a timer marks a task In progress; moving the *running*
task to any non-done status stops its timer and banks the focused time, since
you are no longer working on it.

**Notes.** A `note` string per task, edited inline under the task row, plus a
single-row `Scratchpad` model behind the Notes tab. Both write through on a
400 ms debounce rather than hitting SwiftData on every keystroke.

**Resizing.** Two things were needed beyond adding `.resizable` to the style
mask, both found by driving the real window rather than by reading code:

1. `NSHostingView` pushes SwiftUI's intrinsic size onto the window as Auto
   Layout constraints, which override `minSize`/`maxSize` and stopped the panel
   collapsing back to pill height. Fixed with `hosting.sizingOptions = []`.
2. `minSize`/`maxSize` are not honoured on a borderless panel at all, so user
   edge drags were unconstrained. Clamping moved into
   `windowWillResize(_:to:)`, which is the reliable hook.

Sizes are remembered per mode and saved only on `didEndLiveResize`, so the
app's own animated expand/collapse never overwrites what the user chose.

## Addendum — follow-ups

Finishing a task offers a follow-up in Calendar or Reminders. Presets are
Tomorrow / 3 days / Next week at 9am, plus a picker.

**Resolved against a calendar, not by adding seconds.** `FollowUpOffset` uses
`startOfDay` + `date(byAdding: .day)` + `bySettingHour`, so a preset lands at
9am local even across a DST change, a month end, or a leap day. Adding 86,400
seconds would land at 10:00 on the day the clocks go forward. Tested at all four
boundaries.

**Scheduling is behind `FollowUpScheduling`.** The app model is tested against a
fake, so the suite never touches a real calendar, never needs permissions, and
covers the paths that matter most: a denied permission, a missing default
calendar, and a retry after a failure. Failures keep the prompt open with the
reason on it rather than being swallowed.

**The prompt is its own small panel**, not part of the confetti overlay. The
confetti window is click-through by design; making it interactive would have
swallowed every click on screen while it showed. The prompt also deliberately
does *not* take key focus when it appears — it arrives unannounced and stealing
the caret mid-typing would be hostile. It takes focus only once the user opens
the date picker, which needs it.

**Access is write-only for Calendar** (`requestWriteOnlyAccessToEvents`), since
Floater only ever creates events.

## Deliberately not built

iCloud sync, subtasks, tags, projects, recurring tasks, a stats dashboard,
Pomodoro break cycles, global hotkeys. Follow-ups are one-way: Floater writes to
Calendar and Reminders and never reads them back, so an event you delete there
still shows on the task here.
