// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TribunaDependencies",
    dependencies: [
        .package(url: "https://github.com/SnapKit/SnapKit", from: "5.7.1"),
        .package(url: "https://github.com/supabase/supabase-swift", from: "2.0.0"),
    ]
)
