func modelCatalogChecks(check: (Bool, String) -> Void) {
    func decode(_ json: String, provider: String) -> [String]? {
        try? ModelCatalog.decode(data: Data(json.utf8), provider: provider)
    }

    check(decode(#"{"models":[{"name":"gemma3:4b"},{"model":"llama3.2:latest"}]}"#, provider: "ollama") == ["gemma3:4b", "llama3.2:latest"],
          "Ollama model names and model fallback are decoded")
    check(decode(#"{"object":"list","data":[{"id":"gpt-4o"},{"id":"openai/model-v2"}]}"#, provider: "openai") == ["gpt-4o", "openai/model-v2"],
          "OpenAI model-list IDs are decoded")
    check(decode(#"{"data":[{"id":"provider/model"}]}"#, provider: "OpenRouter") == ["provider/model"] &&
          decode(#"{"data":[{"id":"local-model_v1"}]}"#, provider: "custom-openai-compatible") == ["local-model_v1"],
          "OpenRouter and custom compatible model-list IDs are decoded")
    check(decode(#"{"data":[{"id":"claude-sonnet-4"}]}"#, provider: "anthropic") == ["claude-sonnet-4"],
          "Anthropic model-list IDs are decoded")
    check(ModelCatalog.appleModelIdentifiers == ["SystemLanguageModel.default"] &&
          decode(#"{}"#, provider: "apple") == ["SystemLanguageModel.default"],
          "Apple exposes its static system model identifier")

    check(decode(#"{"models":[]}"#, provider: "ollama") == [], "A valid empty catalog is accepted")
    check(decode(#"{"models":[{"name":"zeta"},{"name":"alpha"},{"model":"alpha"},{"name":"bad name"},{"name":"line\nbreak"},{"name":"bad\u0000id"},null,7]}"#, provider: "ollama") == ["alpha", "zeta"],
          "Malformed rows, duplicate IDs, whitespace, and control-like IDs are skipped")

    let malformed = try? ModelCatalog.decode(data: Data("not json".utf8), provider: "ollama")
    let wrongRoot = try? ModelCatalog.decode(data: Data(#"[{"name":"not-an-envelope"}]"#.utf8), provider: "ollama")
    let wrongEnvelope = try? ModelCatalog.decode(data: Data(#"{"items":[{"id":"model"}]}"#.utf8), provider: "openai")
    let failedStatus = try? ModelCatalog.decode(data: Data(#"{"status":503,"data":[]}"#.utf8), provider: "openai")
    check(malformed == nil && wrongRoot == nil && wrongEnvelope == nil && failedStatus == nil,
          "Malformed JSON, roots, envelopes, and failed status are rejected")
    check((try? ModelCatalog.decode(data: Data(#"{"status":"ok","data":[]}"#.utf8), provider: "openai")) == [],
          "Successful status metadata is accepted")
    let oversized = Data(repeating: 32, count: ModelCatalog.maximumResponseBytes + 1)
    check((try? ModelCatalog.decode(data: oversized, provider: "ollama")) == nil,
          "Oversized catalog responses are rejected before parsing")

    let normalized = ModelCatalog.normalize(ids: ["zeta", "alpha", "alpha", "bad id", "tool/model"], selected: "missing-model:v2")
    check(normalized == ["alpha", "missing-model:v2", "tool/model", "zeta"],
          "Dropdown models are deduplicated, sorted, and keep a missing current selection")
    let bounded = ModelCatalog.normalize(ids: (0..<ModelCatalog.maximumModels).map { "model-\($0)" }, selected: "current-unlisted")
    check(bounded.count == ModelCatalog.maximumModels && bounded.contains("current-unlisted"),
          "Catalog normalization caps IDs while preserving current selection")
    check(ModelCatalog.normalize(ids: [], selected: "bad\nmodel").isEmpty,
          "Unsafe current selection is not added to the dropdown")
}
