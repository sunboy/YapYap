# YapYap Manual Testing Checklist

**Quick reference for when you return from your errand**

Run this checklist after building the app to verify everything works before release.

## Pre-Test Setup

```bash
# Build the app
cd /Users/sandeep/Projects/yapyap/YapYap
make clean
make generate
make build

# Run unit tests first (should all pass)
make test
# Expected: 147 tests, 0 failures

# Launch the app
make run
```

## Phase 1: First Launch & Onboarding

- [ ] **App launches without crash**
- [ ] **Onboarding window appears** (520x580px)
- [ ] **Microphone permission requested**
  - Grant permission in System Settings
  - Verify checkmark appears in onboarding
- [ ] **Accessibility permission requested**
  - Grant permission in System Settings
  - Verify checkmark appears in onboarding
- [ ] **Model selection screen shows**
  - Default STT selected (Parakeet or Whisper Small)
  - Default LLM selected (Qwen 1.5B)
- [ ] **Download progress works** (if downloading models)
- [ ] **Hotkey test works** (hold Option+Space, speak, release)
- [ ] **Onboarding completion** → app minimizes to menu bar

## Phase 2: Menu Bar & Popover

- [ ] **Menu bar icon visible** (lavender creature in top-right)
- [ ] **Creature is sleeping** (breathing animation, floating z's)
- [ ] **Left-click opens popover** (300px wide)
- [ ] **Popover shows**:
  - Creature avatar (32x32, animated)
  - "YapYap" title + status "Sleeping · ⌥Space to wake"
  - Master toggle (OFF by default?)
  - Stats: 0 today, 0m saved, 0 words
  - STT model pill: "Whisper" or "Parakeet"
  - LLM model pill: "Qwen 2.5"
  - Settings button
  - Quit button

## Phase 3: Basic Recording Test

**Test in TextEdit**:
1. Open TextEdit (new document)
2. Click in text area
3. Hold **Option+Space**
4. Say: "Hello, this is a test of the YapYap voice to text system"
5. Release **Option+Space**

**Expected**:
- [ ] Floating bar appears (bottom center)
- [ ] Floating bar expands with spring animation
- [ ] Creature changes to recording state (open eyes, blush, pulse rings)
- [ ] Waveform bars animate (5 bars, orange color)
- [ ] On release: creature shows spinner (processing)
- [ ] After 1-3 seconds: text appears in TextEdit
- [ ] Text is cleaned: "Hello, this is a test of the YapYap voice-to-text system."
- [ ] Floating bar contracts back to resting size
- [ ] Creature returns to sleeping state

**If it fails**:
- Check Console.app for error logs (filter: "YapYap")
- Verify microphone permission granted
- Verify model is downloaded (Settings → Models)
- Try speaking louder

## Phase 4: Filler Word Removal

**Test cleanup works**:
1. Hold Option+Space
2. Say: "Um, so like, I think we should basically, you know, meet on Tuesday"
3. Release

**Expected**:
- [ ] Text appears: "I think we should meet on Tuesday."
- [ ] All fillers removed: "um", "so", "like", "basically", "you know"
- [ ] Proper capitalization and punctuation

## Phase 5: Context-Aware Formatting

### Test 1: Personal Messaging (iMessage)
1. Open Messages.app
2. Click in compose field
3. Record: "hey yeah that sounds good to me let me know when you are free"

**Expected**:
- [ ] Casual formatting: "Hey, yeah that sounds good to me. Let me know when you're free."
- [ ] OR if Very Casual selected: "hey yeah that sounds good to me, let me know when you're free"

### Test 2: Email (Mail)
1. Open Mail.app
2. Click in compose field
3. Record: "Hi John thanks for the report can you send me the updated version by Friday thanks"

**Expected**:
- [ ] Formal formatting with proper structure
- [ ] Sentence breaks: "Hi John, thanks for the report. Can you send me the updated version by Friday? Thanks."

### Test 3: Code Editor (VS Code)
1. Open VS Code (or any code editor)
2. Record: "Create a function called get user by ID that takes a user ID parameter"

**Expected**:
- [ ] Technical terms in backticks: "Create a function called `getUserById` that takes a `userId` parameter"
- [ ] CamelCase detected and wrapped

## Phase 6: Settings Validation

**Open Settings** (Click Settings in popover OR press Cmd+,)

### Writing Style Tab
- [ ] Tab loads
- [ ] Language dropdown shows "English (US)"
- [ ] Formality dropdown shows "Neutral"
- [ ] Custom style prompt textarea empty
- [ ] Cleanup level shows "Medium"

### Models Tab
- [ ] STT models grid shows (2x2 or 2x3)
- [ ] Selected STT model has lavender border + checkmark
- [ ] LLM models grid shows
- [ ] Selected LLM model has lavender border + checkmark
- [ ] "In Use" badge on active model
- [ ] Download button on non-downloaded models
- [ ] Delete button on downloaded non-active models

### Hotkeys Tab
- [ ] Push-to-Talk shows: ⌥Space
- [ ] Hands-Free shows: ⌥⇧Space
- [ ] Command Mode shows: ⌥⌘Space
- [ ] Cancel shows: Esc
- [ ] Sound feedback toggle works
- [ ] Haptic feedback toggle works

### General Tab
- [ ] Launch at login toggle
- [ ] Show floating bar toggle
- [ ] Auto-paste toggle
- [ ] Copy to clipboard toggle
- [ ] Notification toggle
- [ ] Remove filler words toggle
- [ ] Microphone dropdown lists devices
- [ ] Floating bar position dropdown
- [ ] History limit dropdown

### Style Tab
- [ ] Shows 8 app categories
- [ ] Each has style dropdown
- [ ] Defaults match spec

### Analytics Tab
- [ ] Shows total transcriptions (should be 1+ after tests)
- [ ] Shows total words
- [ ] Shows time saved
- [ ] Bar chart shows today's count

### About Tab
- [ ] Large creature (72x72) with smile
- [ ] "yapyap" title
- [ ] Version "v0.1.0"
- [ ] "you yap. it writes." in handwritten font
- [ ] GitHub/Website/License buttons
- [ ] Footer text

## Phase 7: Hands-Free Mode

1. Press **Option+Shift+Space** (toggle hands-free)
2. Say: "This is hands free mode testing one two three"
3. Wait 2 seconds of silence
4. Should auto-stop

**Expected**:
- [ ] Recording starts without holding key
- [ ] Continues until silence detected
- [ ] Auto-stops after ~2s silence
- [ ] Text appears

**OR press Option+Shift+Space again to manually stop**

## Phase 8: Command Mode (Optional)

1. Type in TextEdit: "the quick brown fox"
2. Select the text
3. Press **Option+Command+Space**
4. Say: "Make this uppercase"
5. Release

**Expected**:
- [ ] Text transforms: "THE QUICK BROWN FOX"

## Phase 9: Floating Bar Behavior

- [ ] **Resting state** (if "Show floating bar" enabled):
  - Small circle ~48pt, sleeping creature visible
  - Bottom center (or configured position)
  - Semi-transparent background
- [ ] **Recording state**:
  - Expands horizontally with spring animation
  - Waveform bars appear and animate
  - Border turns warm orange
- [ ] **Processing state**:
  - Stays expanded
  - Waveform freezes
  - Spinner appears
- [ ] **Never steals focus** (type while bar is visible, should keep typing)

## Phase 10: Performance Check

Record a 5-second phrase and time it:

1. Start timer
2. Hold Option+Space
3. Say: "This is a five second performance test to measure the total latency"
4. Release
5. Stop timer when text appears

**Target**: <3 seconds total (capture → paste)
**Acceptable**: <5 seconds

**Your result**: _____ seconds

## Critical Issues to Report

If any of these fail, report immediately:

❌ App crashes on launch
❌ No microphone audio captured
❌ No text appears after recording
❌ Text appears but is gibberish
❌ Settings window doesn't open
❌ Floating bar steals focus (can't type while visible)
❌ Memory usage >3GB with small models
❌ Fan noise during Parakeet usage (should be silent)

## Success Criteria

✅ All checkboxes above checked
✅ No crashes during 15+ minute test session
✅ Transcription accuracy >70% for clear speech
✅ Filler words removed correctly
✅ Context-aware formatting works in 3+ apps
✅ Settings persist after quit/relaunch

## After Testing

If all tests pass:
- [ ] Merge `feature/validation` → `main`
- [ ] Tag version `v0.1.0-rc1`
- [ ] Build release DMG: `make dmg`
- [ ] Test DMG installation on fresh Mac
- [ ] Create GitHub release

---

**Estimated testing time**: 15-20 minutes
**Last updated**: 2026-02-13
