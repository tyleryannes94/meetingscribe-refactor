#!/usr/bin/env bash
#
# make-appicon.sh — generates Resources/AppIcon.icns (C3-1).
#
# A placeholder-quality but real app icon: the in-app brand mark (coral→lilac
# gradient squircle + white waveform glyph) rendered to all macOS icon sizes.
# Reproducible — re-run after changing the mark. Replace with designed art when
# available; the bundle wiring stays the same.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/Resources/AppIcon.icns"
TMP="$(mktemp -d)"
PNG="$TMP/icon-1024.png"
SWIFT_SRC="$TMP/render.swift"

cat > "$SWIFT_SRC" <<'SWIFT'
import AppKit

let outPath = CommandLine.arguments[1]
let size: CGFloat = 1024

let final = NSImage(size: NSSize(width: size, height: size))
final.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

// Full-bleed squircle tile with a small inset (macOS rounds further at display).
let inset: CGFloat = size * 0.085
let rect = CGRect(x: inset, y: inset, width: size - 2*inset, height: size - 2*inset)
let corner = rect.width * 0.2237
let tile = CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)

ctx.saveGState()
ctx.addPath(tile); ctx.clip()
// Coral → lilac, 135°.
let coral = NSColor(srgbRed: 1.0,  green: 0.569, blue: 0.451, alpha: 1).cgColor
let lilac = NSColor(srgbRed: 0.718, green: 0.612, blue: 1.0,  alpha: 1).cgColor
let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                      colors: [coral, lilac] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(grad,
                       start: CGPoint(x: rect.minX, y: rect.maxY),
                       end:   CGPoint(x: rect.maxX, y: rect.minY),
                       options: [])
ctx.restoreGState()

// White waveform glyph, centered.
if let sym = NSImage(systemSymbolName: "waveform", accessibilityDescription: nil) {
    let conf = NSImage.SymbolConfiguration(pointSize: size * 0.40, weight: .bold)
    if let g = sym.withSymbolConfiguration(conf) {
        let gs = g.size
        let target = size * 0.46
        let scale = target / max(gs.width, gs.height)
        let w = gs.width * scale, h = gs.height * scale
        let r = CGRect(x: (size - w)/2, y: (size - h)/2, width: w, height: h)
        // Tint the template glyph white in its own layer so we don't paint the tile.
        let white = NSImage(size: r.size)
        white.lockFocus()
        g.draw(in: CGRect(origin: .zero, size: r.size))
        NSColor.white.set()
        CGRect(origin: .zero, size: r.size).fill(using: .sourceAtop)
        white.unlockFocus()
        white.draw(in: r)
    }
}

final.unlockFocus()

guard let tiff = final.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("failed to render icon\n".data(using: .utf8)!)
    exit(1)
}
try! png.write(to: URL(fileURLWithPath: outPath))
SWIFT

echo "→ rendering 1024px master"
swift "$SWIFT_SRC" "$PNG"

ICONSET="$TMP/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
    sips -z "$s" "$s"   "$PNG" --out "$ICONSET/icon_${s}x${s}.png"    >/dev/null
    d=$((s * 2))
    sips -z "$d" "$d"   "$PNG" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$OUT"
echo "→ wrote $OUT"
rm -rf "$TMP"
