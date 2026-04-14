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
cat > frontend/.env <<EOF
SUPABASE_URL=${SUPABASE_URL}
SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY}
BACKEND_URL=${BACKEND_URL}
EOF

echo "frontend/.env written with BACKEND_URL=${BACKEND_URL}"

cd frontend
flutter pub get
flutter build web --pwa-strategy=none --release
