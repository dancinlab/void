import Foundation

extension UserDefaults {
    static var voidSuite: String? {
        #if DEBUG
        ProcessInfo.processInfo.environment["VOID_USER_DEFAULTS_SUITE"]
        #else
        nil
        #endif
    }

    static var void: UserDefaults {
        voidSuite.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }
}
