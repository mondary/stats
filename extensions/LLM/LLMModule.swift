import Foundation
import Kit

public enum LLMProvider: String, Codable, CaseIterable {
    case codex = "Codex"
    case claude = "Claude"
    case gemini = "Gemini"
    case glm = "GLM"
}

public struct LLMUsage: Codable {
    public var provider: LLMProvider
    public var requests: Int
    public var inputTokens: Int64
    public var outputTokens: Int64
    public var totalTokens: Int64
    public var costUSD: Double
    public var dailyRemainingPercent: Double?
    public var weeklyRemainingPercent: Double?
    public var dailyResetsAt: Date?
    public var weeklyResetsAt: Date?

    public init(
        provider: LLMProvider,
        requests: Int = 0,
        inputTokens: Int64 = 0,
        outputTokens: Int64 = 0,
        totalTokens: Int64 = 0,
        costUSD: Double = 0,
        dailyRemainingPercent: Double? = nil,
        weeklyRemainingPercent: Double? = nil,
        dailyResetsAt: Date? = nil,
        weeklyResetsAt: Date? = nil
    ) {
        self.provider = provider
        self.requests = requests
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
        self.costUSD = costUSD
        self.dailyRemainingPercent = dailyRemainingPercent
        self.weeklyRemainingPercent = weeklyRemainingPercent
        self.dailyResetsAt = dailyResetsAt
        self.weeklyResetsAt = weeklyResetsAt
    }
}

public struct LLMUsageSummary: Codable {
    public var updatedAt: Date = Date()
    public var providers: [LLMUsage] = []

    public var requests: Int { self.providers.reduce(0) { $0 + $1.requests } }
    public var inputTokens: Int64 { self.providers.reduce(0) { $0 + $1.inputTokens } }
    public var outputTokens: Int64 { self.providers.reduce(0) { $0 + $1.outputTokens } }
    public var totalTokens: Int64 { self.providers.reduce(0) { $0 + $1.totalTokens } }
    public var costUSD: Double { self.providers.reduce(0) { $0 + $1.costUSD } }
}

public class LLM: Module {
    private let popupView: LLMPopup = LLMPopup()
    private let settingsView: LLMSettings = LLMSettings()
    private var usageReader: LLMUsageReader? = nil
    private let title: String = ModuleType.llm.stringValue
    private var lastSummary: LLMUsageSummary? = nil
    private var lastRemainingByProvider: [LLMProvider: (daily: Double?, weekly: Double?, dailyReset: Date?, weeklyReset: Date?)] = [:]

    public init() {
        super.init(moduleType: .llm, popup: self.popupView, settings: self.settingsView)
        guard self.available else { return }

        // Default to stack widget for LLM so 5h/Weekly can render on two rows.
        let widgetKey = "\(self.config.name)_widget"
        let rawWidget = Store.shared.string(key: widgetKey, defaultValue: "")
        let isValidWidget = widget_t(rawValue: rawWidget) != nil
        if rawWidget.isEmpty || !isValidWidget {
            Store.shared.set(key: widgetKey, value: widget_t.stack.rawValue)
        }
        // Right-align + monospaced digits so percentages line up vertically.
        Store.shared.set(key: "\(self.config.name)_\(widget_t.stack.rawValue)_mode", value: "twoRows")
        Store.shared.set(key: "\(self.config.name)_\(widget_t.stack.rawValue)_alignment", value: "right")
        Store.shared.set(key: "\(self.config.name)_\(widget_t.stack.rawValue)_monospacedFont", value: true)

        self.usageReader = LLMUsageReader(.llm) { [weak self] value in
            self?.usageCallback(value)
        }

        self.settingsView.callback = { [weak self] in
            self?.refreshFromCache()
        }

        self.setReaders([self.usageReader])
    }

    private func usageCallback(_ raw: LLMUsageSummary?) {
        guard let value = raw, self.enabled else { return }
        self.lastSummary = value

        let showLogos = Store.shared.bool(key: "\(self.title)_showLogos", defaultValue: true)
        let twoLines = Store.shared.bool(key: "\(self.title)_twoLines", defaultValue: true)
        let showLabels = Store.shared.bool(key: "\(self.title)_showLabels", defaultValue: true)
        let rawQuotaView = Store.shared.string(key: "\(self.title)_quotaView", defaultValue: "both")
        let quotaView = ["both", "5h", "weekly"].contains(rawQuotaView) ? rawQuotaView : "both"
        let visibleProviders = self.providersWithCachedQuotas(from: self.filteredProviders(from: value.providers))

        DispatchQueue.main.async {
            self.popupView.callback(
                value,
                showLogos: showLogos,
                visibleProviders: visibleProviders.map { $0.provider },
                quotaProviders: visibleProviders
            )
        }

        let text: String = self.menuBarText(
            visibleProviders: visibleProviders,
            showLogos: showLogos,
            showLabels: showLabels,
            quotaView: quotaView
        )

        self.menuBar.widgets.filter { $0.isActive }.forEach { w in
            switch w.item {
            case let widget as TextWidget:
                widget.setValue(text)
            case let widget as StackWidget:
                widget.setValues(self.quotaRows(
                    providers: visibleProviders,
                    showLogos: showLogos,
                    twoLines: twoLines,
                    showLabels: showLabels,
                    quotaView: quotaView
                ))
            default: break
            }
        }
    }

    private func refreshFromCache() {
        guard let cached = self.lastSummary else { return }
        self.usageCallback(cached)
        // Also refresh in background to avoid stale state when cache is empty/outdated.
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.usageReader?.read()
        }
    }

    private func menuBarText(
        visibleProviders: [LLMUsage],
        showLogos: Bool,
        showLabels: Bool,
        quotaView: String
    ) -> String {
        switch quotaView {
        case "5h":
            return visibleProviders.map { self.providerQuotaText($0, kind: .daily, showLogos: showLogos, showLabels: showLabels) }.joined(separator: " ")
        case "weekly":
            return visibleProviders.map { self.providerQuotaText($0, kind: .weekly, showLogos: showLogos, showLabels: showLabels) }.joined(separator: " ")
        default:
            let daily = visibleProviders.map { self.providerQuotaText($0, kind: .daily, showLogos: showLogos, showLabels: showLabels) }.joined(separator: " ")
            let weekly = visibleProviders.map { self.providerQuotaText($0, kind: .weekly, showLogos: false, showLabels: showLabels) }.joined(separator: " ")
            return "\(daily) | \(weekly)"
        }
    }

    private enum QuotaKind {
        case daily
        case weekly
    }

    private func quotaRows(providers: [LLMUsage], showLogos: Bool, twoLines: Bool, showLabels: Bool, quotaView: String) -> [Stack_t] {
        if !twoLines {
            let dailyText = providers.map { self.providerQuotaText($0, kind: .daily, showLogos: showLogos, showLabels: showLabels) }.joined(separator: " ")
            let weeklyText = providers.map { self.providerQuotaText($0, kind: .weekly, showLogos: showLogos, showLabels: showLabels) }.joined(separator: " ")
            switch quotaView {
            case "5h": return [Stack_t(key: "llm_daily", value: dailyText)]
            case "weekly": return [Stack_t(key: "llm_weekly", value: weeklyText)]
            default: return [Stack_t(key: "llm_both", value: "\(dailyText) | \(weeklyText)")]
            }
        }

        return providers.flatMap { provider in
            let daily = Stack_t(
                key: "\(provider.provider.rawValue.lowercased())_daily",
                value: self.providerQuotaText(provider, kind: .daily, showLogos: showLogos, showLabels: showLabels)
            )
            let weekly = Stack_t(
                key: "\(provider.provider.rawValue.lowercased())_weekly",
                value: self.providerQuotaText(provider, kind: .weekly, showLogos: false, showLabels: showLabels)
            )
            switch quotaView {
            case "5h": return [daily]
            case "weekly": return [weekly]
            default: return [daily, weekly]
            }
        }
    }

    private func providerQuotaText(_ usage: LLMUsage, kind: QuotaKind, showLogos: Bool, showLabels: Bool) -> String {
        let icon = showLogos ? self.iconToken(for: usage.provider) + " " : ""
        let label: String
        switch kind {
        case .daily: label = showLabels ? "D " : ""
        case .weekly: label = showLabels ? "W " : ""
        }
        let value = kind == .daily ? usage.dailyRemainingPercent : usage.weeklyRemainingPercent
        guard let value else { return "\(icon)\(label)--%" }
        return String(format: "\(icon)\(label)%.0f%%", value)
    }

    private func iconToken(for provider: LLMProvider) -> String {
        switch provider {
        case .codex: return "[[icon:codexbar-codex]]"
        case .claude: return "[[icon:codexbar-claude]]"
        case .gemini: return "[[icon:codexbar-gemini]]"
        case .glm: return "[[icon:codexbar-zai]]"
        }
    }

    private func providerVisible(_ provider: LLMProvider) -> Bool {
        Store.shared.bool(key: "\(self.title)_showProvider_\(provider.rawValue.lowercased())", defaultValue: true)
    }

    private func filteredProviders(from providers: [LLMUsage]) -> [LLMUsage] {
        providers.filter { self.providerVisible($0.provider) }
    }

    private func providersWithCachedQuotas(from providers: [LLMUsage]) -> [LLMUsage] {
        providers.map { usage in
            var copy = usage
            let cached = self.lastRemainingByProvider[usage.provider]
            copy.dailyRemainingPercent = usage.dailyRemainingPercent ?? cached?.daily
            copy.weeklyRemainingPercent = usage.weeklyRemainingPercent ?? cached?.weekly
            copy.dailyResetsAt = usage.dailyResetsAt ?? cached?.dailyReset
            copy.weeklyResetsAt = usage.weeklyResetsAt ?? cached?.weeklyReset
            self.lastRemainingByProvider[usage.provider] = (
                daily: copy.dailyRemainingPercent,
                weekly: copy.weeklyRemainingPercent,
                dailyReset: copy.dailyResetsAt,
                weeklyReset: copy.weeklyResetsAt
            )
            return copy
        }
    }
}
