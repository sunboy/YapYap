# History Detail View Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make every history row tappable to open a sheet showing the full cleaned transcription text with a one-click copy button.

**Architecture:** All changes are confined to `HistoryTab.swift`. A new `TranscriptionDetailSheet` SwiftUI struct is added at the bottom of the file. The row view gains a hover state and an `.onTapGesture` that sets `@State var selectedItem: Transcription?`, which drives `.sheet(item:)` on the list container. No data model changes, no new files.

**Tech Stack:** SwiftUI (sheet, ScrollView, textSelection), NSPasteboard (copy), existing DesignTokens color palette.

---

### Task 1: Add selectedItem + hover state + row tap + sheet binding

**Files:**
- Modify: `YapYap/UI/Settings/HistoryTab.swift`

This task wires up the sheet trigger. No sheet UI yet — just the state and the `.sheet(item:)` stub that shows a placeholder.

**Step 1: Add state variables to `HistoryTab`**

In `HistoryTab`, after the existing `@State` declarations (around line 7), add:

```swift
@State private var selectedItem: Transcription? = nil
@State private var hoveredItem: UUID? = nil
```

**Step 2: Add `.sheet(item:)` to the list container**

`timelineList` returns a `VStack`. Wrap its return value with `.sheet(item: $selectedItem)`:

```swift
private var timelineList: some View {
    let grouped = groupedByDate(filteredTranscriptions)
    return VStack(alignment: .leading, spacing: 16) {
        // ... existing ForEach content unchanged ...
    }
    .sheet(item: $selectedItem) { item in
        TranscriptionDetailSheet(item: item)
    }
}
```

**Step 3: Make `transcriptionRow` tappable with hover**

Replace the `transcriptionRow` function's return body. The existing layout stays identical — just add `.background`, `.contentShape`, `.onHover`, and `.onTapGesture`:

```swift
private func transcriptionRow(_ item: Transcription) -> some View {
    HStack(alignment: .top, spacing: 10) {
        // App badge
        VStack(spacing: 2) {
            Text(appEmoji(for: item.sourceApp))
                .font(.system(size: 14))
            Text(timeFormatter.string(from: item.timestamp))
                .font(.system(size: 9))
                .foregroundColor(.ypText4)
        }
        .frame(width: 44)

        // Content
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(item.sourceApp ?? "Unknown")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.ypText1)

                Text("\(item.wordCount) words")
                    .font(.system(size: 10))
                    .foregroundColor(.ypText4)

                if item.durationSeconds > 0 {
                    Text(formatDuration(item.durationSeconds))
                        .font(.system(size: 10))
                        .foregroundColor(.ypText4)
                }
            }

            Text(item.cleanedText)
                .font(.system(size: 11))
                .foregroundColor(.ypText2)
                .lineLimit(2)
        }

        Spacer()
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(hoveredItem == item.id ? Color.ypCard2 : Color.clear)
    .contentShape(Rectangle())
    .onHover { hovering in hoveredItem = hovering ? item.id : nil }
    .onTapGesture { selectedItem = item }
}
```

**Step 4: Add placeholder `TranscriptionDetailSheet` struct**

At the bottom of `HistoryTab.swift`, after the closing `}` of `HistoryTab`, add:

```swift
struct TranscriptionDetailSheet: View {
    let item: Transcription
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Text("Detail: \(item.cleanedText.prefix(40))...")
            .padding()
            .frame(width: 500, height: 300)
    }
}
```

**Step 5: Build and confirm it compiles**

```bash
make build 2>&1 | grep -E "error:|warning:|BUILD"
```

Expected: `BUILD SUCCEEDED` with no errors.

**Step 6: Commit**

```bash
git add YapYap/UI/Settings/HistoryTab.swift
git commit -m "feat: wire history row tap to sheet (placeholder UI)"
```

---

### Task 2: Build the real TranscriptionDetailSheet UI

**Files:**
- Modify: `YapYap/UI/Settings/HistoryTab.swift` — replace the placeholder `TranscriptionDetailSheet` body

**Step 1: Add `@State var copied` to `TranscriptionDetailSheet`**

Replace the existing placeholder struct with:

```swift
struct TranscriptionDetailSheet: View {
    let item: Transcription
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    private let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        ZStack {
            Color(hex: "262140").ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack(alignment: .center) {
                    HStack(spacing: 8) {
                        Text(appEmoji(for: item.sourceApp))
                            .font(.system(size: 18))
                        Text(item.sourceApp ?? "Unknown")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(.ypText1)
                    }

                    Spacer()

                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.ypText3)
                            .frame(width: 28, height: 28)
                            .background(Color.ypCard)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 12)

                // Metadata
                HStack(spacing: 12) {
                    Text(timestampFormatter.string(from: item.timestamp))
                    if item.wordCount > 0 {
                        Text("·")
                        Text("\(item.wordCount) words")
                    }
                    if item.durationSeconds > 0 {
                        Text("·")
                        Text(formatDuration(item.durationSeconds))
                    }
                }
                .font(.system(size: 11))
                .foregroundColor(.ypText4)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)

                Divider()
                    .background(Color.ypBorderLight)

                // Text area with copy button
                ZStack(alignment: .topTrailing) {
                    ScrollView {
                        Text(item.cleanedText)
                            .font(.system(size: 13))
                            .foregroundColor(.ypText1)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(24)
                    }

                    // Copy button
                    Button(action: copyText) {
                        HStack(spacing: 4) {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 10, weight: .medium))
                            Text(copied ? "Copied" : "Copy")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(copied ? .ypMint : .ypText2)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.ypCard)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(copied ? Color.ypMint.opacity(0.5) : Color.ypBorderLight, lineWidth: 1)
                        )
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .padding(16)
                    .animation(.easeInOut(duration: 0.15), value: copied)
                }
            }
        }
        .frame(width: 560, height: 400)
    }

    private func copyText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.cleanedText, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            copied = false
        }
    }

    private func appEmoji(for appName: String?) -> String {
        guard let name = appName?.lowercased() else { return "⚙️" }
        if name.contains("message") || name.contains("whatsapp") || name.contains("telegram") || name.contains("signal") {
            return "💬"
        } else if name.contains("slack") || name.contains("teams") || name.contains("discord") {
            return "💼"
        } else if name.contains("mail") || name.contains("gmail") || name.contains("outlook") {
            return "✉️"
        } else if name.contains("xcode") || name.contains("code") || name.contains("cursor") || name.contains("windsurf") || name.contains("vim") {
            return "🖥️"
        } else if name.contains("safari") || name.contains("chrome") || name.contains("firefox") || name.contains("arc") {
            return "🌐"
        } else if name.contains("notion") || name.contains("obsidian") || name.contains("notes") || name.contains("pages") {
            return "📄"
        } else if name.contains("chatgpt") || name.contains("claude") || name.contains("perplexity") {
            return "🤖"
        }
        return "⚙️"
    }

    private func formatDuration(_ seconds: Double) -> String {
        let s = Int(seconds)
        if s >= 60 { return "\(s / 60)m \(s % 60)s" }
        return "\(s)s"
    }
}
```

**Step 2: Build and verify**

```bash
make build 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`

**Step 3: Run tests**

```bash
make test 2>&1 | tail -5
```

Expected: `Executed 504 tests, with 0 failures`

**Step 4: Commit**

```bash
git add YapYap/UI/Settings/HistoryTab.swift
git commit -m "feat: add full transcription detail sheet with copy button"
```

---

### Task 3: Manual smoke test + final push

**Step 1: Launch the app**

```bash
./dev.sh build
```

**Step 2: Smoke test**
1. Settings → Activity tab → scroll to a history item
2. Hover over a row — confirm subtle highlight appears
3. Click any row — confirm sheet opens with full text
4. Read the text — confirm it is not truncated
5. Click Copy — confirm button shows "Copied ✓" for ~1.5s then reverts
6. Paste somewhere — confirm the full text was copied
7. Click × — confirm sheet dismisses
8. Click outside sheet — confirm sheet dismisses

**Step 3: If all good, push**

```bash
git push origin main
```
