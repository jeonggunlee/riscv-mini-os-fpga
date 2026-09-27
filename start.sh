#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PID_FILE="$PROJECT_DIR/build/slides-server.pid"
LOG_FILE="$PROJECT_DIR/build/slides-server.log"

cd "$PROJECT_DIR"
mkdir -p build

if [[ -f "$PID_FILE" ]]; then
    SERVER_PID="$(<"$PID_FILE")"
    if kill -0 "$SERVER_PID" 2>/dev/null; then
        echo "Slide server is already running (PID $SERVER_PID)."
        echo "Open: http://localhost:8000"
        exit 0
    fi
    rm -f "$PID_FILE"
fi

nohup python3 -m http.server 8000 --directory slides >"$LOG_FILE" 2>&1 &
SERVER_PID=$!
echo "$SERVER_PID" >"$PID_FILE"

sleep 0.5
if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    echo "Failed to start slide server. See: $LOG_FILE" >&2
    rm -f "$PID_FILE"
    exit 1
fi

echo "Slide server started (PID $SERVER_PID)."
echo "Open: http://localhost:8000"
echo "Log:  $LOG_FILE"
