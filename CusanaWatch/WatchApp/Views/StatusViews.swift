import SwiftUI
import CusanaKit

/// **State A** — nothing to pay.
///
/// Deliberately calm. This is the resting state of the app, not an error: a
/// diner who opens Cusana on the subway should see something quiet, not a
/// warning triangle.
struct NotSeatedView: View {
    let onRefresh: () async -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "fork.knife")
                .font(.system(size: 26))
                .foregroundStyle(.tertiary)

            Text("No active check-in")
                .font(.headline)
                .multilineTextAlignment(.center)

            Text("Your check appears here once you're seated.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                // Without this the VStack hands Text a single line's height and
                // it truncates to "Your check appears he…" instead of wrapping.
                .fixedSize(horizontal: false, vertical: true)

            Button("Refresh") {
                Task { await onRefresh() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.top, 2)
        }
        .padding(.horizontal, 4)
    }
}

/// The first-load spinner. Always resolves — `CheckViewModel` has a deadline
/// guard behind it, so this cannot be the last thing on screen.
struct LoadingView: View {
    var body: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text("Checking your table…")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// **State E** — not in the client's spec. Built anyway.
///
/// A live demo is exactly where "network down" and "backend said no" show up,
/// and the brief's hard rule is that a spinner must never run forever. Retry is
/// offered only where retrying can actually help; a dead token needs a new
/// build, and a button that quietly does nothing is worse than no button.
struct FailedView: View {
    let error: CusanaError
    let onRetry: () async -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 24))
                    .foregroundStyle(.orange)

                Text(error.title)
                    .font(.headline)
                    .multilineTextAlignment(.center)

                Text(error.message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if error.isRetryable {
                    Button("Retry") {
                        Task { await onRetry() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .padding(.top, 2)
                } else if case .notConfigured = error {
                    // Only a developer ever sees this, and only in a build made
                    // without a token. It says exactly which file to fix.
                    Text("Add CUSANA_TOKEN to Config/Secrets.xcconfig")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private var symbol: String {
        switch error {
        case .offline:                          "wifi.slash"
        case .timedOut:                         "clock.badge.exclamationmark"
        case .unauthorised, .tokenExpired:      "person.crop.circle.badge.exclamationmark"
        case .notConfigured, .invalidURL:       "wrench.and.screwdriver"
        default:                                "exclamationmark.triangle"
        }
    }
}

#Preview("A — not seated") {
    NotSeatedView(onRefresh: {})
}

#Preview("Loading") {
    LoadingView()
}

#Preview("E — offline") {
    FailedView(error: .offline, onRetry: {})
}

#Preview("E — token dead") {
    FailedView(error: .unauthorised, onRetry: {})
}

#Preview("E — no token in build") {
    FailedView(error: .notConfigured("missing"), onRetry: {})
}
