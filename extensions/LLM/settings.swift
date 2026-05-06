import Cocoa
import Kit

internal class LLMSettings: NSStackView, Settings_v {
    public var callback: (() -> Void) = {}

    private let title = ModuleType.llm.stringValue
    private let quotaOptions: [KeyValue_p] = [
        KeyValue_t(key: "both", value: "5h + Weekly"),
        KeyValue_t(key: "5h", value: "5h only"),
        KeyValue_t(key: "weekly", value: "Weekly only")
    ]

    init() {
        super.init(frame: .zero)
        self.orientation = .vertical
        self.spacing = Constants.Settings.margin

        self.addArrangedSubview(PreferencesSection([
            PreferencesRow("Show Codex", component: switchView(
                action: #selector(toggleCodex),
                state: Store.shared.bool(key: "\(self.title)_showProvider_codex", defaultValue: true)
            )),
            PreferencesRow("Show Claude", component: switchView(
                action: #selector(toggleClaude),
                state: Store.shared.bool(key: "\(self.title)_showProvider_claude", defaultValue: true)
            )),
            PreferencesRow("Show Gemini", component: switchView(
                action: #selector(toggleGemini),
                state: Store.shared.bool(key: "\(self.title)_showProvider_gemini", defaultValue: true)
            )),
            PreferencesRow("Show GLM/z.ai", component: switchView(
                action: #selector(toggleGLM),
                state: Store.shared.bool(key: "\(self.title)_showProvider_glm", defaultValue: true)
            )),
            PreferencesRow("Show logos", component: switchView(
                action: #selector(toggleLogos),
                state: Store.shared.bool(key: "\(self.title)_showLogos", defaultValue: true)
            )),
            PreferencesRow("Show on 2 lines", component: switchView(
                action: #selector(toggleTwoLines),
                state: Store.shared.bool(key: "\(self.title)_twoLines", defaultValue: true)
            )),
            PreferencesRow("Show labels (5h/W)", component: switchView(
                action: #selector(toggleLabels),
                state: Store.shared.bool(key: "\(self.title)_showLabels", defaultValue: true)
            )),
            PreferencesRow("Quota view", component: selectView(
                action: #selector(toggleQuotaView),
                items: self.quotaOptions,
                selected: Store.shared.string(key: "\(self.title)_quotaView", defaultValue: "both")
            ))
        ]))
        self.addArrangedSubview(NSView())
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    internal func load(widgets: [widget_t]) {}

    @objc private func toggleLogos(_ sender: NSControl) {
        guard let control = sender as? NSSwitch else { return }
        Store.shared.set(key: "\(self.title)_showLogos", value: control.state == .on)
        self.callback()
    }

    @objc private func toggleTwoLines(_ sender: NSControl) {
        guard let control = sender as? NSSwitch else { return }
        Store.shared.set(key: "\(self.title)_twoLines", value: control.state == .on)
        self.callback()
    }

    @objc private func toggleLabels(_ sender: NSControl) {
        guard let control = sender as? NSSwitch else { return }
        Store.shared.set(key: "\(self.title)_showLabels", value: control.state == .on)
        self.callback()
    }

    @objc private func toggleQuotaView(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        Store.shared.set(key: "\(self.title)_quotaView", value: key)
        self.callback()
    }

    @objc private func toggleCodex(_ sender: NSControl) { self.setProvider("codex", sender) }
    @objc private func toggleClaude(_ sender: NSControl) { self.setProvider("claude", sender) }
    @objc private func toggleGemini(_ sender: NSControl) { self.setProvider("gemini", sender) }
    @objc private func toggleGLM(_ sender: NSControl) { self.setProvider("glm", sender) }

    private func setProvider(_ provider: String, _ sender: NSControl) {
        guard let control = sender as? NSSwitch else { return }
        Store.shared.set(key: "\(self.title)_showProvider_\(provider)", value: control.state == .on)
        self.callback()
    }
}
