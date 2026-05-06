//
//  Text.swift
//  Kit
//
//  Created by Serhiy Mytrovtsiy on 08/09/2024
//  Using Swift 5.0
//  Running on macOS 14.6
//
//  Copyright © 2024 Serhiy Mytrovtsiy. All rights reserved.
//  

import Cocoa

public class TextWidget: WidgetWrapper {
    private var value: String = ""
    private static var iconCache: [String: NSImage] = [:]
    
    public init(title: String, config: NSDictionary?, preview: Bool = false) {
        super.init(.text, title: title, frame: CGRect(
            x: 0,
            y: Constants.Widget.margin.y,
            width: 30 + (2*Constants.Widget.margin.x),
            height: Constants.Widget.height - (2*Constants.Widget.margin.y)
        ))
        
        if preview {
            self.value = "Text"
        }
        
        self.canDrawConcurrently = true
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        var value: String = ""
        self.queue.sync {
            value = self.value
        }
        
        if value.isEmpty {
            self.setWidth(0)
            return
        }
        
        let valueSize: CGFloat = 12
        let (icon, textValue) = self.parseIcon(from: value)
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let stringAttributes = [
            NSAttributedString.Key.font: NSFont.systemFont(ofSize: valueSize, weight: .regular),
            NSAttributedString.Key.foregroundColor: NSColor.textColor,
            NSAttributedString.Key.paragraphStyle: style
        ]
        let attributedString = NSAttributedString(string: textValue, attributes: stringAttributes)
        let size = attributedString.boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let iconSize: CGFloat = min(18, Constants.Widget.height - 4)
        let iconWidth: CGFloat = icon == nil ? 0 : iconSize
        let iconSpacing: CGFloat = icon == nil ? 0 : 4
        let contentWidth = size.width + iconWidth + iconSpacing
        let width = (contentWidth+Constants.Widget.margin.x*2).roundedUpToNearestTen()
        let origin: CGPoint = CGPoint(x: Constants.Widget.margin.x, y: ((Constants.Widget.height-valueSize-1)/2))
        if let icon {
            let iconRect = CGRect(
                x: origin.x,
                y: ((Constants.Widget.height-iconSize)/2),
                width: iconSize,
                height: iconSize
            )
            icon.draw(in: iconRect)
        }
        let rect = CGRect(
            x: origin.x + iconWidth + iconSpacing,
            y: origin.y,
            width: width - (Constants.Widget.margin.x*2) - iconWidth - iconSpacing,
            height: valueSize
        )
        attributedString.draw(with: rect)
        
        self.setWidth(width)
    }
    
    public func setValue(_ newValue: String) {
        guard self.value != newValue else { return }
        self.value = newValue
        DispatchQueue.main.async(execute: {
            self.display()
        })
    }
    
    static public func parseText(_ raw: String) -> [KeyValue_t] {
        var pairs: [KeyValue_t] = []
        do {
            let regex = try NSRegularExpression(pattern: "(\\$[a-zA-Z0-9_]+)(?:\\.([a-zA-Z0-9_]+))?")
            let matches = regex.matches(in: raw, range: NSRange(raw.startIndex..., in: raw))
            for match in matches {
                if let keyRange = Range(match.range(at: 1), in: raw) {
                    let key = String(raw[keyRange])
                    let value: String?
                    if match.range(at: 2).location != NSNotFound, let valueRange = Range(match.range(at: 2), in: raw) {
                        value = String(raw[valueRange])
                    } else {
                        value = nil
                    }
                    pairs.append(KeyValue_t(key: key, value: value ?? ""))
                }
            }
        } catch {
            print("Error creating regex: \(error.localizedDescription)")
        }
        return pairs
    }

    private func parseIcon(from raw: String) -> (NSImage?, String) {
        guard raw.hasPrefix("[[icon:") else { return (nil, raw) }
        guard let end = raw.range(of: "]]") else { return (nil, raw) }

        let token = String(raw[raw.index(raw.startIndex, offsetBy: 7)..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let text = String(raw[end.upperBound...]).trimmingCharacters(in: .whitespaces)
        guard !token.isEmpty else { return (nil, text) }

        let prefersLightIcon = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua
        let cacheKey = "\(token)|\(prefersLightIcon ? "lightIcon" : "defaultIcon")"
        if let cached = Self.iconCache[cacheKey] {
            return (cached, text)
        }
        let names: [String] = prefersLightIcon ? ["\(token)-dark", token] : [token, "\(token)-dark"]
        let exts: [String] = ["png", "svg"]
        let image: NSImage? = names.lazy.flatMap { name in
            exts.lazy.compactMap { ext in
                guard let url = Bundle.main.url(forResource: name, withExtension: ext) else { return nil }
                return NSImage(contentsOf: url)
            }
        }.first
        guard let image else { return (nil, text) }
        Self.iconCache[cacheKey] = image
        return (image, text)
    }
}
