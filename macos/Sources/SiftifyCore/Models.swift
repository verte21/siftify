import AppKit
import Foundation
import SwiftUI

struct CostsConfig: Codable, Equatable {
    var wrong: Double
    var deferCost: Double

    enum CodingKeys: String, CodingKey {
        case wrong
        case deferCost = "defer"
    }
}

struct SubtagRule: Codable, Equatable, Identifiable {
    var id: String { key }
    var key: String = ""
    var path: String
    var description: String
    var enabled: Bool?
    var order: Int?

    enum CodingKeys: String, CodingKey {
        case path, description, enabled, order
    }

    var isEnabled: Bool {
        get { enabled ?? true }
        set { enabled = newValue }
    }
}

struct TagRule: Codable, Equatable, Identifiable {
    var id: String { key }
    var key: String = ""
    var path: String
    var description: String
    var enabled: Bool?
    var icon: String?
    var color: String?
    var order: Int?
    var subCostWrong: Double?
    var subfolders: [String: SubtagRule]?

    enum CodingKeys: String, CodingKey {
        case path, description, enabled, icon, color, order, subCostWrong, subfolders
    }

    var isEnabled: Bool {
        get { enabled ?? true }
        set { enabled = newValue }
    }

    var sortedSubtags: [SubtagRule] {
        guard let subfolders else { return [] }
        return subfolders.map { k, v in
            var copy = v
            copy.key = k
            return copy
        }.sorted { a, b in
            if let oa = a.order, let ob = b.order, oa != ob { return oa < ob }
            return a.path.localizedStandardCompare(b.path) == .orderedAscending
        }
    }

    var activeSubtagCount: Int {
        let subs = sortedSubtags
        if subs.isEmpty { return isEnabled ? 1 : 0 }
        guard isEnabled else { return 0 }
        return subs.filter(\.isEnabled).count
    }
}

struct TidyConfig: Codable, Equatable {
    var engineUrl: String
    var costs: CostsConfig
    var folders: [String: TagRule]

    enum CodingKeys: String, CodingKey {
        case engineUrl
        case basalUrl
        case costs
        case folders
    }

    init(engineUrl: String, costs: CostsConfig, folders: [String: TagRule]) {
        self.engineUrl = engineUrl
        self.costs = costs
        self.folders = folders
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.engineUrl = try c.decodeIfPresent(String.self, forKey: .engineUrl)
            ?? c.decodeIfPresent(String.self, forKey: .basalUrl)
            ?? "http://127.0.0.1:8766"
        self.costs = try c.decode(CostsConfig.self, forKey: .costs)
        self.folders = try c.decode([String: TagRule].self, forKey: .folders)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(engineUrl, forKey: .engineUrl)
        try c.encode(costs, forKey: .costs)
        try c.encode(folders, forKey: .folders)
    }

    static let builtInOrder: [String] = [
        "documents_notes",
        "invoices_finance",
        "fpv_hobby",
        "3d_prints",
        "screenshots_ui",
        "code_configs",
        "installers_archives",
        "media_photos"
    ]

    var sortedTags: [TagRule] {
        folders.map { k, v in
            var copy = v
            copy.key = k
            return copy
        }.sorted { a, b in
            let ia = Self.builtInOrder.firstIndex(of: a.key)
            let ib = Self.builtInOrder.firstIndex(of: b.key)
            if let oa = a.order, let ob = b.order, oa != ob { return oa < ob }
            if let ia, let ib { return ia < ib }
            if ia != nil { return true }
            if ib != nil { return false }
            return a.path.localizedStandardCompare(b.path) == .orderedAscending
        }
    }
}

enum TagPalette: String, CaseIterable, Identifiable {
    case indigo, emerald, orange, cyan, purple, teal, blue, pink, amber, rose

    var id: String { rawValue }

    var swiftUIColor: Color {
        switch self {
        case .indigo: return Color(red: 0.36, green: 0.42, blue: 0.95)
        case .emerald: return Color(red: 0.13, green: 0.72, blue: 0.48)
        case .orange: return Color(red: 0.95, green: 0.52, blue: 0.18)
        case .cyan: return Color(red: 0.12, green: 0.68, blue: 0.85)
        case .purple: return Color(red: 0.62, green: 0.38, blue: 0.92)
        case .teal: return Color(red: 0.14, green: 0.66, blue: 0.64)
        case .blue: return Color(red: 0.22, green: 0.54, blue: 0.96)
        case .pink: return Color(red: 0.90, green: 0.34, blue: 0.62)
        case .amber: return Color(red: 0.90, green: 0.68, blue: 0.14)
        case .rose: return Color(red: 0.92, green: 0.28, blue: 0.38)
        }
    }

    static func forTag(_ tag: TagRule) -> TagPalette {
        if let c = tag.color, let p = TagPalette(rawValue: c) { return p }
        switch tag.key {
        case "documents_notes": return .indigo
        case "invoices_finance": return .emerald
        case "fpv_hobby": return .orange
        case "3d_prints": return .cyan
        case "screenshots_ui": return .purple
        case "code_configs": return .teal
        case "installers_archives": return .blue
        case "media_photos": return .pink
        default: return .indigo
        }
    }

    static func iconForTag(_ tag: TagRule) -> String {
        if let i = tag.icon, !i.isEmpty { return i }
        switch tag.key {
        case "documents_notes": return "doc.text.fill"
        case "invoices_finance": return "creditcard.fill"
        case "fpv_hobby": return "airplane.circle.fill"
        case "3d_prints": return "cube.transparent.fill"
        case "screenshots_ui": return "camera.viewfinder"
        case "code_configs": return "chevron.left.forwardslash.chevron.right"
        case "installers_archives": return "shippingbox.fill"
        case "media_photos": return "photo.on.rectangle.angled"
        default: return "folder.fill"
        }
    }

    static let iconChoices: [String] = [
        "folder.fill",
        "doc.text.fill",
        "creditcard.fill",
        "airplane.circle.fill",
        "cube.transparent.fill",
        "camera.viewfinder",
        "chevron.left.forwardslash.chevron.right",
        "shippingbox.fill",
        "photo.on.rectangle.angled",
        "book.closed.fill",
        "ticket.fill",
        "briefcase.fill",
        "graduationcap.fill",
        "wrench.and.screwdriver.fill",
        "waveform",
        "sparkles"
    ]
}

struct FileXRayData: Codable, Equatable, Sendable {
    let path: String
    let filename: String
    let ext: String
    let sizeBytes: Int64
    let uti: String?
    let downloadedFrom: [String]
    let spotlightTitle: String?
    let authors: [String]
    let subject: String?
    let pageCount: Int?
    let durationSeconds: Double?
    let dimensions: String?
    let visionTags: [String]
    let archiveEntries: [String]
    let extractionMethod: String?
    let textPreview: String?

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }

    var signalBadges: [String] {
        var badges: [String] = []
        if let firstUrl = downloadedFrom.first, let host = URL(string: firstUrl)?.host {
            badges.append(host.replacingOccurrences(of: "www.", with: ""))
        }
        let chars = textPreview?.count ?? 0
        let pg = pageCount.map { "\($0)p · " } ?? ""
        switch extractionMethod {
        case "apple_vision_ocr" where chars > 0:
            badges.append("Vision OCR")
        case "pdfkit_text" where chars > 0:
            badges.append("PDF · \(pg)\(chars)c")
        case "pdf_vision_ocr" where chars > 0:
            badges.append("Scanned PDF OCR")
        case "office_textutil" where chars > 0:
            badges.append("\(ext.uppercased()) · \(chars)c")
        case "pptx_slides" where chars > 0:
            badges.append("Slides · \(pg)\(chars)c")
        case "xlsx_sheets" where chars > 0:
            badges.append("Sheet · \(pg)\(chars)c")
        case "epub_content" where chars > 0:
            badges.append("EPUB · \(chars)c")
        case "iwork_vision_ocr" where chars > 0:
            badges.append("iWork OCR")
        case "blackbox_header" where chars > 0:
            badges.append("Blackbox Header")
        case "stl_header" where chars > 0:
            badges.append("3D Mesh")
        case "zip_manifest" where !archiveEntries.isEmpty:
            badges.append("Archive · \(archiveEntries.count) items")
        default:
            if chars > 0 { badges.append("Text · \(chars)c") }
        }
        if !visionTags.isEmpty && badges.count < 2 {
            badges.append(visionTags[0].replacingOccurrences(of: "_", with: " "))
        }
        if badges.isEmpty {
            badges.append(ext.isEmpty ? "Metadata" : ".\(ext)")
        }
        return badges
    }
}

enum DeferReason: Equatable {
    case lowConfidence
    case tagUnchecked(String)
    case manualSkip
}

struct EffectiveDecision: Equatable {
    let wouldAutoMove: Bool
    let shouldMove: Bool
    let destinationRelPath: String
    let tagKey: String
    let subtagKey: String?
    let confidence: Double
    let deferReason: DeferReason?
}

struct ScanItem: Identifiable, Equatable {
    var id: String { xray.path }
    let xray: FileXRayData
    let topKey: String
    let topConfidence: Double
    let topProbabilities: [String: Double]
    let subKey: String?
    let subConfidence: Double?
    let subProbabilities: [String: Double]
    let elapsedMs: Int

    var manualIncludeOverride: Bool? = nil
    var manualDestinationRelPath: String? = nil
    var manualTagKey: String? = nil
    var movedToPath: String? = nil

    func evaluate(config: TidyConfig, wrongCost: Double) -> EffectiveDecision {
        if let customRel = manualDestinationRelPath {
            if customRel == "__leave__" {
                return EffectiveDecision(
                    wouldAutoMove: false,
                    shouldMove: false,
                    destinationRelPath: config.folders[topKey]?.path ?? topKey,
                    tagKey: topKey,
                    subtagKey: subKey,
                    confidence: topConfidence,
                    deferReason: .manualSkip
                )
            }
            let should = manualIncludeOverride ?? true
            return EffectiveDecision(
                wouldAutoMove: true,
                shouldMove: should,
                destinationRelPath: customRel,
                tagKey: manualTagKey ?? topKey,
                subtagKey: nil,
                confidence: topConfidence,
                deferReason: should ? nil : .manualSkip
            )
        }

        let deferCost = config.costs.deferCost
        let topThreshold = max(0.0, 1.0 - (deferCost / max(1.01, wrongCost)))
        guard let parentRule = config.folders[topKey] else {
            return EffectiveDecision(
                wouldAutoMove: false,
                shouldMove: manualIncludeOverride ?? false,
                destinationRelPath: topKey,
                tagKey: topKey,
                subtagKey: nil,
                confidence: topConfidence,
                deferReason: .lowConfidence
            )
        }

        var resolvedPath = parentRule.path
        var resolvedConf = topConfidence
        var resolvedSubKey: String? = nil
        var uncheckedLabel: String? = parentRule.isEnabled ? nil : parentRule.path

        if let subs = parentRule.subfolders, !subs.isEmpty {
            let subWrong = parentRule.subCostWrong ?? 1.8
            let subThreshold = max(0.0, 1.0 - (deferCost / max(1.01, subWrong)))
            if let sk = subKey, let sc = subConfidence, let subRule = subs[sk], sc >= subThreshold {
                resolvedSubKey = sk
                resolvedPath = "\(parentRule.path)/\(subRule.path)"
                resolvedConf = min(topConfidence, sc)
                if !subRule.isEnabled {
                    uncheckedLabel = "\(parentRule.path) › \(subRule.path)"
                }
            } else {
                // Ambiguous subtag: only fall back to General if all subtags under this parent are enabled
                let allSubsEnabled = subs.values.allSatisfy { $0.isEnabled }
                if allSubsEnabled {
                    resolvedPath = "\(parentRule.path)/General"
                } else {
                    uncheckedLabel = "\(parentRule.path) (unmatched subtag)"
                }
            }
        }

        if topConfidence < topThreshold {
            let should = manualIncludeOverride ?? false
            return EffectiveDecision(
                wouldAutoMove: false,
                shouldMove: should,
                destinationRelPath: resolvedPath,
                tagKey: topKey,
                subtagKey: resolvedSubKey,
                confidence: resolvedConf,
                deferReason: should ? nil : .lowConfidence
            )
        }

        if let unchecked = uncheckedLabel {
            let should = manualIncludeOverride ?? false
            return EffectiveDecision(
                wouldAutoMove: false,
                shouldMove: should,
                destinationRelPath: resolvedPath,
                tagKey: topKey,
                subtagKey: resolvedSubKey,
                confidence: resolvedConf,
                deferReason: should ? nil : .tagUnchecked(unchecked)
            )
        }

        let should = manualIncludeOverride ?? true
        return EffectiveDecision(
            wouldAutoMove: true,
            shouldMove: should,
            destinationRelPath: resolvedPath,
            tagKey: topKey,
            subtagKey: resolvedSubKey,
            confidence: resolvedConf,
            deferReason: should ? nil : .manualSkip
        )
    }
}

struct MoveRecord: Codable, Equatable {
    let from: String
    let to: String
    let folderKey: String
    let folderPath: String?
    let confidence: Double
}

struct UndoBatch: Codable, Equatable {
    let timestamp: String
    let targetDir: String
    let moves: [MoveRecord]
}

enum ScanScope: String, CaseIterable, Identifiable {
    case latest40 = "Latest 40"
    case latest100 = "Latest 100"
    case all = "All Files"

    var id: String { rawValue }

    var limit: Int? {
        switch self {
        case .latest40: return 40
        case .latest100: return 100
        case .all: return nil
        }
    }
}

enum ResultFilterMode: Equatable {
    case all
    case willMove
    case untouched
    case byTag(String)
}
