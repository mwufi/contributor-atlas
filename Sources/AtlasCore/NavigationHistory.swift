import Foundation

public struct AtlasLocation: Hashable, Sendable {
    public var section: String
    public var filters: Filters
    public var range: String
    public var year: Int
    public init(section: String = "Overview", filters: Filters = Filters(), range: String = "All history", year: Int = 2026) {
        self.section = section; self.filters = filters; self.range = range; self.year = year
    }
    public func differsOnlyInQuery(from other: Self) -> Bool {
        var copy = self
        copy.filters.query = other.filters.query
        return copy == other && filters.query != other.filters.query
    }
}

/// Browser-style history. A new visit after Back discards the forward branch.
public struct NavigationHistory<Location: Equatable & Sendable>: Sendable {
    public private(set) var current: Location
    public private(set) var previous: [Location] = []
    public private(set) var next: [Location] = []
    private let limit: Int
    public var canGoBack: Bool { !previous.isEmpty }
    public var canGoForward: Bool { !next.isEmpty }
    public init(_ initial: Location, limit: Int = 80) { current = initial; self.limit = max(1, limit) }
    public mutating func record(_ location: Location, replacingCurrent: Bool = false) {
        guard location != current else { return }
        if !replacingCurrent {
            previous.append(current)
            if previous.count > limit { previous.removeFirst(previous.count - limit) }
        }
        current = location; next.removeAll()
    }
    @discardableResult public mutating func back() -> Location? {
        guard let destination = previous.popLast() else { return nil }
        next.append(current); current = destination; return destination
    }
    @discardableResult public mutating func forward() -> Location? {
        guard let destination = next.popLast() else { return nil }
        previous.append(current); current = destination; return destination
    }
}

/// Bounded cache; refreshing a repository replaces the entire instance.
public struct RecentCache<Key: Hashable, Value> {
    private var values: [Key: Value] = [:]
    private var order: [Key] = []
    private let capacity: Int
    public init(capacity: Int = 24) { self.capacity = max(1, capacity) }
    public mutating func value(for key: Key) -> Value? {
        guard let value = values[key] else { return nil }
        order.removeAll { $0 == key }; order.append(key)
        return value
    }
    public mutating func insert(_ value: Value, for key: Key) {
        values[key] = value
        order.removeAll { $0 == key }; order.append(key)
        while order.count > capacity { values.removeValue(forKey: order.removeFirst()) }
    }
}
