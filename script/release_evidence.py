#!/usr/bin/env python3
"""Bind successful tests and a production build to unchanged local inputs."""
import hashlib, json, sys
from pathlib import Path

root = Path(__file__).resolve().parents[1]
out = root / '.work/release-evidence'
out.mkdir(parents=True, exist_ok=True)
production = ['main.swift', 'Intelligence.swift', 'ProviderWire.swift', 'RuntimeState.swift',
              'AppleModel.swift', 'ModelCatalog.swift', 'build.sh', 'script/toolchain.sh', 'script/release_evidence.py',
              'script/Profile.swift', 'script/resource_report.py', 'script/install_candidate.py']
tests = production + ['Tests/regression.swift', 'Tests/intelligence.swift', 'Tests/security.swift', 'Tests/catalog.swift', 'Tests/providers.swift', 'Tests/transport.swift', 'script/test.sh']

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def inputs(names):
    return {name: digest(root / name) for name in names}

def save(name, value):
    (out / (name + '.json')).write_text(json.dumps(value, indent=2) + '\n')

def read(name):
    return json.loads((out / (name + '.json')).read_text())

mode = sys.argv[1]
if mode == 'before-build':
    save('build-start', inputs(production))
elif mode == 'after-build':
    current = inputs(production)
    assert current == read('build-start'), 'Build inputs changed while compiling'
    save('build', {'inputs': current, 'executable_sha256': digest(root / 'SystemProcesses.app/Contents/MacOS/systemprocesses')})
elif mode == 'before-test':
    save('test-start', inputs(tests))
elif mode == 'after-test':
    current = inputs(tests)
    assert current == read('test-start'), 'Test inputs changed while compiling or running'
    log = root / '.work/tests-current/checks.log'
    results = [json.loads(line.removeprefix('TEST_RESULT ')) for line in log.read_text().splitlines()
               if line.startswith('TEST_RESULT ')]
    assert results and results[-1].get('checks', 0) >= 210 and results[-1].get('failures') == 0, 'Release tests did not pass'
    save('tests', {'inputs': current, 'result': results[-1], 'checks_sha256': digest(log),
                   'test_executable_sha256': digest(root / '.work/tests-current/SystemProcessesQA.app/Contents/MacOS/systemprocesses')})
elif mode == 'verify':
    build, tested = read('build'), read('tests')
    assert build['inputs'] == inputs(production), 'Production source differs from the built inputs'
    assert tested['inputs'] == inputs(tests), 'Source or tests differ from the tested inputs'
    assert build['executable_sha256'] == digest(root / 'SystemProcesses.app/Contents/MacOS/systemprocesses'), 'Release executable changed'
    assert tested['checks_sha256'] == digest(root / '.work/tests-current/checks.log'), 'Test log changed'
    assert tested['test_executable_sha256'] == digest(root / '.work/tests-current/SystemProcessesQA.app/Contents/MacOS/systemprocesses'), 'Test executable changed'
    print('Source, production build, regression executable and passing log bindings verified.')
else:
    raise SystemExit('Unknown evidence operation')
