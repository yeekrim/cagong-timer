import AppKit
import CoreGraphics

/// 음료 누끼 사진으로 앱 아이콘(.icns)을 만든다.
///
/// 누끼 이미지를 그대로 쓴다 — 바탕 타일도, 그라디언트도, 그림자도 없다.
/// 배경은 투명하게 둔다.
///
/// 다만 음료 PNG는 잔이 캔버스 아래쪽에 붙어 있어서(김 자리를 위에 비워둔 규격)
/// 그대로 넣으면 아이콘에서 아래로 치우친다. 알파 경계를 다시 재서 잔만
/// 잘라내고 가운데에 놓는다.
///
///   swiftc -parse-as-library -target arm64-apple-macos14.0 -o makeicon Tools/MakeIcon.swift
///   ./makeicon Sources/Cagong/Resources/Drinks/matcha-latte.png Sources/Cagong/Resources
@main
struct MakeIcon {

    static let canvas: CGFloat = 1024

    /// 잔이 캔버스에서 차지하는 비율. 가장자리에 딱 붙지 않을 만큼만 남긴다.
    static let fillRatio: CGFloat = 0.94

    static func main() {
        let args = CommandLine.arguments
        guard args.count > 2 else {
            print("사용법: makeicon <음료PNG> <출력디렉터리>")
            return
        }
        let sourcePath = args[1]
        let outDir = args[2]

        guard
            let image = NSImage(contentsOfFile: sourcePath),
            let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            print("✗ 음료 사진을 읽지 못했습니다: \(sourcePath)")
            return
        }

        guard
            let bounds = alphaBounds(cg),
            let drink = cg.cropping(to: bounds),
            let icon = compose(drink)
        else {
            print("✗ 아이콘 합성 실패")
            return
        }

        // .iconset 폴더를 만들고 iconutil로 .icns로 굽는다.
        let iconset = "\(outDir)/AppIcon.iconset"
        try? FileManager.default.removeItem(atPath: iconset)
        try? FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)

        // (한 변, 파일명)
        let variants: [(Int, String)] = [
            (16, "icon_16x16.png"),      (32, "icon_16x16@2x.png"),
            (32, "icon_32x32.png"),      (64, "icon_32x32@2x.png"),
            (128, "icon_128x128.png"),   (256, "icon_128x128@2x.png"),
            (256, "icon_256x256.png"),   (512, "icon_256x256@2x.png"),
            (512, "icon_512x512.png"),   (1024, "icon_512x512@2x.png"),
        ]

        for (side, name) in variants {
            guard
                let scaled = resize(icon, to: side),
                let png = NSBitmapImageRep(cgImage: scaled).representation(using: .png, properties: [:])
            else { print("✗ \(name)"); continue }
            try? png.write(to: URL(fileURLWithPath: "\(iconset)/\(name)"))
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        task.arguments = ["-c", "icns", iconset, "-o", "\(outDir)/AppIcon.icns"]
        try? task.run()
        task.waitUntilExit()

        if task.terminationStatus == 0 {
            try? FileManager.default.removeItem(atPath: iconset)
            print("✓ \(outDir)/AppIcon.icns")
        } else {
            print("✗ iconutil 실패 (\(task.terminationStatus))")
        }
    }

    // MARK: 합성

    /// 잘라낸 잔을 투명한 정사각 캔버스 가운데에 놓는다. 그 외에는 아무것도 하지 않는다.
    static func compose(_ drink: CGImage) -> CGImage? {
        guard let ctx = CGContext(
            data: nil,
            width: Int(canvas), height: Int(canvas),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.interpolationQuality = .high
        ctx.clear(CGRect(x: 0, y: 0, width: canvas, height: canvas))

        let dw = CGFloat(drink.width), dh = CGFloat(drink.height)
        let box = canvas * fillRatio
        let scale = min(box / dw, box / dh)
        let w = dw * scale, h = dh * scale

        ctx.draw(drink, in: CGRect(
            x: (canvas - w) / 2,
            y: (canvas - h) / 2,
            width: w,
            height: h
        ))

        return ctx.makeImage()
    }

    static func resize(_ image: CGImage, to side: Int) -> CGImage? {
        guard let ctx = CGContext(
            data: nil, width: side, height: side,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .high
        ctx.clear(CGRect(x: 0, y: 0, width: side, height: side))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        return ctx.makeImage()
    }

    // MARK: 알파 경계

    static func alphaBounds(_ image: CGImage, threshold: UInt8 = 8) -> CGRect? {
        let w = image.width, h = image.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)

        guard let ctx = CGContext(
            data: &pixels, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            let row = y * w * 4
            for x in 0..<w where pixels[row + x * 4 + 3] > threshold {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}
