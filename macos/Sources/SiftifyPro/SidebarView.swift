import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum ActiveEditorSheet: Identifiable {
    case newTag
    case editTag(TagRule)
    case newSubtag(parent: TagRule)
    case editSubtag(parent: TagRule, subtag: SubtagRule)

    var id: String {
        switch self {
        case .newTag: return "newTag"
        case .editTag(let t): return "editTag-\(t.key)"
        case .newSubtag(let p): return "newSub-\(p.key)"
        case .editSubtag(let p, let s): return "editSub-\(p.key)-\(s.key)"
        }
    }
}

struct SidebarView: View {
    @Bindable var store: TidyStore
    @State private var editorSheet: ActiveEditorSheet? = nil
    @State private var isDropTargeted: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            engineHeader
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 10)

            folderPickerCard
                .padding(.horizontal, 14)
                .padding(.bottom, 12)

            Divider()
                .opacity(0.5)

            tagsHeader
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 6)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(store.config.sortedTags) { tag in
                        TagRowGroupView(
                            store: store,
                            tag: tag,
                            onEditTag: { editorSheet = .editTag(tag) },
                            onAddSubtag: { editorSheet = .newSubtag(parent: tag) },
                            onEditSubtag: { sub in editorSheet = .editSubtag(parent: tag, subtag: sub) }
                        )
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 16)
            }
        }
        .background(.ultraThinMaterial)
        .sheet(item: $editorSheet) { mode in
            switch mode {
            case .newTag:
                TagEditorSheet(store: store, existingTag: nil)
            case .editTag(let tag):
                TagEditorSheet(store: store, existingTag: tag)
            case .newSubtag(let parent):
                SubtagEditorSheet(store: store, parent: parent, existingSubtag: nil)
            case .editSubtag(let parent, let sub):
                SubtagEditorSheet(store: store, parent: parent, existingSubtag: sub)
            }
        }
    }

    private var engineHeader: some View {
        HStack(spacing: 8) {
            switch store.modelState {
            case .downloading(let downloaded, let total, _):
                ProgressView()
                    .controlSize(.mini)
                let pct = Int((Double(downloaded) / Double(max(1, total)) * 100.0).rounded())
                Text("Downloading Q8_0 (\(pct)%)")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                Spacer()
                Button("Cancel") {
                    store.cancelModelDownload()
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

            case .notInstalled, .failed:
                Circle()
                    .fill(Color.orange)
                    .frame(width: 8, height: 8)
                Text("Model Setup Needed")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Download") {
                    store.startModelDownload()
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

            case .installed:
                Circle()
                    .fill(store.engineOnline ? Color.green : (store.isStartingEngine ? Color.orange : Color.secondary.opacity(0.5)))
                    .frame(width: 8, height: 8)
                    .shadow(color: store.engineOnline ? .green.opacity(0.6) : .clear, radius: 4)

                Text(
                    store.engineOnline
                        ? "Metal GPU · Q8_0"
                        : (store.isStartingEngine ? "Loading Q8_0…" : "Q8_0 Standby")
                )
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(store.engineOnline ? .primary : .secondary)

                Spacer()

                if !store.engineOnline && !store.isStartingEngine {
                    Button("Load") {
                        Task { _ = await store.ensureEngineRunning() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }

                engineManageMenu
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private var engineManageMenu: some View {
        Menu {
            Text("Model: basal-2.0-mini-Q8_0.gguf")
            Divider()
            Button("Reveal Model in Finder") {
                store.revealModelInFinder()
            }
            if store.engineOnline {
                Button("Restart Metal Engine") {
                    store.restartEngine()
                }
                Button("Unload Model from RAM") {
                    store.unloadEngineFromMemory()
                }
            }
            Divider()
            Button("Restore Default Categories") {
                store.resetDefaultCategories()
            }
            Button("Remove Downloaded Model…", role: .destructive) {
                store.deleteDownloadedModel()
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Manage local Q8_0 Metal model & categories")
    }

    private var folderPickerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: store.targetFolderURL.path))
                    .resizable()
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 1) {
                    Text(store.targetFolderURL.lastPathComponent)
                        .font(.system(size: 13.5, weight: .semibold))
                        .lineLimit(1)
                    Text("\(store.totalTopLevelFilesInFolder) top-level files")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }

                Spacer()

                Button("Choose…") {
                    store.chooseFolderPanel()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            HStack(spacing: 5) {
                quickFolderChip(
                    label: "Downloads",
                    url: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
                )
                quickFolderChip(
                    label: "Desktop",
                    url: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
                )
                if let demoURL = store.demoInboxURL {
                    quickFolderChip(label: "Demo", url: demoURL)
                }
            }

            Picker("Scope", selection: $store.scanScope) {
                ForEach(ScanScope.allCases) { scope in
                    Text(scope.rawValue).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("Auto-Move Confidence")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("≥ \(store.impliedThresholdPercent)%")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                }
                Slider(value: $store.wrongCost, in: 1.6...4.0, step: 0.1) {
                    Text("Strictness")
                } onEditingChanged: { editing in
                    if !editing { store.saveConfigToDisk() }
                }
                .controlSize(.mini)
            }
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(isDropTargeted ? 0.09 : 0.045))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(isDropTargeted ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: isDropTargeted ? 1.5 : 1)
                )
        )
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { providers in
            guard let first = providers.first else { return false }
            _ = first.loadObject(ofClass: URL.self) { url, _ in
                if let url {
                    DispatchQueue.main.async {
                        store.selectFolder(url)
                    }
                }
            }
            return true
        }
    }

    private func quickFolderChip(label: String, url: URL) -> some View {
        let isCurrent = store.targetFolderURL.standardizedFileURL == url.standardizedFileURL
        return Button {
            store.selectFolder(url)
        } label: {
            Text(label)
                .font(.system(size: 11, weight: isCurrent ? .semibold : .regular))
                .padding(.horizontal, 8)
                .padding(.vertical, 3.5)
                .background(
                    Capsule()
                        .fill(isCurrent ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05))
                )
                .foregroundStyle(isCurrent ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
    }

    private var tagsHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("TAGS & SUBTAGS")
                .font(.system(size: 10.5, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(.secondary)

            Spacer()

            Button("All") { store.setAllTags(enabled: true) }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            Text("·")
                .foregroundStyle(.quaternary)

            Button("None") { store.setAllTags(enabled: false) }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            Button {
                editorSheet = .newTag
            } label: {
                Label("Tag", systemImage: "plus")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
        }
    }
}

struct TagRowGroupView: View {
    @Bindable var store: TidyStore
    let tag: TagRule
    let onEditTag: () -> Void
    let onAddSubtag: () -> Void
    let onEditSubtag: (SubtagRule) -> Void

    @State private var isHovered: Bool = false

    private var isExpanded: Bool {
        store.expandedTagKeys.contains(tag.key)
    }

    private var paletteColor: Color {
        TagPalette.forTag(tag).swiftUIColor
    }

    var body: some View {
        let subtags = tag.sortedSubtags
        let hasSubs = !subtags.isEmpty
        let enabledSubCount = subtags.filter(\.isEnabled).count

        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 7) {
                Button {
                    store.toggleTag(tag.key)
                } label: {
                    Image(systemName: checkboxSymbol(hasSubs: hasSubs, enabledSubCount: enabledSubCount, totalSubs: subtags.count))
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(tag.isEnabled ? paletteColor : .secondary.opacity(0.55))
                }
                .buttonStyle(.plain)

                Image(systemName: TagPalette.iconForTag(tag))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tag.isEnabled ? paletteColor : .secondary)
                    .frame(width: 18)

                Button {
                    if hasSubs {
                        toggleExpand()
                    } else {
                        store.toggleTag(tag.key)
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(tag.path)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(tag.isEnabled ? .primary : .secondary)
                            .lineLimit(1)

                        if hasSubs {
                            Text("\(enabledSubCount)/\(subtags.count)")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.primary.opacity(0.06)))
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isHovered {
                    Button {
                        onAddSubtag()
                    } label: {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Add Subtag under \(tag.path)")
                }

                if hasSubs {
                    Button {
                        toggleExpand()
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovered ? Color.primary.opacity(0.05) : Color.clear)
            )
            .onHover { isHovered = $0 }
            .contextMenu {
                Button("Add Subtag…") { onAddSubtag() }
                Button("Edit Tag…") { onEditTag() }
                Divider()
                Button("Delete Tag", role: .destructive) {
                    store.deleteTag(key: tag.key)
                }
            }

            if hasSubs && isExpanded {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(subtags) { sub in
                        SubtagRowView(
                            subtag: sub,
                            accentColor: paletteColor,
                            onToggle: { store.toggleSubtag(parentKey: tag.key, subKey: sub.key) },
                            onEdit: { onEditSubtag(sub) },
                            onDelete: { store.deleteSubtag(parentKey: tag.key, subKey: sub.key) }
                        )
                    }

                    Button {
                        onAddSubtag()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "plus")
                                .font(.system(size: 9.5, weight: .semibold))
                            Text("Add subtag")
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(.secondary)
                        .padding(.leading, 8)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.leading, 22)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(paletteColor.opacity(0.25))
                        .frame(width: 1.5)
                        .padding(.leading, 15)
                        .padding(.vertical, 4)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func checkboxSymbol(hasSubs: Bool, enabledSubCount: Int, totalSubs: Int) -> String {
        if !tag.isEnabled { return "circle" }
        if hasSubs && enabledSubCount > 0 && enabledSubCount < totalSubs {
            return "minus.circle.fill"
        }
        return "checkmark.circle.fill"
    }

    private func toggleExpand() {
        withAnimation(.snappy(duration: 0.22)) {
            if store.expandedTagKeys.contains(tag.key) {
                store.expandedTagKeys.remove(tag.key)
            } else {
                store.expandedTagKeys.insert(tag.key)
            }
        }
    }
}

struct SubtagRowView: View {
    let subtag: SubtagRule
    let accentColor: Color
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        HStack(spacing: 7) {
            Button(action: onToggle) {
                Image(systemName: subtag.isEnabled ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(subtag.isEnabled ? accentColor : .secondary.opacity(0.5))
            }
            .buttonStyle(.plain)

            Button(action: onToggle) {
                Text(subtag.path)
                    .font(.system(size: 12))
                    .foregroundStyle(subtag.isEnabled ? .primary : .secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isHovered {
                Button(action: onEdit) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Edit subtag")
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isHovered ? Color.primary.opacity(0.045) : Color.clear)
        )
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Edit Subtag…", action: onEdit)
            Divider()
            Button("Delete Subtag", role: .destructive, action: onDelete)
        }
    }
}

struct TagEditorSheet: View {
    @Bindable var store: TidyStore
    let existingTag: TagRule?
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var descriptionText: String = ""
    @State private var selectedColor: String = TagPalette.indigo.rawValue
    @State private var selectedIcon: String = "folder.fill"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(existingTag == nil ? "New Category Tag" : "Edit Category Tag")
                .font(.system(size: 16, weight: .semibold))

            VStack(alignment: .leading, spacing: 6) {
                Text("Folder Name")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("e.g. 3D Slicer Profiles, Client Projects…", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("What files belong here?")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                TextEditor(text: $descriptionText)
                    .font(.system(size: 12.5))
                    .frame(height: 76)
                    .padding(4)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
                    )
                Text("Plain-English clues for the local classifier (file topics, keywords, formats, or download sources).")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Color")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        ForEach(TagPalette.allCases) { pal in
                            Button {
                                selectedColor = pal.rawValue
                            } label: {
                                Circle()
                                    .fill(pal.swiftUIColor)
                                    .frame(width: 18, height: 18)
                                    .overlay(
                                        Circle()
                                            .strokeBorder(Color.white, lineWidth: selectedColor == pal.rawValue ? 2 : 0)
                                    )
                                    .scaleEffect(selectedColor == pal.rawValue ? 1.12 : 1.0)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Icon")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 8), spacing: 6) {
                    ForEach(TagPalette.iconChoices, id: \.self) { icon in
                        let isSel = selectedIcon == icon
                        Button {
                            selectedIcon = icon
                        } label: {
                            Image(systemName: icon)
                                .font(.system(size: 13))
                                .frame(width: 28, height: 28)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(isSel ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.05))
                                )
                                .foregroundStyle(isSel ? Color.accentColor : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack {
                if let existingTag {
                    Button("Delete", role: .destructive) {
                        store.deleteTag(key: existingTag.key)
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(existingTag == nil ? "Add Tag" : "Save") {
                    store.upsertTag(
                        existingKey: existingTag?.key,
                        name: name,
                        description: descriptionText,
                        icon: selectedIcon,
                        color: selectedColor
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || descriptionText.trimmingCharacters(in: .whitespaces).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            if let existingTag {
                name = existingTag.path
                descriptionText = existingTag.description
                selectedColor = TagPalette.forTag(existingTag).rawValue
                selectedIcon = TagPalette.iconForTag(existingTag)
            }
        }
    }
}

struct SubtagEditorSheet: View {
    @Bindable var store: TidyStore
    let parent: TagRule
    let existingSubtag: SubtagRule?
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var descriptionText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(existingSubtag == nil ? "New Subtag in \(parent.path)" : "Edit Subtag")
                    .font(.system(size: 16, weight: .semibold))
                Text("Files will organize into \(parent.path)/\(name.isEmpty ? "Subfolder" : name)")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Subfolder Name")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("e.g. Tax & Statements, TinyWhoop Configs…", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Content Description")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                TextEditor(text: $descriptionText)
                    .font(.system(size: 12.5))
                    .frame(height: 80)
                    .padding(4)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
                    )
            }

            HStack {
                if let existingSubtag {
                    Button("Delete", role: .destructive) {
                        store.deleteSubtag(parentKey: parent.key, subKey: existingSubtag.key)
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(existingSubtag == nil ? "Add Subtag" : "Save") {
                    store.upsertSubtag(
                        parentKey: parent.key,
                        existingSubKey: existingSubtag?.key,
                        name: name,
                        description: descriptionText
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || descriptionText.trimmingCharacters(in: .whitespaces).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 400)
        .onAppear {
            if let existingSubtag {
                name = existingSubtag.path
                descriptionText = existingSubtag.description
            }
        }
    }
}
