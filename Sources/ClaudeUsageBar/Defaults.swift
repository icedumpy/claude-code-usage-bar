import Foundation

/// Thin typed wrapper over `UserDefaults` so the store's preferences read and
/// write through one consistent path, instead of a mix of `bool(forKey:)`,
/// `object(forKey:) as? T`, and raw `string(forKey:)`.
enum Defaults {
    /// Stored value for `key`, or `fallback` if it's absent or the wrong type.
    static func value<T>(_ key: String, _ fallback: T) -> T {
        UserDefaults.standard.object(forKey: key) as? T ?? fallback
    }

    static func set<T>(_ key: String, _ value: T) {
        UserDefaults.standard.set(value, forKey: key)
    }

    /// Variant for a String-backed `RawRepresentable` (our pref enums).
    static func raw<T: RawRepresentable>(_ key: String, _ fallback: T) -> T
        where T.RawValue == String {
        UserDefaults.standard.string(forKey: key).flatMap(T.init(rawValue:)) ?? fallback
    }

    static func setRaw<T: RawRepresentable>(_ key: String, _ value: T)
        where T.RawValue == String {
        UserDefaults.standard.set(value.rawValue, forKey: key)
    }
}
