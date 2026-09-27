#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PID_FILE="$PROJECT_DIR/build/slides-server.pid"

if [[ ! -f "$PID_FILE" ]]; then
    echo "Slide server is not running (PID file not found)."
    exit 0
fi

SERVER_PID="$(<"$PID_FILE")"

if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    echo "Slide server is not running (stale PID $SERVER_PID)."
    rm -f "$PID_FILE"
    exit 0
fi

COMMAND_LINE="$(tr '\0' ' ' <"/proc/$SERVER_PID/cmdline" 2>/dev/null || true)"
if [[ "$COMMAND_LINE" != *"python3 -m http.server 8000 --directory slides"* ]]; then
    echo "Refusing to stop PID $SERVER_PID: it is not the expected slide server." >&2
    exit 1
fi

kill "$SERVER_PID"
for _ in {1..20}; do
    if ! kill -0 "$SERVER_PID" 2>/dev/null; then
        rm -f "$PID_FILE"
        echo "Slide server stopped."
        exit 0
    fi
    sleep 0.1
done

echo "Slide server did not stop within 2 seconds (PID $SERVER_PID)." >&2
exit 1
