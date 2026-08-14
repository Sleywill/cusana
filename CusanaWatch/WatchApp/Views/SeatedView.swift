import SwiftUI
import CusanaKit

/// **State B** — the diner is seated and has a bill.
///
/// The whole product is this screen. Layout priority, in order: the total, the
/// button, then everything else. It is read by someone at a restaurant table
/// who is mid-conversation and not looking carefully.
struct SeatedView: View {
    let snapshot: CheckSnapshot
    let isRefreshing: Bool

    /// 44pt at the default text size, and it grows with the wearer's Dynamic
    /// Type setting instead of ignoring it. A fixed size would keep the hero
    /// number legible for most people and quietly fail the ones who turned
    /// larger text on — which on a watch is a lot of people.
    /// 40pt at the default text size. Sized against the 41mm screen, which is
    /// the tight one: at 44 the "Milestone 2" caption fell below the fold, and
    /// a greyed-out button with no visible explanation reads as broken rather
    /// than as deliberate.
    @ScaledMetric(relativeTo: .largeTitle) private var totalSize: CGFloat = 40

    var body: some View {
        ScrollView {
            VStack(spacing: 3) {
                venue

                total

                if let tableLabel = snapshot.tableLabel {
                    // Shown so the diner can confirm the watch is looking at
                    // *their* table before they pay it.
                    Text(tableLabel)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                settleButton
                    .padding(.top, 4)

                milestoneNote
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 2)
        }
        // One VoiceOver element speaking the client's exact sentence, instead
        // of four fragments read one after another.
        .accessibilityElement(children: .contain)
    }

    private var venue: some View {
        HStack(spacing: 4) {
            Text(snapshot.restaurantName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if isRefreshing {
                // A refresh must never replace the total with a spinner, so it
                // announces itself here instead — small and beside the venue.
                ProgressView()
                    .controlSize(.mini)
                    .transition(.opacity)
            }
        }
        .accessibilityHidden(true)
    }

    private var total: some View {
        Text(snapshot.total.formatted)
            // Rounded because it reads as money rather than as data. Sized by
            // hand rather than by text style so it is unambiguously the largest
            // thing on the screen — but scaled, so it still respects the
            // wearer's text-size setting. The ScrollView above absorbs the
            // overflow when both are large.
            .font(.system(size: totalSize, weight: .bold, design: .rounded))
            .minimumScaleFactor(0.4)
            .lineLimit(1)
            .contentTransition(.numericText())
            .animation(.snappy, value: snapshot.total)
            .accessibilityLabel(snapshot.spokenSummary)
            .accessibilityAddTraits(.isHeader)
    }

    private var settleButton: some View {
        Button {
            // Intentionally empty. The settle call is Milestone 2 and the brief
            // is explicit: do not fake a success state.
        } label: {
            Text("Settle Check")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .tint(.green)
        .disabled(true)
        .accessibilityLabel("Settle check, \(snapshot.total.accessibleDescription)")
        .accessibilityHint("Not available yet. Payment arrives in the next milestone.")
    }

    private var milestoneNote: some View {
        Label("Milestone 2", systemImage: "lock.fill")
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .labelStyle(.titleAndIcon)
            .multilineTextAlignment(.center)
            .accessibilityHidden(true)
    }
}

#Preview("Seated — 45mm") {
    SeatedView(snapshot: MockCusanaAPI.snapshot, isRefreshing: false)
}

#Preview("Refreshing") {
    SeatedView(snapshot: MockCusanaAPI.snapshot, isRefreshing: true)
}
