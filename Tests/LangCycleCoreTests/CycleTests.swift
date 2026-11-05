import Foundation
import Testing
@testable import LangCycleCore

private let abc = ["A", "B", "C"]

/// Simulates hotkey presses the way the app does: remembers its own last selection and its time.
/// `reported(selected)` returns what the system reports as current at the moment of the press.
private func press(times: [TimeInterval], start: String, direction: Direction = .forward,
                   layouts: [String] = abc, reported: (_ selected: [String]) -> String) -> [String] {
    var selected: [String] = [start]
    var last: String?, lastTime: TimeInterval?
    for now in times {
        let target = nextLayout(in: layouts, lastSelected: last, lastSelectedTime: lastTime,
                                current: reported(selected), now: now, direction: direction)!
        selected.append(target)
        last = target
        lastTime = now
    }
    return Array(selected.dropFirst())
}

@Test func quickPressesAdvanceEvenWhenSystemReportsStaleLayout() {
    // The system still reports A for every press (it has not caught up yet).
    #expect(press(times: [0, 0.15, 0.3], start: "A") { _ in "A" } == ["B", "C", "A"])
}

@Test func sixQuickPressesCycleTwiceWithLaggingSystem() {
    // The system reports the selection from two presses ago.
    let result = press(times: [0, 0.1, 0.2, 0.3, 0.4, 0.5], start: "A") { $0[max(0, $0.count - 2)] }
    #expect(result == ["B", "C", "A", "B", "C", "A"])
}

@Test func slowPressesUseCurrentLayoutAndKeepGoingForward() {
    // Press, wait 2 s (system has caught up), press again: B then C — never back to A.
    #expect(press(times: [0, 2], start: "A") { $0.last! } == ["B", "C"])
    #expect(press(times: [0, 1, 2, 3, 4, 5], start: "A") { $0.last! } == ["B", "C", "A", "B", "C", "A"])
}

@Test func externalChangeAfterWindowContinuesFromRealCurrentLayout() {
    // App selected B at t=0; user then picked A from the system menu; next press at t=2 → B (from A), not A (from B).
    let target = nextLayout(in: abc, lastSelected: "B", lastSelectedTime: 0, current: "A", now: 2, direction: .forward)
    #expect(target == "B")
}

@Test func backwardDirectionReverses() {
    #expect(press(times: [0, 0.1, 0.2], start: "A", direction: .backward) { _ in "A" } == ["C", "B", "A"])
    #expect(nextLayout(in: abc, lastSelected: nil, lastSelectedTime: nil, current: "B", now: 5, direction: .backward) == "A")
}

@Test func windowBoundary() {
    // Exactly at the window the last selection still counts; just past it the current layout wins.
    // (Times are exactly representable: 0.75 + 0.75 - 0.75 has no rounding error.)
    #expect(nextLayout(in: abc, lastSelected: "B", lastSelectedTime: 0.75, current: "A", now: 1.5, direction: .forward,
                       window: 0.75) == "C")
    #expect(nextLayout(in: abc, lastSelected: "B", lastSelectedTime: 0.75, current: "A", now: 1.5625, direction: .forward,
                       window: 0.75) == "B")
    #expect(nextLayout(in: abc, lastSelected: "B", lastSelectedTime: 10, current: "A", now: 10.79, direction: .forward) == "C")
    #expect(nextLayout(in: abc, lastSelected: "B", lastSelectedTime: 10, current: "A", now: 10.81, direction: .forward) == "B")
}

@Test func lastSelectionThatWasRemovedFallsBackToCurrent() {
    #expect(nextLayout(in: ["A", "C"], lastSelected: "B", lastSelectedTime: 0, current: "A", now: 0.1, direction: .forward) == "C")
}

@Test func currentLayoutOutsideCycleGoesToFirstOrLast() {
    #expect(nextLayout(in: abc, lastSelected: nil, lastSelectedTime: nil, current: "X", now: 0, direction: .forward) == "A")
    #expect(nextLayout(in: abc, lastSelected: nil, lastSelectedTime: nil, current: "X", now: 0, direction: .backward) == "C")
    #expect(nextLayout(in: abc, lastSelected: nil, lastSelectedTime: nil, current: nil, now: 0, direction: .forward) == "A")
}

@Test func singleAndEmptyLists() {
    #expect(nextLayout(in: ["A"], lastSelected: nil, lastSelectedTime: nil, current: "A", now: 0, direction: .forward) == "A")
    #expect(nextLayout(in: [], lastSelected: nil, lastSelectedTime: nil, current: "A", now: 0, direction: .forward) == nil)
}

@Test(arguments: [2, 3, 4, 5])
func forwardPressNeverReturnsPreviousLayout(count: Int) {
    // Mixed fast and slow presses, system lagging by one press on fast ones: always the next layout in order.
    let layouts = (0..<count).map { "L\($0)" }
    var time: TimeInterval = 0
    let times = (0..<40).map { i -> TimeInterval in time += (i % 3 == 0 ? 1.5 : 0.1); return time }
    var pressIndex = 0
    let result = press(times: times, start: "L0", layouts: layouts) { selected in
        defer { pressIndex += 1 }
        let fast = pressIndex > 0 && times[pressIndex] - times[pressIndex - 1] < 0.8
        return fast ? selected[max(0, selected.count - 2)] : selected.last!
    }
    for (i, id) in result.enumerated() {
        #expect(id == layouts[(i + 1) % count])
    }
}

@Test func shortCodes() {
    #expect(shortCode(languages: ["en", "af"], fallbackName: "ABC") == "EN")
    #expect(shortCode(languages: ["uk", "be"], fallbackName: "Ukrainian") == "УК")
    #expect(shortCode(languages: ["ru"], fallbackName: "Russian") == "РУ")
    #expect(shortCode(languages: ["de-CH"], fallbackName: "Swiss German") == "DE")
    #expect(shortCode(languages: ["sr-Latn"], fallbackName: "Serbian (Latin)") == "SR")
    #expect(shortCode(languages: [], fallbackName: "Unicode Hex Input") == "UN")
}

@Test func nativeNames() {
    #expect(nativeName(language: "uk") == "Українська")
    #expect(nativeName(language: "en") == "English")
    #expect(nativeName(language: "ru") == "Русский")
    #expect(nativeName(language: "de") == "Deutsch")
}
