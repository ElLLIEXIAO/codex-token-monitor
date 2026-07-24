#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
cd "$project_dir"
swift build -c release

app_dir="$project_dir/dist/Codex Token.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$project_dir/.build/release/CodexTokenMonitor" "$app_dir/Contents/MacOS/CodexTokenMonitor"
cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
echo "$app_dir"
