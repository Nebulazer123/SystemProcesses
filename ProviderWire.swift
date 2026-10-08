import Foundation
import Security
import CryptoKit

enum ProviderCredentials {
    static func exists(account: String) -> Bool {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "app.systemprocesses.providers", kSecAttrAccount as String: account]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }
    static func remove(account: String) throws {
        let status = SecItemDelete([kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "app.systemprocesses.providers", kSecAttrAccount as String: account] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw AIFailure(message: "Could not remove this provider key from Keychain.") }
    }
    static func read(account: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "app.systemprocesses.providers",
            kSecAttrAccount as String: account, kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func store(_ value: String, account: String) throws {
        guard !value.isEmpty, value.utf8.count <= 8192,
              value.unicodeScalars.allSatisfy({ (33...126).contains($0.value) }) else { throw AIFailure(message: "Enter an API key without spaces or control characters.") }
        let key: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "app.systemprocesses.providers", kSecAttrAccount as String: account]
        let attributes: [String: Any] = [kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        var status = SecItemUpdate(key as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound { status = SecItemAdd(key.merging(attributes) { _, b in b } as CFDictionary, nil) }
        guard status == errSecSuccess else { throw AIFailure(message: "Could not store provider credential in Keychain.") }
    }
}

extension AIProvider {
    static let choices: [AIProvider] = [.hybrid, .ollama, .apple, .openai, .anthropic, .deepseek, .xai, .openrouter, .compatible, .opencodeGo]
    var title: String {
        switch self {
        case .hybrid: return "Hybrid · Apple + Ollama Cloud"
        case .ollama: return "Ollama Cloud"
        case .apple: return "Apple on-device"
        case .openai: return "OpenAI API"
        case .anthropic: return "Anthropic API"
        case .deepseek: return "DeepSeek API"
        case .xai: return "xAI API"
        case .openrouter: return "OpenRouter"
        case .compatible: return "Custom OpenAI-compatible"
        case .opencodeGo: return "OpenCode Go — permission required"
        }
    }
    var needsKey: Bool { ![.hybrid, .ollama, .apple, .opencodeGo].contains(self) }
    var defaultBase: String {
        switch self {
        case .openai: return "https://api.openai.com/v1"
        case .anthropic: return "https://api.anthropic.com/v1"
        case .deepseek: return "https://api.deepseek.com/v1"
        case .xai: return "https://api.x.ai/v1"
        case .openrouter: return "https://openrouter.ai/api/v1"
        default: return ""
        }
    }
}

enum APIWire {
    static func base(provider: AIProvider, custom: String) throws -> URL {
        let text = (provider == .compatible ? custom : provider.defaultBase).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: text), let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.scheme == "https" || (url.scheme == "http" && ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host.lowercased())),
              !url.pathComponents.contains("..") else { throw AIFailure(message: "Use a clean HTTPS API base URL, or HTTP on localhost. No URL credentials or query parameters.") }
        return url
    }
    static func account(provider: AIProvider, custom: String) throws -> String {
        if provider != .compatible { return provider.rawValue }
        let normalized = try base(provider: provider, custom: custom).absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return "compatible:" + SHA256.hash(data: Data(normalized.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    static func authorize(_ request: inout URLRequest, provider: AIProvider, key: String) throws {
        guard !key.isEmpty, key.utf8.count <= 8192, key.unicodeScalars.allSatisfy({ (33...126).contains($0.value) }) else { throw AIFailure(message: "Save an API key for this provider in Settings first.") }
        if provider == .anthropic {
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        } else { request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization") }
    }
    static func models(provider: AIProvider, custom: String, ollama: String, key: String) throws -> URLRequest {
        guard provider != .opencodeGo && provider != .apple else { throw AIFailure(message: "This provider has no remote catalog available to SystemProcesses.") }
        var url: URL
        if provider == .ollama {
            guard let base = URL(string: ollama), let host = base.host,
                  base.user == nil, base.password == nil, base.query == nil, base.fragment == nil,
                  base.scheme == "https" || (base.scheme == "http" && ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host.lowercased())) else { throw AIFailure(message: "Check the Ollama server URL.") }
            url = base.appendingPathComponent("api/tags")
        } else {
            url = try base(provider: provider, custom: custom).appendingPathComponent("models")
            if provider == .anthropic {
                var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
                components.queryItems = [URLQueryItem(name: "limit", value: "500")]; url = components.url!
            }
        }
        var request = URLRequest(url: url); request.timeoutInterval = 15
        if provider.needsKey && (provider != .openrouter || !key.isEmpty) { try authorize(&request, provider: provider, key: key) }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
    static func request(provider: AIProvider, custom: String, model: String, key: String, instructions: String, prompt: String) throws -> URLRequest {
        guard provider.needsKey else { throw AIFailure(message: "Unsupported API provider.") }
        let route = provider == .openai ? "responses" : provider == .anthropic ? "messages" : "chat/completions"
        var request = URLRequest(url: try base(provider: provider, custom: custom).appendingPathComponent(route))
        request.httpMethod = "POST"; request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try authorize(&request, provider: provider, key: key)
        var body: [String: Any] = ["model": model, "stream": false]
        if provider == .openai {
            body["instructions"] = instructions; body["input"] = prompt
            body["max_output_tokens"] = 2048; body["store"] = false
        } else if provider == .anthropic {
            body["system"] = instructions; body["messages"] = [["role": "user", "content": prompt]]; body["max_tokens"] = 2048
        } else {
            body["messages"] = [["role": "system", "content": instructions], ["role": "user", "content": prompt]]; body["max_tokens"] = 2048
            if provider == .deepseek { body["thinking"] = ["type": "disabled"] }
            if provider == .openrouter { body["provider"] = ["allow_fallbacks": false] }
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }
}

// Limits bytes while receiving, rather than accepting an unbounded body first.
final class BoundedHTTP: NSObject, URLSessionDataDelegate {
    private var session: URLSession!
    private var task: URLSessionDataTask!
    private var bytes = Data()
    private var response: HTTPURLResponse?
    private var oversized = false
    private let limit: Int
    private let completion: (Data?, HTTPURLResponse?, Error?) -> Void
    init(request: URLRequest, limit: Int, configuration: URLSessionConfiguration? = nil, completion: @escaping (Data?, HTTPURLResponse?, Error?) -> Void) {
        self.limit = limit; self.completion = completion
        super.init()
        let settings = configuration ?? URLSessionConfiguration.ephemeral
        settings.urlCache = nil; settings.httpCookieStorage = nil; settings.urlCredentialStorage = nil
        settings.httpShouldSetCookies = false
        settings.timeoutIntervalForRequest = request.timeoutInterval; settings.timeoutIntervalForResource = request.timeoutInterval
        session = URLSession(configuration: settings, delegate: self, delegateQueue: nil)
        task = session.dataTask(with: request); task.resume()
    }
    func cancel() { task.cancel(); session.invalidateAndCancel() }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        self.response = response as? HTTPURLResponse
        oversized = response.expectedContentLength > Int64(limit)
        completionHandler(oversized ? .cancel : .allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard !oversized else { return }
        guard data.count <= limit - bytes.count else { oversized = true; dataTask.cancel(); return }
        bytes.append(data)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let finalError = oversized ? NSError(domain: "SystemProcessesBoundedHTTP", code: 1) : error
        completion(oversized ? nil : bytes, response, finalError)
        session.finishTasksAndInvalidate()
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

protocol ModelDiscovering {
    func fetch(_ request: URLRequest, provider: AIProvider, completion: @escaping (Result<[String], AIFailure>) -> Void) -> AnalysisTask
    func close()
}

final class ModelDiscovery: ModelDiscovering {
    private var active: BoundedHTTP?
    func fetch(_ request: URLRequest, provider: AIProvider, completion: @escaping (Result<[String], AIFailure>) -> Void) -> AnalysisTask {
        active?.cancel()
        let transport = BoundedHTTP(request: request, limit: ModelCatalog.maximumResponseBytes) { data, response, error in
            let result: Result<[String], AIFailure>
            if error != nil { result = .failure(AIFailure(message: "Model discovery failed or timed out. Your current model is kept.")) }
            else if let status = response?.statusCode, (200..<300).contains(status), let data = data {
                do {
                    let kind = [.deepseek, .xai, .compatible].contains(provider) ? "openai" : provider.rawValue
                    var ids = try ModelCatalog.decode(data: data, provider: kind)
                    if provider == .ollama { ids = ids.filter(isCloudModel) }
                    result = .success(ids)
                } catch { result = .failure(error as? AIFailure ?? AIFailure(message: "Invalid model catalog.")) }
            } else { result = .failure(AIFailure(message: "Model catalog unavailable. Check the API key, endpoint, or account access.")) }
            DispatchQueue.main.async { completion(result) }
        }
        active = transport
        return AnalysisTask { transport.cancel() }
    }
    func close() { active?.cancel(); active = nil }
}

// Pure adapters for future permitted use. Runtime eligibility is enforced before credential access.
enum GoWireAdapter {
    static func request(model: String, instructions: String, prompt: String, key: String, session: String) throws -> URLRequest {
        guard !key.isEmpty, !session.isEmpty else { throw AIFailure(message: "Missing provider credential or session.") }
        let responses = ["grok-4.7", "grok-4.6", "gpt-6-luna"].contains(model)
        let messages = ["claude-haiku-5-5", "qwen3.8-flash"].contains(model)
        let chats = ["deepseek-v4.1-flash", "glm-5.3-flash", "mimo-v2.6-flash", "longcat-2.5-preview-free"].contains(model)
        guard responses || messages || chats else { throw AIFailure(message: "Unsupported Go model identifier.") }
        let endpoint = responses ? "responses" : messages ? "messages" : "chat/completions"
        var request = URLRequest(url: URL(string: "https://opencode.ai/zen/go/v1/"+endpoint)!)
        request.httpMethod = "POST"; request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("SystemProcesses/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue(session, forHTTPHeaderField: "x-opencode-session")
        var body: [String: Any] = ["model": model, "stream": false]
        if responses {
            request.setValue("Bearer "+key, forHTTPHeaderField: "Authorization")
            body["instructions"] = instructions; body["input"] = prompt; body["max_output_tokens"] = 2048
            body["store"] = false
            // Reasoning controls remain omitted until the provider documents supported values.
        } else if messages {
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            body["system"] = instructions; body["messages"] = [["role":"user", "content":prompt]]
            body["max_tokens"] = 2048; body["temperature"] = 0
        } else {
            request.setValue("Bearer "+key, forHTTPHeaderField: "Authorization")
            body["messages"] = [["role":"system", "content":instructions], ["role":"user", "content":prompt]]
            body["max_tokens"] = 2048; body["temperature"] = 0
            if model.hasPrefix("deepseek-") { body["thinking"] = ["type":"disabled"] }
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }
    static func decode(_ envelope: [String: Any]) throws -> AIResp {
        let text: String
        if let choices = envelope["choices"] as? [[String: Any]], let first = choices.first {
            guard first["finish_reason"] as? String == "stop", let message = first["message"] as? [String: Any],
                  let content = message["content"] as? String else { throw AIFailure(message: "Incomplete Chat Completions answer.") }
            text = content
        } else if let content = envelope["content"] as? [[String: Any]] {
            guard envelope["stop_reason"] as? String == "end_turn" else { throw AIFailure(message: "Incomplete Messages answer.") }
            text = content.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
        } else {
            guard envelope["status"] as? String == "completed", envelope["incomplete_details"] == nil || envelope["incomplete_details"] is NSNull,
                  let output = envelope["output"] as? [[String: Any]] else { throw AIFailure(message: "Incomplete Responses answer.") }
            text = output.filter { $0["type"] as? String == "message" }.flatMap { $0["content"] as? [[String: Any]] ?? [] }
                .filter { $0["type"] as? String == "output_text" }.compactMap { $0["text"] as? String }.joined()
        }
        var json = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if json.hasPrefix("```"), let newline = json.firstIndex(of: "\n"), json.hasSuffix("```") {
            json = String(json[json.index(after:newline)...].dropLast(3)).trimmingCharacters(in:.whitespacesAndNewlines)
        }
        guard var response = try? JSONDecoder().decode(AIResp.self, from: Data(json.utf8)), response.recommendations.count <= 30 else {
            throw AIFailure(message: "Invalid structured provider answer.")
        }
        let usage = envelope["usage"] as? [String: Any] ?? [:]
        let details = (usage["completion_tokens_details"] ?? usage["output_tokens_details"]) as? [String:Any] ?? [:]
        response.usage = AIUsage(inputTokens: (usage["prompt_tokens"] ?? usage["input_tokens"]) as? Int,
                                outputTokens: (usage["completion_tokens"] ?? usage["output_tokens"]) as? Int,
                                reasoningTokens: details["reasoning_tokens"] as? Int, cachedTokens: nil)
        return response
    }
}
