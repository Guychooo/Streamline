import SwiftUI
import StreamCore

struct AddonsView: View {
    @Environment(AppModel.self) private var model
    @State private var address = ""
    @State private var isInstalling = false
    @State private var errorMessage: String?
    @State private var installedName: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("https://example.com/manifest.json", text: $address)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .onSubmit(install)
                    HStack {
                        PasteButton(payloadType: String.self) { strings in
                            if let first = strings.first { address = first }
                        }
                        .labelStyle(.titleAndIcon)
                        .buttonBorderShape(.capsule)
                        Spacer()
                        Button(action: install) {
                            if isInstalling { ProgressView() } else { Text("Install") }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty || isInstalling)
                    }
                } header: {
                    Text("Add an Add-on")
                } footer: {
                    Text("Paste a manifest URL or a stremio:// install link. Streams play when they are direct HTTP or HLS links. Only install add-ons for content you have the right to watch.")
                }

                Section("Installed") {
                    ForEach(model.addons) { addon in
                        AddonRow(addon: addon)
                    }
                    .onDelete { model.removeAddons(at: $0) }
                    .onMove { model.moveAddons(from: $0, to: $1) }
                }

                if !model.removedBuiltIns.isEmpty {
                    Section("Built-in") {
                        ForEach(model.removedBuiltIns) { addon in
                            Button("Restore \(addon.manifest.name)") { model.restore(addon) }
                        }
                    }
                }
            }
            .navigationTitle("Add-ons")
            .toolbar { EditButton() }
            .alert("Couldn't Install Add-on", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .alert("Installed", isPresented: Binding(get: { installedName != nil }, set: { if !$0 { installedName = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("\(installedName ?? "The add-on") is ready.")
            }
        }
    }

    @MainActor
    private func install() {
        let input = address
        guard !input.trimmingCharacters(in: .whitespaces).isEmpty, !isInstalling else { return }
        isInstalling = true
        Task {
            defer { isInstalling = false }
            do {
                let addon = try await model.installAddon(from: input)
                address = ""
                installedName = addon.manifest.name
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct AddonRow: View {
    let addon: InstalledAddon

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RemoteImage(url: addon.manifest.logo, contentMode: .fit)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(addon.manifest.name).font(.headline)
                    Text("v\(addon.manifest.version)").font(.caption).foregroundStyle(.secondary)
                }
                if let description = addon.manifest.description {
                    Text(description).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                }
                Text(capabilities).font(.caption2).foregroundStyle(.tertiary)
                if addon.manifest.requiresConfiguration {
                    Text("This add-on must be configured on its website first. Install the configured URL instead.")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var capabilities: String {
        let resources = addon.manifest.resources.map(\.name)
        let types = addon.manifest.types.map(ContentTypeLabel.text(for:))
        return (resources + types).joined(separator: " · ")
    }
}
