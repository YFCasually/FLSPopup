import SwiftUI

@MainActor
private final class BindingSession: ObservableObject {
    private var handle: PopupHandle?
    private var identity: AnyHashable?
    private var replacement: (() -> Void)?

    func stop() {
        replacement = nil
        identity = nil
        if let handle { PopupCenter.shared.dismiss(handle) }
    }

    func start<ID: Hashable>(id: ID, target: PopupTarget, options: PopupOptions,
                             ended: @escaping () -> Void, @ViewBuilder content: @escaping () -> some View) {
        let nextIdentity = AnyHashable(PresentationIdentity(item: id, target: target))
        guard identity != nextIdentity else { return }
        identity = nextIdentity
        let present = { [self] in
            let next = PopupHandle()
            handle = next
            let finish = { [self] in
                guard handle == next else { return }
                handle = nil
                if let queued = replacement {
                    replacement = nil
                    queued()
                } else if identity == nextIdentity {
                    identity = nil
                    ended()
                }
            }
            let result = PopupCenter.shared.present(target: target, options: options, handle: next,
                                                    onEnd: { _ in finish() }, content: content)
            if case .rejected = result { finish() }
        }
        // Wait for exit before reusing the same business key or group lock.
        if let handle {
            replacement = present
            PopupCenter.shared.dismiss(handle)
        } else {
            present()
        }
    }
}

private struct PresentationIdentity<ID: Hashable>: Hashable {
    let item: ID?
    let target: PopupTarget
}

@MainActor
private struct ItemPresentation<Item: Identifiable, PopupContent: View>: ViewModifier {
    @Binding var item: Item?
    let target: PopupTarget
    let options: PopupOptions
    let builder: (Item) -> PopupContent
    @StateObject private var session = BindingSession()

    func body(content: Content) -> some View {
        content
            .task(id: PresentationIdentity(item: item?.id, target: target)) {
                // Give enclosing host modifiers their initial registration pass.
                await Task.yield()
                guard !Task.isCancelled else { return }
                guard let snapshot = item else { session.stop(); return }
                let source = $item
                session.start(id: snapshot.id, target: target, options: options, ended: {
                    if source.wrappedValue?.id == snapshot.id { source.wrappedValue = nil }
                }) {
                    BoundPopupContent(source: source, snapshot: snapshot, builder: builder)
                }
            }
    }
}

private struct BoundPopupContent<Item: Identifiable, Content: View>: View {
    @Binding var source: Item?
    let snapshot: Item
    let builder: (Item) -> Content

    var body: some View {
        if let current = source, current.id == snapshot.id {
            builder(current)
        } else {
            builder(snapshot)
        }
    }
}

private struct PresentationFlag: Identifiable {
    let id = true
}

public extension View {
    @MainActor
    func flsPopup<Item: Identifiable, Content: View>(
        item: Binding<Item?>, target: PopupTarget, options: PopupOptions = .init(),
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        modifier(ItemPresentation(item: item, target: target, options: options, builder: content))
    }

    @MainActor
    func flsPopup<Content: View>(
        isPresented: Binding<Bool>, target: PopupTarget, options: PopupOptions = .init(),
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        let flag = Binding<PresentationFlag?>(
            get: { isPresented.wrappedValue ? PresentationFlag() : nil },
            set: { isPresented.wrappedValue = $0 != nil }
        )
        return flsPopup(item: flag, target: target, options: options) { _ in content() }
    }
}

public extension EnvironmentValues {
    /// Submit and query requests from a scene-aware view. Target selection stays explicit.
    @MainActor var popupPresenter: PopupCenter { .shared }
}
