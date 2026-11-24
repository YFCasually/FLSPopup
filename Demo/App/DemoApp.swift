import SwiftUI
import FLSPopup

@main
struct PopupDemoApp: App {
    var body: some Scene {
        WindowGroup(id: "workbench") {
            Workbench().popupSceneHost()
        }
    }
}

enum HostChoice: String, CaseIterable {
    case page = "Page"
    case window = "Window"

    func target(in scene: String) -> PopupTarget {
        switch self {
        case .page: return .page(scene: scene, id: "workbench")
        case .window: return .window(scene: scene)
        }
    }
}

@MainActor
final class Session: ObservableObject {
    @Published private(set) var events: [String] = []
    @Published private(set) var names: [PopupHandle: String] = [:]
    private var number = 0

    func submit<V: View>(_ title: String, to target: PopupTarget, options: PopupOptions,
                         @ViewBuilder content: (String) -> V) {
        number += 1
        let name = "\(title) \(number)"
        let handle = PopupHandle()
        let result = PopupCenter.shared.present(target: target, options: options, handle: handle, onEnd: { [weak self] reason in
            self?.names[handle] = nil
            self?.log("\(name) ended · \(reason)")
        }) {
            content(name)
        }
        switch result {
        case .accepted:
            names[handle] = name
            log("\(name) accepted")
        case .rejected(let reason):
            log("\(name) rejected · \(reason)")
        }
    }

    private func log(_ line: String) {
        events.insert(line, at: 0)
        events = Array(events.prefix(40))
    }

    func card(_ target: PopupTarget, mode: PopupMode, group: String = "workbench",
              title: String = "Request", identifier: String? = nil, priority: PopupPriority = .medium) {
        var options = PopupOptions(style: .card, mode: mode, group: group, identifier: identifier)
        options.priority = priority
        submit(title, to: target, options: options) { name in
            RequestCard(name: name, session: self, target: target, group: group, identifier: identifier)
        }
    }

    func draft(_ target: PopupTarget) {
        var options = PopupOptions(style: .panel, group: "draft")
        options.requiresKeyboard = true
        submit("Draft", to: target, options: options) { _ in
            DraftPanel(session: self, scene: target.sceneID)
        }
    }

    func toast(_ target: PopupTarget) {
        var options = PopupOptions(style: .toast, group: "saves")
        options.duration = 3
        options.background = .passThrough
        submit("Save", to: target, options: options) { _ in
            Label("Draft saved", systemImage: "checkmark.circle.fill")
                .accessibilityIdentifier("savedBanner")
        }
    }
}
