import AppKit
import SwiftUI

struct FlowCustomizeOverlay: View {
    @Bindable var store: FlowStore
    let onClose: () -> Void

    @State private var isAddingFolder: Bool = false
    @State private var newFolderName: String = ""
    @State private var newFolderClues: String = ""
    @State private var newFolderColor: String = TagPalette.indigo.rawValue
    @State private var newFolderIcon: String = "folder.fill"

    var body: some View {
        ZStack {
            Color.black.opacity(0.54)
                .ignoresSafeArea()
                .onTapGesture {
                    onClose()
                }

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(isAddingFolder ? "Create a New Folder Category" : "Sorting Preferences")
                            .font(.system(size: 19, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text(
                            isAddingFolder
                                ? "Describe in plain words what kind of files belong inside."
                                : "Choose which folders to sort into and how careful Siftify should be."
                        )
                        .font(.system(size: 12.5))
                        .foregroundStyle(.white.opacity(0.66))
                    }
                    Spacer()
                    Button {
                        if isAddingFolder {
                            withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
                                isAddingFolder = false
                            }
                        } else {
                            onClose()
                        }
                    } label: {
                        Image(systemName: isAddingFolder ? "chevron.left" : "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(TranslucentGlassButtonStyle())
                }
                .padding(.horizontal, 24)
                .padding(.top, 22)
                .padding(.bottom, 16)

                Divider()
                    .overlay(Color.white.opacity(0.10))

                if isAddingFolder {
                    addFolderForm
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    preferencesBody
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            .frame(width: 620)
            .glassSurface(
                cornerRadius: 26,
                tint: Color(red: 0.34, green: 0.50, blue: 0.98),
                tintOpacity: 0.04,
                borderOpacity: 0.34,
                isHighlighted: true
            )
            .padding(.horizontal, 28)
            .padding(.vertical, 14)
        }
    }

    private var preferencesBody: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("SORTING STYLE")
                    .font(.system(size: 10.5, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.50))

                HStack(spacing: 10) {
                    ForEach(CarefulnessPreset.allCases) { preset in
                        let selected = store.carefulness == preset
                        Button {
                            withAnimation(.spring(response: 0.36, dampingFraction: 0.80)) {
                                store.carefulness = preset
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(spacing: 6) {
                                    Image(systemName: preset.icon)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(selected ? Color(red: 0.32, green: 0.82, blue: 0.98) : .white.opacity(0.65))
                                    Text(preset.title)
                                        .font(.system(size: 13, weight: .bold, design: .rounded))
                                        .foregroundStyle(.white)
                                }
                                Text(preset.subtitle)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.white.opacity(0.62))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 15, style: .continuous)
                                    .fill(selected ? Color.white.opacity(0.13) : Color.white.opacity(0.045))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                                            .strokeBorder(
                                                selected ? Color(red: 0.32, green: 0.82, blue: 0.98).opacity(0.75) : Color.white.opacity(0.10),
                                                lineWidth: selected ? 1.4 : 1.0
                                            )
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("FOLDER CATEGORIES")
                        .font(.system(size: 10.5, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(.white.opacity(0.50))
                    Spacer()
                    Button {
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.80)) {
                            newFolderName = ""
                            newFolderClues = ""
                            isAddingFolder = true
                        }
                    } label: {
                        Label("New Folder", systemImage: "plus")
                            .font(.system(size: 11.5, weight: .semibold))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 5)
                    }
                    .buttonStyle(TranslucentGlassButtonStyle())
                }

                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        ForEach(store.config.sortedTags) { tag in
                            let color = TagPalette.forTag(tag).swiftUIColor
                            let enabled = tag.isEnabled
                            Button {
                                store.toggleCategory(tag.key)
                            } label: {
                                HStack(spacing: 10) {
                                    ZStack {
                                        Circle()
                                            .fill(enabled ? color.opacity(0.24) : Color.white.opacity(0.06))
                                            .frame(width: 30, height: 30)
                                        Image(systemName: TagPalette.iconForTag(tag))
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(enabled ? color : .white.opacity(0.4))
                                    }

                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(tag.path)
                                            .font(.system(size: 12.5, weight: .semibold))
                                            .foregroundStyle(enabled ? .white : .white.opacity(0.45))
                                            .lineLimit(1)
                                        let subCount = tag.sortedSubtags.count
                                        Text(subCount > 0 ? "\(subCount) smart subfolders" : (enabled ? "Active" : "Paused"))
                                            .font(.system(size: 10.5))
                                            .foregroundStyle(.white.opacity(0.48))
                                    }

                                    Spacer()

                                    Image(systemName: enabled ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(enabled ? color : .white.opacity(0.28))
                                }
                                .padding(.horizontal, 11)
                                .padding(.vertical, 9)
                                .background(
                                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                                        .fill(enabled ? Color.white.opacity(0.075) : Color.white.opacity(0.03))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                                .strokeBorder(
                                                    enabled ? color.opacity(0.42) : Color.white.opacity(0.08),
                                                    lineWidth: 1
                                                )
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 236)
            }

            HStack(spacing: 14) {
                Text("Files per scan:")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.68))

                HStack(spacing: 6) {
                    ForEach(ScanScope.allCases) { scope in
                        let active = store.scanScope == scope
                        Button {
                            withAnimation(.snappy(duration: 0.2)) {
                                store.scanScope = scope
                            }
                        } label: {
                            Text(scope.rawValue)
                                .font(.system(size: 11.5, weight: active ? .semibold : .medium))
                                .foregroundStyle(active ? .white : .white.opacity(0.6))
                                .padding(.horizontal, 11)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule()
                                        .fill(active ? Color.white.opacity(0.16) : Color.white.opacity(0.05))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer()
            }

            Divider()
                .overlay(Color.white.opacity(0.10))

            HStack {
                Button("Reset Default Folders") {
                    store.restoreDefaultCategories()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.58))

                if store.engineOnline {
                    Text("·")
                        .foregroundStyle(.white.opacity(0.3))
                    Button("Free AI Memory") {
                        store.unloadEngineFromMemory()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.58))
                }

                Spacer()

                Button {
                    onClose()
                } label: {
                    Text("Done")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 22)
                        .padding(.vertical, 8)
                }
                .buttonStyle(GlowActionButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
    }

    private var addFolderForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Folder Name")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                TextField("e.g. Recipes, Client Projects, TinyWhoop Clips…", text: $newFolderName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13.5))
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(Color.white.opacity(0.07))
                            .overlay(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                            )
                    )
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("What belongs inside?")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                TextField("e.g. Cooking recipes, grocery lists, and meal plans", text: $newFolderClues)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(Color.white.opacity(0.07))
                            .overlay(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                            )
                    )
            }

            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Accent Color")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75))
                    HStack(spacing: 7) {
                        ForEach(TagPalette.allCases) { pal in
                            Button {
                                newFolderColor = pal.rawValue
                            } label: {
                                Circle()
                                    .fill(pal.swiftUIColor)
                                    .frame(width: 20, height: 20)
                                    .overlay(
                                        Circle()
                                            .strokeBorder(.white, lineWidth: newFolderColor == pal.rawValue ? 2 : 0)
                                    )
                                    .scaleEffect(newFolderColor == pal.rawValue ? 1.15 : 1.0)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Icon")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 8), spacing: 6) {
                    ForEach(TagPalette.iconChoices, id: \.self) { icon in
                        let sel = newFolderIcon == icon
                        Button {
                            newFolderIcon = icon
                        } label: {
                            Image(systemName: icon)
                                .font(.system(size: 13.5))
                                .frame(width: 32, height: 32)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(sel ? Color.white.opacity(0.22) : Color.white.opacity(0.06))
                                )
                                .foregroundStyle(sel ? .white : .white.opacity(0.65))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack {
                Button {
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
                        isAddingFolder = false
                    }
                } label: {
                    Text("Back")
                        .font(.system(size: 12.5, weight: .medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
                .buttonStyle(TranslucentGlassButtonStyle())

                Spacer()

                let canSave = !newFolderName.trimmingCharacters(in: .whitespaces).isEmpty &&
                    !newFolderClues.trimmingCharacters(in: .whitespaces).isEmpty
                Button {
                    store.addCustomCategory(
                        name: newFolderName,
                        description: newFolderClues,
                        icon: newFolderIcon,
                        color: newFolderColor
                    )
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                        isAddingFolder = false
                    }
                } label: {
                    Label("Add Folder", systemImage: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                }
                .buttonStyle(GlowActionButtonStyle())
                .disabled(!canSave)
                .opacity(canSave ? 1.0 : 0.45)
            }
            .padding(.top, 4)
        }
        .padding(24)
    }
}
