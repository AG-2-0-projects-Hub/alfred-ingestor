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
#   TELEGRAM_LINK_DOMAIN (optional — defaults to t.me). chat_live_dialog.dart
#   reads this, but this script never emitted it, so the deep-link domain was
#   unset in every deployed bundle and always fell back to the hardcoded t.me —
#   i.e. the fix in 591e9e6 (t.me went NXDOMAIN) was inert on the client.
cat > frontend/.env <<EOF
SUPABASE_URL=${SUPABASE_URL}
SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY}
BACKEND_URL=${BACKEND_URL}
TELEGRAM_BOT_USERNAME=${TELEGRAM_BOT_USERNAME:-}
TELEGRAM_LINK_DOMAIN=${TELEGRAM_LINK_DOMAIN:-}
EOF

echo "frontend/.env written with BACKEND_URL=${BACKEND_URL}"

cd frontend
flutter pub get
flutter build web --pwa-strategy=none --release
