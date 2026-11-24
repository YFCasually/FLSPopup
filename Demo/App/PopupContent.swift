import SwiftUI
import FLSPopup

struct RequestCard: View {
    let name: String
    @ObservedObject var session: Session
    let target: PopupTarget
    let group: String
    let identifier: String?
    @Environment(\.dismissPopup) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(name).font(.title2.bold()).accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("requestTitle")
            Text(group).font(.subheadline).foregroundStyle(.secondary)
            Menu("Submit another request") {
                ForEach(PopupMode.allCases, id: \.self) { next in
                    Button(next.rawValue) { session.card(target, mode: next, group: group) }
                }
                if let identifier {
                    Button("Repeat business key on other host") {
                        let other: PopupTarget
                        switch target {
                        case .page: other = .window(scene: target.sceneID)
                        case .window: other = .page(scene: target.sceneID, id: "workbench")
                        }
                        session.card(other, mode: .queue, group: "repeat", identifier: identifier)
                    }
                }
                Button("Queue high priority") {
                    session.card(target, mode: .queue, group: group, title: "Urgent", priority: .high)
                }
                Button("Interrupt another group") {
                    session.card(target, mode: .interrupt, group: group == "secondary" ? "workbench" : "secondary")
                }
            }
            .accessibilityIdentifier("followUp")
            .frame(minHeight: 44)
            if let latest = session.events.first {
                Text(latest).font(.footnote).accessibilityIdentifier("latestEvent")
            }
            Button("Finish request", action: dismiss)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("finishRequest")
        }
        .padding()
    }
}

struct DraftPanel: View {
    let session: Session
    let scene: String
    @Environment(\.dismissPopup) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Edit draft").font(.headline).accessibilityAddTraits(.isHeader)
            TextField("Draft title", text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .submitLabel(.done)
                .onSubmit { focused = false }
                .accessibilityIdentifier("draftText")
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(1...24, id: \.self) { Text("Revision \($0)") }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier("draftHistory")
            .frame(maxHeight: 100)
            Button("Review in window") {
                focused = false
                session.card(.window(scene: scene), mode: .suspend, group: "draft", title: "Review")
            }
            .accessibilityIdentifier("suspendDraft")
            Button("Finish editing", action: dismiss)
                .accessibilityIdentifier("finishDraft")
        }
        .buttonStyle(.bordered)
        .padding()
    }
}

struct SheetEditor: View {
    let session: Session
    let scene: String
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Draft") {
                    TextField("Sheet title", text: $text)
                        .accessibilityIdentifier("sheetText")
                    Button("Save and show window notification") {
                        session.toast(.window(scene: scene))
                    }
                    .accessibilityIdentifier("sheetSave")
                }
                Section("Present from this sheet") {
                    Button("Card on sheet") {
                        session.card(.page(scene: scene, id: "sheet"), mode: .queue, title: "Sheet card")
                    }
                    .accessibilityIdentifier("sheetCard")
                    Button("Card on underlying page") {
                        session.card(.page(scene: scene, id: "workbench"), mode: .queue, title: "Page card")
                    }
                    .accessibilityIdentifier("underlyingCard")
                    Button("Window input panel") { session.draft(.window(scene: scene)) }
                }
            }
            .navigationTitle("Sheet editor")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("closeSheet")
                }
            }
        }
    }
}
