import SwiftUI
import AppKit

// MARK: - LightShot-Style Screenshot Overlay View

public struct ScreenshotOverlayView: View {
    @ObservedObject var manager: ScreenshotManager

    public init(manager: ScreenshotManager) {
        self.manager = manager
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                // 1. Base Frozen Screen Image
                if let nsImage = manager.screenNSImage {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .allowsHitTesting(false)
                }

                // 2. Dark Translucent Veil with Cutout Hole for Selection
                CutoutVeil(cutout: manager.hasSelection ? manager.selectionRect : .zero)
                    .fill(Color.black.opacity(0.48), style: FillStyle(eoFill: true))
                    .frame(width: geo.size.width, height: geo.size.height)
                    // Initial area selection drag gesture
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .local)
                            .onChanged { value in
                                if !manager.hasSelection {
                                    let minX = max(0, min(value.startLocation.x, value.location.x))
                                    let minY = max(0, min(value.startLocation.y, value.location.y))
                                    let w = min(geo.size.width - minX, abs(value.location.x - value.startLocation.x))
                                    let h = min(geo.size.height - minY, abs(value.location.y - value.startLocation.y))
                                    manager.selectionRect = CGRect(x: minX, y: minY, width: w, height: h)
                                }
                            }
                            .onEnded { value in
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
                } else {
                    // Initial helpful hint at top center
                    initialHintBar(in: geo)
                }
            }
        }
        .edgesIgnoringSafeArea(.all)
    }

    // MARK: - Initial Hint Bar

    private func initialHintBar(in geo: GeometryProxy) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "viewfinder")
                .font(.system(size: FS.body, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Text(tr("Kéo chuột để chọn vùng chụp ảnh • ⎋ Huỷ", "Click & drag to select capture area • ⎋ Cancel"))
                .font(.system(size: FS.label, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.75))
                .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
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
                strokes: manager.strokes,
                activeStroke: manager.activeStroke,
                clipRect: sel
            )
            .frame(width: geo.size.width, height: geo.size.height)
            .allowsHitTesting(false)

            // Selection Boundary Border
            Rectangle()
                .stroke(Color.accentColor, lineWidth: 1.5)
                .frame(width: sel.width, height: sel.height)
                .offset(x: sel.origin.x, y: sel.origin.y)
                .allowsHitTesting(false)

            // Dimension Badge Pill (Top-left above selection)
            dimensionBadge(for: sel)

            // Dedicated Move Grab Bar (Top-center of selection box)
            moveHandleBar(for: sel, in: geo)

            // Interactive Drawing Area inside Selection Box
            Color.clear
                .contentShape(Rectangle())
                .frame(width: max(0, sel.width), height: max(0, sel.height))
                .offset(x: sel.origin.x, y: sel.origin.y)
                .gesture(
                    DragGesture(minimumDistance: 1, coordinateSpace: .local)
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
        }
    }

    // MARK: - Dimension Badge

    private func dimensionBadge(for sel: CGRect) -> some View {
        let badgeY = max(8, sel.origin.y - 26)
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
        .offset(x: sel.origin.x, y: badgeY)
        .allowsHitTesting(false)
    }

    // MARK: - Move Handle Bar

    private func moveHandleBar(for sel: CGRect, in geo: GeometryProxy) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                .font(.system(size: FS.caption - 1))
            Text(tr("Di chuyển", "Move"))
                .font(.system(size: FS.caption, weight: .semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2.5)
        .background(
            Capsule()
                .fill(manager.currentTool == .move ? Color.accentColor : Color.black.opacity(0.75))
                .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 0.5))
        )
        .foregroundStyle(.white)
        .position(x: sel.midX, y: max(14, sel.minY - 14))
        .gesture(
            DragGesture(minimumDistance: 1)
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

    // MARK: - Drag Inside Selection Logic

    private func handleInsideDragChange(value: DragGesture.Value, in geo: GeometryProxy) {
        let absLocation = CGPoint(
            x: manager.selectionRect.origin.x + value.location.x,
            y: manager.selectionRect.origin.y + value.location.y
        )

        switch manager.currentTool {
        case .move:
            if !manager.isDraggingSelection {
                manager.isDraggingSelection = true
                manager.dragStartRect = manager.selectionRect
            }
            let newX = max(0, min(geo.size.width - manager.dragStartRect.width, manager.dragStartRect.origin.x + value.translation.width))
            let newY = max(0, min(geo.size.height - manager.dragStartRect.height, manager.dragStartRect.origin.y + value.translation.height))
            manager.selectionRect.origin = CGPoint(x: newX, y: newY)

        case .pen:
            if manager.activeStroke == nil {
                let startPt = CGPoint(
                    x: manager.selectionRect.origin.x + value.startLocation.x,
                    y: manager.selectionRect.origin.y + value.startLocation.y
                )
                manager.activeStroke = DrawnStroke(
                    tool: .pen,
                    points: [startPt, absLocation],
                    colorHex: manager.selectedColorHex,
                    lineWidth: 3.5
                )
            } else {
                manager.activeStroke?.points.append(absLocation)
            }

        case .marker:
            if manager.activeStroke == nil {
                let startPt = CGPoint(
                    x: manager.selectionRect.origin.x + value.startLocation.x,
                    y: manager.selectionRect.origin.y + value.startLocation.y
                )
                manager.activeStroke = DrawnStroke(
                    tool: .marker,
                    points: [startPt, absLocation],
                    colorHex: manager.selectedColorHex,
                    lineWidth: 14.0
                )
            } else {
                manager.activeStroke?.points.append(absLocation)
            }

        case .arrow:
            let startPt = CGPoint(
                x: manager.selectionRect.origin.x + value.startLocation.x,
                y: manager.selectionRect.origin.y + value.startLocation.y
            )
            manager.activeStroke = DrawnStroke(
                tool: .arrow,
                points: [startPt, absLocation],
                colorHex: manager.selectedColorHex,
                lineWidth: 3.5
            )

        case .rect:
            let startPt = CGPoint(
                x: manager.selectionRect.origin.x + value.startLocation.x,
                y: manager.selectionRect.origin.y + value.startLocation.y
            )
            manager.activeStroke = DrawnStroke(
                tool: .rect,
                points: [startPt, absLocation],
                colorHex: manager.selectedColorHex,
                lineWidth: 3.0
            )
        }
    }

    private func handleInsideDragEnd(value: DragGesture.Value, in geo: GeometryProxy) {
        if manager.currentTool == .move {
            manager.isDraggingSelection = false
        } else if let stroke = manager.activeStroke {
            manager.strokes.append(stroke)
            manager.activeStroke = nil
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
                DragGesture(minimumDistance: 1)
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
        let sideBarH: CGFloat = 240
        let sideOnRight = (sel.maxX + sideBarW + 12) <= geo.size.width
        let sideX = sideOnRight ? (sel.maxX + 6) : max(6, sel.minX - sideBarW - 6)
        let sideY = min(geo.size.height - sideBarH - 10, max(10, sel.minY))

        // Position Bottom Action Bar (default bottom of selection, or flip to top if near screen edge)
        let bottomBarH: CGFloat = 38
        let bottomOnBelow = (sel.maxY + bottomBarH + 12) <= geo.size.height
        let bottomY = bottomOnBelow ? (sel.maxY + 6) : max(10, sel.minY - bottomBarH - 6)
        let bottomX = min(geo.size.width - 240, max(10, sel.maxX - 220))

        return Group {
            // 1. Right Side Toolbar: Drawing Tools & Color Palette
            sideDrawingToolbar
                .frame(width: sideBarW)
                .offset(x: sideX, y: sideY)

            // 2. Bottom Toolbar: Copy (⌘C), Save (⌘V), Close (⎋)
            bottomActionBar
                .offset(x: bottomX, y: bottomY)

            // 3. Color Palette Popover (when expanded)
            if manager.isColorPaletteExpanded {
                colorPalettePill
                    .offset(x: sideOnRight ? (sideX + sideBarW + 6) : (sideX - 160), y: sideY + 120)
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
                .foregroundStyle(manager.strokes.isEmpty ? Color.white.opacity(0.3) : Color.white)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .disabled(manager.strokes.isEmpty)
        .help(tr("Hoàn tác nét vẽ (⌘Z)", "Undo stroke (⌘Z)"))
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
            manager.currentTool = tool
        } label: {
            Image(systemName: icon)
                .font(.system(size: FS.body, weight: isSelected ? .bold : .medium))
                .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.75))
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: Rad.sm, style: .continuous)
                        .fill(isSelected ? Color.accentColor : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .help(tooltip)
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

    // MARK: - Bottom Action Toolbar (Copy ⌘C, Save ⌘V, Close ⎋)

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
            .help(tr("Sao chép ảnh chất lượng cao vào Clipboard (⌘C)", "Copy high-res image to clipboard (⌘C)"))

            // 2. Save Button (⌘V / ⌘S -> Downloads/Screenshots)
            Button {
                manager.saveToDownloads()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.to.line.compact")
                        .font(.system(size: FS.caption))
                    Text(tr("Lưu ảnh (⌘V)", "Save (⌘V)"))
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
            .help(tr("Lưu ảnh vào thư mục Downloads/Screenshots (⌘V)", "Save image to Downloads/Screenshots (⌘V)"))

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

    var body: some View {
        Canvas { context, size in
            // Clip drawing strictly to the selection boundary
            if clipRect.width > 0 && clipRect.height > 0 {
                context.clip(to: Path(clipRect))
            }

            for stroke in strokes {
                renderStroke(stroke, into: &context)
            }

            if let active = activeStroke {
                renderStroke(active, into: &context)
            }
        }
    }

    private func renderStroke(_ stroke: DrawnStroke, into context: inout GraphicsContext) {
        guard !stroke.points.isEmpty else { return }

        var ctx = context
        if stroke.tool == .marker {
            ctx.opacity = 0.38
        }

        let strokeColor = Color(hex: stroke.colorHex)

        switch stroke.tool {
        case .pen, .marker:
            var path = Path()
            path.move(to: stroke.points[0])
            for pt in stroke.points.dropFirst() {
                path.addLine(to: pt)
            }
            ctx.stroke(
                path,
                with: .color(strokeColor),
                style: StrokeStyle(lineWidth: stroke.lineWidth, lineCap: .round, lineJoin: .round)
            )

        case .arrow:
            guard stroke.points.count >= 2 else { break }
            let start = stroke.points[0]
            let end = stroke.points[stroke.points.count - 1]

            var path = Path()
            path.move(to: start)
            path.addLine(to: end)

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

            path.move(to: p1)
            path.addLine(to: end)
            path.addLine(to: p2)

            ctx.stroke(
                path,
                with: .color(strokeColor),
                style: StrokeStyle(lineWidth: stroke.lineWidth, lineCap: .round, lineJoin: .round)
            )

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
            ctx.stroke(
                Path(rect),
                with: .color(strokeColor),
                style: StrokeStyle(lineWidth: stroke.lineWidth, lineCap: .round, lineJoin: .round)
            )

        case .move:
            break
        }
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
