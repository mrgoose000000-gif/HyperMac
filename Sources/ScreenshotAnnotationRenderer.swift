// SPDX-License-Identifier: GPL-3.0-only
// HyperMac — Copyright (C) 2026 Nguyễn Khắc Đại

import AppKit
import SwiftUI

// MARK: - Screenshot Tool & Stroke Models

public enum ScreenshotTool: String, CaseIterable, Sendable {
    case move       // Move selection box
    case pen        // Freehand ink
    case arrow      // Directional pointer arrow
    case rect       // Rectangle outline
    case marker     // Semi-transparent highlighter
    case text       // Editable text annotation
    case blur       // Blur a rectangular area of the captured image
}

public struct DrawnStroke: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var tool: ScreenshotTool
    public var points: [CGPoint] // points relative to the screen frame
    public var colorHex: String
    public var lineWidth: CGFloat
    public var text: String
    public var fontSize: CGFloat

    public init(id: UUID = UUID(), tool: ScreenshotTool, points: [CGPoint], colorHex: String, lineWidth: CGFloat, text: String = "", fontSize: CGFloat = 22) {
        self.id = id
        self.tool = tool
        self.points = points
        self.colorHex = colorHex
        self.lineWidth = lineWidth
        self.text = text
        self.fontSize = fontSize
    }

    public var color: Color {
        Color(nsColor: nsColor)
    }

    public var nsColor: NSColor {
        NSColor(hex: colorHex) ?? .systemRed
    }
}

/// Shared rendering in screen-local, top-left coordinates. Preview and exported pixels stay identical.
enum ScreenshotAnnotationRenderer {
    static func rectangle(for stroke: DrawnStroke) -> CGRect {
        guard let first = stroke.points.first, let last = stroke.points.last else { return .zero }
        return CGRect(x: min(first.x, last.x), y: min(first.y, last.y),
                      width: abs(last.x - first.x), height: abs(last.y - first.y))
    }

    static func attributedText(for stroke: DrawnStroke) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        return NSAttributedString(string: stroke.text, attributes: [
            .font: NSFont.systemFont(ofSize: stroke.fontSize, weight: .semibold),
            .foregroundColor: stroke.nsColor,
            .paragraphStyle: paragraph
        ])
    }

    static func textBounds(for stroke: DrawnStroke) -> CGRect {
        guard let origin = stroke.points.first, let end = stroke.points.last else { return .zero }
        let available = CGSize(width: max(1, end.x - origin.x), height: max(1, end.y - origin.y))
        let size = attributedText(for: stroke).boundingRect(with: available,
            options: [.usesLineFragmentOrigin, .usesFontLeading]).size
        return CGRect(origin: origin, size: CGSize(width: min(available.width, ceil(size.width)),
                                                   height: min(available.height, ceil(size.height))))
    }

    /// Mosaic redaction: average each 12-point tile, retaining the source colours
    /// as hard-edged square pixels. CPU-only so preview/export match on every GPU.
    static func pixelated(_ image: CGImage, scale: CGFloat) -> CGImage? {
        let width = image.width, height = image.height
        let rowBytes = width * 4
        let tile = max(1, Int((12 * max(1, scale)).rounded()))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: rowBytes, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
            let data = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        for y in stride(from: 0, to: height, by: tile) {
            for x in stride(from: 0, to: width, by: tile) {
                let endY = min(y + tile, height), endX = min(x + tile, width)
                var r = 0, g = 0, b = 0, a = 0
                for row in y..<endY {
                    for col in x..<endX {
                        let i = row * rowBytes + col * 4
                        r += Int(data[i]); g += Int(data[i + 1])
                        b += Int(data[i + 2]); a += Int(data[i + 3])
                    }
                }
                let count = (endY - y) * (endX - x)
                let red = UInt8(r / count), green = UInt8(g / count)
                let blue = UInt8(b / count), alpha = UInt8(a / count)
                for row in y..<endY {
                    for col in x..<endX {
                        let i = row * rowBytes + col * 4
                        data[i] = red; data[i + 1] = green
                        data[i + 2] = blue; data[i + 3] = alpha
                    }
                }
            }
        }
        return context.makeImage()
    }

    static func draw(_ stroke: DrawnStroke, in ctx: CGContext, blurredImage: CGImage?, scale: CGFloat) {
        guard !stroke.points.isEmpty else { return }

        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setStrokeColor(stroke.nsColor.cgColor)
        ctx.setFillColor(stroke.nsColor.cgColor)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setLineWidth(stroke.lineWidth)

        if stroke.tool == .marker {
            ctx.setAlpha(0.38)
        } else {
            ctx.setAlpha(1.0)
        }

        switch stroke.tool {
        case .pen, .marker:
            ctx.beginPath()
            ctx.move(to: stroke.points[0])
            for pt in stroke.points.dropFirst() {
                ctx.addLine(to: pt)
            }
            ctx.strokePath()

        case .arrow:
            guard stroke.points.count >= 2 else { break }
            let start = stroke.points[0]
            let end = stroke.points[stroke.points.count - 1]

            // Main arrow line
            ctx.beginPath()
            ctx.move(to: start)
            ctx.addLine(to: end)
            ctx.strokePath()

            // Arrow head wings
            let angle = atan2(end.y - start.y, end.x - start.x)
            let arrowLength: CGFloat = max(12, stroke.lineWidth * 3.5)
            let arrowAngle: CGFloat = .pi / 6

            let p1 = CGPoint(
                x: end.x - arrowLength * cos(angle - arrowAngle),
                y: end.y - arrowLength * sin(angle - arrowAngle)
            )
            let p2 = CGPoint(
                x: end.x - arrowLength * cos(angle + arrowAngle),
                y: end.y - arrowLength * sin(angle + arrowAngle)
            )

            ctx.beginPath()
            ctx.move(to: p1)
            ctx.addLine(to: end)
            ctx.addLine(to: p2)
            ctx.strokePath()

        case .rect:
            guard stroke.points.count >= 2 else { break }
            let p1 = stroke.points[0]
            let p2 = stroke.points[stroke.points.count - 1]
            let rect = CGRect(
                x: min(p1.x, p2.x),
                y: min(p1.y, p2.y),
                width: abs(p2.x - p1.x),
                height: abs(p2.y - p1.y)
            )
            ctx.stroke(rect, width: stroke.lineWidth)

        case .text:
            let bounds = textBounds(for: stroke)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
            attributedText(for: stroke).draw(with: bounds, options: [.usesLineFragmentOrigin, .usesFontLeading])
            NSGraphicsContext.restoreGraphicsState()

        case .blur:
            guard let blurredImage else { break }
            let bounds = rectangle(for: stroke)
            let pixels = CGRect(x: bounds.minX * scale, y: bounds.minY * scale,
                                width: bounds.width * scale, height: bounds.height * scale).integral
            if let patch = blurredImage.cropping(to: pixels) {
                let rect = CGRect(x: pixels.minX / scale, y: pixels.minY / scale,
                                  width: pixels.width / scale, height: pixels.height / scale)
                ctx.saveGState()
                ctx.clip(to: bounds)
                ctx.translateBy(x: rect.minX, y: rect.maxY)
                ctx.scaleBy(x: 1, y: -1)
                ctx.interpolationQuality = .none
                ctx.draw(patch, in: CGRect(origin: .zero, size: rect.size))
                ctx.restoreGState()
            }

        case .move:
            break
        }

    }

}

private extension NSColor {
    convenience init?(hex: String) {
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        guard Scanner(string: clean).scanHexInt64(&int) else { return nil }
        if clean.count == 6 {
            let r = CGFloat((int >> 16) & 0xFF) / 255.0
            let g = CGFloat((int >> 8) & 0xFF) / 255.0
            let b = CGFloat(int & 0xFF) / 255.0
            self.init(srgbRed: r, green: g, blue: b, alpha: 1.0)
        } else {
            self.init(srgbRed: 1.0, green: 0.23, blue: 0.19, alpha: 1.0)
        }
    }
}
