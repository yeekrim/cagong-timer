import AppKit
import CoreGraphics

/// 음료 누끼 PNG를 같은 규격으로 맞춘다.
///
/// 사진마다 여백과 비율이 달라서 그대로 쓰면 잔이 화면에서 조금씩 다른 높이에 놓인다.
/// 그래서 세 단계를 거친다.
///   1. 알파가 있는 실제 영역만 잘라낸다 (투명 여백 제거)
///   2. 정해진 내용 영역에 맞게 축소한다
///   3. 정사각 캔버스에 가로 중앙·세로 하단으로 얹는다 (모든 잔이 같은 바닥에 놓인다)
///
/// 결과가 전부 같은 크기의 정사각형이므로, 앱은 위치 계산 없이 그대로 그리면 된다.
/// 캔버스 위쪽 여백은 김이 올라올 자리다.
///
///   swiftc -parse-as-library -target arm64-apple-macos14.0 -o normalize Tools/NormalizeDrinks.swift
///   ./normalize Sources/Cagong/Resources/Drinks
@main
struct NormalizeDrinks {

    /// 정사각 캔버스 한 변
    static let canvas = 640

    /// 잔이 들어갈 높이. 남는 위쪽은 김 자리로 비워둔다.
    static let contentHeight = 516

    /// 바닥에서 띄우는 여백
    static let bottomInset = 6

    static func main() {
        let dir = CommandLine.arguments.count > 1
            ? CommandLine.arguments[1]
            : "Sources/Cagong/Resources/Drinks"

        let files = ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [])
            .filter { $0.lowercased().hasSuffix(".png") }
            .sorted()

        guard !files.isEmpty else {
            print("✗ \(dir) 에 PNG가 없습니다")
            return
        }

        for file in files {
            let path = "\(dir)/\(file)"
            guard
                let image = NSImage(contentsOfFile: path),
                let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
            else {
                print("✗ \(file): 읽기 실패")
                continue
            }

            guard let bounds = alphaBounds(source) else {
                print("✗ \(file): 불투명한 영역이 없습니다")
                continue
            }

            guard
                let cropped = source.cropping(to: bounds),
                let output = compose(cropped)
            else {
                print("✗ \(file): 합성 실패")
                continue
            }

            guard
                let png = NSBitmapImageRep(cgImage: output).representation(using: .png, properties: [:])
            else {
                print("✗ \(file): 인코딩 실패")
                continue
            }

            do {
                try png.write(to: URL(fileURLWithPath: path))
                print("✓ \(file)  \(source.width)x\(source.height)"
                      + " → 내용 \(Int(bounds.width))x\(Int(bounds.height))"
                      + " → 캔버스 \(canvas)x\(canvas)")
            } catch {
                print("✗ \(file): 쓰기 실패 \(error.localizedDescription)")
            }
        }
    }

    // MARK: 알파 경계

    /// 알파가 살아 있는 픽셀의 최소 사각형. 좌표는 좌상단 기준(CGImage.cropping과 같은 공간).
    static func alphaBounds(_ image: CGImage, threshold: UInt8 = 8) -> CGRect? {
        let w = image.width, h = image.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)

        guard let ctx = CGContext(
            data: &pixels,
            width: w, height: h,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
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

    // MARK: 합성

    /// 잘라낸 잔을 정사각 캔버스의 가로 중앙·세로 하단에 얹는다.
    static func compose(_ drink: CGImage) -> CGImage? {
        guard let ctx = CGContext(
            data: nil,
            width: canvas, height: canvas,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.interpolationQuality = .high
        ctx.clear(CGRect(x: 0, y: 0, width: canvas, height: canvas))

        let dw = CGFloat(drink.width), dh = CGFloat(drink.height)
        let scale = min(CGFloat(canvas) / dw, CGFloat(contentHeight) / dh)
        let tw = dw * scale, th = dh * scale

        // CGContext는 좌하단 원점이므로 y에 bottomInset을 그대로 쓴다.
        let rect = CGRect(
            x: (CGFloat(canvas) - tw) / 2,
            y: CGFloat(bottomInset),
            width: tw,
            height: th
        )
        ctx.draw(drink, in: rect)

        return ctx.makeImage()
    }
}
