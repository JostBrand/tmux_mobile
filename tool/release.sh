#!/usr/bin/env bash
# Builds the release APKs and publishes them as a Forgejo release
# (git.jostbrandstetter.com/jost/tmux_mobile). Obtainium on the phone
# tracks these releases for one-tap updates.
#
# Auth: the CI bot (FORGEJO_CI_USERNAME/PASSWORD) - provided by the
# workspace template from coder-workspaces-secrets.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(grep -m1 '^version:' pubspec.yaml | awk '{print $2}' | tr -d '+')
TAG="v${VERSION}"

if [ -z "${FORGEJO_CI_PASSWORD:-}" ]; then
  echo "FORGEJO_CI_PASSWORD is not set" >&2
  exit 1
fi

AUTH="${FORGEJO_CI_USERNAME:-ci}:${FORGEJO_CI_PASSWORD}"
API="https://git.jostbrandstetter.com/api/v1"
REPO="jost/tmux_mobile"

echo "==> Building release APKs (${TAG})"
export PUB_CACHE="${PUB_CACHE:-/workspaces/.cache/pub}"
export GRADLE_USER_HOME="${GRADLE_USER_HOME:-/workspaces/.cache/gradle}"
flutter build apk --release --split-per-abi

echo "==> Publishing release ${TAG}"
# Idempotent: replace an existing release for this tag.
curl -fsS -u "$AUTH" -X DELETE "$API/repos/$REPO/releases/tags/$TAG" \
  -o /dev/null 2>/dev/null || true
RELEASE_ID=$(curl -fsS -u "$AUTH" -X POST "$API/repos/$REPO/releases" \
  -H "Content-Type: application/json" \
  -d "{\"tag_name\":\"$TAG\",\"target_commitish\":\"main\",\"name\":\"$TAG\",\"body\":\"Release build from the workspace\"}" \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')

echo "==> Uploading APK assets"
for apk in build/app/outputs/flutter-apk/*-release.apk; do
  name=$(basename "$apk")
  curl -fsS -u "$AUTH" -X POST \
    "$API/repos/$REPO/releases/$RELEASE_ID/assets?name=$name" \
    -F "attachment=@$apk" -o /dev/null
  echo "    uploaded $name"
done

# Keep the GitHub mirror in sync (push over SSH via the app key).
if git remote get-url github >/dev/null 2>&1; then
  git push github main 2>/dev/null || echo "    (github mirror push skipped/failed)"
fi

echo "==> Done: https://git.jostbrandstetter.com/jost/tmux_mobile/releases/tag/$TAG"
