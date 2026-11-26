// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TribunaDependencies",
    dependencies: [
        .package(url: "https://github.com/SnapKit/SnapKit", from: "5.7.1"),
        .package(url: "https://github.com/supabase/supabase-swift", from: "2.0.0"),
        // Маркетинговые пуши и события (D36). Лицензия — только при договоре с Mindbox.
        .package(url: "https://github.com/mindbox-cloud/ios-sdk", from: "2.16.0"),
    ]
)
