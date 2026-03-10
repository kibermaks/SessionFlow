---
paths:
  - "SessionFlow/Views/**/*.swift"
  - "SessionFlow/ContentView.swift"
---

# SwiftUI UI Patterns

## Button hit areas
`.buttonStyle(.plain)` buttons only register clicks on visible content (text/icon), not the full frame. Always add `.contentShape(Rectangle())` inside the button label after `.frame()` / `.background()` to make the entire area clickable.

## Split button
The Schedule Sessions button is a split button (HStack with Button + Menu). Use fixed height `.frame(height: 44)` to prevent Menu from expanding vertically.
