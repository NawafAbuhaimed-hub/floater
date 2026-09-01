# Floater

A task tracker that floats above every app and window on macOS, with focus
timers and a confetti burst when you finish something.

## What it does

- **Always on top.** A small capsule that sits above every window, follows you
  across Spaces, and stays visible over fullscreen apps.
- **Never steals focus.** Click it, type in it, start a timer — the app you were
  working in keeps its cursor.
- **15 / 30 / 45 minute timers, attached to a task.** The pill shows what you're
  working on and how long is left.
- **Loud finish.** When time is up: a chime, the pill pulses, a macOS
  notification, and a full-screen "did you finish?" card with Done / +10 min /
  Stop. The full-screen part can be turned off from the menu bar.
- **Confetti on completion.** Ticking a task off bursts confetti across the
  screen and plays a chime.
- **Four statuses**, each colour-coded: Not started (gray), In progress (blue),
  Done (green), Blocked (red). Starting a timer marks a task In progress;
  blocking the running task stops its timer.
- **Notes.** A note per task, opened inline by clicking its title, plus a global
  scratchpad on the Notes tab.
- **Follow-ups.** Finishing a task offers a follow-up in **Calendar** or
  **Reminders** — Tomorrow / 3 days / Next week at 9am, or a date you pick. It
  appears beside the pill and fades after 8 seconds if you ignore it.
- **Chat.** Describe your work in plain language (English or Arabic) and Claude
  proposes changes — new tasks, statuses, timers, notes, follow-ups. Nothing is
  applied until you press **Apply**.
- **Resizable.** Drag the grip in the bottom-right corner. The pill and the
  expanded panel remember their own sizes.
- **Remembers everything.** Tasks, focus time per task, and session history are
  stored locally with SwiftData. A running timer survives sleep, quit, and
  relaunch.

## Build and run

```bash
./run.sh          # build, install nothing, just launch
./build.sh --install   # also copy to ~/Applications
swift test        # 104 tests
```

Floater has no Dock icon. It lives in the menu bar (timer glyph) — that is where
you hide the pill, toggle sound and the full-screen alert, and quit.

## Using it

| Action | How |
|---|---|
| Open the task list | Click the chevron on the pill |
| Add a task | Type in the field, press Return |
| Start a timer | Hover a task, click **15**, **30**, or **45** |
| Finish a task | Click the circle next to it, or ✓ on the pill |
| Move the pill | Drag it anywhere; it remembers where |
| Collapse | Chevron, or Escape |
| Change status | Click the status dot to cycle, right-click for the full list, or open the note and pick a chip |
| Add a note | Click the task title |
| Global scratchpad | **Notes** tab in the header |
| Resize | Drag the grip in the bottom-right corner |
| Schedule a follow-up | Finish a task, then pick a time in the prompt |
| Talk to it | **Chat** tab — "the lease is blocked on legal, start 45 min on the deck" |

## Calendar and Reminders access

The first follow-up you schedule triggers a macOS permission prompt.

**Floater writes to Apple's Calendar and Reminders, not to Google directly.**
Connect a Google account in System Settings → Internet Accounts with Calendars
enabled and its calendars appear here like any other — verified working, events
written to a Google calendar sync straight through. Reminders has no Google
equivalent (Google Tasks is not exposed through EventKit), so reminder lists
stay iCloud-only. Pick which calendar or list receives follow-ups from the menu
bar: **Follow-up calendar** / **Follow-up list** → *Load*, then choose. Leaving it
on *System default* uses whatever macOS is set to.

Calendar access is requested in full rather than write-only, because listing
your calendars for that picker needs read access.

Because Floater is ad-hoc signed, its code signature changes on every rebuild,
and macOS ties permission to that signature. Expect to be asked again after a
rebuild. It stays granted once you stop rebuilding.

## Chat

The Chat tab needs your own Anthropic API key. Paste it once; it is stored in
the macOS Keychain, never in a file or in UserDefaults, and is sent only to
`api.anthropic.com`. The model is `claude-haiku-4-5` — task extraction is an
easy job and it costs a fraction of a cent per message.

Every tool Claude can call is a **proposal**. It can create tasks, change
statuses, start timers, write notes, delete tasks, and schedule follow-ups, but
the change set is shown to you with Apply / Discard and nothing touches your
list until you approve it. The Keychain is not read until you open the tab.

Two things worth knowing:

- The transcript is stored locally and replayed to the API as plain text (tool
  calls are not persisted), and only the last 20 turns are sent.
- Because Floater is ad-hoc signed, its signature changes on every rebuild. The
  Keychain item is stored with an open ACL so macOS does not prompt for access
  after each build. On a shared machine you would want a real signing identity
  and a restricted ACL instead.

## Layout

```
Sources/FloaterCore   Timer engine, SwiftData store, app model, preferences,
                      Claude client and the chat proposal engine
Sources/Floater       AppKit panels, SwiftUI views, menu bar, sounds
Tests/FloaterCoreTests  104 tests over the engine, store, statuses, notes, app model
```

The countdown is deadline-based rather than tick-counting, which is what makes
it survive sleep and relaunch. `TimerEngine` takes an injected `Clock` so all of
that is tested deterministically rather than with real waiting.
