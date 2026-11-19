# Tribuna

Спорт, который слушают. iOS-приложение, в котором болельщик следит за счётом своих команд и тут же слушает спортивное радио и подкасты, не переключаясь между сервисами.

Рынок: Россия и СНГ. Платформа: iOS. Цель: публикация в App Store.

## Возможности MVP

| Раздел | Что делает пользователь |
|---|---|
| Сегодня | Видит матчи футбола (топ-лиги Европы, ЛЧ) и НХЛ по дням: счёт, статус, таблицы |
| Закладки | Сохраняет матчи и получает напоминание за 15 минут до начала |
| Эфир | Слушает спортивное радио в фоне и на экране блокировки |
| Подкасты | Подписывается, скачивает выпуски, слушает офлайн |
| Профиль | Входит через Apple; без входа приложение тоже работает |

Возможности iOS: фоновое аудио и загрузки, пуши, Sign in with Apple, iCloud KVS, Universal Links, Mindbox.

## Источники данных

| API | Что берём | Доступ |
|---|---|---|
| [football-data.org](https://www.football-data.org) | Матчи, счёт, таблицы: 12 турниров, включая АПЛ и ЛЧ | Бесплатный ключ, ~10 запросов/мин |
| NHL Web API | Хоккей: живой счёт, период, таблица | Без ключа |
| [Radio Browser](https://www.radio-browser.info) | Каталог радиостанций, потоки | Без ключа |
| iTunes Search + RSS | Русские подкасты, выпуски, mp3 | Без ключа |
| Supabase (`tribuna_db`) + Mindbox | Профили, закладки, пуши через APNs, рассылки | Свой бэкенд |

Ограничения: футбольный счёт приходит с задержкой, названия команд переводим сами, российских спортивных радиостанций в каталоге мало.

Ключ football-data.org не должен попадать в приложение: лимит общий на ключ, поэтому футбольные данные отдаёт бэкенд.

## Быстрый старт

Нужны Xcode 26 и [mise](https://mise.jdx.dev). Tuist ставится сам, версия закреплена в `mise.toml`.

```bash
./generate
open Tribuna.xcworkspace
```

`.xcodeproj` и `.xcworkspace` генерируются и в git не хранятся.

## Структура репозитория

```
Tribuna/                Приложение: AppDelegate, SceneDelegate, таб-бар
Features/Feature<Имя>/  Модуль на каждую фичу
Core/Core<Имя>/         Общий код
supabase/               Бэкенд: миграции и Edge Function sync-football
Project.swift           Манифест Tuist (все модули)
Tuist/Package.swift     Внешние зависимости (SnapKit)
generate                Генерация проекта
docs/decisions.md       Журнал решений и грабли — читать перед работой
docs/design/            Макеты MVP (PNG, @2x)
TRIBUNA.pdf             Концепт MVP
tribuna_api_check.py    Проверка бесплатных API
tribuna_api_report/     Результат проверки от 18.11.2026
```

## Бэкенд

Каждую минуту pg_cron (задание `sync-football`) через pg_net вызывает Edge Function `sync-football`. Функция ходит в football-data.org и обновляет таблицы `competitions`, `teams`, `matches`, `standings`; состояние последнего запуска лежит в `sync_state`. Ручные поля (`teams.name_ru`, `competitions.enabled`) синк не перезаписывает.

Тесты функции:

```bash
deno test supabase/functions/sync-football --allow-read --allow-env
```

Локальный стек (нужен Docker-совместимый рантайм):

```bash
supabase start
supabase db reset   # применяет миграции из supabase/migrations
```

Локально секретов в Vault нет, поэтому задание запускается, но вызов функции падает. Это нормально.

Локальная проверка функции (до настройки удалённого проекта). Файл с фиктивными значениями держать вне репозитория:

```bash
# /path/to/dummy.env: FOOTBALL_DATA_KEY=dummy, SYNC_SECRET=dummy-secret,
#   SUPABASE_URL=http://127.0.0.1:54321, SUPABASE_SERVICE_ROLE_KEY=<ключ из supabase status>
supabase functions serve sync-football --no-verify-jwt --env-file /path/to/dummy.env
curl -i -X POST http://127.0.0.1:54321/functions/v1/sync-football                                  # 401
curl -i -X POST http://127.0.0.1:54321/functions/v1/sync-football -H 'x-sync-secret: dummy-secret'  # 200
```

### Разовая настройка удалённого проекта

Делает владелец проекта, ключи в репозиторий не попадают.

```bash
supabase login
supabase link --project-ref wgwsdhyrazjzqwvnhgzk
supabase secrets set FOOTBALL_DATA_KEY=<ключ football-data.org> SYNC_SECRET=<случайная строка>
```

В SQL-редакторе проекта создать секреты Vault (`sync_secret` равен `SYNC_SECRET`):

```sql
select vault.create_secret('https://wgwsdhyrazjzqwvnhgzk.supabase.co', 'project_url');
select vault.create_secret('<тот же SYNC_SECRET>', 'sync_secret');
```

Затем сначала функция (флаг нужен, потому что вызов идёт с `x-sync-secret`, а не с JWT), потом миграции, чтобы cron не бил в ещё не задеплоенную функцию:

```bash
supabase functions deploy sync-football --no-verify-jwt
supabase db push
```

Ротация секрета: обновить `SYNC_SECRET` через `supabase secrets set` и в Vault `select vault.update_secret((select id from vault.secrets where name = 'sync_secret'), '<новое значение>');`.

### Проверка

Через пару минут после деплоя:

```sql
select * from sync_state;
select status_code from net._http_response order by created desc limit 3;  -- 200
```

## Проверка API

```bash
python3 tribuna_api_check.py
```

Ключ football-data.org спрашивается при запуске или берётся из `FD_KEY`. Он нигде не сохраняется. Отчёт пишется в `tribuna_api_report/`.

## Архитектура

UIKit + SnapKit, iOS 16+, Swift 6, Tuist, модуль на каждую фичу. Подробности и причины — в [docs/decisions.md](docs/decisions.md).
