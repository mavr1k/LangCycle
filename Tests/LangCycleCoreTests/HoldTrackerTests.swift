import Testing
@testable import LangCycleCore

// Times are exactly representable in binary, so the comparisons have no rounding error.

@Test func staysVisibleWhileKeysAreHeld() {
    var tracker = HoldTracker()
    for now in stride(from: 0.0, through: 60, by: 0.5) {
        #expect(tracker.update(held: true, now: now) == false)
    }
}

@Test func hidesOneSecondAfterAllKeysAreReleased() {
    var tracker = HoldTracker()
    #expect(tracker.update(held: true, now: 10) == false)
    #expect(tracker.update(held: false, now: 10.25) == false)   // released here
    #expect(tracker.update(held: false, now: 10.75) == false)
    #expect(tracker.update(held: false, now: 11.1875) == false) // 0.9375 s after the release
    #expect(tracker.update(held: false, now: 11.25) == true)    // 1 s after the release
}

@Test func aQuickTapStillWaitsTheFullDelayAfterRelease() {
    // Released at the first check: hides 1 s after that, not 1 s after the press.
    var tracker = HoldTracker()
    #expect(tracker.update(held: false, now: 5) == false)
    #expect(tracker.update(held: false, now: 5.75) == false)
    #expect(tracker.update(held: false, now: 6) == true)
}

@Test func holdingAgainDuringTheDelayStartsTheWaitOver() {
    var tracker = HoldTracker()
    #expect(tracker.update(held: false, now: 10) == false)
    #expect(tracker.update(held: false, now: 10.75) == false)
    #expect(tracker.update(held: true, now: 10.875) == false)   // pressed again before the second was up
    #expect(tracker.update(held: false, now: 11) == false)      // new release
    #expect(tracker.update(held: false, now: 11.75) == false)
    #expect(tracker.update(held: false, now: 12) == true)
}

@Test func resetForgetsAnEarlierRelease() {
    var tracker = HoldTracker()
    #expect(tracker.update(held: false, now: 10) == false)
    tracker.reset()                                             // the HUD was shown again
    #expect(tracker.update(held: false, now: 10.5) == false)
    #expect(tracker.update(held: false, now: 11.25) == false)
    #expect(tracker.update(held: false, now: 11.5) == true)
}

@Test func customDelay() {
    var tracker = HoldTracker(delay: 0.5)
    #expect(tracker.update(held: false, now: 1) == false)
    #expect(tracker.update(held: false, now: 1.5) == true)
}
