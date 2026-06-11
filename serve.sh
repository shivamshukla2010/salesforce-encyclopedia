#!/usr/bin/env bash
# Encyclopedia local server + public Cloudflare tunnel
# Usage:  ./serve.sh          — start server and tunnel
#         ./serve.sh stop      — kill both
set -e

PORT=8080
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PID_FILE="$SCRIPT_DIR/.server.pids"

stop() {
  if [ -f "$PID_FILE" ]; then
    while IFS= read -r pid; do
      kill "$pid" 2>/dev/null && echo "Stopped PID $pid" || true
    done < "$PID_FILE"
    rm -f "$PID_FILE"
  fi
  echo "Encyclopedia server stopped."
  exit 0
}

[ "${1}" = "stop" ] && stop

# Kill any existing instance
[ -f "$PID_FILE" ] && stop 2>/dev/null || true

echo "Starting encyclopedia at http://localhost:$PORT ..."
cd "$SCRIPT_DIR"
python3 -m http.server $PORT --bind 127.0.0.1 &>/tmp/encyclopedia-http.log &
HTTP_PID=$!

sleep 0.5
if ! kill -0 "$HTTP_PID" 2>/dev/null; then
  echo "ERROR: HTTP server failed to start. Check /tmp/encyclopedia-http.log"
  exit 1
fi

echo "Starting Cloudflare tunnel..."
cloudflared tunnel --url http://localhost:$PORT --no-autoupdate &>/tmp/encyclopedia-tunnel.log &
TUNNEL_PID=$!

printf "%s\n%s\n" "$HTTP_PID" "$TUNNEL_PID" > "$PID_FILE"

# Wait for the public URL to appear in the tunnel log
echo "Waiting for public URL..."
for i in $(seq 1 30); do
  URL=$(grep -o 'https://[a-zA-Z0-9\-]*\.trycloudflare\.com' /tmp/encyclopedia-tunnel.log 2>/dev/null | head -1)
  if [ -n "$URL" ]; then
    echo ""
    echo "======================================================"
    echo "  Encyclopedia is live!"
    echo ""
    echo "  Local:  http://localhost:$PORT"
    echo "  Public: $URL"
    echo "======================================================"
    echo ""
    echo "Share the public URL with anyone on any network."
    echo "Run './serve.sh stop' to shut down."
    exit 0
  fi
  sleep 1
  printf "."
done

echo ""
echo "Tunnel started but URL not detected yet."
echo "Check /tmp/encyclopedia-tunnel.log for the public URL."
echo "Local server: http://localhost:$PORT"
echo "PIDs saved to $PID_FILE — run './serve.sh stop' to shut down."
