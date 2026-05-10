#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Notes Guy"
APP_BUNDLE="$ROOT_DIR/dist/${APP_NAME}.app"
USER_APPLICATIONS_DIR="$HOME/Applications"
SYSTEM_APPLICATIONS_DIR="/Applications"
EXECUTABLE_SOURCE="$ROOT_DIR/.build/release/notes-guy-desktop"
EXECUTABLE_TARGET="$APP_BUNDLE/Contents/MacOS/NotesGuy"
ICON_SOURCE="$ROOT_DIR/packaging/macos/AppIcon.icns"
CODE_SIGN_IDENTITY="${NOTES_GUY_CODESIGN_IDENTITY:-}"

cd "$ROOT_DIR"

if [[ ! -f "$ICON_SOURCE" ]]; then
  python3 "$ROOT_DIR/scripts/make-macos-icon.py" >/dev/null
fi

swift build -c release --product notes-guy-desktop

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

cp "$EXECUTABLE_SOURCE" "$EXECUTABLE_TARGET"
cp "$ROOT_DIR/packaging/macos/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
if [[ -f "$ICON_SOURCE" ]]; then
  cp "$ICON_SOURCE" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi
chmod +x "$EXECUTABLE_TARGET"

if command -v codesign >/dev/null 2>&1; then
  if [[ -z "$CODE_SIGN_IDENTITY" ]]; then
    if security find-identity -v -p codesigning 2>/dev/null | grep -q '"Notes Guy Local"'; then
      CODE_SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk -F '[ )]+' '/"Notes Guy Local"/ { print $3; exit }')"
    elif security find-identity -v -p codesigning 2>/dev/null | grep -q '"Gramr Fix Anywhere Local"'; then
      CODE_SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk -F '[ )]+' '/"Gramr Fix Anywhere Local"/ { print $3; exit }')"
    else
      CODE_SIGN_IDENTITY="-"
    fi
  fi
  codesign --force --deep --sign "$CODE_SIGN_IDENTITY" "$APP_BUNDLE" >/dev/null
fi

can_install_into() {
  local dir="$1"
  [[ -d "$dir" && -w "$dir" ]]
}

can_update_existing_app_in() {
  local dir="$1"
  [[ -d "$dir/${APP_NAME}.app" && -w "$dir/${APP_NAME}.app" ]]
}

if [[ -n "${NOTES_GUY_INSTALL_DIR:-}" ]] && { can_install_into "$NOTES_GUY_INSTALL_DIR" || can_update_existing_app_in "$NOTES_GUY_INSTALL_DIR"; }; then
  INSTALL_DIR="$NOTES_GUY_INSTALL_DIR"
elif can_install_into "$SYSTEM_APPLICATIONS_DIR" || can_update_existing_app_in "$SYSTEM_APPLICATIONS_DIR"; then
  INSTALL_DIR="$SYSTEM_APPLICATIONS_DIR"
else
  INSTALL_DIR="$USER_APPLICATIONS_DIR"
fi

mkdir -p "$INSTALL_DIR"

INSTALLED_APP="$INSTALL_DIR/${APP_NAME}.app"
pkill -f "${APP_NAME}.app/Contents/MacOS" >/dev/null 2>&1 || true
if can_install_into "$INSTALL_DIR"; then
  rm -rf "$INSTALLED_APP"
  cp -R "$APP_BUNDLE" "$INSTALLED_APP"
else
  rm -rf "$INSTALLED_APP/Contents"
  mkdir -p "$INSTALLED_APP"
  cp -R "$APP_BUNDLE/Contents" "$INSTALLED_APP/Contents"
fi

for STALE_APP in "$HOME/Desktop/${APP_NAME}.app" "$USER_APPLICATIONS_DIR/${APP_NAME}.app" "$SYSTEM_APPLICATIONS_DIR/${APP_NAME}.app"; do
  if [[ "$STALE_APP" != "$INSTALLED_APP" && -d "$STALE_APP" && -w "$(dirname "$STALE_APP")" ]]; then
    rm -rf "$STALE_APP"
  fi
done

rm -rf "$APP_BUNDLE"

echo "Installed to $INSTALLED_APP"
