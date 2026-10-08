# AI providers

AI recommendations and automatic analysis both start off. A fresh configuration selects Hybrid and an Ollama Cloud model, with cloud process sharing ready for when you enable AI. Process monitoring, search, history, and manual stop controls work without AI. Recommendations never stop a process.

## Quick setup with Ollama

1. [Download Ollama for Mac](https://ollama.com/download/mac), open it, and sign in to your account.
2. Choose a cloud model in Ollama, such as [Gemma 4 31B Cloud](https://ollama.com/library/gemma4:31b-cloud). Cloud models run online without downloading local weights.
3. Open System Processes **Settings** and turn on **Enable AI recommendations**. Keep **Hybrid** selected; the app looks up your models automatically. Use **Refresh** if you added a model later.
4. Return to the process list and click **AI** for a check. Automatic checks are optional and can be enabled separately.

Keep Ollama running while using this route. Account limits still apply. See [Ollama's cloud setup guide](https://docs.ollama.com/cloud) if sign-in or cloud access is unavailable.

## Hybrid, the default

Each request considers up to 30 candidates. When OS memory pressure is normal and Apple's on-device model is available, Hybrid asks Apple to review up to eight candidates first, then sends the remaining candidates to the selected Ollama Cloud model. The stages run in order. Each request is bounded by a 30-second total deadline.

When pressure is warning, critical, or unavailable, or the Apple model is unavailable, Hybrid sends all candidates to the selected Ollama Cloud model. The result says when Apple was skipped and cloud reviewed all candidates. If an Apple review starts but fails, Hybrid reports the failure and does not retry that work in the cloud.

In a fresh configuration, cloud sharing is ready but AI is off. Turn on AI to use Hybrid; the app then looks up available model IDs without running inference or sending process details. Opening Settings alone makes no network request, and later model-list checks remain manual with **Refresh**. Sign in to Ollama with your own account if needed.

An existing configuration with cloud sharing explicitly turned off keeps that choice. A saved configuration that predates this setting also remains off; the app does not silently opt it in. Hybrid cannot run a cloud stage until sharing is turned on. Select Apple on-device for local-only recommendations; that mode does not require cloud sharing. It remains subject to system model availability and memory pressure.

## Choose and check a model

In Settings, enable AI recommendations and choose a provider. Enabling AI automatically looks up available model IDs for Hybrid, Ollama Cloud, and Apple on-device. The cloud lookup requests a model catalog only; it does not run inference or send process details. Opening Settings does not make a network request. For later checks, click **Refresh** beside **Model**. You can also enter a model ID yourself. Discovery checks which IDs the provider lists, but a listed model may not support the app's request format or be available to your account. A failed request does not switch providers automatically.

Changing provider or custom endpoint turns off automatic analysis. Enable it again in Settings if you want automatic recommendations.

## Available providers

| Provider | What it needs | Notes |
| --- | --- | --- |
| Ollama Cloud | A signed-in Ollama server with cloud access | Uses cloud model tags available to that account; no local model weights are downloaded by the app. |
| Apple on-device | A compatible Mac with an available system model | Uses Apple's built-in model without an API key. Automatic analysis pauses unless pressure is normal. Availability depends on macOS, the build toolchain, and the device. |
| OpenAI API, Anthropic API, DeepSeek API, xAI API, OpenRouter | Your provider API key | API usage may be billed by that provider; it is separate from any app or chat subscription. |
| Custom OpenAI-compatible | Your API base URL and API key | Use HTTPS. Plain HTTP is accepted only for localhost. The endpoint must support the compatible model-list and chat-completions routes. |
| OpenCode Go | No runtime setup is available | Disabled until permission covers this standalone process-analysis workload. |

Model discovery and inference compatibility vary by provider. The app does not guarantee that every detected model will work.

## Save an API key

For a key-based provider, paste the key into the masked **API key** field and select **Save key**. The app stores its provider-and-endpoint credential in macOS Keychain, not in preferences or the process request body. **Remove** asks before deleting that saved entry. A custom endpoint uses its own key entry; changing the endpoint does not reuse the old endpoint's key. API access can incur provider charges; review pricing before use.

The app does not import credentials from another app. Keep the provider key current and check the provider's own billing and usage terms.

## Cloud data and local analysis

Cloud requests use the **Allow selected process evidence in cloud requests** option. A fresh configuration has this on, but AI itself starts off. Hybrid and other cloud providers send selected evidence such as process names, PIDs, resource readings, age bands, owner labels, and activity or growth signals. The app excludes command lines, environment variables, full executable paths, and private files. Review the selected provider's data handling terms before requesting cloud analysis. You can turn sharing off in Settings; saved opt-outs and older configurations without a saved choice remain off.

Apple on-device analysis uses the system model available on that Mac. It can use additional memory; automatic Apple analysis pauses while pressure is elevated or critical. A manual request may still proceed after a warning.

## Automatic recommendations

Automatic analysis is optional and can be enabled separately. It considers sustained pressure, observed memory growth, and large processes with context. It is limited to six requests per day with a ten-minute cooldown. It pauses if its usage history cannot be read or saved. These controls affect recommendations only; stopping remains a manual action.
