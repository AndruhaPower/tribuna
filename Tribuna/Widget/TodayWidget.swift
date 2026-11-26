#if FEATURE_WIDGET
import CoreDomain
import CoreRepositories
import SwiftUI
import WidgetKit

/// Виджет «Сегодня» (1.1, D40). SwiftUI — исключение из D6: виджеты бывают только на SwiftUI.
@main
struct TribunaWidgets: WidgetBundle {
    var body: some Widget { TodayWidget() }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodayWidget", provider: TodayProvider()) { TodayWidgetView(entry: $0) }
            .configurationDisplayName("Сегодня")
            .description("Ближайшие матчи и счёт. Матчи из закладок — первыми.")
            .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

struct TodayEntry: TimelineEntry {
    let date: Date
    let matches: [Match]
    /// nil — данные загрузились (матчей может не быть); текст — нет сети или ошибка.
    var error: String?
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry { TodayEntry(date: Date(), matches: []) }

    // WidgetKit разрешает звать completion с любого потока; замыкание не Sendable только по объявлению SDK.
    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        nonisolated(unsafe) let completion = completion
        Task { completion(await load().entry) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        nonisolated(unsafe) let completion = completion
        Task {
            let (entry, refresh) = await load()
            completion(Timeline(entries: [entry], policy: .after(refresh)))
        }
    }

    private func load() async -> (entry: TodayEntry, refresh: Date) {
        let now = Date()
        // Закладки пишет приложение (без App Group — сборки коллег — их нет, виджет просто без приоритета).
        let saved = UserDefaults(suiteName: WidgetPlan.appGroup)?.stringArray(forKey: WidgetPlan.bookmarksKey) ?? []
        do {
            let all = try await Services.todayMatches(supabaseURL: AppConfig.supabaseURL, supabaseKey: AppConfig.supabaseKey, now: now)
            let picked = WidgetPlan.pick(all, bookmarks: Set(saved.map(MatchID.init(rawValue:))), limit: 3)
            return (TodayEntry(date: now, matches: picked), WidgetPlan.nextRefresh(all, now: now))
        } catch {
            return (TodayEntry(date: now, matches: [], error: "Нет связи — обновим позже"), now.addingTimeInterval(15 * 60))
        }
    }
}

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayEntry

    var body: some View {
        content
            .widgetURL(entry.matches.first.flatMap(Self.url) ?? URL(string: "tribuna://today"))
            .modifier(WidgetBackground())
    }

    @ViewBuilder private var content: some View {
        switch family {
        case .accessoryRectangular:
            if let match = entry.matches.first { MatchLine(match: match, compact: true) } else { empty }
        case .systemSmall:
            VStack(alignment: .leading, spacing: 6) {
                header
                if let match = entry.matches.first { MatchBlock(match: match) } else { empty }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            VStack(alignment: .leading, spacing: 6) {
                header
                if entry.matches.isEmpty { empty }
                // Три матча с турниром в высоту среднего виджета не входят — строки без турнира.
                ForEach(entry.matches) { match in
                    Link(destination: Self.url(match) ?? URL(string: "tribuna://today")!) { MatchLine(match: match, compact: true) }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var header: some View {
        Text("СЕГОДНЯ").font(.caption2.weight(.semibold)).foregroundStyle(WidgetColors.secondary)
    }

    private var empty: some View {
        Text(entry.error ?? "Сегодня матчей нет").font(.footnote).foregroundStyle(WidgetColors.secondary)
    }

    static func url(_ match: Match) -> URL? { URL(string: "tribuna://match/\(match.id.rawValue)") }
}

/// Строка матча: «LIV — ARS» и справа время, счёт или статус.
struct MatchLine: View {
    let match: Match
    let compact: Bool

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                if !compact { Text(match.competition.name).font(.caption2).foregroundStyle(WidgetColors.secondary).lineLimit(1) }
                Text("\(Self.team(match.home)) — \(Self.team(match.away))").font(.subheadline.weight(.semibold)).lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(Self.trailing(match)).font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(match.status == .live ? WidgetColors.accent : WidgetColors.primary)
        }
        .foregroundStyle(WidgetColors.primary)
        .accessibilityElement(children: .combine)
    }

    static func team(_ team: Team?) -> String { team?.abbreviation ?? team?.name ?? "—" }

    static func trailing(_ match: Match) -> String {
        let score = "\(match.homeScore ?? 0):\(match.awayScore ?? 0)"
        switch match.status {
        case .live, .paused: return match.status == .paused ? "Перерыв \(score)" : "LIVE \(score)"
        case .finished: return score
        case .postponed: return "Перенесён"
        case .cancelled: return "Отменён"
        case .scheduled: return match.kickoff.formatted(date: .omitted, time: .shortened)
        }
    }
}

/// Маленький виджет: в строку «турнир, команды, время» не помещается — турнир, хозяева, гости и время столбиком.
struct MatchBlock: View {
    let match: Match

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(match.competition.name).font(.caption2).foregroundStyle(WidgetColors.secondary).lineLimit(1)
            Text(MatchLine.team(match.home)).font(.headline)
            Text(MatchLine.team(match.away)).font(.headline)
            Text(MatchLine.trailing(match)).font(.title3.monospacedDigit().weight(.semibold)).padding(.top, 4)
                .foregroundStyle(match.status == .live ? WidgetColors.accent : WidgetColors.primary)
        }
        .foregroundStyle(WidgetColors.primary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .accessibilityElement(children: .combine)
    }
}

/// Цвета `Palette` (CoreUI) без UIKit-зависимостей виджета.
enum WidgetColors {
    static let background = Color(red: 0x0B / 255, green: 0x10 / 255, blue: 0x20 / 255)
    static let primary = Color(red: 0xEE / 255, green: 0xF1 / 255, blue: 0xF8 / 255)
    static let secondary = Color(red: 0x9A / 255, green: 0xA4 / 255, blue: 0xBD / 255)
    static let accent = Color(red: 0xFF / 255, green: 0xB0 / 255, blue: 0x20 / 255)
}

/// iOS 17 требует `containerBackground`, iOS 16 — обычный фон.
struct WidgetBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17, *) {
            content.containerBackground(WidgetColors.background, for: .widget)
        } else {
            content.padding().background(WidgetColors.background)
        }
    }
}
#endif
