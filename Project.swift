import ProjectDescription

let bundleId = "com.tribuna.app"
let deployment: DeploymentTargets = .iOS("16.0")
let settings: Settings = .settings(base: ["SWIFT_VERSION": "6.0"])

let features = ["Today", "Match", "Bookmarks", "Radio", "Podcasts", "Player", "Profile"].map { "Feature\($0)" }

func module(_ name: String, path: String, dependencies: [TargetDependency]) -> Target {
    .target(
        name: name,
        destinations: .iOS,
        product: .staticFramework,
        bundleId: "\(bundleId).\(name)",
        deploymentTargets: deployment,
        sources: ["\(path)/Sources/**"],
        dependencies: dependencies,
        settings: settings
    )
}

let coreUI = module("CoreUI", path: "Core/CoreUI", dependencies: [.external(name: "SnapKit")])

let coreDomain = module("CoreDomain", path: "Core/CoreDomain", dependencies: [])

let coreServices = module(
    "CoreServices",
    path: "Core/CoreServices",
    dependencies: [.target(name: "CoreDomain"), .external(name: "Supabase")]
)

let coreServicesTests: Target = .target(
    name: "CoreServicesTests",
    destinations: .iOS,
    product: .unitTests,
    bundleId: "\(bundleId).CoreServicesTests",
    deploymentTargets: deployment,
    sources: ["Core/CoreServices/Tests/**/*.swift"],
    resources: ["Core/CoreServices/Tests/Fixtures/**"],
    dependencies: [.target(name: "CoreServices"), .target(name: "CoreDomain")],
    settings: settings
)

let featureTargets = features.map {
    var deps: [TargetDependency] = [.target(name: "CoreUI"), .external(name: "SnapKit")]
    if $0 == "FeatureToday" { deps.append(.target(name: "CoreDomain")) }
    return module($0, path: "Features/\($0)", dependencies: deps)
}

let app: Target = .target(
    name: "Tribuna",
    destinations: [.iPhone],
    product: .app,
    bundleId: bundleId,
    deploymentTargets: deployment,
    infoPlist: .extendingDefault(with: [
        "CFBundleDisplayName": "Tribuna",
        "UIUserInterfaceStyle": "Dark",
        "UIAppFonts": ["Unbounded.ttf"],
        "UILaunchScreen": ["UIColorName": ""],
        "UIApplicationSceneManifest": [
            "UIApplicationSupportsMultipleScenes": false,
            "UISceneConfigurations": [
                "UIWindowSceneSessionRoleApplication": [[
                    "UISceneConfigurationName": "Default",
                    "UISceneDelegateClassName": "$(PRODUCT_MODULE_NAME).SceneDelegate",
                ]],
            ],
        ],
    ]),
    sources: ["Tribuna/Sources/**"],
    resources: ["Tribuna/Resources/**"],
    dependencies: [.target(name: "CoreUI"), .target(name: "CoreDomain"), .target(name: "CoreServices")] + features.map { .target(name: $0) },
    settings: settings
)

let project = Project(
    name: "Tribuna",
    targets: [app, coreUI, coreDomain, coreServices, coreServicesTests] + featureTargets
)
