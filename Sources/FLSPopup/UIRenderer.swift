import SwiftUI
import UIKit

@MainActor
struct PopupStack: View {
    let target: PopupTarget
    let regions: PopupHitRegions
    @ObservedObject private var center = PopupCenter.shared
    @StateObject private var focus = PopupAccessibilityFocus()

    var body: some View {
        let records = center.records.filter { $0.target == target && $0.phase != .waiting }
        let modal = records.last { $0.options.blocksBackground && $0.phase.occupiesHost }
        ZStack {
            ForEach(records) { record in
                let index = records.firstIndex { $0.id == record.id }!
                PopupLayer(record: record, regions: regions, focus: focus)
                    .accessibilityHidden(record.phase == .suspended ||
                        modal.map { top in records[index...].contains { $0.id == top.id && top.id != record.id } } == true)
                    .zIndex(Double(index))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PopupMarker { regions.boundsView = $0 })
        .onChange(of: modal?.id, initial: true) { _, next in focus.modalChanged(next, regions: regions) }
        .onDisappear { focus.modalChanged(nil, regions: regions) }
    }
}

@MainActor
private struct PopupLayer: View {
    let record: PopupRecord
    let regions: PopupHitRegions
    let focus: PopupAccessibilityFocus
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var opaque
    @Environment(\.colorScheme) private var inheritedScheme
    @State private var inserted = false
    @State private var generation = UUID()
    @State private var announced = false

    private var options: PopupOptions { record.options }
    private var radius: CGFloat { options.style == .panel ? 24 : 16 }

    var body: some View {
        ZStack(alignment: options.alignment) {
            if options.blocksBackground {
                Color.black.opacity(inserted ? 0.33 : 0.001)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if options.background == .dismiss {
                            PopupCenter.shared.dismiss(record.id, reason: .background)
                        }
                    }
                    .accessibilityHidden(true)
            }
            if inserted {
                surface
                    .padding(max(0, options.margin))
                    .transition(reduceMotion ? .opacity : options.transition)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: options.alignment)
        .opacity(record.phase == .suspended ? 0 : 1)
        .allowsHitTesting(record.phase != .suspended)
        .environment(\.colorScheme, options.colorScheme ?? inheritedScheme)
        .environment(\.dismissPopup, { PopupCenter.shared.dismiss(record.id, reason: .action) })
        .task(id: record.phase) {
            await Task.yield()
            guard !Task.isCancelled else { return }
            applyPhase()
        }
    }

    private var surface: some View {
        ViewThatFits(in: .vertical) {
            record.content
            ScrollView { record.content.frame(maxWidth: .infinity, alignment: .leading) }
                .scrollBounceBehavior(.basedOnSize)
        }
        .padding(options.style == .toast ? 12 : 16)
        .frame(minWidth: 44, maxWidth: options.style == .panel ? 640 : 440, minHeight: 44)
        .background {
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            if opaque { shape.fill(Color(uiColor: .systemBackground)) }
            else { shape.fill(.regularMaterial) }
        }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .contentShape(Rectangle())
        .background(PopupMarker { regions.surfaces.setObject($0, forKey: record.id.id as NSUUID) })
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(options.blocksBackground ? .isModal : [])
        .modifier(PopupEscape(enabled: options.allowsEscape, handle: record.id))
        .allowsHitTesting(record.phase != .exiting)
    }

    private func applyPhase() {
        let token = UUID()
        generation = token
        let phase = record.phase
        switch phase {
        case .waiting: break
        case .visible, .suspended:
            inserted = true
            if phase == .visible { notifyAccessibility() }
        case .entering, .exiting:
            let entering = phase == .entering
            let complete = {
                // SwiftUI may complete synchronously when the animation is disabled.
                Task { @MainActor in
                    guard generation == token,
                          PopupCenter.shared.records.contains(where: { $0.id == record.id && $0.phase == phase }) else { return }
                    if entering { PopupCenter.shared.didAppear(record.id) }
                    else { PopupCenter.shared.didExit(record.id) }
                }
            }
            if inserted == entering { complete(); return }
            withAnimation(reduceMotion ? nil : options.animation, completionCriteria: .removed) {
                inserted = entering
            } completion: { complete() }
        }
    }

    private func notifyAccessibility() {
        guard UIAccessibility.isVoiceOverRunning else { return }
        if options.blocksBackground {
            focus.move(to: record.id, regions: regions)
        } else if options.style == .toast, !announced {
            announced = true
            let labels = focus.elements(in: record.id, regions: regions).compactMap(\.accessibilityLabel)
            if !labels.isEmpty {
                UIAccessibility.post(notification: .announcement, argument: labels.joined(separator: ", "))
            }
        }
    }
}

private struct PopupEscape: ViewModifier {
    let enabled: Bool
    let handle: PopupHandle
    @ViewBuilder func body(content: Content) -> some View {
        if enabled {
            content.accessibilityAction(.escape) { PopupCenter.shared.dismiss(handle, reason: .cancelled) }
        } else { content }
    }
}

@MainActor
private final class PopupAccessibilityFocus: ObservableObject {
    private weak var previous: NSObject?
    private var current: PopupHandle?

    func modalChanged(_ next: PopupHandle?, regions: PopupHitRegions) {
        guard current != next else { return }
        if current == nil, next != nil {
            previous = UIAccessibility.focusedElement(using: .notificationVoiceOver) as? NSObject
        }
        current = next
        guard UIAccessibility.isVoiceOverRunning else { return }
        if let next {
            if regions.layers.contains(where: { $0.id == next && $0.phase == .visible }) { move(to: next, regions: regions) }
        } else if let previous {
            UIAccessibility.post(notification: .layoutChanged, argument: previous)
            self.previous = nil
        }
    }

    func move(to id: PopupHandle, regions: PopupHitRegions) {
        guard current == id else { return }
        let items = elements(in: id, regions: regions)
        let item = items.first { $0.accessibilityTraits.contains(.header) } ?? items.first
        UIAccessibility.post(notification: .layoutChanged, argument: item)
    }

    func elements(in id: PopupHandle, regions: PopupHitRegions) -> [NSObject] {
        guard let surface = regions.surfaces.object(forKey: id.id as NSUUID), let window = surface.window else { return [] }
        let frame = UIAccessibility.convertToScreenCoordinates(surface.bounds, in: surface)
        var visited = Set<ObjectIdentifier>()
        var matches: [NSObject] = []
        func visit(_ object: NSObject) {
            guard visited.count < 2048, visited.insert(ObjectIdentifier(object)).inserted,
                  !object.accessibilityElementsHidden else { return }
            if object.isAccessibilityElement {
                let rect = object.accessibilityFrame
                if !rect.isEmpty, frame.contains(CGPoint(x: rect.midX, y: rect.midY)) { matches.append(object) }
                return
            }
            if let children = object.accessibilityElements as? [NSObject] {
                children.forEach(visit)
            } else if let view = object as? UIView {
                view.subviews.filter { !$0.isHidden && $0.alpha > 0 }.forEach(visit)
            }
        }
        visit(window)
        return matches
    }
}
