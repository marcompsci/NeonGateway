import XCTest
@testable import GameCore
final class DumpStateTests: XCTestCase {
    func testDumpMap() throws {
        guard ProcessInfo.processInfo.environment["NG_DUMP"] != nil else { return }
        let d = SolaraState.district
        var lines: [String] = []
        for r in 0..<d.rows {
            lines.append(String((0..<d.cols).map { d.tile(TileCoord(col: $0, row: r)).rawValue }))
        }
        try lines.joined(separator: "\n").write(toFile: "/tmp/claude-0/state_map.txt", atomically: true, encoding: .utf8)
        var z: [String] = []
        for zone in d.zones.values { let c = d.coord(at: zone.rect.center); z.append("\(zone.id.rawValue) \(c.col) \(c.row)") }
        try z.joined(separator: "\n").write(toFile: "/tmp/claude-0/state_zones.txt", atomically: true, encoding: .utf8)
    }
}
