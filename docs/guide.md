# User guide

System Processes keeps a compact process list in a menu bar popup. Its details are intended to help you decide what deserves attention; they cannot establish that a process is safe to stop or abandoned.

## Open and close the popup

Click the menu bar button to open the popup. The **Icon** display option uses a compact three-line button without metric text. Click the button again, click outside the popup, or press Escape to close it. Closing also cancels an in-progress model lookup or AI request.

## Read process details

Use the search field to narrow the list. Select a row to expand its details, including the observed owner, process age, CPU sample, memory footprint, parent, and any measured memory growth. History is collected locally in memory, is bounded, and can cover up to an hour. Growth is an observation, not proof of a leak. An exited parent does not prove that a child is abandoned.

**Group helpers** changes how helper processes are displayed. It does not change which process a stop targets: a grouped row targets only its displayed parent process.

Use **Ignore AI** to exclude an executable from recommendations. Use **Protect** to block stop controls for an executable. These are separate choices: ignoring a process does not protect it from a manual stop.

## Stop a process

Select the stop control on an eligible row, then confirm the graceful stop. The app checks the process identity again before acting. If the process remains, a force stop may become available after the graceful attempt; force requires its own confirmation. Stopping can interrupt work or lose unsaved data. System-protected processes do not expose stop controls.

AI produces recommendations only. It never stops a process for you.

The app does not inspect executable files or icons in personal folders or mounted private disks. A task can still appear in the list with its basic system measurements, but its stop control stays blocked when file identity cannot be verified. You do not need to grant Documents access to use the normal menu.

## Memory readings

The popup uses the operating system's memory-pressure signal and reports memory counters separately. Its bar represents non-free physical pages, which is a different calculation from Activity Monitor's “Memory Used” value. When counters are unavailable, pressure or readings may be shown as unavailable instead of inferred from another metric.

## Settings help

Three information buttons in Settings open short explanations for AI recommendations, automatic analysis, and cloud process evidence. Use them when deciding whether to enable recommendations or allow cloud requests.

AI recommendations and automatic analysis start off. A fresh setup selects Hybrid with an Ollama Cloud model and has cloud sharing ready for when you enable AI, so you do not need a separate cloud-sharing confirmation. If saved settings show sharing off, the app preserves that choice. Older saved configurations without a cloud-sharing choice also remain off; they are not opted in.

When you enable AI with Hybrid, Ollama Cloud, or Apple on-device selected, Settings looks up available model IDs. This is model discovery only: it does not run inference or send process details. Opening Settings alone stays local. Later model-list checks use the **Refresh** button.

## Build and troubleshooting

A source build requires macOS 13 or later and an Apple Swift toolchain with the macOS SDK. It targets the current Mac architecture. If Swift is not available, Apple's Command Line Tools can be installed with `xcode-select --install`. Run these commands from the repository root:

```bash
bash build.sh
open SystemProcesses.app
```

The build script looks for Apple's Foundation Models macro plugin. When it finds the plugin, it includes the on-device model integration. If it does not, the script compiles with on-device analysis disabled while retaining the core app and cloud providers. Apple on-device analysis requires macOS 26 or later, the framework and macro plugin at build time, and an available system model at runtime.

For the regression checks, run:

```bash
bash script/test.sh
```

The checks launch a temporary macOS test app and use synthetic process fixtures and provider responses. They do not require a live AI account. If the app does not appear, confirm the build completed and that macOS allowed the app to open. If model discovery fails, check the selected provider's account access, API key, and endpoint in Settings; the current model selection is retained when discovery fails.

For provider setup, API-key storage, cloud data, and on-device availability, see [AI providers](ai-providers.md).
