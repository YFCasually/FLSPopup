import SwiftUI
import UIKit

public enum PopupTarget: Hashable {
    case page(scene: String, id: String)
    case window(scene: String)

    public var sceneID: String {
        switch self {
        case let .page(scene, _), let .window(scene): return scene
        }
    }
}

public enum PopupMode: String, CaseIterable {
    case queue, interrupt, suspend, replaceInheritSuspend, replaceClearSuspend
    case replaceAll, groupUnique, globalUnique
}

public enum PopupStyle: String, CaseIterable { case toast, card, panel }
public enum PopupScope: Hashable { case scene, application }
public enum PopupBackground: String, CaseIterable { case block, dismiss, passThrough, passThroughAndDismiss }
public enum PopupPhase: String, Hashable { case waiting, entering, visible, suspended, exiting }
public enum PopupEndReason: String { case action, background, drag, timeout, cancelled, replaced, hostRemoved }
public enum PopupRejection: String, Error { case duplicate, groupLocked, globalLocked, hostUnavailable, sceneUnavailable }

public struct PopupHandle: Hashable, Identifiable {
    public let id: UUID
    public init(id: UUID = UUID()) { self.id = id }
}

public enum PopupResult: Equatable {
    case accepted(PopupHandle)
    case rejected(PopupRejection)
}

public struct PopupPriority: RawRepresentable, Hashable, Comparable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let low = Self(rawValue: 0)
    public static let mediumLow = Self(rawValue: 250)
    public static let medium = Self(rawValue: 500)
    public static let mediumHigh = Self(rawValue: 750)
    public static let high = Self(rawValue: 1000)
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

public struct PopupOptions {
    public var style: PopupStyle
    public var mode: PopupMode
    public var group: String
    public var identifier: String?
    public var priority: PopupPriority = .medium
    public var scope: PopupScope = .scene
    public var deduplicationScope: PopupScope = .scene
    public var background: PopupBackground
    public var backdropColor: Color = .black
    public var backdropOpacity: Double = 0.33
    public var duration: TimeInterval?
    /// Called once after the initial entrance finishes, including after a deferred entrance.
    public var onFirstDisplay: ((PopupHandle) -> Void)?
    public var requiresKeyboard = false
    public var alignment: Alignment
    public var transition: AnyTransition
    public var animation: Animation? = .easeInOut(duration: 0.22)
    public var margin: CGFloat = 16
    public var colorScheme: ColorScheme?
    public var statusBarStyle: UIStatusBarStyle?
    public var statusBarHidden: Bool?
    public var orientations: UIInterfaceOrientationMask?
    public var autorotates: Bool?
    public var dragToDismiss: Bool

    public init(style: PopupStyle = .card, mode: PopupMode = .queue,
                group: String = "default", identifier: String? = nil) {
        self.style = style
        self.mode = mode
        self.group = group
        self.identifier = identifier
        background = style == .toast ? .passThrough : .block
        duration = style == .toast ? 3 : nil
        dragToDismiss = style == .panel
        switch style {
        case .toast:
            alignment = .top
            transition = .move(edge: .top).combined(with: .opacity)
        case .card:
            alignment = .center
            transition = .scale(scale: 0.96).combined(with: .opacity)
        case .panel:
            alignment = .bottom
            transition = .move(edge: .bottom)
        }
    }
}
