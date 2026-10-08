# System Processes

System Processes shows which apps and background tasks are using your Mac's memory, right from a small menu bar button. It also lets you kill background tasks easily, with a confirmation before stopping them. It automatically marks protected processes, active development work, and growing memory use; optional AI explains which tasks may need attention. Background checks can watch for sustained problems, while you stay in control of every stop.

[![Latest release](https://img.shields.io/github/v/release/Nebulazer123/SystemProcesses)](https://github.com/Nebulazer123/SystemProcesses/releases/latest)
[![macOS 13 or later](https://img.shields.io/badge/macOS-13%2B-333333)](#install)
[![MIT License](https://img.shields.io/badge/license-MIT-333333)](LICENSE)

<table>
  <tr>
    <th>Find the task that needs attention</th>
    <th>Choose your AI and display settings</th>
  </tr>
  <tr>
    <td width="50%" valign="top"><a href="docs/assets/processes.png"><img src="docs/assets/processes.png" alt="Process popup with memory readings, search, ownership labels, and protected tasks" width="100%"></a></td>
    <td width="50%" valign="top"><a href="docs/assets/settings.png"><img src="docs/assets/settings.png" alt="Settings with a provider dropdown, model selection, and AI controls" width="100%"></a></td>
  </tr>
</table>

*App screenshots use synthetic example tasks and readings. Click either image for a larger view.*

**[Download for Apple Silicon](https://github.com/Nebulazer123/SystemProcesses/releases/download/v1.0.0/SystemProcesses-1.0.0-macOS-arm64.zip)** · **[Let a coding agent set it up](#set-it-up-with-an-ai-coding-agent)** · **[How to use](#how-to-use)**

## Install

**Apple Silicon Mac:**

1. [Download System Processes 1.0.0](https://github.com/Nebulazer123/SystemProcesses/releases/download/v1.0.0/SystemProcesses-1.0.0-macOS-arm64.zip) and unzip it.
2. Move **SystemProcesses.app** to **Applications** and open it.
3. Click the three-line menu bar button. You can search and stop eligible tasks immediately; AI setup is optional.

This build is ad-hoc signed, not notarized. If macOS blocks the first launch, follow [Apple’s first-launch instructions](https://support.apple.com/102445).

**Build from source:**

Requires macOS 13 or later, Python 3, and an Apple Swift toolchain with the macOS SDK. The build targets your Mac's current architecture. If Swift is not available, install Apple's Command Line Tools with `xcode-select --install`.

```bash
git clone https://github.com/Nebulazer123/SystemProcesses.git
cd SystemProcesses
bash build.sh
open SystemProcesses.app
```

The build checks for Apple's Foundation Models macro plugin. Without it, the core app and cloud providers still build, while Apple on-device analysis is disabled. Apple on-device analysis needs macOS 26 or later, a compatible system model, and a toolchain with the macro plugin.

## Set it up with an AI coding agent

Want the agent to do the setup for you? Copy the whole prompt below into an AI coding agent with terminal access to your Mac. It handles downloading or building, installation, preferences, and checks. You only choose the kind of AI you want and complete any account sign-in or macOS prompt it cannot handle.

```text
Install and fully set up System Processes on this Mac for me:
https://github.com/Nebulazer123/SystemProcesses

Carry out the work yourself. Do not hand me terminal commands or stop after making a plan. Ask only for choices, sign-in, credentials, or OS approval that you genuinely need from me. Continue through every step you can complete independently.

1. Inspect this Mac, any existing System Processes installation, and its saved preferences. Read the repository README and docs/ai-providers.md. Reuse a suitable existing checkout without resetting its changes. Back up the existing app and preferences before replacing them.

2. Install the current official release on Apple Silicon, checking its published SHA256SUMS.txt. On another supported Mac, build from source with bash build.sh. If you need a source checkout, clone the repository above. Install in /Applications, preserve a rollback copy, and launch exactly one installed instance. If a prerequisite is missing, handle what you can and ask me only for an unavoidable installer or macOS approval. Do not weaken macOS security settings.

3. Ask me one simple question if I have not already chosen: "Would you like AI advice using an online service, Apple-only advice that stays on your Mac, or no AI?" Explain that online advice sends selected task names and basic process readings to the chosen service. Recommend Hybrid for a mix of Apple and Ollama Cloud, or Ollama Cloud alone if I want the fastest measured route. Do not enable online analysis against an existing saved opt-out; ask whether I want to change that choice.

4. Complete the selected setup. For Hybrid or Ollama Cloud, install or open Ollama from its official Mac download, help me sign in if necessary, enable cloud access for this requested setup, and register gemma4:31b-cloud without downloading local weights. Turn on AI recommendations, discover available models, and select the model. Hybrid uses Apple for up to eight tasks when memory pressure is normal and Apple is available, then Ollama Cloud for the rest; otherwise it uses cloud for all candidates. For Apple-only, check that the installed build and system model support it; explain any missing requirement without silently choosing an online provider. For my own API service, ask which provider I want, use its model dropdown, and have me enter the key into the app's masked field for Keychain storage. Never ask me to paste a secret into this chat. Do not import other apps' credentials, buy credits, enable paid fallback, or download third-party model weights.

5. Set a compact icon-only menu button. Ask whether I want automatic AI checks only if I chose AI; if enabled, explain the limit of six checks per day, at least ten minutes apart. Preserve unrelated existing preferences. Never terminate real tasks as part of setup or testing.

6. Verify the installed executable, saved provider/model choices, and single running instance. Where computer access permits, check opening the popup, Settings and return, search, click-outside dismissal, and Escape. For AI setup, run one manual analysis through the selected route and inspect whether it completed with valid recommendations. If you built from source, run bash script/test.sh. Fix setup failures you can resolve, then continue. If GUI access, account access, or inference is unavailable, report the exact unverified step rather than calling it complete.

Finish with a short report: where the app is installed, which AI mode/model is active, what checks passed, where the backup is, and anything I still need to do. Include the three-line menu button as the next place to click.
```

## How to use

![Compact menu bar button](docs/assets/menu-button.png)

1. **Open the list.** Click the three-line menu bar button. Search by task name or sort by memory use to find the task you are looking for.
2. **Check the labels and details.** Select a row to see its likely owner, age, activity, parent, and recent memory growth. Protected tasks have no stop control. Active development and memory-growth labels help you spot work that needs a closer look; a large task is not automatically safe to kill.
3. **Get advice if you want it.** Enable AI in **Settings**, then click **AI** in the popup. Review its recommendations alongside the local evidence. Recommendations do not grant permission to stop a task.
4. **Stop an eligible task.** Click its stop control and confirm the graceful stop. If it remains running, a separate force-stop action can become available and requires another confirmation. Stopping may interrupt work or lose unsaved changes. A grouped row stops only its displayed parent.
5. **Keep important tasks protected.** Use **Protect** to block termination for an executable. Use **Ignore AI** to leave it out of recommendations; that does not block a manual stop.
6. **Close the popup.** Click the menu button again, click outside, or press Escape. It stays a menu bar app without a separate main window.

The overview reports macOS memory pressure separately from the bar, which represents non-free physical pages. Local history can cover up to an hour; detected growth is a reason to investigate, not proof of a memory leak. See the [user guide](docs/guide.md) for readings, stop controls, and troubleshooting.

## AI features

The process list and stop controls work without an AI account. AI recommendations and automatic checks start off; enable the features you want in **Settings**.

| Feature | What it does |
| --- | --- |
| **Enable AI recommendations** | Adds advice about apps and background tasks that may need attention. Click **AI** for a check. |
| **Analyze sustained problems** | Checks automatically when memory stays under pressure or a task's memory keeps growing. Runs at most six times a day, at least ten minutes apart. |
| **Allow selected process evidence in cloud requests** | Lets your selected online service receive task names and basic details such as memory use, activity, and likely owning app. Fresh setups have this ready; saved opt-outs are preserved. |

Use the information buttons beside these settings for short explanations.

### Pick an AI service

1. Turn on **Enable AI recommendations** and choose a **Provider**.
2. Use the **Model** dropdown to select a detected model. Hybrid, Ollama Cloud, and Apple look up models when AI is enabled; use **Refresh** for later checks or other providers.
3. For an API provider, enter your key in the masked **API key** field and click **Save key**. Keys are stored in macOS Keychain. API charges are separate from chat subscriptions.
4. Return to the list and click **AI** to check that the selected service works with your account.

| Choice | Setup and behavior |
| --- | --- |
| **Hybrid · Apple + Ollama Cloud** | Default selection. Sign in to Ollama and choose a cloud model. Apple reviews up to eight tasks when available and memory pressure is normal; the selected cloud model reviews the rest. Otherwise cloud reviews all candidates. |
| **Ollama Cloud** | Uses your signed-in Ollama account to review all selected tasks online. No local weights are downloaded. |
| **Apple on-device** | Keeps analysis on your Mac and needs no API key. Requires macOS 26 or later, a build with Foundation Models support, and an available system model. |
| **OpenAI, Anthropic, DeepSeek, xAI, OpenRouter** | Use your own provider API key and a model compatible with the app's request format. |
| **Custom OpenAI-compatible** | Enter your API base URL and key, then choose a model. Requires compatible model-list and chat-completions endpoints; use HTTPS, or localhost for a local server. |
| **OpenCode Go** | Runtime integration is currently disabled pending permission for standalone process analysis. |

Detected models can still be unavailable to your account or incompatible with the request format. The app reports failures without silently switching providers. Read [AI provider setup](docs/ai-providers.md) for Ollama sign-in, supported endpoints, cloud data, and troubleshooting.

## Help and license

Report reproducible issues at [GitHub Issues](https://github.com/Nebulazer123/SystemProcesses/issues), or report vulnerabilities privately using the [security policy](SECURITY.md). See [CONTRIBUTING.md](CONTRIBUTING.md) for the build and regression-check workflow. System Processes is available under the [MIT License](LICENSE).
