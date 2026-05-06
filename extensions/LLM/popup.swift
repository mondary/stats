import Cocoa
import Kit

internal class LLMPopup: PopupWrapper {
    private let table: NSStackView = NSStackView()

    init() {
        super.init(.llm, frame: NSRect(x: 0, y: 0, width: Constants.Popup.width, height: 120))
        self.orientation = .vertical
        self.spacing = Constants.Popup.spacing

        self.table.orientation = .vertical
        self.table.spacing = 6
        self.table.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        self.addArrangedSubview(self.table)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    internal func callback(
        _ summary: LLMUsageSummary,
        showLogos: Bool = true,
        visibleProviders: [LLMProvider]? = nil,
        quotaProviders: [LLMUsage] = []
    ) {
        self.table.subviews.forEach { $0.removeFromSuperview() }

        let allowed = Set((visibleProviders ?? LLMProvider.allCases).map { $0.rawValue })
        let providers = quotaProviders.isEmpty
            ? summary.providers.filter { allowed.contains($0.provider.rawValue) }
            : quotaProviders
        for provider in providers {
            self.table.addArrangedSubview(providerGauge(provider, showLogos: showLogos))
        }

        let h = max(70, CGFloat(self.table.subviews.count) * 76 + 18)
        self.setFrameSize(NSSize(width: self.frame.width, height: h))
        self.sizeCallback?(self.frame.size)
    }

    private func row(_ left: String, _ right: String) -> NSView {
        let v = NSStackView()
        v.orientation = .horizontal
        v.distribution = .fill

        let l = TextView(frame: .zero)
        l.stringValue = left
        l.font = NSFont.systemFont(ofSize: 12, weight: .semibold)

        let r = TextView(frame: .zero)
        r.stringValue = right
        r.alignment = .right
        r.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)

        v.addArrangedSubview(l)
        v.addArrangedSubview(NSView())
        v.addArrangedSubview(r)
        return v
    }

    private func gauge(_ title: String, percent: Double) -> NSView {
        let container = NSStackView()
        container.orientation = .vertical
        container.spacing = 4

        let header = NSStackView()
        header.orientation = .horizontal
        let l = TextView(frame: .zero)
        l.stringValue = title
        l.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let r = TextView(frame: .zero)
        r.stringValue = String(format: "%.0f%% left", percent)
        r.alignment = .right
        r.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        header.addArrangedSubview(l)
        header.addArrangedSubview(NSView())
        header.addArrangedSubview(r)

        let bar = NSProgressIndicator(frame: NSRect(x: 0, y: 0, width: 220, height: 8))
        bar.style = .bar
        bar.isIndeterminate = false
        bar.minValue = 0
        bar.maxValue = 100
        bar.doubleValue = percent
        bar.controlSize = .small

        container.addArrangedSubview(header)
        container.addArrangedSubview(bar)
        return container
    }

    private func providerGauge(_ usage: LLMUsage, showLogos: Bool) -> NSView {
        let container = NSStackView()
        container.orientation = .vertical
        container.spacing = 5

        let title = TextView(frame: .zero)
        title.stringValue = usage.provider.rawValue
        title.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        container.addArrangedSubview(title)
        container.addArrangedSubview(gauge("Daily", percent: usage.dailyRemainingPercent))
        container.addArrangedSubview(gauge("Weekly", percent: usage.weeklyRemainingPercent))
        return container
    }

    private func gauge(_ title: String, percent: Double?) -> NSView {
        guard let percent else { return row(title, "--% left") }
        return gauge(title, percent: percent)
    }
}
