# Карточка матча — план реализации

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Экран карточки матча по макету `docs/design/2 · Карточка матча.png` вместо заглушки: статус и счёт, закладка, локальное напоминание, таблица турнира.

**Architecture:** По D21. `FeatureMatch` зависит только от `CoreDomain`/`CoreUI`; реализации — в `CoreRepositories`; приложение собирает и пушит карточку по `openMatch`.

**Tech Stack:** Swift 6, UIKit, iOS 16, SnapKit, PostgREST (supabase-swift), UserNotifications, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-11-19-match-card-design.md`

## Global Constraints

- Всё из D3–D6, D11, D12, D17–D21 (паттерн экрана, модули, цвета/шрифты только через `Palette`/`Typography`, иконки — геометрия Lucide в ассетах, замеры по PNG 780 px = 390 pt).
- Тесты: `./generate && xcodebuild test -workspace Tribuna.xcworkspace -scheme <Модуль> -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=26.0.1' -derivedDataPath /private/tmp/claude-502/tribuna-dd`.
- Напоминание: за 15 минут до `kickoff`, локальное; только для `.scheduled` матча со стартом позже чем через 15 минут. Идентификатор уведомления = `MatchID.rawValue`.
- Подпись «Счёт обновляется с небольшой задержкой» — только футбол.
- Таблица — только футбол, основная таблица турнира (`stage`/`group_name` с наибольшим числом строк), строки обеих команд матча подсвечены (`Palette` по макету).
- Обновление: при открытии, при `willEnterForeground`, раз в 60 с пока `live`/`paused`; без параллельных запросов.
- «Слушать под матч» скрыт. «Поделиться» — текст `«<Хозяева> — <Гости>, <счёт или время> · <Турнир>, <тур>»`.
- Комментарии и документация на русском; коммиты на русском с `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **Закладка/напоминание меняются в другом месте** (на «Сегодня») — карточка отражает это без перезагрузки (подписка на паблишеры).
2. **Отказ в уведомлениях** — кнопка не залипает во «включено», пользователь видит сообщение со ссылкой в Настройки.
3. **Матч перенесён после установки напоминания** — при запуске приложения напоминания пересверяются: время поправлено или напоминание снято для начавшегося/отменённого/перенесённого.
4. **Команды матча нет в таблице** (кубок, плей-офф) — таблица без подсветки, не падает; таблицы нет вовсе — блок скрыт.
5. **Матч не найден** (`match(id:)` → nil) — экран ошибки «Матч не найден», без падения.

---

### Task 1: Данные — матч по id, таблица, напоминания

**Files:** `Core/CoreDomain/Sources/*` (протоколы и модели), `Core/CoreRepositories/Sources/*`, `Core/CoreRepositories/Tests/*`.

**Interfaces — Produces:**
```swift
// CoreDomain
public struct StandingRow: Sendable, Equatable { public let position: Int; public let team: Team; public let teamID: String; public let played: Int; public let points: Int }
public protocol StandingsRepository: Sendable { func standings(competitionCode: String) async throws -> [StandingRow] }
// MatchesRepository дополняется: func match(id: MatchID) async throws -> Match?
// Match дополняется: public let homeTeamID: String?; public let awayTeamID: String?   (для подсветки строк таблицы)
@MainActor public protocol RemindersStore: AnyObject {
    var scheduled: Set<MatchID> { get }
    var scheduledPublisher: AnyPublisher<Set<MatchID>, Never> { get }
    func schedule(_ match: Match) async throws -> ReminderResult   // .scheduled | .denied | .tooLate
    func cancel(_ id: MatchID)
    func reconcile(with matches: [Match])                          // пересверка после загрузки
}
// CoreRepositories: Services.make(...) возвращает также standings: StandingsRepository, reminders: RemindersStore
```
- Футбол: `match(id:)` — тот же select, что для дня, с фильтром по `id`; `standings` — `standings` + `teams` по `competitions.code`, основная таблица (stage/group с макс. числом строк), по `position`.
- НХЛ: `match(id:)` — `GET https://api-web.nhle.com/v1/gamecenter/{id}/landing`, тот же маппинг статусов (с `gameScheduleState`).
- Напоминания: обёртка над `UNUserNotificationCenter` через протокол-центр для тестов; заголовок «Скоро матч», текст «<Хозяева> — <Гости> через 15 минут».
- [ ] Тесты (RED → GREEN): разбор таблицы (фикстура ответа PostgREST, выбор основной таблицы, сортировка); `match(id:)` футбол (фикстура) и НХЛ (фикстура landing — снять одним read-only запросом к API и сохранить); напоминания на фейковом центре: schedule → запрос с триггером kickoff−15 мин; отказ → `.denied`, `scheduled` не меняется; матч через 10 минут → `.tooLate`; `reconcile` переносит время и снимает для `.live`/`.cancelled`/`.postponed`.
- [ ] Коммит `Карточка матча: данные — матч, таблица, напоминания`.

### Task 2: FeatureMatch — модель экрана

**Files:** `Features/FeatureMatch/Sources/{MatchViewModel,MatchState,MatchFormatter}.swift`, `Features/FeatureMatch/Tests/*`, `Project.swift` (FeatureMatch → CoreDomain, тестовый таргет).

**Interfaces — Produces:** `MatchState` (header «АПЛ · 12 тур», status (текст + isLive), home/away (name, abbreviation), score «2 : 1» или пусто, showsDelayNote, isBookmarked, reminder: `.hidden | .off | .on`, standings: `[Row(position, name, played, points, isHighlighted)]`, content `.loading/.loaded/.notFound/.error`, shareText); `MatchViewModel(matchID:, matches:, standings:, bookmarks:, reminders:, now:, calendar:)` с методами `viewDidAppear/Disappear`, `didEnterForeground`, `didToggleBookmark`, `didTapRemind` (async, отдаёт результат для алерта), `didTapRetry`.
- [ ] Тесты: статусы и счёт; подпись задержки только футбол; подсветка двух строк; команды нет в таблице → без подсветки; таблицы нет → `standings == []`; `match == nil` → `.notFound`; напоминание скрыто для live/finished/cancelled/postponed и при старте < 15 мин; `.denied` → reminder `.off` и сигнал алерта; закладка/напоминание меняются из паблишеров без запроса; автообновление только live и при видимом экране, без параллельных запросов; shareText.
- [ ] Коммит `Карточка матча: модель экрана`.

### Task 3: FeatureMatch — вёрстка и сборка в приложении

**Files:** `Features/FeatureMatch/Sources/{FeatureMatch,MatchViewController}.swift` + ячейки, ассеты (Lucide `share`, `bell`, `bookmark`), `Tribuna/Sources/{AppDependencies,SceneDelegate}.swift`.

**Interfaces — Produces:** `FeatureMatch.make(dependencies: .init(matches:standings:bookmarks:reminders:), output: .init(openSettings:), matchID:) -> UIViewController`; заглушка `make(title:)` удаляется; `FeatureToday.Output.openMatch` передаёт только `MatchID` (поправить `FeatureToday`, его тесты и приложение).
- [ ] Вёрстка по замерам PNG (шапка, блок матча, кнопки, таблица с чередованием строк и подсветкой); алерт при отказе с кнопкой «Настройки» (`UIApplication.openSettingsURLString` через Output); `UIActivityViewController` для «Поделиться».
- [ ] Приложение: при старте и при `willEnterForeground` — `reminders.reconcile` с матчами из закладок/напоминаний (загрузить их через `match(id:)`).
- [ ] Сверка с макетом на DEBUG-данных (как `-TodayMockData`), отклонение ≤ 2 pt по ключевым блокам; тесты FeatureToday/FeatureMatch/CoreRepositories зелёные.
- [ ] Коммит `Карточка матча: вёрстка и сборка в приложении`.

### Task 4: Проверка на реальных данных и документация

- [ ] Симулятор, реальный `tribuna_db`: карточка футбольного матча (таблица, подсветка), карточка НХЛ (без таблицы), закладка синхронна с «Сегодня», «Напомнить» → системный запрос разрешения → уведомление запланировано (`UNUserNotificationCenter` pending), «Поделиться». Скриншоты в отчёт.
- [ ] `docs/decisions.md`: D22 — напоминания локальные (почему, пересверка при запуске, серверные пуши — со входом), карточка НХЛ без таблицы, «Слушать под матч» скрыт; README при необходимости.
- [ ] Коммит `Карточка матча: проверка на реальных данных и D22`.
