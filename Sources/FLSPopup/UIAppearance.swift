import UIKit

/// Preferences that the current scene or presenting controller could not apply in full.
public enum PopupAppearanceLimitation: Hashable {
    case statusBarStyle, statusBarHidden, orientations, autorotates
}

public extension PopupCenter {
    /// Evaluates the active presentation against its actual scene and status bar.
    func appearanceLimitations(for handle: PopupHandle) -> Set<PopupAppearanceLimitation> {
        guard let record = records.first(where: { $0.id == handle && $0.phase.occupiesHost }),
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.session.persistentIdentifier == record.target.sceneID }) else { return [] }
        var result = Set<PopupAppearanceLimitation>()
        let options = record.options
        let manager = scene.statusBarManager
        if let style = options.statusBarStyle, manager?.statusBarStyle != style { result.insert(.statusBarStyle) }
        if let hidden = options.statusBarHidden, manager?.isStatusBarHidden != hidden { result.insert(.statusBarHidden) }
        let allowed = UIApplication.shared.supportedInterfaceOrientations(for: scene.keyWindow)
            .intersection(scene.keyWindow?.popupPresentedController?.supportedInterfaceOrientations ?? .all)
        let current = scene.popupOrientation
        let managed = scene.keyWindow is PopupWindow && records.last(where: {
            $0.target == .window(scene: record.target.sceneID) && $0.phase.occupiesHost
        })?.id == handle
        if let mask = options.orientations {
            if mask.isEmpty || current.isEmpty || !mask.contains(current) || mask.intersection(allowed) != mask ||
                (!managed && !allowed.subtracting(mask).isEmpty) { result.insert(.orientations) }
        }
        if let rotates = options.autorotates {
            var locked = !current.isEmpty && allowed == current
            #if compiler(>=6.2)
            if #available(iOS 26, *) { locked = locked || scene.effectiveGeometry.isInterfaceOrientationLocked }
            #endif
            if rotates == locked { result.insert(.autorotates) }
        }
        return result
    }
}

extension UIWindowScene {
    var popupOrientation: UIInterfaceOrientationMask {
        let orientation: UIInterfaceOrientation
        #if compiler(>=6.2)
        if #available(iOS 26, *) { orientation = effectiveGeometry.interfaceOrientation }
        else { orientation = interfaceOrientation }
        #else
        orientation = interfaceOrientation
        #endif
        switch orientation {
        case .portrait: return .portrait
        case .portraitUpsideDown: return .portraitUpsideDown
        case .landscapeLeft: return .landscapeLeft
        case .landscapeRight: return .landscapeRight
        default: return []
        }
    }
}

/// Only restore rotations that this host requested and the scene actually adopted.
@MainActor
final class PopupGeometry {
    private var owner: PopupHandle?
    private var original: UIInterfaceOrientationMask?
    private var requested: UIInterfaceOrientationMask?

    func apply(_ record: PopupRecord?, scene: UIWindowScene, source: UIWindow?) {
        let next = record.flatMap { $0.options.orientations != nil || $0.options.autorotates == false ? $0 : nil }
        guard owner != next?.id else { return }
        owner = next?.id
        let current = scene.popupOrientation
        let supported = UIApplication.shared.supportedInterfaceOrientations(for: source)
            .intersection(source?.popupPresentedController?.supportedInterfaceOrientations ?? .all)
        guard let next else {
            if let original, let requested, !current.isEmpty, requested.contains(current),
               !original.contains(current), supported.contains(original) {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: original)) { _ in }
            }
            original = nil
            requested = nil
            return
        }
        var mask = supported.intersection(next.options.orientations ?? supported)
        if next.options.autorotates == false, mask.contains(current), !current.isEmpty { mask = current }
        guard !mask.isEmpty, !mask.contains(current), !current.isEmpty else { return }
        if original == nil { original = current }
        requested = mask
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in
            // appearanceLimitations(for:) reads the actual geometry after a refusal.
        }
    }
}
