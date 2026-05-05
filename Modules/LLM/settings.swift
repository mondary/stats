import Cocoa
import Kit

internal class LLMSettings: NSStackView, Settings_v {
    public var callback: (() -> Void) = {}

    private let title = ModuleType.llm.stringValue

    init() {
        super.init(frame: .zero)
        self.orientation = .vertical
        self.spacing = Constants.Settings.margin

        self.addArrangedSubview(PreferencesSection([
            PreferencesRow("Codex paths", component: input("\(self.title)_codexPath", placeholder: "~/.codex/sessions:~/.codex/archived_sessions")),
            PreferencesRow("Gemini paths", component: input("\(self.title)_geminiPath", placeholder: "~/.gemini:~/.config/gemini")),
            PreferencesRow("GLM/z.ai paths", component: input("\(self.title)_glmPath", placeholder: "~/.glm:~/.zai:~/.config/zai"))
        ]))

        self.addArrangedSubview(NSView())
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    internal func load(widgets: [widget_t]) {}

    private func input(_ key: String, placeholder: String) -> NSTextField {
        let f = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 22))
        f.identifier = NSUserInterfaceItemIdentifier(rawValue: key)
        f.placeholderString = placeholder
        f.stringValue = Store.shared.string(key: key, defaultValue: "")
        f.target = self
        f.action = #selector(saveValue)
        return f
    }

    @objc private func saveValue(_ sender: NSTextField) {
        guard let key = sender.identifier?.rawValue else { return }
        Store.shared.set(key: key, value: sender.stringValue)
        self.callback()
    }
}
