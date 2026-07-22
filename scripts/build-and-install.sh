#!/bin/bash
# Builds MarkdownEditor (Release) and installs it to ~/Applications.
set -euo pipefail

PROJECT="MarkdownEditor/MarkdownEditor.xcodeproj"
SCHEME="MarkdownEditor"
CONFIGURATION="Release"
DEST_DIR="$HOME/Applications"

cd "$(dirname "$0")/.."

echo "Building $SCHEME ($CONFIGURATION)..."
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIGURATION" build

BUILD_DIR=$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIGURATION" -showBuildSettings 2>/dev/null \
  | awk -F'= ' '/ BUILT_PRODUCTS_DIR /{print $2; exit}')
APP_PATH="$BUILD_DIR/$SCHEME.app"

if [ ! -d "$APP_PATH" ]; then
  echo "error: built app not found at $APP_PATH" >&2
  exit 1
fi

echo "Installing to $DEST_DIR/$SCHEME.app..."
rm -rf "$DEST_DIR/$SCHEME.app"
cp -R "$APP_PATH" "$DEST_DIR/"

echo "Done: $DEST_DIR/$SCHEME.app"
