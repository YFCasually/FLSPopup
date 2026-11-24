import SwiftUI
import UIKit
import Combine

@MainActor
private final class PopupWindow: UIWindow {
    let regions: PopupHitRegions
    var acceptsKeyboard = false
    override var canBecomeKey: Bool { acceptsKeyboard }

    init(scene: UIWindowScene, regions: PopupHitRegions) {
        self.regions = regions
        super.init(windowScene: scene)
        backgroundColor = .clear
        windowLevel = UIWindow.Level(rawValue: UIWindow.Level.normal.rawValue + 1)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard regions.route(point, from: self).hit != nil else { return nil }
        return super.hitTest(point, with: event)
    }
}

@MainActor
private final class PopupController: UIHostingController<AnyView> {
    weak var base: UIViewController?
    var appearance: PopupOptions? {
        didSet {
            setNeedsStatusBarAppearanceUpdate()
            setNeedsUpdateOfSupportedInterfaceOrientations()
        }
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        appearance?.statusBarStyle ?? base?.preferredStatusBarStyle ?? super.preferredStatusBarStyle
    }
    override var prefersStatusBarHidden: Bool {
        appearance?.statusBarHidden ?? base?.prefersStatusBarHidden ?? super.prefersStatusBarHidden
    }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        let supported = base?.supportedInterfaceOrientations ?? super.supportedInterfaceOrientations
        let requested = supported.intersection(appearance?.orientations ?? supported)
        return requested.isEmpty ? supported : requested
    }
    override var shouldAutorotate: Bool {
        appearance?.autorotates ?? base?.shouldAutorotate ?? super.shouldAutorotate
    }
    override var keyCommands: [UIKeyCommand]? {
        guard let window = viewIfLoaded?.window as? PopupWindow,
              window.regions.layers.last?.options.allowsEscape == true else { return super.keyCommands }
        let command = UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(cancelPopup))
        return [command] + (super.keyCommands ?? [])
    }
    @objc private func cancelPopup() {
        if let record = (view.window as? PopupWindow)?.regions.layers.last, record.options.allowsEscape {
            PopupCenter.shared.dismiss(record.id, reason: .cancelled)
        }
    }
}

@MainActor
final class PopupWindowHost: NSObject, ObservableObject {
    @Published private(set) var sceneID: String?
    private let regions = PopupHitRegions()
    private weak var scene: UIWindowScene?
    private weak var source: UIWindow?
    private var overlay: PopupWindow?
    private var controller: PopupController?
    private var subscription: AnyCancellable?
    private var observers: [PopupTouchObserver] = []
    private weak var priorKey: UIWindow?
    private weak var priorResponder: UIView?
    private var inputOwner: PopupHandle?
    private let responders = NSMapTable<NSUUID, UIView>.strongToWeakObjects()
    var environment = EnvironmentValues() {
        didSet { if let controller { controller.rootView = root() } }
    }

    func attach(_ window: UIWindow) {
        guard let next = window.windowScene, next.activationState != .unattached else { return }
        source = window
        guard scene !== next else { return }
        detach()
        source = window
        scene = next
        let id = next.session.persistentIdentifier
        let target = PopupTarget.window(scene: id)
        regions.target = target
        PopupCenter.shared.register(target)
        PopupCenter.shared.setSceneActive(next.activationState == .foregroundActive, scene: id)
        DispatchQueue.main.async { [weak self, weak next] in
            guard let self, self.scene === next, self.sceneID != id else { return }
            self.sceneID = id
        }
        let notifications = NotificationCenter.default
        notifications.addObserver(self, selector: #selector(active), name: UIScene.didActivateNotification, object: next)
        notifications.addObserver(self, selector: #selector(inactive), name: UIScene.willDeactivateNotification, object: next)
        notifications.addObserver(self, selector: #selector(disconnected), name: UIScene.didDisconnectNotification, object: next)
        notifications.addObserver(self, selector: #selector(windowShown(_:)), name: UIWindow.didBecomeVisibleNotification, object: nil)
        subscription = PopupCenter.shared.$records.receive(on: DispatchQueue.main).sink { [weak self] _ in
            self?.refresh()
        }
    }

    func detach() {
        subscription = nil
        NotificationCenter.default.removeObserver(self)
        let old = scene?.session.persistentIdentifier
        releaseWindow()
        scene = nil
        source = nil
        regions.target = nil
        if let old {
            PopupCenter.shared.disconnect(scene: old)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.scene == nil else { return }
                self.sceneID = nil
            }
        }
    }

    @objc private func active() {
        if let scene { PopupCenter.shared.setSceneActive(true, scene: scene.session.persistentIdentifier) }
    }
    @objc private func inactive() {
        if let scene { PopupCenter.shared.setSceneActive(false, scene: scene.session.persistentIdentifier) }
    }
    @objc private func disconnected() { detach() }
    @objc private func windowShown(_ note: Notification) {
        guard overlay != nil, let window = note.object as? UIWindow, window.windowScene === scene else { return }
        observe(window)
    }
    private func observe(_ window: UIWindow) {
        guard !observers.contains(where: { $0.window === window }) else { return }
        observers.removeAll { $0.window == nil }
        observers.append(PopupTouchObserver(window: window, regions: regions))
    }

    private func root() -> AnyView {
        guard let target = regions.target else { return AnyView(EmptyView()) }
        return AnyView(PopupStack(target: target, regions: regions)
            .environment(\.popupSceneID, target.sceneID)
            .environment(\.self, environment))
    }

    private func refresh() {
        guard let scene, let target = regions.target else { return }
        let mounted = PopupCenter.shared.records.filter { $0.target == target && $0.phase != .waiting }
        guard !mounted.isEmpty else { releaseWindow(); return }
        if overlay == nil {
            let window = PopupWindow(scene: scene, regions: regions)
            let rootController = PopupController(rootView: root())
            rootController.view.backgroundColor = .clear
            window.rootViewController = rootController
            controller = rootController
            overlay = window
            window.isHidden = false
            scene.windows.forEach(observe)
        }
        var base = source?.rootViewController
        while let presented = base?.presentedViewController { base = presented }
        controller?.base = base
        let layers = mounted.filter { $0.phase.occupiesHost }
        controller?.appearance = layers.last?.options
        // A blocking non-input popup covers any input layer below it. A passive
        // toast over a form leaves the form's current responder alone.
        let owner = layers.reversed().first { $0.options.requiresKeyboard || $0.options.blocksBackground }
        setInputOwner(owner?.options.requiresKeyboard == true ? owner?.id : nil)
    }

    private func setInputOwner(_ next: PopupHandle?) {
        guard let overlay, let scene, inputOwner != next else { return }
        if let old = inputOwner, let field = overlay.popupFirstResponder, !(field is UIWindow) {
            responders.setObject(field, forKey: old.id as NSUUID)
            field.resignFirstResponder()
        }
        let first = inputOwner == nil
        inputOwner = next
        if let next {
            if first {
                priorKey = scene.windows.first(where: { $0.isKeyWindow && $0 !== overlay })
                priorResponder = priorKey?.popupFirstResponder
                overlay.acceptsKeyboard = true
                overlay.makeKey()
            }
            if overlay.isKeyWindow, let field = responders.object(forKey: next.id as NSUUID), field.window === overlay {
                field.becomeFirstResponder()
            }
        } else {
            if overlay.isKeyWindow {
                if let priorKey, priorKey.windowScene === scene, !priorKey.isHidden {
                    priorKey.makeKey()
                    if let field = priorResponder, field.window === priorKey, priorKey.popupFirstResponder == nil {
                        field.becomeFirstResponder()
                    }
                } else { overlay.resignKey() }
            }
            overlay.acceptsKeyboard = false
            priorKey = nil
            priorResponder = nil
        }
    }

    private func releaseWindow() {
        setInputOwner(nil)
        observers.forEach { $0.detach() }
        observers.removeAll()
        overlay?.isHidden = true
        overlay?.rootViewController = nil
        overlay = nil
        controller = nil
        responders.removeAllObjects()
        regions.surfaces.removeAllObjects()
    }
}
