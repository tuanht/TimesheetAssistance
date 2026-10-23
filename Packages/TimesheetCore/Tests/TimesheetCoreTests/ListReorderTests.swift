import Testing
@testable import TimesheetCore

struct ListReorderTests {
    private let items = ["a", "b", "c", "d"]

    @Test func dropTakesTheTargetsPlaceMovingRight() {
        #expect(ListReorder.move("a", onto: "c", in: items) == ["b", "c", "a", "d"])
    }

    @Test func dropTakesTheTargetsPlaceMovingLeft() {
        #expect(ListReorder.move("d", onto: "b", in: items) == ["a", "d", "b", "c"])
    }

    @Test func dropOntoItselfOrAnUnknownItemChangesNothing() {
        #expect(ListReorder.move("b", onto: "b", in: items) == items)
        #expect(ListReorder.move("x", onto: "b", in: items) == items)
        #expect(ListReorder.move("b", onto: "x", in: items) == items)
    }

    @Test func stepMovesOnePlace() {
        #expect(ListReorder.move("b", by: -1, in: items) == ["b", "a", "c", "d"])
        #expect(ListReorder.move("b", by: 1, in: items) == ["a", "c", "b", "d"])
    }

    @Test func stepPastEitherEndChangesNothing() {
        #expect(ListReorder.move("a", by: -1, in: items) == items)
        #expect(ListReorder.move("d", by: 1, in: items) == items)
    }
}
