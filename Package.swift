// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.
//
// Modified by the Spiral authors, 2026: Spiral's version, checksum and release
// URL, and a MatrixSDKFFI.xcframework beside this file used before the download.
import Foundation
import PackageDescription

let checksum = "2542e7491c65586ec7da5442303ce53491e659baf70bd9461f5d25705dc8f43d"
let version = "26.10.24-spiral.1"
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
