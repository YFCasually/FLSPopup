import XCTest
import SwiftUI
@testable import FLSPopup

final class PopupCenterTests: XCTestCase {
    private let page = PopupTarget.page(scene: "one", id: "edit")
    private let window = PopupTarget.window(scene: "one")
    private let other = PopupTarget.window(scene: "two")

    @MainActor private func makeCenter() -> PopupCenter {
        let center = PopupCenter()
        [page, window, other].forEach(center.register)
        return center
    }

    @MainActor @discardableResult
    private func add(_ center: PopupCenter, _ name: String, _ mode: PopupMode = .queue,
                     to target: PopupTarget? = nil, priority: PopupPriority = .medium,
                     group: String = "g", end: @escaping (PopupEndReason) -> Void = { _ in }) -> PopupHandle {
        var options = PopupOptions(mode: mode, group: group, identifier: name)
        options.priority = priority
        let handle = PopupHandle()
        XCTAssertEqual(center.present(target: target ?? page, options: options, handle: handle,
                                      onEnd: end) { EmptyView() }, .accepted(handle))
        return handle
    }

    @MainActor private func close(_ center: PopupCenter, _ handle: PopupHandle) {
        center.dismiss(handle)
        center.didExit(handle)
    }

    @MainActor func testPriorityUsesFIFOAndDoesNotPreempt() async {
        let c = makeCenter()
        let a = add(c, "A"), low = add(c, "L", priority: .low)
        let high = add(c, "H", priority: .high), high2 = add(c, "H2", priority: .high)
        for (id, name) in [(a, "A"), (high, "H"), (high2, "H2"), (low, "L")] {
            XCTAssertEqual(c.activeIdentifiers(), [name]); close(c, id)
        }
        XCTAssertEqual(c.count(), 0)
    }

    @MainActor func testInterruptAndSuspendRestorePeersBeforeQueue() async {
        let c = makeCenter()
        add(c, "A"); add(c, "B", .interrupt); add(c, "D")
        let x = add(c, "X", .suspend, to: window)
        XCTAssertEqual(c.count(phase: .suspended), 2)
        close(c, x)
        XCTAssertEqual(c.activeIdentifiers(), ["A", "B"])
        XCTAssertEqual(c.count(phase: .waiting), 1)
    }

    @MainActor func testBothReplacementPoliciesWithNestedStack() async {
        for inherit in [true, false] {
            let c = makeCenter()
            add(c, "A"); let b = add(c, "B", .suspend)
            add(c, "C", .suspend); add(c, "D")
            let x = add(c, "X", inherit ? .replaceInheritSuspend : .replaceClearSuspend)
            close(c, x)
            XCTAssertEqual(c.activeIdentifiers(), inherit ? ["B"] : ["D"])
            if inherit { close(c, b); XCTAssertEqual(c.activeIdentifiers(), ["A"]) }
        }
    }

    @MainActor func testReplacingAndLockingGroupPreservesOtherGroup() async {
        for mode in [PopupMode.replaceAll, .groupUnique] {
            let c = makeCenter()
            add(c, "A"); add(c, "B", .suspend); add(c, "C")
            add(c, "Z", group: "z")
            let owner = add(c, "X", mode)
            XCTAssertEqual(c.count(group: "g"), 1)
            XCTAssertEqual(c.count(group: "z"), 1)
            let options = PopupOptions(group: "g")
            let result = c.present(target: window, options: options) { EmptyView() }
            if mode == .groupUnique {
                XCTAssertEqual(result, .rejected(.groupLocked))
            } else { XCTAssertEqual(c.count(phase: .waiting), 1) }
            close(c, owner)
            add(c, "Y")
        }
    }

    @MainActor func testGlobalLockAcrossScenesReleasesOnDisconnect() async {
        let c = makeCenter()
        add(c, "A"); add(c, "B", to: other)
        add(c, "X", .globalUnique, to: window)
        XCTAssertEqual(c.activeIdentifiers(), ["X"])
        XCTAssertEqual(c.present(target: other) { EmptyView() }, .rejected(.globalLocked))
        c.disconnect(scene: "one")
        add(c, "Z", to: other)
        XCTAssertEqual(c.present(target: page) { EmptyView() }, .rejected(.hostUnavailable))
        XCTAssertEqual(c.present(target: window) { EmptyView() }, .rejected(.sceneUnavailable))
    }

    @MainActor func testDeduplicationPersistsDuringExitAndSeparatesScenes() async {
        let c = makeCenter()
        let first = add(c, "draft")
        c.dismiss(first)
        var opts = PopupOptions(group: "other", identifier: "draft")
        XCTAssertEqual(c.present(target: window, options: opts) { EmptyView() }, .rejected(.duplicate))
        add(c, "draft", to: other)
        opts.deduplicationScope = .application
        c.didExit(first)
        XCTAssertEqual(c.present(target: page, options: opts) { EmptyView() }, .rejected(.duplicate))
        c.dismissAll()
        add(c, "draft")
    }

    @MainActor func testInvalidHostDoesNotClearExistingItems() async {
        let c = makeCenter(); add(c, "A")
        let result = c.present(target: .page(scene: "one", id: "gone"),
                               options: .init(mode: .globalUnique)) { EmptyView() }
        XCTAssertEqual(result, .rejected(.hostUnavailable))
        XCTAssertEqual(c.activeIdentifiers(), ["A"])
    }

    @MainActor func testOwnerDismissedBeforePeerDoesNotStrandLayer() async {
        let c = makeCenter(); add(c, "A")
        let b = add(c, "B", .suspend), x = add(c, "X", .interrupt)
        close(c, b); XCTAssertEqual(c.activeIdentifiers(), ["X"])
        close(c, x); XCTAssertEqual(c.activeIdentifiers(), ["A"])
    }

    @MainActor func testHostRemovalSkipsInvalidSuspendedItem() async {
        let c = makeCenter(); add(c, "A")
        let w = add(c, "W", .suspend, to: window)
        add(c, "Q", to: window)
        c.unregister(page); close(c, w)
        XCTAssertEqual(c.activeIdentifiers(), ["Q"])
    }

    @MainActor func testExactlyOnceAndReentrantPresentation() async {
        let c = makeCenter()
        var reasons: [PopupEndReason] = []
        let a = add(c, "A", end: { reason in
            reasons.append(reason)
            self.add(c, "next")
        })
        c.dismiss(a, reason: .action); c.dismiss(a); c.didExit(a); c.didExit(a)
        XCTAssertEqual(reasons, [.action])
        XCTAssertEqual(c.activeIdentifiers(), ["next"])
    }

    @MainActor func testCancellingSuspendedSubtreePreservesCurrentOwner() async {
        let c = makeCenter(); add(c, "A")
        let b = add(c, "B", .suspend), x = add(c, "X", .suspend)
        c.dismiss(b)
        XCTAssertEqual(c.count(), 1)
        close(c, x); XCTAssertEqual(c.count(), 0)
    }

    @MainActor func testFirstDisplayFiresOnceAfterEntranceEvenWhenSuspended() async {
        let center = makeCenter()
        var displays: [PopupHandle] = []
        var options = PopupOptions(group: "g")
        options.onFirstDisplay = { displays.append($0) }
        let id = PopupHandle()
        _ = center.present(target: page, options: options, handle: id) { EmptyView() }
        let first = add(center, "first", .suspend)
        center.didAppear(id)
        XCTAssertTrue(displays.isEmpty)
        close(center, first)
        center.didAppear(id)
        let second = add(center, "second", .suspend)
        close(center, second)
        center.didAppear(id)
        XCTAssertEqual(displays, [id])
    }

    @MainActor func testApplicationGroupSharesQueueAcrossScenes() async {
        let center = makeCenter()
        var options = PopupOptions(group: "shared")
        options.scope = .application
        let a = PopupHandle(), b = PopupHandle()
        _ = center.present(target: window, options: options, handle: a) { EmptyView() }
        _ = center.present(target: other, options: options, handle: b) { EmptyView() }
        XCTAssertEqual(center.records(phase: .waiting).map(\.id), [b])
        center.disconnect(scene: "one")
        XCTAssertEqual(center.records(phase: .entering).map(\.id), [b])
        center.dismiss(applicationGroup: "shared")
        XCTAssertEqual(center.count(), 0)
    }

    @MainActor func testCountdownPausesWhileBackgroundedAndSuspended() async {
        var now: TimeInterval = 0
        var callbacks: [@MainActor () -> Void] = []
        var delays: [TimeInterval] = []
        let c = PopupCenter(now: { now }, schedule: { delay, fire in
            callbacks.append(fire); delays.append(delay); return {}
        })
        c.register(page)
        var options = PopupOptions(style: .toast, group: "g")
        options.duration = 10
        let h = PopupHandle()
        _ = c.present(target: page, options: options, handle: h) { EmptyView() }
        c.didAppear(h)
        now = 3; c.setSceneActive(false, scene: "one")
        now = 60; callbacks[0]()
        c.setSceneActive(true, scene: "one")
        XCTAssertEqual(delays.last, 7)
        now = 62; let s = add(c, "S", .suspend)
        now = 70; close(c, s)
        XCTAssertEqual(delays.last, 5)
        now = 75; callbacks.last?()
        XCTAssertEqual(c.records.first?.phase, .exiting)
        c.didExit(h); XCTAssertEqual(c.count(), 0)
    }
}
