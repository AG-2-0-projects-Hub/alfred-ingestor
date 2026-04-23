#!/usr/bin/env bash
# Flutter web dev server for WSL2.
#
# WHY: `flutter run -d chrome` crashes in WSL2 with German-locale Windows 11
# because Flutter auto-detects the Windows Chrome binary
# (/mnt/c/Program Files/Google/Chrome/Application/chrome.exe) and pipes its
# stdout. Windows Chrome emits CP1252-encoded bytes (German umlaut at offset 41
# in its startup output). Flutter's tool decodes the pipe as UTF-8 → crash.
#
# FIX: `web-server` device skips Chrome launch entirely. Flutter serves the
# compiled app on a local port. Open http://localhost:8080 in Windows Chrome.
#
# PERMANENT FIX: Install Linux Google Chrome (native .deb), then Flutter will
# find /usr/bin/google-chrome and `flutter run -d chrome` will work normally.

set -e
cd "$(dirname "$0")"
echo "Starting Flutter web dev server at http://localhost:8080"
echo "Open that URL in your Windows browser."
echo ""
flutter run -d web-server --web-port 8080 --web-hostname 0.0.0.0
