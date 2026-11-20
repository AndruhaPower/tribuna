import ProjectDescription

let bundleId = "com.tribuna.app"
let deployment: DeploymentTargets = .iOS("16.0")
let settings: Settings = .settings(base: ["SWIFT_VERSION": "6.0"])

let features = ["Today", "Match", "Bookmarks", "Radio", "Podcasts", "Player", "Profile"].map { "Feature\($0)" }

func module(_ name: String, path: String, resources: ResourceFileElements? = nil, dependencies: [TargetDependency]) -> Target {
    .target(
        name: name,
        destinations: .iOS,
        product: .staticFramework,
        bundleId: "\(bundleId).\(name)",
        deploymentTargets: deployment,
        sources: ["\(path)/Sources/**"],
        resources: resources,
        dependencies: dependencies,
        settings: settings
    )
}

let coreUI = module("CoreUI", path: "Core/CoreUI", resources: ["Core/CoreUI/Resources/**"], dependencies: [.external(name: "SnapKit")])

let coreDomain = module("CoreDomain", path: "Core/CoreDomain", dependencies: [])

let coreRepositories = module(
    "CoreRepositories",
    path: "Core/CoreRepositories",
    dependencies: [.target(name: "CoreDomain"), .external(name: "PostgREST")]
)

let corePlayback = module("CorePlayback", path: "Core/CorePlayback", dependencies: [.target(name: "CoreDomain")])

let corePlaybackTests: Target = .target(
    name: "CorePlaybackTests",
    destinations: .iOS,
    product: .unitTests,
    bundleId: "\(bundleId).CorePlaybackTests",
    deploymentTargets: deployment,
    sources: ["Core/CorePlayback/Tests/**"],
    dependencies: [.target(name: "CorePlayback"), .target(name: "CoreDomain")],
    settings: settings
)

let coreRepositoriesTests: Target = .target(
    name: "CoreRepositoriesTests",
    destinations: .iOS,
    product: .unitTests,
    bundleId: "\(bundleId).CoreRepositoriesTests",
    deploymentTargets: deployment,
    sources: ["Core/CoreRepositories/Tests/**/*.swift"],
    resources: ["Core/CoreRepositories/Tests/Fixtures/**"],
    dependencies: [.target(name: "CoreRepositories"), .target(name: "CoreDomain")],
    settings: settings
)

let coreUITests: Target = .target(
    name: "CoreUITests",
    destinations: .iOS,
    product: .unitTests,
    bundleId: "\(bundleId).CoreUITests",
    deploymentTargets: deployment,
    sources: ["Core/CoreUI/Tests/**"],
    dependencies: [.target(name: "CoreUI")],
    settings: settings
)

let featureTodayTests: Target = .target(
    name: "FeatureTodayTests",
    destinations: .iOS,
    product: .unitTests,
    bundleId: "\(bundleId).FeatureTodayTests",
    deploymentTargets: deployment,
    sources: ["Features/FeatureToday/Tests/**"],
    dependencies: [.target(name: "FeatureToday"), .target(name: "CoreDomain")],
    settings: settings
)

let featureMatchTests: Target = .target(
    name: "FeatureMatchTests",
    destinations: .iOS,
    product: .unitTests,
    bundleId: "\(bundleId).FeatureMatchTests",
    deploymentTargets: deployment,
    sources: ["Features/FeatureMatch/Tests/**"],
    dependencies: [.target(name: "FeatureMatch"), .target(name: "CoreDomain")],
    settings: settings
)

let featureRadioTests: Target = .target(
    name: "FeatureRadioTests",
    destinations: .iOS,
    product: .unitTests,
    bundleId: "\(bundleId).FeatureRadioTests",
    deploymentTargets: deployment,
    sources: ["Features/FeatureRadio/Tests/**"],
    dependencies: [.target(name: "FeatureRadio"), .target(name: "CoreDomain")],
    settings: settings
)

let featurePlayerTests: Target = .target(
    name: "FeaturePlayerTests",
    destinations: .iOS,
    product: .unitTests,
    bundleId: "\(bundleId).FeaturePlayerTests",
    deploymentTargets: deployment,
    sources: ["Features/FeaturePlayer/Tests/**"],
    dependencies: [.target(name: "FeaturePlayer"), .target(name: "CoreDomain")],
    settings: settings
)

let featurePodcastsTests: Target = .target(
    name: "FeaturePodcastsTests",
    destinations: .iOS,
    product: .unitTests,
    bundleId: "\(bundleId).FeaturePodcastsTests",
    deploymentTargets: deployment,
    sources: ["Features/FeaturePodcasts/Tests/**"],
    dependencies: [.target(name: "FeaturePodcasts"), .target(name: "CoreDomain")],
    settings: settings
)

let featureTargets = features.map {
    var deps: [TargetDependency] = [.target(name: "CoreUI"), .external(name: "SnapKit")]
    var resources: ResourceFileElements?
    if ["FeatureToday", "FeatureMatch", "FeatureRadio", "FeaturePlayer", "FeaturePodcasts"].contains($0) {
        deps.append(.target(name: "CoreDomain"))
        resources = ["Features/\($0)/Resources/**"]
    }
    return module($0, path: "Features/\($0)", resources: resources, dependencies: deps)
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
        "UIBackgroundModes": ["audio"],
        // Макеты только портретные.
        "UISupportedInterfaceOrientations": ["UIInterfaceOrientationPortrait"],
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
    dependencies: [.target(name: "CoreUI"), .target(name: "CoreDomain"), .target(name: "CoreRepositories"), .target(name: "CorePlayback")] + features.map { .target(name: $0) },
    settings: settings
)

let project = Project(
    name: "Tribuna",
    targets: [app, coreUI, coreDomain, coreRepositories, coreRepositoriesTests, coreUITests, corePlayback, corePlaybackTests, featureTodayTests, featureMatchTests, featureRadioTests, featurePlayerTests, featurePodcastsTests] + featureTargets
)
