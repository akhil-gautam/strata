import AppKit
import SwiftUI

/// Searchable list of installed apps and standard folders.
@MainActor
@Observable
final class PickerModel {
    var query = ""
    private(set) var applications: [AppDescriptor] = []
    private(set) var folders: [AppDescriptor] = []

    private let iconProvider = IconProvider()

    func load() async {
        folders = AppCatalog.standardFolders()
        if AppCatalogStore.shared.apps.isEmpty {
            applications = await Task.detached(priority: .userInitiated) { AppCatalog.scan() }.value
            AppCatalogStore.shared.update(applications)
        } else {
            applications = AppCatalogStore.shared.apps
        }
    }

    var results: [AppDescriptor] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return applications }
        return applications.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed)
                || $0.url.path.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var folderResults: [AppDescriptor] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return folders }
        return folders.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    func icon(for descriptor: AppDescriptor) -> NSImage {
        iconProvider.icon(for: descriptor)
    }
}

struct AppPickerView: View {
    @Bindable var model: PickerModel
    let onSelect: (AppDescriptor) -> Void
    let onAddFolder: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search applications", text: $model.query)
                .textFieldStyle(.roundedBorder)
                .padding(12)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if !model.folderResults.isEmpty {
                        SectionHeader(title: "Folders")
                        ForEach(model.folderResults) { descriptor in
                            row(for: descriptor)
                        }
                    }

                    SectionHeader(title: "Applications")
                    ForEach(model.results) { descriptor in
                        row(for: descriptor)
                    }
                }
                .padding(.vertical, 6)
            }

            Divider()

            HStack {
                Button("Add Folder…", action: onAddFolder)
                Spacer()
            }
            .padding(12)
        }
        .frame(width: 420, height: 520)
    }

    private func row(for descriptor: AppDescriptor) -> some View {
        Button {
            onSelect(descriptor)
        } label: {
            HStack(spacing: 10) {
                Image(nsImage: model.icon(for: descriptor))
                    .resizable()
                    .frame(width: 22, height: 22)
                Text(descriptor.name)
                    .lineLimit(1)
                Spacer()
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

private struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }
}

@MainActor
final class AppPickerController {
    private var window: NSWindow?
    private let model = PickerModel()

    func present(onSelect: @escaping (AppDescriptor) -> Void) {
        Task { await model.load() }

        let view = AppPickerView(
            model: model,
            onSelect: { [weak self] descriptor in
                onSelect(descriptor)
                self?.window?.close()
            },
            onAddFolder: { [weak self] in
                self?.presentFolderPanel(onSelect: onSelect)
            }
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 520),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Add to Shelfie"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    private func presentFolderPanel(onSelect: @escaping (AppDescriptor) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add Folder"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            onSelect(
                AppDescriptor(
                    id: url.path,
                    name: url.lastPathComponent,
                    url: url,
                    kind: .folder
                )
            )
            self.window?.close()
        }
    }
}
