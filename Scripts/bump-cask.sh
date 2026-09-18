#!/usr/bin/env bash
# Render Casks/otter-stats.rb for a release and push it to the Homebrew tap.
#   Scripts/bump-cask.sh <version> <sha256>            # e.g. 0.1.0 abc123...
#   TAP_REPO=owner/homebrew-tap                        # default chris-wozniczek/homebrew-tap
#   TAP_GITHUB_TOKEN=...                               # optional; git credentials are used otherwise
#   DRY_RUN=1                                          # render to stdout only
set -euo pipefail

VERSION="${1:?version}"
SHA256="${2:?sha256}"
TAP_REPO="${TAP_REPO:-chris-wozniczek/homebrew-tap}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

render() {
  sed -e "s/@VERSION@/${VERSION#v}/" -e "s/@SHA256@/${SHA256}/" "$ROOT/Homebrew/otter-stats.rb.tmpl"
}

if [ "${DRY_RUN:-0}" = "1" ]; then
  render
  exit 0
fi

WORK="$(mktemp -d)"
if [ -n "${TAP_GITHUB_TOKEN:-}" ]; then
  REMOTE="https://x-access-token:${TAP_GITHUB_TOKEN}@github.com/${TAP_REPO}.git"
else
  REMOTE="${TAP_REMOTE:-https://github.com/${TAP_REPO}.git}"
fi
git clone --quiet --depth 1 "$REMOTE" "$WORK"
mkdir -p "$WORK/Casks"
render > "$WORK/Casks/otter-stats.rb"
cd "$WORK"
git add Casks/otter-stats.rb
if git diff --cached --quiet; then
  echo "cask already at ${VERSION#v}"
  exit 0
fi
git -c user.name="${GIT_AUTHOR_NAME:-otter-stats release}" \
    -c user.email="${GIT_AUTHOR_EMAIL:-noreply@github.com}" \
    commit --quiet -m "otter-stats ${VERSION#v}"
git push --quiet origin HEAD
echo "==> pushed otter-stats ${VERSION#v} to ${TAP_REPO}"
