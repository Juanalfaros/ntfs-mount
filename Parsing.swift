import Foundation

// Pure helpers, kept apart from main.swift so test.sh can compile and exercise them on their own.

/// "2026.7.7" out of ".../Cellar/ntfs-3g-mac/2026.7.7/bin/ntfs-3g"
func cellarVersion(_ path: String) -> String? {
    let c = path.split(separator: "/").map(String.init)
    guard let i = c.firstIndex(of: "Cellar"), c.count > i + 2 else { return nil }
    return c[i + 2]
}

func isNewer(_ a: String, than b: String) -> Bool { a.compare(b, options: .numeric) == .orderedDescending }

/// Parses the output of `mount` into device id -> mount point for macFUSE volumes.
/// Mount points may contain " (" ("Backup (2)"), so the options group is the LAST " (" on the line.
func parseFuseMounts(_ out: String) -> [String: String] {
    var result: [String: String] = [:]
    for line in out.split(separator: "\n") {
        let s = String(line)
        guard s.contains("(macfuse") || s.contains("(fusefs") || s.contains("(osxfuse"),
              s.hasPrefix("/dev/disk"),
              let on = s.range(of: " on "),
              let paren = s.range(of: " (", options: .backwards), paren.lowerBound >= on.upperBound else { continue }
        let dev = String(s[..<on.lowerBound]).replacingOccurrences(of: "/dev/", with: "")
        result[dev] = String(s[on.upperBound..<paren.lowerBound])
    }
    return result
}
