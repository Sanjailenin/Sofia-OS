import Testing
import Foundation
@testable import SofiaCore

@Suite struct ComputerV2Tests {
    @Test func deeplinksFollowTheSchemeList() {
        #expect(MacAction(["action": "open_deeplink", "target": "spotify:search:jazz"])?.kind == .openDeeplink)
        #expect(MacAction(["action": "open_deeplink", "target": "slack://open"])?.summary == "open slack link")
        #expect(MacAction(["action": "open_deeplink", "target": "file:///etc/passwd"]) == nil)
        #expect(MacAction(["action": "open_deeplink", "target": "https://example.com"]) == nil, "web addresses go through open_url")
        #expect(MacAction(["action": "open_deeplink", "target": "javascript:alert(1)"]) == nil)
    }

    @Test func elementReportAndMatching() {
        let els = [AXElement(id: "e1", role: "button", title: "Compose", x: 120, y: 80), AXElement(id: "e2", role: "text field", title: "Search mail", x: 600, y: 40, editable: true), AXElement(id: "e3", role: "link", title: "Inbox (3)", x: 60, y: 200)]
        #expect(els[0].matches("compose") && els[0].matches("COMP") && !els[0].matches("send"))
        #expect(els[1].matches("search mail") && !els[1].matches("search inbox"))
        let all = AXElement.report(els, query: "")
        #expect(all.hasPrefix("3 controls")); #expect(all.contains("e2 text field \"Search mail\" (600,40) editable"))
        #expect(AXElement.report(els, query: "compose") == "1 control (id role \"title\" (x,y)):\ne1 button \"Compose\" (120,80)")
        #expect(AXElement.report(els, query: "delete").hasPrefix("No control matches \"delete\"; 3 controls"))
        #expect(AXElement.report([], query: "x").hasPrefix("No controls exposed"))
        let many = (1...40).map { AXElement(id: "e\($0)", role: "button", title: "B\($0)", x: $0, y: $0) }
        #expect(AXElement.report(many, query: "").hasPrefix("40 controls, first 25"))
    }

    @Test func roleNames() {
        #expect(AXElement.roleName("AXButton") == "button"); #expect(AXElement.roleName("AXSearchField") == "text field")
        #expect(AXElement.roleName("AXCheckBox", subrole: "AXSwitch") == "switch"); #expect(AXElement.roleName("AXGroup") == nil)
    }
}
