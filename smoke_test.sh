#!/bin/bash
# smoke_test.sh — Automated smoke test for YapYap after build
# Verifies the app launched correctly, UI is responsive, and no errors in logs.
set -euo pipefail

PASS=0
FAIL=0
LOG=/tmp/yapyap_log.txt

pass() { ((PASS++)); echo "  ✅ $1"; }
fail() { ((FAIL++)); echo "  ❌ $1"; }

echo "=== YapYap Smoke Test ==="
echo ""

# 1. Process check
echo "1. Process"
if pgrep -x YapYap > /dev/null; then
    pass "YapYap process running (PID $(pgrep -x YapYap))"
else
    fail "YapYap process not found"
fi

# 2. Menu bar item
echo "2. Menu Bar"
MENU_CHECK=$(osascript -e '
tell application "System Events"
    tell process "YapYap"
        if exists menu bar item 1 of menu bar 2 then
            return "found"
        else
            return "missing"
        end if
    end tell
end tell' 2>/dev/null || echo "error")

if [ "$MENU_CHECK" = "found" ]; then
    pass "Menu bar item present"
else
    fail "Menu bar item not found ($MENU_CHECK)"
fi

# 3. Settings window opens
echo "3. Settings Window"
osascript -e '
tell application "System Events"
    tell process "YapYap"
        -- Click menu bar to open popover
        click menu bar item 1 of menu bar 2
        delay 0.5
    end tell
end tell' 2>/dev/null || true

# Try opening settings via keyboard shortcut or menu
SETTINGS_OPEN=$(osascript -e '
tell application "System Events"
    tell process "YapYap"
        keystroke "," using command down
        delay 1
        set wins to count of windows
        return wins
    end tell
end tell' 2>/dev/null || echo "0")

if [ "$SETTINGS_OPEN" -gt 0 ] 2>/dev/null; then
    pass "Settings window opened ($SETTINGS_OPEN window(s))"
else
    # Try alternative: check if any window exists
    WIN_COUNT=$(osascript -e '
    tell application "System Events"
        tell process "YapYap"
            return count of windows
        end tell
    end tell' 2>/dev/null || echo "0")
    if [ "$WIN_COUNT" -gt 0 ] 2>/dev/null; then
        pass "Window present ($WIN_COUNT window(s))"
    else
        fail "No settings window detected"
    fi
fi

# 4. Log health checks
echo "4. Log Analysis"
if [ -f "$LOG" ]; then
    # Check for critical errors
    if grep -qE -i 'fatal|crash|SIGABRT|SIGSEGV|EXC_BAD' "$LOG" 2>/dev/null; then
        ERRORS=$(grep -cE -i 'fatal|crash|SIGABRT|SIGSEGV|EXC_BAD' "$LOG" 2>/dev/null)
        fail "$ERRORS fatal error(s) in log"
    else
        pass "No fatal errors in log"
    fi

    # Check hotkey registration
    if grep -q 'registerHotkeys.*called' "$LOG" 2>/dev/null; then
        pass "Hotkeys registered"
    else
        fail "Hotkey registration not found in log"
    fi

    # Check audio engine
    if grep -q 'Engine pre-warmed\|AudioCaptureManager.*Warm-up' "$LOG" 2>/dev/null; then
        pass "Audio engine initialized"
    else
        fail "Audio engine not initialized"
    fi

    # Check STT model loading
    if grep -q 'Loading STT\|STT.*loaded' "$LOG" 2>/dev/null; then
        pass "STT model loading initiated"
    else
        fail "STT model not loading"
    fi

    # Check for LLM model loading
    if grep -q 'Loading LLM\|LLM.*loaded\|TranscriptionExecutor.*Loading' "$LOG" 2>/dev/null; then
        pass "LLM model loading initiated"
    else
        # LLM may still be loading — check if STT is at least working
        echo "  ⚠️  LLM not yet loaded (may still be downloading)"
    fi
else
    fail "Log file not found at $LOG"
fi

# 5. Version check
echo "5. Version"
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData/YapYap-*/Build/Products/Debug/YapYap.app -maxdepth 0 2>/dev/null | head -1)
if [ -n "$APP_PATH" ]; then
    VERSION=$(defaults read "$APP_PATH/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "unknown")
    BUILD=$(defaults read "$APP_PATH/Contents/Info" CFBundleVersion 2>/dev/null || echo "unknown")
    if [ "$VERSION" = "0.2.0" ]; then
        pass "Version $VERSION (build $BUILD)"
    else
        fail "Expected version 0.2.0, got $VERSION"
    fi
else
    fail "App bundle not found"
fi

# Close settings window
osascript -e '
tell application "System Events"
    tell process "YapYap"
        if (count of windows) > 0 then
            keystroke "w" using command down
        end if
    end tell
end tell' 2>/dev/null || true

# Summary
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
