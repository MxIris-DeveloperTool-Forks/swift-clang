// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-clang",
    products: [
        .library(
            name: "Clang",
            targets: ["Clang"]
        ),
    ],
    targets: [
        .target(
            name: "Cclang"
        ),
        .target(
            name: "CclangWrapper",
            dependencies: [
                "Cclang",
            ],
        ),
        .target(
            name: "Clang",
            dependencies: [
                "Cclang",
                "CclangWrapper",
            ],
        ),
        .testTarget(
            name: "ClangTests",
            dependencies: ["Clang"]
        ),
    ],
    swiftLanguageModes: [.v5],
)
