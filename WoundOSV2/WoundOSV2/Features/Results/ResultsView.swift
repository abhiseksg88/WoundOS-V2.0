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
            VStack(spacing: 0) {
                // Top: full-bleed annotated image (mirrors the screenshot)
                heroAnnotatedImage

                if viewModel.isRefining {
                    refiningBanner
                        .padding(.horizontal, WOSSpacing.lg)
                        .padding(.top, WOSSpacing.md)
                }

                // Wound identifier + clinical measurement table
                woundHeader
                    .padding(.horizontal, WOSSpacing.lg)
                    .padding(.top, WOSSpacing.lg)

                clinicalMeasurementTable
                    .padding(.horizontal, WOSSpacing.lg)
                    .padding(.top, WOSSpacing.md)
                    .animation(.easeInOut(duration: 0.4), value: viewModel.measurements)

                // Secondary sections: depth, clinical summary, PUSH, 3D, actions
                VStack(spacing: WOSSpacing.xxl) {
                    depthHeatmapSection
                    clinicalSummarySection
                    pushScoreSection
                    viewer3DSection
                    actionsSection
                }
                .padding(.horizontal, WOSSpacing.lg)
                .padding(.top, WOSSpacing.xxl)
                .padding(.bottom, WOSSpacing.xxxl)
            }
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
                LongitudinalCompareView(scans: viewModel.patient?.wounds ?? MockDataProvider.allScans.filter { $0.status == .complete })
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Close") { showCompare = false }
                        }
                    }
            }
        }
    }

    // MARK: - Refining Banner
    private var refiningBanner: some View {
        HStack(spacing: WOSSpacing.sm) {
            ProgressView()
                .scaleEffect(0.8)
            Text("Refining measurements...")
                .font(WOSTypography.footnote)
                .foregroundColor(WOSColors.textSecondary)
            Spacer()
            Text("Preliminary")
                .font(WOSTypography.caption)
                .fontWeight(.semibold)
                .foregroundColor(WOSColors.orange)
                .padding(.horizontal, WOSSpacing.sm)
                .padding(.vertical, WOSSpacing.xs)
                .background(WOSColors.orange.opacity(0.15))
                .clipShape(Capsule())
        }
        .padding(WOSSpacing.md)
        .background(WOSColors.yellow.opacity(0.1))
        .cornerRadius(WOSRadius.sm)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Hero Annotated Image (full-bleed, like Apple Measure / Tissue Analytics)
    private var heroAnnotatedImage: some View {
        Group {
            if let image = viewModel.annotatedImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .frame(height: 360)
                    .clipped()
                    .accessibilityLabel("Annotated wound image with L and W cross markers")
            } else {
                Rectangle()
                    .fill(WOSColors.fill)
                    .frame(maxWidth: .infinity)
                    .frame(height: 360)
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 56))
                            .foregroundColor(WOSColors.textTertiary)
                    )
            }
        }
    }

    // MARK: - Wound Header ("● Wound W1")
    private var woundHeader: some View {
        HStack(spacing: WOSSpacing.sm) {
            Circle()
                .fill(WOSColors.green)
                .frame(width: 10, height: 10)
            Text("Wound W1")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(WOSColors.textPrimary)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Clinical Measurement Table (Area / Circumference / Length / Width / Depth / Volume)
    private var clinicalMeasurementTable: some View {
        WOSCard {
            VStack(spacing: 0) {
                tableRow(
                    label: "Area",
                    value: String(format: "%.2f cm\u{00B2}", viewModel.measurements.areaCm2),
                    showDivider: true
                )
                tableRow(
                    label: "Circumference",
                    value: String(format: "%.2f cm", viewModel.measurements.circumferenceCm),
                    showDivider: true
                )
                tableRow(
                    label: "Length",
                    value: String(format: "%.2f cm", viewModel.measurements.lengthCm),
                    showDivider: true
                )
                tableRow(
                    label: "Width",
                    value: String(format: "%.2f cm", viewModel.measurements.widthCm),
                    showDivider: true
                )
                tableRow(
                    label: "Max Depth",
                    value: String(format: "%.2f mm", viewModel.measurements.maxDepthMm),
                    showDivider: true
                )
                tableRow(
                    label: "Volume",
                    value: String(format: "%.2f mL", viewModel.measurements.volumeMl),
                    showDivider: false
                )
            }
        }
    }

    private func tableRow(label: String, value: String, showDivider: Bool) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(label)
                    .font(.system(size: 17, weight: .regular, design: .default))
                    .foregroundColor(WOSColors.textPrimary)
                Spacer()
                Text(value)
                    .font(.system(size: 17, weight: .regular, design: .default))
                    .foregroundColor(WOSColors.textSecondary)
            }
            .padding(.vertical, WOSSpacing.md)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(label): \(value)")

            if showDivider {
                Divider()
            }
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
