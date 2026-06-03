import SwiftUI
import UIKit
import Combine

struct ImagePicker: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    let onImagePicked: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_: UIImagePickerController, context _: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let parent: ImagePicker

        init(parent: ImagePicker) {
            self.parent = parent
        }

        func imagePickerControllerDidCancel(_: UIImagePickerController) {
            parent.dismiss()
        }

        func imagePickerController(
            _: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            parent.dismiss()
            if let image = info[.originalImage] as? UIImage {
                DispatchQueue.main.async {
                    self.parent.onImagePicked(image)
                }
            }
        }
    }
}

@MainActor
final class CropCanvasController: ObservableObject {
    fileprivate weak var canvasView: CropImageCanvasView?

    fileprivate func attach(_ canvasView: CropImageCanvasView) {
        self.canvasView = canvasView
    }

    func croppedImage(cropRectInView: CGRect) -> UIImage? {
        canvasView?.croppedImage(cropRectInView: cropRectInView)
    }

    func croppedImage(normalizedCropRect: CGRect) -> UIImage? {
        canvasView?.croppedImage(normalizedCropRect: normalizedCropRect)
    }
}

private final class CropImageCanvasView: UIView, UIScrollViewDelegate {
    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private var normalizedImage: UIImage?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(AppTheme.Auth.surfaceMuted)

        scrollView.delegate = self
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 6
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.bouncesZoom = true
        scrollView.backgroundColor = .clear

        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true

        addSubview(scrollView)
        scrollView.addSubview(imageView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scrollView.frame = bounds
        updateLayoutForCurrentImage()
    }

    func setImage(_ image: UIImage) {
        normalizedImage = normalizedUpImage(image)
        imageView.image = normalizedImage
        updateLayoutForCurrentImage()
    }

    private func updateLayoutForCurrentImage() {
        guard let image = normalizedImage, bounds.width > 0, bounds.height > 0 else { return }

        let imageSize = image.size
        imageView.frame = CGRect(origin: .zero, size: imageSize)
        scrollView.contentSize = imageSize

        // Start with the entire image visible (fit) instead of filling the viewport.
        let fitScale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        scrollView.minimumZoomScale = fitScale
        if scrollView.zoomScale < fitScale || scrollView.zoomScale == 1 {
            scrollView.zoomScale = fitScale
        }
        centerImageIfNeeded()
    }

    private func centerImageIfNeeded() {
        let boundsSize = scrollView.bounds.size
        var frameToCenter = imageView.frame

        frameToCenter.origin.x = frameToCenter.size.width < boundsSize.width
            ? (boundsSize.width - frameToCenter.size.width) / 2
            : 0
        frameToCenter.origin.y = frameToCenter.size.height < boundsSize.height
            ? (boundsSize.height - frameToCenter.size.height) / 2
            : 0
        imageView.frame = frameToCenter
    }

    func viewForZooming(in _: UIScrollView) -> UIView? {
        imageView
    }

    func scrollViewDidZoom(_: UIScrollView) {
        centerImageIfNeeded()
    }

    func croppedImage(cropRectInView: CGRect) -> UIImage? {
        guard let image = normalizedImage, let cgImage = image.cgImage else { return nil }

        let clampedCropRect = cropRectInView.intersection(bounds)
        guard !clampedCropRect.isNull, !clampedCropRect.isEmpty else {
            return image
        }

        // Convert from overlay/view coordinates to unscaled image-view coordinates.
        let imageRect = convert(clampedCropRect, to: imageView)
        let imageBounds = CGRect(origin: .zero, size: image.size)
        let clampedImageRect = imageRect.intersection(imageBounds)
        guard !clampedImageRect.isNull, !clampedImageRect.isEmpty else {
            return image
        }

        let pixelScale = image.scale
        let pixelRect = CGRect(
            x: clampedImageRect.origin.x * pixelScale,
            y: clampedImageRect.origin.y * pixelScale,
            width: clampedImageRect.size.width * pixelScale,
            height: clampedImageRect.size.height * pixelScale
        )
        .integral
        .intersection(CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))

        guard
            pixelRect.width > 1,
            pixelRect.height > 1,
            let cropped = cgImage.cropping(to: pixelRect)
        else {
            return image
        }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: .up)
    }

    func croppedImage(normalizedCropRect: CGRect) -> UIImage? {
        guard bounds.width > 0, bounds.height > 0 else { return normalizedImage }

        let minX = max(0, min(1, normalizedCropRect.minX))
        let minY = max(0, min(1, normalizedCropRect.minY))
        let maxX = max(minX, min(1, normalizedCropRect.maxX))
        let maxY = max(minY, min(1, normalizedCropRect.maxY))
        let rect = CGRect(
            x: minX * bounds.width,
            y: minY * bounds.height,
            width: (maxX - minX) * bounds.width,
            height: (maxY - minY) * bounds.height
        )
        return croppedImage(cropRectInView: rect)
    }

    private func normalizedUpImage(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let renderer = UIGraphicsImageRenderer(size: image.size)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }
}

private struct CropImageCanvasRepresentable: UIViewRepresentable {
    let image: UIImage
    let controller: CropCanvasController

    func makeUIView(context _: Context) -> CropImageCanvasView {
        let view = CropImageCanvasView()
        view.setImage(image)
        controller.attach(view)
        return view
    }

    func updateUIView(_ uiView: CropImageCanvasView, context _: Context) {
        uiView.setImage(image)
        controller.attach(uiView)
    }
}

struct ImageCropperSheet: View {
    let image: UIImage
    let onCancel: () -> Void
    let onConfirm: (UIImage) -> Void

    @StateObject private var controller = CropCanvasController()
    @State private var cropRectNormalized = CGRect(x: 0.05, y: 0.12, width: 0.9, height: 0.76)
    @State private var resizeStartRect: CGRect?
    private let minNormalizedWidth: CGFloat = 0.18
    private let minNormalizedHeight: CGFloat = 0.18
    private let handleSize: CGFloat = 36

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Færðu myndina með tveimur fingrum. Dragðu horn rammans til að breyta stærð.")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.Auth.textSecondary)

                GeometryReader { proxy in
                    let liveCanvasSize = proxy.size
                    let cropRect = cropRectInView(from: cropRectNormalized, size: liveCanvasSize)

                    ZStack {
                        CropImageCanvasRepresentable(image: image, controller: controller)

                        Path { path in
                            path.addRect(CGRect(origin: .zero, size: liveCanvasSize))
                            path.addRoundedRect(in: cropRect, cornerSize: CGSize(width: 8, height: 8))
                        }
                        .fill(Color.black.opacity(0.35), style: FillStyle(eoFill: true))
                        .allowsHitTesting(false)

                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white, lineWidth: 2)
                            .frame(width: cropRect.width, height: cropRect.height)
                            .position(x: cropRect.midX, y: cropRect.midY)
                            .contentShape(Rectangle())
                            .allowsHitTesting(false)

                        cropHandle(.topLeft, cropRect: cropRect, in: liveCanvasSize)
                        cropHandle(.topRight, cropRect: cropRect, in: liveCanvasSize)
                        cropHandle(.bottomLeft, cropRect: cropRect, in: liveCanvasSize)
                        cropHandle(.bottomRight, cropRect: cropRect, in: liveCanvasSize)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(AppTheme.Auth.border, lineWidth: 1)
                    )
                }
                .frame(minHeight: 360)

                Button("Endurstilla ramma") {
                    cropRectNormalized = CGRect(x: 0.05, y: 0.12, width: 0.9, height: 0.76)
                    resizeStartRect = nil
                }
                .buttonStyle(.bordered)
            }
            .padding(16)
            .background(AppTheme.Auth.background.ignoresSafeArea())
            .navigationTitle("Klippa mynd")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Hætta við") {
                        onCancel()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Nota mynd") {
                        onConfirm(controller.croppedImage(normalizedCropRect: cropRectNormalized) ?? image)
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    @ViewBuilder
    private func cropHandle(_ handle: CropHandle, cropRect: CGRect, in canvasSize: CGSize) -> some View {
        Circle()
            .fill(Color.white)
            .frame(width: handleSize, height: handleSize)
            .overlay(Circle().stroke(Color.black.opacity(0.25), lineWidth: 1))
            .position(adjustedHandlePosition(handle.position(in: cropRect), in: canvasSize))
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if resizeStartRect == nil {
                            resizeStartRect = cropRectNormalized
                        }
                        let start = resizeStartRect ?? cropRectNormalized
                        cropRectNormalized = resizedRect(
                            from: start,
                            handle: handle,
                            translation: value.translation,
                            in: canvasSize
                        )
                    }
                    .onEnded { _ in
                        resizeStartRect = nil
                    }
            )
    }

    private func adjustedHandlePosition(_ raw: CGPoint, in size: CGSize) -> CGPoint {
        let radius = (handleSize / 2) + 4
        return CGPoint(
            x: clamp(raw.x, min: radius, max: max(radius, size.width - radius)),
            y: clamp(raw.y, min: radius, max: max(radius, size.height - radius))
        )
    }

    private func resizedRect(from start: CGRect, handle: CropHandle, translation: CGSize, in size: CGSize) -> CGRect {
        let dx = translation.width / max(size.width, 1)
        let dy = translation.height / max(size.height, 1)

        var minX = start.minX
        var minY = start.minY
        var maxX = start.maxX
        var maxY = start.maxY

        switch handle {
        case .topLeft:
            minX = clamp(start.minX + dx, min: 0, max: start.maxX - minNormalizedWidth)
            minY = clamp(start.minY + dy, min: 0, max: start.maxY - minNormalizedHeight)
        case .topRight:
            maxX = clamp(start.maxX + dx, min: start.minX + minNormalizedWidth, max: 1)
            minY = clamp(start.minY + dy, min: 0, max: start.maxY - minNormalizedHeight)
        case .bottomLeft:
            minX = clamp(start.minX + dx, min: 0, max: start.maxX - minNormalizedWidth)
            maxY = clamp(start.maxY + dy, min: start.minY + minNormalizedHeight, max: 1)
        case .bottomRight:
            maxX = clamp(start.maxX + dx, min: start.minX + minNormalizedWidth, max: 1)
            maxY = clamp(start.maxY + dy, min: start.minY + minNormalizedHeight, max: 1)
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func cropRectInView(from normalizedRect: CGRect, size: CGSize) -> CGRect {
        CGRect(
            x: normalizedRect.origin.x * size.width,
            y: normalizedRect.origin.y * size.height,
            width: normalizedRect.size.width * size.width,
            height: normalizedRect.size.height * size.height
        )
    }

    private func clamp(_ value: CGFloat, min lowerBound: CGFloat, max upperBound: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, lowerBound), upperBound)
    }
}

private enum CropHandle {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    func position(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft:
            CGPoint(x: rect.minX, y: rect.minY)
        case .topRight:
            CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomLeft:
            CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomRight:
            CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }
}
