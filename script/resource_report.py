#!/usr/bin/env python3
"""Summarize observed app resources; incomplete samples cannot pass acceptance."""
import hashlib, json, statistics, struct
from pathlib import Path
root = Path(__file__).resolve().parents[1]
path = root / '.work/performance/final-30min-soak.jsonl'
sample_bytes = path.read_bytes()
samples = [json.loads(line) for line in sample_bytes.decode().splitlines()]
assert len(samples) > 1
required = ['time','pid','process_start_abstime','process_uuid','rss_bytes','cpu_seconds',
            'interrupt_wakeups','package_idle_wakeups']
assert all(all(key in sample for key in required) for sample in samples), 'Missing required resource telemetry'
identities = {(s['pid'], s['process_start_abstime'], s['process_uuid']) for s in samples}
assert len(identities) == 1, 'Mixed process identities in resource samples'
assert all('retained_history' in sample and 'menu_shown' in sample for sample in samples[2:]), 'Missing UI/history telemetry'
meta = json.loads((root / '.work/performance/final-soak-meta.json').read_text())
assert samples[0]['pid'] == meta['app_pid'], 'Samples belong to a different process'
assert samples[0]['time'] >= meta['measurement_started'], 'Samples predate the measurement'

start, end = samples[0], samples[-1]
duration = end['time'] - start['time']
gaps = [b['time'] - a['time'] for a, b in zip(samples, samples[1:])]
coverage = len(samples) >= 330 and all(0 < gap <= 15 for gap in gaps)
cpu = (end['cpu_seconds'] - start['cpu_seconds']) / duration * 100
# Compare medians of the settled first and last five minutes; also retain raw extremes.
settled = [s for s in samples if s['time'] >= start['time'] + 60]
early = [s['rss_bytes'] for s in settled if s['time'] <= start['time'] + 360]
late = [s['rss_bytes'] for s in samples if s['time'] >= end['time'] - 300]
growth = (statistics.median(late) - statistics.median(early)) / 1048576
rss = [s['rss_bytes'] / 1048576 for s in settled]
closed = all(s.get('menu_shown') is False for s in samples[2:])
blob = (root / '.work/performance/SystemProcessesFinal.app/Contents/MacOS/systemprocesses').read_bytes()
pos = 32; payload = None
for _ in range(struct.unpack_from('<I', blob, 16)[0]):
    command, size = struct.unpack_from('<II', blob, pos)
    if command == 0x1d:
        offset, _ = struct.unpack_from('<II', blob, pos + 8)
        payload = hashlib.sha256(blob[:offset]).hexdigest()
    pos += size
assert payload == meta['native_payload_sha256'], 'Candidate changed during measurement'
report = {'samples_sha256': hashlib.sha256(sample_bytes).hexdigest(), 'sampled_pid': samples[0]['pid'],
          'process_start_abstime': samples[0]['process_start_abstime'], 'process_uuid': samples[0]['process_uuid'], 'samples': len(samples), 'duration_seconds': duration,
          'max_sample_gap_seconds': max(gaps), 'continuous_coverage_passed': coverage,
          'cpu_percent_one_core': cpu, 'rss_mib_median': statistics.median(rss),
          'rss_mib_min': min(rss), 'rss_mib_max': max(rss),
          'rss_mib_settled_growth': growth, 'menu_closed_confirmed': closed,
          'history_max': max(s['retained_history'] for s in samples[2:]),
          'interrupt_wakeups_per_second': (end['interrupt_wakeups'] - start['interrupt_wakeups']) / duration,
          'package_idle_wakeups_per_second': (end['package_idle_wakeups'] - start['package_idle_wakeups']) / duration,
          'native_payload_sha256': payload,
          'acceptance_passed': duration >= 1800 and coverage and closed and cpu < 1 and max(rss) < 100 and growth <= 10 and max(s['retained_history'] for s in samples[2:]) <= 512}
# Attribute energy only to the exact process sampled in this release soak.
valid = [s for s in samples if 'kernel_energy_nj' in s]
if len(valid) > 1:
    a, b = valid[0], valid[-1]
    delta = b['kernel_energy_nj'] - a['kernel_energy_nj']
    report['kernel_estimated_energy'] = {
        'duration_seconds': b['time'] - a['time'], 'delta_nj': delta,
        'counter_available': b['kernel_energy_nj'] > 0,
        'note': 'Kernel process estimate; excludes shared model services and is not a direct power or battery measurement.'}
(root / '.work/performance/final-resource-report.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report, indent=2))
