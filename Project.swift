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

let featureTargets = features.map {
    module($0, path: "Features/\($0)", dependencies: [.target(name: "CoreUI"), .external(name: "SnapKit")])
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
    dependencies: [.target(name: "CoreUI")] + features.map { .target(name: $0) },
    settings: settings
)

let project = Project(
    name: "Tribuna",
    targets: [app, coreUI] + featureTargets
)
