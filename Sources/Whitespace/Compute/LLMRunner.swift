import Foundation

/// Runs an LLM (Claude) cell: the cell's text is the prompt, upstream cell
/// output is passed as context. Wiring several LLM cells with arrows and running
/// the graph = a multi-agent pipeline (each node an inference, edges the context).
///
/// Uses the user's own Anthropic API key (entered in the app, stored locally).
enum LLMRunner {
    static let defaultModel = "claude-sonnet-4-6"

    static func run(prompt: String, context: String, model: String = defaultModel,
                    completion: @escaping @Sendable (KernelResult) -> Void) {
        func finish(_ text: String, failed: Bool) {
            DispatchQueue.main.async {
                completion(KernelResult(text: text, failed: failed, mimeType: nil, mimeData: nil))
            }
        }
        guard let key = Settings.anthropicKey, !key.isEmpty else {
            finish("Set your Anthropic API key — gear ▸ Set API Key…", failed: true); return
        }

        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        let content = context.isEmpty ? prompt
            : "Context from upstream cells:\n\(context)\n\n---\n\(prompt)"
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1500,
            "messages": [["role": "user", "content": content]],
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: req) { data, _, err in
            if let err { finish("Request failed: \(err.localizedDescription)", failed: true); return }
            guard let data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                finish("No response", failed: true); return
            }
            if let parts = obj["content"] as? [[String: Any]] {
                let text = parts.compactMap { $0["text"] as? String }.joined()
                finish(text.isEmpty ? "(empty response)" : text, failed: false)
            } else if let error = obj["error"] as? [String: Any], let msg = error["message"] as? String {
                finish("API error: \(msg)", failed: true)
            } else {
                finish(String(data: data, encoding: .utf8) ?? "Unexpected response", failed: true)
            }
        }.resume()
    }
}
