import Foundation

/// How many times each voice was picked, day by day. Kept on disk, so history survives restarts.
public struct PickStats: Codable, Equatable, Sendable {
    /// "yyyy-MM-dd" in the user's time zone → voice → picks.
    public private(set) var days: [String: [Voice: Int]] = [:]

    public init(days: [String: [Voice: Int]] = [:]) { self.days = days }

    public static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    /// Records a pick. When the user changes their mind about the same answer, `replacing` moves the pick
    /// instead of counting twice.
    public mutating func record(_ voice: Voice, replacing previous: Voice? = nil, on day: String) {
        var counts = days[day] ?? [:]
        if let previous, let n = counts[previous], n > 0 {
            counts[previous] = n - 1 == 0 ? nil : n - 1
        }
        counts[voice, default: 0] += 1
        days[day] = counts
    }

    /// Takes a pick back when the user un-picks the winner.
    public mutating func remove(_ voice: Voice, on day: String) {
        guard let n = days[day]?[voice], n > 0 else { return }
        days[day]?[voice] = n == 1 ? nil : n - 1
        if days[day]?.isEmpty == true { days[day] = nil }
    }

    public func counts(on day: String) -> [Voice: Int] { days[day] ?? [:] }

    public var allTime: [Voice: Int] {
        days.values.reduce(into: [:]) { total, day in
            for (voice, n) in day { total[voice, default: 0] += n }
        }
    }

    /// The voices picked most. Several when they are tied, in the parliament's order; empty with no picks.
    public static func leaders(of counts: [Voice: Int]) -> [Voice] {
        guard let top = counts.values.max(), top > 0 else { return [] }
        return Voice.allCases.filter { counts[$0] == top }
    }

    /// Recent days with picks, newest first.
    public func recentDays(_ limit: Int) -> [(day: String, leaders: [Voice], total: Int)] {
        days.keys.sorted(by: >).prefix(limit).compactMap { day in
            let counts = days[day] ?? [:]
            let leaders = Self.leaders(of: counts)
            guard !leaders.isEmpty else { return nil }
            return (day, leaders, counts.values.reduce(0, +))
        }
    }
}

/// Reads and writes the stats as JSON in Application Support.
public struct PickStatsStore: Sendable {
    public let url: URL

    public init(url: URL? = nil) {
        self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Cortes/stats.json")
    }

    public func load() -> PickStats {
        guard let data = try? Data(contentsOf: url),
              let stats = try? JSONDecoder().decode(PickStats.self, from: data) else { return PickStats() }
        return stats
    }

    public func save(_ stats: PickStats) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(stats).write(to: url, options: .atomic)
    }
}
