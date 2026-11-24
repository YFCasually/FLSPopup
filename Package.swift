// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FLSPopup",
    platforms: [.iOS(.v17)],
    products: [.library(name: "FLSPopup", targets: ["FLSPopup"])],
    targets: [
        .target(name: "FLSPopup"),
        .testTarget(name: "FLSPopupTests", dependencies: ["FLSPopup"])
    ]
)
