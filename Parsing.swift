import Foundation

// Pure helpers, kept apart from main.swift so test.sh can compile and exercise them on their own.

/// "2026.7.7" out of ".../Cellar/ntfs-3g-mac/2026.7.7/bin/ntfs-3g"
func cellarVersion(_ path: String) -> String? {
    let c = path.split(separator: "/").map(String.init)
    guard let i = c.firstIndex(of: "Cellar"), c.count > i + 2 else { return nil }
    return c[i + 2]
}

func isNewer(_ a: String, than b: String) -> Bool { a.compare(b, options: .numeric) == .orderedDescending }

/// Device id -> mount point for the volumes served by our own ntfs-3g, whichever FUSE layer it runs on.
///
/// macFUSE lists them as "/dev/disk4s1 on /Volumes/X (macfuse…)" but FUSE-T as "fuse-t:/X on /Volumes/X (nfs…)",
/// with no device in it, so the device comes from the ntfs-3g process instead (`ps -axww -o command=`):
///   /usr/local/libexec/ntfsmount/bin/ntfs-3g /dev/disk4s1 /Volumes/Backup (2) -o local,allow_other,…
/// Mount points may contain " (" and " on ". A volume only counts while `mount` really lists its mount point,
/// so a leftover process of a volume that is gone is ignored.
func parseNtfs3gMounts(ps: String, mount: String) -> [String: String] {
    var result: [String: String] = [:]
    for line in ps.split(separator: "\n") {
        let s = String(line)
        guard let tool = s.range(of: "ntfs-3g /dev/disk") else { continue }
        let rest = s[s.index(tool.upperBound, offsetBy: -4)...]            // "disk4s1 /Volumes/Backup (2) -o …"
        guard let sp = rest.firstIndex(of: " ") else { continue }
        let dev = String(rest[..<sp])
        guard dev.range(of: "^disk[0-9]+s[0-9]+$", options: .regularExpression) != nil else { continue }
        var mp = String(rest[rest.index(after: sp)...])
        if let o = mp.range(of: " -o ", options: .backwards) { mp = String(mp[..<o.lowerBound]) }
        guard mp.hasPrefix("/"), mount.contains(" on \(mp) (") else { continue }
        result[dev] = mp
    }
    return result
}

/// "1.2.9" out of the names in FUSE-T's bin folder (go-nfsv4, go-nfsv4-1.2.9).
func fuseTVersion(fromBinaryNames names: [String]) -> String? {
    names.compactMap { n -> String? in
        guard n.hasPrefix("go-nfsv4-") else { return nil }
        return String(n.dropFirst("go-nfsv4-".count))
    }.max { $0.compare($1, options: .numeric) == .orderedAscending }
}
