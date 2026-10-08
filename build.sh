#!/bin/bash
set -e
source "$(dirname "$0")/script/toolchain.sh"
python3 script/release_evidence.py before-build
mkdir -p SystemProcesses.app/Contents/MacOS SystemProcesses.app/Contents/Resources
cp LICENSE SystemProcesses.app/Contents/Resources/LICENSE
swiftc "${sp_apple_flags[@]}" -Osize -target "$(uname -m)-apple-macosx13.0" -o SystemProcesses.app/Contents/MacOS/systemprocesses main.swift Intelligence.swift ProviderWire.swift RuntimeState.swift AppleModel.swift ModelCatalog.swift \
  -framework Cocoa \
  -framework UserNotifications -framework Security -framework CryptoKit "${sp_apple_links[@]}"
strip SystemProcesses.app/Contents/MacOS/systemprocesses
codesign --force --sign - SystemProcesses.app
echo "Built SystemProcesses.app ($(du -h SystemProcesses.app/Contents/MacOS/systemprocesses | cut -f1 | xargs))"

python3 script/release_evidence.py after-build
