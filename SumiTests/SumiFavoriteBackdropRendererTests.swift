import AppKit
import ImageIO
import XCTest

@testable import Sumi

@MainActor
final class SumiFavoriteBackdropRendererTests: XCTestCase {
    func testBakeIsDeterministicOpaqueSixteenPixelPNG() async throws {
        let favicon = makeSplitColorImage()

        let firstData = await SumiFavoriteBackdropRenderer.bake(favicon: favicon)
        let first = try XCTUnwrap(firstData)
        let secondData = await SumiFavoriteBackdropRenderer.bake(favicon: favicon)
        let second = try XCTUnwrap(secondData)

        XCTAssertEqual(first, second)
        let image = try decodedCGImage(first)
        XCTAssertEqual(image.width, 16)
        XCTAssertEqual(image.height, 16)
        XCTAssertTrue(pixelBytes(image).enumerated().allSatisfy {
            $0.offset % 4 != 3 || $0.element == 255
        })
    }

    func testTransparentFaviconDoesNotProduceArtifact() async {
        let data = await SumiFavoriteBackdropRenderer.bake(
            favicon: makeImage { context, rect in
                context.clear(rect)
            }
        )
        XCTAssertNil(data)
    }

    func testBakedColorRegionsPreserveFaviconOrientation() async throws {
        let bakedData = await SumiFavoriteBackdropRenderer.bake(
            favicon: makeSplitColorImage()
        )
        let data = try XCTUnwrap(bakedData)
        let bytes = pixelBytes(try decodedCGImage(data))
        let left = averageRGB(bytes, xRange: 0..<4)
        let right = averageRGB(bytes, xRange: 12..<16)

        XCTAssertGreaterThan(left.red, left.blue)
        XCTAssertGreaterThan(right.blue, right.red)
    }

    func testNearWhiteFaviconKeepsVisibleClampedBaseAtEdges() async throws {
        let favicon = makeImage { context, rect in
            context.setFillColor(NSColor.white.cgColor)
            context.fill(rect.insetBy(dx: 2, dy: 2))
        }
        let bakedData = await SumiFavoriteBackdropRenderer.bake(favicon: favicon)
        let data = try XCTUnwrap(bakedData)
        let bytes = pixelBytes(try decodedCGImage(data))
        let cornerOffset = 0

        XCTAssertLessThan(bytes[cornerOffset], 245)
        XCTAssertLessThan(bytes[cornerOffset + 1], 245)
        XCTAssertLessThan(bytes[cornerOffset + 2], 245)
    }

    private func makeSplitColorImage() -> NSImage {
        makeImage { context, rect in
            context.setFillColor(NSColor.systemRed.cgColor)
            context.fill(CGRect(
                x: rect.minX,
                y: rect.minY,
                width: rect.width / 2,
                height: rect.height
            ))
            context.setFillColor(NSColor.systemBlue.cgColor)
            context.fill(CGRect(
                x: rect.midX,
                y: rect.minY,
                width: rect.width / 2,
                height: rect.height
            ))
        }
    }

    private func makeImage(
        draw: (CGContext, CGRect) -> Void
    ) -> NSImage {
        let dimension = 32
        let context = CGContext(
            data: nil,
            width: dimension,
            height: dimension,
            bitsPerComponent: 8,
            bytesPerRow: dimension * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        draw(context, CGRect(x: 0, y: 0, width: dimension, height: dimension))
        return NSImage(
            cgImage: context.makeImage()!,
            size: NSSize(width: dimension, height: dimension)
        )
    }

    private func decodedCGImage(_ data: Data) throws -> CGImage {
        let source = try XCTUnwrap(
            CGImageSourceCreateWithData(data as CFData, nil)
        )
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    private func pixelBytes(_ image: CGImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 16 * 16 * 4)
        let context = CGContext(
            data: &bytes,
            width: 16,
            height: 16,
            bitsPerComponent: 8,
            bytesPerRow: 16 * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                | CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: 16, height: 16))
        return bytes
    }

    private func averageRGB(
        _ bytes: [UInt8],
        xRange: Range<Int>
    ) -> (red: Double, green: Double, blue: Double) {
        var red = 0
        var green = 0
        var blue = 0
        for y in 0..<16 {
            for x in xRange {
                let offset = (y * 16 + x) * 4
                red += Int(bytes[offset])
                green += Int(bytes[offset + 1])
                blue += Int(bytes[offset + 2])
            }
        }
        let count = Double(16 * xRange.count)
        return (
            Double(red) / count,
            Double(green) / count,
            Double(blue) / count
        )
    }
}
