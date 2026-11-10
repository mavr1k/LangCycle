import Foundation

/// Puts the enabled layouts into the user's order (FR-28). Pure, so it can be unit tested.
///
/// `ids` are the enabled layouts in system order, `saved` the stored custom order. Saved IDs that are enabled
/// come first, in saved order; layouts that are not in `saved` (newly enabled) follow in system order. Saved IDs
/// that are not enabled are ignored here, and duplicates in `saved` count once.
public func applyOrder(to ids: [String], saved: [String]) -> [String] {
    let enabled = Set(ids)
    var seen = Set<String>()
    let known = saved.filter { enabled.contains($0) && seen.insert($0).inserted }
    return known + ids.filter { !seen.contains($0) }
}

/// Moves `id` one slot earlier in `ids`. The first item wraps to the end, because the cycle is circular.
public func movingUp(_ id: String, in ids: [String]) -> [String] { moving(id, by: -1, in: ids) }

/// Moves `id` one slot later in `ids`. The last item wraps to the start.
public func movingDown(_ id: String, in ids: [String]) -> [String] { moving(id, by: 1, in: ids) }

private func moving(_ id: String, by step: Int, in ids: [String]) -> [String] {
    guard ids.count > 1, let index = ids.firstIndex(of: id) else { return ids }
    var result = ids
    let target = index + step
    if target < 0 {  // first item up: to the end (the others keep their order)
        result.append(result.removeFirst())
    } else if target >= ids.count {  // last item down: to the start
        result.insert(result.removeLast(), at: 0)
    } else {
        result.swapAt(index, target)
    }
    return result
}

/// Writes a new order of the enabled layouts back into the stored list (FR-28).
///
/// Stored IDs of layouts that are currently disabled keep their slots, so enabling such a layout again puts it
/// back where it was. Layouts the stored list doesn't know yet are appended.
public func mergeOrder(visible: [String], into saved: [String]) -> [String] {
    let visibleSet = Set(visible)
    var seen = Set<String>()
    var queue = visible[...]
    var result: [String] = []
    for id in saved where seen.insert(id).inserted {
        if visibleSet.contains(id) {
            if let next = queue.popFirst() { result.append(next) }
        } else {
            result.append(id)
        }
    }
    result.append(contentsOf: queue)
    return result
}
