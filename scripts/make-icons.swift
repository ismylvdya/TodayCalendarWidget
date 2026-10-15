// Готовит иконки из исходников в Icons/:
//   icon-ios.png                → icon-macos.png (форма macOS: скругление, поля, тень)
//   icon-ios-tinted-source.png  → icon-ios-tinted.png (инверсия: светлый значок на чёрном)
import AppKit
import CoreImage

func load(_ path: String) -> CGImage {
    let img = NSImage(contentsOfFile: path)!
    var r = CGRect(origin: .zero, size: img.size)
    return img.cgImage(forProposedRect: &r, context: nil, hints: nil)!
}

func save(_ image: CGImage, _ path: String) {
    try! NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: path))
}

func context() -> CGContext {
    CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

let dir = CommandLine.arguments[1]

// macOS: шаблон Apple — тело 824×824 в холсте 1024, радиус ≈ 185, мягкая тень снизу.
let mac = context()
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let shape = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
mac.saveGState()
mac.setShadow(offset: CGSize(width: 0, height: -10), blur: 20, color: CGColor(gray: 0, alpha: 0.3))
mac.addPath(shape); mac.setFillColor(CGColor(gray: 1, alpha: 1)); mac.fillPath()
mac.restoreGState()
mac.addPath(shape); mac.clip()
mac.draw(load("\(dir)/icon-ios.png"), in: body)
save(mac.makeImage()!, "\(dir)/icon-macos.png")

// iOS Tinted: система красит светлое, поэтому чёрный значок на белом инвертируется.
let inverted = CIImage(cgImage: load("\(dir)/icon-ios-tinted-source.png")).applyingFilter("CIColorInvert")
let tinted = CIContext().createCGImage(inverted, from: CGRect(x: 0, y: 0, width: 1024, height: 1024))!
let flat = context()
flat.draw(tinted, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
save(flat.makeImage()!, "\(dir)/icon-ios-tinted.png")
