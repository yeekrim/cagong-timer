import AppKit
import CoreGraphics

/// 배경 사진을 같은 규격으로 맞춘다.
///
/// 사진마다 비율이 다르면(4:3 vs 3:2) 화면을 채울 때 잘려 나가는 양이 달라져서,
/// 장면을 넘길 때 확대율이 튀는 것처럼 보인다. 가운데를 기준으로 같은 비율로
/// 잘라내고 같은 크기로 줄여, 어느 장면이든 같은 방식으로 담기게 한다.
///
/// 비율은 16:10을 쓴다. 기본 창(약 1.37)보다 넓으므로 창을 채울 때 가로만
/// 잘린다 — 하늘이나 주요 피사체가 있는 위아래를 지키는 쪽이 덜 파괴적이다.
///
///   swiftc -parse-as-library -target arm64-apple-macos14.0 -o normalizebg Tools/NormalizeBackgrounds.swift
///   ./normalizebg Sources/Cagong/Resources/Backgrounds
@main
struct NormalizeBackgrounds {

    static let targetWidth = 1600
    static let targetHeight = 1000
    static let quality: CGFloat = 0.72

    static var targetAspect: CGFloat { CGFloat(targetWidth) / CGFloat(targetHeight) }

    static func main() {
        let dir = CommandLine.arguments.count > 1
            ? CommandLine.arguments[1]
            : "Sources/Cagong/Resources/Backgrounds"

        let files = ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [])
            .filter { ["jpg", "jpeg", "png"].contains(($0 as NSString).pathExtension.lowercased()) }
            .sorted()

        guard !files.isEmpty else {
            print("✗ \(dir) 에 사진이 없습니다")
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

            guard let output = normalize(source) else {
                print("✗ \(file): 변환 실패")
                continue
            }

            let rep = NSBitmapImageRep(cgImage: output)
            guard let jpeg = rep.representation(
                using: .jpeg,
                properties: [.compressionFactor: quality]
            ) else {
                print("✗ \(file): 인코딩 실패")
                continue
            }

            do {
                try jpeg.write(to: URL(fileURLWithPath: path))
                print("✓ \(file)  \(source.width)x\(source.height)"
                      + " → \(targetWidth)x\(targetHeight)")
            } catch {
                print("✗ \(file): 쓰기 실패 \(error.localizedDescription)")
            }
        }
    }

    /// 가운데를 기준으로 목표 비율로 자른 뒤 목표 크기로 줄인다.
    static func normalize(_ image: CGImage) -> CGImage? {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let aspect = w / h

        // 목표보다 납작하면 좌우를, 목표보다 홀쭉하면 위아래를 잘라낸다.
        let crop: CGRect
        if aspect > targetAspect {
            let keep = h * targetAspect
            crop = CGRect(x: (w - keep) / 2, y: 0, width: keep, height: h)
        } else {
            let keep = w / targetAspect
            crop = CGRect(x: 0, y: (h - keep) / 2, width: w, height: keep)
        }

        guard let cropped = image.cropping(to: crop.integral) else { return nil }

        guard let ctx = CGContext(
            data: nil,
            width: targetWidth, height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }

        ctx.interpolationQuality = .high
        ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        return ctx.makeImage()
    }
}
