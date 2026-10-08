# Contributing

Changes to documentation, bug reports, and focused pull requests are welcome. Please describe the macOS version and steps that reproduce a behavior issue. Do not include API keys, private process details, or other sensitive information in reports.

## Build

Use macOS with an Apple Swift toolchain and the macOS SDK. From the repository root:

```bash
bash build.sh
open SystemProcesses.app
```

The optional Foundation Models integration requires an SDK that contains `FoundationModels` and its matching Swift macro plugin. A Command Line Tools installation without those components is insufficient for that integration.

## Regression checks

Run the macOS regression app with:

```bash
bash script/test.sh
```

The script builds and opens a temporary test app, uses synthetic process fixtures and stubbed provider responses, and reports the checks in its output. No live provider account is needed. Close the test app if it remains open after the checks finish.

When changing process handling, preserve the distinction between observed evidence and conclusions: memory growth does not prove a leak, and parent exit does not prove abandonment. Process stopping remains a confirmed user action.

## License

Contributions are made under the project's [MIT License](LICENSE).
