#!/bin/bash
# dev.sh — YapYap development helper
# Usage:
#   ./dev.sh build       — build, test, restart app, open accessibility settings
#   ./dev.sh restart     — restart app only (no build/test)
#   ./dev.sh logs        — tail live logs
#   ./dev.sh test        — run tests only

APP_BINARY="/Users/sandeep/Library/Developer/Xcode/DerivedData/YapYap-fgocbvsmqtadmncqpdsycxzkwxrc/Build/Products/Debug/YapYap.app/Contents/MacOS/YapYap"
LOG_FILE="/tmp/yapyap_log.txt"
BUNDLE_ID="dev.yapyap.app"

_kill() {
    if pgrep -x YapYap > /dev/null; then
        pkill -x YapYap
        sleep 1
        echo "✓ Killed existing YapYap"
    fi
}

_reset_accessibility() {
    tccutil reset Accessibility "$BUNDLE_ID"
    echo "✓ Accessibility grant reset"
}

_launch() {
    if [ ! -f "$APP_BINARY" ]; then
        echo "✗ Binary not found: $APP_BINARY"
        echo "  Run: make build"
        exit 1
    fi
    "$APP_BINARY" > "$LOG_FILE" 2>&1 &
    echo "✓ Launched YapYap (PID $!) — logs at $LOG_FILE"
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    echo "→ Toggle YapYap ON in System Settings → Privacy & Security → Accessibility"
}

case "${1:-build}" in
    build)
        echo "=== Building ==="
        make build || exit 1

        echo ""
        echo "=== Testing ==="
        make test || { echo "✗ Tests failed — fix before restarting"; exit 1; }

        echo ""
        echo "=== Restarting ==="
        _kill
        _reset_accessibility
        _launch
        ;;

    restart)
        _kill
        _reset_accessibility
        _launch
        ;;

    logs)
        echo "Tailing $LOG_FILE (Ctrl+C to stop)"
        tail -f "$LOG_FILE"
        ;;

    test)
        make test
        ;;

    *)
        echo "Usage: ./dev.sh [build|restart|logs|test]"
        exit 1
        ;;
esac
