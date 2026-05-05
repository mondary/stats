import Foundation
import Kit

internal class LLMUsageReader: Reader<LLMUsageSummary> {
    private let fm = FileManager.default
    private let title: String = ModuleType.llm.stringValue

    private var customCodexPath: String {
        Store.shared.string(key: "\(self.title)_codexPath", defaultValue: "")
    }
    private var customClaudePath: String {
        Store.shared.string(key: "\(self.title)_claudePath", defaultValue: "")
    }
    private var customGeminiPath: String {
        Store.shared.string(key: "\(self.title)_geminiPath", defaultValue: "")
    }
    private var customGLMPath: String {
        Store.shared.string(key: "\(self.title)_glmPath", defaultValue: "")
    }

    public override func read() {
        self.callback(scan())
    }

    private func scan() -> LLMUsageSummary {
        var byProvider: [LLMProvider: LLMUsage] = [:]
        LLMProvider.allCases.forEach { byProvider[$0] = LLMUsage(provider: $0) }

        let roots: [URL] =
            paths(custom: self.customCodexPath, defaults: ["~/.codex/sessions", "~/.codex/archived_sessions"]) +
            paths(custom: self.customClaudePath, defaults: ["~/.claude/projects", "~/.config/claude/projects"]) +
            paths(custom: self.customGeminiPath, defaults: ["~/.gemini", "~/.config/gemini"]) +
            paths(custom: self.customGLMPath, defaults: ["~/.glm", "~/.zai", "~/.config/zai"])

        roots.forEach { root in
            guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return }
            for case let file as URL in enumerator {
                guard file.pathExtension.lowercased() == "jsonl" else { continue }
                parseFile(file, stats: &byProvider)
            }
        }

        var summary = LLMUsageSummary()
        summary.providers = LLMProvider.allCases.compactMap { byProvider[$0] }
        return summary
    }

    private func paths(custom: String, defaults: [String]) -> [URL] {
        let raw = custom.isEmpty ? defaults : custom.split(separator: ":").map(String.init)
        return raw
            .map { NSString(string: $0).expandingTildeInPath }
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            .filter { fm.fileExists(atPath: $0.path) }
    }

    private func parseFile(_ file: URL, stats: inout [LLMProvider: LLMUsage]) {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return }
        defer { try? handle.close() }

        guard let content = String(data: (try? handle.readToEnd()) ?? Data(), encoding: .utf8) else { return }

        for line in content.split(separator: "\n") {
            guard let data = line.data(using: .utf8) else { continue }
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

            let provider = inferProvider(from: obj, filePath: file.path)
            guard let provider else { continue }

            let usage = extractUsage(from: obj)
            guard usage.total > 0 || usage.input > 0 || usage.output > 0 || usage.cost > 0 else { continue }

            var row = stats[provider] ?? LLMUsage(provider: provider)
            row.requests += 1
            row.inputTokens += usage.input
            row.outputTokens += usage.output
            row.totalTokens += usage.total > 0 ? usage.total : (usage.input + usage.output)
            row.costUSD += usage.cost
            stats[provider] = row
        }
    }

    private func inferProvider(from obj: [String: Any], filePath: String) -> LLMProvider? {
        let text = [
            stringAtPath(obj, ["payload", "model_provider"]),
            stringAtPath(obj, ["payload", "model"]),
            stringAtPath(obj, ["model"]),
            stringAtPath(obj, ["message", "model"]),
            filePath
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        .lowercased()

        if text.contains("codex") || text.contains("openai") { return .codex }
        if text.contains("gemini") { return .gemini }
        if text.contains("glm") || text.contains("z.ai") || text.contains("zai") { return .glm }
        if text.contains("claude") || text.contains("anthropic") { return .claude }
        return nil
    }

    private func extractUsage(from obj: [String: Any]) -> (input: Int64, output: Int64, total: Int64, cost: Double) {
        // Format A: Codex token_count event
        if let eventType = stringAtPath(obj, ["payload", "type"]), eventType == "token_count",
           let usage = dictAtPath(obj, ["payload", "info", "last_token_usage"]) ?? dictAtPath(obj, ["payload", "info", "total_token_usage"]) {
            let input = int64(usage["input_tokens"]) ?? 0
            let output = int64(usage["output_tokens"]) ?? 0
            let total = int64(usage["total_tokens"]) ?? (input + output)
            return (input, output, total, 0)
        }

        // Format B: Claude/GLM style message.usage
        if let usage = dictAtPath(obj, ["message", "usage"]) ?? dictAtPath(obj, ["usage"]) {
            let input = int64(usage["input_tokens"]) ?? int64(usage["prompt_tokens"]) ?? 0
            let output = int64(usage["output_tokens"]) ?? int64(usage["completion_tokens"]) ?? 0
            let total = int64(usage["total_tokens"]) ?? (input + output)
            let cost = double(usage["cost_usd"]) ?? double(usage["cost"]) ?? 0
            return (input, output, total, cost)
        }

        // Format C: Gemini style tokens object
        if let tokens = dictAtPath(obj, ["tokens"]) {
            let input = int64(tokens["input"]) ?? 0
            let output = int64(tokens["output"]) ?? 0
            let total = int64(tokens["total"]) ?? (input + output)
            return (input, output, total, 0)
        }

        // Generic fallback
        let input = int64(obj["input_tokens"]) ?? int64(obj["prompt_tokens"]) ?? 0
        let output = int64(obj["output_tokens"]) ?? int64(obj["completion_tokens"]) ?? 0
        let total = int64(obj["total_tokens"]) ?? (input + output)
        let cost = double(obj["cost_usd"]) ?? double(obj["cost"]) ?? 0
        return (input, output, total, cost)
    }

    private func dictAtPath(_ root: [String: Any], _ path: [String]) -> [String: Any]? {
        var current: Any = root
        for key in path {
            guard let dict = current as? [String: Any], let next = dict[key] else { return nil }
            current = next
        }
        return current as? [String: Any]
    }

    private func stringAtPath(_ root: [String: Any], _ path: [String]) -> String? {
        var current: Any = root
        for key in path {
            guard let dict = current as? [String: Any], let next = dict[key] else { return nil }
            current = next
        }
        return current as? String
    }

    private func int64(_ value: Any?) -> Int64? {
        if let i = value as? Int64 { return i }
        if let i = value as? Int { return Int64(i) }
        if let d = value as? Double { return Int64(d) }
        if let s = value as? String, let i = Int64(s) { return i }
        return nil
    }

    private func double(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let s = value as? String, let d = Double(s) { return d }
        return nil
    }
}
