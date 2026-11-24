import SwiftUI

public struct PopupRecord: Identifiable {
    public let id: PopupHandle
    public let target: PopupTarget
    public let options: PopupOptions
    public fileprivate(set) var phase: PopupPhase
    public fileprivate(set) var content: AnyView
}

private extension PopupPhase {
    var isActive: Bool { self == .entering || self == .visible || self == .exiting }
}

@MainActor
public final class PopupCenter: ObservableObject {
    public static let shared = PopupCenter()
    @Published public private(set) var records: [PopupRecord] = []

    private struct Group: Hashable {
        let name: String
        let scene: String?

        init(_ name: String, scene: String?) {
            self.name = name
            self.scene = scene
        }

        init(_ target: PopupTarget, _ options: PopupOptions) {
            self.init(options.group, scene: options.scope == .scene ? target.sceneID : nil)
        }
    }

    private final class Entry {
        var record: PopupRecord
        let group: Group
        let end: (PopupEndReason) -> Void
        var reason: PopupEndReason?
        var appeared = false
        var remaining: TimeInterval?
        var started: TimeInterval?
        var timerID: UUID?
        var cancelTimer: (() -> Void)?

        init(_ record: PopupRecord, end: @escaping (PopupEndReason) -> Void) {
            self.record = record
            self.group = Group(record.target, record.options)
            self.end = end
            remaining = record.options.duration.flatMap { $0.isFinite ? max(0, $0) : nil }
        }
    }

    // Oldest layer first. An owner that finishes before its peers leaves its
    // layer in the group until every active peer has finished.
    private struct Layer {
        var owner: PopupHandle?
        var members: [PopupHandle]
    }

    private var entries: [Entry] = []
    private var layers: [Group: [Layer]] = [:]
    private var hosts: Set<PopupTarget> = []
    private var inactiveScenes: Set<String> = []
    private var completions: [() -> Void] = []
    private var publishing = false
    private var delivering = false
    private var changed = false

    typealias Schedule = (TimeInterval, @escaping @MainActor () -> Void) -> () -> Void
    private let now: () -> TimeInterval
    private let schedule: Schedule

    convenience init() {
        let clock = ContinuousClock()
        let origin = clock.now
        self.init(now: {
            let elapsed = origin.duration(to: clock.now).components
            return Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
        }) { delay, fire in
            let task = Task { @MainActor in
                // Bound each sleep to avoid overflowing nanoseconds for large durations.
                do { try await Task.sleep(nanoseconds: UInt64(min(delay, 86_400) * 1e9)) }
                catch { return }
                fire()
            }
            return { task.cancel() }
        }
    }

    init(now: @escaping () -> TimeInterval, schedule: @escaping Schedule) {
        self.now = now
        self.schedule = schedule
    }

    public func register(_ target: PopupTarget) {
        hosts.insert(target)
    }

    public func unregister(_ target: PopupTarget) {
        hosts.remove(target)
        clear(entries.filter { $0.record.target == target }, reason: .hostRemoved)
    }

    public func disconnect(scene: String) {
        hosts = hosts.filter { $0.sceneID != scene }
        inactiveScenes.remove(scene)
        clear(entries.filter { $0.record.target.sceneID == scene }, reason: .hostRemoved)
    }

    public func setSceneActive(_ active: Bool, scene: String) {
        if active {
            guard inactiveScenes.remove(scene) != nil else { return }
        } else {
            guard inactiveScenes.insert(scene).inserted else { return }
        }
        for entry in entries where entry.record.target.sceneID == scene {
            if active { startTimer(entry) } else { pauseTimer(entry) }
        }
    }

    @discardableResult
    public func present(target: PopupTarget, options: PopupOptions = .init(),
                        handle: PopupHandle = .init(),
                        onEnd: @escaping (PopupEndReason) -> Void = { _ in },
                        @ViewBuilder content: () -> some View) -> PopupResult {
        if let reason = rejection(target, options, handle) { return .rejected(reason) }
        let view = AnyView(content())
        // The caller's synchronous builder can itself submit or remove requests.
        if let reason = rejection(target, options, handle) { return .rejected(reason) }

        let record = PopupRecord(id: handle, target: target, options: options, phase: .entering, content: view)
        let entry = Entry(record, end: onEnd)
        let members = entries.filter { $0.group == entry.group }
        let active = members.filter { $0.record.phase.isActive }
        switch options.mode {
        case .queue:
            if !active.isEmpty { entry.record.phase = .waiting }
        case .interrupt:
            break
        case .suspend:
            let resumable = active.filter { $0.record.phase != .exiting }
            finish(active.filter { $0.record.phase == .exiting }, reason: .replaced)
            if !resumable.isEmpty {
                for item in resumable {
                    pauseTimer(item)
                    item.record.phase = .suspended
                }
                layers[entry.group, default: []].append(
                    Layer(owner: handle, members: resumable.map { $0.record.id })
                )
            }
        case .replaceInheritSuspend:
            let previous = Set(active.map { $0.record.id })
            if var stack = layers[entry.group] {
                for index in stack.indices where stack[index].owner.map(previous.contains) == true {
                    stack[index].owner = handle
                }
                layers[entry.group] = stack
            }
            finish(active, reason: .replaced)
        case .replaceClearSuspend:
            finish(members.filter { $0.record.phase != .waiting }, reason: .replaced)
        case .replaceAll, .groupUnique:
            finish(members, reason: .replaced)
        case .globalUnique:
            finish(entries, reason: .replaced)
        }
        entries.append(entry)
        publish()
        return .accepted(handle)
    }

    private func rejection(_ target: PopupTarget, _ options: PopupOptions, _ handle: PopupHandle) -> PopupRejection? {
        guard hosts.contains(target) else {
            if case .page = target { return .hostUnavailable }
            return .sceneUnavailable
        }
        if entries.contains(where: { $0.record.options.mode == .globalUnique }) { return .globalLocked }
        let group = Group(target, options)
        if entries.contains(where: { $0.group == group && $0.record.options.mode == .groupUnique }) {
            return .groupLocked
        }
        if entries.contains(where: { $0.record.id == handle }) { return .duplicate }
        if let key = options.identifier, entries.contains(where: {
            $0.record.options.identifier == key &&
                (options.deduplicationScope == .application ||
                 $0.record.options.deduplicationScope == .application || $0.record.target.sceneID == target.sceneID)
        }) { return .duplicate }
        return nil
    }

    public func update(_ handle: PopupHandle, content: AnyView) {
        guard let item = entry(handle), item.record.phase != .exiting else { return }
        item.record.content = content
        publish()
    }

    public func didAppear(_ handle: PopupHandle) {
        guard let item = entry(handle), item.record.phase == .entering else { return }
        if !item.appeared, let shown = item.record.options.onFirstDisplay {
            completions.append { shown(handle) }
        }
        item.appeared = true
        item.record.phase = .visible
        startTimer(item)
        publish()
    }

    public func dismiss(_ handle: PopupHandle, reason: PopupEndReason = .cancelled) {
        guard let item = entry(handle) else { return }
        switch item.record.phase {
        case .exiting: return
        case .waiting:
            clear([item], reason: reason)
        case .suspended:
            var subtree: Set<PopupHandle> = [handle]
            // Owners always belong to a later layer than the members they suspended.
            for layer in (layers[item.group] ?? []).reversed() {
                if let owner = layer.owner, subtree.contains(owner) { subtree.formUnion(layer.members) }
            }
            clear(entries.filter { subtree.contains($0.record.id) }, reason: reason)
        case .entering, .visible:
            pauseTimer(item)
            item.reason = reason
            item.record.phase = .exiting
            publish()
        }
    }

    public func didExit(_ handle: PopupHandle) {
        guard let item = entry(handle), item.record.phase == .exiting, let reason = item.reason else { return }
        clear([item], reason: reason)
    }

    /// Clears one scene-scoped scheduling group on both page and window hosts.
    public func dismiss(group: String = "default", scene: String) {
        clear(entries.filter { $0.group == Group(group, scene: scene) }, reason: .cancelled)
    }

    public func dismiss(applicationGroup group: String) {
        clear(entries.filter { $0.group == Group(group, scene: nil) }, reason: .cancelled)
    }

    /// Clears targets in the scene, including members of application-scoped groups.
    public func dismiss(scene: String) {
        clear(entries.filter { $0.record.target.sceneID == scene }, reason: .cancelled)
    }

    public func dismissAll() { clear(entries, reason: .cancelled) }

    /// Filters by physical scene, group name, scheduling scope, business key and phase.
    public func records(scene: String? = nil, group: String? = nil, scope: PopupScope? = nil,
                        identifier: String? = nil, phase: PopupPhase? = nil) -> [PopupRecord] {
        entries.map(\.record).filter {
            (scene == nil || $0.target.sceneID == scene) && (group == nil || $0.options.group == group)
                && (scope == nil || $0.options.scope == scope) && (identifier == nil || $0.options.identifier == identifier)
                && (phase == nil || $0.phase == phase)
        }
    }

    public func count(scene: String? = nil, group: String? = nil, scope: PopupScope? = nil,
                      phase: PopupPhase? = nil) -> Int {
        records(scene: scene, group: group, scope: scope, phase: phase).count
    }

    public func activeCount(scene: String? = nil, group: String? = nil, scope: PopupScope? = nil) -> Int {
        records(scene: scene, group: group, scope: scope).filter { $0.phase.isActive }.count
    }

    public func activeIdentifiers(scene: String? = nil, group: String? = nil, scope: PopupScope? = nil) -> [String] {
        records(scene: scene, group: group, scope: scope).filter { $0.phase.isActive }.compactMap(\.options.identifier)
    }

    private func entry(_ handle: PopupHandle) -> Entry? { entries.first { $0.record.id == handle } }

    private func clear(_ victims: [Entry], reason: PopupEndReason) {
        guard !victims.isEmpty else { return }
        finish(victims, reason: reason)
        for group in Set(victims.map(\.group)) { dispatch(group) }
        publish()
    }

    private func finish(_ victims: [Entry], reason: PopupEndReason) {
        guard !victims.isEmpty else { return }
        let ids = Set(victims.map { $0.record.id })
        entries.removeAll { ids.contains($0.record.id) }
        for group in Set(victims.map(\.group)) {
            guard var stack = layers[group] else { continue }
            for index in stack.indices {
                if let owner = stack[index].owner, ids.contains(owner) { stack[index].owner = nil }
                stack[index].members.removeAll(where: ids.contains)
            }
            stack.removeAll { $0.members.isEmpty }
            layers[group] = stack.isEmpty ? nil : stack
        }
        for item in victims {
            pauseTimer(item)
            let end = item.end
            let result = item.reason ?? reason
            completions.append { end(result) }
        }
    }

    private func dispatch(_ group: Group) {
        let members = entries.filter { $0.group == group }
        guard !members.contains(where: { $0.record.phase.isActive }) else { return }
        if var stack = layers[group], let layer = stack.popLast() {
            layers[group] = stack.isEmpty ? nil : stack
            for id in layer.members {
                guard let item = entry(id) else { continue }
                item.record.phase = item.appeared ? .visible : .entering
                startTimer(item)
            }
            return
        }
        // Waiting entries retain insertion order. Compare strictly so ties keep the first.
        var next: Entry?
        for item in members where item.record.phase == .waiting {
            if let best = next, item.record.options.priority.rawValue <= best.record.options.priority.rawValue { continue }
            next = item
        }
        if let next {
            entries.removeAll { $0 === next }
            next.record.phase = .entering
            entries.append(next)
        }
    }

    private func pauseTimer(_ item: Entry) {
        item.cancelTimer?()
        item.cancelTimer = nil
        item.timerID = nil
        if let started = item.started, let remaining = item.remaining {
            item.remaining = max(0, remaining - (now() - started))
        }
        item.started = nil
    }

    private func startTimer(_ item: Entry) {
        guard item.record.phase == .visible, !inactiveScenes.contains(item.record.target.sceneID),
              item.timerID == nil, let remaining = item.remaining else { return }
        let token = UUID()
        item.timerID = token
        item.started = now()
        item.cancelTimer = schedule(remaining) { [weak self, weak item] in
            guard let self, let item, item.timerID == token else { return }
            self.pauseTimer(item)
            if item.remaining == 0 {
                self.dismiss(item.record.id, reason: .timeout)
            } else {
                self.startTimer(item)
            }
        }
    }

    // @Published sends synchronously in willSet. Nested submissions mutate the
    // canonical entries immediately, then this outer loop publishes the latest state.
    private func publish() {
        changed = true
        guard !publishing else { return }
        publishing = true
        while changed {
            changed = false
            records = entries.map(\.record)
        }
        publishing = false

        guard !delivering else { return }
        delivering = true
        while !completions.isEmpty {
            let callbacks = completions
            completions.removeAll()
            for callback in callbacks { callback() }
        }
        delivering = false
    }
}
