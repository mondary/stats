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
        var codexRateTimestamp: Date = .distantPast

        let codexRoots = paths(custom: self.customCodexPath, defaults: ["~/.codex/sessions", "~/.codex/archived_sessions"])
        let codexRateSourceFile = mostRecentCodexSessionFile(roots: codexRoots)
        let codexRPCQuota = fetchCodexRPCQuota()
        let geminiQuota = fetchGeminiQuota()
        let zaiQuota = fetchZaiQuota()

        let roots: [URL] =
            codexRoots +
            paths(custom: self.customClaudePath, defaults: ["~/.claude/projects", "~/.config/claude/projects"]) +
            paths(custom: self.customGeminiPath, defaults: ["~/.gemini", "~/.config/gemini"]) +
            paths(custom: self.customGLMPath, defaults: ["~/.glm", "~/.zai", "~/.config/zai"])

        roots.forEach { root in
            guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return }
            for case let file as URL in enumerator {
                guard file.pathExtension.lowercased() == "jsonl" else { continue }
                parseFile(
                    file,
                    stats: &byProvider,
                    codexRateTimestamp: &codexRateTimestamp,
                    codexRateSourceFile: codexRateSourceFile
                )
            }
        }

        if let codexRPCQuota {
            var codex = byProvider[.codex] ?? LLMUsage(provider: .codex)
            codex.dailyRemainingPercent = codexRPCQuota.primaryRemaining
            codex.weeklyRemainingPercent = codexRPCQuota.secondaryRemaining
            codex.dailyResetsAt = codexRPCQuota.primaryResetsAt
            codex.weeklyResetsAt = codexRPCQuota.secondaryResetsAt
            byProvider[.codex] = codex
        }
        if let geminiQuota {
            var gemini = byProvider[.gemini] ?? LLMUsage(provider: .gemini)
            gemini.dailyRemainingPercent = geminiQuota.primaryRemaining
            gemini.weeklyRemainingPercent = geminiQuota.secondaryRemaining
            gemini.dailyResetsAt = geminiQuota.primaryResetsAt
            gemini.weeklyResetsAt = geminiQuota.secondaryResetsAt
            byProvider[.gemini] = gemini
        }
        if let zaiQuota {
            var glm = byProvider[.glm] ?? LLMUsage(provider: .glm)
            glm.dailyRemainingPercent = zaiQuota.primaryRemaining
            glm.weeklyRemainingPercent = zaiQuota.secondaryRemaining
            glm.dailyResetsAt = zaiQuota.primaryResetsAt
            glm.weeklyResetsAt = zaiQuota.secondaryResetsAt
            byProvider[.glm] = glm
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

    private func parseFile(
        _ file: URL,
        stats: inout [LLMProvider: LLMUsage],
        codexRateTimestamp: inout Date,
        codexRateSourceFile: URL?
    ) {
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

            if provider == .codex,
               codexRateSourceFile?.path == file.path,
               let rates = extractCodexRemaining(from: obj) {
                let ts = extractTimestamp(from: obj) ?? .distantPast
                if ts >= codexRateTimestamp {
                    codexRateTimestamp = ts
                    var codex = stats[.codex] ?? LLMUsage(provider: .codex)
                    codex.dailyRemainingPercent = rates.primaryRemaining
                    codex.weeklyRemainingPercent = rates.secondaryRemaining
                    codex.dailyResetsAt = rates.primaryResetsAt
                    codex.weeklyResetsAt = rates.secondaryResetsAt
                    stats[.codex] = codex
                }
            }
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

    private func extractCodexRemaining(from obj: [String: Any]) -> (
        primaryRemaining: Double,
        secondaryRemaining: Double,
        primaryResetsAt: Date?,
        secondaryResetsAt: Date?
    )? {
        guard
            let eventType = stringAtPath(obj, ["payload", "type"]),
            eventType == "token_count",
            let rate = dictAtPath(obj, ["rate_limits"]) ?? dictAtPath(obj, ["payload", "rate_limits"]),
            let primary = rate["primary"] as? [String: Any],
            let secondary = rate["secondary"] as? [String: Any]
        else { return nil }

        let primaryUsed = double(primary["used_percent"]) ?? 0
        let secondaryUsed = double(secondary["used_percent"]) ?? 0

        return (
            primaryRemaining: max(0, min(100, 100 - primaryUsed)),
            secondaryRemaining: max(0, min(100, 100 - secondaryUsed)),
            primaryResetsAt: resetsAtDate(from: primary),
            secondaryResetsAt: resetsAtDate(from: secondary)
        )
    }

    private func extractTimestamp(from obj: [String: Any]) -> Date? {
        guard let raw = obj["timestamp"] as? String else { return nil }
        return ISO8601DateFormatter().date(from: raw)
    }

    private func mostRecentCodexSessionFile(roots: [URL]) -> URL? {
        var best: (url: URL, mtime: Date)?

        for root in roots {
            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for case let file as URL in enumerator {
                guard file.pathExtension.lowercased() == "jsonl" else { continue }
                let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
                guard values?.isRegularFile == true, let mtime = values?.contentModificationDate else { continue }
                if best == nil || mtime > best!.mtime {
                    best = (file, mtime)
                }
            }
        }

        return best?.url
    }

    private func fetchCodexRPCQuota() -> (
        primaryRemaining: Double?,
        secondaryRemaining: Double?,
        primaryResetsAt: Date?,
        secondaryResetsAt: Date?
    )? {
        let process = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        var env = ProcessInfo.processInfo.environment
        let currentPath = env["PATH"] ?? ""
        env["PATH"] = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
            currentPath,
        ].joined(separator: ":")

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["codex", "-s", "read-only", "-a", "untrusted", "app-server"]
        process.environment = env
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return nil
        }

        let messages = [
            #"{"id":1,"method":"initialize","params":{"clientInfo":{"name":"stats-llm","version":"0.1"}}}"#,
            #"{"method":"initialized","params":{}}"#,
            #"{"id":2,"method":"account/rateLimits/read","params":{}}"#,
        ].joined(separator: "\n") + "\n"

        if let data = messages.data(using: .utf8) {
            stdinPipe.fileHandleForWriting.write(data)
        }
        try? stdinPipe.fileHandleForWriting.close()

        // Read stdout incrementally; terminate as soon as we get the rateLimits response.
        let semaphore = DispatchSemaphore(value: 0)
        var resultTuple: (Double?, Double?, Date?, Date?)? = nil
        var buffer = Data()

        let handle = stdoutPipe.fileHandleForReading
        handle.readabilityHandler = { [weak self] _ in
            guard let self else { return }
            let data = handle.availableData
            if data.isEmpty { return }
            buffer.append(data)

            while let nl = buffer.firstIndex(of: 0x0A) {
                let lineData = buffer.subdata(in: 0..<nl)
                buffer.removeSubrange(0...nl)
                guard
                    let line = String(data: lineData, encoding: .utf8),
                    let payload = line.data(using: .utf8),
                    let obj = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
                    let id = obj["id"] as? Int,
                    id == 2,
                    let res = obj["result"] as? [String: Any],
                    let rateLimits = res["rateLimits"] as? [String: Any]
                else { continue }

                let primary = rateLimits["primary"] as? [String: Any]
                let secondary = rateLimits["secondary"] as? [String: Any]
                resultTuple = (
                    self.remainingPercent(from: primary),
                    self.remainingPercent(from: secondary),
                    self.resetsAtDate(from: primary),
                    self.resetsAtDate(from: secondary)
                )
                semaphore.signal()
                return
            }
        }

        _ = semaphore.wait(timeout: .now() + 10)
        handle.readabilityHandler = nil
        if process.isRunning {
            process.terminate()
        }
        process.waitUntilExit()

        if let t = resultTuple {
            return (primaryRemaining: t.0, secondaryRemaining: t.1, primaryResetsAt: t.2, secondaryResetsAt: t.3)
        }
        return nil
    }

    private func remainingPercent(from window: [String: Any]?) -> Double? {
        guard let used = double(window?["usedPercent"]) else { return nil }
        return max(0, min(100, 100 - used))
    }

    private func resetsAtDate(from window: [String: Any]?) -> Date? {
        if let seconds = double(window?["resetsAt"]) {
            return Date(timeIntervalSince1970: seconds)
        }
        if let seconds = double(window?["resetAt"]) {
            return Date(timeIntervalSince1970: seconds)
        }
        if let seconds = double(window?["resets_at"]) {
            return Date(timeIntervalSince1970: seconds)
        }
        if let seconds = double(window?["reset_at"]) {
            return Date(timeIntervalSince1970: seconds)
        }
        return nil
    }

    private func fetchGeminiQuota() -> (
        primaryRemaining: Double?,
        secondaryRemaining: Double?,
        primaryResetsAt: Date?,
        secondaryResetsAt: Date?
    )? {
        let credsURL = fm.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini", isDirectory: true)
            .appendingPathComponent("oauth_creds.json")
        guard
            let data = try? Data(contentsOf: credsURL),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let token = json["access_token"] as? String,
            !token.isEmpty
        else { return nil }

        guard
            let response = requestJSON(
                url: URL(string: "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota")!,
                method: "POST",
                headers: [
                    "Authorization": "Bearer \(token)",
                    "Content-Type": "application/json",
                ],
                body: Data("{}".utf8)
            ),
            let buckets = response["buckets"] as? [[String: Any]]
        else { return nil }

        func remaining(for marker: String) -> Double? {
            let matches = buckets.filter {
                (($0["modelId"] as? String)?.lowercased().contains(marker) ?? false) &&
                (($0["tokenType"] as? String)?.uppercased() == "REQUESTS")
            }
            let values = matches.compactMap { bucket -> Double? in
                if let fraction = double(bucket["remainingFraction"]) {
                    return max(0, min(100, fraction * 100))
                }
                if let percent = double(bucket["percentLeft"]) ?? double(bucket["remainingPercent"]) {
                    return max(0, min(100, percent))
                }
                return nil
            }
            return values.min()
        }

        return (
            primaryRemaining: remaining(for: "pro") ?? buckets.compactMap { double($0["remainingFraction"]).map { $0 * 100 } }.min(),
            secondaryRemaining: remaining(for: "flash"),
            primaryResetsAt: nil, // Gemini API doesn't provide reset time
            secondaryResetsAt: nil
        )
    }

    private func fetchZaiQuota() -> (
        primaryRemaining: Double?,
        secondaryRemaining: Double?,
        primaryResetsAt: Date?,
        secondaryResetsAt: Date?
    )? {
        guard let token = zaiToken() else { return nil }
        guard
            let response = requestJSON(
                url: URL(string: "https://api.z.ai/api/monitor/usage/quota/limit")!,
                method: "GET",
                headers: [
                    "authorization": "Bearer \(token)",
                    "accept": "application/json",
                ],
                body: nil
            ),
            ((response["success"] as? Bool) == true || (response["code"] as? Int) == 200),
            let data = response["data"] as? [String: Any],
            let limits = data["limits"] as? [[String: Any]]
        else { return nil }

        let tokenLimits = limits
            .filter { ($0["type"] as? String) == "TOKENS_LIMIT" }
            .sorted { (int($0["number"]) ?? Int.max) < (int($1["number"]) ?? Int.max) }
        let timeLimit = limits.first { ($0["type"] as? String) == "TIME_LIMIT" }

        return (
            primaryRemaining: zaiRemaining(from: tokenLimits.first ?? timeLimit),
            secondaryRemaining: zaiRemaining(from: timeLimit ?? tokenLimits.last),
            primaryResetsAt: nil, // Z.ai API doesn't provide reset time
            secondaryResetsAt: nil
        )
    }

    private func zaiToken() -> String? {
        let env = ProcessInfo.processInfo.environment
        if let token = env["Z_AI_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            return token
        }
        let glmConfig = fm.homeDirectoryForCurrentUser
            .appendingPathComponent(".glm", isDirectory: true)
            .appendingPathComponent("config.json")
        guard
            let data = try? Data(contentsOf: glmConfig),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let token = json["anthropic_auth_token"] as? String
        else { return nil }
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func zaiRemaining(from limit: [String: Any]?) -> Double? {
        guard let limit else { return nil }
        if let usage = int(limit["usage"]), usage > 0, let remaining = int(limit["remaining"]) {
            return max(0, min(100, (Double(remaining) / Double(usage)) * 100))
        }
        if let used = double(limit["percentage"]) {
            return max(0, min(100, 100 - used))
        }
        return nil
    }

    private func requestJSON(url: URL, method: String, headers: [String: String], body: Data?) -> [String: Any]? {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 8
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        request.httpBody = body

        let semaphore = DispatchSemaphore(value: 0)
        var result: [String: Any]?
        URLSession.shared.dataTask(with: request) { data, response, _ in
            defer { semaphore.signal() }
            guard
                let http = response as? HTTPURLResponse,
                (200...299).contains(http.statusCode),
                let data,
                let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return }
            result = obj
        }.resume()
        _ = semaphore.wait(timeout: .now() + 8)
        return result
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

    private func int(_ value: Any?) -> Int? {
        if let i = value as? Int { return i }
        if let d = value as? Double { return Int(d) }
        if let s = value as? String, let i = Int(s) { return i }
        return nil
    }

    private func double(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let s = value as? String, let d = Double(s) { return d }
        return nil
    }
}
