#!/usr/bin/env bash
# Deploy SHIP: push to main, wait for Vercel's auto-deploy to finish,
# then re-point the pinned sea-hawk-intelligence-portal.vercel.app alias
# to the new deployment.
#
# Why: trade-management-tool.vercel.app auto-tracks production, but the
# vanity alias sea-hawk-intelligence-portal.vercel.app was pinned to a
# specific deployment and won't update on its own. This script fixes that.
#
# Usage:  ./deploy.sh           (commits must already be staged or committed)
# Requires: vercel CLI logged in, git remote configured, gnu/bsd awk + grep.

set -euo pipefail

ALIAS="sea-hawk-intelligence-portal.vercel.app"
TIMEOUT=300   # seconds to wait for the new production deployment to go Ready

cd "$(dirname "$0")"

# 1. Push to origin/main. Capture output so we can detect a no-op push.
echo "→ Pushing to origin/main…"
PUSH_OUTPUT="$(git push origin main 2>&1)"
PUSH_EXIT=$?
echo "$PUSH_OUTPUT"
if [[ $PUSH_EXIT -ne 0 ]]; then
  echo "✗ git push failed." >&2
  exit 1
fi
if [[ "$PUSH_OUTPUT" == *"Everything up-to-date"* ]]; then
  echo "→ No new commits — nothing for Vercel to deploy."
  echo "  Current alias: https://$ALIAS"
  exit 0
fi

# 2. Remember which deployment the alias currently points at, so we can tell
#    when a NEW one has been promoted past it.
OLD_TARGET="$(vercel inspect "$ALIAS" 2>&1 \
  | awk '/^[[:space:]]*url[[:space:]]/ {print $2; exit}')"
echo "→ Current alias target: ${OLD_TARGET:-<none>}"

# 3. Poll vercel ls --prod for a NEWER production deployment that's Ready.
echo "→ Waiting for the new Vercel production deployment to go Ready…"
START=$(date +%s)
NEW_URL=""

while true; do
  TOP_LINE="$(vercel ls --prod 2>&1 \
    | grep -E 'https://[^ ]+\.vercel\.app' \
    | head -1 || true)"
  TOP_URL="$(echo "$TOP_LINE" | grep -oE 'https://[^ ]+' | head -1 || true)"

  if [[ -n "$TOP_URL" \
        && "$TOP_URL" != "$OLD_TARGET" \
        && "$TOP_LINE" == *"Ready"* ]]; then
    NEW_URL="$TOP_URL"
    break
  fi

  ELAPSED=$(( $(date +%s) - START ))
  if (( ELAPSED > TIMEOUT )); then
    echo
    echo "✗ Timed out after ${TIMEOUT}s. Latest deployment URL: ${TOP_URL:-<none>}" >&2
    exit 1
  fi
  printf "."
  sleep 5
done
echo
echo "→ New deployment Ready: $NEW_URL"

# 4. Re-point the pinned alias to the new deployment.
echo "→ Re-pointing $ALIAS …"
vercel alias set "$NEW_URL" "$ALIAS"

echo
echo "✓ Live at https://$ALIAS"
echo "  (Hard-refresh the browser with Cmd+Shift+R if you still see the old page.)"
