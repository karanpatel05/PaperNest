# Shared settings for scripts/*.sh (sourced, not executed).
#
# Build products live outside the checkout, in ~/Library/Caches. This
# checkout may sit in an iCloud Drive-synced folder (Desktop & Documents),
# where the file provider adds Finder-info attributes to bundles that make
# `codesign` fail, and syncing hundreds of MB of build output creates
# conflict copies ("debug 2"). Override with PAPERNEST_SCRATCH.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
REPO_HASH="$(printf '%s' "$REPO_ROOT" | shasum | cut -c1-12)"
SCRATCH="${PAPERNEST_SCRATCH:-$HOME/Library/Caches/PaperNest/build-$REPO_HASH}"
# Built .app bundles too: iCloud re-tags bundles after signing, which then
# fails `codesign --verify --strict`.
DIST="$SCRATCH/dist"
mkdir -p "$SCRATCH" "$DIST"
