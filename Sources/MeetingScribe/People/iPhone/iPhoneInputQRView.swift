import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import AppKit

/// Phase 7-B (Option 1) UI: starts the local input server and shows a QR code
/// the user scans from their iPhone camera to open the add-person form. QR is
/// generated with CoreImage's `CIQRCodeGenerator` — no library needed.
@available(macOS 14.0, *)
struct iPhoneInputQRView: View {
    @StateObject private var service = iPhoneInputService()

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add via iPhone").font(.headline)
                    Text("Scan from your iPhone's camera to open the People entry form.")
                        .font(NDS.tiny).foregroundStyle(NDS.textSecondary)
                }
                Spacer()
                Toggle(isOn: Binding(
                    get: { service.isRunning },
                    set: { $0 ? service.start() : service.stop() }
                )) {
                    Text(service.isRunning ? "Server On" : "Server Off")
                }
                .toggleStyle(.switch)
            }

            if service.isRunning {
                if let url = service.formURL {
                    qrCode(for: url)
                    HStack(spacing: 6) {
                        Image(systemName: "link").foregroundStyle(NDS.textTertiary)
                        Text(url).font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(url, forType: .string)
                        } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.borderless).help("Copy URL")
                    }
                    .padding(8)
                    .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: NDS.radius))

                    HStack(spacing: 14) {
                        Label("\(service.connectionCount) connected", systemImage: "iphone.gen3")
                        Label("\(service.addedCount) added", systemImage: "person.badge.plus")
                        if let last = service.lastAdded {
                            Text("Last: \(last)").foregroundStyle(NDS.textSecondary)
                        }
                    }
                    .font(NDS.tiny).foregroundStyle(NDS.textTertiary)
                } else {
                    ProgressView("Starting server…").controlSize(.small)
                }
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "qrcode").font(.system(size: 40)).foregroundStyle(.secondary)
                    Text("Turn the server on to show a QR code.")
                        .font(NDS.tiny).foregroundStyle(NDS.textTertiary)
                    Text("Your iPhone must be on the same Wi-Fi network.")
                        .font(NDS.tiny).foregroundStyle(NDS.textTertiary)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 12)
            }
        }
        .padding(14)
        .background(NDS.fieldBg, in: RoundedRectangle(cornerRadius: 10))
        .onDisappear { service.stop() }
    }

    @ViewBuilder
    private func qrCode(for url: String) -> some View {
        if let image = Self.qrImage(from: url) {
            Image(nsImage: image)
                .interpolation(.none)
                .resizable()
                .frame(width: 200, height: 200)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            Color.clear.frame(height: 1)
        }
    }

    /// Renders a QR code for `string` into an `NSImage`.
    static func qrImage(from string: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let context = CIContext()
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: scaled.extent.width, height: scaled.extent.height))
    }
}
