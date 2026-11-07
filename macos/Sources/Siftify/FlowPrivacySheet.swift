import AppKit
import SwiftUI

struct FlowPrivacyOverlay: View {
    @Bindable var store: FlowStore
    let onClose: () -> Void

    private let emerald = Color(red: 0.18, green: 0.86, blue: 0.58)
    private let cyan = Color(red: 0.24, green: 0.78, blue: 0.96)

    var body: some View {
        ZStack {
            Color.black.opacity(0.54)
                .ignoresSafeArea()
                .onTapGesture {
                    onClose()
                }

            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(emerald.opacity(0.20))
                            .frame(width: 48, height: 48)
                            .overlay(
                                Circle()
                                    .strokeBorder(emerald.opacity(0.55), lineWidth: 1.2)
                            )
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(emerald)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("100% Running on Your Mac")
                            .font(.system(size: 19, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("Zero cloud servers, zero internet used while sorting, zero file uploads.")
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
                }

                Divider()
                    .overlay(Color.white.opacity(0.10))

                VStack(spacing: 10) {
                    guaranteeRow(
                        icon: "cpu.fill",
                        color: cyan,
                        title: "Powered by Your \(store.localChipName)",
                        detail: "Every PDF, screenshot, invoice, and document is inspected directly on your Mac’s built-in processor and Neural Engine."
                    )

                    guaranteeRow(
                        icon: "wifi.slash",
                        color: emerald,
                        title: "Works Completely Offline",
                        detail: "The bundled organizer runs strictly in offline mode on your Mac (127.0.0.1 loopback only). You can turn Wi-Fi off completely and sort any folder."
                    )

                    guaranteeRow(
                        icon: "hand.raised.fill",
                        color: Color(red: 0.62, green: 0.56, blue: 0.98),
                        title: "Only Opens Folders You Pick",
                        detail: "Siftify waits until you explicitly choose or drop a folder, previews every move first, and keeps a 1-click Undo receipt locally on your disk."
                    )
                }

                Divider()
                    .overlay(Color.white.opacity(0.10))

                HStack {
                    if store.modelState.isInstalled {
                        Button {
                            store.revealModelInFinder()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "folder")
                                    .font(.system(size: 11.5, weight: .semibold))
                                Text("Show Offline AI File on This Mac")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(TranslucentGlassButtonStyle())
                    }

                    Spacer()

                    Button {
                        onClose()
                    } label: {
                        Text("Got It")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .padding(.horizontal, 22)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(GlowActionButtonStyle(accent: emerald, secondaryAccent: cyan))
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
            .frame(width: 560)
            .glassSurface(
                cornerRadius: 26,
                tint: emerald,
                tintOpacity: 0.05,
                borderOpacity: 0.36,
                isHighlighted: true
            )
            .padding(24)
        }
    }

    private func guaranteeRow(icon: String, color: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(color.opacity(0.18))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(color)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.66))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }

            Spacer(minLength: 0)
        }
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(Color.white.opacity(0.045))
                .overlay(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.09), lineWidth: 1)
                )
        )
    }
}
