import PencilKit
import SwiftUI
import Combine

enum CanvasToolKind: String, CaseIterable {
    case pencil
    case pen
    case highlighter
    case eraser
    case lasso

    var systemImageName: String {
        switch self {
        case .pencil:
            return "pencil"
        case .pen:
            return "pencil.tip"
        case .highlighter:
            return "highlighter"
        case .eraser:
            return "eraser"
        case .lasso:
            return "lasso"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .pencil:
            return "Blýantur"
        case .pen:
            return "Penni"
        case .highlighter:
            return "Yfirstrikunarpenni"
        case .eraser:
            return "Strokleður"
        case .lasso:
            return "Lasso"
        }
    }

    static let notebookEnabledTools: [CanvasToolKind] = [.pen, .eraser, .lasso]
    static let examEnabledTools: [CanvasToolKind] = [.pen, .eraser, .lasso]
}

enum PaperStyle: String, CaseIterable {
    case blank
    case ruled
    case squared

    var displayName: String {
        switch self {
        case .blank:
            return "Autt"
        case .ruled:
            return "Línustrikað"
        case .squared:
            return "Reitað"
        }
    }
}

enum CanvasViewportMode {
    case fitWidth
    case fitPage
}

@MainActor
final class PencilCanvasController: ObservableObject {
    weak var canvasView: PKCanvasView?
    private var drawingSnapshot: PKDrawing = PKDrawing()
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false

    func attach(_ canvasView: PKCanvasView) {
        let didChangeCanvas = self.canvasView !== canvasView
        self.canvasView = canvasView
        drawingSnapshot = canvasView.drawing
        guard didChangeCanvas else { return }
        DispatchQueue.main.async { [weak self] in
            self?.refreshUndoState()
        }
    }

    func undo() {
        canvasView?.undoManager?.undo()
        refreshUndoState()
    }

    func redo() {
        canvasView?.undoManager?.redo()
        refreshUndoState()
    }

    func refreshUndoState() {
        let nextCanUndo = canvasView?.undoManager?.canUndo ?? false
        let nextCanRedo = canvasView?.undoManager?.canRedo ?? false

        if canUndo != nextCanUndo {
            canUndo = nextCanUndo
        }
        if canRedo != nextCanRedo {
            canRedo = nextCanRedo
        }
    }

    func currentDrawing() -> PKDrawing? {
        canvasView?.drawing ?? drawingSnapshot
    }

    func updateDrawingSnapshot(_ drawing: PKDrawing) {
        drawingSnapshot = drawing
    }
}

struct PencilCanvasRepresentable: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    @Binding var zoomScale: CGFloat
    @Binding var selectedTool: CanvasToolKind
    let controller: PencilCanvasController
    let onDrawingChange: ((PKDrawing) -> Void)?
    let isCanvasActive: Bool
    let inkColor: UIColor
    let pencilWidth: CGFloat
    let penWidth: CGFloat
    let highlighterWidth: CGFloat
    let eraserType: PKEraserTool.EraserType
    let isRulerActive: Bool
    let paperStyle: PaperStyle
    let viewportMode: CanvasViewportMode

    init(
        drawing: Binding<PKDrawing>,
        zoomScale: Binding<CGFloat>,
        selectedTool: Binding<CanvasToolKind>,
        controller: PencilCanvasController,
        onDrawingChange: ((PKDrawing) -> Void)? = nil,
        isCanvasActive: Bool = true,
        inkColor: UIColor,
        pencilWidth: CGFloat,
        penWidth: CGFloat,
        highlighterWidth: CGFloat,
        eraserType: PKEraserTool.EraserType,
        isRulerActive: Bool,
        paperStyle: PaperStyle,
        viewportMode: CanvasViewportMode = .fitWidth
    ) {
        self._drawing = drawing
        self._zoomScale = zoomScale
        self._selectedTool = selectedTool
        self.controller = controller
        self.onDrawingChange = onDrawingChange
        self.isCanvasActive = isCanvasActive
        self.inkColor = inkColor
        self.pencilWidth = pencilWidth
        self.penWidth = penWidth
        self.highlighterWidth = highlighterWidth
        self.eraserType = eraserType
        self.isRulerActive = isRulerActive
        self.paperStyle = paperStyle
        self.viewportMode = viewportMode
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvasView = PKCanvasView()
        context.coordinator.canvasView = canvasView
        canvasView.drawing = drawing
        canvasView.drawingPolicy = .pencilOnly
        canvasView.alwaysBounceVertical = true
        canvasView.alwaysBounceHorizontal = true
        canvasView.bouncesZoom = true
        canvasView.contentSize = Coordinator.pageSize
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        context.coordinator.installPaperBackgroundIfNeeded(in: canvasView)
        context.coordinator.updatePaperBackground(for: canvasView, style: paperStyle)
        applySelectedTool(to: canvasView)
        canvasView.isRulerActive = isRulerActive
        canvasView.delegate = context.coordinator
        let pencilInteraction = UIPencilInteraction()
        pencilInteraction.delegate = context.coordinator
        canvasView.addInteraction(pencilInteraction)
        context.coordinator.configureViewport(for: canvasView, force: true)
        let coordinator = context.coordinator
        DispatchQueue.main.async { [weak canvasView] in
            guard let canvasView else { return }
            coordinator.refreshPresentationIfNeeded(for: canvasView)
            coordinator.configureViewport(for: canvasView, force: true)
        }

        controller.attach(canvasView)
        controller.updateDrawingSnapshot(drawing)
        if isCanvasActive {
            canvasView.becomeFirstResponder()
        }
        return canvasView
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.canvasView = uiView
        if controller.canvasView !== uiView {
            controller.attach(uiView)
        }

        if uiView.drawing.dataRepresentation() != drawing.dataRepresentation() {
            let coordinator = context.coordinator
            coordinator.isApplyingDrawingFromSwiftUI = true
            uiView.drawing = drawing
            DispatchQueue.main.async {
                coordinator.isApplyingDrawingFromSwiftUI = false
            }
        }

        applySelectedTool(to: uiView)
        if uiView.isRulerActive != isRulerActive {
            DispatchQueue.main.async {
                if uiView.isRulerActive != isRulerActive {
                    uiView.isRulerActive = isRulerActive
                }
            }
        }
        context.coordinator.refreshPresentationIfNeeded(for: uiView)
        DispatchQueue.main.async {
            if isCanvasActive {
                if !uiView.isFirstResponder {
                    uiView.becomeFirstResponder()
                }
            } else if uiView.isFirstResponder {
                uiView.resignFirstResponder()
            }
        }
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate, UIPencilInteractionDelegate {
        static let pageSize = CGSize(width: 1240, height: 1754)

        var parent: PencilCanvasRepresentable
        weak var canvasView: PKCanvasView?
        var isApplyingDrawingFromSwiftUI = false
        var isApplyingZoomFromSwiftUI = false
        private weak var paperContainerView: UIView?
        private var lastPaperStyle: PaperStyle?
        private var hasAppliedInitialViewport = false
        private var lastBoundsSize: CGSize = .zero
        private var lastViewportMode: CanvasViewportMode?
        private var lastPresentationBoundsSize: CGSize = .zero
        private var lastPresentationStyle: PaperStyle?
        private var lastPresentationViewportMode: CanvasViewportMode?

        init(parent: PencilCanvasRepresentable) {
            self.parent = parent
        }

        func pencilInteractionDidTap(_: UIPencilInteraction) {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard self.parent.isCanvasActive else { return }
                guard let canvasView = self.canvasView else { return }
                guard self.parent.controller.canvasView === canvasView else { return }
                switch self.parent.selectedTool {
                case .pen:
                    self.parent.selectedTool = .eraser
                case .eraser:
                    self.parent.selectedTool = .pen
                default:
                    break
                }
            }
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !isApplyingDrawingFromSwiftUI else { return }
            let updatedDrawing = canvasView.drawing
            parent.controller.updateDrawingSnapshot(updatedDrawing)
            parent.onDrawingChange?(updatedDrawing)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.parent.drawing.dataRepresentation() != updatedDrawing.dataRepresentation() {
                    self.parent.drawing = updatedDrawing
                }
                self.parent.controller.refreshUndoState()
            }
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            guard let canvasView = scrollView as? PKCanvasView else { return }
            guard !isApplyingZoomFromSwiftUI else { return }

            if parent.viewportMode == .fitWidth {
                centerContent(in: canvasView)
                let updatedZoom = canvasView.zoomScale
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    if abs(self.parent.zoomScale - updatedZoom) > 0.01 {
                        self.parent.zoomScale = updatedZoom
                    }
                }
            } else {
                centerContent(in: canvasView)
            }
        }

        func installPaperBackgroundIfNeeded(in canvasView: PKCanvasView) {
            let containerView = zoomContentContainer(in: canvasView)
            if paperContainerView !== containerView {
                paperContainerView = containerView
                lastPaperStyle = nil
            }
        }

        func updatePaperBackground(for canvasView: PKCanvasView?, style: PaperStyle) {
            guard let canvasView else { return }
            if !(canvasView.backgroundColor?.isEqual(UIColor.clear) ?? false) {
                canvasView.backgroundColor = .clear
            }
            if canvasView.isOpaque {
                canvasView.isOpaque = false
            }
            installPaperBackgroundIfNeeded(in: canvasView)
            let backgroundColor = PaperPatternFactory.backgroundColor(for: style)
            guard let paperContainerView else { return }
            if lastPaperStyle != style {
                paperContainerView.backgroundColor = backgroundColor
                paperContainerView.isOpaque = true
                lastPaperStyle = style
            }
        }

        func refreshPresentationIfNeeded(for canvasView: PKCanvasView) {
            let boundsSize = canvasView.bounds.size
            guard boundsSize.width > 0, boundsSize.height > 0 else { return }

            let boundsChanged = abs(lastPresentationBoundsSize.width - boundsSize.width) > 0.5 ||
                abs(lastPresentationBoundsSize.height - boundsSize.height) > 0.5
            let styleChanged = lastPresentationStyle != parent.paperStyle
            let viewportChanged = lastPresentationViewportMode != parent.viewportMode

            updatePaperBackground(for: canvasView, style: parent.paperStyle)
            if boundsChanged || styleChanged || viewportChanged {
                configureViewport(for: canvasView, force: false)
            }

            lastPresentationBoundsSize = boundsSize
            lastPresentationStyle = parent.paperStyle
            lastPresentationViewportMode = parent.viewportMode
        }

        private func zoomContentContainer(in canvasView: PKCanvasView) -> UIView {
            let largestSubview = canvasView.subviews.max { lhs, rhs in
                (lhs.bounds.width * lhs.bounds.height) < (rhs.bounds.width * rhs.bounds.height)
            }
            return largestSubview ?? canvasView
        }

        func configureViewport(for canvasView: PKCanvasView, force: Bool) {
            let boundsSize = canvasView.bounds.size
            guard boundsSize.width > 0, boundsSize.height > 0 else { return }

            let fitWidthScale = boundsSize.width / Self.pageSize.width
            let fitPageScale = min(
                boundsSize.width / Self.pageSize.width,
                boundsSize.height / Self.pageSize.height
            )

            let modeChanged = lastViewportMode != parent.viewportMode
            let boundsChanged = abs(lastBoundsSize.width - boundsSize.width) > 0.5 ||
                abs(lastBoundsSize.height - boundsSize.height) > 0.5
            lastViewportMode = parent.viewportMode
            lastBoundsSize = boundsSize

            if parent.viewportMode == .fitPage {
                let minimumScale = max(fitPageScale * 0.9, 0.08)
                let maximumScale = max(minimumScale + 0.6, fitWidthScale * 8)

                if abs(canvasView.minimumZoomScale - minimumScale) > 0.001 {
                    canvasView.minimumZoomScale = minimumScale
                }
                if abs(canvasView.maximumZoomScale - maximumScale) > 0.001 {
                    canvasView.maximumZoomScale = maximumScale
                }

                let initialScale = min(max(fitPageScale, minimumScale), maximumScale)
                if force || !hasAppliedInitialViewport || modeChanged || boundsChanged {
                    hasAppliedInitialViewport = true
                    applyZoom(initialScale, to: canvasView, recenterContentOffset: true, updateBinding: false)
                }

                centerContent(in: canvasView)
                return
            }

            let minimumScale: CGFloat
            minimumScale = max(fitPageScale, 0.15)
            let maximumScale = max(minimumScale + 0.6, fitWidthScale * 8)

            if abs(canvasView.minimumZoomScale - minimumScale) > 0.001 {
                canvasView.minimumZoomScale = minimumScale
            }
            if abs(canvasView.maximumZoomScale - maximumScale) > 0.001 {
                canvasView.maximumZoomScale = maximumScale
            }

            let preferredScale = fitWidthScale
            let requestedScale = parent.zoomScale > 0 ? parent.zoomScale : preferredScale
            let clampedRequested = min(max(requestedScale, minimumScale), maximumScale)

            let shouldApplyInitialScale = force || !hasAppliedInitialViewport || modeChanged
            if shouldApplyInitialScale {
                hasAppliedInitialViewport = true
                applyZoom(clampedRequested, to: canvasView, recenterContentOffset: true)
                return
            }

            if boundsChanged, canvasView.zoomScale < minimumScale {
                applyZoom(minimumScale, to: canvasView, recenterContentOffset: true)
                return
            }

            centerContent(in: canvasView)
        }

        private func applyZoom(
            _ zoom: CGFloat,
            to canvasView: PKCanvasView,
            recenterContentOffset: Bool,
            updateBinding: Bool = true
        ) {
            isApplyingZoomFromSwiftUI = true
            canvasView.setZoomScale(zoom, animated: false)
            let targetInset = centerContent(in: canvasView)
            if recenterContentOffset {
                canvasView.setContentOffset(
                    CGPoint(x: -targetInset.left, y: -targetInset.top),
                    animated: false
                )
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isApplyingZoomFromSwiftUI = false
                if updateBinding, abs(self.parent.zoomScale - zoom) > 0.01 {
                    self.parent.zoomScale = zoom
                }
            }
        }

        @discardableResult
        private func centerContent(in canvasView: PKCanvasView) -> UIEdgeInsets {
            let scaledWidth = Self.pageSize.width * canvasView.zoomScale
            let scaledHeight = Self.pageSize.height * canvasView.zoomScale

            let horizontalInset = max((canvasView.bounds.width - scaledWidth) * 0.5, 0)
            let verticalInset = max((canvasView.bounds.height - scaledHeight) * 0.5, 0)
            let targetInset = UIEdgeInsets(
                top: verticalInset,
                left: horizontalInset,
                bottom: verticalInset,
                right: horizontalInset
            )

            if !targetInset.isNearlyEqual(to: canvasView.contentInset) {
                canvasView.contentInset = targetInset
                canvasView.scrollIndicatorInsets = targetInset
            }
            return targetInset
        }
    }

    private func applySelectedTool(to canvasView: PKCanvasView) {
        let nextTool: PKTool

        switch selectedTool {
        case .pencil:
            nextTool = PKInkingTool(.pencil, color: inkColor, width: pencilWidth)
        case .pen:
            nextTool = PKInkingTool(.pen, color: inkColor, width: penWidth)
        case .highlighter:
            nextTool = PKInkingTool(.marker, color: inkColor, width: highlighterWidth)
        case .eraser:
            nextTool = PKEraserTool(eraserType)
        case .lasso:
            nextTool = PKLassoTool()
        }

        canvasView.tool = nextTool
    }
}

private enum PaperPatternFactory {
    private static var ruledPattern: UIColor?
    private static var squaredPattern: UIColor?

    static func backgroundColor(for style: PaperStyle) -> UIColor {
        switch style {
        case .blank:
            return UIColor(AppTheme.Auth.surface)
        case .ruled:
            if let ruledPattern { return ruledPattern }
            let created = UIColor(patternImage: makePatternImage(style: .ruled))
            ruledPattern = created
            return created
        case .squared:
            if let squaredPattern { return squaredPattern }
            let created = UIColor(patternImage: makePatternImage(style: .squared))
            squaredPattern = created
            return created
        }
    }

    private static func makePatternImage(style: PaperStyle) -> UIImage {
        let scale = UIScreen.main.scale
        let spacing: CGFloat = 28
        let tileSize = CGSize(width: spacing * 8, height: spacing * 8)
        let rendererFormat = UIGraphicsImageRendererFormat.default()
        rendererFormat.scale = scale
        rendererFormat.opaque = true
        let renderer = UIGraphicsImageRenderer(size: tileSize, format: rendererFormat)

        return renderer.image { context in
            let rect = CGRect(origin: .zero, size: tileSize)
            UIColor(AppTheme.Auth.surface).setFill()
            context.fill(rect)

            let lineWidth = 1 / scale
            let cgContext = context.cgContext
            cgContext.setLineWidth(lineWidth)

            switch style {
            case .blank:
                return
            case .ruled:
                cgContext.setStrokeColor(UIColor(AppTheme.Auth.border).withAlphaComponent(0.75).cgColor)
                var y = spacing * 0.5
                while y <= tileSize.height {
                    cgContext.move(to: CGPoint(x: 0, y: y))
                    cgContext.addLine(to: CGPoint(x: tileSize.width, y: y))
                    y += spacing
                }
                cgContext.strokePath()
            case .squared:
                cgContext.setStrokeColor(UIColor(AppTheme.Auth.border).withAlphaComponent(0.72).cgColor)
                var x: CGFloat = 0
                while x <= tileSize.width {
                    cgContext.move(to: CGPoint(x: x, y: 0))
                    cgContext.addLine(to: CGPoint(x: x, y: tileSize.height))
                    x += spacing
                }
                var y: CGFloat = 0
                while y <= tileSize.height {
                    cgContext.move(to: CGPoint(x: 0, y: y))
                    cgContext.addLine(to: CGPoint(x: tileSize.width, y: y))
                    y += spacing
                }
                cgContext.strokePath()
            }
        }
    }
}

private extension UIEdgeInsets {
    func isNearlyEqual(to other: UIEdgeInsets, tolerance: CGFloat = 0.5) -> Bool {
        abs(top - other.top) <= tolerance &&
            abs(left - other.left) <= tolerance &&
            abs(bottom - other.bottom) <= tolerance &&
            abs(right - other.right) <= tolerance
    }
}
