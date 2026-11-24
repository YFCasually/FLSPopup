import SwiftUI
import UIKit

extension PopupOptions {
    var blocksBackground: Bool { background == .block || background == .dismiss }
    var allowsEscape: Bool { background == .dismiss || background == .passThroughAndDismiss || dragToDismiss }
}

extension PopupPhase {
    var occupiesHost: Bool { self == .entering || self == .visible || self == .exiting }
}

/// Mounted rectangles are measured in UIKit coordinates, including safe-area and keyboard changes.
@MainActor
final class PopupHitRegions {
    let surfaces = NSMapTable<NSUUID, UIView>.strongToWeakObjects()
    weak var boundsView: UIView?
    var target: PopupTarget?

    var layers: [PopupRecord] {
        PopupCenter.shared.records.filter { $0.target == target && $0.phase.occupiesHost }
    }

    func route(_ point: CGPoint, from window: UIWindow) -> (hit: PopupRecord?, inside: Bool, dismiss: [PopupHandle]) {
        var dismiss: [PopupHandle] = []
        for layer in layers.reversed() {
            if let view = surfaces.object(forKey: layer.id.id as NSUUID), view.window != nil,
               view.bounds.contains(view.convert(point, from: window)) {
                return (layer, true, dismiss)
            }
            if layer.options.blocksBackground { return (layer, false, dismiss) }
            if layer.options.background == .passThroughAndDismiss { dismiss.append(layer.id) }
        }
        return (nil, false, dismiss)
    }
}

struct PopupMarker: UIViewRepresentable {
    var attach: (UIView) -> Void
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
        attach(view)
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) { attach(uiView) }
}

extension UIView {
    var popupController: UIViewController? {
        var node: UIResponder? = self
        while let current = node {
            if let controller = current as? UIViewController { return controller }
            node = current.next
        }
        return nil
    }

    var popupFirstResponder: UIView? {
        subviews.lazy.compactMap { $0.popupFirstResponder }.first ?? (isFirstResponder ? self : nil)
    }
}

extension UIWindow {
    var popupPresentedController: UIViewController? {
        var controller = rootViewController
        while let presented = controller?.presentedViewController, !presented.isBeingDismissed {
            controller = presented
        }
        return controller
    }

    var popupFocusedSubview: UIView? {
        guard let responder = popupFirstResponder, responder !== self else { return nil }
        return responder
    }
}

// Listening on the receiving window lets the original touch reach its SwiftUI or UIKit
// control even when a separate overlay window returned nil from hitTest.
@MainActor
final class PopupTouchObserver: NSObject, UIGestureRecognizerDelegate {
    let regions: PopupHitRegions
    weak var window: UIWindow?
    private var outside: [PopupHandle] = []
    private var dragging: PopupHandle?
    private let tap = PassiveTap()
    private let pan = PassivePan()

    init(window: UIWindow, regions: PopupHitRegions) {
        self.window = window
        self.regions = regions
        super.init()
        tap.addTarget(self, action: #selector(tapped))
        pan.addTarget(self, action: #selector(panned))
        pan.maximumNumberOfTouches = 1
        for gesture in [tap as UIGestureRecognizer, pan] {
            gesture.delegate = self
            gesture.cancelsTouchesInView = false
            gesture.delaysTouchesBegan = false
            gesture.delaysTouchesEnded = false
            window.addGestureRecognizer(gesture)
        }
    }

    func detach() {
        window?.removeGestureRecognizer(tap)
        window?.removeGestureRecognizer(pan)
    }

    func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let window, let bounds = regions.boundsView, let host = bounds.window else { return false }
        let point = touch.location(in: window)
        if case .page = regions.target {
            guard window === host, bounds.bounds.contains(bounds.convert(point, from: window)) else { return false }
            // A presented sheet in the same window owns its own touches.
            var controller = bounds.popupController
            while let owner = controller {
                if let sheet = owner.presentedViewController, !sheet.isBeingDismissed,
                   let hit = touch.view, hit.isDescendant(of: sheet.view) { return false }
                controller = owner.parent
            }
        }
        let route = regions.route(point, from: window)
        if gesture === tap {
            outside = route.dismiss
            return !outside.isEmpty
        }
        guard window === host, route.inside, let layer = route.hit,
              layer.phase != .exiting, layer.options.dragToDismiss else { return false }
        var node = touch.view
        while let view = node {
            if let scroll = view as? UIScrollView, scroll.contentOffset.y > -scroll.adjustedContentInset.top + 1 {
                return false
            }
            node = view.superview
        }
        dragging = layer.id
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }

    @objc private func tapped() {
        for id in outside where regions.layers.contains(where: { $0.id == id && $0.phase != .exiting }) {
            PopupCenter.shared.dismiss(id, reason: .background)
        }
        outside = []
    }

    @objc private func panned() {
        guard pan.state == .ended, let dragging else { return }
        let delta = pan.translation(in: window)
        if delta.y >= 60, delta.y > abs(delta.x), regions.layers.contains(where: { $0.id == dragging }) {
            PopupCenter.shared.dismiss(dragging, reason: .drag)
        }
        self.dragging = nil
    }

    private final class PassiveTap: UITapGestureRecognizer {
        override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    }
    private final class PassivePan: UIPanGestureRecognizer {
        override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    }
}
