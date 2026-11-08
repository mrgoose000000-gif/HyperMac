import Foundation

/// NSWindow numbers are signed platform integers, not guaranteed CGWindowIDs.
enum MenuBarWindowIdentity {
    static func exactID(_ number: Int) -> UInt32? {
        guard number > 0 else { return nil }
        return UInt32(exactly: number)
    }
}
