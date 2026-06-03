import PencilKit
import SwiftUI

struct PencilCanvasView: View {
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

    var body: some View {
        PencilCanvasRepresentable(
            drawing: $drawing,
            zoomScale: $zoomScale,
            selectedTool: $selectedTool,
            controller: controller,
            onDrawingChange: onDrawingChange,
            isCanvasActive: isCanvasActive,
            inkColor: inkColor,
            pencilWidth: pencilWidth,
            penWidth: penWidth,
            highlighterWidth: highlighterWidth,
            eraserType: eraserType,
            isRulerActive: isRulerActive,
            paperStyle: paperStyle,
            viewportMode: viewportMode
        )
            .frame(minHeight: 360)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.gray.opacity(0.25), lineWidth: 1)
            )
    }
}
