import Foundation

/// Looks `key` up in the app's Localizable.strings and fills the `{0}`, `{1}`… placeholders.
/// The keys are the English texts, so a language the app has no translation for (or a missing
/// entry) simply shows English. Spanish lives in Resources/es.lproj/Localizable.strings.
func L(_ key: String, _ args: Any...) -> String {
    var s = NSLocalizedString(key, comment: "")
    for (i, a) in args.enumerated() { s = s.replacingOccurrences(of: "{\(i)}", with: "\(a)") }
    return s
}
