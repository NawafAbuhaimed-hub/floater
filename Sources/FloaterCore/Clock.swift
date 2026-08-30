import Foundation

/// Abstraction over "what time is it" so the timer can be driven deterministically in tests.
public protocol Clock: AnyObject {
    var now: Date { get }
}

public final class SystemClock: Clock {
    public init() {}
    public var now: Date { Date() }
}

/// Manually advanced clock used by tests to simulate ticking, sleeping, and waking.
public final class TestClock: Clock {
    public var now: Date
    public init(now: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
        self.now = now
    }
    public func advance(_ interval: TimeInterval) {
        now = now.addingTimeInterval(interval)
    }
}
