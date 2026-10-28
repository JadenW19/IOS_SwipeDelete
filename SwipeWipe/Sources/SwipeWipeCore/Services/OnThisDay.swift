//
//  OnThisDay.swift
//  SwipeWipeCore
//
//  "On This Day" memories (same month/day, earlier years) and completion tracking.
//

import Foundation

public enum OnThisDay {

    /// Assets captured on the same month and day as `date`, in earlier years. Newest first.
    public static func assets(
        in buckets: [MonthlyBucket],
        on date: Date,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> [PhotoAssetModel] {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = c.year, let month = c.month, let day = c.day else { return [] }

        var result: [PhotoAssetModel] = []
        for bucket in buckets where bucket.identifier.month == month && bucket.identifier.year < year {
            for asset in bucket.assets where calendar.component(.day, from: asset.creationDate) == day {
                result.append(asset)
            }
        }
        return result.sorted { $0.creationDate > $1.creationDate }
    }

    /// Stable completion key for a day, e.g. `otd-2026-10-28`.
    public static func completionKey(
        for date: Date,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "otd-%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Completion key for a monthly cohort, e.g. `month-2026-10`.
    public static func completionKey(for month: MonthIdentifier) -> String {
        "month-\(month.id)"
    }
}

/// Persists which cohorts (months / on-this-day dates) the user has finished swiping.
public final class CompletionStore: @unchecked Sendable {

    private let defaults: UserDefaults
    private let storageKey = "swipewipe.completedCohorts"
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func isCompleted(_ key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return Set(defaults.stringArray(forKey: storageKey) ?? []).contains(key)
    }

    public func markCompleted(_ key: String) {
        lock.lock()
        defer { lock.unlock() }
        var set = Set(defaults.stringArray(forKey: storageKey) ?? [])
        set.insert(key)
        defaults.set(Array(set), forKey: storageKey)
    }

    public func clear(_ key: String) {
        lock.lock()
        defer { lock.unlock() }
        var set = Set(defaults.stringArray(forKey: storageKey) ?? [])
        set.remove(key)
        defaults.set(Array(set), forKey: storageKey)
    }

    public var allCompleted: Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return Set(defaults.stringArray(forKey: storageKey) ?? [])
    }
}
