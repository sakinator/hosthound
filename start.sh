#!/usr/bin/env bash
# =============================================================================
#  PlayTorrio Nuvio Addon — Linux / Android (Termux) Launcher
#  Works on: NVIDIA Shield Pro, Raspberry Pi, Ubuntu, Debian, any ARM64/x64
#
#  Usage:
#    bash start.sh          # default port 7000
#    bash start.sh 8080     # custom port
# =============================================================================

set -e
cd "$(cd "$(dirname "$0")" && pwd)"   # always run from project root

PORT="${1:-7000}"

echo ""
echo "==============================================================="
echo "               ⚡ Hostreamio Addon for Nuvio ⚡"
echo "==============================================================="

# ── 1. Find Dart ─────────────────────────────────────────────────────────────
DART_EXE=""
if   [ -f "../dart-sdk/bin/dart" ]; then DART_EXE="$(realpath ../dart-sdk/bin/dart)"
elif [ -f "dart-sdk/bin/dart" ];    then DART_EXE="$(realpath dart-sdk/bin/dart)"
elif command -v dart &>/dev/null;   then DART_EXE="dart"
fi

# ── 2. First-time setup (creates lib/upstream symlink + dart pub get) ─────────
if [ -n "$DART_EXE" ] && [ ! -L "lib/upstream" ] && [ ! -d "lib/upstream" ]; then
    echo ""
    echo " Running first-time setup..."
    "$DART_EXE" run tool/setup.dart
fi

# Also run pub get if packages are missing
if [ -n "$DART_EXE" ] && [ ! -f ".dart_tool/package_config.json" ]; then
    echo " Running dart pub get..."
    "$DART_EXE" pub get
fi

# ── 3. Detect LAN IP ─────────────────────────────────────────────────────────
LAN_IP=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+\.\d+\.\d+\.\d+' \
         | grep -v '127\.' | grep -v '169\.254\.' | head -1 2>/dev/null || echo "127.0.0.1")

echo ""
echo " LAN IP : http://$LAN_IP:$PORT"
echo " Local  : http://localhost:$PORT"
echo " Install in Nuvio: http://$LAN_IP:$PORT/manifest.json"
echo " Dashboard: http://localhost:$PORT/configure"
echo "==============================================================="
echo ""

# ── 4. Start the server ───────────────────────────────────────────────────────
if [ -f "./hostreamio" ] && [ -x "./hostreamio" ]; then
    echo " Using compiled binary (fastest startup)..."
    exec "./hostreamio" "$PORT"
elif [ -f "./hosthound" ] && [ -x "./hosthound" ]; then
    echo " Using compiled binary (fastest startup)..."
    exec "./hosthound" "$PORT"
elif [ -f "./unbound" ] && [ -x "./unbound" ]; then
    echo " Using compiled binary (fastest startup)..."
    exec "./unbound" "$PORT"
elif [ -f "./sakinator-MegaScraper" ] && [ -x "./sakinator-MegaScraper" ]; then
    echo " Using compiled binary (fastest startup)..."
    exec "./sakinator-MegaScraper" "$PORT"
elif [ -n "$DART_EXE" ]; then
    echo " Using dart run..."
    exec "$DART_EXE" run bin/server.dart "$PORT"
else
    echo ""
    echo " ERROR: Dart not found!"
    echo ""
    echo " Install on NVIDIA Shield / Android (Termux):"
    echo "   pkg update && pkg install dart git"
    echo ""
    echo " Install on Raspberry Pi / Ubuntu / Debian:"
    echo "   sudo apt update && sudo apt install dart"
    echo "   OR: https://dart.dev/get-dart"
    echo ""
    exit 1
fi
