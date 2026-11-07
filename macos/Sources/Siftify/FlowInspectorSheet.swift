import AppKit
import SwiftUI

struct FlowStackDetailOverlay: View {
    @Bindable var store: FlowStore
    let target: FlowInspectorTarget
    let onClose: () -> Void

    private var groupData: FolderStackGroup? {
        if case .group(let key) = target {
            return store.folderStacks.first { $0.tagKey == key }
        }
        return nil
    }

    private var entries: [(item: ScanItem, decision: EffectiveDecision)] {
        switch target {
        case .group(let key):
            return store.folderStacks.first(where: { $0.tagKey == key })?.entries ?? []
        case .stayingPut:
            return store.stayingPutEntries
        }
    }

    private var accentColor: Color {
        if let g = groupData {
            return g.palette.swiftUIColor
        }
        return Color(red: 0.55, green: 0.62, blue: 0.78)
    }

    private var headerTitle: String {
        if let g = groupData {
            return g.title
        }
        return "Keeping Safe in Place"
    }

    private var headerSubtitle: String {
        if let g = groupData {
            return "\(g.selectedCount) of \(g.totalCount) file\(g.totalCount == 1 ? "" : "s") selected to move into \(g.title)"
        }
        let count = entries.count
        return "\(count) file\(count == 1 ? "" : "s") we weren’t sure enough about — you can still pick a folder manually"
    }

    private var headerIcon: String {
        if let g = groupData {
            return g.icon
        }
        return "shield.checkered"
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.52)
                .ignoresSafeArea()
                .onTapGesture {
                    onClose()
                }

            VStack(spacing: 0) {
                headerBar
                    .padding(.horizontal, 24)
                    .padding(.top, 22)
                    .padding(.bottom, 16)

                Divider()
                    .overlay(Color.white.opacity(0.10))

                if entries.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 28))
                            .foregroundStyle(.white.opacity(0.5))
                        Text("No files left in this group.")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                    .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(entries, id: \.item.id) { pair in
                                FlowDetailFileRow(
                                    store: store,
                                    item: pair.item,
                                    decision: pair.decision,
                                    accentColor: accentColor
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                    }
                    .frame(maxHeight: 380)
                }

                Divider()
                    .overlay(Color.white.opacity(0.10))

                HStack {
                    if let g = groupData {
                        Button {
                            store.toggleGroupSelection(g.tagKey)
                        } label: {
                            Label(
                                g.isAllSelected ? "Pause Whole Folder" : "Include All in \(g.title)",
                                systemImage: g.isAllSelected ? "pause.circle" : "checkmark.circle.fill"
                            )
                            .font(.system(size: 12.5, weight: .medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                        }
                        .buttonStyle(TranslucentGlassButtonStyle())
                    }

                    Spacer()

                    Button {
                        onClose()
                    } label: {
                        Text("Done")
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(GlowActionButtonStyle(accent: accentColor, secondaryAccent: accentColor.opacity(0.8)))
                    .keyboardShortcut(.cancelAction)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
            }
            .frame(width: 660)
            .glassSurface(
                cornerRadius: 26,
                tint: accentColor,
                tintOpacity: 0.05,
                borderOpacity: 0.36,
                isHighlighted: true
            )
            .padding(28)
        }
    }

    private var headerBar: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.22))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Circle()
                            .strokeBorder(accentColor.opacity(0.55), lineWidth: 1)
                    )
                Image(systemName: headerIcon)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(accentColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(headerTitle)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(headerSubtitle)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.white.opacity(0.68))
            }

            Spacer()

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(TranslucentGlassButtonStyle())
            .help("Close")
        }
    }
}

struct FlowDetailFileRow: View {
    @Bindable var store: FlowStore
    let item: ScanItem
    let decision: EffectiveDecision
    let accentColor: Color

    @State private var isHovered: Bool = false

    private var surenessBadge: (label: String, color: Color) {
        if decision.confidence >= 0.80 {
            return ("Very Sure", Color(red: 0.20, green: 0.88, blue: 0.62))
        } else if decision.confidence >= 0.63 {
            return ("Clear Match", Color(red: 0.28, green: 0.78, blue: 0.96))
        } else if decision.shouldMove {
            return ("Good Match", Color(red: 0.56, green: 0.68, blue: 0.98))
        } else {
            return ("Unsure", Color.white.opacity(0.50))
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                store.toggleItemMove(item.id)
            } label: {
                Image(systemName: decision.shouldMove ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(
                        decision.shouldMove
                            ? Color(red: 0.20, green: 0.86, blue: 0.60)
                            : Color.white.opacity(0.32)
                    )
                    .symbolEffect(.bounce, value: decision.shouldMove)
            }
            .buttonStyle(.plain)
            .help(decision.shouldMove ? "Keep this file in place" : "Include this file when organizing")

            Image(nsImage: NSWorkspace.shared.icon(forFile: item.xray.path))
                .resizable()
                .interpolation(.high)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.xray.filename)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(decision.shouldMove ? .white : .white.opacity(0.62))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(item.xray.friendlyClueDescription)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.56))
                        .lineLimit(1)

                    Text("·")
                        .foregroundStyle(.white.opacity(0.3))

                    Text(surenessBadge.label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(surenessBadge.color)
                }
            }

            Spacer(minLength: 8)

            destinationMenu

            HStack(spacing: 4) {
                Button {
                    store.openFile(item.xray.path)
                } label: {
                    Image(systemName: "eye")
                        .font(.system(size: 12))
                        .frame(width: 26, height: 26)
                        .foregroundStyle(.white.opacity(0.75))
                }
                .buttonStyle(.plain)
                .help("Open File")

                Button {
                    store.revealInFinder(item.xray.path)
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 12))
                        .frame(width: 26, height: 26)
                        .foregroundStyle(.white.opacity(0.75))
                }
                .buttonStyle(.plain)
                .help("Show in Finder")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(isHovered ? 0.085 : 0.045))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(isHovered ? 0.18 : 0.08), lineWidth: 1)
                )
        )
        .animation(.easeOut(duration: 0.16), value: isHovered)
        .onHover { isHovered = $0 }
    }

    private var destinationMenu: some View {
        Menu {
            Button("Suggested (\(decision.destinationRelPath.replacingOccurrences(of: "/", with: " › ")))") {
                store.setManualDestination(itemID: item.id, relPath: nil, tagKey: nil)
            }
            Button("Keep Where It Is") {
                store.setManualDestination(itemID: item.id, relPath: "__leave__", tagKey: nil)
            }
            Divider()
            ForEach(store.config.sortedTags) { tag in
                let subs = tag.sortedSubtags
                if subs.isEmpty {
                    Button(tag.path) {
                        store.setManualDestination(itemID: item.id, relPath: tag.path, tagKey: tag.key)
                    }
                } else {
                    Menu(tag.path) {
                        ForEach(subs) { sub in
                            Button(sub.path) {
                                store.setManualDestination(
                                    itemID: item.id,
                                    relPath: "\(tag.path)/\(sub.path)",
                                    tagKey: tag.key
                                )
                            }
                        }
                        Divider()
                        Button("\(tag.path) › General") {
                            store.setManualDestination(
                                itemID: item.id,
                                relPath: "\(tag.path)/General",
                                tagKey: tag.key
                            )
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(decision.shouldMove ? accentColor : Color.white.opacity(0.35))
                    .frame(width: 7, height: 7)
                Text(
                    decision.shouldMove
                        ? decision.destinationRelPath.replacingOccurrences(of: "/", with: " › ")
                        : "Keep in place"
                )
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(decision.shouldMove ? accentColor.opacity(0.20) : Color.white.opacity(0.07))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.8)
                    )
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}
