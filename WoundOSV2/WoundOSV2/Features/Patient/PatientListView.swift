import SwiftUI

struct PatientListView: View {
    @StateObject private var viewModel = PatientViewModel()

    var body: some View {
        NavigationStack {
            List {
                ForEach(viewModel.filteredPatients) { patient in
                    NavigationLink(value: patient) {
                        PatientRow(patient: patient, viewModel: viewModel)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $viewModel.searchText, prompt: "Search patients")
            .navigationTitle("Patients")
            .navigationDestination(for: Patient.self) { patient in
                PatientProfileView(patient: patient)
            }
            .overlay {
                if viewModel.filteredPatients.isEmpty && !viewModel.searchText.isEmpty {
                    emptySearchState
                } else if viewModel.patients.isEmpty {
                    emptyState
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: WOSSpacing.lg) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 48))
                .foregroundColor(WOSColors.textTertiary)
            Text("No Patients Yet")
                .font(WOSTypography.title3)
                .foregroundColor(WOSColors.textPrimary)
            Text("Patients will appear here after their first scan.")
                .font(WOSTypography.subheadline)
                .foregroundColor(WOSColors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private var emptySearchState: some View {
        VStack(spacing: WOSSpacing.md) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundColor(WOSColors.textTertiary)
            Text("No results for \"\(viewModel.searchText)\"")
                .font(WOSTypography.headline)
                .foregroundColor(WOSColors.textSecondary)
        }
    }
}

struct PatientRow: View {
    let patient: Patient
    let viewModel: PatientViewModel

    var body: some View {
        HStack(spacing: WOSSpacing.md) {
            // Avatar
            ZStack {
                Circle()
                    .fill(WOSColors.accent.opacity(0.15))
                    .frame(width: 48, height: 48)
                Text(patient.initials)
                    .font(WOSTypography.headline)
                    .foregroundColor(WOSColors.accent)
            }

            VStack(alignment: .leading, spacing: WOSSpacing.xs) {
                Text(patient.fullName)
                    .font(WOSTypography.headline)
                    .foregroundColor(WOSColors.textPrimary)

                HStack(spacing: WOSSpacing.sm) {
                    if let mrn = patient.mrn {
                        Text(mrn)
                            .font(WOSTypography.caption)
                            .foregroundColor(WOSColors.textSecondary)
                    }
                    if let room = patient.roomNumber {
                        Text("Rm \(room)")
                            .font(WOSTypography.caption)
                            .foregroundColor(WOSColors.textTertiary)
                    }
                }

                Text("\(viewModel.woundCount(for: patient)) wound\(viewModel.woundCount(for: patient) == 1 ? "" : "s")")
                    .font(WOSTypography.caption)
                    .foregroundColor(WOSColors.textSecondary)
            }

            Spacer()

            if let latest = viewModel.latestScan(for: patient),
               let trend = latest.healingTrend {
                healingBadge(for: trend)
            }
        }
        .padding(.vertical, WOSSpacing.xs)
    }

    private func healingBadge(for trend: HealingTrend) -> some View {
        let status: WOSHealingStatus = {
            switch trend {
            case .healing: return .healing
            case .stable: return .stable
            case .worsening: return .worsening
            }
        }()
        return WOSStatusBadge(status: status)
    }
}

#if DEBUG
struct PatientListView_Previews: PreviewProvider {
    static var previews: some View {
        PatientListView()
    }
}
#endif
