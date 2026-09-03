#!/usr/bin/env bash
set -euo pipefail

# Install Flutter SDK if not present (Vercel build environment)
if ! command -v flutter &>/dev/null; then
  echo "Installing Flutter SDK..."
  git clone https://github.com/flutter/flutter.git -b stable --depth 1 /opt/flutter
  export PATH="/opt/flutter/bin:$PATH"
fi

export PATH="/opt/flutter/bin:${PATH:-}"

flutter --version
flutter config --no-analytics

# Write frontend/.env from Vercel environment variables.
# These must be set in the Vercel project dashboard:
#   SUPABASE_URL, SUPABASE_ANON_KEY, BACKEND_URL
#   TELEGRAM_BOT_USERNAME (optional — enables the guest Telegram link in the
#   host chat view; the link is hidden when unset).
#   WHATSAPP_NUMBER (optional — the shared Alfred WhatsApp number in E.164,
#   e.g. +5215512345678. Enables the guest WhatsApp link in the host chat view;
#   the link is hidden when unset. Must match the number the backend sends from,
#   or guests will message a number that never answers.)
#
# TELEGRAM_LINK_DOMAIN is deliberately NOT emitted. Both the client
# (chat_live_dialog.dart) and the backend (messages.py) default to `t.me`, which
# is what we want: the 2026-07 outage that prompted 591e9e6 was a global
# Telegram problem, not ours. The env lever stays in the code as an escape hatch
# if t.me ever breaks again — leaving it unset is what pins us to t.me.
cat > frontend/.env <<EOF
SUPABASE_URL=${SUPABASE_URL}
SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY}
BACKEND_URL=${BACKEND_URL}
TELEGRAM_BOT_USERNAME=${TELEGRAM_BOT_USERNAME:-}
WHATSAPP_NUMBER=${WHATSAPP_NUMBER:-}
EOF

echo "frontend/.env written with BACKEND_URL=${BACKEND_URL}"

cd frontend
flutter pub get
flutter build web --pwa-strategy=none --release
