import ProjectDescription

// TUIST_BUNDLE_ID — свой ID для установки коллегами на телефон (./install-iphone), D32.
let bundleId = Environment.bundleId.getString(default: "com.tribuna.app")
let deployment: DeploymentTargets = .iOS("16.0")
let settings: Settings = .settings(base: ["SWIFT_VERSION": "6.0"])
// Сборка для App Store — под командой D53MGF5HR8 с платными capabilities (D35).
// У коллег через ./install-iphone свой Bundle ID и, возможно, бесплатный Apple ID — им этих capabilities не даём.
let isStoreBuild = bundleId == "com.tribuna.app"
let storeSettings: Settings = .settings(base: ["SWIFT_VERSION": "6.0", "DEVELOPMENT_TEAM": "D53MGF5HR8", "CODE_SIGN_STYLE": "Automatic"])
// Общий контейнер приложения и расширения пушей; имя задаёт Mindbox SDK: group.cloud.Mindbox.<bundle id приложения> (D36).
let mindboxGroup = "group.cloud.Mindbox.\(bundleId)"

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
    dependencies: [.target(name: "CoreDomain"), .external(name: "PostgREST"), .external(name: "Auth")]
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

let featureProfileTests: Target = .target(
    name: "FeatureProfileTests",
    destinations: .iOS,
    product: .unitTests,
    bundleId: "\(bundleId).FeatureProfileTests",
    deploymentTargets: deployment,
    sources: ["Features/FeatureProfile/Tests/**"],
    dependencies: [.target(name: "FeatureProfile"), .target(name: "CoreDomain")],
    settings: settings
)

let featureTargets = features.map {
    var deps: [TargetDependency] = [.target(name: "CoreUI"), .external(name: "SnapKit")]
    var resources: ResourceFileElements?
    if ["FeatureToday", "FeatureMatch", "FeatureRadio", "FeaturePlayer", "FeaturePodcasts", "FeatureProfile"].contains($0) {
        deps.append(.target(name: "CoreDomain"))
    }
    if ["FeatureToday", "FeatureMatch", "FeatureRadio", "FeaturePlayer", "FeaturePodcasts"].contains($0) {
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
        // Системные элементы (кнопка Apple, системные листы) — по-русски, как всё приложение.
        "CFBundleDevelopmentRegion": "ru",
        "UIUserInterfaceStyle": "Dark",
        "UIAppFonts": ["Unbounded.ttf"],
        "UILaunchScreen": ["UIColorName": ""],
        // fetch — обновление лент подписок в фоне (D35); загрузкам выпусков фоновый режим не нужен (фоновая URLSession).
        // fetch, processing, remote-notification и три задачи cloud.MindBox.* — гарантированная доставка событий Mindbox (D36).
        "UIBackgroundModes": ["audio", "fetch", "processing", "remote-notification"],
        "BGTaskSchedulerPermittedIdentifiers": [
            "$(PRODUCT_BUNDLE_IDENTIFIER).refresh",
            "cloud.MindBox.$(PRODUCT_BUNDLE_IDENTIFIER).GDAppRefresh",
            "cloud.MindBox.$(PRODUCT_BUNDLE_IDENTIFIER).GDAppProcessing",
            "cloud.MindBox.$(PRODUCT_BUNDLE_IDENTIFIER).DBCleanAppProcessing",
        ],
        // Текст запроса трекинга (D33).
        "NSUserTrackingUsageDescription": "Так мы точнее подберём матчи, эфиры и подкасты под ваши интересы",
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
    entitlements: isStoreBuild ? .dictionary([
        // Первая группа — прежняя группа приложения: сессия Supabase в Keychain остаётся на месте.
        // Вторая — общая с будущими расширениями (пуши Mindbox).
        "keychain-access-groups": ["$(AppIdentifierPrefix)$(CFBundleIdentifier)", "$(AppIdentifierPrefix)com.tribuna.app.shared"],
        "com.apple.developer.ubiquity-kvstore-identifier": "$(TeamIdentifierPrefix)$(CFBundleIdentifier)",
        // Xcode при выгрузке в App Store сам ставит production.
        "aps-environment": "development",
        "com.apple.security.application-groups": [.string(mindboxGroup)],
    ]) : nil,
    dependencies: [.target(name: "CoreUI"), .target(name: "CoreDomain"), .target(name: "CoreRepositories"), .target(name: "CorePlayback"),
                   .external(name: "Mindbox"), .target(name: "TribunaNotificationService")] + features.map { .target(name: $0) },
    settings: isStoreBuild ? storeSettings : settings
)

/// Расширение пушей Mindbox: картинки и кнопки в уведомлении, отметка доставки (D36).
let notificationService: Target = .target(
    name: "TribunaNotificationService",
    destinations: [.iPhone],
    product: .appExtension,
    bundleId: "\(bundleId).NotificationService",
    deploymentTargets: deployment,
    infoPlist: .extendingDefault(with: [
        "CFBundleDisplayName": "Tribuna",
        "NSExtension": [
            "NSExtensionPointIdentifier": "com.apple.usernotifications.service",
            "NSExtensionPrincipalClass": "$(PRODUCT_MODULE_NAME).NotificationService",
        ],
    ]),
    sources: ["Tribuna/NotificationService/**"],
    entitlements: isStoreBuild ? .dictionary(["com.apple.security.application-groups": [.string(mindboxGroup)]]) : nil,
    dependencies: [.external(name: "MindboxNotificationsService")],
    settings: isStoreBuild ? storeSettings : settings
)

let project = Project(
    name: "Tribuna",
    targets: [app, notificationService, coreUI, coreDomain, coreRepositories, coreRepositoriesTests, coreUITests, corePlayback, corePlaybackTests, featureTodayTests, featureMatchTests, featureRadioTests, featurePlayerTests, featurePodcastsTests, featureProfileTests] + featureTargets
)
