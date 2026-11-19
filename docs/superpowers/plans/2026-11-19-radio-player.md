# Эфир и плеер — план реализации

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Каталог станций в Supabase, движок воспроизведения `CorePlayback`, экран «Эфир», мини-плеер над таб-баром и полноэкранный плеер радио.

**Architecture:** По D5/D15/D21. Протоколы в `CoreDomain`, реализации в `CoreRepositories`/`CorePlayback`, экраны `FeatureRadio`/`FeaturePlayer`, сборка в приложении.

**Tech Stack:** Swift 6, UIKit, iOS 16, SnapKit, AVFoundation, MediaPlayer, PostgREST, Supabase migrations, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-11-19-radio-player-design.md`

## Global Constraints

- Всё из D3–D6, D11, D12, D15, D17–D22 (паттерн экрана, модули, Palette/Typography, иконки Lucide в ассетах, замеры PNG 780 px = 390 pt, обработка возврата из фона).
- Тесты: `./generate && xcodebuild test -workspace Tribuna.xcworkspace -scheme <Модуль> -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=26.0.1' -derivedDataPath /private/tmp/claude-502/tribuna-dd`.
- Supabase: только `tribuna_db`; миграции файлами в `supabase/migrations/`, на удалённый проект применяет пользователь (`supabase db push`).
- Один `AudioPlayer` на приложение. Фоновое аудио: `UIBackgroundModes = [audio]`.
- Волна декоративная, анимируется только при `playing`. Трек (ICY) не показываем.
- Комментарии/документация на русском; коммиты на русском с `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **Поток не отвечает / обрывается** — состояние `failed`, мини-плеер показывает ошибку, play повторяет; звук и UI не расходятся.
2. **Звонок / Siri / другое приложение забрало звук** — пауза; после прерывания с `shouldResume` — продолжение.
3. **Отключили наушники** — пауза (как в системных плеерах).
4. **Таймер сна при свёрнутом приложении** — останавливает воспроизведение в фоне.
5. **Мини-плеер перекрывает контент** — вкладки получают отступ, последний элемент списка доступен.

---

### Task 1: Каталог станций — бэкенд и репозиторий
**Files:** `supabase/migrations/<время>_stations.sql` (таблица, RLS, начальные данные), `Core/CoreDomain/Sources/` (`Station`, `StationsRepository`), `Core/CoreRepositories/Sources/` (`SupabaseStationsRepository`, `Services.make` + `stations`), тесты.
**Interfaces:** `Station(id, name, streamURL, country, bitrate, genres: Set<StationGenre>, subtitle, featuredOrder: Int?)`; `enum StationGenre: String { sport, football, hockey, news }`; `StationsRepository.stations() async throws -> [Station]` (только enabled, по `featured_order` затем имени).
- [ ] Отобрать 8–15 живых станций из Radio Browser (спорт/футбол/хоккей/новости, приоритет — русскоязычные), проверить каждый поток (HTTP 200, `audio/*`), записать в миграцию с жанрами и подписями; 3–5 в подборке на жанр.
- [ ] `supabase db reset` локально; RLS: anon видит только enabled.
- [ ] Тесты разбора (фикстура ответа), сортировки, отсечения disabled.
- [ ] Коммит `Эфир: каталог станций`.

### Task 2: CorePlayback — движок
**Files:** `Core/CoreDomain/Sources/AudioPlayer.swift` (протокол, `PlaybackState`, `PlaybackStatus`), `Core/CorePlayback/Sources/*`, `Core/CorePlayback/Tests/*`, `Project.swift`.
**Interfaces:** `@MainActor protocol AudioPlayer: AnyObject { var state: PlaybackState { get }; var statePublisher: AnyPublisher<PlaybackState, Never> { get }; func play(_: Station); func togglePlayPause(); func stop(); func setSleepTimer(minutes: Int?) }`; `PlaybackState(item: Station?, status: PlaybackStatus, sleepTimerEndsAt: Date?)`; `enum PlaybackStatus: Equatable { idle, loading, playing, paused, failed(String) }`. Реализация `RadioPlayer` поверх протокола-движка (обёртка AVPlayer) — для тестов фейк.
- [ ] Тесты на фейковом движке и инжектируемых часах: переходы состояний, ошибка, повтор, прерывание (с/без shouldResume), отключение наушников, таймер сна (срабатывает, отменяется, переживает смену станции), Now Playing (заголовок, `isLiveStream`), команды экрана блокировки.
- [ ] Реализация: `AVAudioSession` `.playback`, уведомления о прерываниях и смене маршрута, `MPNowPlayingInfoCenter`, `MPRemoteCommandCenter` (play/pause/toggle), live-поток без длительности.
- [ ] Коммит `Эфир: движок воспроизведения`.

### Task 3: FeatureRadio — экран «Эфир»
**Files:** `Features/FeatureRadio/Sources/*` (`RadioViewModel/State/Formatter`, `RadioViewController`, ячейки, ассеты Lucide `search`, `play`, `pause`), тесты, `Project.swift`.
**Interfaces:** `FeatureRadio.make(dependencies: .init(stations:player:), output: .init(openPlayer:)) -> UIViewController`.
- [ ] Модель (тесты): чип «Спорт» по умолчанию, фильтр по чипу, поиск по названию и жанрам без учёта регистра (при поиске чип игнорируется), «Подборка редакции» по `featuredOrder`, карточка «Сейчас играет» из состояния плеера, «Ничего не нашлось», ошибка загрузки + повтор, возврат из фона.
- [ ] Вёрстка по `3 · Эфир.png` (замеры), волна — декоративная анимация.
- [ ] Коммит `Эфир: экран`.

### Task 4: FeaturePlayer — мини-плеер и плеер, сборка в приложении
**Files:** `Features/FeaturePlayer/Sources/*` (мини-плеер `MiniPlayerView` + модель, `PlayerViewController` + модель, таймер сна — action sheet), тесты, `Tribuna/Sources/*` (один `AudioPlayer`, вкладка «Эфир» через `FeatureRadio.make`, мини-плеер в `MainTabBarController` над таб-баром с отступом вкладкам, лист плеера), `Project.swift` (`UIBackgroundModes`).
**Interfaces:** `FeaturePlayer.makeMiniPlayer(player:onOpen:) -> UIView`, `FeaturePlayer.makePlayer(player:) -> UIViewController`.
- [ ] Модели (тесты): тексты статусов мини-плеера («● В эфире», «Подключение…», «Не удалось подключиться»), видимость, подпись «Россия · 128 кбит/с», состояние таймера сна («Сон через 25 мин»).
- [ ] Вёрстка мини-плеера по «Сегодня»/«Подкасты» и плеера по `5 · Плеер.png` (без перемотки/скорости/«Скачан»/«Поделиться»).
- [ ] Отступ вкладкам при показанном мини-плеере (Review Focus 5).
- [ ] Коммит `Эфир: мини-плеер и плеер`.

### Task 5: Проверка на реальных данных и документация
- [ ] Пользователь: `supabase db push` (каталог станций).
- [ ] Симулятор: «Эфир» с реальным каталогом, станция играет (`playing`), мини-плеер на всех вкладках, плеер, пауза/продолжение, таймер сна, ошибка на заведомо мёртвом потоке (DEBUG). Скриншоты.
- [ ] `docs/decisions.md`: D23 — каталог (подход A, права — вопрос релиза), `CorePlayback` и контракт `AudioPlayer`, мини-плеер в контейнере вкладок, поведение при прерываниях/наушниках, волна декоративная, ICY не показываем.
- [ ] Коммит `Эфир: проверка и D23`.
