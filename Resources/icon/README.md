# Icon

`make-icon.swift` draws the icon so it can be changed in code rather than kept
as an opaque binary.

```bash
swiftc -O make-icon.swift -o /tmp/make-icon

# macOS app icon — rounded corners, transparent outside them
/tmp/make-icon icon-1024.png

# For Slack, Notion, GitHub and anything else that applies its OWN rounding —
# full bleed, no transparency. A transparent corner composites as white there.
/tmp/make-icon icon-slack-1024.png --square
```

It renders into an explicitly sized `NSBitmapImageRep` rather than using
`NSImage.lockFocus`, which adopts the display's backing scale and silently
doubles the output on a Retina Mac. Slack rejects anything over 2000px.

Rebuild the `.icns` after changing `icon-1024.png`:

```bash
ICONSET=/tmp/Floater.iconset; rm -rf "$ICONSET"; mkdir -p "$ICONSET"
for spec in "16 16x16" "32 16x16@2x" "32 32x32" "64 32x32@2x" "128 128x128" \
            "256 128x128@2x" "256 256x256" "512 256x256@2x" "512 512x512" "1024 512x512@2x"; do
  px=${spec% *}; name=${spec#* }
  sips -z "$px" "$px" icon-1024.png --out "$ICONSET/icon_$name.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o Floater.icns
```
