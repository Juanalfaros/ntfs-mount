import Foundation

/// The user-space file system layer ntfs-3g runs on. FUSE-T needs no kernel extension (the easy install);
/// macFUSE needs one, which on Apple Silicon means approving it in Recovery.
enum FuseBackend: String {
    case fuseT = "fuse-t", macFUSE = "macfuse"
    var name: String { self == .fuseT ? "FUSE-T" : "macFUSE" }
}

let fuseTHome = "/Library/Application Support/fuse-t"
/// Written by install-root.sh next to the private ntfs-3g copy: the layer that copy was built for.
let backendStampPath = "/usr/local/libexec/ntfsmount/BACKEND"
/// Run it in a terminal to install or repair everything (shown by the Welcome screen).
let installCommand = "curl -fsSL https://raw.githubusercontent.com/Juanalfaros/ntfs-mount/main/install.sh | sh"

var macFUSEOnDisk: Bool { FileManager.default.fileExists(atPath: "/Library/Filesystems/macfuse.fs") }
var fuseTOnDisk: Bool { FileManager.default.isExecutableFile(atPath: "\(fuseTHome)/bin/go-nfsv4") }

/// The stamp wins (it says what the private copy needs). Without one (installs made by 1.x) it is whatever is
/// installed, preferring macFUSE because that is what 1.x used.
func detectBackend() -> FuseBackend {
    if let s = try? String(contentsOfFile: backendStampPath, encoding: .utf8),
       let b = FuseBackend(rawValue: s.trimmingCharacters(in: .whitespacesAndNewlines)) { return b }
    if macFUSEOnDisk { return .macFUSE }
    if fuseTOnDisk { return .fuseT }
    return .fuseT
}
var backend: FuseBackend { detectBackend() }

var fuseInstalled: Bool { backend == .macFUSE ? macFUSEOnDisk : fuseTOnDisk }
var fuseVersion: String? {
    switch backend {
    case .macFUSE: return macFUSEVersion
    case .fuseT:
        let names = (try? FileManager.default.contentsOfDirectory(atPath: "\(fuseTHome)/bin")) ?? []
        return fuseTOnDisk ? (fuseTVersion(fromBinaryNames: names) ?? L("installed")) : nil
    }
}
/// macFUSE also needs its kernel extension loaded; FUSE-T is ready as soon as it is installed.
func fuseReady() -> Bool { backend == .macFUSE ? kextLoaded() : fuseTOnDisk }

/// ntfs-3g we can run: our private copy, or (before the first install, and in macFUSE mode) Homebrew's.
var ntfs3gAvailable: Bool { FileManager.default.isExecutableFile(atPath: secureNtfs3g) || ntfs3gPath != nil }

/// "2026.9.28" out of `ntfs-3g --version`.
func ntfs3gVersion(at path: String) -> String? {
    let out = run(path, ["--version"], timeout: 5).out
    let parts = out.split(separator: " ")
    return parts.count >= 2 && parts[0] == "ntfs-3g" ? String(parts[1]) : nil
}
