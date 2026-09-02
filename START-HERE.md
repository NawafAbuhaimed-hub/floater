# Floater — build it yourself

A task tracker that floats above every window on macOS, with focus timers,
statuses, notes, calendar logging, and a Claude-powered chat.

**Hand this whole folder to Claude Code and say "build and run this".**
Or do it yourself:

```bash
./run.sh          # builds and launches
swift test        # 136 tests
```

Floater has no Dock icon — it lives in the menu bar (timer glyph).

## What you need

- macOS 14 or later
- Xcode command line tools (`xcode-select --install`)

Nothing else. No package manager, no dependencies, no Xcode project — it is a
Swift Package that builds its own `.app` bundle.

## Why build instead of installing the DMG

A locally built app is not quarantined, so macOS opens it without the
"unidentified developer" song and dance. You also get to change it.

## Things you might want to change

| What | Where |
|---|---|
| Completion sounds | `Resources/Sounds/done/` — any mp3, filename order |
| "More time" sounds | `Resources/Sounds/more/` |
| Timer lengths (15/30/45) | `timerLengths` in `Sources/FloaterCore/AppModel.swift` |
| Status colours | `Theme.color(for:)` in `Sources/Floater/Views/Theme.swift` |
| Pill and panel sizes | `FloatingPanelController` |
| Bundle identifier | `Resources/Info.plist` |

The sounds included are placeholders — drop your own mp3s in and they join the
rotation automatically, no code change.

## Optional bits

- **Chat tab** needs your own Anthropic API key from console.anthropic.com.
  It is stored in your Keychain and sent only to Anthropic. Everything else
  works without it.
- **Calendar / Reminders** permissions are only requested if you use follow-ups
  or the completion log.

## Where things live

```
Sources/FloaterCore   Timer engine, SwiftData store, app model, Claude client
Sources/Floater       AppKit panels, SwiftUI views, menu bar, sounds
Tests/FloaterCoreTests  136 tests, no network and no real calendar writes
docs/superpowers/specs  The design document, including why things are the way
                        they are and what was deliberately left out
```

`README.md` has the full feature list. The design doc is worth a read before
changing anything — several decisions there look arbitrary and are not.
