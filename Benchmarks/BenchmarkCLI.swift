import Foundation

enum AIVerdict: String, Codable { case safe, caution, critical }
struct AIRec: Codable { let pid: Int32; let verdict: AIVerdict; let reason: String }
struct AIResp: Codable { let recommendations: [AIRec]; let summary: String }

struct Input: Decodable { let provider: String; let prompt: String }
struct Output: Encodable {
    let provider: String
    let model: String
    let availability: String
    let latency_ms: Int?
    let first_event_ms: Int?
    let first_answer_ms: Int?
    let input_tokens: Int?
    let output_tokens: Int?
    let reasoning_tokens: Int?
    let completion_confirmed: Bool
    let raw: AIResp?
    let raw_content: String?
    let error: String?
}

private final class RejectRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

@main
struct BenchmarkCLI {
    static func main() async {
        var providerName = "unknown"
        do {
            let input = try JSONDecoder().decode(Input.self, from: FileHandle.standardInput.readDataToEndOfFile())
            providerName = input.provider
            let output: Output
            switch input.provider {
            case "apple": output = try await apple(input.prompt)
            case "ollama": output = try await ollama(input.prompt)
            case "availability":
                if #available(macOS 26.0, *) {
                    output = Output(provider: "apple", model: "SystemLanguageModel.default",
                        availability: AppleAnalyzer.availability, latency_ms: nil, first_event_ms: nil,
                        first_answer_ms: nil, input_tokens: nil, output_tokens: nil,
                        reasoning_tokens: nil, completion_confirmed: true, raw: nil, raw_content: nil, error: nil)
                } else {
                    output = Output(provider: "apple", model: "SystemLanguageModel.default",
                        availability: "unavailable: requires macOS 26", latency_ms: nil,
                        first_event_ms: nil, first_answer_ms: nil, input_tokens: nil,
                        output_tokens: nil, reasoning_tokens: nil, completion_confirmed: false,
                        raw: nil, raw_content: nil, error: "requires macOS 26")
                }
            default: throw NSError(domain: "Benchmark", code: 2, userInfo: [NSLocalizedDescriptionKey: "provider must be apple, ollama, or availability"])
            }
            let data = try JSONEncoder().encode(output)
            FileHandle.standardOutput.write(data); FileHandle.standardOutput.write(Data([10]))
        } catch {
            let out = Output(provider: providerName, model: "", availability: "unknown",
                latency_ms: nil, first_event_ms: nil, first_answer_ms: nil,
                input_tokens: nil, output_tokens: nil, reasoning_tokens: nil,
                completion_confirmed: false, raw: nil, raw_content: nil, error: String(describing: error))
            if let data = try? JSONEncoder().encode(out) {
                FileHandle.standardOutput.write(data); FileHandle.standardOutput.write(Data([10]))
            }
            exit(1)
        }
    }

    @available(macOS 26.0, *)
    static func apple(_ prompt: String) async throws -> Output {
        let start = ContinuousClock.now
        let result = try await AppleAnalyzer.analyze(prompt: prompt)
        let ms = Int(start.duration(to: .now).components.seconds * 1000
            + start.duration(to: .now).components.attoseconds / 1_000_000_000_000_000)
        return Output(provider: "apple", model: "SystemLanguageModel.default",
            availability: AppleAnalyzer.availability, latency_ms: ms,
            first_event_ms: nil, first_answer_ms: nil, input_tokens: nil,
            output_tokens: nil, reasoning_tokens: nil, completion_confirmed: true,
            raw: result, raw_content: nil, error: nil)
    }

    static func ollama(_ prompt: String) async throws -> Output {
        guard let url = URL(string: "http://localhost:11434/api/chat") else { fatalError("invalid URL") }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("SystemProcessesBenchmark/1.0", forHTTPHeaderField: "User-Agent")
        let body: [String: Any] = ["model": "gemma4:31b-cloud", "messages": [["role": "user", "content": prompt]],
            "stream": true, "think": false, "keep_alive": "60s", "options": ["temperature": 0, "num_predict": 2048]]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 30
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        let session = URLSession(configuration: configuration, delegate: RejectRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let start = DispatchTime.now().uptimeNanoseconds
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw NSError(domain: "Ollama", code: 1, userInfo: [NSLocalizedDescriptionKey: "No HTTP response"]) }
        guard (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "Ollama", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode); response body withheld"])
        }
        var firstEvent: Int?
        var firstAnswer: Int?
        var content = ""
        var finalEnvelope: [String: Any]?
        for try await line in bytes.lines {
            guard !line.isEmpty else { continue }
            let elapsed = Int((DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
            if firstEvent == nil { firstEvent = elapsed }
            let record = line.hasPrefix("data:") ? String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces) : line
            if record.isEmpty || record == "[DONE]" || (record.hasPrefix("#") && http.value(forHTTPHeaderField: "Content-Type")?.contains("text/event-stream") == true) { continue }
            guard let data = record.data(using: .utf8),
                  let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                let contentType = http.value(forHTTPHeaderField: "Content-Type") ?? "not provided"
                let firstByte = line.utf8.first.map { String(format: "%02X", $0) } ?? "none"
                throw NSError(domain: "Ollama", code: 2, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode); content-type \(contentType); malformed stream record (first byte 0x\(firstByte)); response body withheld"])
            }
            if let message = envelope["message"] as? [String: Any],
               let fragment = message["content"] as? String, !fragment.isEmpty {
                if firstAnswer == nil { firstAnswer = elapsed }
                content += fragment
            }
            if let delta = ((envelope["choices"] as? [[String: Any]])?.first?["delta"] as? [String: Any])?[
                "content"] as? String, !delta.isEmpty {
                if firstAnswer == nil { firstAnswer = elapsed }
                content += delta
            }
            if let serviceError = envelope["error"] as? String, !serviceError.isEmpty {
                throw NSError(domain: "Ollama", code: 3, userInfo: [NSLocalizedDescriptionKey: "Provider returned an error; body withheld"])
            }
            finalEnvelope = envelope
        }
        guard let envelope = finalEnvelope, envelope["done"] as? Bool == true,
              envelope["done_reason"] as? String != "length" else {
            throw NSError(domain: "Ollama", code: 4, userInfo: [NSLocalizedDescriptionKey: "Response did not confirm a complete answer"])
        }
        let ms = Int((DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
        let cleaned = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let json: String
        if cleaned.hasPrefix("```") {
            guard let newline = cleaned.firstIndex(of: "\n"), cleaned.hasSuffix("```") else { throw NSError(domain: "Ollama", code: 3, userInfo: [NSLocalizedDescriptionKey: "Incomplete fenced JSON"]) }
            json = String(cleaned[cleaned.index(after: newline)..<cleaned.index(cleaned.endIndex, offsetBy: -3)]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else { json = cleaned }
        let inputTokens=envelope["prompt_eval_count"] as? Int
        let outputTokens=envelope["eval_count"] as? Int
        let decoded=try? JSONDecoder().decode(AIResp.self, from: Data(json.utf8))
        guard let result=decoded, result.recommendations.count<=30 else {
            return Output(provider: "ollama", model: "gemma4:31b-cloud", availability: "HTTP \(http.statusCode)",
                latency_ms: ms, first_event_ms: firstEvent, first_answer_ms: firstAnswer,
                input_tokens: inputTokens, output_tokens: outputTokens, reasoning_tokens: nil,
                completion_confirmed: true, raw: nil, raw_content: String(content.prefix(100_000)),
                error: "Complete response failed the recommendation JSON schema or exceeded 30 records")
        }
        return Output(provider: "ollama", model: "gemma4:31b-cloud", availability: "HTTP \(http.statusCode)",
            latency_ms: ms, first_event_ms: firstEvent, first_answer_ms: firstAnswer,
            input_tokens: inputTokens, output_tokens: outputTokens,
            reasoning_tokens: nil, completion_confirmed: true, raw: result,
            raw_content: String(content.prefix(100_000)), error: nil)
    }
}
