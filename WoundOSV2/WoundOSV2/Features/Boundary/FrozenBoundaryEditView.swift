import SwiftUI

/// On-device boundary draw + measure screen.
///
/// Replaces the server-side `BoundaryEditView` for the LiDAR clinical critical path.
/// The nurse draws the wound boundary directly on the frozen capture image, then
/// taps "Measure" to run the entire measurement pipeline on-device via
/// `MeasurementEngine.measure(...)`.
///
/// All gesture coordinates live in **screen space** while the user is drawing,
/// then are mapped to **image pixel space** at submit time using the displayed
/// image's `aspect-fit` rectangle.
struct FrozenBoundaryEditView: View {
    let snapshot: WoundCaptureSnapshot
    var onMeasured: ((PrimaryMeasurement) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var screenPoints: [CGPoint] = []
    @State private var isDrawing: Bool = false
    @State private var displayRect: CGRect = .zero  // image's aspect-fit rect inside the canvas
    @State private var isMeasuring: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            canvas
                .layoutPriority(1)
            instructionsBar
            actionButtons
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Trace the wound")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Measurement failed", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Canvas
    private var canvas: some View {
        GeometryReader { geometry in
            ZStack {
                Image(uiImage: snapshot.rgbImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .onAppear {
                        displayRect = aspectFitRect(
                            imageSize: CGSize(
                                width: snapshot.imageWidth,
                                height: snapshot.imageHeight
                            ),
                            in: geometry.size
                        )
                    }
                    .onChange(of: geometry.size) { newSize in
                        displayRect = aspectFitRect(
                            imageSize: CGSize(
                                width: snapshot.imageWidth,
                                height: snapshot.imageHeight
                            ),
                            in: newSize
                        )
                    }

                drawnPolygonOverlay
                    .allowsHitTesting(false)

                // Drawing surface
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .local)
                            .onChanged { value in
                                if !isDrawing {
                                    isDrawing = true
                                    screenPoints = []
                                }
                                let p = clampToDisplayRect(value.location)
                                // Sub-sample: only add points that are >2pt away from the last
                                if let last = screenPoints.last {
                                    let dx = p.x - last.x
                                    let dy = p.y - last.y
                                    if dx * dx + dy * dy < 4 { return }
                                }
                                screenPoints.append(p)
                            }
                            .onEnded { _ in
                                isDrawing = false
                                WOSHaptics.selection()
                            }
                    )
                if isMeasuring {
                    measuringOverlay
                }
            }
        }
    }

    private var drawnPolygonOverlay: some View {
        Canvas { context, _ in
            guard screenPoints.count >= 2 else { return }
            var path = Path()
            path.move(to: screenPoints[0])
            for p in screenPoints.dropFirst() {
                path.addLine(to: p)
            }
            // Close the polygon if we're done drawing
            if !isDrawing && screenPoints.count >= 3 {
                path.closeSubpath()
                context.fill(path, with: .color(WOSColors.accent.opacity(0.18)))
            }
            context.stroke(path, with: .color(WOSColors.accent), lineWidth: 2.5)

            // Draw vertex markers
            for p in screenPoints {
                let dot = CGRect(x: p.x - 2, y: p.y - 2, width: 4, height: 4)
                context.fill(Path(ellipseIn: dot), with: .color(.white))
            }
        }
    }

    // MARK: - Instructions
    private var instructionsBar: some View {
        let pointCount = screenPoints.count
        let label: String
        if pointCount == 0 {
            label = "Drag your finger around the wound edge"
        } else if pointCount < 8 {
            label = "Keep going — trace the full perimeter"
        } else {
            label = "Tap Measure when you're happy with the trace"
        }
        return HStack(spacing: WOSSpacing.sm) {
            Image(systemName: pointCount >= 8 ? "checkmark.circle.fill" : "hand.draw")
                .foregroundColor(pointCount >= 8 ? WOSColors.green : .white)
            Text(label)
                .font(WOSTypography.footnote)
                .foregroundColor(.white)
            Spacer()
            if pointCount > 0 {
                Text("\(pointCount) pts")
                    .font(WOSTypography.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, WOSSpacing.md)
        .padding(.vertical, WOSSpacing.sm)
        .background(Color.black.opacity(0.85))
    }

    // MARK: - Action buttons
    private var actionButtons: some View {
        HStack(spacing: WOSSpacing.md) {
            WOSButton(title: "Redo", icon: "arrow.uturn.backward", style: .secondary) {
                screenPoints = []
                WOSHaptics.selection()
            }
            .disabled(screenPoints.isEmpty || isMeasuring)

            WOSButton(title: "Measure", icon: "ruler", style: .primary) {
                handleMeasure()
            }
            .disabled(screenPoints.count < 3 || isMeasuring)
        }
        .padding(WOSSpacing.md)
        .background(Color.black)
    }

    private var measuringOverlay: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: WOSSpacing.md) {
                ProgressView()
                    .scaleEffect(1.4)
                    .tint(.white)
                Text("Computing measurements...")
                    .font(WOSTypography.headline)
                    .foregroundColor(.white)
            }
        }
    }

    // MARK: - Measure

    private func handleMeasure() {
        guard screenPoints.count >= 3 else { return }
        isMeasuring = true
        WOSHaptics.capture()

        let pixelPoints = screenPoints.map { screenToImagePixels($0) }

        Task {
            do {
                let measurement = try await MeasurementEngine.measure(
                    snapshot: snapshot,
                    nursePolygonPixels: pixelPoints
                )
                await MainActor.run {
                    isMeasuring = false
                    WOSHaptics.complete()
                    onMeasured?(measurement)
                }
            } catch {
                await MainActor.run {
                    isMeasuring = false
                    WOSHaptics.error()
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Coordinate mapping

    /// Compute the rectangle the image actually occupies inside `containerSize`
    /// when displayed with `aspectRatio(contentMode: .fit)`.
    private func aspectFitRect(imageSize: CGSize, in containerSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
              containerSize.width > 0, containerSize.height > 0 else {
            return CGRect(origin: .zero, size: containerSize)
        }
        let imageAspect = imageSize.width / imageSize.height
        let containerAspect = containerSize.width / containerSize.height
        var rect = CGRect.zero
        if imageAspect > containerAspect {
            // Letterboxed top/bottom
            rect.size.width = containerSize.width
            rect.size.height = containerSize.width / imageAspect
            rect.origin.x = 0
            rect.origin.y = (containerSize.height - rect.size.height) / 2
        } else {
            // Pillarboxed left/right
            rect.size.height = containerSize.height
            rect.size.width = containerSize.height * imageAspect
            rect.origin.y = 0
            rect.origin.x = (containerSize.width - rect.size.width) / 2
        }
        return rect
    }

    /// Clamp a screen-space point to the displayed image's rect so the user
    /// can't draw in the letterbox area.
    private func clampToDisplayRect(_ point: CGPoint) -> CGPoint {
        guard displayRect.width > 0 else { return point }
        return CGPoint(
            x: min(max(point.x, displayRect.minX), displayRect.maxX),
            y: min(max(point.y, displayRect.minY), displayRect.maxY)
        )
    }

    /// Convert a screen-space point inside the displayed image into the
    /// snapshot's full-resolution image pixel space.
    private func screenToImagePixels(_ point: CGPoint) -> CGPoint {
        guard displayRect.width > 0, displayRect.height > 0 else { return point }
        let nx = (point.x - displayRect.minX) / displayRect.width
        let ny = (point.y - displayRect.minY) / displayRect.height
        return CGPoint(
            x: nx * CGFloat(snapshot.imageWidth),
            y: ny * CGFloat(snapshot.imageHeight)
        )
    }
}
