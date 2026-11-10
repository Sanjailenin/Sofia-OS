import Foundation

public struct AXElement: Equatable {
    public var id: String
    public var role: String
    public var title: String
    public var x: Int, y: Int
    public var editable: Bool

    public init(id: String, role: String, title: String, x: Int, y: Int, editable: Bool = false) {
        self.id = id; self.role = role; self.title = title; self.x = x; self.y = y; self.editable = editable
    }

    public static func roleName(_ axRole: String, subrole: String? = nil) -> String? {
        switch axRole {
        case "AXButton": return "button"
        case "AXLink": return "link"
        case "AXTextField", "AXSearchField": return "text field"
        case "AXTextArea": return "text area"
        case "AXComboBox": return "combo box"
        case "AXPopUpButton": return "popup"
        case "AXMenuItem", "AXMenuBarItem": return "menu item"
        case "AXCheckBox": return subrole == "AXToggle" || subrole == "AXSwitch" ? "switch" : "checkbox"
        case "AXRadioButton": return "radio"
        case "AXTabGroup": return nil
        case "AXTab": return "tab"
        case "AXSlider": return "slider"
        case "AXCell", "AXRow": return "row"
        case "AXDisclosureTriangle": return "disclosure"
        default: return nil
        }
    }

    public func matches(_ query: String) -> Bool {
        let words = query.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        guard !words.isEmpty else { return true }
        let t = title.lowercased()
        return words.allSatisfy { t.contains($0) }
    }

    public var line: String { "\(id) \(role) \"\(title.replacingOccurrences(of: "\"", with: "'").prefix(60))\" (\(x),\(y))\(editable ? " editable" : "")" }

    public static func report(_ elements: [AXElement], query: String, limit: Int = 25) -> String {
        let hits = elements.filter { $0.matches(query) }
        if hits.isEmpty { return elements.isEmpty ? "No controls exposed by the front window; use the screenshot." : "No control matches \"\(query)\"; \(elements.count) controls in the window. Try other words or use the screenshot." }
        let shown = hits.prefix(limit)
        return "\(hits.count) control\(hits.count == 1 ? "" : "s")\(hits.count > limit ? ", first \(limit)" : "") (id role \"title\" (x,y)):\n" + shown.map(\.line).joined(separator: "\n")
    }
}
