import SwiftUI
import UIKit

private enum PopupSceneKey: EnvironmentKey {
    static let defaultValue: String? = nil
}
private enum DismissPopupKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

public extension EnvironmentValues {
    var popupSceneID: String? {
        get { self[PopupSceneKey.self] }
        set { self[PopupSceneKey.self] = newValue }
    }

    var dismissPopup: () -> Void {
        get { self[DismissPopupKey.self] }
        set { self[DismissPopupKey.self] = newValue }
    }
}

public extension View {
    @MainActor func popupSceneHost() -> some View { modifier(PopupSceneHost()) }

    @MainActor func popupHost(id: String, isActive: Bool = true) -> some View {
        modifier(PopupPageHost(id: id, active: isActive))
    }
}

@MainActor
private struct PopupSceneHost: ViewModifier {
    @StateObject private var host = PopupWindowHost()
    @Environment(\.self) private var environment
    @ObservedObject private var center = PopupCenter.shared

    func body(content: Content) -> some View {
        let target = host.sceneID.map { PopupTarget.window(scene: $0) }
        let modal = center.records.last { $0.target == target && $0.phase.occupiesHost && $0.options.blocksBackground }
        content
            .accessibilityHidden(modal != nil)
            .background {
                if let record = center.records.last(where: { $0.target == target && $0.phase.occupiesHost }),
                   record.options.allowsEscape {
                    PopupEscapeShortcut(handle: record.id)
                }
            }
            .environment(\.popupSceneID, host.sceneID)
            .background(WindowProbe(
                update: { host.environment = environment },
                attach: { host.attach($0) },
                remove: { host.detach() }
            ))
    }
}

struct PopupEscapeShortcut: View {
    let handle: PopupHandle
    var body: some View {
        Button("Dismiss") { PopupCenter.shared.dismiss(handle, reason: .cancelled) }
            .keyboardShortcut(.cancelAction)
            .frame(width: 0, height: 0)
            .clipped()
            .accessibilityHidden(true)
    }
}

@MainActor
private struct PopupPageHost: ViewModifier {
    let id: String
    let active: Bool
    @StateObject private var host = PopupPageRegistration()
    @ObservedObject private var center = PopupCenter.shared
    @Environment(\.popupSceneID) private var inheritedScene

    func body(content: Content) -> some View {
        let scene = host.sceneID ?? inheritedScene
        let target = scene.map { PopupTarget.page(scene: $0, id: id) }
        let layers = center.records.filter { $0.target == target && $0.phase.occupiesHost }
        let isModal = active && layers.contains { $0.options.blocksBackground }
        content
            .accessibilityHidden(isModal)
            .overlay {
                if active, let target {
                    PopupStack(target: target, regions: host.regions)
                        .background {
                            if let record = layers.last, record.options.allowsEscape {
                                PopupEscapeShortcut(handle: record.id)
                            }
                        }
                }
            }
            .environment(\.popupSceneID, scene)
            .background(WindowProbe(
                update: { host.configure(id: id, active: active) },
                attach: { host.attach($0) },
                remove: { host.detach() }
            ))
    }
}

// UIKit can temporarily detach a page while a covering presentation is onscreen.
// Only dismantling the representable (or explicitly deactivating it) removes the host.
private struct WindowProbe: UIViewRepresentable {
    var update: () -> Void
    var attach: (UIWindow) -> Void
    var remove: () -> Void

    final class Probe: UIView {
        var attach: ((UIWindow) -> Void)?
        var remove: (() -> Void)?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let window { attach?(window) }
        }
    }

    func makeUIView(context: Context) -> Probe {
        let probe = Probe()
        probe.isUserInteractionEnabled = false
        probe.accessibilityElementsHidden = true
        return probe
    }
    func updateUIView(_ probe: Probe, context: Context) {
        probe.attach = attach
        probe.remove = remove
        update()
        if let window = probe.window { attach(window) }
    }
    static func dismantleUIView(_ probe: Probe, coordinator: ()) {
        probe.attach = nil
        probe.remove?()
        probe.remove = nil
    }
}

@MainActor
private final class PopupPageRegistration: ObservableObject {
    let regions = PopupHitRegions()
    @Published private(set) var sceneID: String?
    private weak var window: UIWindow?
    private var observer: PopupTouchObserver?
    private var id = ""
    private var active = false

    func configure(id: String, active: Bool) {
        self.id = id
        self.active = active
        register()
    }

    func attach(_ window: UIWindow) {
        if self.window !== window {
            observer?.detach()
            self.window = window
            observer = PopupTouchObserver(window: window, regions: regions)
        }
        register()
        let scene = window.windowScene?.session.persistentIdentifier
        if sceneID != scene {
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, self.window === window, self.sceneID != scene else { return }
                self.sceneID = scene
            }
        }
    }

    private func register() {
        let target = active ? window?.windowScene.map { PopupTarget.page(scene: $0.session.persistentIdentifier, id: id) } : nil
        guard regions.target != target else { return }
        if let old = regions.target { PopupCenter.shared.unregister(old) }
        regions.target = target
        if let target { PopupCenter.shared.register(target) }
    }

    func detach() {
        observer?.detach()
        observer = nil
        window = nil
        register()
    }
}
