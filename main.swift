import Cocoa
import ServiceManagement
import DiskArbitration
import IOKit
import UserNotifications
import SwiftUI
import Combine

// MARK: - Log

let logURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/NTFSMount.log")
private let logQ = DispatchQueue(label: "ntfsmount.log")

/// Appends a timestamped line to ~/Library/Logs/NTFSMount.log (trimmed to its tail past ~500 KB).
func logLine(_ s: String) {
    logQ.async {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let line = "\(f.string(from: Date())) \(s.replacingOccurrences(of: "\n", with: " ⏎ "))\n"
        let fm = FileManager.default
        if let size = (try? fm.attributesOfItem(atPath: logURL.path))?[.size] as? Int, size > 500_000,
           let data = try? Data(contentsOf: logURL) {
            try? data.suffix(200_000).write(to: logURL)
        }
        if !fm.fileExists(atPath: logURL.path) { fm.createFile(atPath: logURL.path, contents: nil) }
        if let h = try? FileHandle(forWritingTo: logURL) {
            h.seekToEndOfFile()
            h.write(Data(line.utf8))
            try? h.close()
        }
    }
}

func logTail(_ n: Int) -> String {
    logQ.sync {
        guard let text = try? String(contentsOf: logURL, encoding: .utf8) else { return "(no log)" }
        return text.split(separator: "\n", omittingEmptySubsequences: true).suffix(n).joined(separator: "\n")
    }
}

// MARK: - Helpers

@discardableResult
func run(_ path: String, _ args: [String], timeout: TimeInterval? = nil) -> (status: Int32, out: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    do { try p.run() } catch { return (-1, "\(error)") }
    if let t = timeout { DispatchQueue.global().asyncAfter(deadline: .now() + t) { if p.isRunning { p.terminate() } } }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
}

func plist(_ args: [String]) -> [String: Any]? {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = Pipe()
    do { try p.run() } catch { return nil }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
}

var appVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?" }
var macFUSEVersion: String? {
    NSDictionary(contentsOfFile: "/Library/Filesystems/macfuse.fs/Contents/Info.plist")?["CFBundleShortVersionString"] as? String
}
func kextLoaded() -> Bool { run("/usr/bin/kmutil", ["showloaded", "--list-only"]).out.contains("io.macfuse") }

func shq(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

func fmtBytes(_ n: Int64) -> String { ByteCountFormatter.string(fromByteCount: n, countStyle: .file) }

func fmtRate(_ bps: Double) -> String {
    bps < 1000 ? "0 KB/s" : ByteCountFormatter.string(fromByteCount: Int64(bps), countStyle: .file) + "/s"
}

func fmtDuration(_ s: TimeInterval) -> String {
    let f = DateComponentsFormatter()
    f.allowedUnits = s >= 3600 ? [.hour, .minute] : [.minute, .second]
    f.unitsStyle = .abbreviated
    return f.string(from: max(s, 1)) ?? ""
}

/// Runs a shell command as root through the standard macOS password prompt.
func runAsAdmin(_ cmd: String) -> (ok: Bool, out: String) {
    let esc = cmd.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    let r = run("/usr/bin/osascript", ["-e", "do shell script \"\(esc)\" with administrator privileges"])
    return (r.status == 0, r.out.trimmingCharacters(in: .whitespacesAndNewlines))
}

// MARK: - Privileged helper

/// Root-owned copy of ntfsmount-helper plus a NOPASSWD sudoers rule for that one script
/// (installed once from the menu). Without it we fall back to the password prompt.
let helperPath = "/usr/local/libexec/ntfsmount-helper"
let secureNtfs3g = "/usr/local/libexec/ntfsmount/bin/ntfs-3g"
let secureSourceStamp = "/usr/local/libexec/ntfsmount/SOURCE"
var bundledHelper: String? { Bundle.main.path(forResource: "ntfsmount-helper", ofType: nil) }
var bundledInstaller: String? { Bundle.main.path(forResource: "install-root.sh", ofType: nil) }
var bundledUninstaller: String? { Bundle.main.path(forResource: "uninstall-root.sh", ofType: nil) }
var helperInstalled: Bool { FileManager.default.fileExists(atPath: helperPath) }
private var helperCache: (stamp: Date, ok: Bool)?
private let helperLock = NSLock()
func invalidateHelperCache() { helperLock.lock(); helperCache = nil; helperLock.unlock() }

var helperReady: Bool {
    // The installed copy must match the one bundled in the app, otherwise offer a reinstall.
    let fm = FileManager.default
    guard fm.isExecutableFile(atPath: helperPath), let src = bundledHelper,
          fm.contentsEqual(atPath: src, andPath: helperPath),
          fm.isExecutableFile(atPath: secureNtfs3g)
    else { return false }
    let modified = (try? fm.attributesOfItem(atPath: helperPath)[.modificationDate]) as? Date ?? .distantPast
    helperLock.lock(); defer { helperLock.unlock() }
    if let c = helperCache, c.ok, c.stamp == modified { return true }   // avoid a `sudo -l` (and a log line) per refresh
    let ok = run("/usr/bin/sudo", ["-n", "-l", helperPath]).status == 0
    helperCache = (modified, ok)
    return ok
}

/// The private copy still works after `brew upgrade`, it is just older: compare the ntfs-3g it was
/// made from (recorded by install-root.sh) with the one Homebrew has now.
func copyStatus() -> (stale: Bool, from: String?, to: String?) {
    guard backend == .macFUSE, let installed = ntfs3gPath,
          let stamp = try? String(contentsOfFile: secureSourceStamp, encoding: .utf8) else { return (false, nil, nil) }
    let old = stamp.trimmingCharacters(in: .whitespacesAndNewlines)
    let new = URL(fileURLWithPath: installed).resolvingSymlinksInPath().path
    return (old != new, cellarVersion(old), cellarVersion(new))
}

func privileged(_ args: [String]) -> (ok: Bool, out: String) {
    let r = privilegedRun(args)
    logLine("helper \(args.joined(separator: " ")) → " + (r.ok ? "ok" : "FAILED") + (r.out.isEmpty ? "" : ": \(String(r.out.prefix(400)))"))
    return r
}

private func privilegedRun(_ args: [String]) -> (ok: Bool, out: String) {
    if helperReady {
        let r = run("/usr/bin/sudo", ["-n", helperPath] + args)
        if r.status != 0 && r.out.contains("password is required") { invalidateHelperCache() }
        return (r.status == 0, r.out.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    guard let h = bundledHelper else { return (false, L("ntfsmount-helper was not found inside the app.")) }
    // Password-prompt fallback: no private ntfs-3g copy yet, so allow Homebrew's (the user just authenticated).
    return runAsAdmin("NTFSMOUNT_UNSAFE_BIN=1 " + (["/bin/sh", h] + args).map(shq).joined(separator: " ") + " 2>&1")
}

func installHelper() -> (ok: Bool, out: String) {
    guard let helper = bundledHelper, let installer = bundledInstaller else {
        return (false, L("Installation files are missing from the app."))
    }
    let user = NSUserName()
    guard user.range(of: "^[A-Za-z0-9_.-]+$", options: .regularExpression) != nil else {
        return (false, L("Unsupported user name: {0}", user))
    }
    invalidateHelperCache()
    // install-root.sh copies ntfs-3g to a root-owned folder, installs the helper and the sudoers rule
    return runAsAdmin("/bin/sh \(shq(installer)) \(shq(helper)) \(shq(user)) 2>&1")
}

let ntfs3gCandidates = ["/opt/homebrew/bin/ntfs-3g", "/usr/local/bin/ntfs-3g", "/opt/homebrew/sbin/ntfs-3g", "/usr/local/sbin/ntfs-3g"]
var ntfs3gPath: String? { ntfs3gCandidates.first { FileManager.default.isExecutableFile(atPath: $0) } }

// MARK: - Preferences

enum Pref {
    static let defaults: [String: Bool] = ["winNames": false]   // everything else defaults to on
    static func get(_ key: String) -> Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? defaults[key] ?? true }
    static func set(_ key: String, _ v: Bool) { UserDefaults.standard.set(v, forKey: key) }
    static var readOnlyUUIDs: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "readOnlyUUIDs") ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: "readOnlyUUIDs") }
    }
    /// Every NTFS disk seen, UUID -> last known name, for the Disks tab in Settings.
    static var knownDisks: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: "knownDisks") as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "knownDisks") }
    }
}

/// `category` adds action buttons (see App.registerNotificationActions); `info` travels back with the click.
func notify(_ title: String, _ body: String, category: String = "", info: [String: String] = [:]) {
    logLine("notice: \(title) — \(body)")
    let c = UNMutableNotificationContent()
    c.title = title
    c.body = body
    c.categoryIdentifier = category
    c.userInfo = info
    UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
}

// MARK: - Model

struct Vol {
    let dev: String          // e.g. disk4s1
    let name: String
    let size: Int64
    let mountPoint: String?
    let rw: Bool             // mounted through ntfs-3g (read/write)
    let parentDisk: String
    let uuid: String?
    let bus: String?         // USB, Thunderbolt, SATA...
}

/// A mounted external/removable volume that isn't NTFS (exFAT, FAT, APFS...). macOS handles it; we only show it.
struct Other {
    let dev: String
    let name: String
    let size: Int64
    let mountPoint: String
    let fs: String           // "exFAT", "FAT", "APFS"...
    let parentDisk: String
    let bus: String?
}

func fsDisplayName(_ kind: String) -> String {
    switch kind.lowercased() {
    case "exfat": return "exFAT"
    case "msdos": return "FAT"
    case "apfs": return "APFS"
    case "hfs": return "Mac OS Plus"
    case "udf": return "UDF"
    case "cd9660": return "CD/DVD"
    default: return kind.isEmpty ? L("Unknown") : kind.uppercased()
    }
}

/// Mounted volumes on removable or external media that aren't NTFS/FUSE and aren't disk images.
func scanOthers() -> [Other] {
    guard let session = DASessionCreate(kCFAllocatorDefault) else { return [] }
    let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) ?? []
    var out: [Other] = []
    for url in urls {
        guard let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, url as CFURL),
              let d = DADiskCopyDescription(disk) as? [String: Any],
              let bsd = d["DAMediaBSDName"] as? String else { continue }
        let kind = (d["DAVolumeKind"] as? String ?? "").lowercased()
        if ["ntfs", "macfuse", "fusefs", "osxfuse"].contains(kind) { continue }
        let proto = d["DADeviceProtocol"] as? String
        if (d["DADeviceModel"] as? String) == "Disk Image" || proto == "Virtual Interface" { continue }
        let internalDev = d["DADeviceInternal"] as? Bool ?? false
        let removable = d["DAMediaRemovable"] as? Bool ?? false
        let ejectable = d["DAMediaEjectable"] as? Bool ?? false
        guard !internalDev || removable || ejectable else { continue }
        let name = (d["DAVolumeName"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? url.lastPathComponent
        let size = (d["DAMediaSize"] as? NSNumber)?.int64Value ?? 0
        let parent = bsd.range(of: "s[0-9]+$", options: .regularExpression).map { String(bsd[..<$0.lowerBound]) } ?? bsd
        out.append(Other(dev: bsd, name: name, size: size, mountPoint: url.path, fs: fsDisplayName(kind), parentDisk: parent, bus: proto))
    }
    return out
}

func fuseMounts() -> [String: String] {   // device id -> mount point, whichever FUSE layer serves it
    parseNtfs3gMounts(ps: run("/bin/ps", ["-axww", "-o", "command="]).out, mount: run("/sbin/mount", []).out)
}

func scanVolumes() -> [Vol] {
    guard let list = plist(["list", "-plist"]),
          let disks = list["AllDisksAndPartitions"] as? [[String: Any]] else { return [] }
    let fuse = fuseMounts()
    var items: [(String, String)] = []   // (dev, parent)
    for d in disks {
        let parent = d["DeviceIdentifier"] as? String ?? ""
        let parts = (d["Partitions"] as? [[String: Any]]) ?? [d]
        for p in parts {
            let content = p["Content"] as? String ?? ""
            guard let id = p["DeviceIdentifier"] as? String else { continue }
            if content == "Microsoft Basic Data" || content == "Windows_NTFS" || fuse[id] != nil {
                items.append((id, parent))
            }
        }
    }
    // `diskutil info` on a partition reads a block from the disk, which resets the drive's idle timer and
    // keeps a hard disk spinning forever. DiskArbitration descriptions come from its cache instead; the
    // probe is only a fallback for an unmounted partition whose file system DA can't name, once per device.
    guard let session = DASessionCreate(kCFAllocatorDefault) else { return [] }
    probeLock.lock(); defer { probeLock.unlock() }
    let present = Set(items.map { $0.0 })
    probeCache = probeCache.filter { present.contains($0.key) }
    var vols: [Vol] = []
    for (id, parent) in items {
        var desc: [String: Any] = [:]
        if let d = DADiskCreateFromBSDName(kCFAllocatorDefault, session, "/dev/" + id),
           let c = DADiskCopyDescription(d) as? [String: Any] { desc = c }
        let mp = fuse[id]
        var kind = (desc["DAVolumeKind"] as? String ?? "").lowercased()
        var name = (desc["DAVolumeName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        var size = (desc["DAMediaSize"] as? NSNumber)?.int64Value ?? 0
        var uuid = [desc["DAMediaUUID"], desc["DAVolumeUUID"]].lazy.compactMap { $0 }
            .first { CFGetTypeID($0 as CFTypeRef) == CFUUIDGetTypeID() }
            .flatMap { CFUUIDCreateString(nil, ($0 as! CFUUID)) as String? }
        var bus = desc["DADeviceProtocol"] as? String
        var mount = mp ?? (desc["DAVolumePath"] as? URL)?.path
        if kind.isEmpty && mp == nil {
            let info: [String: Any]
            if let c = probeCache[id] { info = c } else {
                info = plist(["info", "-plist", "/dev/" + id]) ?? [:]
                probeCache[id] = info
            }
            kind = (info["FilesystemType"] as? String ?? "").lowercased()
            name = name ?? (info["VolumeName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            if size == 0 { size = (info["TotalSize"] as? Int64) ?? Int64(info["TotalSize"] as? Int ?? 0) }
            uuid = uuid ?? (info["DiskUUID"] as? String) ?? (info["VolumeUUID"] as? String)
            bus = bus ?? info["BusProtocol"] as? String
            mount = (info["MountPoint"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        }
        guard mp != nil || kind == "ntfs" else { continue }
        let shown = name ?? mp.map { ($0 as NSString).lastPathComponent } ?? "NTFS"
        // MBR disks have no partition UUID and a FUSE mount hides the volume's: fall back to name + size
        // so "always read-only" and the remembered-disks list still work for them.
        if uuid == nil, size > 0 { uuid = "ntfs:\(shown)|\(size)" }
        vols.append(Vol(dev: id, name: shown, size: size,
                        mountPoint: mount, rw: mp != nil, parentDisk: parent, uuid: uuid, bus: bus))
    }
    return vols
}
private let probeLock = NSLock()
private var probeCache: [String: [String: Any]] = [:]

// MARK: - Monitoring

func capacity(_ path: String) -> (total: Int64, free: Int64)? {
    var s = statfs()
    guard statfs(path, &s) == 0 else { return nil }
    let bs = Int64(s.f_bsize)
    return (Int64(s.f_blocks) * bs, Int64(s.f_bavail) * bs)
}

/// Cumulative bytes read/written by a whole disk (e.g. "disk4"), from the IOKit block storage driver.
func diskCounters(_ bsd: String) -> (read: UInt64, write: UInt64)? {
    guard let match = IOBSDNameMatching(kIOMainPortDefault, 0, bsd) else { return nil }
    let media = IOServiceGetMatchingService(kIOMainPortDefault, match)   // consumes `match`
    guard media != 0 else { return nil }
    var cur = media
    for _ in 0..<8 {
        var parent: io_registry_entry_t = 0
        let kr = IORegistryEntryGetParentEntry(cur, kIOServicePlane, &parent)
        IOObjectRelease(cur)
        guard kr == KERN_SUCCESS else { return nil }
        cur = parent
        if IOObjectConformsTo(cur, "IOBlockStorageDriver") != 0 {
            defer { IOObjectRelease(cur) }
            guard let st = IORegistryEntryCreateCFProperty(cur, "Statistics" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? [String: Any] else { return nil }
            let r = (st["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
            let w = (st["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
            return (r, w)
        }
    }
    IOObjectRelease(cur)
    return nil
}

/// Processes with files open on these volumes, named after the app they belong to
/// ("Terminal (zsh)"). Only the user's own processes are visible, which covers what they can close.
func blockers(_ mountPoints: [String]) -> [(name: String, app: NSRunningApplication?)] {
    guard !mountPoints.isEmpty else { return [] }
    // a mount point as argument makes lsof list every open file on that file system
    let out = run("/usr/sbin/lsof", ["-n", "-P", "-w", "-F", "pc", "--"] + mountPoints, timeout: 10).out
    var procs: [(pid_t, String)] = []
    var pid: pid_t = 0
    for l in out.split(separator: "\n") {
        if l.hasPrefix("p") { pid = pid_t(l.dropFirst()) ?? 0 }
        else if l.hasPrefix("c"), pid > 0, pid != getpid() { procs.append((pid, String(l.dropFirst()))) }
    }
    var seen = Set<String>()
    var result: [(name: String, app: NSRunningApplication?)] = []
    for (p, cmd) in procs {
        let app = owningApp(p)
        let appName = app?.localizedName ?? cmd
        let name = app == nil || app?.processIdentifier == p ? appName : "\(appName) (\(cmd))"
        if seen.insert(name).inserted { result.append((name, app)) }
    }
    return result
}

/// The GUI app a process belongs to, walking up its parents (zsh → login → Terminal).
func owningApp(_ pid: pid_t) -> NSRunningApplication? {
    var p = pid
    for _ in 0..<12 {
        if let a = NSRunningApplication(processIdentifier: p), a.activationPolicy != .prohibited { return a }
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, p]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        p = info.kp_eproc.e_ppid
        if p <= 1 { return nil }
    }
    return nil
}

// MARK: - UI components

func sym(_ name: String, _ color: NSColor? = nil, size: CGFloat = 14) -> NSImage? {
    var cfg = NSImage.SymbolConfiguration(pointSize: size, weight: .regular)
    if let c = color { cfg = cfg.applying(.init(hierarchicalColor: c)) }
    let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(cfg)
    img?.isTemplate = (color == nil)
    return img
}

func txt(_ s: String, _ font: NSFont, _ color: NSColor, truncate: Bool = false) -> NSAttributedString {
    var a: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    if truncate {
        let p = NSMutableParagraphStyle()
        p.lineBreakMode = .byTruncatingTail
        a[.paragraphStyle] = p
    }
    return NSAttributedString(string: s, attributes: a)
}

/// "Reduce motion" in Accessibility settings: no easing, no pulsing.
var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

/// SF Symbol for a disk, by the bus it hangs from.
func driveSymbol(_ bus: String?) -> String {
    switch (bus ?? "").lowercased() {
    case let b where b.contains("secure digital") || b == "sd": return "sdcard.fill"
    case "thunderbolt": return "bolt.horizontal.fill"
    case "sata", "pci-express", "apple fabric", "nvme": return "internaldrive.fill"
    default: return "externaldrive.fill"
    }
}

enum CardAction: Int { case open, eject, mount }

struct Card {
    var name = ""
    var sizeText = ""
    var state = ""
    var stateIcon: String?       // glyph inside the badge
    var stateColor = NSColor.secondaryLabelColor
    var mounted = false
    var icon = "externaldrive.fill"
    var actions: [CardAction] = []
    var busyText: String?        // "Montando…" while an operation on this disk runs
    var frac: Double?            // used fraction 0...1
    var usedText = ""
    var freeText = ""
    var freePct = ""             // big "62 % libre" figure
    var eta = ""                 // "se llena en ~12 min" while writing
    var r = 0.0, w = 0.0         // bytes/s
    var history: [Double] = []   // recent total throughput samples
    var writing: Bool { w > 1_000_000 }

    /// What VoiceOver reads for the whole card.
    var spoken: String {
        var s = [name, sizeText.replacingOccurrences(of: " · ", with: ", "), busyText ?? state]
        if !freePct.isEmpty { s += [freePct, usedText, freeText] }
        if mounted { s.append(L("read {0}, write {1}", fmtRate(r), fmtRate(w))) }
        if !eta.isEmpty { s.append(eta) }
        return s.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

/// Borderless icon button with a soft rounded highlight on hover.
final class HoverButton: NSButton {
    private var hovering = false { didSet { needsDisplay = true } }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with e: NSEvent) { hovering = true }
    override func mouseExited(with e: NSEvent) { hovering = false }
    override func draw(_ r: NSRect) {
        if hovering && isEnabled {
            NSColor.labelColor.withAlphaComponent(0.1).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        }
        super.draw(r)
    }
}

/// One card per volume: icon, name, state badge, action buttons, usage bar, speeds and a small activity graph.
/// Clicking the card itself opens the volume in Finder.
final class VolumeCardView: NSView {
    static let width: CGFloat = 330
    static func height(_ c: Card) -> CGFloat { c.mounted ? 134 : 48 }

    var card: Card { didSet { cardChanged() } }
    var onAction: ((CardAction) -> Void)?
    override var isFlipped: Bool { true }

    private var shown: Double            // bar fill currently drawn (eases toward card.frac)
    private var phase = 0.0              // pulse phase while writing
    private var timer: Timer?
    private var hovered = false
    private var controls: [NSView] = []
    private var controlsKey = ""

    init(_ c: Card) {
        card = c
        shown = c.frac ?? 0
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: Self.height(c)))
        autoresizingMask = [.width]
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        cardChanged()
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { timer?.invalidate() }

    private func cardChanged() {
        if reduceMotion { shown = card.frac ?? 0 }
        needsDisplay = true
        layoutControls()
        setAccessibilityLabel(card.spoken)
        startAnimating()
    }

    // MARK: controls

    private var clickable: Bool { card.mounted && card.busyText == nil && card.actions.contains(.open) }

    /// Buttons on the right of the header; a spinner instead while the disk is busy.
    private func layoutControls() {
        let key = card.busyText != nil ? "busy" : card.actions.map { "\($0.rawValue)" }.joined() + "\(card.mounted)"
        guard key != controlsKey else { return }
        controlsKey = key
        controls.forEach { $0.removeFromSuperview() }
        controls = []
        var x = bounds.width - 10
        let y: CGFloat = card.mounted ? 9 : 11
        if card.busyText != nil {
            let s = NSProgressIndicator(frame: NSRect(x: x - 21, y: y + 5, width: 16, height: 16))
            s.style = .spinning
            s.controlSize = .small
            s.startAnimation(nil)
            s.autoresizingMask = [.minXMargin]
            addSubview(s)
            controls = [s]
            return
        }
        for a in card.actions.reversed() {
            let b: NSButton
            if a == .mount && !card.mounted {
                b = NSButton(title: L("Mount"), target: self, action: #selector(tapped(_:)))
                b.bezelStyle = .push
                b.controlSize = .small
                b.font = .systemFont(ofSize: 11, weight: .medium)
                b.sizeToFit()
                b.frame.origin = NSPoint(x: x - b.frame.width, y: y + 1)
                b.toolTip = L("Mount with write access")
            } else {
                let (icon, tip) = Self.look(a)
                let h = HoverButton(image: sym(icon, size: 13) ?? NSImage(), target: self, action: #selector(tapped(_:)))
                h.isBordered = false
                h.imagePosition = .imageOnly
                h.contentTintColor = .secondaryLabelColor
                h.frame = NSRect(x: x - 26, y: y, width: 26, height: 26)
                h.toolTip = tip
                h.setAccessibilityLabel(tip)
                b = h
            }
            b.tag = a.rawValue
            b.autoresizingMask = [.minXMargin]
            addSubview(b)
            controls.append(b)
            x = b.frame.minX - 2
        }
    }

    static func look(_ a: CardAction) -> (icon: String, tip: String) {
        switch a {
        case .open: return ("folder", L("Open in Finder"))
        case .eject: return ("eject", L("Eject disk"))
        case .mount: return ("square.and.pencil", L("Mount with write access"))
        }
    }

    @objc private func tapped(_ b: NSButton) {
        if let a = CardAction(rawValue: b.tag) { onAction?(a) }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with e: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with e: NSEvent) { hovered = false; needsDisplay = true }
    override func mouseUp(with e: NSEvent) { if clickable { onAction?(.open) } }

    // MARK: animation

    /// Runs only while something moves (bar easing or write pulse) and only while the card is on screen.
    private func startAnimating() {
        guard timer == nil, needsTick else { return }
        let t = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)   // .common so it also runs while the menu is open
        timer = t
    }

    private var needsTick: Bool {
        card.mounted && !reduceMotion && (card.writing || abs((card.frac ?? 0) - shown) > 0.0005)
    }

    private func tick() {
        guard window != nil, needsTick else { timer?.invalidate(); timer = nil; needsDisplay = true; return }
        let target = card.frac ?? 0
        shown = abs(target - shown) < 0.0005 ? target : shown + (target - shown) * 0.22
        phase += 0.2
        needsDisplay = true
    }

    // MARK: drawing

    override func draw(_ dirty: NSRect) {
        let w = bounds.width, pad: CGFloat = 16
        let controlsMinX = controls.map { $0.frame.minX }.min() ?? (w - 10)

        if hovered && clickable {
            NSColor.labelColor.withAlphaComponent(0.06).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 1), xRadius: 8, yRadius: 8).fill()
        }

        // icon (pulses while the disk is being written to) + name
        let pulse = card.mounted && card.writing && !reduceMotion ? 0.7 + 0.3 * sin(phase) : 1
        (sym(card.icon, card.stateColor, size: 17) ?? sym("externaldrive.fill", card.stateColor, size: 17))?
            .draw(in: NSRect(x: pad, y: 11, width: 24, height: 20), from: .zero, operation: .sourceOver, fraction: CGFloat(pulse))
        txt(card.name, .systemFont(ofSize: 13, weight: .semibold), .labelColor, truncate: true)
            .draw(in: NSRect(x: pad + 32, y: 6, width: max(0, controlsMinX - pad - 38), height: 17))

        // size, then the state badge right after it
        let size = txt(card.sizeText, .systemFont(ofSize: 11), .secondaryLabelColor)
        size.draw(at: NSPoint(x: pad + 32, y: 23))
        let busy = card.busyText != nil
        let color = busy ? NSColor.systemBlue : card.stateColor
        let label = txt(card.busyText ?? card.state, .systemFont(ofSize: 9.5, weight: .semibold), color)
        let glyph = busy ? nil : card.stateIcon.flatMap { sym($0, color, size: 8) }
        let gw: CGFloat = glyph == nil ? 0 : 12
        let pill = NSRect(x: pad + 32 + size.size().width + 6, y: 23.5, width: label.size().width + gw + 12, height: 15)
        color.withAlphaComponent(0.16).setFill()
        NSBezierPath(roundedRect: pill, xRadius: 7.5, yRadius: 7.5).fill()
        glyph?.draw(in: NSRect(x: pill.minX + 6, y: pill.minY + 3.5, width: 9, height: 8))
        label.draw(at: NSPoint(x: pill.minX + 6 + gw, y: pill.minY + (15 - label.size().height) / 2))

        guard card.mounted else { return }

        // big free-space figure, and a fill-up estimate while writing
        if !card.freePct.isEmpty {
            txt(card.freePct, .systemFont(ofSize: 17, weight: .semibold), .labelColor).draw(at: NSPoint(x: pad, y: 44))
        }
        if !card.eta.isEmpty {
            let eta = txt(card.eta, .systemFont(ofSize: 11, weight: .medium), .systemOrange)
            eta.draw(at: NSPoint(x: w - pad - eta.size().width, y: 49))
        }

        // usage bar (green → orange → red as it fills up), with a mark at 90 %
        let bar = NSRect(x: pad, y: 70, width: w - 2 * pad, height: 7)
        NSColor.quaternaryLabelColor.setFill()
        NSBezierPath(roundedRect: bar, xRadius: 3.5, yRadius: 3.5).fill()
        if card.frac != nil {
            let f = shown
            let col: NSColor = f < 0.75 ? .systemGreen : (f < 0.9 ? .systemOrange : .systemRed)
            var fill = bar
            fill.size.width = max(7, bar.width * CGFloat(min(max(f, 0), 1)))
            let path = NSBezierPath(roundedRect: fill, xRadius: 3.5, yRadius: 3.5)
            NSGradient(starting: col.highlight(withLevel: 0.3) ?? col, ending: col)?.draw(in: path, angle: 90)
        }
        let markX = bar.minX + bar.width * 0.9
        NSColor.labelColor.withAlphaComponent(0.35).setFill()
        NSRect(x: markX - 0.5, y: bar.minY - 2, width: 1, height: bar.height + 4).fill()

        txt(card.usedText, .systemFont(ofSize: 11), .labelColor).draw(at: NSPoint(x: pad, y: 82))
        let free = txt(card.freeText, .systemFont(ofSize: 11), .secondaryLabelColor)
        free.draw(at: NSPoint(x: w - pad - free.size().width, y: 82))

        // speeds
        let mono = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .medium)
        txt("↓", .systemFont(ofSize: 13, weight: .bold), .systemBlue).draw(at: NSPoint(x: pad, y: 109))
        txt(fmtRate(card.r), mono, .labelColor).draw(at: NSPoint(x: pad + 13, y: 110))
        txt("↑", .systemFont(ofSize: 13, weight: .bold), .systemOrange).draw(at: NSPoint(x: pad + 108, y: 109))
        txt(fmtRate(card.w), mono, .labelColor).draw(at: NSPoint(x: pad + 121, y: 110))

        // activity graph (last ~60 s) with a baseline and the peak
        let gwd: CGFloat = 70, gh: CGFloat = 15, gx = w - pad - gwd, gy: CGFloat = 112
        let peak = max(card.history.max() ?? 0, 1_000_000)
        if let top = card.history.max(), top > 1_000_000 {
            let p = txt(L("max. {0}", fmtRate(top)), .systemFont(ofSize: 9), .tertiaryLabelColor)
            p.draw(at: NSPoint(x: w - pad - p.size().width, y: 100))
        }
        let n = 30, bw = gwd / CGFloat(n)
        let samples = Array(card.history.suffix(n))
        for (i, v) in samples.enumerated() {
            let x = gx + CGFloat(n - samples.count + i) * bw
            let h = max(1.5, gh * CGFloat(v / peak))
            (v > 100_000 ? NSColor.systemTeal : NSColor.quaternaryLabelColor).setFill()
            NSBezierPath(roundedRect: NSRect(x: x + 0.4, y: gy + gh - h, width: bw - 0.8, height: h), xRadius: 1, yRadius: 1).fill()
        }
        NSColor.separatorColor.setFill()
        NSRect(x: gx, y: gy + gh + 0.5, width: gwd, height: 0.5).fill()
    }
}

/// Shown instead of the cards when no NTFS disk is connected.
final class EmptyCardView: NSView {
    override var isFlipped: Bool { true }
    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: VolumeCardView.width, height: 56))
        autoresizingMask = [.width]
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(L("No NTFS disks connected. Plug in a Windows disk and it will show up here."))
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirty: NSRect) {
        sym("externaldrive.badge.questionmark", .tertiaryLabelColor, size: 20)?.draw(in: NSRect(x: 16, y: 14, width: 28, height: 26))
        txt(L("No NTFS disks connected"), .systemFont(ofSize: 13, weight: .semibold), .secondaryLabelColor).draw(at: NSPoint(x: 54, y: 11))
        txt(L("Plug in a Windows disk and it will show up here."), .systemFont(ofSize: 11), .tertiaryLabelColor).draw(at: NSPoint(x: 54, y: 29))
    }
}

// MARK: - Settings and Welcome windows

struct KnownDisk: Identifiable {
    let uuid: String
    let name: String
    let connected: Bool
    let readOnly: Bool
    var id: String { uuid }
}

/// Setup state for the Settings and Welcome windows; the slow checks run off the main thread.
final class SetupModel: ObservableObject {
    @Published var fuse: String?             // installed version of the FUSE layer (macFUSE or FUSE-T)
    @Published var kext = false
    @Published var ntfs3g: String?           // version of the ntfs-3g in use
    @Published var privateCopy: String?
    @Published var stale = false
    @Published var helper = false
    @Published var fuseIssue: String?
    @Published var login = SMAppService.mainApp.status == .enabled
    @Published var disks: [KnownDisk] = []
    @Published var copied: String?           // which "Copiar" button shows "Copiado ✓" (no @State: it's a macro swiftc can't expand here)
    private var loading = false

    func flashCopied(_ key: String) {
        copied = key
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { if self.copied == key { self.copied = nil } }
    }

    var installed: Bool { fuse != nil && ntfs3g != nil }
    var complete: Bool { installed && fuseIssue == nil && helper }

    func reload() {
        reloadDisks()
        guard !loading else { return }
        loading = true
        let issue = delegate.fuseIssue
        DispatchQueue.global().async {
            let fuse = fuseVersion
            let k = fuse != nil && fuseReady()
            let priv = FileManager.default.isExecutableFile(atPath: secureNtfs3g) ? ntfs3gVersion(at: secureNtfs3g) : nil
            let n = priv ?? ntfs3gPath.map { cellarVersion(URL(fileURLWithPath: $0).resolvingSymlinksInPath().path) ?? L("installed") }
            let stamp = (try? String(contentsOfFile: secureSourceStamp, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
            let copy = stamp.flatMap { cellarVersion($0) } ?? priv
            let st = copyStatus().stale
            let h = helperReady
            DispatchQueue.main.async {
                (self.fuse, self.kext, self.ntfs3g, self.privateCopy, self.stale, self.helper) = (fuse, k, n, copy, st, h)
                self.fuseIssue = issue
                self.login = SMAppService.mainApp.status == .enabled
                self.loading = false
            }
        }
    }

    func reloadDisks() { disks = delegate.knownDisks() }
}

struct StatusRow: View {
    let ok: Bool, title: String, detail: String
    var body: some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(ok ? Color.green : Color.orange)
                .accessibilityLabel(ok ? L("All good") : L("Needs attention"))
            Text(title)
            Spacer()
            Text(detail).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: SetupModel
    var body: some View {
        TabView {
            GeneralTab(model: model).tabItem { Label(L("General"), systemImage: "gearshape") }
            MountTab(model: model).tabItem { Label(L("Mounting"), systemImage: "externaldrive") }
            DisksTab(model: model).tabItem { Label(L("Disks"), systemImage: "list.bullet") }
            AdvancedTab(model: model).tabItem { Label(L("Advanced"), systemImage: "wrench.and.screwdriver") }
        }
        .frame(width: 540, height: 440)
    }
}

struct GeneralTab: View {
    @ObservedObject var model: SetupModel
    @AppStorage("showSpeed") var showSpeed = true
    @AppStorage("showOthers") var showOthers = true
    var body: some View {
        Form {
            Section {
                Toggle(L("Open NTFS Mount at login"), isOn: Binding(
                    get: { model.login },
                    set: { delegate.setLogin($0); model.login = SMAppService.mainApp.status == .enabled }))
            }
            Section {
                Toggle(L("Show the speed in the menu bar"), isOn: $showSpeed)
                Toggle(L("Show “Other volumes” (exFAT, FAT, APFS…)"), isOn: $showOthers)
            } header: { Text(L("Menu")) } footer: {
                Text(L("The speed only shows while an NTFS disk is active.")).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct MountTab: View {
    @ObservedObject var model: SetupModel
    @AppStorage("autoMount") var autoMount = true
    @AppStorage("unmountOnSleep") var unmountOnSleep = true
    @AppStorage("noIndex") var noIndex = true
    @AppStorage("winNames") var winNames = false
    var body: some View {
        Form {
            Section {
                Toggle(L("Mount automatically with write access"), isOn: $autoMount)
                Toggle(L("Unmount on sleep or shutdown"), isOn: $unmountOnSleep)
                Toggle(L("Keep Spotlight from indexing the disks"), isOn: $noIndex)
            } header: { Text(L("Automatic")) } footer: {
                if !model.helper {
                    Text(L("These need passwordless mounting. Turn it on in the Advanced tab.")).foregroundStyle(.orange)
                }
            }
            .disabled(!model.helper)
            Section {
                Toggle(L("Windows-compatible file names"), isOn: $winNames)
            } footer: {
                Text(L("Prevents creating names Windows doesn’t accept (with : * ? \" < > | or ending in a dot or space). Applies on the next mount."))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct DisksTab: View {
    @ObservedObject var model: SetupModel
    var body: some View {
        Form {
            Section {
                if model.disks.isEmpty {
                    Text(L("You haven’t connected any NTFS disk yet.")).foregroundStyle(.secondary)
                }
                ForEach(model.disks) { d in
                    HStack(spacing: 10) {
                        Image(systemName: d.connected ? "externaldrive.fill" : "externaldrive")
                            .foregroundStyle(d.connected ? Color.accentColor : Color.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(d.name)
                            Text(d.connected ? L("Connected") : L("Not connected")).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle(L("Always read-only"), isOn: Binding(
                            get: { d.readOnly },
                            set: { delegate.setReadOnly(uuid: d.uuid, $0); model.reloadDisks() }))
                        .toggleStyle(.checkbox)
                        Button(L("Forget")) { delegate.forgetDisk(d.uuid); model.reloadDisks() }
                            .disabled(d.connected)
                            .help(d.connected ? L("Disconnect it first") : L("Remove it from this list"))
                    }
                }
            } header: { Text(L("Remembered disks")) } footer: {
                Text(L("A read-only disk is never mounted with write access automatically. You can mount it with write access once from its card in the menu."))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { model.reloadDisks() }
    }
}

struct AdvancedTab: View {
    @ObservedObject var model: SetupModel
    var body: some View {
        Form {
            Section(L("Status")) {
                StatusRow(ok: model.fuse != nil && model.fuseIssue == nil, title: backend.name,
                          detail: model.fuse.map { backend == .macFUSE ? L("{0} · extension {1}", $0, model.kext ? L("loaded") : L("not loaded")) : L("{0} · no kernel extension needed", $0) } ?? L("Not installed"))
                StatusRow(ok: model.ntfs3g != nil, title: "ntfs-3g", detail: model.ntfs3g ?? L("Not installed"))
                StatusRow(ok: model.helper && !model.stale, title: L("Passwordless mounting"),
                          detail: model.helper ? (model.stale ? L("Active · copy {0} (outdated)", model.privateCopy ?? "?") : L("Active · copy {0}", model.privateCopy ?? "?")) : L("Disabled"))
                if let issue = model.fuseIssue { Text(issue).font(.caption).foregroundStyle(.orange) }
            }
            Section(L("Maintenance")) {
                Button(model.helper ? (model.stale ? L("Update the ntfs-3g copy…") : L("Reinstall passwordless mounting…"))
                                    : L("Turn on passwordless mounting…")) { delegate.installHelperAction() }
                    .disabled(!model.installed)
                Button(L("Check for {0} updates…", backend.name)) { delegate.checkMacFUSEUpdate() }
                HStack {
                    Button(model.copied == "diag" ? L("Diagnostics copied ✓") : L("Copy diagnostics")) {
                        delegate.copyDiagnostics()
                        model.flashCopied("diag")
                    }
                    Button(L("View log")) { delegate.openLog() }
                    Button(L("Show the welcome screen")) { delegate.showWelcome() }
                }
            }
            Section {
                Button(L("Uninstall privileged components…"), role: .destructive) { delegate.uninstallAction() }
                    .foregroundStyle(helperInstalled ? Color.red : Color.secondary)
                    .disabled(!helperInstalled)
            } footer: {
                Text(L("Removes the sudoers rule, the helper and the private copy of ntfs-3g. The app keeps working by asking for your password."))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// First-run checklist: macFUSE, ntfs-3g and the password-less mount, each with what to do next.
struct WelcomeView: View {
    @ObservedObject var model: SetupModel
    var done: () -> Void
    private let tick = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(systemName: model.complete ? "externaldrive.fill.badge.checkmark" : "externaldrive.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(model.complete ? Color.green : Color.accentColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Welcome to NTFS Mount")).font(.title2.bold())
                    Text(model.complete ? L("All set. Plug in a Windows disk and it will appear in the menu bar.")
                                        : L("To write to Windows disks, these steps are missing:"))
                        .foregroundStyle(.secondary)
                }
            }
            StepRow(n: 1, done: model.fuse != nil && model.fuseIssue == nil, title: L("Install {0}", backend.name),
                    detail: model.fuse == nil ? L("Lets macOS use file systems such as NTFS.")
                          : model.fuseIssue != nil ? L("Installed, but macOS hasn’t loaded the extension. Approve it in Privacy & Security and restart.")
                          : L("Version {0}", model.fuse ?? ""),
                    command: model.fuse == nil ? (backend == .macFUSE ? "brew install --cask macfuse" : installCommand) : nil,
                    action: model.fuse != nil && model.fuseIssue != nil ? (L("Open Privacy & Security"), {
                        if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security") { NSWorkspace.shared.open(u) }
                    }) : nil, model: model)
            StepRow(n: 2, done: model.ntfs3g != nil, title: L("Install ntfs-3g"),
                    detail: model.ntfs3g == nil ? L("The driver that reads and writes NTFS.") : L("Version {0}", model.ntfs3g ?? ""),
                    command: model.ntfs3g == nil ? (backend == .macFUSE ? "brew tap gromgit/homebrew-fuse && brew install ntfs-3g-mac" : installCommand) : nil, model: model)
            StepRow(n: 3, done: model.helper, title: L("Turn on passwordless mounting"),
                    detail: L("Just once: after that, disks mount on their own without asking for your password."),
                    action: model.helper ? nil : (L("Turn on…"), { delegate.installHelperAction() }),
                    enabled: model.installed, model: model)
            Divider()
            Toggle(L("Open NTFS Mount at login"), isOn: Binding(
                get: { model.login },
                set: { delegate.setLogin($0); model.login = SMAppService.mainApp.status == .enabled }))
            HStack {
                if !model.installed {
                    if backend == .macFUSE { Link(L("The commands need Homebrew (brew.sh)"), destination: URL(string: "https://brew.sh")!).font(.caption) }
                }
                Spacer()
                Button(model.complete ? L("Get started") : L("Finish later")) { done() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 540)
        .onAppear { model.reload() }
        .onReceive(tick) { _ in model.reload() }
    }
}

struct StepRow: View {
    let n: Int, done: Bool, title: String, detail: String
    var command: String? = nil
    var action: (String, () -> Void)? = nil
    var enabled = true
    @ObservedObject var model: SetupModel

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(done ? Color.green : Color.secondary.opacity(0.2)).frame(width: 26, height: 26)
                if done { Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.white) }
                else { Text("\(n)").font(.system(size: 13, weight: .semibold)) }
            }
            .accessibilityLabel(done ? L("Step {0} done", n) : L("Step {0} pending", n))
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline).foregroundStyle(enabled || done ? Color.primary : Color.secondary)
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if !done, let c = command {
                    HStack {
                        Text(c).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.12)))
                        Button(model.copied == c ? L("Copied ✓") : L("Copy")) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(c, forType: .string)
                            model.flashCopied(c)
                        }
                        .controlSize(.small)
                    }
                }
                if !done, let a = action {
                    Button(a.0, action: a.1).disabled(!enabled)
                }
            }
        }
    }
}

// MARK: - App

final class App: NSObject, NSApplicationDelegate, NSMenuDelegate, UNUserNotificationCenterDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let menu = NSMenu()
    var vols: [Vol] = []
    var others: [Other] = []
    var busy = false
    var helperOK = false
    var copyStale: (from: String?, to: String?)?   // set when Homebrew's ntfs-3g is newer than our private copy
    var staleNotified = false
    var fuseIssue: String?                         // why macFUSE can't be used right now, if it can't
    var lastLoggedSig = ""
    var menuOpen = false
    var menuSignature = ""
    var iconKey = ""
    var retried = Set<String>()          // devices whose automatic mount already got its one retry

    var attempted = Set<String>()        // devices we already tried to mount (until unplugged)
    var userUnmounted = Set<String>()    // devices the user unmounted on purpose
    var ejectedDevs = Set<String>()      // devices we ejected (so their removal isn't "unsafe")
    var knownMountPoints = Set<String>() // FUSE mount points seen, to clean up leftovers
    var mountedAt: [String: Date] = [:]
    var lowSpaceNotified = Set<String>()

    // monitoring
    let sampleQ = DispatchQueue(label: "ntfsmount.sample")
    var lastCounters: [String: (t: Date, r: UInt64, w: UInt64)] = [:]
    var baseCounters: [String: (r: UInt64, w: UInt64)] = [:]
    var speeds: [String: (r: Double, w: Double)] = [:]   // parent disk -> bytes/s
    var live: [String: VolumeCardView] = [:]
    var history: [String: [Double]] = [:]   // parent disk -> recent throughput
    var wSmooth: [String: Double] = [:]     // parent disk -> smoothed write bytes/s

    var capCache: [String: (total: Int64, free: Int64)] = [:]   // by mount point; filled off the main thread
    var capBusy = false
    var capStamp = Date.distantPast
    let jobQ = DispatchQueue(label: "ntfsmount.jobs")             // privileged actions run one at a time
    var jobs = 0

    var daSession: DASession?
    var pendingRefresh: DispatchWorkItem?
    var pendingPrefs: DispatchWorkItem?

    var busyDevs: [String: String] = [:]   // device -> "Montando…" while an operation on it runs
    var lastActive = Date.distantPast      // last time any disk moved > 100 KB/s (menu bar speed)
    var firstApply = true
    let setup = SetupModel()
    var settingsWindow: NSWindow?
    var welcomeWindow: NSWindow?

    // MARK: lifecycle

    func applicationDidFinishLaunching(_ n: Notification) {
        item.button?.imagePosition = .imageLeading
        updateIcon()
        menu.delegate = self
        item.menu = menu
        rebuild()

        let un = UNUserNotificationCenter.current()
        un.delegate = self
        un.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        registerNotificationActions()
        installMainMenu()
        startDiskEvents()
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.prefsChanged()
        }

        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.refresh() }   // safety net; DiskArbitration events do the real work
        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.sample() }
        RunLoop.main.add(t, forMode: .common)   // keeps ticking while the menu is open

        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.beforeSleep() }
        nc.addObserver(forName: NSWorkspace.willPowerOffNotification, object: nil, queue: .main) { [weak self] _ in self?.beforeSleep() }
        nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.attempted.removeAll()
            self?.scheduleRefresh()
            self?.checkFUSE()
        }
        logLine("app started (v\(appVersion), \(backend.name) \(fuseVersion ?? "not installed"))")
        refresh()
        checkFUSE()
    }

    /// DiskArbitration tells us when disks appear, disappear or (un)mount, so no tight polling is needed.
    func startDiskEvents() {
        guard let s = DASessionCreate(kCFAllocatorDefault) else { return }
        daSession = s
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        DARegisterDiskAppearedCallback(s, nil, { disk, c in
            let app = Unmanaged<App>.fromOpaque(c!).takeUnretainedValue()
            if app.relevant(disk) { app.scheduleRefresh() }
        }, ctx)
        DARegisterDiskDisappearedCallback(s, nil, { disk, c in
            let app = Unmanaged<App>.fromOpaque(c!).takeUnretainedValue()
            if app.relevant(disk) { app.scheduleRefresh() }
        }, ctx)
        DARegisterDiskDescriptionChangedCallback(s, nil, nil, { disk, _, c in
            let app = Unmanaged<App>.fromOpaque(c!).takeUnretainedValue()
            if app.relevant(disk) { app.scheduleRefresh() }
        }, ctx)
        DASessionSetDispatchQueue(s, DispatchQueue.main)
    }

    /// Only NTFS/FUSE volumes, or disks we already track, are worth a rescan (internal volumes change constantly).
    func relevant(_ disk: DADisk) -> Bool {
        guard let d = DADiskCopyDescription(disk) as? [String: Any] else { return true }
        let kind = (d["DAVolumeKind"] as? String ?? "").lowercased()
        let content = (d["DAMediaContent"] as? String ?? "").uppercased()
        let bsd = d["DAMediaBSDName"] as? String ?? ""
        let external = !(d["DADeviceInternal"] as? Bool ?? true) || (d["DAMediaRemovable"] as? Bool ?? false)
            || (d["DAMediaEjectable"] as? Bool ?? false)
        return external || others.contains { $0.dev == bsd || $0.parentDisk == bsd } || ["ntfs", "macfuse", "fusefs", "osxfuse"].contains(kind)
            || content == "EBD0A0A2-B9E5-4433-87C0-68B6B72699C7" || content == "MICROSOFT BASIC DATA"
            || vols.contains { $0.dev == bsd || $0.parentDisk == bsd }
    }

    func scheduleRefresh() {
        pendingRefresh?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.refresh() }
        pendingRefresh = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: w)
    }

    func menuWillOpen(_ menu: NSMenu) { menuOpen = true; refresh(); updateLive() }
    func menuDidClose(_ menu: NSMenu) { menuOpen = false }

    // MARK: refresh

    func refresh() {
        if busy { return }
        DispatchQueue.global().async {
            let v = scanVolumes()
            let o = scanOthers()
            let ok = helperReady
            let cs = ok ? copyStatus() : (false, nil, nil)
            DispatchQueue.main.async { self.apply(v, others: o, helperOK: ok, copy: cs) }
        }
    }

    func apply(_ new: [Vol], others newOthers: [Other], helperOK ok: Bool, copy: (stale: Bool, from: String?, to: String?)) {
        let ids = Set(new.map { $0.dev })

        // disks that vanished while mounted read/write and weren't ejected by us
        for g in vols where g.rw && !ids.contains(g.dev) && !ejectedDevs.contains(g.dev) {
            notify(L("“{0}” was disconnected without ejecting", g.name), L("Some data may not have been written. Click to see what to do."),
                   category: "unsafe", info: ["name": g.name])
        }
        ejectedDevs.formIntersection(ids)

        vols = new
        others = newOthers
        helperOK = ok
        copyStale = copy.stale ? (copy.from, copy.to) : nil
        if copy.stale && !staleNotified {
            staleNotified = true
            notify(L("A new version of ntfs-3g is available"), L("Update the secure copy from the NTFS Mount menu."))
        }
        attempted.formIntersection(ids)
        retried.formIntersection(ids)
        userUnmounted.formIntersection(ids)
        lowSpaceNotified.formIntersection(ids)
        for v in new {
            if v.rw {
                if mountedAt[v.dev] == nil { mountedAt[v.dev] = Date() }
                if !busy { ejectedDevs.remove(v.dev) }   // mounted again, so a later unplug is unsafe again
            } else {
                mountedAt[v.dev] = nil
            }
        }
        for k in mountedAt.keys where !ids.contains(k) { mountedAt[k] = nil }
        var known = Pref.knownDisks
        for v in new { if let u = v.uuid { known[u] = v.name } }
        if known != Pref.knownDisks { Pref.knownDisks = known }
        cleanupLeftovers()

        // don't tear down the menu under the user's cursor unless something actually changed
        let sig = new.map { "\($0.dev)|\($0.name)|\($0.rw)|\($0.mountPoint ?? "-")|\(Pref.readOnlyUUIDs.contains($0.uuid ?? ""))" }
            .joined(separator: ";") + "|\(ok)|\(copy.stale)|"
            + newOthers.map { "\($0.dev)|\($0.name)|\($0.fs)" }.joined(separator: ";")
        if sig != lastLoggedSig {
            lastLoggedSig = sig
            logLine("volumes: " + (new.isEmpty ? "none" : new.map {
                "\($0.name) [\($0.dev) " + ($0.rw ? "read-write" : ($0.mountPoint != nil ? "read-only" : "unmounted")) + "]"
            }.joined(separator: ", ")))
        }
        if !menuOpen || sig != menuSignature { rebuild(); menuSignature = sig }
        updateLive()
        refreshCapacities(force: true)
        autoMountPending()
        if settingsWindow?.isVisible == true || welcomeWindow?.isVisible == true { setup.reload() }
        if firstApply {
            firstApply = false
            if !UserDefaults.standard.bool(forKey: "welcomeShown") && (!ntfs3gAvailable || !fuseInstalled || !ok) { showWelcome() }
        }
    }

    /// Settings changed (menu or Settings window): reflect them without waiting for the next refresh.
    func prefsChanged() {
        pendingPrefs?.cancel()
        let w = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if !self.menuOpen { self.rebuild() }
            self.updateLive()
            self.autoMountPending()
        }
        pendingPrefs = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: w)
    }

    /// statfs on a hung FUSE mount can block forever, so it never runs on the main thread.
    func refreshCapacities(force: Bool = false) {
        // free space barely moves: every 2 s while someone looks at the menu or data is flowing, otherwise every 60 s
        let wanted: TimeInterval = menuOpen || Date().timeIntervalSince(lastActive) < 10 ? 2 : 60
        guard !capBusy, force || capCache.isEmpty || Date().timeIntervalSince(capStamp) >= wanted else { return }
        capStamp = Date()
        capBusy = true
        let mps = vols.compactMap { $0.mountPoint } + others.map { $0.mountPoint }
        DispatchQueue.global().async {
            var out: [String: (total: Int64, free: Int64)] = [:]
            for mp in mps { if let c = capacity(mp) { out[mp] = c } }
            DispatchQueue.main.async {
                self.capCache = out
                self.capBusy = false
                self.updateLive()
                self.checkLowSpace()
            }
        }
    }

    /// Removes the empty /Volumes/<name> folders left behind after a disk was unplugged.
    func cleanupLeftovers() {
        let current = Set(vols.filter { $0.rw }.compactMap { $0.mountPoint })
        let stale = knownMountPoints.subtracting(current)
        knownMountPoints.formUnion(current)
        guard helperOK else { return }
        for mp in stale {
            knownMountPoints.remove(mp)
            jobQ.async {   // same queue as mounts, so it can't race a re-plug of the same name
                guard (try? FileManager.default.contentsOfDirectory(atPath: mp))?.isEmpty == true else { return }
                _ = privileged(["cleanup", mp])
            }
        }
    }

    /// Mounts, one at a time, any NTFS volume macOS left read-only or unmounted.
    /// Only runs when the helper is installed, so it never pops a password prompt.
    func autoMountPending() {
        guard Pref.get("autoMount"), helperOK, !busy, ntfs3gAvailable, fuseInstalled else { return }
        let ro = Pref.readOnlyUUIDs
        guard let v = vols.first(where: {
            !$0.rw && !attempted.contains($0.dev) && !userUnmounted.contains($0.dev) && !ro.contains($0.uuid ?? "")
        }) else { return }
        logLine("auto-mount \(v.name) (\(v.dev))")
        mountVolume(v, force: false, auto: true)
    }

    // MARK: macFUSE health

    /// Looks for the classic breakages (extension not approved after a macOS update, not loaded...) before
    /// they show up as a cryptic mount error. Loading it needs the helper, so without it we stay quiet:
    /// an unloaded extension is normal until the first mount.
    func checkFUSE() {
        guard fuseInstalled else { return }
        DispatchQueue.global().async {
            var issue: String?
            // FUSE-T has no kernel extension to break: it is ready once installed
            if backend == .macFUSE, !kextLoaded(), helperReady {
                let r = privileged(["loadfuse"])
                if !r.ok { issue = r.out.isEmpty ? L("Couldn’t load the {0} extension.", backend.name) : r.out }
            }
            DispatchQueue.main.async {
                guard self.fuseIssue != issue else { return }
                self.fuseIssue = issue
                if self.menuOpen { self.menuSignature = "" } else { self.rebuild() }   // not under the cursor
            }
        }
    }

    @objc func showFUSEIssue() {
        guard let issue = fuseIssue else { return }
        ask(L("{0} is not active", backend.name),
            L("{0}\n\nIf macOS was updated recently, it may have disapproved the extension: approve it in System Settings > Privacy & Security (it may ask you to restart). If macFUSE is out of date, reinstall it from macfuse.github.io.", issue),
            [L("Open Settings"), L("Close")]) { i in
            if i == 0, let u = URL(string: "x-apple.systempreferences:com.apple.preference.security") { NSWorkspace.shared.open(u) }
        }
    }

    // MARK: monitoring

    func sample() {
        let parents = Set(vols.filter { $0.mountPoint != nil }.map { $0.parentDisk } + others.map { $0.parentDisk })
        sampleQ.async {
            var out: [String: (r: Double, w: Double)] = [:]
            let now = Date()
            for p in parents {
                guard let c = diskCounters(p) else { continue }
                if self.baseCounters[p] == nil { self.baseCounters[p] = (c.read, c.write) }
                if let last = self.lastCounters[p] {
                    let dt = now.timeIntervalSince(last.t)
                    if dt > 0 {
                        out[p] = (Double(c.read &- last.r) / dt, Double(c.write &- last.w) / dt)
                    }
                }
                self.lastCounters[p] = (now, c.read, c.write)
            }
            for k in self.lastCounters.keys where !parents.contains(k) { self.lastCounters[k] = nil; self.baseCounters[k] = nil }
            DispatchQueue.main.async {
                self.speeds = out
                for (p, s) in out { self.history[p] = Array(((self.history[p] ?? []) + [s.r + s.w]).suffix(30)) }
                for k in self.history.keys where out[k] == nil { self.history[k] = nil }
                for (p, s) in out { self.wSmooth[p] = (self.wSmooth[p] ?? s.w) * 0.7 + s.w * 0.3 }
                let ntfsParents = Set(self.vols.map { $0.parentDisk })
                if out.contains(where: { ntfsParents.contains($0.key) && $0.value.r + $0.value.w > 100_000 }) { self.lastActive = now }
                for k in self.wSmooth.keys where out[k] == nil { self.wSmooth[k] = nil }
                self.updateLive()
                self.refreshCapacities()
            }
        }
    }

    /// Monochrome (template) like every menu bar icon; colour only when something needs attention.
    func updateIcon() {
        let ro = Pref.readOnlyUUIDs
        let name: String, label: String
        var color: NSColor?
        if busy { (name, label) = ("arrow.triangle.2.circlepath", L("working")) }
        else if fuseIssue != nil || !ntfs3gAvailable || !fuseInstalled || vols.contains(where: { !$0.rw && !ro.contains($0.uuid ?? "") }) {
            (name, label, color) = ("externaldrive.badge.exclamationmark", L("needs attention"), .systemOrange)
        }
        else if vols.contains(where: { $0.rw }) { (name, label) = ("externaldrive.fill", L("disks mounted with write access")) }
        else { (name, label) = ("externaldrive", L("no NTFS disks")) }
        let key = name + (color == nil ? "" : "!")
        guard key != iconKey else { return }
        iconKey = key
        item.button?.image = sym(name, color, size: 15)
        item.button?.setAccessibilityLabel("NTFS Mount, " + label)
    }

    func updateTitle() {
        updateIcon()
        guard let b = item.button else { return }
        b.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        if busy { b.title = " …"; return }
        // stays up for a few seconds after activity stops, so short pauses don't make it blink
        if Pref.get("showSpeed"), Date().timeIntervalSince(lastActive) < 6 {
            let ntfsParents = Set(vols.map { $0.parentDisk })
            let s = speeds.filter { ntfsParents.contains($0.key) }.values
            b.title = " ↓\(barRate(s.reduce(0) { $0 + $1.r })) ↑\(barRate(s.reduce(0) { $0 + $1.w })) MB/s"
        } else {
            b.title = ""
        }
    }

    /// Always MB/s and always the same width (figure spaces are as wide as digits), so the menu bar doesn't jiggle.
    func barRate(_ bps: Double) -> String {
        let mb = bps / 1_000_000
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.usesGroupingSeparator = false
        f.minimumFractionDigits = mb < 100 ? 1 : 0
        f.maximumFractionDigits = f.minimumFractionDigits
        var s = f.string(from: NSNumber(value: mb)) ?? "0"
        if mb >= 100 { s = "\u{2008}" + s }   // punctuation space stands in for the decimal separator
        while s.count < 5 { s = "\u{2007}" + s }
        return s
    }

    func card(for v: Vol) -> Card {
        let ro = Pref.readOnlyUUIDs.contains(v.uuid ?? "")
        var c = Card()
        c.name = v.name
        c.sizeText = fmtBytes(v.size) + (v.bus.map { " · \($0)" } ?? "")
        c.mounted = v.mountPoint != nil
        c.icon = driveSymbol(v.bus)
        if v.rw {
            (c.state, c.stateIcon, c.stateColor) = (L("Read-write"), "pencil", .systemGreen)
            c.actions = [.open, .eject]
        } else if v.mountPoint != nil {
            (c.state, c.stateIcon, c.stateColor) = (L("Read-only"), ro ? "lock.fill" : "eye", .systemOrange)
            c.actions = [.mount, .open, .eject]
        } else {
            (c.state, c.stateIcon, c.stateColor) = (L("Not mounted"), ro ? "lock.fill" : nil, .secondaryLabelColor)
            c.actions = [.mount, .eject]
        }
        c.busyText = busyDevs[v.dev]
        fillMetrics(&c, mount: v.mountPoint, parent: v.parentDisk)
        return c
    }

    /// Usage text, speeds, graph history and fill-up estimate; shared by NTFS and "other" volumes.
    func fillMetrics(_ c: inout Card, mount: String?, parent: String) {
        if let mp = mount, let cap = capCache[mp], cap.total > 0 {
            let used = cap.total - cap.free
            c.frac = Double(used) / Double(cap.total)
            c.usedText = L("{0} used", fmtBytes(used))
            c.freeText = L("{0} free of {1}", fmtBytes(cap.free), fmtBytes(cap.total))
            c.freePct = L("{0}% free", Int(((1 - c.frac!) * 100).rounded()))
        } else if mount != nil {
            c.usedText = capCache.isEmpty ? L("Calculating…") : L("Space unavailable")
        }
        if let s = speeds[parent] { c.r = s.r; c.w = s.w }
        // fill-up estimate from the smoothed write rate (instantaneous speed is too jumpy)
        if let mp = mount, let cap = capCache[mp], let sw = wSmooth[parent], sw > 1_000_000, c.w > 1_000_000 {
            let secs = Double(cap.free) / sw
            if secs < 86_400 { c.eta = L("full in ~{0}", fmtDuration(secs)) }
        }
        c.history = history[parent] ?? []
    }

    func card(for o: Other) -> Card {
        var c = Card()
        c.name = o.name
        c.sizeText = fmtBytes(o.size) + (o.bus.map { " · \($0)" } ?? "")
        c.mounted = true
        c.icon = driveSymbol(o.bus)
        (c.state, c.stateColor) = (o.fs, .systemBlue)
        c.actions = [.open, .eject]
        c.busyText = busyDevs[o.dev]
        fillMetrics(&c, mount: o.mountPoint, parent: o.parentDisk)
        return c
    }

    func updateLive() {
        updateTitle()
        for (dev, view) in live {
            if let v = vols.first(where: { $0.dev == dev }) { view.card = card(for: v) }
            else if let o = others.first(where: { $0.dev == dev }) { view.card = card(for: o) }
        }
    }

    func checkLowSpace() {
        for v in vols where v.rw && !lowSpaceNotified.contains(v.dev) {
            guard let mp = v.mountPoint, let c = capCache[mp], c.total > 0 else { continue }
            if Double(c.free) / Double(c.total) < 0.05 {
                lowSpaceNotified.insert(v.dev)
                notify(L("Low space on “{0}”", v.name), L("Only {0} left of {1}.", fmtBytes(c.free), fmtBytes(c.total)),
                       category: "lowspace", info: ["mp": mp])
            }
        }
    }

    // MARK: menu

    /// Problems first, then one card per disk (actions live on the card; rare ones in "Más opciones"),
    /// other volumes, and the app-level items last.
    func rebuild() {
        menu.removeAllItems()
        live.removeAll()
        var attention = false
        if !ntfs3gAvailable || !fuseInstalled {
            menu.addItem(action(L("Missing: {0} — finish setup…", fuseInstalled ? "ntfs-3g" : "\(backend.name) / ntfs-3g"),
                                "exclamationmark.triangle.fill", #selector(showWelcome), .systemOrange))
            attention = true
        }
        if fuseIssue != nil {
            menu.addItem(action(L("{0} is not active — see details…", backend.name), "exclamationmark.octagon.fill", #selector(showFUSEIssue), .systemRed))
            attention = true
        }
        if ntfs3gAvailable && fuseInstalled {
            if !helperOK {
                menu.addItem(action(L("Turn on passwordless mounting…"), "key.fill", #selector(installHelperAction), .systemYellow))
                attention = true
            } else if let c = copyStale {
                let versions = [c.from, c.to].compactMap { $0 }.joined(separator: " → ")
                menu.addItem(action(versions.isEmpty ? L("Update ntfs-3g copy…") : L("Update ntfs-3g copy ({0})…", versions),
                                    "arrow.triangle.2.circlepath", #selector(installHelperAction), .systemBlue))
                attention = true
            }
        }
        if attention { menu.addItem(.separator()) }

        if vols.isEmpty {
            let i = NSMenuItem()
            i.view = EmptyCardView()
            menu.addItem(i)
            menu.addItem(.separator())
        }
        for v in vols {
            addVolume(v)
            menu.addItem(.separator())
        }
        if !others.isEmpty && Pref.get("showOthers") {
            let o = NSMenuItem(title: L("Other volumes ({0})", others.count), action: nil, keyEquivalent: "")
            o.image = sym("externaldrive")
            o.submenu = othersMenu()
            menu.addItem(o)
            menu.addItem(.separator())
        }
        let mountable = vols.filter { !$0.rw && !Pref.readOnlyUUIDs.contains($0.uuid ?? "") }
        if mountable.count >= 2 && ntfs3gAvailable && fuseInstalled {
            menu.addItem(action(L("Mount all with write access"), "square.and.pencil", #selector(mountAll)))
        }
        if vols.filter({ $0.rw }).count >= 2 {
            menu.addItem(action(L("Unmount all without ejecting"), "arrow.down.circle", #selector(unmountAll)))
        }
        if ejectableParents().count >= 2 {
            let all = action(L("Eject all disks"), "eject", #selector(ejectAll))
            all.keyEquivalent = "e"
            menu.addItem(all)
        }
        let settings = action(L("Settings…"), "gearshape", #selector(showSettings))
        settings.keyEquivalent = ","
        menu.addItem(settings)
        let quit = action(L("Quit"), "power", #selector(NSApplication.terminate(_:)))
        quit.target = nil
        quit.keyEquivalent = "q"
        menu.addItem(quit)
    }

    /// Read-only info cards for non-NTFS volumes (exFAT, FAT, APFS...), which macOS already mounts by itself.
    func othersMenu() -> NSMenu {
        let m = NSMenu()
        for (i, o) in others.enumerated() {
            if i > 0 { m.addItem(.separator()) }
            m.addItem(cardItem(card(for: o), dev: o.dev))
        }
        return m
    }

    func cardItem(_ c: Card, dev: String) -> NSMenuItem {
        let it = NSMenuItem()
        let view = VolumeCardView(c)
        view.onAction = { [weak self] a in self?.cardAction(a, dev: dev) }
        it.view = view
        live[dev] = view
        return it
    }

    func disabled(_ title: String, _ icon: String? = nil, _ color: NSColor? = nil) -> NSMenuItem {
        let m = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        m.isEnabled = false
        if let i = icon { m.image = sym(i, color) }
        return m
    }

    func action(_ title: String, _ icon: String, _ sel: Selector, _ color: NSColor? = nil, rep: String? = nil) -> NSMenuItem {
        let m = NSMenuItem(title: title, action: sel, keyEquivalent: "")
        m.target = self
        m.representedObject = rep
        m.image = sym(icon, color)
        return m
    }

    func addVolume(_ v: Vol) {
        menu.addItem(cardItem(card(for: v), dev: v.dev))
        let more = NSMenuItem(title: L("More options for “{0}”", v.name), action: nil, keyEquivalent: "")
        more.image = sym("ellipsis.circle")
        more.submenu = moreMenu(v)
        menu.addItem(more)
    }

    /// The less frequent actions for one disk, plus its technical details.
    func moreMenu(_ v: Vol) -> NSMenu {
        let m = NSMenu()
        let ro = Pref.readOnlyUUIDs.contains(v.uuid ?? "")
        if v.rw {
            m.addItem(action(L("Unmount without ejecting"), "arrow.down.circle", #selector(unmount(_:)), rep: v.dev))
        } else {
            m.addItem(action(ro ? L("Mount with write access (this time)") : L("Mount with write access"), "square.and.pencil", #selector(mount(_:)), rep: v.dev))
        }
        if v.uuid != nil {
            let i = action(L("Always read-only"), "lock", #selector(toggleReadOnly(_:)), rep: v.dev)
            i.state = ro ? .on : .off
            m.addItem(i)
        }
        m.addItem(action(L("Repair with ntfsfix…"), "bandage", #selector(repairAction(_:)), rep: v.dev))
        m.addItem(.separator())
        m.addItem(disabled(L("Device: /dev/{0}", v.dev), "internaldrive"))
        if let b = v.bus { m.addItem(disabled(L("Connection: {0}", b), "cable.connector")) }
        if let mp = v.mountPoint { m.addItem(disabled(L("Mount point: {0}", mp), "folder")) }
        if let u = v.uuid { m.addItem(disabled("UUID: \(u)", "number")) }
        if let t = mountedAt[v.dev] { m.addItem(disabled(L("Mounted with write access {0} ago", fmtDuration(Date().timeIntervalSince(t))), "clock")) }
        let counters = sampleQ.sync { (lastCounters[v.parentDisk], baseCounters[v.parentDisk]) }
        if let c = counters.0, let b = counters.1 {
            m.addItem(disabled(L("Since you opened the app: read {0} · written {1}", fmtBytes(Int64(c.r &- b.r)), fmtBytes(Int64(c.w &- b.w))), "arrow.up.arrow.down"))
        }
        return m
    }

    /// Whole disks that "Expulsar todos" would eject: mounted NTFS ones and other mounted volumes.
    func ejectableParents() -> Set<String> {
        Set(vols.filter { $0.mountPoint != nil }.map { $0.parentDisk } + others.map { $0.parentDisk })
    }

    /// Buttons on a card. The menu closes first so alerts and Finder windows don't fight with it.
    func cardAction(_ a: CardAction, dev: String) {
        menu.cancelTracking()
        DispatchQueue.main.async { [self] in
            if let v = vols.first(where: { $0.dev == dev }) {
                switch a {
                case .open: if let mp = v.mountPoint { openPath(mp) }
                case .eject: ejectParent(v.parentDisk)
                case .mount: requestMount(v)
                }
            } else if let o = others.first(where: { $0.dev == dev }) {
                switch a {
                case .open: openPath(o.mountPoint)
                case .eject: ejectOther(o)
                case .mount: break
                }
            }
        }
    }

    func openPath(_ p: String) { NSWorkspace.shared.open(URL(fileURLWithPath: p)) }

    func vol(_ s: NSMenuItem) -> Vol? { vols.first { $0.dev == s.representedObject as? String } }

    // MARK: actions

    func setLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch { alert(L("Couldn’t change the login item"), "\(error.localizedDescription)") }
    }

    @objc func toggleReadOnly(_ s: NSMenuItem) {
        guard let v = vol(s), let u = v.uuid else { return }
        setReadOnly(uuid: u, !Pref.readOnlyUUIDs.contains(u))
    }

    /// Pins a disk to read-only (remounting it with Apple's driver if it's connected), or releases it.
    func setReadOnly(uuid u: String, _ on: Bool) {
        var set = Pref.readOnlyUUIDs
        guard set.contains(u) != on else { return }
        let v = vols.first { $0.uuid == u }
        if on { set.insert(u) } else { set.remove(u) }
        Pref.readOnlyUUIDs = set
        if !on {
            if let v { attempted.remove(v.dev); userUnmounted.remove(v.dev) }
            rebuild()
            autoMountPending()
        } else if let v {
            if v.mountPoint == nil {
                work(L("Mounting…"), devs: [v.dev]) { run("/usr/sbin/diskutil", ["mount", v.dev]) }
            } else if v.rw {
                remountReadOnly(v)
            }
            rebuild()
        }
    }

    func remountReadOnly(_ v: Vol) {
        guard let mp = v.mountPoint else { return }
        work(L("Switching…"), devs: [v.dev]) {
            let r = privileged(["unmount", mp])
            if r.ok { run("/usr/sbin/diskutil", ["mount", v.dev]) }
            else { self.diskInUse(L("Couldn’t switch “{0}” to read-only", v.name), mountPoints: [mp], error: r.out) { self.remountReadOnly(v) } }
        }
    }

    func forgetDisk(_ uuid: String) {
        var k = Pref.knownDisks
        k[uuid] = nil
        Pref.knownDisks = k
        Pref.readOnlyUUIDs = Pref.readOnlyUUIDs.subtracting([uuid])
    }

    func knownDisks() -> [KnownDisk] {
        let known = Pref.knownDisks, ro = Pref.readOnlyUUIDs
        let connected = Set(vols.compactMap { $0.uuid })
        return Set(known.keys).union(ro)
            .map { KnownDisk(uuid: $0, name: known[$0] ?? L("Unnamed disk"), connected: connected.contains($0), readOnly: ro.contains($0)) }
            .sorted { ($0.connected ? 0 : 1, $0.name.lowercased()) < ($1.connected ? 0 : 1, $1.name.lowercased()) }
    }

    @objc func mount(_ s: NSMenuItem) {
        guard let v = vol(s) else { return }
        requestMount(v)
    }

    func requestMount(_ v: Vol) {
        guard ntfs3gAvailable, fuseInstalled else { showWelcome(); return }
        mountVolume(v, force: false, auto: false)
    }

    func mountVolume(_ v: Vol, force: Bool, auto: Bool) {
        attempted.insert(v.dev)
        work(L("Mounting…"), devs: [v.dev]) { self.doMount(v, force: force, auto: auto) }
    }

    /// Runs on the work thread.
    func doMount(_ v: Vol, force: Bool, auto: Bool) {
        var flags: [String] = []
        if force { flags.append("force") }
        if Pref.get("winNames") { flags.append("winnames") }
        var r = privileged(["mount", v.dev, v.name] + flags)
        if !r.ok, auto, !retried.contains(v.dev) {
            // macFUSE may still be loading right after login or wake: one quiet retry before bothering anyone
            DispatchQueue.main.async { self.retried.insert(v.dev) }
            Thread.sleep(forTimeInterval: 8)
            r = privileged(["mount", v.dev, v.name] + flags)
        }
        var mounted: String?
        if r.ok { for _ in 0..<30 { mounted = fuseMounts()[v.dev]; if mounted != nil { break }; Thread.sleep(forTimeInterval: 0.1) } }
        if let mp = mounted {
            if Pref.get("noIndex"), helperReady { _ = privileged(["noindex", mp]) }
            if auto {
                let free = capacity(mp).map { L(" · {0} free", fmtBytes($0.free)) } ?? ""
                notify(L("“{0}” mounted with write access", v.name), fmtBytes(v.size) + free,
                       category: "mounted", info: ["mp": mp, "parent": v.parentDisk])
            } else {
                DispatchQueue.main.async { NSWorkspace.shared.open(URL(fileURLWithPath: mp)) }
            }
            return
        }
        run("/usr/sbin/diskutil", ["mount", v.dev])   // fall back to Apple's read-only mount
        mountFailed(v, r.out.isEmpty && r.ok ? L("The volume didn’t show up mounted after running ntfs-3g.") : r.out)
    }

    func mountFailed(_ v: Vol, _ out: String) {
        let low = out.lowercased()
        if low.contains("user canceled") || low.contains("(-128)") { return }
        let detail = out.isEmpty ? L("Unknown error.") : out
        if low.contains("error opening") && low.contains("operation not permitted") {
            ask(L("macOS blocked access to the disk"),
                L("Give NTFS Mount “Full Disk Access” in System Settings > Privacy & Security, quit the app and open it again.\n\n{0}", detail),
                [L("Open Settings"), L("Cancel")]) { i in
                if i == 0, let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                    NSWorkspace.shared.open(u)
                }
            }
        } else if low.contains("hibernat") || low.contains("unsafe state") || low.contains("fast restart") {
            ask(L("“{0}” is hibernated or using Windows Fast Startup", v.name),
                L("The best option is to start Windows and shut it down completely.\n\nIf you mount it anyway, the hibernation file is deleted: you lose what Windows had open in that session (not your files). The disk stays read-only if you cancel."),
                [L("Mount anyway"), L("Keep read-only")]) { i in
                if i == 0 { self.mountVolume(v, force: true, auto: false) }
            }
        } else if low.contains("unclean") || low.contains("metadata kept") || low.contains("inconsistent") || low.contains("corrupt") {
            ask(L("“{0}” needs repair", v.name),
                L("The file system wasn’t closed properly. ntfsfix can clean up the state and retry the mount (it doesn’t replace Windows’ chkdsk).\n\n{0}", detail),
                [L("Repair with ntfsfix and retry"), L("Keep read-only")]) { i in
                if i == 0 { self.fixAndMount(v) }
            }
        } else if low.contains("macfuse") || low.contains("fuse-t") || low.contains("fuse:") || low.contains("kext") || low.contains("kernel extension")
                    || low.contains("/dev/macfuse") || low.contains("filesystem is not available") {
            checkFUSE()
            alert(L("{0} didn’t respond", backend.name),
                  L("{0}\n\nThe extension may not be approved or loaded. See Settings > Advanced for details.", detail))
        } else {
            alert(L("Couldn’t mount with write access"), detail)
        }
    }

    func fixAndMount(_ v: Vol) {
        work(L("Repairing…"), devs: [v.dev]) { self.doFix(v) }
    }

    /// Runs on the work thread; the volume must not be mounted by ntfs-3g.
    func doFix(_ v: Vol) {
        let r = privileged(["fix", v.dev])
        if r.ok { doMount(v, force: false, auto: false) }
        else {
            run("/usr/sbin/diskutil", ["mount", v.dev])
            alert(L("ntfsfix failed"), r.out)
        }
    }

    @objc func repairAction(_ s: NSMenuItem) {
        guard let v = vol(s) else { return }
        ask(L("Repair “{0}” with ntfsfix?", v.name),
            L("Fixes basic errors and flags the disk so Windows checks it (chkdsk) the next time you connect it. It doesn’t replace chkdsk.\n\nThe disk is unmounted during the repair and then mounted again with write access."),
            [L("Repair"), L("Cancel")]) { i in
            guard i == 0 else { return }
            guard v.rw, let mp = v.mountPoint else { self.fixAndMount(v); return }
            self.work(L("Repairing…"), devs: [v.dev]) {
                let r = privileged(["unmount", mp])
                if r.ok { self.doFix(v) }
                else { self.diskInUse(L("Couldn’t repair “{0}”", v.name), mountPoints: [mp], error: r.out) { self.fixAndMount(v) } }
            }
        }
    }

    @objc func unmount(_ s: NSMenuItem) {
        guard let v = vol(s) else { return }
        unmountVolume(v)
    }

    func unmountVolume(_ v: Vol) {
        guard let mp = v.mountPoint else { return }
        userUnmounted.insert(v.dev)
        logLine("unmount \(v.name) (\(v.dev))")
        work(L("Unmounting…"), devs: [v.dev]) {
            let r = privileged(["unmount", mp])
            if !r.ok {
                DispatchQueue.main.async { self.userUnmounted.remove(v.dev) }
                self.diskInUse(L("Couldn’t unmount “{0}”", v.name), mountPoints: [mp], error: r.out) { self.unmountVolume(v) }
            }
        }
    }

    /// Mounts every NTFS volume that isn't mounted read/write, one after another (the job queue is serial).
    @objc func mountAll() {
        let ro = Pref.readOnlyUUIDs
        for v in vols where !v.rw && !ro.contains(v.uuid ?? "") {
            userUnmounted.remove(v.dev)
            mountVolume(v, force: false, auto: false)
        }
    }

    @objc func unmountAll() {
        let rw = vols.filter { $0.rw }
        guard !rw.isEmpty else { return }
        for v in rw { userUnmounted.insert(v.dev) }
        logLine("unmount all (\(rw.map { $0.name }.joined(separator: ", ")))")
        work(L("Unmounting…"), devs: rw.map { $0.dev }) {
            let r = privileged(["unmountall"])
            if !r.ok {
                DispatchQueue.main.async { for v in rw { self.userUnmounted.remove(v.dev) } }
                self.diskInUse(L("Couldn’t unmount the disks"), mountPoints: rw.compactMap { $0.mountPoint }, error: r.out) { self.unmountAll() }
            }
        }
    }

    @objc func ejectAll() {
        let parents = Set(vols.filter { $0.mountPoint != nil }.map { $0.parentDisk })
        if !parents.isEmpty { ejectParent(parents) }
        var done = parents
        for o in others where done.insert(o.parentDisk).inserted { ejectOther(o) }
    }

    func ejectParent(_ parent: String) { ejectParent([parent]) }

    func ejectParent(_ parents: Set<String>) {
        for v in vols where parents.contains(v.parentDisk) { userUnmounted.insert(v.dev); ejectedDevs.insert(v.dev) }
        let names = Set(vols.filter { parents.contains($0.parentDisk) }.map { $0.name }).sorted()
        let devs = vols.filter { parents.contains($0.parentDisk) }.map { $0.dev } + others.filter { parents.contains($0.parentDisk) }.map { $0.dev }
        logLine("eject \(names.joined(separator: ", ")) (\(parents.sorted().joined(separator: ", ")))")
        work(L("Ejecting…"), devs: devs) {
            var allOK = true
            for p in parents.sorted() {
                let r = privileged(["eject", p])
                if !r.ok {
                    allOK = false
                    let (mps, label) = DispatchQueue.main.sync { () -> ([String], String) in
                        for v in self.vols where v.parentDisk == p { self.userUnmounted.remove(v.dev); self.ejectedDevs.remove(v.dev) }
                        let onDisk = self.vols.filter { $0.parentDisk == p }
                        return (onDisk.compactMap { $0.mountPoint } + self.others.filter { $0.parentDisk == p }.map { $0.mountPoint },
                                onDisk.first.map { L("“{0}”", $0.name) } ?? p)
                    }
                    self.diskInUse(L("Couldn’t eject {0}", label), mountPoints: mps, error: r.out) { self.ejectParent(p) }
                }
            }
            if allOK, !names.isEmpty {
                notify(L("You can now disconnect {0}", names.map { L("“{0}”", $0) }.joined(separator: ", ")),
                       L("The data is written and the disk is ejected."))
            }
        }
    }

    /// exFAT/FAT/APFS... volumes belong to macOS, so a plain diskutil eject is enough.
    func ejectOther(_ o: Other) {
        work(L("Ejecting…"), devs: others.filter { $0.parentDisk == o.parentDisk }.map { $0.dev }) {
            let r = run("/usr/sbin/diskutil", ["eject", "/dev/" + o.parentDisk])
            logLine("eject \(o.name) (\(o.parentDisk)) → " + (r.status == 0 ? "ok" : "FAILED: \(r.out)"))
            if r.status == 0 {
                notify(L("You can now disconnect {0}", L("“{0}”", o.name)), L("The disk is ejected."))
            } else {
                self.diskInUse(L("Couldn’t eject “{0}”", o.name), mountPoints: [o.mountPoint],
                               error: r.out.trimmingCharacters(in: .whitespacesAndNewlines)) { self.ejectOther(o) }
            }
        }
    }

    /// After a failed unmount/eject: names the apps holding files on the disk and offers to close them.
    /// Runs on the work thread (lsof can take a moment); `retry` runs on the main thread.
    func diskInUse(_ failure: String, mountPoints: [String], error: String, retry: @escaping () -> Void) {
        let who = blockers(mountPoints)
        let finder = "com.apple.finder"
        var apps: [NSRunningApplication] = []
        for b in who { if let a = b.app, a.bundleIdentifier != finder, !apps.contains(a) { apps.append(a) } }
        logLine("\(failure); in use by: " + (who.isEmpty ? "(nobody visible)" : who.map { $0.name }.joined(separator: ", ")))
        if who.isEmpty {
            ask(failure, (error.isEmpty ? "" : error + "\n\n") + L("Close the open files on the disk and try again."),
                [L("Retry"), L("Cancel")]) { i in if i == 0 { retry() } }
            return
        }
        let list = who.map { "• \($0.name)" }.joined(separator: "\n")
        var buttons = [L("Retry"), L("Cancel")]
        if !apps.isEmpty {
            buttons.insert(apps.count == 1 ? L("Close {0} and retry", apps[0].localizedName ?? L("the app")) : L("Close {0} apps and retry", apps.count), at: 0)
        }
        ask(L("The disk is in use"),
            L("{0} because these programs have files open on it:\n\n{1}\n\nSave your work and close them, or let NTFS Mount close them (they will ask if anything is unsaved).", failure, list),
            buttons) { i in
            let closeIdx = apps.isEmpty ? -1 : 0
            if i == closeIdx {
                apps.forEach { $0.terminate() }
                DispatchQueue.global().async {
                    let deadline = Date().addingTimeInterval(15)
                    while Date() < deadline && apps.contains(where: { !$0.isTerminated }) { Thread.sleep(forTimeInterval: 0.25) }
                    DispatchQueue.main.async(execute: retry)
                }
            } else if i == closeIdx + 1 {
                retry()
            }
        }
    }

    /// Unmounting before sleep/shutdown avoids leaving a dirty NTFS volume behind.
    func beforeSleep() {
        guard Pref.get("unmountOnSleep"), helperOK, vols.contains(where: { $0.rw }) else { return }
        logLine("unmounting everything before sleep/shutdown")
        let r = privileged(["unmountall"])
        // unplugging during sleep is harmless only for what really got unmounted
        let still = fuseMounts()
        for v in vols where v.rw && still[v.dev] == nil { ejectedDevs.insert(v.dev) }
        if !r.ok { logLine("disks were still mounted before sleep: \(r.out)") }
    }

    @objc func installHelperAction() {
        work(L("Installing…")) {
            let r = installHelper()
            logLine("privileged components install → " + (r.ok ? "ok" : "FAILED: \(String(r.out.prefix(400)))"))
            if r.ok {
                self.checkFUSE()
                self.alert(L("Done"), L("Passwordless mounting is on and the secure ntfs-3g copy is up to date. Disks that are already mounted keep working; the new version will be used on the next mount."))
            }
            else if !r.out.contains("(-128)") { self.alert(L("Couldn’t turn on passwordless mounting"), r.out) }
        }
    }

    /// Privileged actions run one at a time; the menu shows "busy" until the queue drains.
    @objc func uninstallAction() {
        ask(L("Uninstall privileged components"),
            L("This removes the sudoers rule, the helper and the private copy of ntfs-3g (in /usr/local/libexec) and turns off “Open NTFS Mount at login”. Disks that are already mounted keep working until you eject them. The app will keep working, asking for your password on each action.\n\nTo also delete the app and its preferences, see the README."),
            [L("Uninstall"), L("Cancel")]) { i in
            guard i == 0 else { return }
            self.work(L("Uninstalling…")) {
                guard let script = bundledUninstaller else {
                    self.alert(L("Couldn’t uninstall"), L("uninstall-root.sh is missing from the app."))
                    return
                }
                let r = runAsAdmin("/bin/sh \(shq(script)) 2>&1")
                invalidateHelperCache()
                logLine("uninstall → " + (r.ok ? "ok" : "FAILED: \(String(r.out.prefix(400)))"))
                if r.ok {
                    DispatchQueue.main.async { try? SMAppService.mainApp.unregister() }
                    self.alert(L("Components uninstalled"), L("The sudoers rule, the helper and the private copy of ntfs-3g are gone. You can turn them back on from the menu whenever you like."))
                } else if !r.out.contains("(-128)") {
                    self.alert(L("Couldn’t uninstall"), r.out)
                }
            }
        }
    }

    @objc func openLog() {
        logLine("(log opened by the user)")
        NSWorkspace.shared.open(logURL)
    }

    /// Everything someone would ask for when something misbehaves.
    /// Call on the main thread (it reads UI-side state); the slow part can then run anywhere.
    func diagnostics(withLog: Bool) -> String {
        var lines: [String] = []
        let stamp = (try? String(contentsOfFile: secureSourceStamp, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
        let copy = copyStatus()
        lines.append("NTFS Mount \(appVersion) · \(ProcessInfo.processInfo.operatingSystemVersionString)")
        lines.append("FUSE layer: \(backend.name) \(fuseVersion ?? "not installed") · " + (fuseReady() ? "ready" : "NOT ready")
                 + (fuseIssue.map { " · PROBLEM: \($0)" } ?? ""))
        lines.append("ntfs-3g (Homebrew): \(ntfs3gPath.flatMap { cellarVersion(URL(fileURLWithPath: $0).resolvingSymlinksInPath().path) } ?? "not installed")"
                 + " · private copy: " + (stamp.flatMap { cellarVersion($0) } ?? "not installed") + (copy.stale ? " (OUTDATED)" : ""))
        lines.append("Passwordless mounting: " + (helperReady ? "active" : (helperInstalled ? "installed but not valid" : "not installed")))
        lines.append("Options: auto=\(Pref.get("autoMount")) sleep=\(Pref.get("unmountOnSleep")) spotlight=\(Pref.get("noIndex")) bar=\(Pref.get("showSpeed")) others=\(Pref.get("showOthers")) winnames=\(Pref.get("winNames"))"
                 + " · login item: \(SMAppService.mainApp.status == .enabled ? "yes" : "no") · read-only pinned disks: \(Pref.readOnlyUUIDs.count)")
        lines.append("")
        if vols.isEmpty { lines.append("No NTFS disks connected.") }
        for v in vols {
            let state = v.rw ? "read-write" : (v.mountPoint != nil ? "read-only" : "unmounted")
            lines.append("• \(v.name) [\(v.dev)] \(fmtBytes(v.size)) \(v.bus ?? "") — \(state)" + (v.mountPoint.map { " — \($0)" } ?? ""))
        }
        let mounts = run("/sbin/mount", []).out.split(separator: "\n").filter { $0.contains("macfuse") || $0.contains("fuse-t:") || $0.contains(" ntfs") }
        if !mounts.isEmpty { lines.append(""); lines.append("mount:"); lines.append(contentsOf: mounts.map { "  \($0)" }) }
        if withLog { lines.append(""); lines.append("Log (last lines):"); lines.append(logTail(60)) }
        return lines.joined(separator: "\n")
    }

    func copyDiagnostics() {
        let full = diagnostics(withLog: true)   // main thread: reads vols/fuseIssue
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(full, forType: .string)
    }

    /// Only on demand: the app never talks to the network by itself.
    @objc func checkMacFUSEUpdate() {
        guard let installed = fuseVersion else { showWelcome(); return }
        let repo = backend == .macFUSE ? "macfuse/macfuse" : "macos-fuse-t/fuse-t"
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
        req.setValue("NTFSMount", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15
        URLSession.shared.dataTask(with: req) { data, _, err in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else {
                self.alert(L("Couldn’t check"), err?.localizedDescription ?? L("Unexpected response from GitHub."))
                return
            }
            let latest = tag.replacingOccurrences(of: "macfuse-", with: "").replacingOccurrences(of: "v", with: "")
            let page = json["html_url"] as? String ?? "https://github.com/\(repo)/releases"
            logLine("\(backend.name) installed \(installed), latest \(latest)")
            if isNewer(latest, than: installed) {
                self.ask(L("A new version of {0} is available", backend.name),
                         L("Installed: {0} · Available: {1}\n\nAfter updating you will have to approve the extension again and restart.", installed, latest),
                         [L("Open download"), L("Not now")]) { i in
                    if i == 0, let u = URL(string: page) { NSWorkspace.shared.open(u) }
                }
            } else {
                self.alert(L("{0} is up to date", backend.name), L("Installed version: {0}", installed))
            }
        }.resume()
    }

    /// Privileged actions run one at a time; `devs` show `title` and a spinner on their cards meanwhile.
    func work(_ title: String, devs: [String] = [], _ block: @escaping () -> Void) {
        jobs += 1
        busy = true
        for d in devs { busyDevs[d] = title }
        updateLive()
        jobQ.async {
            block()
            DispatchQueue.main.async {
                for d in devs { self.busyDevs[d] = nil }
                self.jobs -= 1
                if self.jobs == 0 { self.busy = false; self.refresh() }
                self.updateLive()
                if self.settingsWindow?.isVisible == true || self.welcomeWindow?.isVisible == true { self.setup.reload() }
            }
        }
    }

    func alert(_ title: String, _ text: String) { ask(title, text, ["OK"]) { _ in } }

    func ask(_ title: String, _ text: String, _ buttons: [String], _ handler: @escaping (Int) -> Void) {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            let a = NSAlert()
            a.messageText = title
            a.informativeText = text
            buttons.forEach { a.addButton(withTitle: $0) }
            handler(a.runModal().rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue)
        }
    }

    // MARK: windows

    func window<V: View>(_ title: String, _ view: V) -> NSWindow {
        let w = NSWindow(contentViewController: NSHostingController(rootView: view))
        w.title = title
        w.styleMask = [.titled, .closable]
        w.isReleasedWhenClosed = false
        w.center()
        return w
    }

    func present(_ w: NSWindow?) {
        NSApp.activate(ignoringOtherApps: true)
        w?.makeKeyAndOrderFront(nil)
    }

    @objc func showSettings() {
        if settingsWindow == nil { settingsWindow = window(L("NTFS Mount Settings"), SettingsView(model: setup)) }
        setup.reload()
        present(settingsWindow)
    }

    @objc func showWelcome() {
        if welcomeWindow == nil {
            welcomeWindow = window(L("Welcome"), WelcomeView(model: setup) { [weak self] in
                UserDefaults.standard.set(true, forKey: "welcomeShown")
                self?.welcomeWindow?.close()
            })
        }
        setup.reload()
        present(welcomeWindow)
    }

    /// An accessory app has no menu bar of its own, but its windows still want ⌘W, ⌘Q and copy/paste.
    func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: L("Settings…"), action: #selector(showSettings), keyEquivalent: ",").target = self
        appMenu.addItem(withTitle: L("Close window"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appMenu.addItem(withTitle: L("Quit NTFS Mount"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)
        let editItem = NSMenuItem()
        let edit = NSMenu(title: L("Edit"))
        edit.addItem(withTitle: L("Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: L("Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: L("Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    // MARK: notifications

    func registerNotificationActions() {
        let open = UNNotificationAction(identifier: "open", title: L("Open"), options: [.foreground])
        let eject = UNNotificationAction(identifier: "eject", title: L("Eject"), options: [])
        let help = UNNotificationAction(identifier: "help", title: L("What to do"), options: [.foreground])
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: "mounted", actions: [open, eject], intentIdentifiers: []),
            UNNotificationCategory(identifier: "lowspace", actions: [open], intentIdentifiers: []),
            UNNotificationCategory(identifier: "unsafe", actions: [help], intentIdentifiers: []),
        ])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler done: @escaping () -> Void) {
        let content = response.notification.request.content
        let info = content.userInfo as? [String: String] ?? [:]
        let action = response.actionIdentifier
        DispatchQueue.main.async {
            if action == "eject", let p = info["parent"] {
                self.ejectParent(p)
            } else if action == "help" || (action == UNNotificationDefaultActionIdentifier && content.categoryIdentifier == "unsafe") {
                self.showUnsafeHelp(info["name"] ?? L("The disk"))
            } else if action == "open" || action == UNNotificationDefaultActionIdentifier, let mp = info["mp"] {
                self.openPath(mp)
            }
            done()
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner, .sound])
    }

    func showUnsafeHelp(_ name: String) {
        alert(L("“{0}” was disconnected without ejecting", name),
              L("Whatever was being copied at that moment may be incomplete.\n\n")
              + L("1. Plug it back in. If it mounts with write access, check the last files you copied.\n")
              + L("2. If it doesn’t mount or shows errors, use “Repair with ntfsfix…” under “More options” for the disk.\n")
              + L("3. For a full check, connect it to a Windows PC and run chkdsk /f.\n\n")
              + L("To avoid this, always click Eject (⏏) before unplugging."))
    }

    // MARK: URL scheme

    /// ntfsmount://expulsar (or eject-all) and ntfsmount://ajustes, e.g. from a Shortcut.
    func application(_ application: NSApplication, open urls: [URL]) {
        for u in urls where u.scheme == "ntfsmount" {
            logLine("link: \(u.absoluteString)")
            switch (u.host ?? "").lowercased() {
            case "expulsar", "eject-all":
                // any web page can open this link, so never act without asking
                ask(L("Eject all disks?"), L("A ntfsmount://eject-all link asked to eject all disks."),
                    [L("Eject"), L("Cancel")]) { i in if i == 0 { self.ejectAll() } }
            case "ajustes", "settings": showSettings()
            default: break
            }
        }
    }

}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = App()
app.delegate = delegate
app.run()
