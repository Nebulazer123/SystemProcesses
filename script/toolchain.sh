#!/bin/bash
# Resolve a usable process-local toolchain; never change global Xcode selection.
if ! swiftc --version >/dev/null 2>&1; then
    if [[ -z "${DEVELOPER_DIR:-}" && -x /Library/Developer/CommandLineTools/usr/bin/swiftc ]] && DEVELOPER_DIR=/Library/Developer/CommandLineTools swiftc --version >/dev/null 2>&1; then
        export DEVELOPER_DIR=/Library/Developer/CommandLineTools
    else
        echo 'Swift is unavailable. Install Xcode or Command Line Tools and set DEVELOPER_DIR to that installation.' >&2
        return 1
    fi
fi
# Foundation Models macros ship with full Xcode. Core monitoring can build without them.
sp_apple_flags=(-D SYSTEMPROCESSES_NO_APPLE_MODEL)
sp_plugin_candidates=()
if [[ -n "${FOUNDATION_MODELS_PLUGIN_PATH:-}" ]]; then
    sp_plugin_candidates+=("$FOUNDATION_MODELS_PLUGIN_PATH")
fi
sp_developer="${DEVELOPER_DIR:-$(xcode-select -p 2>/dev/null || true)}"
sp_plugin_candidates+=("$sp_developer/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins")
for sp_app in /Applications/*.app; do
    sp_plugin_candidates+=("$sp_app/Contents/Developer/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins")
done
for sp_plugin in "${sp_plugin_candidates[@]}"; do
    if [[ -f "$sp_plugin/libFoundationModelsMacros.dylib" ]]; then
        sp_apple_flags=(-plugin-path "$sp_plugin")
        break
    fi
done
if [[ "${sp_apple_flags[0]}" == '-D' ]]; then
    echo 'Foundation Models macro plugin unavailable; building core app and cloud providers without on-device AI.' >&2
fi

# Older SDKs have no FoundationModels framework; do not ask their linker for it.
sp_apple_links=()
sp_sdk="$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)"
if [[ -d "$sp_sdk/System/Library/Frameworks/FoundationModels.framework" ]]; then
    sp_apple_links=(-Xlinker -weak_framework -Xlinker FoundationModels)
else
    sp_apple_flags=(-D SYSTEMPROCESSES_NO_APPLE_MODEL)
fi
