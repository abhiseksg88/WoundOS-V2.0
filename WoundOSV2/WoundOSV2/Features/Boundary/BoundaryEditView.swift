import SwiftUI

struct BoundaryEditView: View {
    @StateObject var viewModel: BoundaryViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            imageCanvas
            modeSelector
            actionButtons
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Wound Boundary")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Image Canvas
    private var imageCanvas: some View {
        GeometryReader { geometry in
            ZStack {
                // Wound image
                if let image = viewModel.woundImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onAppear {
                            viewModel.imageSize = geometry.size
                        }
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                }

                // Boundary overlay
                boundaryOverlay

                // Drawing overlay
                if viewModel.mode == .draw {
                    drawingOverlay
                }

                // Adjust handles
                if viewModel.mode == .adjust {
                    handleOverlay
                }
            }
            .gesture(drawGesture)
        }
    }

    // MARK: - Boundary Overlay
    private var boundaryOverlay: some View {
        Canvas { context, size in
            let path = viewModel.bezierPath().cgPath
            let swiftUIPath = Path(path)

            // Semi-transparent fill
            context.fill(swiftUIPath, with: .color(.green.opacity(0.2)))

            // Stroke
            context.stroke(swiftUIPath, with: .color(.green), lineWidth: 2)
        }
    }

    // MARK: - Drawing Overlay
    private var drawingOverlay: some View {
        Canvas { context, size in
            guard viewModel.drawingPoints.count > 1 else { return }
            var path = Path()
            path.move(to: viewModel.drawingPoints[0])
            for point in viewModel.drawingPoints.dropFirst() {
                path.addLine(to: point)
            }
            context.stroke(path, with: .color(.yellow), lineWidth: 2)
        }
    }

    // MARK: - Drag Handles
    private var handleOverlay: some View {
        ForEach(Array(viewModel.boundaryPoints.enumerated()), id: \.offset) { index, point in
            Circle()
                .fill(viewModel.selectedHandleIndex == index ? Color.yellow : Color.green)
                .frame(width: 16, height: 16)
                .position(point)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            viewModel.selectedHandleIndex = index
                            viewModel.handleDrag(index: index, location: value.location)
                        }
                        .onEnded { _ in
                            viewModel.selectedHandleIndex = nil
                        }
                )
        }
    }

    // MARK: - Draw Gesture
    private var drawGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                guard viewModel.mode == .draw else { return }
                viewModel.addDrawingPoint(value.location)
            }
            .onEnded { _ in
                guard viewModel.mode == .draw else { return }
                viewModel.finishDrawing()
            }
    }

    // MARK: - Mode Selector
    private var modeSelector: some View {
        Picker("Mode", selection: $viewModel.mode) {
            ForEach(BoundaryEditMode.allCases, id: \.self) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .padding()
        .background(.ultraThinMaterial)
    }

    // MARK: - Actions
    private var actionButtons: some View {
        HStack(spacing: WOSSpacing.md) {
            WOSButton(title: "Cancel", style: .ghost) {
                dismiss()
            }
            WOSButton(title: "Accept & Measure", icon: "checkmark", style: .primary) {
                viewModel.acceptBoundary()
                dismiss()
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }
}

#if DEBUG
struct BoundaryEditView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            BoundaryEditView(viewModel: BoundaryViewModel(woundImage: nil, maskImage: nil))
        }
    }
}
#endif
