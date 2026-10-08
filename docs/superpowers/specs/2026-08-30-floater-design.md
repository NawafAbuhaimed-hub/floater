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

**Access was write-only for Calendar, and is now full.** Write-only is the least
privilege that can create events, but it cannot list calendars — and without a
list the user cannot choose *which* calendar receives follow-ups (a Google one,
say, rather than whatever macOS defaults to). The picker won, so
`requestFullAccessToEvents` it is. The chosen calendar is stored per destination
and falls back to the system default when unset or when the calendar has since
disappeared.

Two things only a live run against a real calendar could have found:

1. `defaultCalendarForNewEvents` under write-only access was an open question —
   the write path had never been executed. It works.
2. `availableTargets` gated itself on `EKEventStore.authorizationStatus`, which
   still reads `notDetermined` in-process immediately after the user grants
   access. The calendar list came back **empty right after being authorised**.
   It now asks the store directly, which returns nothing when access is
   genuinely missing and the real list when it is not.

## Addendum — chat

A Chat tab where plain language becomes changes to the task list. Swift has no
official Anthropic SDK, so this is raw HTTP against `POST /v1/messages`
(`claude-haiku-4-5`, strict tool use).

**Every tool is a proposal, which collapses the design.** Because nothing is
applied until the user confirms, the model never needs a real tool result — so
there is no agentic loop at all. One API call per turn: the response's
`tool_use` blocks become the change set, and the conversation history is kept as
plain text. That last part matters: replaying an assistant turn containing a
`tool_use` block without its matching `tool_result` is a 400, and it is the
failure a persisted transcript would walk straight into.

**Handles, not UUIDs.** The system prompt carries a snapshot of the task list
with short handles (`t1`, `t2`). The model addresses existing tasks by handle
and tasks it is creating this turn by its own ref (`new-1`), which are resolved
to real ids at apply time. A handle that maps to nothing is dropped rather than
guessed at.

**Testing.** `ClaudeClient` is a protocol, so the suite runs against canned
responses — no network, no key, no spend. Covered: the wire shape, decoding an
unknown block type, error mapping, every tool mapping, refs resolving across a
change set, out-of-range input being rejected, a refusal, and that a proposal
leaves the task list untouched until Apply.

The live paths were verified end to end against the real API through the real
engine: multi-tool turns, a question that correctly calls no tools, Arabic input,
and a destructive delete.

**The key is read lazily.** An early version read the Keychain in
`AppModel.init`, and the app launched to no window at all — `SecItemCopyMatching`
was blocking on a system access prompt before any window was created. The
Keychain is now untouched until the Chat tab is opened.

## Addendum — the completion log

Finishing a task writes a calendar event titled `<task> ✅`, on the same calendar
follow-ups use. It **ends** at the completion moment and **starts** a
focused-time earlier, so the calendar shows the real work block rather than a
uniform marker; a task finished without ever running a timer gets a 15 minute
block instead.

**Reopening deletes the event.** A task that is no longer done but still has a
✅ on the calendar is simply wrong, so the event id is stored on the task and
removed whenever it leaves Done — by reopen, by a status change, or by deletion.
That is what `remove(id:destination:)` on the scheduler is for.

**The calendar cannot veto a completion.** The write runs detached; a failure
sets `completionLogError` and surfaces in the follow-up card that is already on
screen, but the task is done either way. Tested.

`FollowUpRequest` was renamed `ScheduleRequest` — it now serves two different
kinds of write, and the old name had stopped being true.

There are two sound sets — `done/` on completion and `more/` when time is added
to a task — each a directory in the bundle with its own independently persisted
position, so playing one never advances the other. Sounds rotate round-robin
through every mp3 in the set,
discovered from the bundle at launch rather than listed in code — adding one is
a file copy. The position is persisted, so the rotation continues across
launches instead of restarting on the first sound every session. The index is
taken modulo the count rather than bounds-checked, so removing sounds cannot
leave a stored index pointing past the end. A system sound remains the fallback
when a set is empty.

Extending is announced through `onExtend`, which fires only when a timer is
actually running — pressing "+10 min" with nothing active is a no-op and makes
no sound.

## The black edge line, settled by measurement

Reported three times and guessed at twice — first the rim stroke
(`Color.primary` resolves to black in light appearance), then the `.resizable`
style mask. Neither was it.

The cause was the SwiftUI `.shadow(radius: 12, y: 4)` inside `GlassBackground`,
drawn within a window whose content had only 6pt of transparent padding. A
shadow drawn inside a view is clipped at the window bounds, so the gradient was
cut off part-way down its falloff — and a soft gradient ending in a hard step is
indistinguishable from a drawn line.

The fix is to let the window server draw the shadow instead: it renders outside
the window bounds and cannot be clipped. `GlassBackground` now carries no stroke
and no shadow, and the panel's `hasShadow` does the work, with
`invalidateShadow()` after every frame change so it tracks the rounded shape.

**How it was verified**, since the screen itself is not visible from the agent's
side: render the view offscreen into an `NSBitmapImageRep` via
`bitmapImageRepForCachingDisplay` / `cacheDisplay`, composite it over a known
background, and read a luminance scanline outward from the card edge. Before,
the light-mode top edge read 231 at y=0 and climbed to 244 — a shadow still
mid-gradient at the boundary. After, it reads a flat 254 until the card begins.
That is a measurement, not an opinion, and the same technique settles any future
"it looks wrong" report.

## Editing shortcuts needed a main menu

Copy and paste did not work *anywhere* in Floater — not the add field, notes,
the scratchpad, or the chat box. macOS dispatches the standard editing
shortcuts through the Edit menu, and an app with no main menu simply never
receives them. Being an accessory app makes this easy to miss, because the menu
bar is never shown; installing the menu changes nothing visually and fixes every
field at once.

**Cmd-C on a task without stealing Cmd-C from text fields.** A text field that
has focus consumes the keystroke first; only when none does it reach the window.
So `FloatingPanel` implements `copy(_:)` and copies the selected task there,
and overrides `responds(to:)` so the menu item disables itself when nothing can
handle it. No conditional logic about who has focus, no conflict.

Clicking a task selects it; opening its note selects it too, so Cmd-C always has
an obvious target. Deleting the selected task clears the selection rather than
leaving an id pointing at a task that no longer exists.

The add field takes several lines, and submitting creates one task per non-blank
line — pasting a list in and pressing Return creates the list.

Verified by inspecting the installed menu's key equivalents and selectors, and
confirming `NSTextView` responds to each. `undo:` is the exception: it is routed
through the undo manager rather than declared on `NSText`, so Cmd-Z is not proven
the way the others are.

## Addendum — the digest and the prompt generator

**The digest never asks the model to remember anything.** `Store.digest(days:)`
assembles the real figures — what was finished, when, under which project, how
long was focused, what is still open, blocked or overdue — and renders them as a
fact sheet. Claude is handed that sheet and told to phrase it, with an explicit
instruction to use nothing else. A write-up that invents a task or a number is
the obvious failure here, and the only reliable guard is to not let the model
supply the facts.

**Categories are what make the prompt generator work.** A category carries the
repo it maps to, so a task's category selects which `CLAUDE.md`, design systems,
git log and personal notes get read. Notes are scored by how many of the task's
words they mention, with a strong signal for the project name and repo folder;
the memory index is excluded because it mentions every project and so matches
everything.

Both run through `oneOff`, which never touches the chat conversation: a
generation must not be steered by, or pollute, the chat history, and it offers
no tools. Tested.

The brief is capped per document and overall, so one generation cannot balloon
into a large bill.

## Addendum — the game, and a resize bug worth recording

The scoring is a set of pure functions over dates and seconds — XP, levels,
streak, badges — so each rule is checked on its own rather than inferred from a
screenshot. Two judgements worth stating: a streak counts back from today *or
from yesterday*, so it is not declared broken at midnight before the day it
would actually break on; and the Slack status is assembled clause by clause and
stops before Slack's 100-character cut, rather than being truncated mid-word.

Slack is off until the user turns it on, and turning it off clears the status
Floater set rather than leaving a stale one behind.

**The status is a film line, chosen by the day.** Mood is read first from the
calendar (in a meeting, a packed day), then the timer, then the list (overdue,
blocked, goal met), and the last slot of the evening always winds down rather
than reporting that you are behind — nine at night is not the time to be told
that. Lines are short quotations and the pool is small and curated.

It changes on a schedule rather than on events: five slots a day at 9, 12, 15,
18 and 21, Sunday to Friday, and outside those hours Floater leaves whatever is
there alone instead of announcing an empty evening. One consequence worth
knowing: the mood is sampled once per slot, so a meeting that starts after the
slot fired is not reflected until the next one.

**It is still not a scoreboard.** It carries no task count, no level
and no goal progress — the only number it may ever show is the streak's day
count, and a test asserts exactly that across every state and every hour of the
day. It also has no parameter for the task title, so what the user is working on
— client names included — cannot reach the workspace even by accident. One joke
had to be reworded to keep the "no numbers" rule mechanically checkable; a rule
a test can enforce is worth more than one funny line.

Lines are chosen by day and hour, so the status has variety without Floater
writing to Slack on every tick. The weekly write-up is given
the same fact sheet as the digest, with the same instruction to invent nothing.

**The resize grip measured the drag in its own coordinate space.** The grip
moves as the window resizes, so every frame fed the next one a corrupted delta
and the panel jumped around. It now measures against `NSEvent.mouseLocation`,
anchored to the frame the drag started from — the only measurement that stays
valid while the thing being measured is moving. Verified by driving ten
simulated steps: each grows by exactly the amount dragged.

## Why the generated prompts kept asking for context

Two causes, both mine.

**Each note was reduced to one line.** The reader kept only the `description:`
from the front matter and discarded the body — which is where the why, the
how-to-apply and the traps live. The prompt was being built from headlines.
Notes now carry their substance, capped per note.

**The system prompt asked for it.** It said: "if the context is thin, say
plainly what it should read first to orient itself". That instruction produced
exactly the behaviour it was meant to guard against. It is now forbidden
outright: never delegate the research, never ask a question, never remark that
the context is limited.

With both fixed, the same task went from "start by reading DATASOURCES.md to
orient yourself" to naming the file, the data structure, the rule numbers, the
migration script and its applied date, the deployed bundle and the branch.

## Skills are files, not code

`Resources/Skills/*.md` ship in the bundle and are loaded at launch. Prompt
engineering applies to every generation; the taste guidance is added only when
the task's words say it touches a screen. Editing the markdown changes the
output without a code change, and a missing file degrades to the base rules
rather than failing.

## Chat was showing its own Markdown

Assistant messages arrive as Markdown, and SwiftUI's `Text` renders a plain
`String` literally — so `**hello**` arrived with its asterisks. Parsed as an
`AttributedString` now, inline-only so newlines survive.

## The ticker was burning 10% of a core doing nothing

The countdown ticks four times a second. It called the full refresh, which read
the whole database (five fetches), recomputed every statistic, wrote the active
run to disk, and republished a dozen values — all of it four times a second,
forever, whether anything had changed or not. Idle CPU sat between 7 and 12%.

Two separate causes, and fixing only the first is not enough:

1. **The hot path did cold-path work.** A countdown changing is not a reason to
   re-read the database. The tick now updates only the values the clock moves,
   and falls back to the full refresh solely when the timer's phase changes or
   it reaches zero.
2. **Every assignment to a `@Published` re-renders, changed or not.** Even after
   (1), three values were being republished four times a second with identical
   contents. Each is now assigned only when it actually differs, and the
   countdown is compared in whole seconds, since that is all that is displayed.
   When nothing is running there is no countdown at all, so the tick does
   nothing.

Idle CPU is now 0.0%. Tests pin both halves: a plain tick must not touch the
store, and an idle tick must publish nothing.

## A dead Slack token used to be retried forever

An `invalid_auth` was reported into a field nobody reads and then tried again
every five minutes for the life of the process. A token that has been revoked
will never start working, so the feature now switches itself off and drops the
dead token, while a transient error such as a rate limit changes nothing.

The credentials file is also read each time rather than cached: a cache meant a
credential cleared from outside the app carried on being used.

## Expanding the panel sometimes left it unable to type

The mode change animated the frame and then asked for key status. An animated
`setFrame` runs asynchronously, so the focus call was racing it: often the panel
became key, sometimes it did not, and when it did not the add field would not
take a keystroke. The panel's position drifted across toggles for the same
reason — a second change starting while the first was still animating.

Animating a panel between two fixed sizes buys very little, and it made the
sequence non-deterministic. The frame is now set instantly, which makes the
whole mode change synchronous.

Measured by driving the real window: four expand/collapse rounds plus a rapid
triple toggle. Before, two of five expansions failed to take focus and the
origin walked from x=3705 to x=4333. After, every expansion takes focus, every
collapse releases it, and the origin is identical in every round.

## The panel resized before its content changed

Expanding sometimes showed the pill's background stretched across the whole
expanded panel; collapsing sometimes drew the task list outside a pill-sized
window. Both are the same fault seen from either side.

A `@Published` sink runs *during* the change, before SwiftUI has rendered
anything. The controller resized the window in that sink, so for a moment the
frame was new and the content was old. The isolated check — flip the mode and
count the hosting view's descendants — showed propagation working fine (2
subviews to 59), which is what ruled out a binding problem and pointed at
ordering instead.

Mode changes are now delivered on the next runloop pass: SwiftUI switches the
view first, and the frame follows. Driving the real window through four rounds
plus a rapid triple toggle, size, keyboard focus and rendered content agree in
all ten samples.

Worth recording as a technique: rendering the panel's own SwiftUI into an
`NSBitmapImageRep` shows exactly what the layout does without needing the
screen, and it is what proved the expanded layout itself was never at fault.

## The digest writes release notes, not a diary

The first version produced a narrative paragraph about the week. What was
actually wanted was a changelog: themed sections, one line per change, each
written as what is now true for the reader rather than what was set out to be
done.

Two things had to change beyond the wording. The fact sheet now carries each
task's **note**, because the title says what was attempted and the note usually
says what changed — and the note is what a changelog line needs. And the style
moved into `Resources/Skills/changelog.md`, so the format is editable without a
code change, like the other skills.

Three rules earned their place by watching real output fail without them:

- **Never put everything under one heading.** The first run put twenty-seven
  bullets under a single "CRM" section. Sections are named after the part of the
  product the reader uses, never after the project.
- **Every line is something that is now true.** A finished task whose title
  names a problem was being written up as an outstanding problem.
- **A line that only restates its task title is worse than no line.** "Data
  cleanup: data cleanup has been completed" says nothing.

The quality depends heavily on tasks having notes. In the run used to develop
this, only two of thirty-four did.

## Clearing finished work used to erase it

"Clear done" deleted the finished tasks. Every statistic — XP, level, streak,
badges, the digest — is derived from the tasks themselves, so tidying the list
reset all of it to zero. The feature that was meant to be housekeeping was
destroying the record.

Finished tasks are now archived rather than deleted: hidden from the list,
still counted. The store keeps `allTasks` alongside the visible `tasks`, and
everything that measures reads the former. Deleting a single task is still a
real delete, which is the distinction that was missing.

**The already-lost work was recoverable.** `FocusSessionRecord` is a separate
model, so clearing never touched it: 58 sessions survived their tasks. Each
carries the title, the seconds focused and when it ended, which is enough to
rebuild the task as archived and completed. Restoring on the real database took
70 XP back to 728, and level 1 to level 5.

That recovery is a method on the model with tests, not a one-off script —
several sessions on one task collapse into one task, running it twice changes
nothing, and a task that still exists is left alone rather than duplicated.

## Deliberately not built

iCloud sync, subtasks, tags, projects, recurring tasks, a stats dashboard,
Pomodoro break cycles, global hotkeys. Chat does not stream, and the model is
not told about follow-ups that already exist. Follow-ups are one-way: Floater writes to
Calendar and Reminders and never reads them back, so an event you delete there
still shows on the task here.
