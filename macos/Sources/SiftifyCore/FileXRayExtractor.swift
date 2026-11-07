import AppKit
import CoreServices
import Darwin
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import Vision

enum FileXRayExtractor {
    private static let textExtensions: Set<String> = [
        "txt", "md", "markdown", "json", "jsonl", "yaml", "yml", "toml", "ini", "cfg", "conf",
        "csv", "tsv", "log", "srt", "xml", "html", "htm", "cli", "diff", "patch",
        "py", "ts", "tsx", "js", "jsx", "swift", "rs", "go", "sh", "zsh", "sql", "gcode", "tex", "bib"
    ]

    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "heic", "heif", "webp", "tiff", "tif", "bmp", "gif"
    ]

    private static let textutilExtensions: Set<String> = [
        "docx", "doc", "rtf", "odt", "wordml"
    ]

    private static let iworkExtensions: Set<String> = [
        "pages", "key", "numbers"
    ]

    static func inspect(path: String) -> FileXRayData {
        autoreleasepool {
            inspectImpl(path: path)
        }
    }

    private static func truncateClean(_ s: String, maxChars: Int = 2200) -> String {
        let collapsed = s
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        if collapsed.count <= maxChars { return collapsed }
        return String(collapsed.prefix(maxChars)) + "…"
    }

    private static func runCommandCapture(executable: String, arguments: [String], maxBytes: Int = 98_304) -> Data? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = arguments
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            let data = try? pipe.fileHandleForReading.read(upToCount: maxBytes)
            try? pipe.fileHandleForReading.close()
            if proc.isRunning {
                proc.terminate()
            }
            proc.waitUntilExit()
            return data
        } catch {
            return nil
        }
    }

    private static func decodeXMLEntities(_ s: String) -> String {
        s.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }

    private static func stripMarkupTags(_ raw: String) -> String {
        let withBreaks = raw
            .replacingOccurrences(of: "</p>", with: "\n")
            .replacingOccurrences(of: "</div>", with: "\n")
            .replacingOccurrences(of: "</li>", with: "\n")
            .replacingOccurrences(of: "</h1>", with: "\n")
            .replacingOccurrences(of: "</h2>", with: "\n")
            .replacingOccurrences(of: "</h3>", with: "\n")
            .replacingOccurrences(of: "<br>", with: "\n")
            .replacingOccurrences(of: "<br/>", with: "\n")
            .replacingOccurrences(of: "</a:p>", with: "\n")
        let stripped = withBreaks.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        return decodeXMLEntities(stripped)
    }

    private static func regexCaptures(_ text: String, pattern: String, maxMatches: Int = 80) -> [String] {
        guard let rx = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        let ns = text as NSString
        let matches = rx.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length))
        var out: [String] = []
        for m in matches.prefix(maxMatches) {
            if m.numberOfRanges > 1 {
                let r = m.range(at: 1)
                if r.location != NSNotFound {
                    let val = stripMarkupTags(ns.substring(with: r)).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !val.isEmpty { out.append(val) }
                }
            }
        }
        return out
    }

    private static func readXattrStrings(path: String, name: String) -> [String] {
        let size = getxattr(path, name, nil, 0, 0, 0)
        guard size > 0 else { return [] }
        var buffer = Data(count: size)
        let read = buffer.withUnsafeMutableBytes { ptr in
            getxattr(path, name, ptr.baseAddress, size, 0, 0)
        }
        guard read > 0 else { return [] }
        if let plist = try? PropertyListSerialization.propertyList(from: buffer, options: [], format: nil) {
            if let arr = plist as? [String] { return arr.filter { !$0.isEmpty } }
            if let str = plist as? String, !str.isEmpty { return [str] }
        }
        return []
    }

    private static func runVision(on cgImage: CGImage) -> (ocr: String?, tags: [String]) {
        let ocrReq = VNRecognizeTextRequest()
        ocrReq.recognitionLevel = .accurate
        ocrReq.usesLanguageCorrection = true

        let classifyReq = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([ocrReq, classifyReq])

        let lines = (ocrReq.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        let ocrText = lines.isEmpty ? nil : truncateClean(lines.joined(separator: "\n"))

        let tags = (classifyReq.results ?? [])
            .filter { $0.confidence >= 0.25 }
            .prefix(5)
            .map { $0.identifier }

        return (ocrText, Array(tags))
    }

    private struct PDFExtraction {
        let method: String?
        let text: String?
        let tags: [String]
        let pageCount: Int
        let title: String?
        let authors: [String]
        let subject: String?
    }

    private static func extractPDF(url: URL) -> PDFExtraction? {
        guard let doc = PDFDocument(url: url), doc.pageCount > 0 else { return nil }
        let pageCount = doc.pageCount
        let docAttrs = doc.documentAttributes ?? [:]
        let rawTitle = (docAttrs[PDFDocumentAttribute.titleAttribute] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawAuthor = (docAttrs[PDFDocumentAttribute.authorAttribute] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawSubject = (docAttrs[PDFDocumentAttribute.subjectAttribute] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let keywords = (docAttrs[PDFDocumentAttribute.keywordsAttribute] as? [String])?.joined(separator: ", ")

        let title = (rawTitle?.isEmpty == false) ? rawTitle : nil
        let authors = (rawAuthor?.isEmpty == false) ? [rawAuthor!] : []
        let combinedSubj = [rawSubject, keywords].compactMap { ($0?.isEmpty == false) ? $0 : nil }.joined(separator: " | ")
        let subject = combinedSubj.isEmpty ? nil : truncateClean(combinedSubj, maxChars: 240)

        var collected = ""
        for idx in 0..<min(pageCount, 5) {
            if let pageText = doc.page(at: idx)?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !pageText.isEmpty {
                collected += pageText + "\n"
                if collected.count >= 2600 { break }
            }
        }

        let cleaned = truncateClean(collected, maxChars: 2200)
        if cleaned.count >= 32 {
            return PDFExtraction(method: "pdfkit_text", text: cleaned, tags: [], pageCount: pageCount, title: title, authors: authors, subject: subject)
        }

        var ocrParts: [String] = []
        var firstTags: [String] = []
        for idx in 0..<min(pageCount, 2) {
            if let page = doc.page(at: idx) {
                let thumb = page.thumbnail(of: CGSize(width: 1600, height: 1600), for: .mediaBox)
                if let cgImage = thumb.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    let vision = runVision(on: cgImage)
                    if idx == 0 { firstTags = vision.tags }
                    if let ocr = vision.ocr, !ocr.isEmpty { ocrParts.append(ocr) }
                    if ocrParts.joined(separator: "\n").count >= 200 { break }
                }
            }
        }
        let ocrCombined = ocrParts.isEmpty ? nil : truncateClean(ocrParts.joined(separator: "\n"), maxChars: 2200)
        return PDFExtraction(method: ocrCombined != nil ? "pdf_vision_ocr" : nil, text: ocrCombined, tags: firstTags, pageCount: pageCount, title: title, authors: authors, subject: subject)
    }

    private static func listZipEntries(path: String, maxEntries: Int = 200) -> [String] {
        guard let data = runCommandCapture(executable: "/usr/bin/zipinfo", arguments: ["-1", path], maxBytes: 65_536), !data.isEmpty else {
            return []
        }
        let out = String(data: data, encoding: .utf8) ?? ""
        return Array(
            out.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .prefix(maxEntries)
        )
    }

    private static func unzipEntryText(path: String, entries: [String], maxBytes: Int = 98_304) -> String? {
        guard !entries.isEmpty,
              let data = runCommandCapture(executable: "/usr/bin/unzip", arguments: ["-p", path] + entries, maxBytes: maxBytes),
              !data.isEmpty else {
            return nil
        }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }

    private static func extractPptx(path: String) -> (slideCount: Int?, text: String?) {
        let entries = listZipEntries(path: path, maxEntries: 300)
        let slides = entries
            .filter { $0.hasPrefix("ppt/slides/slide") && $0.hasSuffix(".xml") }
            .sorted { a, b in a.localizedStandardCompare(b) == .orderedAscending }
        guard !slides.isEmpty else { return (nil, nil) }
        guard let xml = unzipEntryText(path: path, entries: Array(slides.prefix(5)), maxBytes: 131_072) else {
            return (slides.count, nil)
        }
        let cleaned = truncateClean(stripMarkupTags(xml), maxChars: 2200)
        return (slides.count, cleaned.isEmpty ? nil : cleaned)
    }

    private static func extractXlsx(path: String) -> (sheetCount: Int?, text: String?) {
        let entries = Set(listZipEntries(path: path, maxEntries: 200))
        var parts: [String] = []
        var sheetCount: Int? = nil

        if entries.contains("xl/workbook.xml"),
           let wbXml = unzipEntryText(path: path, entries: ["xl/workbook.xml"], maxBytes: 32_768) {
            let sheets = regexCaptures(wbXml, pattern: "<sheet[^>]*\\bname=\"([^\"]+)\"", maxMatches: 25)
            if !sheets.isEmpty {
                sheetCount = sheets.count
                parts.append("Sheets: " + sheets.joined(separator: ", "))
            }
        }
        if entries.contains("xl/sharedStrings.xml"),
           let ssXml = unzipEntryText(path: path, entries: ["xl/sharedStrings.xml"], maxBytes: 65_536) {
            let cells = regexCaptures(ssXml, pattern: "<t(?:\\s[^>]*)?>([^<]+)</t>", maxMatches: 80)
            if !cells.isEmpty {
                parts.append("Headers & Values: " + cells.joined(separator: " | "))
            }
        }
        let combined = truncateClean(parts.joined(separator: "\n"), maxChars: 2200)
        return (sheetCount, combined.isEmpty ? nil : combined)
    }

    private static func extractEpub(path: String) -> (title: String?, authors: [String], subject: String?, text: String?) {
        let entries = listZipEntries(path: path, maxEntries: 300)
        var title: String? = nil
        var authors: [String] = []
        var subject: String? = nil
        var chunks: [String] = []

        if let opfEntry = entries.first(where: { $0.lowercased().hasSuffix(".opf") }),
           let opfXml = unzipEntryText(path: path, entries: [opfEntry], maxBytes: 65_536) {
            title = regexCaptures(opfXml, pattern: "<dc:title[^>]*>(.*?)</dc:title>", maxMatches: 1).first
            authors = regexCaptures(opfXml, pattern: "<dc:creator[^>]*>(.*?)</dc:creator>", maxMatches: 4)
            let subjects = regexCaptures(opfXml, pattern: "<dc:subject[^>]*>(.*?)</dc:subject>", maxMatches: 6)
            if !subjects.isEmpty { subject = subjects.joined(separator: ", ") }
            if let desc = regexCaptures(opfXml, pattern: "<dc:description[^>]*>(.*?)</dc:description>", maxMatches: 1).first {
                chunks.append(desc)
            }
        }

        let chapterEntries = entries.filter {
            let lower = $0.lowercased()
            return (lower.hasSuffix(".xhtml") || lower.hasSuffix(".html") || lower.hasSuffix(".htm")) &&
                !lower.contains("nav") && !lower.contains("toc")
        }
        if !chapterEntries.isEmpty,
           let chapHtml = unzipEntryText(path: path, entries: Array(chapterEntries.prefix(2)), maxBytes: 98_304) {
            let body = stripMarkupTags(chapHtml)
            if !body.isEmpty { chunks.append(body) }
        }
        let preview = chunks.isEmpty ? nil : truncateClean(chunks.joined(separator: "\n"), maxChars: 2200)
        return (title, authors, subject, preview)
    }

    private static func extractIWorkPreview(path: String) -> (ocr: String?, tags: [String]) {
        let entries = listZipEntries(path: path, maxEntries: 80)
        guard let previewEntry = entries.first(where: {
            let l = $0.lowercased()
            return l.hasSuffix("preview.jpg") || l.hasSuffix("preview-micro.jpg") || l.hasSuffix("thumbnail.jpg")
        }),
        let imgData = runCommandCapture(executable: "/usr/bin/unzip", arguments: ["-p", path, previewEntry], maxBytes: 4_194_304),
        !imgData.isEmpty,
        let src = CGImageSourceCreateWithData(imgData as CFData, nil),
        let cgImg = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            return (nil, [])
        }
        return runVision(on: cgImg)
    }

    private static func extractTextFile(url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 65_536), !data.isEmpty else { return nil }
        let raw = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        if raw.isEmpty { return nil }
        if raw.count <= 2200 { return truncateClean(raw, maxChars: 2200) }

        let importantMarkers = ["Betaflight", "board_name", "manufacturer_id", "craft_name", "feature ", "serial "]
        let extraHits = raw
            .components(separatedBy: .newlines)
            .filter { line in importantMarkers.contains(where: { line.contains($0) }) }
            .prefix(10)
            .joined(separator: "\n")
        let combined = extraHits.isEmpty ? raw : (extraHits + "\n" + raw)
        return truncateClean(combined, maxChars: 2200)
    }

    private static func extractBlackboxHeaders(url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 8192), !data.isEmpty else { return nil }
        let ascii = String(decoding: data, as: UTF8.self)
        let headerLines = ascii.components(separatedBy: .newlines).filter { $0.hasPrefix("H ") }.prefix(15)
        return headerLines.isEmpty ? nil : truncateClean(headerLines.joined(separator: "\n"))
    }

    private static func extractStlHeader(url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 256), !data.isEmpty else { return nil }
        let head = String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: "\0", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let printable = head.unicodeScalars.filter { $0.value >= 32 && $0.value < 127 }
        let str = String(String.UnicodeScalarView(printable)).trimmingCharacters(in: .whitespaces)
        return str.count >= 4 ? truncateClean(str, maxChars: 200) : nil
    }

    private static func inspectImpl(path: String) -> FileXRayData {
        let url = URL(fileURLWithPath: path)
        let filename = url.lastPathComponent
        let ext = url.pathExtension.lowercased()
        let attrs = (try? FileManager.default.attributesOfItem(atPath: path)) ?? [:]
        let sizeBytes = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        let uti = ext.isEmpty ? nil : UTType(filenameExtension: ext)?.identifier

        var whereFroms: [String] = []
        var spotlightTitle: String?
        var authors: [String] = []
        var subject: String?
        var pageCount: Int?
        var spotlightText: String?
        var durationSeconds: Double?
        var widthPx: Int?
        var heightPx: Int?

        if let mdItem = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL) {
            if let urls = MDItemCopyAttribute(mdItem, kMDItemWhereFroms) as? [String] {
                whereFroms = urls.filter { !$0.isEmpty }
            }
            spotlightTitle = MDItemCopyAttribute(mdItem, kMDItemTitle) as? String
            if let mdAuthors = MDItemCopyAttribute(mdItem, kMDItemAuthors) as? [String] {
                authors = mdAuthors.filter { !$0.isEmpty }
            }
            subject = MDItemCopyAttribute(mdItem, kMDItemSubject) as? String
            pageCount = MDItemCopyAttribute(mdItem, kMDItemNumberOfPages) as? Int
            spotlightText = MDItemCopyAttribute(mdItem, kMDItemTextContent) as? String
            durationSeconds = MDItemCopyAttribute(mdItem, kMDItemDurationSeconds) as? Double
            widthPx = MDItemCopyAttribute(mdItem, kMDItemPixelWidth) as? Int
            heightPx = MDItemCopyAttribute(mdItem, kMDItemPixelHeight) as? Int
        }
        if whereFroms.isEmpty {
            whereFroms = readXattrStrings(path: path, name: "com.apple.metadata:kMDItemWhereFroms")
        }

        var visionTags: [String] = []
        var archiveEntries: [String] = []
        var method: String?
        var textPreview: String?

        if ext == "pdf" {
            if let pdf = extractPDF(url: url) {
                method = pdf.method
                textPreview = pdf.text
                visionTags = pdf.tags
                pageCount = pdf.pageCount
                if spotlightTitle == nil { spotlightTitle = pdf.title }
                if authors.isEmpty { authors = pdf.authors }
                if subject == nil { subject = pdf.subject }
            }
        } else if imageExtensions.contains(ext) {
            if let src = CGImageSourceCreateWithURL(url as CFURL, nil),
               let cgImg = CGImageSourceCreateImageAtIndex(src, 0, nil) {
                if widthPx == nil { widthPx = cgImg.width }
                if heightPx == nil { heightPx = cgImg.height }
                let res = runVision(on: cgImg)
                method = "apple_vision_ocr"
                textPreview = res.ocr
                visionTags = res.tags
            }
        } else if textutilExtensions.contains(ext) {
            method = "office_textutil"
            if let data = runCommandCapture(executable: "/usr/bin/textutil", arguments: ["-convert", "txt", "-stdout", path], maxBytes: 65_536),
               let raw = String(data: data, encoding: .utf8) {
                let cleaned = truncateClean(raw, maxChars: 2200)
                textPreview = cleaned.isEmpty ? nil : cleaned
            }
        } else if ext == "pptx" {
            let pptx = extractPptx(path: path)
            method = "pptx_slides"
            if pageCount == nil { pageCount = pptx.slideCount }
            textPreview = pptx.text
        } else if ext == "xlsx" {
            let xlsx = extractXlsx(path: path)
            method = "xlsx_sheets"
            if pageCount == nil { pageCount = xlsx.sheetCount }
            textPreview = xlsx.text
        } else if ext == "epub" {
            let epub = extractEpub(path: path)
            method = "epub_content"
            if spotlightTitle == nil { spotlightTitle = epub.title }
            if authors.isEmpty { authors = epub.authors }
            if subject == nil { subject = epub.subject }
            textPreview = epub.text
        } else if iworkExtensions.contains(ext) {
            if let spText = spotlightText, !spText.isEmpty {
                method = "spotlight_text"
                textPreview = truncateClean(spText, maxChars: 2200)
            } else {
                let preview = extractIWorkPreview(path: path)
                method = preview.ocr != nil ? "iwork_vision_ocr" : nil
                textPreview = preview.ocr
                visionTags = preview.tags
            }
        } else if textExtensions.contains(ext) {
            method = "text_head"
            if ext == "html" || ext == "htm" {
                if let raw = extractTextFile(url: url) {
                    textPreview = truncateClean(stripMarkupTags(raw), maxChars: 2200)
                }
            } else {
                textPreview = extractTextFile(url: url)
            }
        } else if ext == "bbl" || ext == "bfl" {
            method = "blackbox_header"
            textPreview = extractBlackboxHeaders(url: url)
        } else if ext == "zip" || ext == "3mf" {
            method = "zip_manifest"
            archiveEntries = Array(listZipEntries(path: path, maxEntries: 25))
        } else if ext == "stl" {
            method = "stl_header"
            textPreview = extractStlHeader(url: url)
        } else if ["mp4", "mov", "mkv"].contains(ext) {
            let base = url.deletingPathExtension().path
            for srtCandidate in [base + ".srt", base + ".SRT"] {
                if FileManager.default.fileExists(atPath: srtCandidate) {
                    method = "video_sidecar_srt"
                    textPreview = extractTextFile(url: URL(fileURLWithPath: srtCandidate))
                    break
                }
            }
        } else if let spText = spotlightText, !spText.isEmpty {
            method = "spotlight_text"
            textPreview = truncateClean(spText, maxChars: 2200)
        }

        let dimensions = (widthPx != nil && heightPx != nil) ? "\(widthPx!)x\(heightPx!)" : nil

        return FileXRayData(
            path: path,
            filename: filename,
            ext: ext,
            sizeBytes: sizeBytes,
            uti: uti,
            downloadedFrom: whereFroms,
            spotlightTitle: spotlightTitle,
            authors: authors,
            subject: subject,
            pageCount: pageCount,
            durationSeconds: durationSeconds,
            dimensions: dimensions,
            visionTags: visionTags,
            archiveEntries: archiveEntries,
            extractionMethod: method,
            textPreview: textPreview
        )
    }
}
