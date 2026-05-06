import Cocoa
import Kit

internal class LLMPopup: PopupWrapper {
    private let table: NSStackView = NSStackView()
    private let iconSize: CGFloat = 16
    private let relativeFormatter: DateComponentsFormatter = {
        let f = DateComponentsFormatter()
        f.unitsStyle = .abbreviated
        f.allowedUnits = [.day, .hour, .minute]
        f.maximumUnitCount = 2
        f.zeroFormattingBehavior = [.dropAll]
        return f
    }()

    init() {
        super.init(.llm, frame: NSRect(x: 0, y: 0, width: Constants.Popup.width, height: 120))
        self.orientation = .vertical
        self.alignment = .width
        self.spacing = Constants.Popup.spacing

        self.table.orientation = .vertical
        self.table.alignment = .width
        self.table.distribution = .fill
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
        self.table.arrangedSubviews.forEach {
            self.table.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        let allowed = Set((visibleProviders ?? LLMProvider.allCases).map { $0.rawValue })
        let providers = quotaProviders.isEmpty
            ? summary.providers.filter { allowed.contains($0.provider.rawValue) }
            : quotaProviders
        for provider in providers {
            self.table.addArrangedSubview(providerGauge(provider, showLogos: showLogos))
        }

        self.layoutSubtreeIfNeeded()
        self.table.layoutSubtreeIfNeeded()

        let computed = self.fittingSize
        let h = max(70, computed.height)
        self.setFrameSize(NSSize(width: computed.width, height: h))
        self.sizeCallback?(self.frame.size)
    }

    private func row(_ left: String, _ right: String) -> NSView {
        let v = NSStackView()
        v.orientation = .horizontal
        v.distribution = .fill

        let l = NSTextField(labelWithString: left)
        l.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        l.lineBreakMode = .byTruncatingTail
        l.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let r = NSTextField(labelWithString: right)
        r.alignment = .right
        r.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        r.lineBreakMode = .byClipping
        r.setContentCompressionResistancePriority(.required, for: .horizontal)

        v.addArrangedSubview(l)
        v.addArrangedSubview(NSView())
        v.addArrangedSubview(r)
        return v
    }

    private func providerHeader(_ usage: LLMUsage, showLogos: Bool) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.distribution = .fill
        row.alignment = .centerY
        row.translatesAutoresizingMaskIntoConstraints = false
        row.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        if showLogos, let image = iconImage(for: usage.provider) {
            let iv = NSImageView(image: image)
            iv.imageScaling = .scaleProportionallyUpOrDown
            iv.translatesAutoresizingMaskIntoConstraints = false
            iv.widthAnchor.constraint(equalToConstant: iconSize).isActive = true
            iv.heightAnchor.constraint(equalToConstant: iconSize).isActive = true
            row.addArrangedSubview(iv)
        }

        let title = NSTextField(labelWithString: usage.provider.rawValue)
        title.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        title.lineBreakMode = .byTruncatingTail
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(title)

        // Force header to expand to full width
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(spacer)
        return row
    }

    private func gauge(_ title: String, percent: Double, resetsAt: Date?) -> NSView {
        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .width
        container.spacing = 4

        let header = NSStackView()
        header.orientation = .horizontal
        header.distribution = .fill
        header.translatesAutoresizingMaskIntoConstraints = false
        header.setContentHuggingPriority(.defaultLow, for: .horizontal)
        header.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let l = NSTextField(labelWithString: title)
        l.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        l.lineBreakMode = .byTruncatingTail
        l.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let r = NSTextField(labelWithString: String(format: "%.0f%% left", percent))
        r.alignment = .right
        r.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        r.lineBreakMode = .byClipping
        r.setContentCompressionResistancePriority(.required, for: .horizontal)
        header.addArrangedSubview(l)
        header.addArrangedSubview(NSView())
        header.addArrangedSubview(r)

        let barContainer = NSView(frame: .zero)
        barContainer.translatesAutoresizingMaskIntoConstraints = false
        barContainer.heightAnchor.constraint(equalToConstant: 8).isActive = true
        barContainer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        barContainer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let bar = NSProgressIndicator(frame: .zero)
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.style = .bar
        bar.isIndeterminate = false
        bar.minValue = 0
        bar.maxValue = 100
        bar.doubleValue = percent
        bar.controlSize = .small
        barContainer.addSubview(bar)
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: barContainer.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: barContainer.trailingAnchor),
            bar.topAnchor.constraint(equalTo: barContainer.topAnchor),
            bar.bottomAnchor.constraint(equalTo: barContainer.bottomAnchor)
        ])

        container.addArrangedSubview(header)
        container.addArrangedSubview(barContainer)

        if let resetsAt, let rel = resetRelativeText(resetsAt) {
            let note = NSTextField(labelWithString: rel)
            note.font = NSFont.systemFont(ofSize: 10, weight: .regular)
            note.textColor = .secondaryLabelColor
            note.lineBreakMode = .byTruncatingTail
            note.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            container.addArrangedSubview(note)
            note.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true
        }

        // Ensure arranged subviews span full width (otherwise NSStackView may size them to intrinsic width).
        header.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true
        barContainer.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true
        return container
    }

    private func providerGauge(_ usage: LLMUsage, showLogos: Bool) -> NSView {
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .width
        stack.distribution = .fill
        stack.spacing = 5

        let header = providerHeader(usage, showLogos: showLogos)
        let dailyGauge = gauge("Daily", percent: usage.dailyRemainingPercent, resetsAt: usage.dailyResetsAt)
        let weeklyGauge = gauge("Weekly", percent: usage.weeklyRemainingPercent, resetsAt: usage.weeklyResetsAt)

        stack.addArrangedSubview(header)
        stack.addArrangedSubview(dailyGauge)
        stack.addArrangedSubview(weeklyGauge)

        // Force all subviews to full width
        header.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        dailyGauge.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        weeklyGauge.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        return stack
    }

    private func iconToken(for provider: LLMProvider) -> String {
        switch provider {
        case .codex: return "[[icon:codexbar-codex]]"
        case .claude: return "[[icon:codexbar-claude]]"
        case .gemini: return "[[icon:codexbar-gemini]]"
        case .glm: return "[[icon:codexbar-zai]]"
        }
    }

    private func iconImage(for provider: LLMProvider) -> NSImage? {
        let token: String
        switch provider {
        case .codex: token = "codexbar-codex"
        case .claude: token = "codexbar-claude"
        case .gemini: token = "codexbar-gemini"
        case .glm: token = "codexbar-zai"
        }

        // Light theme wants the white icon variant (token-dark).
        let prefersLightIcon = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua
        let names: [String] = prefersLightIcon ? ["\(token)-dark", token] : [token, "\(token)-dark"]
        let exts: [String] = ["png", "svg"]
        for name in names {
            for ext in exts {
                if let url = Bundle.main.url(forResource: name, withExtension: ext),
                   let img = NSImage(contentsOf: url) {
                    return img
                }
            }
        }
        return nil
    }

    private func gauge(_ title: String, percent: Double?, resetsAt: Date?) -> NSView {
        guard let percent else { return row(title, "--% left") }
        return gauge(title, percent: percent, resetsAt: resetsAt)
    }

    private func resetRelativeText(_ resetsAt: Date) -> String? {
        let now = Date()
        let interval = resetsAt.timeIntervalSince(now)
        if interval <= 0 { return "resets soon" }
        // keep it compact; we only need rough timing.
        return relativeFormatter.string(from: interval).map { "resets in \($0)" }
    }
}
