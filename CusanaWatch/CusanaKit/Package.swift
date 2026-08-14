// swift-tools-version: 6.0
import PackageDescription

// CusanaKit holds every piece of logic that is *not* SwiftUI: the Base44 wire
// models, the REST client, and the watch state machine. Keeping it in a package
// means it compiles and unit-tests on macOS in seconds, with no watchOS
// simulator and no test host — the watch app target just links it.
let package = Package(
    name: "CusanaKit",
    platforms: [
        .watchOS(.v10),
        .macOS(.v14),
    ],
    products: [
        .library(name: "CusanaKit", targets: ["CusanaKit"]),
        // Command-line probe: runs the real client against the live backend so
        // the network path is proven before it is ever run on a watch.
        .executable(name: "cusana-probe", targets: ["CusanaProbe"]),
    ],
    targets: [
        .target(name: "CusanaKit"),
        .executableTarget(name: "CusanaProbe", dependencies: ["CusanaKit"]),
        .testTarget(name: "CusanaKitTests", dependencies: ["CusanaKit"]),
    ]
)
