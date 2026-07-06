#!/bin/bash
#
# curl -fsSL https://raw.githubusercontent.com/arc-com/surface-releases/main/install.sh | bash
#
# This file has to be HOSTED IN THE PUBLIC arc-com/surface-releases REPO (not
# this private source repo) for that one-liner to work without auth — copy it
# over whenever it changes. Re-running this script is also how to update:
# it always re-fetches "latest" and overwrites the installed copy.

set -e

REPO="arc-com/surface-releases"
APP_NAME="Surface"
INSTALL_DIR="${SURFACE_INSTALL_DIR:-/Applications}"
BASE_URL="https://github.com/$REPO/releases/latest/download"

# ── Downloader ────────────────────────────────────────────────────────────────

DOWNLOADER=""
if command -v curl >/dev/null 2>&1; then
    DOWNLOADER="curl"
elif command -v wget >/dev/null 2>&1; then
    DOWNLOADER="wget"
else
    echo "Either curl or wget is required but neither is installed" >&2
    exit 1
fi

download_file() {
    local url="$1" output="$2"
    if [ "$DOWNLOADER" = "curl" ]; then
        curl -fsSL -o "$output" "$url"
    else
        wget -q -O "$output" "$url"
    fi
}

# ── Platform check ────────────────────────────────────────────────────────────
# Surface is macOS/arm64 only for now (see the shell's Cmd+Q hold handling,
# app.getFileIcon usage, and Finder-style chrome, none of which are portable
# yet) — reject everything else with a clear message instead of half-working.

if [ "$(uname -s)" != "Darwin" ]; then
    echo "Surface only supports macOS right now. See https://github.com/$REPO for updates." >&2
    exit 1
fi

arch="$(uname -m)"
# Rosetta 2: an Apple Silicon Mac can still report x86_64 if the shell itself
# is running translated — the underlying hardware is arm64, so check for that
# before rejecting it as unsupported.
if [ "$arch" = "x86_64" ] && [ "$(sysctl -n sysctl.proc_translated 2>/dev/null)" = "1" ]; then
    arch="arm64"
fi
if [ "$arch" != "arm64" ]; then
    echo "Surface currently only ships an Apple Silicon (arm64) build — this Mac reports $arch." >&2
    exit 1
fi

# ── Download + verify ─────────────────────────────────────────────────────────

TMP_DIR="$(mktemp -d)"
trap '/bin/rm -rf "$TMP_DIR"' EXIT

zip_path="$TMP_DIR/${APP_NAME}-${arch}.zip"
sha_path="$TMP_DIR/${APP_NAME}-${arch}.zip.sha256"

echo "Downloading $APP_NAME..."
if ! download_file "$BASE_URL/${APP_NAME}-${arch}.zip" "$zip_path"; then
    echo "Download failed. Check https://github.com/$REPO/releases for the latest build." >&2
    exit 1
fi

if download_file "$BASE_URL/${APP_NAME}-${arch}.zip.sha256" "$sha_path" 2>/dev/null; then
    expected="$(cut -d' ' -f1 "$sha_path")"
    actual="$(shasum -a 256 "$zip_path" | cut -d' ' -f1)"
    if [ "$expected" != "$actual" ]; then
        echo "Checksum verification failed — the download may be corrupt or tampered with." >&2
        exit 1
    fi
else
    echo "warning: no checksum published for this release, skipping verification" >&2
fi

# ── Install ───────────────────────────────────────────────────────────────────
# ditto (not curl/Safari/AirDrop) fetched and is extracting this, so it never
# picks up the com.apple.quarantine attribute Gatekeeper checks for — no
# right-click-Open or System Settings step needed on first launch.

echo "Installing to $INSTALL_DIR..."
/bin/rm -rf "$INSTALL_DIR/${APP_NAME}.app"
if ! ditto -x -k "$zip_path" "$INSTALL_DIR" 2>/tmp/surface-install-err.$$; then
    echo "Failed to extract to $INSTALL_DIR — do you have write access there? Try:" >&2
    echo "  SURFACE_INSTALL_DIR=\"\$HOME/Applications\" $0" >&2
    cat /tmp/surface-install-err.$$ >&2
    /bin/rm -f /tmp/surface-install-err.$$
    exit 1
fi
/bin/rm -f /tmp/surface-install-err.$$

echo ""
echo "$APP_NAME installed: $INSTALL_DIR/${APP_NAME}.app"
echo "Not code-signed, but launched normally (Finder/Spotlight/Dock) should just"
echo "work — no Gatekeeper prompt, since this script never triggered quarantine."
echo "If macOS still blocks it, right-click the app -> Open -> Open."
echo ""
echo "To update later, just re-run this same command."
