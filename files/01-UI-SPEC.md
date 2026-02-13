# YapYap — UI Specification

> Maps every screen element from the UX mockup to native implementation.
> Reference mockup: `yapyap-macos-ux.html`

---

## 1. Design Tokens

### Colors (Dark Mode — always dark, no light mode)

```swift
extension Color {
    // Backgrounds
    static let ypBg          = Color(hex: "1E1E24")       // Main background
    static let ypBg2         = Color(white: 1, opacity: 0.03) // Card background
    static let ypBg3         = Color(hex: "24212E")       // Popover background (with opacity: 0.97)
    static let ypBg4         = Color(hex: "18162C")       // Settings sidebar

    // Creature & Accent  
    static let ypLavender    = Color(hex: "C4B8E8")       // Primary — creature body, accent
    static let ypWarm        = Color(hex: "F4A261")       // Warm orange — recording state, CTA
    static let ypMint        = Color(hex: "7EC8A0")       // Mint green — toggles, success
    static let ypZzz         = Color(hex: "8B8FC7")       // Sleeping z's, idle indicators
    static let ypBlush       = Color(hex: "E8A0B4")       // Creature blush cheeks
    static let ypRed         = Color(hex: "E85D5D")       // Errors, before-cleanup text

    // Text
    static let ypText1       = Color(white: 1, opacity: 0.88) // Primary text
    static let ypText2       = Color(white: 1, opacity: 0.55) // Secondary text
    static let ypText3       = Color(white: 1, opacity: 0.30) // Tertiary/muted
    static let ypText4       = Color(white: 1, opacity: 0.12) // Disabled/ghost

    // Borders
    static let ypBorder      = Color(white: 1, opacity: 0.06) // Default border
    static let ypBorderLight = Color(white: 1, opacity: 0.04) // Subtle dividers
    static let ypBorderFocus = Color(hex: "C4B8E8", opacity: 0.3) // Focus ring
    
    // Semantic pills
    static let ypPillLavender = Color(hex: "C4B8E8", opacity: 0.15) // STT model pill bg
    static let ypPillWarm     = Color(hex: "F4A261", opacity: 0.12) // LLM model pill bg
    static let ypPillMint     = Color(hex: "7EC8A0", opacity: 0.10) // Success pill bg
}
```

### Typography

```swift
extension Font {
    // Primary — DM Sans (or SF Pro as system fallback)
    static let ypTitle    = Font.system(size: 28, weight: .bold)    // View titles
    static let ypHeading  = Font.system(size: 16, weight: .semibold) // Section headings
    static let ypBody     = Font.system(size: 13, weight: .regular)  // Body text
    static let ypCaption  = Font.system(size: 11, weight: .medium)   // Descriptions
    static let ypMicro    = Font.system(size: 10, weight: .semibold) // Tags, labels
    static let ypMono     = Font.system(size: 11, design: .monospaced) // Shortcuts, code
    
    // Handwritten accent — Caveat (loaded from bundle)
    static let ypHandwritten = Font.custom("Caveat", size: 14)      // Footer whimsy
}
```

### Animations

```swift
struct YPAnimation {
    // Creature breathing (idle)
    static let breathe = Animation.easeInOut(duration: 3.5).repeatForever(autoreverses: true)
    // Scale: 1.0 → 1.04 on Y axis, slight translateY(-0.5pt)
    
    // Head drift (idle) 
    static let headDrift = Animation.easeInOut(duration: 3.5).repeatForever(autoreverses: true)
    // Rotation: 0° → 3° → -1.5° → 0°
    
    // Floating z's
    static let zFloat = Animation.easeInOut(duration: 2.8).repeatForever(autoreverses: true)
    // Opacity: 0.2 → 0.75, translateY: 0 → -3pt
    
    // Recording pulse ring
    static let pulseRing = Animation.easeOut(duration: 1.5).repeatForever(autoreverses: false)
    // Scale: 1.0 → 1.3, opacity: 0.5 → 0. Two rings offset by 0.75s
    
    // Processing spinner
    static let spin = Animation.linear(duration: 0.8).repeatForever(autoreverses: false)
    // Rotation: 0° → 360°
    
    // Floating bar expand (recording start)
    static let barExpand = Animation.spring(response: 0.35, dampingFraction: 0.7)
    
    // Waveform bars
    // Driven by AVAudioEngine RMS → 5 bars with sine wave modulation
    // Height range: 4pt → 15pt, update at 30fps
}
```

---

## 2. Layer 1 — Menu Bar Icon (NSStatusItem)

### Implementation

```swift
class StatusBarController {
    private var statusItem: NSStatusItem!
    private var animationTimer: Timer?
    
    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        // 18×18pt icon (36×36 @2x)
        // Rendered as template image for dark/light menu bar compatibility
        // BUT: we use a custom colored view for the creature
        
        if let button = statusItem.button {
            // Custom view for animated creature
            let creatureView = MenuBarCreatureView(frame: NSRect(x: 0, y: 0, width: 22, height: 22))
            button.addSubview(creatureView)
            button.action = #selector(togglePopover)
        }
    }
}
```

### Creature States (18×18pt logical, 36×36 @2x)

**State 1: Sleeping (idle)**
- Closed eyes (curved lines, not circles)
- Subtle breathing animation: scaleY 1.0 → 1.04 over 3.5s
- Head drift: slight rotation ±3° over 3.5s
- Floating z's: two "z" characters drifting up-right with staggered opacity
- Opacity pulse: 0.85 → 1.0

**State 2: Recording (listening)**
- Open eyes with pupils (dark circles with white highlight dots)
- Blush cheeks visible (pink ellipses at ~40% opacity)
- Warm-colored pulse rings radiating outward (2 rings, 1.5s cycle, 0.75s offset)
- No breathing animation — creature is "alert"

**State 3: Processing (cleanup)**
- Open eyes looking slightly upward (pupils offset up)
- Lavender spinner ring around the icon (0.8s full rotation)
- Subtle "thinking" posture — slight head tilt

### Popover Trigger
- **Left click**: Toggle NSPopover
- **Right click**: Quick menu (Quit, Settings shortcut)

---

## 3. Layer 2 — Popover (NSPopover)

### Popover Configuration
```swift
let popover = NSPopover()
popover.contentSize = NSSize(width: 300, height: 0) // Height auto-sized
popover.behavior = .transient  // Dismiss on click outside
popover.animates = true
```

### Popover Layout (top to bottom)

**3.1 Header (56pt height)**
- Left: Creature avatar (32×32pt) — animated, matches current state
- Center: "YapYap" label (13pt semibold) + status line "Sleeping · ⌥Space to wake"
  - Status dot: 5×5pt circle, color matches state (ypZzz for idle, ypWarm for recording, ypLavender for processing)
- Right: Master toggle (36×20pt) — green when active, gray when off
  - When off: app completely idle, no hotkey listening
  - When on: app ready to record on hotkey press

**3.2 Last Transcription (if exists)**
- Label: "LAST TRANSCRIPTION" (9pt, uppercase, ypText3)
- Content card: 2-line clamp of most recent cleaned text
  - Background: ypBg2, border: ypBorderLight, rounded 6pt
  - Click to copy full text to clipboard (with brief checkmark feedback)

**3.3 Quick Stats (3-column grid)**
- Column 1: Transcription count today (number 16pt bold, "TODAY" 9pt label)
- Column 2: Estimated time saved (e.g. "12m")
- Column 3: Total words today

**3.4 Quick Settings (list rows)**
Each row: icon (12pt) + label + right detail (pill badge or chevron)

| Row | Icon | Label | Right Detail |
|-----|------|-------|-------------|
| STT Model | 🎙 | STT Model | Lavender pill: "Parakeet" › |
| Cleanup Model | ✨ | Cleanup Model | Warm pill: "Qwen 2.5" › |
| Language | 🌐 | Language | "English" › |
| divider | — | — | — |
| Auto-paste | 📋 | Paste to clipboard | Mini toggle (28×16pt) |

- Clicking a model row opens a submenu (or in-place picker) to switch models
- Model pills: Lavender background for STT, Warm/Orange for LLM

**3.5 Footer**
- "Settings…" row with ⌘, shortcut in mono font
- "Quit YapYap" row with ⌘Q shortcut, muted text color

---

## 4. Layer 3 — Settings Window (NSWindow)

### Window Configuration
```swift
let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 780, height: 540),
    styleMask: [.titled, .closable, .miniaturizable],
    backing: .buffered,
    defer: false
)
window.titlebarAppearsTransparent = true
window.isMovableByWindowBackground = true
window.center()
```

### Layout: Sidebar (200pt) + Content Area (580pt)

**Sidebar:**
- Traffic lights (close/minimize/zoom) in titlebar area
- Brand: Creature (28×28) + "yapyap" + "v0.1.0" version
- Navigation sections:
  - **Configuration**: Writing Style, Models, Hotkeys, General
  - **Insights**: Analytics
  - **App**: About
- Selected item: ypLavender background pill (ypPillLavender), bold text
- Footer: Handwritten text in Caveat font "~ the little one is listening ~" (ypText4)

### Tab: Writing Style

| Element | Type | Details |
|---------|------|---------|
| Title | Heading | "How should YapYap write for you?" |
| Subtitle | Caption | "Configure how your speech gets cleaned up and formatted." |
| Writing Language | Select dropdown | English (US), English (UK), Spanish, French, German, Hindi, Japanese |
| Formality | Select dropdown | Casual, Neutral, Formal |
| Custom Style Prompt | Textarea | Placeholder: "e.g. Concise, direct, no fluff..." |
| Cleanup Level | Select dropdown | Light / Medium / Heavy |
| Preview | Card | Shows before (red strikethrough) → after (green) example |

### Tab: Models

**STT Models section:**
- 2×2 grid of model cards
- Each card: Model name (13pt bold), description (11pt), size badge (10pt mono)
- Selected card: ypLavender border + checkmark icon
- Cards: Whisper Large v3 Turbo, Whisper Medium, Whisper Small, Parakeet TDT v3

**LLM Models section:**
- Same 2×2 grid layout
- Cards: Qwen 2.5 1.5B, Qwen 2.5 3B, Llama 3.2 1B, Llama 3.2 3B, Gemma 2 2B

**Model management actions (per card):**
- Non-active downloaded models show a "Delete" button (trash icon, 11pt, ypText3)
- Tap delete → confirmation alert: "Delete {model name}? ({size}MB freed. You can re-download anytime.)"
- Active model card shows "In Use" badge — cannot delete while selected
- Deleted model card reverts to "Download" state (arrow-down icon) for on-demand re-download
- Not-yet-downloaded models show download size + "Download" button

**Bottom toggles:**
- Auto-download models (toggle)
- GPU acceleration (toggle)

### Tab: Hotkeys

| Shortcut | Default | Description |
|----------|---------|-------------|
| Push-to-Talk (hold) | ⌥ + Space | Hold to record, release to transcribe |
| Hands-Free Mode (toggle) | ⌥ + ⇧ + Space | Press once to start, again to stop |
| Cancel Recording | Esc | Abort without pasting |

Display using KeyboardShortcuts recorder view.

**Toggles:**
- Double-tap activation (⌥ double-tap for hands-free)
- Sound feedback (subtle chime on start/stop)
- Haptic feedback (trackpad vibration, MacBook only)

### Tab: General

Toggle rows (same pattern as mockup):
- Launch at login
- Show floating bar
- Auto-paste after transcription
- Copy to clipboard
- Notification on complete
- **Remove filler words** (default: ON) — "Removes um, uh, like, you know from output"

Dropdowns:
- Microphone selection (from AVAudioSession available inputs)
- Floating bar position: Bottom center / Bottom left / Bottom right / Top center
- Transcription history: Last 50 / 100 / 500 / Keep all / Don't save

**Audio Quality section** (with subtle divider):
- **Environment Mode**: segmented control `[Auto] [Quiet] [Noisy]` (default: Auto)
  - Auto: Monitors ambient RMS and switches VAD presets dynamically
  - Quiet: Low VAD threshold (0.25) — catches quiet/whispered speech
  - Noisy: High VAD threshold (0.5) — aggressive noise filtering for cafés/streets
  - Subtitle under control: "Adjusts noise filtering based on your environment" (ypText3, 11pt)
- **Cleanup Level**: segmented control `[Minimal] [Standard] [Aggressive]` (default: Standard)
  - Minimal: Fix hesitations only
  - Standard: Remove fillers + self-corrections (matches WisprFlow)
  - Aggressive: Full prose rewrite
  - Subtitle: "How much the AI cleans up your speech" (ypText3, 11pt)

### Tab: Style ✨ (NEW)

> Controls how YapYap formats text differently depending on which app you're using.
> WisprFlow calls this "Personalized Style" — we match it with 8 app categories.

**Layout:** Vertical list of app categories, each with a style selector.

Each row:
```
[App Category Icon]  Personal Messaging         [Very Casual ▾]
                     iMessage, WhatsApp, Telegram, Signal
```

| App Category | Icon | Default Style | Available Styles |
|-------------|------|---------------|-----------------|
| Personal Messaging | 💬 | Casual | Very Casual, Casual, Excited, Formal |
| Work Messaging | 💼 | Casual | Casual, Excited, Formal |
| Email | ✉️ | Formal | Casual, Excited, Formal |
| Code Editor | 🖥️ | Formal | Casual, Formal |
| Documents | 📄 | Formal | Casual, Formal |
| AI Chat | 🤖 | Casual | Casual, Formal |
| Browser | 🌐 | Casual | Casual, Excited, Formal |
| Other | ⚙️ | Casual | Casual, Formal |

**Style preview:** On hover/select, show a subtle example of how text would be formatted:
- Very Casual: `"hey yeah that sounds good to me"`
- Casual: `"Hey, yeah that sounds good to me"`
- Excited: `"Hey, yeah that sounds good to me!"`
- Formal: `"Hey, that sounds good to me."`

**IDE section** (with divider, only shows if Code Editor apps detected):
- **Variable recognition** (toggle, default: ON) — "Wrap camelCase and snake_case in backticks"
- **File tagging in chat** (toggle, default: ON) — "Say 'at main.py' → types @main.py in Cursor/Windsurf"
- Subtitle: "These features work in Cursor, Windsurf, VS Code, and Xcode"

**Bottom section:**
- **App overrides** (disclosure arrow → sub-panel)
  - Shows detected running apps with their auto-classified category
  - User can drag apps to different categories
  - Shows: `[Slack icon] Slack — Work Messaging [Change ▾]`

### Tab: Hotkeys (updated)

| Shortcut | Default | Description |
|----------|---------|-------------|
| Push-to-Talk (hold) | ⌥ + Space | Hold to record, release to transcribe |
| Hands-Free Mode (toggle) | ⌥ + ⇧ + Space | Press once to start, again to stop |
| **Command Mode** | ⌥ + ⌘ + Space | Highlight text first, then speak a command to rewrite |
| Cancel Recording | Esc | Abort without pasting |

Display using KeyboardShortcuts recorder view.

**Command Mode section** (with subtle divider):
- Subtitle: "Highlight text, press hotkey, speak a command. Examples: 'make this more professional', 'turn into bullet points', 'summarize this'"
- Sound feedback uses a different chime (ascending tone vs descending for dictation)
- Floating bar shows 🎯 icon during Command Mode (vs 🎙 for dictation)

**Toggles:**
- Double-tap activation (⌥ double-tap for hands-free)
- Sound feedback (subtle chime on start/stop)
- Haptic feedback (trackpad vibration, MacBook only)

**Stats cards (3-column grid):**
- Total transcriptions (ypLavender accent)
- Total words (ypWarm accent)
- Time saved estimate (ypMint accent)

**Bar chart: Transcriptions This Week**
- 7 bars (Mon–Sun), heights proportional to daily count
- ypLavender bars, 60% opacity
- Current day at full opacity, future days at 30%

**Privacy note**: "All data stays on your Mac. Always." (ypText3)

### Tab: About

Centered layout:
- Large creature (72×72pt) with open eyes and smile
- "yapyap" (20pt bold)
- "Version 0.1.0 (Build 42)" (12pt)
- "you yap. it writes." in Caveat font (16pt, ypZzz color)
- Description paragraph
- Button row: GitHub | Website | License
- Footer: "MIT Licensed · Made with 💜 and too much coffee"

---

## 5. Layer 4 — Floating Bar (NSPanel)

### Panel Configuration
```swift
class FloatingBarPanel: NSPanel {
    override init(
        contentRect: NSRect,
        styleMask: NSWindow.StyleMask,
        backing: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: backing,
            defer: flag
        )
        
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isMovableByWindowBackground = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.hidesOnDeactivate = false  // Stay visible when app not focused
    }
}
```

### Floating Bar States

**Resting (idle — optional, shown when "Show floating bar" is enabled)**
- Pill shape: ~48pt circle containing sleeping creature
- Background: rgba(20, 18, 28, 0.92) with 1px border
- Creature: sleeping state with breathing animation
- Position: Bottom center of screen (or user-configured)

**Active (recording)**
- Pill expands horizontally with spring animation (response: 0.35, dampingFraction: 0.7)
- Creature switches to recording state (open eyes, blush)
- Waveform bars appear to the right of creature
  - 5 bars, 2.5pt wide, ypWarm color
  - Height driven by mic RMS: 4pt → 15pt
  - Sine wave modulation: `height = 4 + abs(sin(t * 3.5 + i * 0.9)) * 11`
- Border color shifts to rgba(244, 162, 97, 0.12)
- Subtle warm glow shadow

**Processing (cleanup in progress)**
- Pill stays expanded
- Creature switches to processing state (spinner)
- Waveform bars freeze and fade
- Brief lavender shimmer effect

**Dismissed (after paste completes)**
- Pill contracts back to resting size with spring animation
- Creature returns to sleeping state
- If "Show floating bar" is off, panel hides completely

---

## 6. Interaction Flows

### Flow 1: Push-to-Talk (Primary)

```
User holds ⌥+Space
  → Creature wakes: sleeping → recording
  → Floating bar: resting → active (spring expand)
  → Audio capture starts (AVAudioEngine)
  → Waveform bars animate with mic RMS
  → Sound feedback: subtle "start" chime
  → Haptic: trackpad tap

User releases ⌥+Space
  → Audio capture stops
  → Creature: recording → processing (spinner)
  → Waveform bars freeze
  → Sound feedback: subtle "stop" chime
  → Pipeline: Audio buffer → STT engine → raw text
  → Pipeline: Raw text → LLM cleanup → cleaned text
  → Pipeline: Cleaned text → paste into active app
  → Creature: processing → sleeping
  → Floating bar: active → resting (spring contract)
  → History entry saved to SwiftData
  → Stats updated
```

### Flow 2: Hands-Free Mode

```
User presses ⌥+⇧+Space
  → Same as Push-to-Talk start
  → But recording continues until:
    a) User presses ⌥+⇧+Space again, OR
    b) Silence detected for configured duration (default 1.5s)
  → Then same stop/process/paste flow
```

### Flow 3: Cancel

```
User presses Esc during recording
  → Audio capture stops immediately
  → Audio buffer discarded (not transcribed)
  → Creature: recording → sleeping
  → Floating bar: active → resting
  → No paste, no history entry
```

---

## 7. First Launch / Onboarding

On first launch (no settings exist):

1. **Welcome screen** (centered window)
   - Large creature with open eyes
   - "Hey! I'm your new writing buddy."
   - "I live in your menu bar and turn your voice into clean, formatted text."

2. **Permissions**
   - Microphone: "I need to hear you!" → System dialog
   - Accessibility: "I need to paste for you!" → System Preferences link

3. **Model Selection**
   - "Pick your transcription engine:" → Card grid (default: Parakeet highlighted)
   - "Pick your cleanup brain:" → Card grid (default: Qwen 1.5B highlighted)
   - Download progress bars

4. **Hotkey Setup**
   - Show default ⌥+Space, allow customization
   - Quick test: "Try holding your hotkey and saying something!"
   - Show before/after cleanup preview

5. **Done**
   - "I'll be sleeping in your menu bar. Wake me anytime. 💜"
   - App minimizes to menu bar
