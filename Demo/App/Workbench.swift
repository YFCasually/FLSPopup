import SwiftUI
import FLSPopup

struct Workbench: View {
    @Environment(\.popupSceneID) private var scene
    @Environment(\.openWindow) private var openWindow
    @Environment(\.supportsMultipleWindows) private var multipleWindows
    @StateObject private var session = Session()
    @ObservedObject private var center = PopupCenter.shared
    @State private var host = HostChoice.page
    @State private var mode = PopupMode.queue
    @State private var sheet = false
    @State private var lab = false
    @State private var editor = false
    @State private var otherGroup = false
    @State private var useKey = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Presentation") {
                    Picker("Host", selection: $host) {
                        ForEach(HostChoice.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Picker("Mode", selection: $mode) {
                        ForEach(PopupMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .accessibilityIdentifier("modePicker")
                    Toggle("Use a second group", isOn: $otherGroup)
                    Toggle("Use the same business key", isOn: $useKey)
                    Button("Present request") {
                        if let scene {
                            session.card(host.target(in: scene), mode: mode,
                                         group: otherGroup ? "secondary" : "workbench",
                                         identifier: useKey ? "shared" : nil)
                        }
                    }
                    .accessibilityIdentifier("presentRequest")
                }
                Section("Try a workflow") {
                    Button("Edit a draft") {
                        if let scene { session.draft(host.target(in: scene)) }
                    }
                    .accessibilityIdentifier("openDraft")
                    Button("Open system sheet") { sheet = true }
                        .accessibilityIdentifier("openSheet")
                    Button("Navigate to editor") { editor = true }
                    Button("Open interaction lab") { lab = true }
                    if multipleWindows {
                        Button("Open another scene") { openWindow(id: "workbench") }
                    }
                }
                .disabled(scene == nil)
                if let scene {
                    Section("Requests in this scene") {
                        let records = center.records.filter { $0.target.sceneID == scene }
                        if records.isEmpty { Text("No requests").foregroundStyle(.secondary) }
                        ForEach(records) { record in
                            Button {
                                center.dismiss(record.id)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(session.names[record.id] ?? record.options.group)
                                        Text(String(describing: record.phase)).font(.caption)
                                    }
                                    Spacer()
                                    Image(systemName: "xmark.circle")
                                }
                            }
                            .accessibilityHint("Cancels this request")
                        }
                    }
                }
                if !session.events.isEmpty {
                    Section("Recent events") {
                        ForEach(Array(session.events.enumerated()), id: \.offset) { event in
                            Text(event.element).font(.footnote)
                        }
                    }
                }
            }
            .navigationTitle("Popup workbench")
            .disabled(scene == nil)
            .popupHost(id: "workbench", isActive: !editor && !lab)
            .navigationDestination(isPresented: $lab) {
                if let scene {
                    InteractionLab(session: session, scene: scene)
                        .popupHost(id: "interaction")
                }
            }
            .navigationDestination(isPresented: $editor) {
                if let scene {
                    EditorPage(session: session, scene: scene)
                        .popupHost(id: "editor")
                        .navigationTitle("Editor")
                }
            }
            .sheet(isPresented: $sheet) {
                if let scene {
                    SheetEditor(session: session, scene: scene)
                        .popupHost(id: "sheet")
                }
            }
        }
    }
}

private struct EditorPage: View {
    let session: Session
    let scene: String

    var body: some View {
        Form {
            Button("Open page draft") { session.draft(.page(scene: scene, id: "editor")) }
            Button("Show window notification") { session.toast(.window(scene: scene)) }
        }
    }
}
