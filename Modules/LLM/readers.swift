import Foundation
import Kit

internal class LLMUsageReader: Reader<LLMUsageSummary> {
    private let fm = FileManager.default
    private let title: String = ModuleType.llm.stringValue

    private var customCodexPath: String {
        Store.shared.string(key: "\(self.title)_codexPath", defaultValue: "")
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

        let roots: [(LLMProvider, [URL])] = [
            (.codex, paths(custom: self.customCodexPath, defaults: ["~/.codex/sessions", "~/.codex/archived_sessions"])),
            (.gemini, paths(custom: self.customGeminiPath, defaults: ["~/.gemini", "~/.config/gemini"])),
            (.glm, paths(custom: self.customGLMPath, defaults: ["~/.glm", "~/.zai", "~/.config/zai"]))
        ]

        roots.forEach { provider, urls in
            urls.forEach { root in
                guard let e = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return }
                for case let file as URL in e {
                    guard file.pathExtension.lowercased() == "jsonl" else { continue }
                    parseFile(file, provider: provider, stats: &byProvider)
                }
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

    private func parseFile(_ file: URL, provider: LLMProvider, stats: inout [LLMProvider: LLMUsage]) {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return }
        defer { try? handle.close() }

        guard let content = String(data: (try? handle.readToEnd()) ?? Data(), encoding: .utf8) else { return }
        for line in content.split(separator: "\n") {
            guard let data = line.data(using: .utf8) else { continue }
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

            let lower = file.path.lowercased()
            if provider == .gemini && !lower.contains("gemini") { continue }
            if provider == .glm && !(lower.contains("glm") || lower.contains("zai") || lower.contains("z.ai")) { continue }

            let usage = (obj["usage"] as? [String: Any]) ?? [:]
            let input = int64(usage["input_tokens"]) ?? int64(usage["prompt_tokens"]) ?? int64(usage["inputTokens"]) ?? 0
            let output = int64(usage["output_tokens"]) ?? int64(usage["completion_tokens"]) ?? int64(usage["outputTokens"]) ?? 0
            let total = int64(usage["total_tokens"]) ?? (input + output)
            let cost = double(obj["cost_usd"]) ?? double(obj["cost"]) ?? 0

            guard input > 0 || output > 0 || total > 0 || cost > 0 else { continue }
            var row = stats[provider] ?? LLMUsage(provider: provider)
            row.requests += 1
            row.inputTokens += input
            row.outputTokens += output
            row.totalTokens += total
            row.costUSD += cost
            stats[provider] = row
        }
    }

    private func int64(_ v: Any?) -> Int64? {
        if let i = v as? Int64 { return i }
        if let i = v as? Int { return Int64(i) }
        if let d = v as? Double { return Int64(d) }
        if let s = v as? String, let i = Int64(s) { return i }
        return nil
    }

    private func double(_ v: Any?) -> Double? {
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        if let s = v as? String, let d = Double(s) { return d }
        return nil
    }
}
