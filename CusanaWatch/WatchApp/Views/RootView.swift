import SwiftUI
import CusanaKit

/// Switches between the states. The only place the state machine touches the UI.
struct RootView: View {
    /// Owned by `CusanaWatchApp`, not by this view. `@Observable` tracks reads
    /// during body evaluation through a plain `let`, so no property wrapper is
    /// needed here — and the model survives view re-creation, which is what
    /// stops `.task` from re-fetching on every scene update.
    let model: CheckViewModel

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Cusana")
                .containerBackground(backgroundTint.gradient, for: .navigation)
        }
        .task {
            // `.task` covers first load; it is cancelled automatically when the
            // view goes away, which is why the model treats CancellationError
            // as "not a failure" rather than flashing State E.
            await model.load()
            model.startPolling()
        }
        .onDisappear {
            // A watch screen that keeps polling in the dark is a battery
            // complaint waiting to happen.
            model.stopPolling()
        }
        .animation(.smooth(duration: 0.25), value: model.state)
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            LoadingView()

        case .notSeated:
            NotSeatedView(onRefresh: { await model.refresh() })

        case .seated(let snapshot):
            SeatedView(snapshot: snapshot, isRefreshing: model.isRefreshing)

        case .failed(let error):
            FailedView(error: error, onRetry: { await model.retry() })

        // Milestone 2 states. Unreachable in this build — there is no settle
        // call to enter them — but declared so M2 adds a transition, not a
        // new concept.
        case .processing:
            ProcessingView()

        case .paid(let amount):
            PaidView(amount: amount)
        }
    }

    /// Green only when there is a bill on screen. State A and State E stay
    /// neutral so the colour means something.
    private var backgroundTint: Color {
        switch model.state {
        case .seated, .paid: .green.opacity(0.35)
        case .failed:        .orange.opacity(0.25)
        default:             .clear
        }
    }
}

/// **State C** — Milestone 2.
struct ProcessingView: View {
    var body: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.large)
            Text("Settling…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// **State D** — Milestone 2.
struct PaidView: View {
    let amount: Amount

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.green)
            Text("Paid!")
                .font(.title3.bold())
            Text(amount.formatted)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Paid \(amount.accessibleDescription)")
    }
}

#Preview("B — seated") {
    RootView(model: CheckViewModel(service: .mock(.seated), pollInterval: nil))
}

#Preview("A — not seated") {
    RootView(model: CheckViewModel(service: .mock(.notSeated), pollInterval: nil))
}

#Preview("E — offline") {
    RootView(model: CheckViewModel(service: .mock(.failing(.offline)), pollInterval: nil))
}

#Preview("Loading") {
    RootView(model: CheckViewModel(service: .mock(.slow(.seconds(30))), pollInterval: nil))
}
