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

    internal func callback(_ summary: LLMUsageSummary) {
        self.table.subviews.forEach { $0.removeFromSuperview() }

        let total = row("Total", "\(summary.requests) req  \(summary.totalTokens) tok  $\(String(format: "%.2f", summary.costUSD))")
        self.table.addArrangedSubview(total)

        for p in summary.providers {
            let text = "\(p.requests) req  \(p.totalTokens) tok  $\(String(format: "%.2f", p.costUSD))"
            self.table.addArrangedSubview(row(p.provider.rawValue, text))
        }

        let h = max(70, CGFloat(self.table.subviews.count) * 24 + 18)
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
}
