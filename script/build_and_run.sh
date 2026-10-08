#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$task_root"
if [[ "${1:-}" == "--verify" ]]; then exec ./script/test.sh; fi
# Only stop this checkout's executable, not an installed app or another checkout.
python3 - "$task_root/SystemProcesses.app/Contents/MacOS/systemprocesses" <<'PY'
import os,signal,subprocess,sys
target=sys.argv[1]
for line in subprocess.check_output(['ps','-axo','pid=,comm='],text=True).splitlines():
    parts=line.strip().split(None,1)
    if len(parts)==2 and parts[1]==target:
        try: os.kill(int(parts[0]),signal.SIGTERM)
        except ProcessLookupError: pass
PY
./build.sh
/usr/bin/open -n "$task_root/SystemProcesses.app"
