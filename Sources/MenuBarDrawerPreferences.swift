import Foundation

/// Stable bundle IDs retain preferences while an application is not running.
struct MenuBarDrawerPreferences: Codable {
    var order: [String] = []

    func sortedIDs(_ ids: [String]) -> [String] {
        let available = Set(ids)
        var seen = Set<String>()
        return (order.filter { available.contains($0) } + ids).filter { seen.insert($0).inserted }
    }

    static func load(from defaults: UserDefaults) -> Self {
        guard let data = defaults.data(forKey: "menubar_drawer_preferences"),
              let value = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return value
    }

    func save(to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: "menubar_drawer_preferences")
    }
}
