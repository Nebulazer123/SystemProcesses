#!/bin/bash
set -euo pipefail

demo_script_dir="$(cd "$(dirname "$0")" && pwd)"
demo_root=""
demo_cursor="$demo_script_dir"
while [[ "$demo_cursor" != / ]]; do
    if [[ -f "$demo_cursor/main.swift" && -f "$demo_cursor/build.sh" && -f "$demo_cursor/SystemProcesses.app/Contents/Info.plist" ]]; then
        demo_root="$demo_cursor"
        break
    fi
    demo_cursor="$(dirname "$demo_cursor")"
done
if [[ -z "$demo_root" ]]; then
    echo "Could not locate the System Processes project root from $demo_script_dir" >&2
    exit 1
fi

cd "$demo_root"
source "$demo_root/script/toolchain.sh"

demo_work="$(python3 - <<'PY'
from pathlib import Path
import tempfile
base = Path(tempfile.gettempdir()).resolve()
if 'Documents' in base.parts:
    raise SystemExit(f'Demo runtime must stay outside Documents: {base}')
print(tempfile.mkdtemp(prefix='systemprocesses-demo-', dir=base))
PY
)"
trap 'rm -rf "$demo_work"' EXIT
demo_bundle="$demo_work/SystemProcessesDemo.app"
demo_source="$demo_work/main.swift"
demo_config="$demo_work/config"
demo_runtime_assets="$demo_work/assets"
demo_publish_assets="$demo_root/docs/assets"
mkdir -p "$demo_bundle/Contents/MacOS" "$demo_config" "$demo_runtime_assets"

python3 - "$demo_root" "$demo_source" "$demo_bundle/Contents/Info.plist" "$demo_config" "$demo_runtime_assets" <<'PY'
from pathlib import Path
import json, plistlib, re, sys

root, source_path, plist_path, config_dir, assets_dir = map(Path, sys.argv[1:])
source = (root / 'main.swift').read_text()
marker = '// MARK: - Entry Point'
if marker not in source:
    raise SystemExit('Could not find production entry-point boundary')
source = source.split(marker, 1)[0]
source, config_count = re.subn(r'^let CONFIG_DIR = .*$', 'let CONFIG_DIR = ' + json.dumps(str(config_dir)), source, count=1, flags=re.M)
if config_count != 1:
    raise SystemExit('Could not isolate the demo configuration directory')
source, label_count = re.subn(
    r'^\s*let pl = NSTextField\(labelWithString: \(CONFIG_PATH as NSString\)\.abbreviatingWithTildeInPath\)$',
    '        let pl = NSTextField(labelWithString: "~/.config/systemprocesses/config.json")',
    source, count=1, flags=re.M)
if label_count != 1:
    raise SystemExit('Could not replace the Settings config-path display line')
source += '\n' + (root / 'Intelligence.swift').read_text()
source += '\n' + (root / 'ProviderWire.swift').read_text()
source += '\n' + (root / 'RuntimeState.swift').read_text()
source += '\n' + (root / 'AppleModel.swift').read_text()
source += '\n' + (root / 'ModelCatalog.swift').read_text()
demo = (root / 'script/Demo.swift').read_text()
demo = demo.replace('__DEMO_ASSETS__', json.dumps(str(assets_dir)))
source_path.write_text(source + '\n' + demo)

with (root / 'SystemProcesses.app/Contents/Info.plist').open('rb') as f:
    info = plistlib.load(f)
info['CFBundleIdentifier'] = 'app.systemprocesses.demo'
info['CFBundleName'] = info['CFBundleDisplayName'] = 'System Processes Demo'
info['CFBundleExecutable'] = 'systemprocesses'
with plist_path.open('wb') as f:
    plistlib.dump(info, f)
PY

swiftc "${sp_apple_flags[@]}" -Osize -target "$(uname -m)-apple-macosx13.0" \
    "$demo_source" -o "$demo_bundle/Contents/MacOS/systemprocesses" \
    -framework Cocoa -framework UserNotifications -framework Security -framework CryptoKit \
    "${sp_apple_links[@]}"
codesign --force --sign - "$demo_bundle"
cd "$demo_work"
/usr/bin/open -n -W "$demo_bundle"
cd "$demo_root"
mkdir -p "$demo_publish_assets"

for demo_asset in processes.png settings.png settings-help.png menu-button.png; do
    if [[ ! -s "$demo_runtime_assets/$demo_asset" ]]; then
        echo "Demo did not render $demo_runtime_assets/$demo_asset" >&2
        exit 1
    fi
    cp "$demo_runtime_assets/$demo_asset" "$demo_publish_assets/$demo_asset"
done
echo "Rendered synthetic AppKit screenshots to $demo_publish_assets"
