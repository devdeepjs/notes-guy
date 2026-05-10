// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "notes-guy",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "NotesGuyCore",
            targets: ["NotesGuyCore"]
        ),
        .executable(
            name: "notes-guy",
            targets: ["NotesGuyCLI"]
        ),
        .executable(
            name: "notes-guy-desktop",
            targets: ["NotesGuyDesktop"]
        )
    ],
    targets: [
        .target(
            name: "NotesGuyCore"
        ),
        .executableTarget(
            name: "NotesGuyCLI",
            dependencies: ["NotesGuyCore"]
        ),
        .executableTarget(
            name: "NotesGuyDesktop",
            dependencies: ["NotesGuyCore"]
        ),
        .testTarget(
            name: "NotesGuyCoreTests",
            dependencies: ["NotesGuyCore"]
        )
    ]
)
