import Foundation
import CoreGraphics

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
    checks += 1
}
func decode(_ text: String) throws -> QuotaSnapshot {
    try JSONDecoder().decode(QuotaSnapshot.self, from: Data(text.utf8))
}

let standard = try decode("""
{"rateLimits":{"primary":{"usedPercent":99,"windowDurationMins":300}},
 "rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":56,"windowDurationMins":300,"resetsAt":2000000000},"secondary":{"usedPercent":15,"windowDurationMins":10080}}}}
""")
check(standard.fiveHour?.remaining == 44, "Must display remaining, not used, and prefer Codex bucket")
check(standard.weekly?.remaining == 85, "Weekly quota parsed independently")
check(standard.fiveHour?.isExpired(at: Date(timeIntervalSince1970: 2000000001)) == true, "Past reset must expire")
check(standard.fiveHour?.isExpired(at: Date(timeIntervalSince1970: 1999999999)) == false, "Future reset stays valid")

let swapped = try decode("""
{"rateLimits":{"primary":{"usedPercent":10,"windowDurationMins":10080},"secondary":{"usedPercent":80,"windowDurationMins":300}}}
""")
check(swapped.fiveHour?.remaining == 20, "Find 300-minute window even in secondary")
let weeklyOnly = try decode("""
{"rateLimits":{"primary":{"usedPercent":31,"windowDurationMins":10080},"secondary":null}}
""")
check(weeklyOnly.fiveHour == nil, "Weekly quota must never masquerade as 5 hours")
let otherBucket = try decode("""
{"rateLimits":{"primary":{"usedPercent":1,"windowDurationMins":300}},"rateLimitsByLimitId":{"other":{"primary":{"usedPercent":8,"windowDurationMins":300}}}}
""")
check(otherBucket.fiveHour == nil, "Never use a different model's bucket")
let legacyOther = try decode("""
{"rateLimits":{"limitId":"other","primary":{"usedPercent":8,"windowDurationMins":300}}}
""")
check(legacyOther.fiveHour == nil, "Legacy non-Codex bucket must be excluded")
for percentage in [0, 100] {
    let boundary = try decode("{\"rateLimits\":{\"primary\":{\"usedPercent\":\(percentage),\"windowDurationMins\":300}}}")
    check(boundary.fiveHour?.remaining == 100 - percentage, "Boundary percentage")
}
for percentage in [-1, 101] {
    let invalid = try decode("{\"rateLimits\":{\"primary\":{\"usedPercent\":\(percentage),\"windowDurationMins\":300}}}")
    check(invalid.fiveHour == nil, "Reject invalid percentages")
}
let unknown = try decode("{\"rateLimits\":{\"primary\":{\"usedPercent\":42}}}")
check(unknown.fiveHour == nil, "Unknown window duration cannot be assumed")
let empty = try decode("{}")
check(empty.fiveHour == nil, "Absent data must remain unknown")
let missingReset = try decode("{\"rateLimits\":{\"primary\":{\"usedPercent\":42,\"windowDurationMins\":300}}}")
check(missingReset.fiveHour?.remaining == 58, "Missing reset doesn't invalidate percentage")
check(MeterFormat.resetTime(nil) == "--:--", "Unknown reset must not be invented")
// Regression: the popup must remain below the menu bar, including secondary displays.
for visible in [CGRect(x: 0, y: 38, width: 1470, height: 891),
                CGRect(x: -1920, y: 0, width: 1920, height: 1055),
                CGRect(x: 0, y: 1000, width: 1280, height: 680),
                CGRect(x: 0, y: 0, width: 800, height: 300)] {
    for anchorX in [visible.minX, visible.midX, visible.maxX] {
        let anchor = CGRect(x: anchorX, y: visible.maxY, width: 150, height: 24)
        let frame = PanelPlacement.frame(anchor: anchor, visible: visible, content: CGSize(width: 330, height: 470))
        check(visible.contains(frame), "Entire popup must fit on the anchor's display")
        check(frame.maxY <= anchor.minY - 6, "Popup top must stay below the menu bar")
        check(frame.height <= visible.height - 16, "Short screen must constrain height for scrolling")
    }
}
print("Passed \(checks) quota and popup placement checks.")
