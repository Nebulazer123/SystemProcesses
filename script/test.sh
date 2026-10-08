#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$task_root"
source "$task_root/script/toolchain.sh"
task_mode="${1:-current}"
case "$task_mode" in current) ;; *) echo "Usage: $0 [current]" >&2; exit 2 ;; esac
if [[ "$task_mode" == "current" ]]; then python3 script/release_evidence.py before-test; fi
task_out="$task_root/.work/tests-$task_mode"
task_runtime="$(python3 - "$task_mode" <<'PY'
from pathlib import Path
import tempfile, sys
base = Path(tempfile.gettempdir()).resolve()
if 'Documents' in base.parts:
    raise SystemExit(f'GUI test runtime must stay outside Documents: {base}')
print(tempfile.mkdtemp(prefix=f'systemprocesses-tests-{sys.argv[1]}-', dir=base))
PY
)"
task_test_app="$task_runtime/SystemProcessesQA.app"
task_config="$task_runtime/config"
task_screenshots="$task_runtime/screenshots"
task_log="$task_runtime/checks.log"
task_stderr="$task_runtime/stderr.log"
mkdir -p "$task_test_app/Contents/MacOS" "$task_config" "$task_screenshots" "$task_out"
task_results_copied=0
copy_results_back() {
    [[ "$task_results_copied" == 0 ]] || return 0
    mkdir -p "$task_out"
    if [[ -x "$task_test_app/Contents/MacOS/systemprocesses" ]]; then
        if [[ -d "$task_out/SystemProcessesQA.app" ]]; then
            mv "$task_out/SystemProcessesQA.app" "$task_out/SystemProcessesQA-$task_stamp.app"
        fi
        ditto "$task_test_app" "$task_out/SystemProcessesQA.app"
    fi
    [[ ! -f "$task_log" ]] || cp "$task_log" "$task_out/checks.log"
    [[ ! -f "$task_stderr" ]] || cp "$task_stderr" "$task_out/stderr.log"
    if [[ -d "$task_screenshots" ]]; then
        mkdir -p "$task_out/screenshots"
        cp -R "$task_screenshots"/. "$task_out/screenshots"/
    fi
    task_results_copied=1
}
task_stamp="$(date +%Y%m%d-%H%M%S)-$$"
for task_previous_log in checks.log stderr.log; do
    if [[ -f "$task_out/$task_previous_log" ]]; then
        cp "$task_out/$task_previous_log" "$task_out/${task_previous_log%.log}-$task_stamp.log"
    fi
done
trap 'copy_results_back; rm -rf "$task_runtime"' EXIT

python3 - "$task_root" "$task_runtime" "$task_mode" <<'PY'
from pathlib import Path
import json, plistlib, subprocess, sys, re
root, out = map(Path, sys.argv[1:3])
source = (root/'main.swift').read_text()
source = source.split('// MARK: - Entry Point')[0]
source, count = re.subn(r'^let CONFIG_DIR.*$', 'let CONFIG_DIR = ' + json.dumps(str(out/'config')), source, count=1, flags=re.M)
if count != 1: raise SystemExit('Could not isolate the regression configuration directory')
tests = (root/'Tests/regression.swift').read_text().replace('TEST_OUTPUT',str(out/'screenshots'))
if sys.argv[3]!='baseline':
 tests = (root/'Tests/intelligence.swift').read_text()+'\n'+(root/'Tests/security.swift').read_text()+'\n'+(root/'Tests/catalog.swift').read_text()+'\n'+(root/'Tests/providers.swift').read_text()+'\n'+(root/'Tests/transport.swift').read_text()+'\n'+tests
 tests = tests.replace('try unitChecks()', 'try unitChecks(); intelligenceChecks { check($0, $1) }; securityChecks { check($0, $1) }; modelCatalogChecks { check($0, $1) }; providerChecks { check($0, $1) }')
 source = source+'\n'+''.join((root/name).read_text() for name in ['Intelligence.swift','ProviderWire.swift','RuntimeState.swift','AppleModel.swift','ModelCatalog.swift'])
(out/'main.swift').write_text(source+tests)
p = plistlib.loads((root/'SystemProcesses.app/Contents/Info.plist').read_bytes())
p['CFBundleIdentifier'] = 'app.systemprocesses.regression-'+sys.argv[3]
p['CFBundleDisplayName'] = p['CFBundleName'] = 'SystemProcesses Regression'
(out/'SystemProcessesQA.app/Contents/Info.plist').write_bytes(plistlib.dumps(p))
PY
task_flags=(-D CURRENT)
swiftc "${sp_apple_flags[@]}" -Osize -target "$(uname -m)-apple-macosx13.0" "${task_flags[@]}" "$task_runtime/main.swift" \
    -o "$task_test_app/Contents/MacOS/systemprocesses" -framework Cocoa -framework UserNotifications -framework Security -framework CryptoKit "${sp_apple_links[@]}"
codesign --force --sign - "$task_test_app"
: > "$task_log"
: > "$task_stderr"
cd "$task_runtime"
/usr/bin/open -n -W "$task_test_app" --stdout "$task_log" --stderr "$task_stderr"
cd "$task_root"
copy_results_back
python3 - "$task_out" <<'PY'
from pathlib import Path
import json,sys
out=Path(sys.argv[1]); log=(out/'checks.log').read_text()
print(log)
results=[json.loads(line.removeprefix('TEST_RESULT ')) for line in log.splitlines() if line.startswith('TEST_RESULT ')]
if not results:
    print((out/'stderr.log').read_text()); sys.exit('No completion result from the GUI regression app')
sys.exit(0 if results[-1]['failures']==0 else 1)
PY

if [[ "$task_mode" == "current" ]]; then python3 script/release_evidence.py after-test; fi
