import ProjectDescription

// TUIST_BUNDLE_ID — свой ID для установки коллегами на телефон (./install-iphone), D32.
let bundleId = Environment.bundleId.getString(default: "com.tribuna.app")
let deployment: DeploymentTargets = .iOS("16.0")
// Фичи следующих обновлений под флагами сборки (спека docs/superpowers/specs/2026-11-25-updates-1.1-1.2-design.md):
// TUIST_FEATURES=widget,profile2 ./generate → -DFEATURE_WIDGET -DFEATURE_PROFILE2 у всех таргетов. Флаги сборки, а не удалённые:
// Apple отклоняет функции, включаемые после ревью (2.3.1). OTHER_SWIFT_FLAGS — потому что SWIFT_ACTIVE_COMPILATION_CONDITIONS
// Tuist задаёт на уровне конфигурации (DEBUG), и значение таргета там бы потерялось.
let enabledFeatures = Environment.features.getString(default: "").split(separator: ",").map(String.init)
let swiftBase: SettingsDictionary = ["SWIFT_VERSION": "6.0"].merging(enabledFeatures.isEmpty ? [:] : [
    "OTHER_SWIFT_FLAGS": .string((["$(inherited)"] + enabledFeatures.map { "-DFEATURE_\($0.uppercased())" }).joined(separator: " ")),
]) { $1 }
let settings: Settings = .settings(base: swiftBase)
// Сборка для App Store — под командой D53MGF5HR8 с платными capabilities (D35).
// У коллег через ./install-iphone свой Bundle ID и, возможно, бесплатный Apple ID — им этих capabilities не даём.
let isStoreBuild = bundleId == "com.tribuna.app"
let storeSettings: Settings = .settings(base: swiftBase.merging(["DEVELOPMENT_TEAM": "D53MGF5HR8", "CODE_SIGN_STYLE": "Automatic"]) { $1 })
// Общий контейнер приложения и расширения пушей; имя задаёт Mindbox SDK: group.cloud.Mindbox.<bundle id приложения> (D36).
let mindboxGroup = "group.cloud.Mindbox.\(bundleId)"
// Mindbox включается endpoint-ом из кабинета Mindbox (D38): пусто — в сборке нет ни SDK, ни расширения пушей,
// ни processing/remote-notification, ни APNs и App Group, ни запроса трекинга. Endpoint не секрет — лежит в бинарнике.
// Включить: вписать сюда или TUIST_MINDBOX_ENDPOINT=<endpoint> ./generate. Лицензия SDK — только при договоре с Mindbox.
let mindboxEndpoint = Environment.mindboxEndpoint.getString(default: "")
let mindbox = !mindboxEndpoint.isEmpty
// Вход через Apple (D38): true — entitlement и кнопки «Продолжить с Apple». До включения: провайдер Apple в Supabase
// (Client ID = bundle id) и отзыв токена Apple при удалении аккаунта (D33). false — кнопок нет.
let signInWithApple = false

let features = ["Today", "Match", "Radio", "Podcasts", "Player", "Profile"].map { "Feature\($0)" }

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

// Части app-таргета, зависящие от Mindbox и входа через Apple, — отдельно: одним выражением компилятор манифеста не справляется.
let backgroundModes = ["audio", "fetch"] + (mindbox ? ["processing", "remote-notification"] : [])
let backgroundTasks = ["$(PRODUCT_BUNDLE_IDENTIFIER).refresh"] + (mindbox ? [
    "cloud.MindBox.$(PRODUCT_BUNDLE_IDENTIFIER).GDAppRefresh",
    "cloud.MindBox.$(PRODUCT_BUNDLE_IDENTIFIER).GDAppProcessing",
    "cloud.MindBox.$(PRODUCT_BUNDLE_IDENTIFIER).DBCleanAppProcessing",
] : [])
var appInfo: [String: Plist.Value] = [:]
if mindbox {
    // Текст запроса трекинга (D33) — только с Mindbox: без него трекинга нет и запрос не показываем (D38).
    appInfo["NSUserTrackingUsageDescription"] = "Так мы точнее подберём матчи, эфиры и подкасты под ваши интересы"
}
var appEntitlements: [String: Plist.Value] = [
    // Первая группа — прежняя группа приложения: сессия Supabase в Keychain остаётся на месте.
    // Вторая — общая с будущими расширениями (пуши Mindbox).
    "keychain-access-groups": ["$(AppIdentifierPrefix)$(CFBundleIdentifier)", "$(AppIdentifierPrefix)com.tribuna.app.shared"],
    // iCloud KVS: «Только по Wi-Fi» на всех iPhone с тем же Apple ID (D38), в 1.2 — «Турниры в ленте».
    "com.apple.developer.ubiquity-kvstore-identifier": "$(TeamIdentifierPrefix)$(CFBundleIdentifier)",
]
if mindbox {
    // Xcode при выгрузке в App Store сам ставит production.
    appEntitlements["aps-environment"] = "development"
    appEntitlements["com.apple.security.application-groups"] = [.string(mindboxGroup)]
}
if signInWithApple { appEntitlements["com.apple.developer.applesignin"] = ["Default"] }
let appDependencies: [TargetDependency] = [.target(name: "CoreUI"), .target(name: "CoreDomain"), .target(name: "CoreRepositories"), .target(name: "CorePlayback")]
    + (mindbox ? [.external(name: "Mindbox"), .target(name: "TribunaNotificationService")] : [])
    + features.map { .target(name: $0) }

let app: Target = .target(
    name: "Tribuna",
    destinations: [.iPhone],
    product: .app,
    bundleId: bundleId,
    deploymentTargets: deployment,
    infoPlist: .extendingDefault(with: appInfo.merging([
        "CFBundleDisplayName": "Tribuna",
        // Системные элементы (кнопка Apple, системные листы) — по-русски, как всё приложение.
        "CFBundleDevelopmentRegion": "ru",
        "UIUserInterfaceStyle": "Dark",
        "UIAppFonts": ["Unbounded.ttf"],
        "UILaunchScreen": ["UIColorName": ""],
        // fetch — обновление лент подписок в фоне (D35); загрузкам выпусков фоновый режим не нужен (фоновая URLSession).
        // processing, remote-notification и три задачи cloud.MindBox.* — гарантированная доставка событий Mindbox (D36).
        "UIBackgroundModes": .array(backgroundModes.map { .string($0) }),
        "BGTaskSchedulerPermittedIdentifiers": .array(backgroundTasks.map { .string($0) }),
        "MindboxEndpoint": .string(mindboxEndpoint),
        "TribunaSignInWithApple": .boolean(signInWithApple),
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
    ]) { $1 }),
    sources: ["Tribuna/Sources/**"],
    resources: ["Tribuna/Resources/**"],
    entitlements: isStoreBuild ? .dictionary(appEntitlements) : nil,
    dependencies: appDependencies,
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
    targets: [app] + (mindbox ? [notificationService] : []) + [coreUI, coreDomain, coreRepositories, coreRepositoriesTests, coreUITests, corePlayback, corePlaybackTests, featureTodayTests, featureMatchTests, featureRadioTests, featurePlayerTests, featurePodcastsTests, featureProfileTests] + featureTargets
)
