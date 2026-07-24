#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
cd "$project_dir"

xcodegen generate
xcodebuild \
  -project CodexTokenNative.xcodeproj \
  -scheme CodexToken \
  -configuration Release \
  -derivedDataPath "$project_dir/.xcode-derived" \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGN_STYLE=Manual \
  build

echo "$project_dir/.xcode-derived/Build/Products/Release/Codex Token.app"
