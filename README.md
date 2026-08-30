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
- **Remembers everything.** Tasks, focus time per task, and session history are
  stored locally with SwiftData. A running timer survives sleep, quit, and
  relaunch.

## Build and run

```bash
./run.sh          # build, install nothing, just launch
./build.sh --install   # also copy to ~/Applications
swift test        # 39 tests
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

## Layout

```
Sources/FloaterCore   Timer engine, SwiftData store, app model, preferences
Sources/Floater       AppKit panels, SwiftUI views, menu bar, sounds
Tests/FloaterCoreTests  39 tests over the engine, store, and app model
```

The countdown is deadline-based rather than tick-counting, which is what makes
it survive sleep and relaunch. `TimerEngine` takes an injected `Clock` so all of
that is tested deterministically rather than with real waiting.
