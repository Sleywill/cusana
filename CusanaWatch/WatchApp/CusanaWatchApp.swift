import SwiftUI
import CusanaKit

/// Standalone watchOS app. No iOS target, no companion, no WatchConnectivity —
/// watchOS routes HTTPS through the paired iPhone at the OS level, so the watch
/// talks to the Base44 REST API directly.
@main
struct CusanaWatchApp: App {
    /// Built once, here, and held for the life of the app.
    ///
    /// `.live` reads the token from the bundle. If it is missing it returns a
    /// model that fails into State E with "Setup needed" rather than crashing
    /// at launch — a build with no token still runs and still explains itself.
    @State private var model = Self.makeModel()

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
        }
    }

    private static func makeModel() -> CheckViewModel {
        #if DEBUG
        // Lets the UI be checked at 41mm and 45mm without a token and without
        // live data — the reason M1-BUILD-SPEC asks for a mock conformer at all.
        //
        //   xcrun simctl launch <udid> xyz.sleywil.cusanawatch -CusanaMock seated
        //
        // DEBUG only, so it cannot exist in anything shipped. And to be explicit:
        // a demo video for the client must show live data. Filming this and
        // calling it real would be exactly the faked success state the brief
        // forbids.
        if let scenario = MockScenario.fromLaunchArguments() {
            CusanaLog.state.notice("⚠️ DEBUG mock mode: \(scenario.name) — not live data")
            return CheckViewModel(service: .mock(scenario.scenario), pollInterval: nil)
        }
        #endif
        return .live()
    }
}

#if DEBUG
/// Maps `-CusanaMock <name>` onto a mock scenario.
private struct MockScenario {
    let name: String
    let scenario: MockCusanaAPI.Scenario

    static func fromLaunchArguments() -> MockScenario? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-CusanaMock"),
              arguments.index(after: flag) < arguments.endIndex else { return nil }

        let name = arguments[arguments.index(after: flag)]
        return switch name {
        case "seated":      MockScenario(name: name, scenario: .seated)
        case "notSeated":   MockScenario(name: name, scenario: .notSeated)
        case "settled":     MockScenario(name: name, scenario: .seatedButSettled)
        case "offline":     MockScenario(name: name, scenario: .failing(.offline))
        case "unauthorised":MockScenario(name: name, scenario: .failing(.unauthorised))
        case "timeout":     MockScenario(name: name, scenario: .failing(.timedOut))
        case "slow":        MockScenario(name: name, scenario: .slow(.seconds(30)))
        default:            nil
        }
    }
}
#endif
