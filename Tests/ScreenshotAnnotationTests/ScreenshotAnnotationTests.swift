// SPDX-License-Identifier: GPL-3.0-only
// HyperMac — Copyright (C) 2026 Nguyễn Khắc Đại

import Testing
import AppKit
import SwiftUI
@testable import HyperMac

@Suite(.serialized)
struct ScreenshotAnnotationTests {
    private func fixture(scale: Int) -> CGImage {
        let width = 600 * scale, height = 400 * scale
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: CGFloat(scale), y: -CGFloat(scale))
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: 600, height: 400))
        for y in stride(from: 0, to: 400, by: 4) {
            for x in stride(from: 0, to: 600, by: 4) {
                ctx.setFillColor((y < 200 ? NSColor.systemBlue : NSColor.systemOrange).withAlphaComponent((x/4 + y/4) % 2 == 0 ? 1 : 0.1).cgColor)
                ctx.fill(CGRect(x: x, y: y, width: 4, height: 4))
            }
        }
        return ctx.makeImage()!
    }

    @MainActor private func setup(scale: Int = 2) -> ScreenshotManager {
        let manager = ScreenshotManager.shared
        manager.resetAnnotations()
        manager.screenImage = fixture(scale: scale)
        manager.screenNSImage = NSImage(cgImage: manager.screenImage!, size: NSSize(width: 600, height: 400))
        manager.screenFrame = CGRect(x: 0, y: 0, width: 600, height: 400)
        manager.scaleFactor = CGFloat(scale)
        manager.selectionRect = CGRect(x: 40, y: 30, width: 500, height: 300)
        manager.hasSelection = true
        return manager
    }

    private func bytes(_ image: CGImage) -> [UInt8] {
        let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                            bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Array(UnsafeBufferPointer(start: ctx.data!.assumingMemoryBound(to: UInt8.self), count: image.width * image.height * 4))
    }

    @Test func testTextDraftCommitEditCancelAndUndo() async {
        await MainActor.run {
            let m = setup()
            m.beginText(at: CGPoint(x: 80, y: 70))
            #expect(m.isEditingText)
            #expect(gIsScreenshotEditingText)
            m.textDraft = "Khóa sạc 90% — Tiếng Việt\nDòng thứ hai"
            m.textFontSize = 28
            m.commitTextEditing()
            #expect((m.strokes.count) == (1))
            #expect(!(gIsScreenshotEditingText))
            let original = m.strokes[0]
            #expect((original.fontSize) == (28))
            m.beginText(at: CGPoint(x: 82, y: 72))
            m.textDraft = "Bản sửa"
            m.commitTextEditing()
            #expect((m.strokes.count) == (1))
            #expect((m.strokes[0].id) == (original.id))
            m.undoLastStroke()
            #expect((m.strokes[0]) == (original))
            m.beginText(at: CGPoint(x: 82, y: 72))
            m.textDraft = "Không lưu"
            m.cancelTextEditing()
            #expect((m.strokes[0]) == (original))
            m.clearAllStrokes()
            #expect(m.strokes.isEmpty)
            m.undoLastStroke()
            #expect((m.strokes) == ([original]))
            m.resetAnnotations()
        }
    }

    @Test func testUndoFollowsDrawingOrderIncludingUnfinishedFourthStroke() async {
        await MainActor.run {
            let m = setup()
            let sequence = (1...4).map { number in
                DrawnStroke(tool: .pen, points: [CGPoint(x: 60 + number * 40, y: 80),
                    CGPoint(x: 65 + number * 40, y: 120)], colorHex: "#FF3B30", lineWidth: 3.5)
            }
            for stroke in sequence {
                m.activeStroke = stroke
                m.finishActiveStroke()
            }
            for count in stride(from: 3, through: 0, by: -1) {
                m.undoLastStroke()
                #expect(m.strokes == Array(sequence.prefix(count)))
                #expect(m.activeStroke == nil)
            }
            for stroke in sequence.prefix(3) { m.appendStroke(stroke) }
            m.activeStroke = sequence[3]
            m.undoLastStroke()
            #expect(m.strokes == Array(sequence.prefix(3)))
            #expect(m.activeStroke == nil)
            m.finishActiveStroke() // Late mouse-up must not resurrect the undone stroke.
            #expect(m.strokes == Array(sequence.prefix(3)))
            m.undoLastStroke()
            #expect(m.strokes == Array(sequence.prefix(2)))
            m.resetAnnotations()
        }
    }

    @Test func testUndoCancelsFourthTextDraftBeforeThirdCommittedAnnotation() async {
        await MainActor.run {
            let m = setup()
            for number in 1...3 {
                m.beginText(at: CGPoint(x: 50 + number * 90, y: 80))
                m.textDraft = String(number)
                m.commitTextEditing()
            }
            m.beginText(at: CGPoint(x: 430, y: 80))
            m.textDraft = "4"
            m.undoLastStroke()
            #expect(m.strokes.map(\.text) == ["1", "2", "3"])
            #expect(!m.isEditingText)
            m.undoLastStroke()
            #expect(m.strokes.map(\.text) == ["1", "2"])
            m.resetAnnotations()
        }
    }

    @Test func testPixelationHasSquareTilesAndKeepsSourceColourVariation() throws {
        for scale in [1, 2] {
            let width = 96 * scale, height = 48 * scale
            let ctx = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            // An uneven gradient plus small details distinguishes mosaic from a flat cover.
            for x in 0..<width {
                let shade = CGFloat(x) / CGFloat(width)
                ctx.setFillColor(CGColor(gray: shade, alpha: 1))
                ctx.fill(CGRect(x: x, y: 0, width: 1, height: height))
            }
            let original = try #require(ctx.makeImage())
            let result = try #require(ScreenshotAnnotationRenderer.pixelated(original, scale: CGFloat(scale)))
            let pixels = bytes(result), tile = 12 * scale
            #expect(pixels != bytes(original))
            for y in 0..<height {
                for x in 0..<width {
                    let start = ((y / tile) * tile * width + (x / tile) * tile) * 4
                    let index = (y * width + x) * 4
                    #expect(pixels[index..<index+4] == pixels[start..<start+4])
                    #expect(pixels[index+3] == 255)
                }
            }
            #expect(pixels[0] < pixels[tile * 4])
            #expect(Int(pixels[(width-1)*4]) - Int(pixels[0]) > 180)
        }
    }

    @Test func testTextMosaicMatchesReferenceStyle() async throws {
        try await MainActor.run {
            let ctx = try #require(CGContext(data: nil, width: 900, height: 240, bitsPerComponent: 8,
                bytesPerRow: 900 * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: 900, height: 240))
            ctx.translateBy(x: 0, y: 240)
            ctx.scaleBy(x: 1, y: -1)
            for y in [30, 145] {
                let text = DrawnStroke(tool: .text, points: [CGPoint(x: 30, y: y), CGPoint(x: 870, y: y + 80)],
                    colorHex: "#000000", lineWidth: 0, text: "this is super secret", fontSize: 64)
                ScreenshotAnnotationRenderer.draw(text, in: ctx, blurredImage: nil, scale: 1)
            }
            let source = try #require(ctx.makeImage())
            let filtered = try #require(ScreenshotAnnotationRenderer.pixelated(source, scale: 1))
            let region = DrawnStroke(tool: .blur, points: [CGPoint(x: 20, y: 20), CGPoint(x: 870, y: 120)],
                colorHex: "#FF3B30", lineWidth: 0)
            ScreenshotAnnotationRenderer.draw(region, in: ctx, blurredImage: filtered, scale: 1)
            let output = try #require(ctx.makeImage())
            let data = bytes(output)
            var shades = Set<UInt8>()
            for y in 20..<120 {
                for x in 20..<870 { shades.insert(data[(y * 900 + x) * 4]) }
            }
            #expect(shades.count > 8) // Source detail remains as tiles, never a uniform cover.
            let path = "/private/tmp/hypermac-mosaic-reference-check.png"
            try #require(NSBitmapImageRep(cgImage: output).representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: path))
        }
    }

    @Test func testEmptyDraftAndCaptureResetDoNotLeakKeyboardState() async {
        await MainActor.run {
            let m = setup()
            m.beginText(at: CGPoint(x: 80, y: 70))
            m.textDraft = " \n "
            m.commitTextEditing()
            #expect(m.strokes.isEmpty)
            m.beginText(at: CGPoint(x: 80, y: 70))
            m.textDraft = "Đang nhập"
            m.cancelCapture()
            #expect(m.textAnchor == nil)
            #expect(!(gIsScreenshotEditingText))
            #expect(!(m.canUndoAnnotations))
        }
    }

    @Test func testTextIsBurnedIntoRetinaExportAndClippedToSelection() async throws {
        try await MainActor.run {
            for scale in [1, 2] {
                let m = setup(scale: scale)
                let before = try #require(m.renderCompositeImage())
                m.beginText(at: CGPoint(x: 65, y: 55))
                m.textDraft = "Chú thích tiếng Việt\n90%"
                m.selectedColorHex = "#FF3B30"
                let after = try #require(m.renderCompositeImage()) // Export commits an open draft.
                #expect((after.width) == (500 * scale))
                #expect((after.height) == (300 * scale))
                #expect(!(m.isEditingText))
                let a = bytes(before), b = bytes(after)
                var changed = 0
                for y in 0..<after.height {
                    for x in 0..<after.width {
                        let i = (y * after.width + x) * 4
                        if a[i..<i+4] != b[i..<i+4] {
                            changed += 1
                            // Text must appear near the top-left anchor, not vertically inverted.
                            #expect((y) < (130 * scale))
                            #expect((x) < (470 * scale))
                        }
                    }
                }
                #expect((changed) > (100))
            }
        }
    }

    @Test func testBlurChangesOnlySelectedPixelsAtBothScales() async throws {
        for scale in [1, 2] {
            let baseline = try await MainActor.run { () -> CGImage in
                let m = setup(scale: scale)
                return try #require(m.renderCompositeImage())
            }
            await MainActor.run { ScreenshotManager.shared.selectTool(.blur) }
            for _ in 0..<500 {
                if await MainActor.run(body: { !ScreenshotManager.shared.isPreparingBlur }) { break }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            try await MainActor.run {
                let m = ScreenshotManager.shared
                #expect(m.blurredScreenImage != nil)
                // Reverse-direction rectangle, with a nonzero crop origin and Retina scaling.
                m.appendStroke(DrawnStroke(tool: .blur, points: [CGPoint(x: 260, y: 160), CGPoint(x: 100, y: 80)], colorHex: "#000000", lineWidth: 0))
                let result = try #require(m.renderCompositeImage())
                let a = bytes(baseline), b = bytes(result)
                var inside = 0
                for y in 0..<result.height {
                    for x in 0..<result.width {
                        let i = (y * result.width + x) * 4
                        let changed = a[i..<i+4] != b[i..<i+4]
                        let inBlur = x >= 60*scale && x < 220*scale && y >= 50*scale && y < 130*scale
                        if inBlur && changed { inside += 1 }
                        if !inBlur { #expect(!(changed)) }
                    }
                }
                #expect((inside) > (1000 * scale))
                let center = (90 * scale * result.width + 100 * scale) * 4
                #expect(b[center + 2] > b[center]) // This top-half patch must stay blue, not flip to orange.
                m.undoLastStroke()
                #expect((bytes(try #require(m.renderCompositeImage()))) == (a))
                m.resetAnnotations()
            }
        }
    }

    @Test func testBlurFailsClosedWhenFilteredImageIsMissing() async {
        await MainActor.run {
            let m = setup()
            m.appendStroke(DrawnStroke(tool: .blur, points: [CGPoint(x: 100, y: 80), CGPoint(x: 260, y: 160)], colorHex: "#000000", lineWidth: 0))
            #expect(!(m.canExport))
            #expect(m.renderCompositeImage() == nil)
            #expect(m.annotationError != nil)
            m.resetAnnotations()
        }
    }

    @Test func testOldBlurJobCannotAttachToANewCapture() async throws {
        await MainActor.run {
            let m = setup()
            m.prepareBlur()
            m.screenImage = fixture(scale: 1)
        }
        try await Task.sleep(nanoseconds: 500_000_000)
        await MainActor.run {
            #expect(ScreenshotManager.shared.blurredScreenImage == nil)
            #expect(!(ScreenshotManager.shared.isPreparingBlur))
        }
    }

    @Test func testNativePanelTypingUndoAndVietnameseExport() async throws {
        let out = ProcessInfo.processInfo.environment["HYPERMAC_SCREENSHOT_QA_OUT"] ?? "/private/tmp/hypermac-screenshot-regression.png"
        let ui = try await MainActor.run {
            let m = setup()
            m.currentTool = .text
            m.appendStroke(DrawnStroke(tool: .text, points: [CGPoint(x: 90, y: 75), CGPoint(x: 500, y: 260)], colorHex: "#FFFFFF", lineWidth: 0,
                                        text: "Chú thích tiếng Việt\nKhóa sạc 90%", fontSize: 28))
            let view = NSHostingView(rootView: ScreenshotOverlayView(manager: m))
            view.frame = CGRect(x: 0, y: 0, width: 600, height: 400)
            let window = ScreenshotOverlayPanel(contentRect: view.frame)
            #expect(window.canBecomeKey)
            #expect(!window.styleMask.contains(.nonactivatingPanel))
            window.contentView = view
            window.layoutIfNeeded()
            NSApplication.shared.setActivationPolicy(.accessory)
            NSApplication.shared.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try #require(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: out))
            // Verify the actual native text input, including focus, Vietnamese input and Enter commit.
            m.beginText(at: CGPoint(x: 100, y: 220))
            view.layoutSubtreeIfNeeded()
            return (window, view)
        }
        // Yield the main queue so the real first-responder handoff can complete.
        try await Task.sleep(nanoseconds: 150_000_000)
        try await MainActor.run {
            let (window, view) = ui
            let m = ScreenshotManager.shared
            @MainActor func findEditor(_ parent: NSView) -> NSTextView? {
                if let text = parent as? NSTextView { return text }
                return parent.subviews.compactMap { findEditor($0) }.first
            }
            let editor = try #require(findEditor(view))
            #expect(window.firstResponder === editor)
            #expect(window.canBecomeKey) // Swift Testing has no NSApplication.run() event loop.
            let typed = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "a",
                charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0))
            window.sendEvent(typed) // Dispatch through the panel, not directly to NSTextView.
            #expect(m.textDraft == "a")
            editor.breakUndoCoalescing()
        }
        // Native UndoManager closes the typing group at the end of the event-loop turn.
        try await Task.sleep(nanoseconds: 100_000_000)
        try await MainActor.run {
            let (window, view) = ui
            let m = ScreenshotManager.shared
            let editor = try #require(window.firstResponder as? NSTextView)
            #expect(editor.undoManager?.canUndo == true)
            let undo = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "z",
                charactersIgnoringModifiers: "z", isARepeat: false, keyCode: 6))
            #expect(editor.performKeyEquivalent(with: undo))
            #expect(editor.string.isEmpty)
            #expect(m.textDraft.isEmpty)
            editor.insertText("Ghi chú tiếng Việt 90%", replacementRange: NSRange(location: NSNotFound, length: 0))
            #expect(m.textDraft.contains("Ghi chú tiếng Việt 90%"))
            let editorBitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: editorBitmap)
            try #require(editorBitmap.representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: out.replacingOccurrences(of: ".png", with: "-editor.png")))
            let enter = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\r",
                charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
            editor.keyDown(with: enter)
            #expect(!m.isEditingText)
            #expect(m.strokes.last?.text == "Ghi chú tiếng Việt 90%")
            let exported = try #require(m.renderCompositeImage())
            try #require(NSBitmapImageRep(cgImage: exported).representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: out.replacingOccurrences(of: ".png", with: "-export.png")))
            window.orderOut(nil)
            window.contentView = nil
            m.resetAnnotations()
        }
    }
}
