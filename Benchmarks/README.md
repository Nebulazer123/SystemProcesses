# Synthetic process benchmark

The fixtures cover protected system tasks, applications, development tools, background workers, memory growth, ambiguous ownership, reused process IDs, and misleading process names. They contain invented process identities and evidence.

Preview the cloud comparison without contacting a provider:

```bash
python3 Benchmarks/compare.py
```

Use `python3 Benchmarks/compare.py --help` for the bounded live-run options. A live run requires an explicitly selected, authorized provider account. Results are written under the ignored `.work/` directory. The harness does not inspect or upload the processes running on your Mac, purchase credits, or retry a provider error.

`script/benchmark.sh` also builds the optional Apple evaluation CLI when the framework is available. Model availability, account limits, and performance depend on the machine and provider. A small synthetic sample cannot establish a production accuracy guarantee.
