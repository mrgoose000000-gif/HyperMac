import SwiftUI
import AppKit

// Hallmark · component: screenshot editor · genre: modern-minimal · theme: HyperMac native
// Hallmark · pre-emit critique: P4 H4 E4 S5 R5 V4
// Existing FS / Rad / Tone tokens and native input states; no page macrostructure.
// MARK: - LightShot-Style Screenshot Overlay View

public struct ScreenshotOverlayView: View {
    @ObservedObject var manager: ScreenshotManager

    public init(manager: ScreenshotManager) {
        self.manager = manager
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                // 1. Base Frozen Screen Image (Spans entire multi-screen union)
                if let nsImage = manager.screenNSImage {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                        .allowsHitTesting(false)
                }

                // 2. Dark Translucent Veil with Cutout Hole for Selection
                CutoutVeil(cutout: (manager.selectionRect.width > 0 && manager.selectionRect.height > 0) ? manager.selectionRect : .zero)
                    .fill(Color.black.opacity(0.48), style: FillStyle(eoFill: true))
                    .frame(width: geo.size.width, height: geo.size.height)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    // Initial area selection drag gesture (also allows re-dragging when clicking outside)
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .named("canvasSpace"))
                            .onChanged { value in
                                if manager.isSpaceHeld && manager.selectionRect.width > 0 && manager.selectionRect.height > 0 {
                                    if !manager.isDraggingSelection {
                                        manager.isDraggingSelection = true
                                        manager.dragStartRect = manager.selectionRect
                                    }
                                    let newX = max(0, min(geo.size.width - manager.dragStartRect.width, manager.dragStartRect.origin.x + value.translation.width))
                                    let newY = max(0, min(geo.size.height - manager.dragStartRect.height, manager.dragStartRect.origin.y + value.translation.height))
                                    manager.selectionRect.origin = CGPoint(x: newX, y: newY)
                                    return
                                }
                                manager.isDraggingSelection = false
                                if !manager.hasSelection || !manager.selectionRect.contains(value.startLocation) {
                                    if manager.hasSelection {
                                        manager.hasSelection = false
                                        manager.resetAnnotations()
                                    }
                                    let minX = max(0, min(value.startLocation.x, value.location.x))
                                    let minY = max(0, min(value.startLocation.y, value.location.y))
                                    let w = min(geo.size.width - minX, abs(value.location.x - value.startLocation.x))
                                    let h = min(geo.size.height - minY, abs(value.location.y - value.startLocation.y))
                                    manager.selectionRect = CGRect(x: minX, y: minY, width: w, height: h)
                                }
                            }
                            .onEnded { value in
                                manager.isDraggingSelection = false
                                if !manager.hasSelection {
                                    if manager.selectionRect.width > 20 && manager.selectionRect.height > 20 {
                                        manager.hasSelection = true
                                    } else {
                                        manager.selectionRect = .zero
                                        manager.hasSelection = false
                                    }
                                }
                            }
                    )

                // 3. Selection Box, Annotations Canvas & Toolbars
                if manager.hasSelection && manager.selectionRect.width > 0 && manager.selectionRect.height > 0 {
                    selectionContent(in: geo)
                } else if manager.selectionRect.width > 0 && manager.selectionRect.height > 0 {
                    // Live dragging preview: Cutout hole + dashed border + dimension pill during active drag!
                    liveDraggingPreview(for: manager.selectionRect)
                } else {
                    // Initial helpful hint at top center
                    initialHintBar(in: geo)
                }
            }
            .coordinateSpace(name: "canvasSpace")
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .edgesIgnoringSafeArea(.all)
    }

    // MARK: - Initial Hint Bar

    private func initialHintBar(in geo: GeometryProxy) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "viewfinder")
                .font(.system(size: FS.body, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            if NSScreen.screens.count > 1 {
                Text(tr("Kéo chọn vùng • Đè Space di chuyển • ⇥ Đổi màn • ⎋ Huỷ", "Drag area • Hold Space to move • ⇥ Switch screen • ⎋ Cancel"))
                    .font(.system(size: FS.label, weight: .semibold))
                    .foregroundStyle(Color.white)
            } else {
                Text(tr("Kéo chọn vùng • Đè Space di chuyển • ⎋ Huỷ", "Click & drag area • Hold Space to move • ⎋ Cancel"))
                    .font(.system(size: FS.label, weight: .semibold))
                    .foregroundStyle(Color.white)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.85))
                .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1))
        )
        .shadow(color: Color.black.opacity(0.4), radius: 10, y: 4)
        .position(x: geo.size.width / 2, y: 50)
    }

    // MARK: - Selection Content (Box, Annotations, Handles, Toolbars)

    private func selectionContent(in geo: GeometryProxy) -> some View {
        let sel = manager.selectionRect

        return ZStack(alignment: .topLeading) {
            // Drawn Annotations Layer (All completed strokes + active in-progress stroke)
            AnnotationsCanvas(
                strokes: manager.previewStrokes,
                activeStroke: manager.activeStroke,
                clipRect: sel,
                blurredImage: manager.blurredScreenImage,
                scale: manager.scaleFactor
            )
            .frame(width: geo.size.width, height: geo.size.height)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
            .allowsHitTesting(false)

            // Selection Boundary Border
            Rectangle()
                .stroke(Color.accentColor, lineWidth: 1.5)
                .frame(width: sel.width, height: sel.height)
                .position(x: sel.midX, y: sel.midY)
                .allowsHitTesting(false)

            // Dimension Badge Pill (Top-left above selection)
            dimensionBadge(for: sel)

            // Dedicated Move Grab Bar (Top-center of selection box)
            moveHandleBar(for: sel, in: geo)

            // Interactive Drawing Area inside Selection Box
            Color.clear
                .contentShape(Rectangle())
                .frame(width: max(0, sel.width), height: max(0, sel.height))
                .position(x: sel.midX, y: sel.midY)
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .named("canvasSpace"))
                        .onChanged { value in
                            handleInsideDragChange(value: value, in: geo)
                        }
                        .onEnded { value in
                            handleInsideDragEnd(value: value, in: geo)
                        }
                )

            // 8 Resize Handles on Border
            resizeHandles(for: sel, in: geo)

            // LightShot Floating Toolbars (Side Drawing Tools & Bottom Actions)
            floatingToolbars(for: sel, in: geo)

            if manager.isEditingText {
                textEditor(in: geo)
            }
        }
    }

    private var annotationStatus: some View {
        HStack(spacing: 6) {
            if manager.isPreparingBlur {
                ProgressView().controlSize(.small)
            }
            Text(manager.annotationError ?? (manager.isPreparingBlur
                ? tr("Đang chuẩn bị làm mờ…", "Preparing blur…")
                : manager.currentTool == .text
                    ? tr("Nhấp để thêm chữ · Nhấp vào chữ để sửa", "Click to add text · Click text to edit")
                    : tr("Kéo khoanh vùng cần làm mờ pixel", "Drag over the area to pixelate")))
                .font(.system(size: FS.label, weight: .medium))
                .foregroundStyle(manager.annotationError == nil ? Color.white : Color.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: Rad.sm).fill(Color.black.opacity(0.85)))
        .allowsHitTesting(false)
    }

    private func textEditor(in geo: GeometryProxy) -> some View {
        let width = min(320, geo.size.width - 20)
        let anchor = manager.textAnchor ?? .zero
        let x = min(geo.size.width - width - 10, max(10, anchor.x))
        let y = min(geo.size.height - 200, max(10, anchor.y + manager.textFontSize + 12))
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(tr("Nội dung chữ", "Text annotation"))
                    .font(.system(size: FS.title, weight: .semibold))
                Spacer()
                Picker(tr("Cỡ chữ", "Size"), selection: $manager.textFontSize) {
                    ForEach([16, 22, 28, 36, 48], id: \.self) { size in
                        Text("\(size) pt").tag(CGFloat(size))
                    }
                }
                .frame(width: 130)
                .controlSize(.small)
                Button { manager.cancelTextEditing() } label: {
                    Image(systemName: "xmark").font(.system(size: FS.label, weight: .medium))
                }
                .buttonStyle(.borderless)
                .help(tr("Hủy nhập chữ (Esc)", "Cancel text (Esc)"))
                .accessibilityLabel(tr("Hủy nhập chữ", "Cancel text"))
            }
            ScreenshotTextInput(text: $manager.textDraft,
                onCommit: { manager.commitTextEditing() },
                onCancel: { manager.cancelTextEditing() },
                onSave: { manager.saveToDownloads() })
                .frame(height: 76)
                .accessibilityLabel(tr("Nội dung chữ trên ảnh", "Screenshot annotation text"))
            Text(tr("Enter: áp dụng · Shift+Enter: xuống dòng · Esc: hủy", "Enter: apply · Shift+Enter: new line · Esc: cancel"))
                .font(.system(size: FS.caption))
                .foregroundStyle(.primary.opacity(0.8))
            HStack(spacing: 4) {
                ForEach(manager.availableColors, id: \.self) { hex in
                    Button {
                        manager.selectedColorHex = hex
                    } label: {
                        Circle().fill(Color(hex: hex))
                            .frame(width: 16, height: 16)
                            .overlay(Circle().stroke(manager.selectedColorHex == hex ? Color.accentColor : Color.secondary,
                                                     lineWidth: 2))
                            .padding(2)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(hex)
                }
                Spacer(minLength: 0)
                Button(tr("Áp dụng", "Apply")) { manager.commitTextEditing() }
                    .disabled(!manager.canCommitText)
                    .controlSize(.small)
            }
        }
        .padding(12)
        .foregroundStyle(.primary)
        .background(RoundedRectangle(cornerRadius: Rad.md).fill(Color(nsColor: .windowBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: Rad.md).stroke(Color.primary.opacity(0.15), lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
        .frame(width: width)
        .offset(x: x, y: max(10, y))
    }

    // MARK: - Live Dragging Selection Preview

    private func liveDraggingPreview(for sel: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            // Live dashed accent selection border
            Rectangle()
                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .frame(width: max(0, sel.width), height: max(0, sel.height))
                .position(x: sel.midX, y: sel.midY)
                .allowsHitTesting(false)

            // 4 Corner Viewfinder Accents
            cornerViewfinderMarks(for: sel)

            // Live Dimension badge (appears when box is large enough to read)
            if sel.width >= 40 && sel.height >= 20 {
                dimensionBadge(for: sel)
            }
        }
    }

    private func cornerViewfinderMarks(for sel: CGRect) -> some View {
        let size: CGFloat = 8
        return ZStack {
            Rectangle().fill(Color.accentColor)
                .frame(width: size, height: size)
                .position(x: sel.minX, y: sel.minY)
            Rectangle().fill(Color.accentColor)
                .frame(width: size, height: size)
                .position(x: sel.maxX, y: sel.minY)
            Rectangle().fill(Color.accentColor)
                .frame(width: size, height: size)
                .position(x: sel.minX, y: sel.maxY)
            Rectangle().fill(Color.accentColor)
                .frame(width: size, height: size)
                .position(x: sel.maxX, y: sel.maxY)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Dimension Badge

    private func dimensionBadge(for sel: CGRect) -> some View {
        let badgeY = sel.origin.y > 28 ? (sel.origin.y - 14) : (sel.origin.y + 16)
        let retinaW = Int(round(sel.width * manager.scaleFactor))
        let retinaH = Int(round(sel.height * manager.scaleFactor))

        return HStack(spacing: 4) {
            Text("\(Int(sel.width)) × \(Int(sel.height))")
                .font(.system(size: FS.caption, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
            Text("(\(retinaW)×\(retinaH) px)")
                .font(.system(size: FS.caption - 1, weight: .regular, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: Rad.sm, style: .continuous)
                .fill(Color.black.opacity(0.80))
                .overlay(RoundedRectangle(cornerRadius: Rad.sm).stroke(Color.white.opacity(0.15), lineWidth: 0.5))
        )
        .position(x: min(sel.minX + 85, sel.midX), y: badgeY)
        .allowsHitTesting(false)
    }

    // MARK: - Move Handle Bar

    private func moveHandleBar(for sel: CGRect, in geo: GeometryProxy) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                .font(.system(size: FS.caption - 1))
            Text(manager.isSpaceHeld ? tr("Đang di chuyển (Thả Space để vẽ)", "Moving (Release Space to draw)") : tr("Di chuyển (đè Space)", "Move (hold Space)"))
                .font(.system(size: FS.caption, weight: .semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2.5)
        .background(
            Capsule()
                .fill(manager.isSpaceHeld || manager.currentTool == .move ? Color.accentColor : Color.black.opacity(0.75))
                .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 0.5))
        )
        .foregroundStyle(.white)
        .position(x: sel.midX, y: max(14, sel.minY - 14))
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .named("canvasSpace"))
                .onChanged { val in
                    if !manager.isDraggingSelection {
                        manager.isDraggingSelection = true
                        manager.dragStartRect = manager.selectionRect
                    }
                    let newX = max(0, min(geo.size.width - manager.dragStartRect.width, manager.dragStartRect.origin.x + val.translation.width))
                    let newY = max(0, min(geo.size.height - manager.dragStartRect.height, manager.dragStartRect.origin.y + val.translation.height))
                    manager.selectionRect.origin = CGPoint(x: newX, y: newY)
                }
                .onEnded { _ in
                    manager.isDraggingSelection = false
                }
        )
    }

    // MARK: - Drag Inside Selection Logic (Pixel-Accurate: No Coordinate Offset!)

    private func handleInsideDragChange(value: DragGesture.Value, in geo: GeometryProxy) {
        // Holding Space OR using move tool -> Pan/Move selection box!
        if manager.isSpaceHeld || manager.currentTool == .move {
            if !manager.isDraggingSelection {
                manager.isDraggingSelection = true
                manager.dragStartRect = manager.selectionRect
            }
            let newX = max(0, min(geo.size.width - manager.dragStartRect.width, manager.dragStartRect.origin.x + value.translation.width))
            let newY = max(0, min(geo.size.height - manager.dragStartRect.height, manager.dragStartRect.origin.y + value.translation.height))
            manager.selectionRect.origin = CGPoint(x: newX, y: newY)
            return
        }

        guard !manager.isEditingText else { return }
        let currentPt = CGPoint(x: min(max(value.location.x, manager.selectionRect.minX), manager.selectionRect.maxX),
                                y: min(max(value.location.y, manager.selectionRect.minY), manager.selectionRect.maxY))

        switch manager.currentTool {
        case .move:
            if !manager.isDraggingSelection {
                manager.isDraggingSelection = true
                manager.dragStartRect = manager.selectionRect
            }
            let newX = max(0, min(geo.size.width - manager.dragStartRect.width, manager.dragStartRect.origin.x + value.translation.width))
            let newY = max(0, min(geo.size.height - manager.dragStartRect.height, manager.dragStartRect.origin.y + value.translation.height))
            manager.selectionRect.origin = CGPoint(x: newX, y: newY)

        case .text:
            break // A click opens the text editor when the gesture ends.

        case .blur:
            guard manager.blurredScreenImage != nil else { return }
            manager.activeStroke = DrawnStroke(tool: .blur, points: [value.startLocation, currentPt],
                                               colorHex: manager.selectedColorHex, lineWidth: 0)

        case .pen:
            if manager.activeStroke == nil {
                manager.activeStroke = DrawnStroke(
                    tool: .pen,
                    points: [value.startLocation, currentPt],
                    colorHex: manager.selectedColorHex,
                    lineWidth: 3.5
                )
            } else {
                manager.activeStroke?.points.append(currentPt)
            }

        case .marker:
            if manager.activeStroke == nil {
                manager.activeStroke = DrawnStroke(
                    tool: .marker,
                    points: [value.startLocation, currentPt],
                    colorHex: manager.selectedColorHex,
                    lineWidth: 14.0
                )
            } else {
                manager.activeStroke?.points.append(currentPt)
            }

        case .arrow:
            manager.activeStroke = DrawnStroke(
                tool: .arrow,
                points: [value.startLocation, currentPt],
                colorHex: manager.selectedColorHex,
                lineWidth: 3.5
            )

        case .rect:
            manager.activeStroke = DrawnStroke(
                tool: .rect,
                points: [value.startLocation, currentPt],
                colorHex: manager.selectedColorHex,
                lineWidth: 3.0
            )
        }
    }

    private func handleInsideDragEnd(value: DragGesture.Value, in geo: GeometryProxy) {
        if manager.isDraggingSelection || manager.currentTool == .move {
            manager.isDraggingSelection = false
        } else if manager.currentTool == .text {
            if !manager.isEditingText { manager.beginText(at: value.location) }
        } else {
            manager.finishActiveStroke()
        }
    }

    // MARK: - 8 Resize Handles

    private func resizeHandles(for sel: CGRect, in geo: GeometryProxy) -> some View {
        Group {
            handleView(at: CGPoint(x: sel.minX, y: sel.minY), handle: .topLeft, in: geo)
            handleView(at: CGPoint(x: sel.midX, y: sel.minY), handle: .topCenter, in: geo)
            handleView(at: CGPoint(x: sel.maxX, y: sel.minY), handle: .topRight, in: geo)

            handleView(at: CGPoint(x: sel.minX, y: sel.midY), handle: .midLeft, in: geo)
            handleView(at: CGPoint(x: sel.maxX, y: sel.midY), handle: .midRight, in: geo)

            handleView(at: CGPoint(x: sel.minX, y: sel.maxY), handle: .bottomLeft, in: geo)
            handleView(at: CGPoint(x: sel.midX, y: sel.maxY), handle: .bottomCenter, in: geo)
            handleView(at: CGPoint(x: sel.maxX, y: sel.maxY), handle: .bottomRight, in: geo)
        }
    }

    private func handleView(at point: CGPoint, handle: ResizeHandle, in geo: GeometryProxy) -> some View {
        Circle()
            .fill(Color.white)
            .frame(width: 9, height: 9)
            .overlay(Circle().stroke(Color.accentColor, lineWidth: 1.5))
            .shadow(color: Color.black.opacity(0.3), radius: 2)
            .position(point)
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .named("canvasSpace"))
                    .onChanged { val in
                        if manager.activeHandle == nil {
                            manager.activeHandle = handle
                            manager.dragStartRect = manager.selectionRect
                        }
                        updateSelection(with: handle, translation: val.translation, in: geo)
                    }
                    .onEnded { _ in
                        manager.activeHandle = nil
                    }
            )
    }

    private func updateSelection(with handle: ResizeHandle, translation: CGSize, in geo: GeometryProxy) {
        let r = manager.dragStartRect
        var newRect = r

        switch handle {
        case .topLeft:
            newRect.origin.x = max(0, min(r.maxX - 20, r.origin.x + translation.width))
            newRect.origin.y = max(0, min(r.maxY - 20, r.origin.y + translation.height))
            newRect.size.width = r.maxX - newRect.origin.x
            newRect.size.height = r.maxY - newRect.origin.y

        case .topCenter:
            newRect.origin.y = max(0, min(r.maxY - 20, r.origin.y + translation.height))
            newRect.size.height = r.maxY - newRect.origin.y

        case .topRight:
            newRect.origin.y = max(0, min(r.maxY - 20, r.origin.y + translation.height))
            newRect.size.width = max(20, min(geo.size.width - r.minX, r.width + translation.width))
            newRect.size.height = r.maxY - newRect.origin.y

        case .midLeft:
            newRect.origin.x = max(0, min(r.maxX - 20, r.origin.x + translation.width))
            newRect.size.width = r.maxX - newRect.origin.x

        case .midRight:
            newRect.size.width = max(20, min(geo.size.width - r.minX, r.width + translation.width))

        case .bottomLeft:
            newRect.origin.x = max(0, min(r.maxX - 20, r.origin.x + translation.width))
            newRect.size.width = r.maxX - newRect.origin.x
            newRect.size.height = max(20, min(geo.size.height - r.minY, r.height + translation.height))

        case .bottomCenter:
            newRect.size.height = max(20, min(geo.size.height - r.minY, r.height + translation.height))

        case .bottomRight:
            newRect.size.width = max(20, min(geo.size.width - r.minX, r.width + translation.width))
            newRect.size.height = max(20, min(geo.size.height - r.minY, r.height + translation.height))
        }

        manager.selectionRect = newRect
    }

    // MARK: - LightShot Floating Toolbars

    private func floatingToolbars(for sel: CGRect, in geo: GeometryProxy) -> some View {
        // Position Side Drawing Bar (default right side of selection, or flip to left if near screen edge)
        let sideBarW: CGFloat = 36
        let sideBarH: CGFloat = 340
        let sideOnRight = (sel.maxX + sideBarW + 12) <= geo.size.width
        let sideX = sideOnRight ? (sel.maxX + 6) : max(6, sel.minX - sideBarW - 6)
        let sideY = max(10, min(geo.size.height - sideBarH - 10, max(10, sel.minY)))

        // Position Bottom Action Bar (default bottom of selection, or flip to top if near screen edge)
        let bottomBarH: CGFloat = 38
        let bottomOnBelow = (sel.maxY + bottomBarH + 12) <= geo.size.height
        var bottomY = bottomOnBelow ? (sel.maxY + 6) : max(10, sel.minY - bottomBarH - 6)
        let bottomBarW: CGFloat = min(280, geo.size.width - 20)
        let bottomX = min(geo.size.width - bottomBarW - 10, max(10, sel.maxX - bottomBarW))
        let sideBounds = CGRect(x: sideX, y: sideY, width: sideBarW, height: sideBarH)
        if sideBounds.intersects(CGRect(x: bottomX, y: bottomY, width: bottomBarW, height: bottomBarH)) {
            bottomY = sideBounds.maxY + bottomBarH + 6 <= geo.size.height
                ? sideBounds.maxY + 6 : max(10, sideY - bottomBarH - 6)
        }

        return Group {
            // 1. Right Side Toolbar: Drawing Tools & Color Palette
            sideDrawingToolbar
                .frame(width: sideBarW)
                .offset(x: sideX, y: sideY)

            // 2. Bottom Toolbar: Copy (⌘C), Save (⌘S), Close (⎋)
            bottomActionBar
                .frame(width: bottomBarW)
                .offset(x: bottomX, y: bottomY)

            if manager.currentTool == .text || manager.currentTool == .blur || manager.annotationError != nil {
                annotationStatus
                    .frame(maxWidth: min(360, geo.size.width - 20))
                    .position(x: min(geo.size.width - min(360, geo.size.width - 20) / 2 - 10,
                                     max(min(360, geo.size.width - 20) / 2 + 10, sel.midX)),
                              y: min(geo.size.height - 18, max(18, bottomY + bottomBarH + 20)))
            }

            // 3. Color Palette Popover (when expanded)
            if manager.isColorPaletteExpanded {
                colorPalettePill
                    .offset(x: min(geo.size.width - 38, max(6, sideOnRight ? sideX - 40 : sideX + sideBarW + 6)),
                            y: min(geo.size.height - 220, max(10, sideY + 100)))
            }
        }
    }

    // MARK: - Side Toolbar (Drawing Tools)

    private var sideDrawingToolbar: some View {
        VStack(spacing: 5) {
            // Pen tool (Bút vẽ - Default)
            toolButton(tool: .pen, icon: "pencil.tip", tooltip: tr("Bút vẽ (Highlight)", "Pen (Highlight)"))

            // Arrow tool (Mũi tên)
            toolButton(tool: .arrow, icon: "arrow.up.right", tooltip: tr("Mũi tên chỉ hướng", "Pointer Arrow"))

            // Rect tool (Khung chữ nhật)
            toolButton(tool: .rect, icon: "rectangle", tooltip: tr("Khung viền", "Rectangle"))

            // Marker tool (Dạ quang)
            toolButton(tool: .marker, icon: "highlighter", tooltip: tr("Bút dạ quang", "Highlighter"))

            toolButton(tool: .text, icon: "textformat", tooltip: tr("Chữ — nhấp để thêm hoặc sửa", "Text — click to add or edit"))
            toolButton(tool: .blur, icon: "square.grid.3x3.fill", tooltip: tr("Làm mờ pixel — kéo khoanh vùng", "Pixelate — drag an area"))

            // Move tool (Di chuyển khung)
            toolButton(tool: .move, icon: "arrow.up.and.down.and.arrow.left.and.right", tooltip: tr("Di chuyển vùng chọn", "Move Selection"))

            Divider().opacity(0.3).frame(width: 22)

            // Color Swatch Button (Màu bút - click to toggle palette)
            colorSwatchButton

            // Undo (Hoàn tác ⌘Z)
            undoButton

            // Clear All Annotations
            clearButton
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: Rad.md, style: .continuous)
                .fill(Color.black.opacity(0.82))
                .overlay(RoundedRectangle(cornerRadius: Rad.md).stroke(Color.white.opacity(0.18), lineWidth: 1))
        )
        .shadow(color: Color.black.opacity(0.4), radius: 8, y: 3)
    }

    private var colorSwatchButton: some View {
        Button {
            manager.isColorPaletteExpanded.toggle()
        } label: {
            Circle()
                .fill(Color(hex: manager.selectedColorHex))
                .frame(width: 18, height: 18)
                .overlay(Circle().stroke(Color.white.opacity(0.8), lineWidth: 1.5))
                .shadow(color: Color.black.opacity(0.3), radius: 2)
        }
        .buttonStyle(.plain)
        .help(tr("Chọn màu vẽ", "Choose Color"))
    }

    private var undoButton: some View {
        Button {
            manager.undoLastStroke()
        } label: {
            Image(systemName: "arrow.uturn.backward")
                .font(.system(size: FS.body))
                .foregroundStyle(!manager.canUndoAnnotations ? Color.white.opacity(0.3) : Color.white)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .disabled(!manager.canUndoAnnotations)
        .help(tr("Hoàn tác chú thích (⌘Z)", "Undo annotation (⌘Z)"))
    }

    @ViewBuilder
    private var clearButton: some View {
        if !manager.strokes.isEmpty {
            Button {
                manager.clearAllStrokes()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: FS.caption))
                    .foregroundStyle(Color.red.opacity(0.9))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help(tr("Xóa tất cả chú thích", "Clear all annotations"))
        }
    }

    private func toolButton(tool: ScreenshotTool, icon: String, tooltip: String) -> some View {
        let isSelected = manager.currentTool == tool

        return Button {
            manager.selectTool(tool)
        } label: {
            Image(systemName: icon)
                .font(.system(size: FS.body, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.75))
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: Rad.sm, style: .continuous)
                        .fill(isSelected ? Color.accentColor : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .accessibilityLabel(tooltip)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Color Palette Pill

    private var colorPalettePill: some View {
        VStack(spacing: 6) {
            ForEach(manager.availableColors, id: \.self) { hex in
                Button {
                    manager.selectedColorHex = hex
                    manager.isColorPaletteExpanded = false
                } label: {
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 20, height: 20)
                        .overlay(
                            Circle()
                                .stroke(manager.selectedColorHex == hex ? Color.white : Color.white.opacity(0.2), lineWidth: manager.selectedColorHex == hex ? 2 : 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: Rad.md, style: .continuous)
                .fill(Color.black.opacity(0.88))
                .overlay(RoundedRectangle(cornerRadius: Rad.md).stroke(Color.white.opacity(0.2), lineWidth: 1))
        )
        .shadow(color: Color.black.opacity(0.45), radius: 8)
    }

    // MARK: - Bottom Action Toolbar (Copy ⌘C, Save ⌘S, Close ⎋)

    private var bottomActionBar: some View {
        HStack(spacing: 6) {
            // 1. Copy Button (⌘C)
            Button {
                manager.copyToClipboard()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "doc.on.doc.fill")
                        .font(.system(size: FS.caption))
                    Text(tr("Sao chép (⌘C)", "Copy (⌘C)"))
                        .font(.system(size: FS.caption, weight: .semibold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: Rad.sm, style: .continuous)
                        .fill(Color.accentColor)
                )
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(!manager.canExport)
            .help(tr("Sao chép ảnh chất lượng cao vào Clipboard (⌘C)", "Copy high-res image to clipboard (⌘C)"))

            // 2. Save Button (⌘S -> Downloads/Screenshots)
            Button {
                manager.saveToDownloads()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.to.line.compact")
                        .font(.system(size: FS.caption))
                    Text(tr("Lưu ảnh (⌘S)", "Save (⌘S)"))
                        .font(.system(size: FS.caption, weight: .semibold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: Rad.sm, style: .continuous)
                        .fill(Color.white.opacity(0.16))
                )
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(!manager.canExport)
            .help(tr("Lưu ảnh vào thư mục Downloads/Screenshots (⌘S)", "Save image to Downloads/Screenshots (⌘S)"))

            // 3. Cancel Button (⎋ Esc)
            Button {
                manager.cancelCapture()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: FS.caption, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .help(tr("Huỷ bỏ (⎋ Esc)", "Cancel (⎋ Esc)"))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: Rad.md, style: .continuous)
                .fill(Color.black.opacity(0.85))
                .overlay(RoundedRectangle(cornerRadius: Rad.md).stroke(Color.white.opacity(0.18), lineWidth: 1))
        )
        .shadow(color: Color.black.opacity(0.4), radius: 8, y: 3)
    }
}

// Native editing preserves Vietnamese IME, selection, paste and undo while the global tap passes keys through.
private struct ScreenshotTextInput: NSViewRepresentable {
    @Binding var text: String
    var onCommit: () -> Void
    var onCancel: () -> Void
    var onSave: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.borderType = .bezelBorder
        scroll.hasVerticalScroller = true
        let editor = AnnotationTextView(frame: NSRect(x: 0, y: 0, width: 280, height: 76))
        editor.isRichText = false
        editor.allowsUndo = true
        editor.font = NSFont.systemFont(ofSize: FS.subhead)
        editor.textColor = .textColor
        editor.backgroundColor = .textBackgroundColor
        editor.textContainerInset = NSSize(width: 6, height: 6)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.delegate = context.coordinator
        editor.string = text
        editor.onCommit = onCommit
        editor.onCancel = onCancel
        editor.onSave = onSave
        scroll.documentView = editor
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? AnnotationTextView else { return }
        if editor.string != text && !editor.hasMarkedText() { editor.string = text }
        editor.onCommit = onCommit
        editor.onCancel = onCancel
        editor.onSave = onSave
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ScreenshotTextInput
        init(_ parent: ScreenshotTextInput) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            parent.text = editor.string
        }
    }
}

private final class AnnotationTextView: NSTextView {
    // Each draft owns its undo history, independent from the window and annotations.
    private let textUndoManager = UndoManager()
    override var undoManager: UndoManager? { textUndoManager }
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?
    var onSave: (() -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let targetWindow = window else { return }
        DispatchQueue.main.async { [weak self, weak targetWindow] in
            guard let self, let targetWindow, self.window === targetWindow else { return }
            targetWindow.makeKey()
            targetWindow.makeFirstResponder(self)
            self.setSelectedRange(NSRange(location: (self.string as NSString).length, length: 0))
        }
    }

    // Menu-bar apps have no standard Edit menu to route these key equivalents.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == .command || flags == [.command, .shift] else {
            return super.performKeyEquivalent(with: event)
        }
        switch event.keyCode {
        case 0: selectAll(nil)
        case 8: copy(nil)
        case 9: paste(nil)
        case 7: cut(nil)
        case 6:
            if flags.contains(.shift) { undoManager?.redo() }
            else { undoManager?.undo() }
            // Explicit key-equivalent routing bypasses the usual Edit-menu action.
            // Synchronize the binding now so SwiftUI cannot restore the pre-undo draft.
            didChangeText()
        case 1:
            guard !hasMarkedText() else { return true }
            onCommit?()
            onSave?()
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }

    override func keyDown(with event: NSEvent) {
        // Marked text must first be committed by the input method, not exported as a half-composed word.
        if !hasMarkedText() {
            if event.keyCode == 53 { onCancel?(); return }
            if (event.keyCode == 36 || event.keyCode == 76) && !event.modifierFlags.contains(.shift) {
                onCommit?(); return
            }
            if event.modifierFlags.contains(.command), event.keyCode == 1 {
                onCommit?()
                onSave?()
                return
            }
        }
        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

// MARK: - Cutout Veil Shape (Even-Odd rule punches transparent hole for selection)

private struct CutoutVeil: Shape {
    var cutout: CGRect

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        if cutout.width > 0 && cutout.height > 0 {
            path.addRect(cutout)
        }
        return path
    }
}

// MARK: - Drawn Annotations Canvas

private struct AnnotationsCanvas: View {
    let strokes: [DrawnStroke]
    let activeStroke: DrawnStroke?
    let clipRect: CGRect
    let blurredImage: CGImage?
    let scale: CGFloat

    var body: some View {
        Canvas { context, _ in
            context.clip(to: Path(clipRect))
            context.withCGContext { cg in
                for stroke in strokes {
                    ScreenshotAnnotationRenderer.draw(stroke, in: cg, blurredImage: blurredImage, scale: scale)
                }
                if let activeStroke {
                    ScreenshotAnnotationRenderer.draw(activeStroke, in: cg, blurredImage: blurredImage, scale: scale)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Hex Color Helper

private extension Color {
    init(hex: String) {
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: clean).scanHexInt64(&int)
        let r, g, b: Double
        if clean.count == 6 {
            r = Double((int >> 16) & 0xFF) / 255.0
            g = Double((int >> 8) & 0xFF) / 255.0
            b = Double(int & 0xFF) / 255.0
        } else {
            r = 1.0; g = 0.23; b = 0.19
        }
        self.init(red: r, green: g, blue: b)
    }
}
