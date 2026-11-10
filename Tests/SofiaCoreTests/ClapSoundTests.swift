import Testing
import Foundation
@testable import SofiaCore

struct ClapSoundTests {
    @Test func clappingBeatsOtherImpacts() {
        #expect(ClapSound.verdict(["clapping": 0.72, "knock": 0.10, "speech": 0.05]) == .clap)
        #expect(ClapSound.verdict(["applause": 0.55, "clapping": 0.30, "door": 0.2]) == .clap)
        #expect(ClapSound.verdict(["clapping": 0.35, "finger_snapping": 0.31]) == .clap)
    }

    @Test func aSlapLikeBangCountsAsAClap() {
        #expect(ClapSound.verdict(["slap_smack": 0.74, "hammer": 0.35, "finger_snapping": 0.26]) == .clap)
    }

    @Test func aCloseCallIsNeverBlocked() {
        #expect(ClapSound.verdict(["slap_smack": 0.96, "finger_snapping": 0.95, "clapping": 0.82]) == .clap)
        #expect(ClapSound.verdict(["finger_snapping": 0.95, "slap_smack": 0.90]) == .unsure)
        #expect(ClapSound.verdict(["glass_clink": 0.86, "slap_smack": 0.83]) == .unsure)
        #expect(ClapSound.verdict(["thump_thud": 0.40, "clapping": 0.39]) == .unsure)
        #expect(ClapSound.verdict(["door": 0.6, "clapping": 0.5]) == .unsure, "a lead under the margin")
    }

    @Test func aKnockOrSnapWithAClearLeadIsNotAClap() {
        #expect(ClapSound.verdict(["knock": 0.96, "chopping_food": 0.89, "door": 0.77]) == .other("knock"))
        #expect(ClapSound.verdict(["finger_snapping": 1.00, "slap_smack": 0.67, "whispering": 0.53]) == .other("finger_snapping"))
        #expect(ClapSound.verdict(["glass_clink": 0.64, "clapping": 0.22]) == .other("glass_clink"))
        #expect(ClapSound.verdict(["typing_computer_keyboard": 0.89, "typing": 0.87, "knock": 0.60]) == .other("typing_computer_keyboard"))
        #expect(ClapSound.verdict(["door": 0.69, "door_slam": 0.57, "hammer": 0.46]) == .other("door"))
    }

    @Test func weakEvidenceEitherWayIsUnsure() {
        #expect(ClapSound.verdict([:]) == .unsure)
        #expect(ClapSound.verdict(["clapping": 0.12, "knock": 0.10]) == .unsure)
        #expect(ClapSound.verdict(["music": 0.9, "clapping": 0.1]) == .unsure, "labels that aren't impacts don't decide")
    }

    @Test func theLogLineShowsTheStrongestLabels() {
        let line = ClapSound.describe(["clapping": 0.72, "knock": 0.10, "speech": 0.05, "music": 0.02, "tap": 0.01])
        #expect(line == "clap | clapping 0.72, knock 0.10, speech 0.05, music 0.02")
        #expect(ClapSound.describe([:]) == "unsure | nothing recognised")
        #expect(ClapSound.versus(["slap_smack": 0.96, "finger_snapping": 0.95]) == "clap-like 0.96 vs other finger_snapping 0.95")
        #expect(ClapSound.versus(["music": 0.9]) == "clap-like 0.00 vs other none")
    }
}
