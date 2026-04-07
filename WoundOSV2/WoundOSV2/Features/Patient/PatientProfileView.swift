import SwiftUI

struct PatientProfileView: View {
    let patient: Patient
    @State private var showCapture = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WOSSpacing.xxl) {
                patientInfoCard
                actionsSection
                woundTimelineSection
            }
            .padding(.horizontal, WOSSpacing.lg)
            .padding(.bottom, WOSSpacing.xxxl)
        }
        .background(WOSColors.background.ignoresSafeArea())
        .navigationTitle(patient.fullName)
        .navigationBarTitleDisplayMode(.large)
        .fullScreenCover(isPresented: $showCapture) {
            Text("Capture coming in Phase 2")
        }
    }

    // MARK: - Patient Info Card
    private var patientInfoCard: some View {
        WOSCard {
            VStack(alignment: .leading, spacing: WOSSpacing.md) {
                HStack(spacing: WOSSpacing.lg) {
                    ZStack {
                        Circle()
                            .fill(WOSColors.accent.opacity(0.15))
                            .frame(width: 64, height: 64)
                        Text(patient.initials)
                            .font(WOSTypography.title2)
                            .foregroundColor(WOSColors.accent)
                    }

                    VStack(alignment: .leading, spacing: WOSSpacing.xs) {
                        Text(patient.fullName)
                            .font(WOSTypography.title3)
                            .foregroundColor(WOSColors.textPrimary)

                        if let dob = patient.dateOfBirth {
                            Text("DOB: \(dob, format: .dateTime.month().day().year())")
                                .font(WOSTypography.footnote)
                                .foregroundColor(WOSColors.textSecondary)
                        }
                    }
                }

                Divider()

                infoRow(icon: "number", label: "MRN", value: patient.mrn ?? "—")
                infoRow(icon: "building.2", label: "Facility", value: patient.facilityName ?? "—")
                infoRow(icon: "door.left.hand.open", label: "Room", value: patient.roomNumber ?? "—")
                infoRow(icon: "bandage", label: "Active Wounds", value: "\(patient.wounds.count)")
            }
        }
    }

    private func infoRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: WOSSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(WOSColors.accent)
                .frame(width: 24)
            Text(label)
                .font(WOSTypography.footnote)
                .foregroundColor(WOSColors.textSecondary)
            Spacer()
            Text(value)
                .font(WOSTypography.footnote)
                .fontWeight(.medium)
                .foregroundColor(WOSColors.textPrimary)
        }
    }

    // MARK: - Actions
    private var actionsSection: some View {
        WOSButton(title: "New Scan", icon: "camera.fill", style: .primary) {
            showCapture = true
        }
    }

    // MARK: - Wound Timeline
    private var woundTimelineSection: some View {
        VStack(alignment: .leading, spacing: WOSSpacing.md) {
            Text("Wound History")
                .font(WOSTypography.title3)
                .foregroundColor(WOSColors.textPrimary)

            WoundTimelineView(scans: patient.wounds.sorted { $0.capturedAt > $1.capturedAt })
        }
    }
}

#if DEBUG
struct PatientProfileView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            PatientProfileView(patient: MockDataProvider.patients[0])
        }
    }
}
#endif
