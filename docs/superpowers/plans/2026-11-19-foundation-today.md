# Каркас экрана и данных + «Сегодня» — план реализации

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Модули `CoreDomain`/`CoreServices`, паттерн экрана MVVM и экран «Сегодня» с реальными данными футбола из `tribuna_db` и НХЛ.

**Architecture:** Фича зависит только от протоколов `CoreDomain`; приложение собирает реализации из `CoreServices` и обрабатывает выходы фич. Экран = `ViewModel` (`@MainActor`, `@Published state`) + `State` (готово к показу) + `ViewController` (SnapKit, diffable collection).

**Tech Stack:** Swift 6, UIKit, iOS 16, Tuist 4.195, SnapKit 5.7.1, supabase-swift 2.x, Combine, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-11-19-foundation-today-design.md`

## Global Constraints

- iOS 16 минимум, Swift 6 language mode (D3, D6). API новее iOS 16 — только за `if #available`.
- UIKit + SnapKit, без storyboard/xib (D6). Цвета — только `Palette`, шрифты — только `Typography` (D12, D18); новые цвета добавляются в `Palette`.
- Фичи не зависят друг от друга и от `CoreServices`; `CoreDomain` не зависит ни от чего (D5).
- Фича наружу: `Feature<Имя>.make(dependencies:output:) -> UIViewController`, всё остальное `internal` (D11, уточнение этого этапа).
- Проект генерируется: после правок `Project.swift`/`Tuist/Package.swift` — `./generate`; `.xcodeproj`/`.xcworkspace` не коммитить (D4).
- Supabase: URL `https://wgwsdhyrazjzqwvnhgzk.supabase.co`, publishable-ключ `sb_publishable_l-xow6_fopQcOc02UAzpfw_RbeFcQLE` — в конфиге приложения. Только чтение (RLS).
- День — по часовому поясу устройства (D17). Полоса дней: вчера … +6, по умолчанию сегодня.
- Включённые турниры и их порядок секций: CL, PL, PD, BL1, SA, FL1, затем НХЛ.
- Макет 780 px = 390 pt @2x. Замеры «Сегодня»: поля 20 pt; карточки шириной 350 pt; чип дня ≈51.5×55 pt, шаг ≈60 pt; кружок аббревиатуры 28 pt; кнопка в карточке 36 pt высотой; строка списка турнира ≈71.5 pt; разделитель 1 pt `Palette.separator`. Точнее — замер по PNG при вёрстке.
- Документация и комментарии — на русском. Коммиты на русском, с `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **Ночные матчи НХЛ** — матч в 03:00 по Москве в четверг должен попасть в день «Чт» и секцию с подписью «ночь на чт»; НХЛ отдаёт день по восточному времени США. Тест в Task 2.
2. **Смена дня у полуночи и часовой пояс не Москва** — группировка по местному дню устройства, не по UTC. Тест в Task 3 (пояс `Asia/Vladivostok`).
3. **Сбой одного источника** — НХЛ недоступен, а футбол пришёл (или наоборот): экран показывает то, что есть, без общей ошибки. Тест в Task 2 (композитный репозиторий) и Task 3.
4. **Команда не определена** (плей-офф, `home_team_id = null`) — строка показывает «—», не падает. Тест в Task 3.
5. **Автообновление не плодит запросы** — таймер не работает, когда экран скрыт или выбран не сегодняшний день, и не запускает второй запрос, пока идёт первый. Тест в Task 3.

---

## Структура файлов

```
Core/CoreDomain/Sources/        Models.swift, MatchesRepository.swift, BookmarksStore.swift
Core/CoreServices/Sources/      FootballRepository.swift, NHLClient.swift, CombinedMatchesRepository.swift,
                                UserDefaultsBookmarksStore.swift, ServicesFactory.swift
Core/CoreServices/Tests/        NHLClientTests.swift, FootballMappingTests.swift, CombinedMatchesRepositoryTests.swift,
                                BookmarksStoreTests.swift
Core/CoreUI/Sources/            + TeamBadgeView.swift, SectionHeaderView.swift
Features/FeatureToday/Sources/  FeatureToday.swift, TodayViewModel.swift, TodayState.swift, TodayFormatter.swift,
                                TodayViewController.swift, Cells/*.swift
Features/FeatureToday/Tests/    TodayViewModelTests.swift, TodayFormatterTests.swift, Fakes.swift
Features/FeatureMatch/Sources/  FeatureMatch.swift (заглушка с заголовком матча)
Tribuna/Sources/                AppDependencies.swift, AppConfig.swift, SceneDelegate.swift (сборка)
supabase/migrations/            20261119130000_competitions_ru.sql
Project.swift, Tuist/Package.swift, docs/decisions.md (D21)
```

---

### Task 1: CoreDomain — модели и протоколы

**Files:** Create `Core/CoreDomain/Sources/{Models,MatchesRepository,BookmarksStore}.swift`; Modify `Project.swift` (модуль `CoreDomain`, static framework, без зависимостей; `FeatureToday` дополнительно зависит от `CoreDomain`; приложение — от `CoreDomain`). Модуль `CoreServices`, зависимость supabase-swift и тестовые таргеты появляются в Task 2 и Task 3 вместе со своим кодом.

**Interfaces — Produces:**
```swift
public enum Sport: String, Sendable { case football, hockey }
public struct MatchID: Hashable, Sendable, Codable, RawRepresentable { public let rawValue: String }  // "football:555081", "hockey:2025020301"
public enum MatchStatus: Sendable, Equatable { case scheduled, live, paused, finished, postponed, cancelled }
public struct Team: Sendable, Equatable { public let name: String; public let abbreviation: String? }   // name уже выбран: name_ru ?? short_name ?? name
public struct Competition: Sendable, Equatable { public let code: String; public let name: String }   // "PL", "АПЛ"; НХЛ: code "NHL", name "НХЛ"
public struct Match: Sendable, Equatable, Identifiable {
    public let id: MatchID; public let sport: Sport; public let competition: Competition
    public let kickoff: Date; public let status: MatchStatus
    public let home: Team?; public let away: Team?
    public let homeScore: Int?; public let awayScore: Int?
    public let round: String?           // "12 тур" для футбола, nil для НХЛ
}
public protocol MatchesRepository: Sendable { func matches(in interval: DateInterval) async throws -> [Match] }
@MainActor public protocol BookmarksStore: AnyObject {
    var bookmarks: Set<MatchID> { get }
    var bookmarksPublisher: AnyPublisher<Set<MatchID>, Never> { get }
    func toggle(_ id: MatchID)
}
```
- [ ] **Step 1:** Модели и протоколы по интерфейсу; публичные `init` у всех структур.
- [ ] **Step 2:** Правки `Project.swift` по списку файлов выше.
- [ ] **Step 3:** `./generate` и сборка схемы `Tribuna` для симулятора — Expected: BUILD SUCCEEDED.
- [ ] **Step 4:** Коммит `Каркас: модуль CoreDomain`.

### Task 2: CoreServices — данные

**Files:** Create `Core/CoreServices/Sources/*`, `Core/CoreServices/Tests/*`, `supabase/migrations/20261119130000_competitions_ru.sql`; Modify `Project.swift` (модуль `CoreServices`: static framework, зависит от `CoreDomain` и `.external(name: "Supabase")`; таргет `CoreServicesTests` типа `.unitTests` с источниками `Core/CoreServices/Tests/**` и фикстурами как ресурсами; приложение зависит от `CoreServices`), `Tuist/Package.swift` (+ `https://github.com/supabase/supabase-swift` from `2.0.0`).

**Interfaces — Consumes:** Task 1. **Produces:**
```swift
public enum Services {
    @MainActor public static func make(supabaseURL: URL, supabaseKey: String, defaults: UserDefaults = .standard)
        -> (matches: MatchesRepository, bookmarks: BookmarksStore)
}
```
- Футбол: `FootballRepository` читает `matches` с вложенными `competition:competitions(code,name,name_ru,enabled)`, `home:teams!home_team_id(name,short_name,tla,name_ru,short_name_ru)`, `away:teams!away_team_id(...)` при `utc_date` в интервале, оставляет `competition.enabled`. Разбор строки — отдельная чистая функция `FootballMapping.match(from: FootballRow) -> Match` (статусы: `SCHEDULED`/`TIMED` → scheduled; `IN_PLAY` / `EXTRA_TIME` / `PENALTY_SHOOTOUT` → live; `PAUSED` → paused; `FINISHED`/`AWARDED` → finished; `POSTPONED`/`SUSPENDED` → postponed; `CANCELLED` → cancelled; `round` = "\(matchday) тур", если `matchday` есть).
- НХЛ: `NHLClient` — `GET https://api-web.nhle.com/v1/score/{yyyy-MM-dd}`; запрашивает даты по поясу `America/New_York`, покрывающие интервал (1–2 запроса), оставляет игры со `startTimeUTC` в интервале. Статусы: `FUT`/`PRE` → scheduled; `LIVE`/`CRIT` → live; `FINAL`/`OFF` → finished; `PPD` → postponed; `CNCL` → cancelled. Команда: `name.default`, `abbrev`.
- `CombinedMatchesRepository` — запускает оба источника параллельно; если один упал — отдаёт другой; если упали оба — бросает первую ошибку.
- `UserDefaultsBookmarksStore` — ключ `bookmarks.v1`, массив строк `MatchID.rawValue`.
- Миграция: `update competitions set name_ru = ...` — PL 'АПЛ', PD 'Ла Лига', BL1 'Бундеслига', SA 'Серия А', FL1 'Лига 1', CL 'Лига чемпионов'.

- [ ] **Step 1: Тесты:**
  - `NHLClientTests`: разбор фикстуры `tribuna_api_report/raw/nhl_score_now.body` (скопировать в `Core/CoreServices/Tests/Fixtures/`) → непустой список, у первой игры `sport == .hockey`, `competition.code == "NHL"`, `id.rawValue` начинается с `"hockey:"`; таблица статусов (каждый из 7 кодов); `datesToQuery(for: интервал 19.11 00:00–24:00 по Москве)` → `["2026-11-18", "2026-11-19"]` (Review Focus 1); игра со `startTimeUTC` 2026-11-20T00:00:00Z попадает в московский день 20.11 (03:00), не в 19.11.
  - `FootballMappingTests`: строка с `name_ru = "Арсенал"` → `Team.name == "Арсенал"`; без `name_ru`, с `short_name` → `short_name`; `home = nil` → `Match.home == nil`; таблица статусов; `matchday 12` → `round == "12 тур"`; `competition.name_ru == nil` → `competition.name` = английское.
  - `CombinedMatchesRepositoryTests` (фейки источников): оба ок → объединение; НХЛ бросает → только футбол, без ошибки; оба бросают → ошибка (Review Focus 3).
  - `BookmarksStoreTests`: toggle добавляет/удаляет; новое хранилище на том же `UserDefaults(suiteName:)` видит сохранённое; паблишер шлёт новое множество.
- [ ] **Step 2:** Запуск тестов `CoreServicesTests` — Expected: FAIL.
- [ ] **Step 3:** Реализация. Сетевые клиенты принимают `URLSession`/клиент Supabase через `init` (для тестов разбор вызывается без сети).
- [ ] **Step 4:** Тесты — Expected: PASS. `supabase db reset` локально — миграция применяется.
- [ ] **Step 5:** Коммит `Каркас: CoreServices — футбол, НХЛ, закладки`.

### Task 3: FeatureToday — модель экрана

**Files:** Create `Features/FeatureToday/Sources/{TodayViewModel,TodayState,TodayFormatter}.swift`, `Features/FeatureToday/Tests/*`; Modify `Project.swift` (таргет `FeatureTodayTests` типа `.unitTests`, источники `Features/FeatureToday/Tests/**`, зависит от `FeatureToday`).

**Interfaces — Consumes:** `MatchesRepository`, `BookmarksStore`, модели (Task 1). **Produces:**
```swift
struct TodayState: Equatable {
    var days: [DayItem]                    // DayItem: id (Date начала дня), weekday "Ср", number "18", isSelected
    var content: Content                   // .loading | .loaded(events: [EventCard], sections: [Section]) | .empty | .error(message: String)
}
// EventCard: id, header "АПЛ · 12 тур", isLive, home/away (name, abbreviation), homeScore/awayScore строки
// Section: id (код турнира), title "ЛИГА ЧЕМПИОНОВ", trailing "2 матча" | "ночь на чт", rows: [MatchRow]
// MatchRow: id, leading "22:00" | "2 : 1" | "LIVE 2 : 1" | "Перенесён" | "Отменён", home "Реал Мадрид", away "Бавария", isBookmarked
@MainActor final class TodayViewModel {
    @Published private(set) var state: TodayState
    init(matches: MatchesRepository, bookmarks: BookmarksStore, now: @escaping () -> Date = Date.init,
         calendar: Calendar = .current, onOpenMatch: @escaping (MatchID, String) -> Void)
    func viewDidAppear(); func viewDidDisappear()
    func didSelectDay(_ id: Date); func didPullToRefresh(); func didTapRetry()
    func didToggleBookmark(_ id: MatchID); func didTapMatch(_ id: MatchID)
}
```
- Порядок секций: CL, PL, PD, BL1, SA, FL1, NHL; внутри — по времени начала. «Мои события» — матчи выбранного дня из закладок, по времени.
- Подпись НХЛ: если все матчи секции начинаются с 00:00 до 08:00 местного — «ночь на <день недели выбранного дня в винительном/кратком: "чт">»; иначе — «N матч(а/ей)» с правильным склонением.
- Автообновление: таймер 60 с, только если экран виден, выбран сегодняшний день и есть матч `live`/`paused` или `scheduled` со стартом в ближайшие 15 мин; повторный запрос не стартует, пока идёт текущий.
- Ошибка: «Не удалось загрузить матчи» + повтор. Пусто: `.empty`.

- [ ] **Step 1: Тесты** (`now` = 2026-11-18 20:00 Москва, `calendar.timeZone = Europe/Moscow`, фейковый репозиторий возвращает заданные матчи и считает вызовы):
  - `days.count == 8`, первый — 17.11 «Вт», выбран 18.11 «Ср».
  - Секции идут CL → PL → … → NHL; пустые турниры не показываются; trailing «2 матча», «1 матч», «5 матчей».
  - НХЛ с матчами 03:00 и 04:30 → trailing «ночь на чт».
  - Строки: scheduled → «22:00»; finished 2:1 → «2 : 1»; live → «LIVE 2 : 1»; postponed → «Перенесён»; `home == nil` → имя «—» (Review Focus 4).
  - Закладка матча дня → он в `events` с `header "АПЛ · 12 тур"`; `didToggleBookmark` обновляет `isBookmarked` и `events` без нового запроса.
  - `didSelectDay(19.11)` → запрос с интервалом 19.11 00:00–20.11 00:00 по поясу календаря; с `Asia/Vladivostok` интервал сдвигается (Review Focus 2).
  - Репозиторий бросает → `.error`; `didTapRetry` → повторный запрос → `.loaded`.
  - Пустой ответ → `.empty`.
  - Автообновление: при live-матче и видимом экране тик таймера (инжектируемый планировщик или вызов внутреннего `tick()`) делает запрос; после `viewDidDisappear` — нет; при выбранном не-сегодня — нет; пока запрос в полёте — второй не стартует (Review Focus 5).
  - `didTapMatch` вызывает `onOpenMatch(id, "Ливерпуль — Арсенал")`.
- [ ] **Step 2:** Тесты — Expected: FAIL. **Step 3:** Реализация (форматирование — в `TodayFormatter`, чистые функции). **Step 4:** Тесты — PASS.
- [ ] **Step 5:** Коммит `«Сегодня»: модель экрана`.

### Task 4: FeatureToday — вёрстка

**Files:** Create `Features/FeatureToday/Sources/{FeatureToday,TodayViewController}.swift`, `Features/FeatureToday/Sources/Cells/*`, `Core/CoreUI/Sources/{TeamBadgeView,SectionHeaderView}.swift`; Modify `Palette.swift` при необходимости.

**Interfaces — Consumes:** `TodayViewModel`, `TodayState` (Task 3). **Produces:**
```swift
public enum FeatureToday {
    public struct Dependencies { public init(matches: MatchesRepository, bookmarks: BookmarksStore) }
    public struct Output { public init(openMatch: @escaping (MatchID, String) -> Void) }
    @MainActor public static func make(dependencies: Dependencies, output: Output) -> UIViewController
}
public final class TeamBadgeView: UIView   // кружок 28 pt, Palette.surfaceHigh, аббревиатура SF 13 semibold
public final class SectionHeaderView: UICollectionReusableView  // заголовок SF 15 semibold, капс, textSecondary, трекинг; trailing справа SF 15 textSecondary
```
- Один `UICollectionView` с compositional layout: шапка (логотип + заголовок) → полоса дней (горизонтальная секция, `orthogonalScrollingBehavior = .continuous`) → «Мои события» → секции турниров (строки внутри карточки `Palette.surface` со скруглением, разделители между строками) → состояние пусто/ошибка/загрузка. Pull-to-refresh — `UIRefreshControl`.
- Навигационная панель скрыта на этом экране (заголовок рисуется в контенте).
- Кнопка закладки — иконка Lucide `bookmark` (SVG по образцу D19 в `Assets` фичи или CoreUI), заполненная для активной.
- Убрать прежний `makeRoot()` у `FeatureToday`.

- [ ] **Step 1:** Вёрстка по макету; размеры — замером PNG (`docs/design/1 · Сегодня.png`), шрифты/цвета из `Typography`/`Palette`.
- [ ] **Step 2:** Временный прогон в симуляторе с фейковыми данными, повторяющими макет (Ливерпуль 2:1 Арсенал LIVE в «Мои события»; ЛЧ: Реал Мадрид — Бавария 22:00, Интер — ПСЖ 22:00; НХЛ «ночь на чт»), скриншот и сравнение с макетом по замерам (отклонение ≤ 2 pt по ключевым элементам: шапка, чипы, карточка событий, строки ЛЧ). Фейки — только в отладочном превью/тестах, не в релизной сборке.
- [ ] **Step 3:** Сборка без предупреждений Swift 6 в новых файлах.
- [ ] **Step 4:** Коммит `«Сегодня»: вёрстка по макету`.

### Task 5: Сборка приложения и проверка на реальных данных

**Files:** Create `Tribuna/Sources/{AppConfig,AppDependencies}.swift`; Modify `Tribuna/Sources/SceneDelegate.swift`, `Features/FeatureMatch/Sources/FeatureMatch.swift`, `docs/decisions.md`, `README.md`.

**Interfaces — Consumes:** `Services.make` (Task 2), `FeatureToday.make` (Task 4). **Produces:** `FeatureMatch.make(title: String) -> UIViewController` (заглушка: `PlaceholderViewController(title:)`).

- [ ] **Step 1:** `AppConfig` (URL и publishable-ключ из Global Constraints), `AppDependencies` (создаёт `Services.make` один раз), вкладка «Сегодня» через `FeatureToday.make`; `openMatch` пушит `FeatureMatch.make(title:)` в навигационный стек вкладки «Сегодня».
- [ ] **Step 2:** `docs/decisions.md`: D21 — паттерн экрана (MVVM + `@Published state` + Output-замыкания, координатор только при нескольких экранах в фиче), модули `CoreDomain`/`CoreServices`, закладки локальные, publishable-ключ в коде. README — структура модулей.
- [ ] **Step 3:** Сборка, запуск в симуляторе на реальном `tribuna_db`: видны секции включённых турниров за сегодня/завтра, НХЛ, переключение дней, закладка → карточка в «Мои события», закладка переживает перезапуск приложения, тап по матчу → заглушка с названием. Скриншоты в отчёт.
- [ ] **Step 4:** Полный прогон тестов `CoreServicesTests` и `FeatureTodayTests` — PASS.
- [ ] **Step 5:** Коммит `Каркас: сборка приложения и «Сегодня» на реальных данных`.
- [ ] **Step 6 (пользователь):** `supabase db push` — применить `20261119130000_competitions_ru.sql` на `tribuna_db` (русские названия турниров).
