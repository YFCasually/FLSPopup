import SwiftUI
import FLSPopup

struct InteractionLab: View {
    let session: Session
    let scene: String
    @State private var host = HostChoice.page
    @State private var background = PopupBackground.passThrough
    @State private var taps = 0
    @State private var inside = 0
    @State private var useAppearance = false
    @State private var notice = false
    @State private var item: Sample?
    @State private var nextItem = 0

    private struct Sample: Identifiable { let id: Int }

    private var target: PopupTarget {
        host == .page ? .page(scene: scene, id: "interaction") : .window(scene: scene)
    }

    var body: some View {
        Form {
            Picker("Host", selection: $host) {
                ForEach(HostChoice.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            Picker("Background", selection: $background) {
                ForEach(PopupBackground.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            Toggle("Request dark, portrait appearance", isOn: $useAppearance)
            Button("Show touch sample") {
                var options = PopupOptions(style: .toast, group: "interaction")
                options.duration = nil
                options.background = background
                options.transition = .opacity
                if useAppearance {
                    options.colorScheme = .dark
                    options.statusBarStyle = .lightContent
                    options.orientations = .portrait
                    options.autorotates = false
                }
                session.submit("Touch sample", to: target, options: options) { _ in
                    TouchSample(inside: $inside)
                }
            }
            Button("Background taps: \(taps)") { taps += 1 }
                .accessibilityIdentifier("backgroundCounter")
            Section("Bindings") {
                Button("Present Bool binding") { notice = true }
                Button("Present item binding") { nextItem += 1; item = Sample(id: nextItem) }
            }
            Section("Unavailable host") {
                Button("Request a missing page") {
                    session.card(.page(scene: scene, id: "unregistered"), mode: .queue)
                }
                if let latest = session.events.first { Text(latest).font(.footnote) }
            }
        }
        .flsPopup(isPresented: $notice, target: target) {
            BindingCard(title: "Bound notice", change: nil)
        }
        .flsPopup(item: $item, target: target) { sample in
            BindingCard(title: "Item \(sample.id)") {
                nextItem += 1
                item = Sample(id: nextItem)
            }
        }
        .navigationTitle("Interaction lab")
    }
}

private struct BindingCard: View {
    let title: String
    let change: (() -> Void)?
    @Environment(\.dismissPopup) private var dismiss

    var body: some View {
        VStack(spacing: 12) {
            Text(title).font(.headline)
            if let change { Button("Switch item", action: change) }
            Button("Close", action: dismiss)
        }
        .buttonStyle(.bordered)
        .padding()
    }
}

private struct TouchSample: View {
    @Binding var inside: Int
    @Environment(\.dismissPopup) private var dismiss

    var body: some View {
        HStack {
            Button("Content taps: \(inside)") { inside += 1 }
            Button("Close", action: dismiss)
        }
        .buttonStyle(.bordered)
    }
}
