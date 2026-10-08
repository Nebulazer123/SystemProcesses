import Foundation

/// Pure decoding and normalization for provider model-list responses.
/// Network access, provider URLs, and credentials intentionally live elsewhere.
enum ModelCatalog {
    static let maximumResponseBytes = 2 * 1024 * 1024
    static let maximumModels = 500
    static let maximumIdentifierLength = 200

    /// The Apple Foundation Models framework exposes a system-selected model,
    /// rather than a remotely enumerable model catalog.
    static let appleModelIdentifiers = ["SystemLanguageModel.default"]

    static func decode(data: Data, provider: String) throws -> [String] {
        guard data.count <= maximumResponseBytes else {
            throw AIFailure(message: "Provider model list is too large.")
        }
        guard let root = try? JSONSerialization.jsonObject(with: data),
              let object = root as? [String: Any] else {
            throw AIFailure(message: "Provider returned an invalid model list.")
        }

        if let status = object["status"], !isSuccessfulStatus(status) {
            throw AIFailure(message: "Provider reported a model-list error.")
        }
        if object["error"] != nil {
            throw AIFailure(message: "Provider reported a model-list error.")
        }

        let key: String
        switch provider.lowercased() {
        case "ollama": key = "models"
        case "openai", "openrouter", "openai-compatible", "openaicompatible",
             "custom", "custom-openai", "custom-openai-compatible": key = "data"
        case "anthropic": key = "data"
        case "apple": return appleModelIdentifiers
        default: throw AIFailure(message: "Model discovery is not supported for this provider.")
        }

        guard let entries = object[key] as? [Any] else {
            throw AIFailure(message: "Provider returned an invalid model-list envelope.")
        }

        var identifiers: [String] = []
        identifiers.reserveCapacity(min(entries.count, maximumModels))
        var seen = Set<String>()
        for entry in entries {
            guard let row = entry as? [String: Any] else { continue }
            let raw: String?
            if provider.lowercased() == "ollama" {
                raw = (row["name"] as? String) ?? (row["model"] as? String)
            } else {
                raw = row["id"] as? String
            }
            guard let identifier = raw, isValidIdentifier(identifier), seen.insert(identifier).inserted else { continue }
            identifiers.append(identifier)
        }
        return Array(identifiers.sorted().prefix(maximumModels))
    }

    /// Removes malformed and duplicate identifiers, sorts predictably, and
    /// retains a valid previously selected ID when a provider omits it.
    static func normalize(ids: [String], selected: String) -> [String] {
        var seen = Set<String>()
        var result = ids.filter { isValidIdentifier($0) && seen.insert($0).inserted }
            .sorted()
        result = Array(result.prefix(maximumModels))
        if isValidIdentifier(selected), !result.contains(selected) {
            if result.count >= maximumModels { result.removeLast() }
            result.append(selected)
            result.sort()
        }
        return Array(result.prefix(maximumModels))
    }

    private static func isSuccessfulStatus(_ status: Any) -> Bool {
        if let number = status as? NSNumber {
            return (200...299).contains(number.intValue)
        }
        if let value = status as? String {
            switch value.lowercased() {
            case "ok", "success", "successful", "complete", "completed": return true
            default: return false
            }
        }
        return false
    }

    private static func isValidIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= maximumIdentifierLength else { return false }
        return value.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 48...57, 65...90, 97...122, 58, 47, 45, 46, 95: return true
            default: return false
            }
        }
    }
}
