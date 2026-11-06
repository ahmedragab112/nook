import Foundation

/// Reads the internal battery through `pmset`, which needs no extra permissions.
final class BatteryReader {
    private(set) var percent: Int?
    private(set) var charging = false

    func sample() {
        guard let out = Util.shell("/usr/bin/pmset", ["-g", "batt"]), out.contains("InternalBattery") else {
            percent = nil
            return
        }
        let pattern = "(\\d{1,3})%\\s*;\\s*([a-zA-Z ]+);"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let range = NSRange(out.startIndex..., in: out)
        guard let match = regex.firstMatch(in: out, range: range),
              let percentRange = Range(match.range(at: 1), in: out),
              let stateRange = Range(match.range(at: 2), in: out) else { return }
        percent = Int(out[percentRange])
        let state = out[stateRange].trimmingCharacters(in: .whitespaces).lowercased()
        charging = state == "charging" || state == "finishing charge" || state == "full" || state == "charged"
    }
}
