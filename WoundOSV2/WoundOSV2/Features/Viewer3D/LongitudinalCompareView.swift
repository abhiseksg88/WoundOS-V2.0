import SwiftUI
import SceneKit

struct LongitudinalCompareView: View {
    let scans: [WoundScan]
    @State private var leftScanIndex: Int = 0
    @State private var rightScanIndex: Int = 1

    var body: some View {
        VStack(spacing: 0) {
            scanSelectors

            HStack(spacing: 2) {
                leftViewer
                rightViewer
            }
            .frame(maxHeight: .infinity)

            if completedScans.count >= 2 {
                trendChart
            }
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Compare Scans")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private var completedScans: [WoundScan] {
        scans.filter { $0.status == .complete }.sorted { $0.capturedAt < $1.capturedAt }
    }

    // MARK: - Scan Selectors
    private var scanSelectors: some View {
        HStack {
            scanPicker(title: "Before", index: $leftScanIndex)
            Divider()
                .frame(height: 40)
            scanPicker(title: "After", index: $rightScanIndex)
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    private func scanPicker(title: String, index: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(WOSTypography.caption)
                .foregroundColor(.white.opacity(0.6))

            if completedScans.indices.contains(index.wrappedValue) {
                let scan = completedScans[index.wrappedValue]
                Text(scan.capturedAt, format: .dateTime.month().day().year())
                    .font(WOSTypography.footnote)
                    .foregroundColor(.white)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Viewers
    private var leftViewer: some View {
        ZStack {
            MeshViewerRepresentable(meshData: nil)
            scanInfoOverlay(index: leftScanIndex)
        }
    }

    private var rightViewer: some View {
        ZStack {
            MeshViewerRepresentable(meshData: nil)
            scanInfoOverlay(index: rightScanIndex)
        }
    }

    private func scanInfoOverlay(index: Int) -> some View {
        VStack {
            Spacer()
            if completedScans.indices.contains(index),
               let m = completedScans[index].measurements {
                HStack(spacing: WOSSpacing.md) {
                    metricPill("Area", String(format: "%.1f cm²", m.areaCm2))
                    metricPill("Depth", String(format: "%.1f mm", m.maxDepthMm))
                }
                .padding(WOSSpacing.sm)
            }
        }
    }

    private func metricPill(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial)
        .cornerRadius(6)
    }

    // MARK: - Trend Chart
    private var trendChart: some View {
        WOSCard {
            VStack(alignment: .leading, spacing: WOSSpacing.sm) {
                Text("Area Over Time")
                    .font(WOSTypography.caption)
                    .foregroundColor(WOSColors.textSecondary)
                HealingTrendChart(scans: completedScans)
                    .frame(height: 100)
            }
        }
        .padding()
    }
}

#if DEBUG
struct LongitudinalCompareView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            LongitudinalCompareView(scans: MockDataProvider.patients[2].wounds)
        }
    }
}
#endif
