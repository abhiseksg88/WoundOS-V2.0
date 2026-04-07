import SwiftUI

struct ResultsView: View {
    @StateObject var viewModel: ResultsViewModel
    @State private var showPDF = false
    @State private var show3DViewer = false
    @State private var showShareSheet = false
    @State private var showCompare = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: WOSSpacing.xxl) {
                annotatedImageSection
                metricsGrid
                depthHeatmapSection
                clinicalSummarySection
                pushScoreSection
                viewer3DSection
                actionsSection
            }
            .padding(.horizontal, WOSSpacing.lg)
            .padding(.bottom, WOSSpacing.xxxl)
        }
        .background(WOSColors.background.ignoresSafeArea())
        .navigationTitle("Results")
        .navigationBarTitleDisplayMode(.large)
        .onAppear { viewModel.saveToStore() }
        .fullScreenCover(isPresented: $show3DViewer) {
            NavigationStack {
                MeshViewerView(meshData: viewModel.serverResponse.meshOBJData)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Close") { show3DViewer = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showPDF) {
            NavigationStack {
                if let url = viewModel.pdfURL {
                    ReportPreviewView(pdfURL: url)
                } else {
                    ProgressView("Generating report...")
                        .onAppear { viewModel.generatePDF() }
                        .onChange(of: viewModel.pdfURL) { _ in }
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let image = viewModel.annotatedImage {
                ShareSheet(items: [image])
            }
        }
        .sheet(isPresented: $showCompare) {
            NavigationStack {
                LongitudinalCompareView()
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Close") { showCompare = false }
                        }
                    }
            }
        }
    }

    // MARK: - Annotated Image
    private var annotatedImageSection: some View {
        WOSCard {
            VStack(alignment: .leading, spacing: WOSSpacing.sm) {
                Text("Wound Analysis")
                    .font(WOSTypography.headline)
                    .foregroundColor(WOSColors.textPrimary)

                if let image = viewModel.annotatedImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .cornerRadius(WOSRadius.md)
                        .accessibilityLabel("Annotated wound image with measurement overlays")
                } else {
                    RoundedRectangle(cornerRadius: WOSRadius.md)
                        .fill(WOSColors.fill)
                        .frame(height: 200)
                        .overlay(
                            Image(systemName: "photo")
                                .font(.system(size: 40))
                                .foregroundColor(WOSColors.textTertiary)
                        )
                }
            }
        }
    }

    // MARK: - Metrics Grid (2x3)
    private var metricsGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: WOSSpacing.md),
            GridItem(.flexible(), spacing: WOSSpacing.md)
        ], spacing: WOSSpacing.md) {
            WOSMetricTile(
                icon: "square.dashed",
                iconColor: WOSColors.teal,
                label: "Area",
                value: String(format: "%.1f", viewModel.measurements.areaCm2),
                unit: "cm\u{00B2}",
                trend: viewModel.areaTrend
            )

            WOSMetricTile(
                icon: "arrow.down.to.line",
                iconColor: WOSColors.red,
                label: "Max Depth",
                value: String(format: "%.1f", viewModel.measurements.maxDepthMm),
                unit: "mm"
            )

            WOSMetricTile(
                icon: "cube",
                iconColor: WOSColors.purple,
                label: "Volume",
                value: String(format: "%.1f", viewModel.measurements.volumeMl),
                unit: "mL"
            )

            MeasurementCard(
                icon: "ruler",
                iconColor: WOSColors.orange,
                label: "L \u{00D7} W",
                value: String(format: "%.0f \u{00D7} %.0f", viewModel.measurements.lengthMm, viewModel.measurements.widthMm),
                unit: "mm"
            )

            WOSMetricTile(
                icon: "circle.dashed",
                iconColor: WOSColors.blue,
                label: "Perimeter",
                value: String(format: "%.0f", viewModel.measurements.perimeterMm),
                unit: "mm"
            )

            PUSHScoreView(score: viewModel.pushScore ?? PUSHScore())
        }
    }

    // MARK: - Depth Heatmap
    private var depthHeatmapSection: some View {
        WOSCard {
            VStack(alignment: .leading, spacing: WOSSpacing.sm) {
                Text("Depth Heatmap")
                    .font(WOSTypography.headline)
                    .foregroundColor(WOSColors.textPrimary)

                DepthHeatmapView(image: viewModel.depthHeatmap)
                    .frame(height: 200)
                    .accessibilityLabel("Wound depth heatmap showing green for shallow and red for deep areas")
            }
        }
    }

    // MARK: - Clinical Summary
    private var clinicalSummarySection: some View {
        ClinicalSummaryView(text: viewModel.clinicalSummary)
    }

    // MARK: - PUSH Score
    private var pushScoreSection: some View {
        Group {
            if let score = viewModel.pushScore {
                WOSCard {
                    VStack(alignment: .leading, spacing: WOSSpacing.md) {
                        Text("PUSH Score Breakdown")
                            .font(WOSTypography.headline)
                            .foregroundColor(WOSColors.textPrimary)

                        HStack(spacing: WOSSpacing.xl) {
                            WOSProgressRing(
                                progress: score.normalizedScore,
                                lineWidth: 8,
                                color: pushScoreColor(score),
                                centerText: "\(score.totalScore)"
                            )
                            .frame(width: 64, height: 64)
                            .accessibilityLabel("PUSH Score \(score.totalScore) out of \(score.maxPossible)")

                            VStack(alignment: .leading, spacing: WOSSpacing.sm) {
                                scoreRow("Area", score.areaScore, maxScore: 10)
                                scoreRow("Exudate", score.exudateScore, maxScore: 3)
                                scoreRow("Surface Type", score.surfaceTypeScore, maxScore: 4)
                            }
                        }

                        Text(score.interpretation)
                            .font(WOSTypography.footnote)
                            .foregroundColor(pushScoreColor(score))
                            .fontWeight(.semibold)
                    }
                }
            }
        }
    }

    private func scoreRow(_ label: String, _ value: Int, maxScore: Int) -> some View {
        HStack {
            Text(label)
                .font(WOSTypography.caption)
                .foregroundColor(WOSColors.textSecondary)
            Spacer()
            Text("\(value)/\(maxScore)")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(WOSColors.textPrimary)
        }
    }

    private func pushScoreColor(_ score: PUSHScore) -> Color {
        switch score.totalScore {
        case 0...5: return WOSColors.green
        case 6...10: return WOSColors.yellow
        case 11...14: return WOSColors.orange
        default: return WOSColors.red
        }
    }

    // MARK: - 3D Viewer
    private var viewer3DSection: some View {
        WOSCard {
            HStack {
                VStack(alignment: .leading, spacing: WOSSpacing.xs) {
                    Text("3D Model")
                        .font(WOSTypography.headline)
                        .foregroundColor(WOSColors.textPrimary)
                    Text("View wound in 3D")
                        .font(WOSTypography.caption)
                        .foregroundColor(WOSColors.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(WOSColors.textTertiary)
            }
        }
        .onTapGesture { show3DViewer = true }
        .accessibilityLabel("View wound in 3D model viewer")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Actions
    private var actionsSection: some View {
        VStack(spacing: WOSSpacing.md) {
            HStack(spacing: WOSSpacing.md) {
                WOSButton(title: "PDF Report", icon: "doc.text", style: .secondary) {
                    viewModel.generatePDF()
                    showPDF = true
                }
                WOSButton(title: "Share", icon: "square.and.arrow.up", style: .secondary) {
                    showShareSheet = true
                }
            }
            WOSButton(title: "Compare Scans", icon: "arrow.left.arrow.right", style: .ghost) {
                showCompare = true
            }
        }
    }
}

#if DEBUG
struct ResultsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            ResultsView(viewModel: ResultsViewModel(response: ServerResponse(
                measurements: WoundMeasurement(areaCm2: 12.4, maxDepthMm: 5.2, avgDepthMm: 2.8, volumeMl: 3.1, lengthMm: 45, widthMm: 32, perimeterMm: 128.5),
                annotatedImageBase64: "",
                depthHeatmapBase64: "",
                woundMaskBase64: "",
                meshOBJData: nil,
                splatURL: nil,
                clinicalSummary: "Stage III pressure injury showing granulation tissue.",
                pushScore: PUSHScore(areaScore: 9, exudateScore: 2, surfaceTypeScore: 3),
                processingTimeMs: 2100
            )))
        }
    }
}
#endif
