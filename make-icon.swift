import AppKit
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = root.appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for pixels in [16, 32, 64, 128, 256, 512, 1024] {
    let image = NSImage(size: NSSize(width: pixels, height: pixels))
    image.lockFocus()
    let scale = CGFloat(pixels) / 1024
    let t = NSAffineTransform(); t.scale(by: scale); t.concat()
    NSColor(calibratedRed: 0.12, green: 0.25, blue: 0.48, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 50, y: 50, width: 924, height: 924), xRadius: 205, yRadius: 205).fill()
    for col in 0..<5 {
        for row in 0..<5 {
            let opacities: [CGFloat] = [0.15, 0.3, 0.5, 0.75, 1]
            NSColor(calibratedRed: 0.52, green: 0.91, blue: 0.72, alpha: opacities[(col + row * 2) % 5]).setFill()
            NSBezierPath(roundedRect: NSRect(x: 200 + col * 132, y: 200 + row * 132, width: 99, height: 99), xRadius: 18, yRadius: 18).fill()
        }
    }
    image.unlockFocus()
    let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
    let data = bitmap.representation(using: .png, properties: [:])!
    if pixels <= 512 && pixels != 64 { try data.write(to: iconset.appendingPathComponent("icon_\(pixels)x\(pixels).png")) }
    if pixels >= 32 { let logical = pixels / 2; try data.write(to: iconset.appendingPathComponent("icon_\(logical)x\(logical)@2x.png")) }
}
let task = Process(); task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("AppIcon.icns").path]
try task.run(); task.waitUntilExit()
if task.terminationStatus != 0 { exit(task.terminationStatus) }
