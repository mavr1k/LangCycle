import Foundation

/// Decides when the HUD should hide: `delay` seconds after the last key of the hotkey combination was released.
/// While any of those keys is held the HUD stays; pressing one again during the delay starts the wait over.
/// Pure (the caller supplies the clock), so it can be unit tested.
public struct HoldTracker {
    public let delay: TimeInterval
    private var releasedAt: TimeInterval?

    public init(delay: TimeInterval = 1) {
        self.delay = delay
    }

    /// Forget any earlier release, e.g. when the HUD is shown again.
    public mutating func reset() {
        releasedAt = nil
    }

    /// Feed the current key state. Returns true once the HUD should hide.
    public mutating func update(held: Bool, now: TimeInterval) -> Bool {
        if held {
            releasedAt = nil
            return false
        }
        let since = releasedAt ?? now
        releasedAt = since
        return now - since >= delay
    }
}
