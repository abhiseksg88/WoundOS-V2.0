import SwiftUI

struct DashboardView: View {
    @StateObject private var viewModel = DashboardViewModel()
    @State private var showCapture = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: WOSSpacing.xxl) {
                    headerSection
                    quickScanSection
                    recentScansSection
                    healingTrendSection
                }
                .padding(.horizontal, WOSSpacing.lg)
                .padding(.bottom, WOSSpacing.xxxl)
            }
            .background(WOSColors.background.ignoresSafeArea())
            .navigationTitle("Dashboard")
            .fullScreenCover(isPresented: $showCapture) {
                Text("Capture coming in Phase 2")
            }
        }
    }

    // MARK: - Header
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: WOSSpacing.xs) {
            Text(viewModel.greeting)
                .font(WOSTypography.largeTitle)
                .foregroundColor(WOSColors.textPrimary)

            Text("\(viewModel.recentScans.filter { $0.status == .complete }.count) scans this week")
                .font(WOSTypography.subheadline)
                .foregroundColor(WOSColors.textSecondary)
        }
        .padding(.top, WOSSpacing.sm)
    }

    // MARK: - Quick Scan CTA
    private var quickScanSection: some View {
        WOSButton(title: "Quick Scan", icon: "camera.fill", style: .primary) {
            showCapture = true
        }
    }

    // MARK: - Recent Scans
    private var recentScansSection: some View {
        VStack(alignment: .leading, spacing: WOSSpacing.md) {
            HStack {
                Text("Recent Scans")
                    .font(WOSTypography.title3)
                    .foregroundColor(WOSColors.textPrimary)
                Spacer()
                Button("See All") {}
                    .font(WOSTypography.subheadline)
                    .foregroundColor(WOSColors.accent)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: WOSSpacing.md) {
                    ForEach(viewModel.recentScans.prefix(5)) { scan in
                        RecentScanCard(
                            scan: scan,
                            patientName: viewModel.patientForScan(scan)?.fullName ?? "Unknown"
                        )
                    }
                }
            }
            .shimmer(active: viewModel.isLoading)
        }
    }

    // MARK: - Healing Trend
    private var healingTrendSection: some View {
        VStack(alignment: .leading, spacing: WOSSpacing.md) {
            Text("Healing Trends")
                .font(WOSTypography.title3)
                .foregroundColor(WOSColors.textPrimary)

            WOSCard {
                HealingTrendChart(scans: viewModel.recentScans.filter { $0.measurements != nil })
                    .frame(height: 180)
            }
        }
    }
}

#if DEBUG
struct DashboardView_Previews: PreviewProvider {
    static var previews: some View {
        DashboardView()
    }
}
#endif
