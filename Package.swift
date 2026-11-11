// swift-tools-version: 5.9
// SPDX-License-Identifier: GPL-3.0-only
// HyperMac — Copyright (C) 2026 Nguyễn Khắc Đại
// Licensed under the GNU General Public License v3.0 (see LICENSE).
import PackageDescription

let package = Package(
    name: "HyperMac",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "VirtualDisplayBridge",
            path: "Sources/VirtualDisplayBridge",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "HyperMac",
            dependencies: ["VirtualDisplayBridge"],
            path: "Sources",
            exclude: ["VirtualDisplayBridge"],
            linkerSettings: [
                .linkedFramework("IOKit"),
            ]
        )
    ]
)
