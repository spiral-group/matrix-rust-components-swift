// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.
//
// Modified by the Spiral authors, 2026: Spiral's version, checksum and release
// URL, and a MatrixSDKFFI.xcframework beside this file used before the download.
import Foundation
import PackageDescription

let checksum = "a45531a024c2f86da601f4b1f208c139c61bb8a7275a130eea3557d0ca7a8cb3"
let version = "26.10.29-spiral.1"
let releaseBaseURL = "https://github.com/spiral-group/matrix-rust-components-swift/releases/download"
let url = "\(releaseBaseURL)/\(version)/MatrixSDKFFI.xcframework.zip"
let localFrameworkURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("MatrixSDKFFI.xcframework")
let matrixSDKFFITarget: Target = if FileManager.default.fileExists(atPath: localFrameworkURL.path) {
    .binaryTarget(name: "MatrixSDKFFI", path: "MatrixSDKFFI.xcframework")
} else {
    .binaryTarget(name: "MatrixSDKFFI", url: url, checksum: checksum)
}

let package = Package(
    name: "MatrixRustSDK",
    platforms: [
        .iOS(.v16),
    ],
    products: [
        .library(name: "MatrixRustSDK", type: .dynamic, targets: ["MatrixRustSDK"]),
    ],
    targets: [
        matrixSDKFFITarget,
        .target(name: "MatrixRustSDK", dependencies: [.target(name: "MatrixSDKFFI")]),
    ]
)
