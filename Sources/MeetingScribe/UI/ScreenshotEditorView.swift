import SwiftUI
import AppKit

/// Lightweight Mac-screenshot-tool-style editor: shows a captured image, lets
/// the user draw freeform strokes or rectangles over it in the accent color,
/// then save a flattened PNG to `<storageDir>/Screenshots/<timestamp>/` and/or
/// copy it to the clipboard. (MVP markup — richer tools can grow later.)
@available(macOS 14.0, *)
struct ScreenshotEditorView: View {
    let image: CGImage
    var onSaved: () -> Void = {}
    @Environment(\.dismiss) private var dismiss

    enum Tool: String, CaseIterable { case pen = "Pen", rect = "Box" }
    struct Mark: Identifiable { let id = UUID(); var points: [CGPoint]; var isRect: Bool }

    @State private var tool: Tool = .pen
    @State private var marks: [Mark] = []
    @State private var current: Mark?
    @State private var savedNote: String?

    private var pixelSize: CGSize { CGSize(width: image.width, height: image.height) }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().overlay(NDS.divider)
            GeometryReader { geo in
                let fit = fittedRect(in: geo.size)
                ZStack {
                    Image(decorative: image, scale: 1)
                        .resizable().interpolation(.high)
                        .frame(width: fit.width, height: fit.height)
                    markupCanvas(displaySize: fit).frame(width: fit.width, height: fit.height)
                        .contentShape(Rectangle())
                        .gesture(drawGesture(displaySize: fit))
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .frame(minWidth: 480, minHeight: 320)
            .background(NDS.bg)
            Divider().overlay(NDS.divider)
            footer
        }
        .frame(minWidth: 560, minHeight: 460)
        .background(NDS.bg)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Text("Screenshot").scaledFont(15, weight: .bold)
            Picker("", selection: $tool) {
                ForEach(Tool.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).fixedSize() // design-lint:allow
            Button { if !marks.isEmpty { marks.removeLast() } } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(MSTertiaryButtonStyle()).disabled(marks.isEmpty)
            Spacer()
        }
        .padding(12)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let note = savedNote {
                Label(note, systemImage: "checkmark.circle.fill").scaledFont(11).foregroundStyle(NDS.mint)
            }
            Spacer()
            Button("Copy") { copyToClipboard() }.buttonStyle(MSSecondaryButtonStyle())
            Button("Save") { save() }.buttonStyle(MSPrimaryButtonStyle())
            Button("Done") { dismiss() }.buttonStyle(MSTertiaryButtonStyle())
        }
        .padding(12)
    }

    @ViewBuilder
    private func markupCanvas(displaySize: CGSize) -> some View {
        Canvas { ctx, _ in
            let scale = displaySize.width / pixelSize.width
            for mark in marks + (current.map { [$0] } ?? []) {
                var path = Path()
                if mark.isRect, let a = mark.points.first, let b = mark.points.last {
                    path.addRect(CGRect(x: min(a.x, b.x) * scale, y: min(a.y, b.y) * scale,
                                        width: abs(b.x - a.x) * scale, height: abs(b.y - a.y) * scale))
                } else if let first = mark.points.first {
                    path.move(to: CGPoint(x: first.x * scale, y: first.y * scale))
                    for p in mark.points.dropFirst() { path.addLine(to: CGPoint(x: p.x * scale, y: p.y * scale)) }
                }
                ctx.stroke(path, with: .color(NDS.accent), lineWidth: 3)
            }
        }
    }

    private func drawGesture(displaySize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let scale = pixelSize.width / displaySize.width
                let p = CGPoint(x: value.location.x * scale, y: value.location.y * scale)
                if current == nil { current = Mark(points: [p], isRect: tool == .rect) }
                else if tool == .rect { current?.points = [current!.points[0], p] }
                else { current?.points.append(p) }
            }
            .onEnded { _ in
                if let c = current { marks.append(c) }
                current = nil
            }
    }

    private func fittedRect(in size: CGSize) -> CGSize {
        let scale = min(size.width / pixelSize.width, size.height / pixelSize.height, 1)
        return CGSize(width: pixelSize.width * scale, height: pixelSize.height * scale)
    }

    // MARK: - Flatten + persist

    /// Renders the image + marks to a flattened CGImage at full pixel size.
    private func flatten() -> CGImage? {
        let view = ZStack {
            Image(decorative: image, scale: 1).resizable()
                .frame(width: pixelSize.width, height: pixelSize.height)
            markupCanvas(displaySize: pixelSize)
                .frame(width: pixelSize.width, height: pixelSize.height)
        }
        .frame(width: pixelSize.width, height: pixelSize.height)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        return renderer.cgImage
    }

    private func copyToClipboard() {
        guard let cg = flatten() else { return }
        let rep = NSBitmapImageRep(cgImage: cg)
        let img = NSImage(size: NSSize(width: cg.width, height: cg.height))
        img.addRepresentation(rep)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([img])
        savedNote = "Copied to clipboard"
    }

    private func save() {
        let dir = AppSettings.shared.storageDir
            .appendingPathComponent("Screenshots", isDirectory: true)
            .appendingPathComponent(stamp(), isDirectory: true)
        ScreenshotCapturer.writePNG(image, to: dir.appendingPathComponent("image.png"))
        if !marks.isEmpty, let flat = flatten() {
            ScreenshotCapturer.writePNG(flat, to: dir.appendingPathComponent("annotated.png"))
        }
        savedNote = "Saved"
        onSaved()
    }

    private func stamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return "Shot-\(f.string(from: Date()))"
    }
}
