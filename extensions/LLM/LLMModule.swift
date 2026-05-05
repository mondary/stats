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

    public init(provider: LLMProvider, requests: Int = 0, inputTokens: Int64 = 0, outputTokens: Int64 = 0, totalTokens: Int64 = 0, costUSD: Double = 0) {
        self.provider = provider
        self.requests = requests
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
        self.costUSD = costUSD
    }
}

public struct LLMUsageSummary: Codable {
    public var updatedAt: Date = Date()
    public var providers: [LLMUsage] = []
    public var codexPrimaryRemainingPercent: Double? = nil
    public var codexSecondaryRemainingPercent: Double? = nil

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

    public init() {
        super.init(moduleType: .llm, popup: self.popupView, settings: self.settingsView)
        guard self.available else { return }

        // Force stack widget for LLM so 5h/Weekly render on two rows (like used/free widgets).
        Store.shared.set(key: "\(self.config.name)_widget", value: widget_t.stack.rawValue)
        // Right-align + monospaced digits so percentages line up vertically.
        Store.shared.set(key: "\(self.config.name)_\(widget_t.stack.rawValue)_alignment", value: "right")
        Store.shared.set(key: "\(self.config.name)_\(widget_t.stack.rawValue)_monospacedFont", value: true)

        self.usageReader = LLMUsageReader(.llm) { [weak self] value in
            self?.usageCallback(value)
        }

        self.settingsView.callback = { [weak self] in
            self?.usageReader?.read()
        }

        self.setReaders([self.usageReader])
    }

    private func usageCallback(_ raw: LLMUsageSummary?) {
        guard let value = raw, self.enabled else { return }

        DispatchQueue.main.async {
            self.popupView.callback(value)
        }

        let text: String
        if let session = value.codexPrimaryRemainingPercent, let weekly = value.codexSecondaryRemainingPercent {
            text = String(format: "⌬ 5h %.0f%% | W %.0f%%", session, weekly)
        } else {
            let totalK = Double(value.totalTokens) / 1000.0
            text = String(format: "%.1fk $%.2f", totalK, value.costUSD)
        }

        self.menuBar.widgets.filter { $0.isActive }.forEach { w in
            switch w.item {
            case let widget as TextWidget:
                widget.setValue(text)
            case let widget as StackWidget:
                if let session = value.codexPrimaryRemainingPercent, let weekly = value.codexSecondaryRemainingPercent {
                    widget.setValues([
                        Stack_t(key: "codex_5h", value: String(format: "5h %.0f%%", session)),
                        Stack_t(key: "codex_weekly", value: String(format: "W %.0f%%", weekly))
                    ])
                } else {
                    let rows = value.providers.map { Stack_t(key: $0.provider.rawValue, value: "\($0.requests)") }
                    widget.setValues(rows)
                }
            default: break
            }
        }
    }
}
