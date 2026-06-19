#!/usr/bin/env bash
set -euo pipefail

# Build script for DeepSeek Balance Monitor
# Usage: ./build.sh [--copy-icon]

APP_NAME="DeepSeekBalance"
SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_BUNDLE="$SOURCE_DIR/$APP_NAME.app"

echo "🔨 Compiling $APP_NAME..."
cd "$APP_BUNDLE/Contents/MacOS"
xcrun swiftc -o "$APP_NAME" -O main.swift

echo "✅ Compiled: $APP_BUNDLE/Contents/MacOS/$APP_NAME ($(stat -f%z "$APP_NAME") bytes)"

# Copy icon if SVG source available and rsvg-convert installed
if [ ! -f "$APP_BUNDLE/Contents/Resources/deepseek-icon.png" ] && command -v rsvg-convert &>/dev/null; then
    if [ -f "$SOURCE_DIR/deepseek-whale.svg" ]; then
        echo "🎨 Generating icon from SVG..."
        rsvg-convert -w 16 -h 16 --keep-aspect-ratio --background-color none \
            -o "$APP_BUNDLE/Contents/Resources/deepseek-icon.png" \
            "$SOURCE_DIR/deepseek-whale.svg"
    fi
fi

echo ""
echo "🚀 To launch: open $APP_BUNDLE"
echo "📌 To auto-start at login, add a LaunchAgent pointing to:"
echo "   $APP_BUNDLE/Contents/MacOS/$APP_NAME"
