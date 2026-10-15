#!/usr/bin/env bash
# Publish a new version of Egtma3.
#
# Step 1 — build (raises the version, signs with the permanent key):
#   bash tool/release.sh build
#   → APK at build/app/outputs/flutter-apk/app-release.apk
#     Upload it to Google Drive, share "anyone with the link", copy the link.
#
# Step 2 — announce (website + update message on every phone):
#   bash tool/release.sh publish "https://drive.google.com/file/d/..../view" "ملاحظة"
#
# Phones then show "فيه نسخة جديدة" and update in place (data kept).
set -euo pipefail
cd "$(dirname "$0")/.."

case "${1:-}" in
  build)
    if [ ! -f android/key.properties ]; then
      echo "❌ android/key.properties is missing — updates must be signed with the release key." >&2
      exit 1
    fi
    OLD_BUILD=$(sed -n 's/^version: .*+\([0-9]*\)$/\1/p' pubspec.yaml)
    BUILD=$((OLD_BUILD + 1))
    sed -i "s/^version: .*/version: 1.0.$BUILD+$BUILD/" pubspec.yaml
    flutter build apk --release
    echo "✅ Built version 1.0.$BUILD (build $BUILD): build/app/outputs/flutter-apk/app-release.apk"
    echo "   Upload it to Google Drive, then run: bash tool/release.sh publish \"<drive link>\" \"ملاحظة\""
    ;;
  publish)
    LINK="${2:?Drive link of the APK is required}"
    NOTES="${3:-}"
    BUILD=$(sed -n 's/^version: .*+\([0-9]*\)$/\1/p' pubspec.yaml)
    flutter build web --release --pwa-strategy=none
    python - "$BUILD" "$LINK" "$NOTES" <<'PY'
import json, sys
build, link, notes = sys.argv[1:4]
json.dump({"build": int(build), "version": f"1.0.{build}", "apk": link, "notes": notes},
          open("build/web/app_update.json", "w", encoding="utf8"), ensure_ascii=False)
PY
    firebase deploy --only hosting --project egtma3-church-app --non-interactive
    echo "✅ Phones with an older version will now be offered build $BUILD."
    ;;
  *)
    echo "Usage: bash tool/release.sh build | publish <drive-link> [notes]" >&2
    exit 1
    ;;
esac
