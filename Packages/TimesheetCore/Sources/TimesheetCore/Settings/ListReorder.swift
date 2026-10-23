/// Reorders a list for drag-and-drop and arrow-key moves. An unknown item or an impossible move changes nothing.
public enum ListReorder {
    /// The dropped item takes the target's place, so dropping right lands after it and dropping left before it.
    public static func move<T: Equatable>(_ item: T, onto target: T, in items: [T]) -> [T] {
        guard let from = items.firstIndex(of: item), let to = items.firstIndex(of: target), from != to else {
            return items
        }
        var result = items
        result.remove(at: from)
        result.insert(item, at: to)
        return result
    }

    /// Moves the item `offset` places along the list.
    public static func move<T: Equatable>(_ item: T, by offset: Int, in items: [T]) -> [T] {
        guard let from = items.firstIndex(of: item), items.indices.contains(from + offset) else { return items }
        return move(item, onto: items[from + offset], in: items)
    }
}
