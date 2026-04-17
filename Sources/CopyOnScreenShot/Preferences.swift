import Foundation

enum DefaultsKey {
    static let autoCopyEnabled = "autoCopyEnabled"
    static let deleteAfterCopyEnabled = "deleteAfterCopyEnabled"
    static let launchAtLoginEnabled = "launchAtLoginEnabled"
}

@MainActor
final class Preferences {
    static let shared = Preferences()

    private let defaults: UserDefaults

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            DefaultsKey.autoCopyEnabled: true,
            DefaultsKey.deleteAfterCopyEnabled: false,
            DefaultsKey.launchAtLoginEnabled: false
        ])
    }

    var autoCopyEnabled: Bool {
        get { defaults.bool(forKey: DefaultsKey.autoCopyEnabled) }
        set { defaults.set(newValue, forKey: DefaultsKey.autoCopyEnabled) }
    }

    var deleteAfterCopyEnabled: Bool {
        get { defaults.bool(forKey: DefaultsKey.deleteAfterCopyEnabled) }
        set { defaults.set(newValue, forKey: DefaultsKey.deleteAfterCopyEnabled) }
    }

    var launchAtLoginEnabled: Bool {
        get { defaults.bool(forKey: DefaultsKey.launchAtLoginEnabled) }
        set { defaults.set(newValue, forKey: DefaultsKey.launchAtLoginEnabled) }
    }
}
