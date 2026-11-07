import AppKit
import CoreGraphics
import Darwin
import Foundation

let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func setWhereFroms(path: String, urls: [String]) {
    guard let data = try? PropertyListSerialization.data(fromPropertyList: urls, format: .binary, options: 0) else {
        return
    }
    _ = data.withUnsafeBytes { ptr in
        setxattr(path, "com.apple.metadata:kMDItemWhereFroms", ptr.baseAddress, data.count, 0, 0)
    }
}

func renderTextPNG(to url: URL, lines: [String]) throws {
    let width = 1000
    let height = 520
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .calibratedRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    NSColor.white.setFill()
    NSBezierPath.fill(NSRect(x: 0, y: 0, width: width, height: height))

    let titleAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.boldSystemFont(ofSize: 30),
        .foregroundColor: NSColor.black
    ]
    let bodyAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 22, weight: .medium),
        .foregroundColor: NSColor.darkGray
    ]

    var y = CGFloat(height - 70)
    for (idx, line) in lines.enumerated() {
        let attrs = idx == 0 ? titleAttrs : bodyAttrs
        (line as NSString).draw(at: NSPoint(x: 44, y: y), withAttributes: attrs)
        y -= idx == 0 ? 54 : 42
    }

    NSGraphicsContext.restoreGraphicsState()
    let pngData = rep.representation(using: .png, properties: [:])!
    try pngData.write(to: url)
}

func renderSimplePDF(to url: URL, text: String) throws {
    var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
    guard let consumer = CGDataConsumer(url: url as CFURL),
          let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
        return
    }
    ctx.beginPDFPage(nil)
    let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = nsCtx

    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 16),
        .foregroundColor: NSColor.black
    ]
    (text as NSString).draw(in: NSRect(x: 50, y: 100, width: 512, height: 640), withAttributes: attrs)

    NSGraphicsContext.restoreGraphicsState()
    ctx.endPDFPage()
    ctx.closePDF()
}

// 1. Generic filename screenshot -> Apple Vision OCR reads BetaFPV AIO pinout!
try renderTextPNG(
    to: outDir.appendingPathComponent("CleanShot 2026-11-03 at 22.14.08.png"),
    lines: [
        "BETAFPV Matrix 1S Brushless Flight Controller",
        "5IN1 AIO Wiring & Pinout Diagram",
        "Pads: VBAT  GND  5V  CAM  VTX  RX1  TX1 (ELRS 2.4G)",
        "ESC: Bluejay 48kHz Bi-Directional DShot300",
        "Motor Connectors: JST-1.25 3-Pin (M1 M2 M3 M4)"
    ]
)

// 2. Generic IMG_9042.png -> Apple Vision OCR reads Stripe Invoice!
try renderTextPNG(
    to: outDir.appendingPathComponent("IMG_9042.png"),
    lines: [
        "INVOICE & PAYMENT RECEIPT #INV-2026-8841",
        "Billed To: Acme Studio LLC",
        "Item: Cloudflare Pro Plan Subscription (Monthly)",
        "Amount Paid: $25.00 USD — Paid via Visa *4242",
        "Date Paid: November 3, 2026"
    ]
)

// 3. Generic scan_02.pdf -> PDFKit extracts lease guide text
try renderSimplePDF(
    to: outDir.appendingPathComponent("scan_02.pdf"),
    text: """
    APARTMENT LEASE RENEWAL & TENANT HANDBOOK (2026-2027)

    Section 1: Quiet Hours, Building Access, and Maintenance Requests.
    Tenants shall submit non-emergency plumbing or appliance repair requests
    through the resident portal at least 48 hours in advance.
    """
)

// 4. Betaflight CLI dump text file
let btfl = """
# version
# Betaflight / STM32F411 (S411) 4.5.1 Oct 12 2026 / 14:02:11 (norevision) MSP API: 1.46
board_name BETAFPVF411
manufacturer_id BFPV
set craft_name = Air65_Freestyle
set dshot_bidir = ON
set motor_poles = 12
save
"""
try btfl.write(to: outDir.appendingPathComponent("BTFL_cli_20261103.txt"), atomically: true, encoding: .utf8)

// 5. Terrible filename "download (4).stl" rescued by macOS kMDItemWhereFroms xattr!
let stlPath = outDir.appendingPathComponent("download (4).stl")
try "solid canopy_mount\nendsolid canopy_mount\n".write(to: stlPath, atomically: true, encoding: .utf8)
setWhereFroms(
    path: stlPath.path,
    urls: ["https://www.printables.com/model/991204-lightweight-tpu-canopy-mount-stl"]
)

// 6. macOS .dmg installer
let dmgPath = outDir.appendingPathComponent("Raycast_v1.88.2_universal.dmg")
try Data("fake-dmg-header".utf8).write(to: dmgPath)
setWhereFroms(path: dmgPath.path, urls: ["https://releases.raycast.com/download"])

// 7. Deliberately vague mystery scratch file -> should trigger mathematical DEFER!
try "maybe check tuesday?? idk\n".write(
    to: outDir.appendingPathComponent("misc_untitled.txt"),
    atomically: true,
    encoding: .utf8
)

// 8. Generic arXiv-style PDF -> PDFKit extracts abstract/citations -> Documents/Papers & Books
try renderSimplePDF(
    to: outDir.appendingPathComponent("2610.04821v1.pdf"),
    text: """
    Calibrated Single-Pass Decision Readouts Under Quantized KV Prefixes
    Abstract — Autoregressive decoding incurs O(T) memory-bandwidth reads per decision.
    We evaluate temperature-calibrated log-probability readouts across 12 benchmarks and
    demonstrate selective risk-controlled deferral under distribution shift.
    Keywords: calibration, selective classification, transformer inference, arXiv preprint.
    References: [1] Guo et al., On Calibration of Modern Neural Networks, ICML.
    """
)

// 9. Opaque filename .docx -> extracted via macOS textutil -> Documents/Career & Resumes
let tmpTxt = outDir.appendingPathComponent(".resume_src.txt")
try """
ALEX RIVERA — Staff Systems Engineer
San Francisco, CA | github.com/arivera

EXPERIENCE
Principal Infrastructure Engineer, Horizon Cloud (2022–Present)
- Led Rust & Swift macOS developer tooling across 140 engineers.
EDUCATION
B.S. Computer Science, UC Berkeley
""".write(to: tmpTxt, atomically: true, encoding: .utf8)
let docxOut = outDir.appendingPathComponent("document_final_v3.docx")
let convert = Process()
convert.executableURL = URL(fileURLWithPath: "/usr/bin/textutil")
convert.arguments = ["-convert", "docx", tmpTxt.path, "-output", docxOut.path]
try convert.run()
convert.waitUntilExit()
try? FileManager.default.removeItem(at: tmpTxt)

// 10. Opaque attachment PDF -> PDFKit extracts flight itinerary -> Documents/Tickets & Travel
try renderSimplePDF(
    to: outDir.appendingPathComponent("attachment_04.pdf"),
    text: """
    BOARDING PASS & E-TICKET ITINERARY — BOOKING REF: K9X4MP
    Passenger: RIVERA / ALEX
    Flight UA 901  SFO -> LHR   Departure: 19:25  Gate G9  Seat 14A
    Boarding Group 2 — Present QR barcode at security and boarding gate.
    """
)

print("Generated 10 sample files in \(outDir.path)")
