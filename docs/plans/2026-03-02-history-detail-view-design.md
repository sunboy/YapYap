# History Detail View — Design

**Date:** 2026-03-02
**Scope:** `YapYap/UI/Settings/HistoryTab.swift` only

---

## Problem

History rows truncate `cleanedText` to 2 lines. Users cannot read longer transcriptions and cannot easily copy the text.

---

## Design

### Interaction

- Every history row is tappable. On hover, the row background shifts to `Color.ypCard2` (white 14% opacity) to signal interactivity.
- Clicking a row sets `@State var selectedItem: Transcription?` which triggers `.sheet(item: $selectedItem)`.

### Detail Sheet

A SwiftUI sheet anchored to the settings window. Contains:

1. **Header bar** — app emoji + app name (left), `×` close button (right)
2. **Metadata line** — timestamp (medium date + short time), word count, recording duration — in `ypText3` / `ypText4` muted style
3. **Copy button** — top-right of the text area, copies full `cleanedText` to `NSPasteboard.general`. Shows "Copied ✓" for 1.5 seconds then reverts.
4. **Text body** — `cleanedText` in a `ScrollView` with `.textSelection(.enabled)` so users can manually select portions. Font: 13pt regular, `ypText1` colour.
5. **Dismiss** — clicking outside the sheet or pressing Escape (default `.sheet` behaviour) + explicit `×` button.

### What is NOT shown

- `rawText` — users only want what was pasted (cleaned output).
- LLM/STT model metadata — not useful in the reading context.

---

## Files Changed

| File | Change |
|------|--------|
| `YapYap/UI/Settings/HistoryTab.swift` | Add `@State var selectedItem: Transcription?`; add hover state; wire `.sheet(item:)`; add `TranscriptionDetailSheet` struct |

No new files, no new data model changes, no other files touched.

---

## Acceptance Criteria

1. Tapping any history row opens the detail sheet.
2. Full `cleanedText` is visible and scrollable in the sheet.
3. Copy button copies the text and shows "Copied ✓" for 1.5s.
4. Text is selectable with mouse.
5. Sheet dismisses on click-outside or `×`.
6. Hover highlight appears on rows.
7. All 504 tests still pass (no logic changes).
