import Foundation

enum SessionFlowDefaults {
    private static let lock = NSLock()
    private static var overrideStore: UserDefaults?

    static var store: UserDefaults {
        lock.lock()
        defer { lock.unlock() }
        return overrideStore ?? .standard
    }

    static func useOverrideStore(_ store: UserDefaults?) {
        lock.lock()
        overrideStore = store
        lock.unlock()
    }
}
