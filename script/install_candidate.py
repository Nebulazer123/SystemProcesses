#!/usr/bin/env python3
"""Recoverable local release. --apply is required; never push or alter credentials."""
import argparse, datetime, hashlib, json, os, plistlib, shutil, signal, subprocess, time
from pathlib import Path

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--apply', action='store_true')
args = parser.parse_args()
if not args.apply:
    raise SystemExit('Use --apply only after the candidate acceptance gates pass.')
source = root / 'SystemProcesses.app'
installed = Path('/Applications/SystemProcesses.app')
config = Path.home() / '.config/systemprocesses/config.json'
subprocess.run(['python3', str(root / 'script/release_evidence.py'), 'verify'], check=True)
checks = (root / '.work/tests-current/checks.log').read_text()
assert '"failures":0' in checks, 'Expected release regression evidence'
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(source)], check=True)
info = plistlib.loads((source / 'Contents/Info.plist').read_bytes())
assert info['CFBundleExecutable'] == 'systemprocesses'
assert info['CFBundleIdentifier'] == 'app.systemprocesses'
# The final closed-menu soak must have at least 30 minutes of recorded samples.
samples = [json.loads(line) for line in (root / '.work/performance/final-30min-soak.jsonl').read_text().splitlines()]
assert samples[-1]['time'] - samples[0]['time'] >= 1800, 'Soak is incomplete'
assert all(sample.get('menu_shown') is False for sample in samples[2:]), 'Closed-menu evidence required'
report = json.loads((root / '.work/performance/final-resource-report.json').read_text())
assert report['acceptance_passed'] and report['continuous_coverage_passed'], 'Resource acceptance evidence required'
assert len(samples) >= 330 and all(0 < b['time'] - a['time'] <= 15 for a, b in zip(samples, samples[1:])), 'Sparse soak cannot pass'
assert report['samples_sha256'] == hashlib.sha256((root / '.work/performance/final-30min-soak.jsonl').read_bytes()).hexdigest(), 'Resource report is stale'
assert all(s['pid'] == report['sampled_pid'] and s['process_start_abstime'] == report['process_start_abstime'] and s['process_uuid'] == report['process_uuid'] for s in samples), 'Resource identity mismatch'
assert all('retained_history' in s for s in samples[2:]), 'History telemetry missing'
# Reuse the tested native payload even though bundle identifiers change signatures.
def payload_hash(path):
    import struct
    blob = path.read_bytes(); pos = 32
    for _ in range(struct.unpack_from('<I', blob, 16)[0]):
        command, size = struct.unpack_from('<II', blob, pos)
        if command == 0x1d:
            offset, _ = struct.unpack_from('<II', blob, pos + 8)
            return hashlib.sha256(blob[:offset]).hexdigest()
        pos += size
    raise ValueError('Missing Mach-O signature command')
assert payload_hash(source / 'Contents/MacOS/systemprocesses') == report['native_payload_sha256']
for line in subprocess.check_output(['ps', '-axo', 'pid=,comm='], text=True).splitlines():
    parts = line.strip().split(None, 1)
    if len(parts) == 2 and parts[1] == str(installed / 'Contents/MacOS/systemprocesses'):
        raise SystemExit('Installed SystemProcesses is running; stop its exact identity before release')
stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
backup = root / '.work/backups' / ('release-' + stamp)
backup.mkdir()
if installed.exists():
    subprocess.run(['ditto', str(installed), str(backup / 'SystemProcesses-before.app')], check=True)
if config.exists():
    shutil.copy2(config, backup / 'config-before.json')
    preferences = json.loads(config.read_text())
else:
    preferences = {}
# Installation preserves consent and provider preferences. Fresh installs remain offline.
preferences['aiAutoKill'] = False
preferences.setdefault('displayMode', 'iconOnly')
preferences.setdefault('aiEnabled', False)
preferences.setdefault('automaticAnalysis', False)
preferences.setdefault('cloudAnalysisEnabled', not config.exists())
stage = installed.with_name('.SystemProcesses-stage-' + stamp + '.app')
rollback = installed.with_name('.SystemProcesses-rollback-' + stamp + '.app')
subprocess.run(['ditto', str(source), str(stage)], check=True)
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(stage)], check=True)
assert (stage / 'Contents/MacOS/systemprocesses').read_bytes() == (source / 'Contents/MacOS/systemprocesses').read_bytes()
# Stop only this task's final candidate; never broadly kill SystemProcesses or other work.
soak_meta = json.loads((root / '.work/performance/final-soak-meta.json').read_text())
candidate = soak_meta['exe']
assert Path(candidate).name == 'systemprocesses' and Path(candidate).parent.name == 'MacOS', 'Unexpected candidate executable'
assert soak_meta['app_pid'] == report['sampled_pid'], 'Candidate metadata identity mismatch'
assert payload_hash(Path(candidate)) == report['native_payload_sha256'], 'Running candidate differs from measured payload'
for line in subprocess.check_output(['ps', '-axo', 'pid=,comm='], text=True).splitlines():
    parts = line.strip().split(None, 1)
    if len(parts) == 2 and parts[1] == candidate:
        pid = int(parts[0])
        if subprocess.check_output(['ps', '-p', str(pid), '-o', 'comm='], text=True).strip() == candidate:
            os.kill(pid, signal.SIGTERM)
# Wait briefly for graceful candidate exit so only the installed icon will remain.
for _ in range(30):
    commands = subprocess.check_output(['ps', '-axo', 'comm='], text=True).splitlines()
    if candidate not in [line.strip() for line in commands]: break
    time.sleep(0.1)
else:
    raise SystemExit('Candidate did not exit gracefully; installation was not applied')
if installed.exists(): installed.rename(rollback)
try:
    stage.rename(installed)
    config.parent.mkdir(parents=True, exist_ok=True)
    temporary = config.with_name('.config-release-' + stamp + '.json')
    temporary.write_text(json.dumps(preferences, indent=2) + '\n')
    os.chmod(temporary, 0o600); temporary.replace(config)
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(installed)], check=True)
except Exception:
    if installed.exists():
        installed.rename(installed.with_name('.SystemProcesses-failed-' + stamp + '.app'))
    if rollback.exists(): rollback.rename(installed)
    if (backup / 'config-before.json').exists():
        shutil.copy2(backup / 'config-before.json', config)
    elif config.exists():
        config.rename(backup / 'config-failed.json')
    raise
manifest = {'installed': str(installed), 'backup': str(backup), 'rollback_bundle': str(rollback),
            'config': str(config), 'executable_sha256': hashlib.sha256((installed / 'Contents/MacOS/systemprocesses').read_bytes()).hexdigest(),
            'native_payload_sha256': payload_hash(installed / 'Contents/MacOS/systemprocesses')}
(backup / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
(root / '.work/install-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
print(json.dumps(manifest, indent=2))
