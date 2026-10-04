# Sounds

Two sets, each rotating independently:

- `done/` — plays when you finish a task
- `more/` — plays when you add time to a running task

Drop any `.mp3` into either folder and it joins that rotation, in filename
order. No code change, no rebuild of a list. Number the files (`1-…`, `2-…`) if
you care about the order.

The folders ship empty: the clips used during development are third-party sound
effects and are not redistributed here. With an empty folder the app falls back
to a macOS system sound, so nothing breaks.
