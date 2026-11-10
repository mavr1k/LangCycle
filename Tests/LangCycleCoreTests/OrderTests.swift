import Testing
@testable import LangCycleCore

@Test func noSavedOrderKeepsSystemOrder() {
    #expect(applyOrder(to: ["a", "b", "c"], saved: []) == ["a", "b", "c"])
}

@Test func savedOrderIsRespected() {
    #expect(applyOrder(to: ["a", "b", "c"], saved: ["c", "a", "b"]) == ["c", "a", "b"])
}

@Test func newLayoutIsAppendedAndRemovedOneIsDropped() {
    #expect(applyOrder(to: ["a", "b", "d"], saved: ["c", "b", "a"]) == ["b", "a", "d"])
}

@Test func duplicatesInSavedOrderAreHarmless() {
    #expect(applyOrder(to: ["a", "b"], saved: ["b", "b", "a", "a", "x"]) == ["b", "a"])
}

@Test func movingUpSwapsWithNeighbourAndWraps() {
    #expect(movingUp("c", in: ["a", "b", "c"]) == ["a", "c", "b"])
    #expect(movingUp("a", in: ["a", "b", "c"]) == ["b", "c", "a"])
}

@Test func movingDownSwapsWithNeighbourAndWraps() {
    #expect(movingDown("a", in: ["a", "b", "c"]) == ["b", "a", "c"])
    #expect(movingDown("c", in: ["a", "b", "c"]) == ["c", "a", "b"])
}

@Test func movingUnknownIDOrShortListChangesNothing() {
    #expect(movingUp("x", in: ["a", "b"]) == ["a", "b"])
    #expect(movingDown("a", in: ["a"]) == ["a"])
    #expect(movingUp("a", in: []) == [])
}

@Test func mergeKeepsDisabledLayoutsInTheirSlots() {
    // "x" is disabled right now; moving "c" up must not lose it or change its slot.
    #expect(mergeOrder(visible: ["c", "a", "b"], into: ["a", "x", "b", "c"]) == ["c", "x", "a", "b"])
}

@Test func mergeAppendsLayoutsTheSavedListDoesNotKnow() {
    #expect(mergeOrder(visible: ["b", "a", "n"], into: ["a", "b"]) == ["b", "a", "n"])
    #expect(mergeOrder(visible: ["a", "b"], into: []) == ["a", "b"])
}

@Test func reEnabledLayoutReturnsToItsOldSlot() {
    let saved = mergeOrder(visible: ["b", "a"], into: ["a", "x", "b"])  // x disabled
    #expect(applyOrder(to: ["a", "x", "b"], saved: saved) == ["b", "x", "a"])
}

@Test func cyclingFollowsTheCustomOrder() {
    let order = applyOrder(to: ["a", "b", "c"], saved: ["c", "a", "b"])
    var current = "c"
    var visited: [String] = []
    for step in 0..<4 {
        current = nextLayout(in: order, lastSelected: nil, lastSelectedTime: nil, current: current,
                             now: Double(step) * 5, direction: .forward)!
        visited.append(current)
    }
    #expect(visited == ["a", "b", "c", "a"])
}
