# Бэкенд футбола — план реализации

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Supabase-проект `tribuna_db` сам раз в минуту забирает матчи и таблицы из football-data.org, приложение читает их только на чтение.

**Architecture:** pg_cron → `net.http_post` → Edge Function `sync-football` (Deno). Функция решает, что запрашивать (`plan.ts`), разбирает ответы (`mapping.ts`) и пишет через service role. Таблицы закрыты RLS: клиенту только `SELECT`.

**Tech Stack:** Supabase (Postgres 17, pg_cron, pg_net, Vault, Edge Functions), Deno + TypeScript, `@supabase/supabase-js@2`, Supabase CLI 2.117.

**Spec:** `docs/superpowers/specs/2026-11-19-football-backend-design.md`

## Global Constraints

- Проект Supabase — только `tribuna_db` (ref `wgwsdhyrazjzqwvnhgzk`). `swap-dev` и `trading-bot` в том же аккаунте не трогать.
- Ключ football-data.org — секрет `FOOTBALL_DATA_KEY`, задаёт пользователь сам; в git и в логи не попадает.
- Функция вызывается только с заголовком `x-sync-secret` = секрет `SYNC_SECRET`; без него — 401. `verify_jwt = false`.
- Не больше 3 запросов к football-data.org за запуск: 1 на матчи, до 2 на таблицы.
- Окно матчей: `dateFrom` = вчера (UTC), `dateTo` = сегодня + 7 дней (UTC).
- Матчи — каждый запуск, если есть live или старт в ближайшие 15 минут; иначе раз в 15 минут.
- Таблицы — сначала турниры с матчем, закончившимся после `standings_updated_at`; иначе самая старая старше 6 часов; не больше 2 за запуск.
- Включённые турниры по умолчанию: PL, PD, BL1, SA, FL1, CL. Выключенные: BSA, ELC, EC, DED, PPL, CLI, WC.
- Синхронизация никогда не перезаписывает `enabled`, `name_ru`, `short_name_ru`.
- Документация и комментарии — на русском.

## Review Focus

1. **Ручные поля затираются синком** — upsert `teams`/`competitions` не должен трогать `name_ru`, `short_name_ru`, `enabled`. Проверка в Task 5, шаг 6.
2. **Обрыв на середине (429, сеть)** — таблица турнира не должна остаться пустой или наполовину заменённой. Замена атомарна через `replace_standings`; проверка в Task 1, шаг 4.
3. **Перенесённые и отменённые матчи** (`POSTPONED`, `CANCELLED`, `SUSPENDED`) не считаются live и не держат частый режим. Тест в Task 3.
4. **Нет включённых турниров** — запрос матчей не уходит вообще (иначе API вернёт все турниры). Тест в Task 3.
5. **У команды нет `tla` или `shortName`** (бывает в кубках) — разбор не падает, берёт `name`. Тест в Task 2.

---

## Структура файлов

```
supabase/
  config.toml                                     supabase init + [functions.sync-football] verify_jwt = false
  migrations/20261119120000_football.sql          таблицы, RLS, индексы, replace_standings, начальные турниры
  migrations/20261119120100_football_cron.sql     pg_cron, pg_net, задание sync-football
  functions/sync-football/
    types.ts       типы ответов football-data и строк таблиц
    mapping.ts     JSON → строки
    mapping_test.ts
    plan.ts        что запрашивать в этом запуске
    plan_test.ts
    index.ts       HTTP-обработчик
    index_test.ts
docs/decisions.md                                 D20
```

---

### Task 1: Схема базы

**Files:**
- Create: `supabase/config.toml` (через `supabase init`), `supabase/migrations/20261119120000_football.sql`
- Modify: `docs/decisions.md` (D20 — бэкенд футбола, ссылка на спек; грабли про `swap-dev`)

**Interfaces:**
- Produces: таблицы
  - `competitions(id int pk, code text unique not null, name text not null, name_ru text, emblem_url text, enabled bool not null default false, standings_updated_at timestamptz)`
  - `teams(id int pk, name text not null, short_name text, tla text, crest_url text, name_ru text, short_name_ru text, updated_at timestamptz not null default now())`
  - `matches(id int pk, competition_id int not null → competitions, utc_date timestamptz not null, status text not null, matchday int, stage text, group_name text, home_team_id int → teams, away_team_id int → teams, home_score int, away_score int, winner text, source_updated_at timestamptz, synced_at timestamptz not null default now())`, индексы `(utc_date)`, `(competition_id, utc_date)`
  - `standings(competition_id int → competitions, stage text, group_name text not null default '', position int not null, team_id int → teams, played int, won int, draw int, lost int, goals_for int, goals_against int, goal_difference int, points int, form text, pk (competition_id, stage, group_name, team_id))`
  - `sync_state(key text pk, value jsonb not null, updated_at timestamptz not null default now())`
  - `replace_standings(p_competition_id int, p_rows jsonb) returns void` — `security definer`, в одной транзакции удаляет строки турнира, вставляет `jsonb_to_recordset(p_rows)`, ставит `competitions.standings_updated_at = now()`. `execute` только у `service_role`.
  - Начальные строки `competitions` (id, code, name, enabled): 2021 PL, 2014 PD, 2002 BL1, 2019 SA, 2015 FL1, 2001 CL — `true`; 2013 BSA, 2016 ELC, 2018 EC, 2003 DED, 2017 PPL, 2152 CLI, 2000 WC — `false`.
  - RLS включён на всех пяти таблицах; политики `select` для `anon, authenticated` на `competitions, teams, matches, standings`; на `sync_state` политик нет.

- [ ] **Step 1:** Запустить Docker Desktop (`open -a Docker`), `supabase init` в корне репозитория, в `config.toml` добавить `[functions.sync-football]` с `verify_jwt = false`.
- [ ] **Step 2:** Написать миграцию по интерфейсу выше.
- [ ] **Step 3:** `supabase start && supabase db reset` — Expected: миграция применяется без ошибок.
- [ ] **Step 4: Проверка RLS и атомарности** через `psql "$(supabase status -o env | grep DB_URL | cut -d= -f2- | tr -d '"')"`:
  - `set role anon; select count(*) from competitions;` → 13
  - `set role anon; insert into teams(id,name) values (1,'x');` → ошибка RLS
  - `set role anon; select * from sync_state;` → 0 строк
  - `set role anon; select replace_standings(2021,'[]');` → permission denied
  - `reset role; select replace_standings(2021, '[{"stage":"REGULAR_SEASON","group_name":"","position":1,"team_id":999}]');` → ошибка FK (нет команды 999), и после неё `select count(*) from standings` → 0 (ничего не удалено частично)
- [ ] **Step 5:** Дописать D20 и грабли в `docs/decisions.md`, коммит `Бэкенд футбола: схема базы`.

### Task 2: Разбор ответов football-data

**Files:**
- Create: `supabase/functions/sync-football/types.ts`, `mapping.ts`, `mapping_test.ts`

**Interfaces:**
- Produces (`types.ts`): `CompetitionRow { id; code; name; emblem_url }`, `TeamRow { id; name; short_name; tla; crest_url }`, `MatchRow` (колонки `matches` кроме `synced_at`), `StandingRow` (колонки `standings` кроме `competition_id`).
- Produces (`mapping.ts`):
  - `mapMatches(json: unknown): { competitions: CompetitionRow[]; teams: TeamRow[]; matches: MatchRow[] }` — команды и турниры без дублей.
  - `mapStandings(json: unknown): { competitionId: number; rows: StandingRow[] }` — только таблицы `type === "TOTAL"`; `group_name` = `group ?? ""`.
  - Строки без `*_ru` и без `enabled` — их синк не пишет.

- [ ] **Step 1: Тесты** в `mapping_test.ts` на фикстурах `tribuna_api_report/raw/` (путь через `new URL("../../../tribuna_api_report/raw/…", import.meta.url)`):
  - `mapMatches(fd_matches_week)` → `matches.length === 12`, у первого `id === 555081`, `status === "TIMED"`, `matchday === 35`, `home_score === null`; `competitions` уникальны по `id` и среди них `{ id: 2013, code: "BSA" }`; `teams` уникальны по `id`, есть `{ id: 4241, tla: "COR", short_name: "Coritiba" }`.
  - `mapStandings(fd_standings_PL)` → `competitionId === 2021`, 20 строк, первая `position === 1`, `team_id === 57`, `points === 27`, `played === 10`.
  - `mapStandings(fd_standings_CL)` → `competitionId === 2001`, все строки `stage === "LEAGUE_STAGE"`.
  - Команда без `tla` и `shortName` → `tla === null`, `short_name === "<name>"` (Review Focus 5).
  - Матч с `score.fullTime = {home: 2, away: 1}` → `home_score === 2`, `away_score === 1`.
- [ ] **Step 2:** `deno test supabase/functions/sync-football/mapping_test.ts --allow-read` — Expected: FAIL (нет модуля).
- [ ] **Step 3:** Реализовать `types.ts` и `mapping.ts`.
- [ ] **Step 4:** Тот же запуск — Expected: PASS.
- [ ] **Step 5:** Коммит `Бэкенд футбола: разбор ответов football-data`.

### Task 3: План запуска

**Files:**
- Create: `supabase/functions/sync-football/plan.ts`, `plan_test.ts`

**Interfaces:**
- Produces:
  - `isLiveOrSoon(matches: { status: string; utc_date: string }[], now: Date): boolean` — true, если есть `IN_PLAY` или `PAUSED`, либо `TIMED`/`SCHEDULED` с `utc_date` в `[now, now + 15 мин]`.
  - `type CompetitionState = { code: string; standingsUpdatedAt: Date | null; lastFinishedAt: Date | null }`
  - `planRun(now: Date, s: { enabledCodes: string[]; lastMatchesFetchAt: Date | null; liveOrSoon: boolean; competitions: CompetitionState[] }): { fetchMatches: boolean; standingsCodes: string[] }`

- [ ] **Step 1: Тесты** в `plan_test.ts` (`now = 2026-11-19T20:00:00Z`):
  - `isLiveOrSoon`: `IN_PLAY` → true; `PAUSED` → true; `TIMED` в 20:10 → true; `TIMED` в 20:20 → false; `POSTPONED`/`CANCELLED`/`SUSPENDED` в 20:05 → false; `FINISHED` в 19:00 → false.
  - `fetchMatches`: `lastMatchesFetchAt = null` → true; live + 30 с назад → true; не live + 14 мин назад → false; не live + 15 мин назад → true; `enabledCodes = []` → false при любых остальных.
  - `standingsCodes`: PL с `lastFinishedAt` 19:50 и `standingsUpdatedAt` 19:00 → первым `PL`; три турнира с `standingsUpdatedAt = null` → ровно 2 кода; все обновлены 1 час назад, ничего не закончилось → `[]`; один обновлён 7 часов назад → `[его код]`; коды только из `enabledCodes`.
- [ ] **Step 2:** `deno test supabase/functions/sync-football/plan_test.ts` — Expected: FAIL.
- [ ] **Step 3:** Реализовать `plan.ts`. Порядок таблиц: сначала «закончился матч после обновления» (по возрастанию `standingsUpdatedAt`, `null` первым), потом «старше 6 часов» (так же), без повторов, `slice(0, 2)`.
- [ ] **Step 4:** Тот же запуск — Expected: PASS.
- [ ] **Step 5:** Коммит `Бэкенд футбола: план запуска синхронизации`.

### Task 4: Edge Function

**Files:**
- Create: `supabase/functions/sync-football/index.ts`, `index_test.ts`

**Interfaces:**
- Consumes: `mapMatches`, `mapStandings` (Task 2), `isLiveOrSoon`, `planRun` (Task 3), `replace_standings` (Task 1).
- Produces: `export async function handle(req: Request, deps: { env: (k: string) => string | undefined; fetch: typeof fetch; db: SupabaseClient }): Promise<Response>`; `Deno.serve` вызывает `handle` с реальными зависимостями.
  - Ответ 200: JSON `{ fetchedMatches: boolean; standings: string[]; error?: string }`.
  - Пишет в `sync_state`: ключ `matches` → `{ fetchedAt }`, ключ `last_run` → `{ at, fetchedMatches, standings, error }`.

- [ ] **Step 1: Тесты** в `index_test.ts` с подменёнными `fetch` и `db`:
  - без заголовка `x-sync-secret` → 401, `fetch` не вызывался;
  - неверный секрет → 401;
  - нет `FOOTBALL_DATA_KEY` → 500 с текстом без значения секрета;
  - football-data ответил 429 на матчи → 200, `error` содержит `429`, `replace_standings` не вызывался.
- [ ] **Step 2:** `deno test supabase/functions/sync-football/index_test.ts --allow-env` — Expected: FAIL.
- [ ] **Step 3:** Реализовать `index.ts`. Порядок: проверка секрета → читаем включённые турниры, `sync_state.matches`, матчи окна (для `isLiveOrSoon`), последний `FINISHED` по турнирам → `planRun` → запрос матчей (`/v4/matches?competitions=<codes>&dateFrom&dateTo`, заголовок `X-Auth-Token`) → upsert `competitions` (только `id, code, name, emblem_url`), `teams` (только синк-колонки), `matches` → таблицы через `/v4/competitions/{code}/standings` и `rpc("replace_standings")` → запись `sync_state`. На 429/сетевой ошибке — прекратить запросы, записать `error`, вернуть 200. Ключ не логировать.
- [ ] **Step 4:** Тот же запуск — Expected: PASS. Плюс `deno check supabase/functions/sync-football/index.ts` — без ошибок.
- [ ] **Step 5:** Коммит `Бэкенд футбола: Edge Function sync-football`.

### Task 5: Расписание и запуск на tribuna_db

**Files:**
- Create: `supabase/migrations/20261119120100_football_cron.sql`
- Modify: `README.md` (раздел «Бэкенд»: секреты, деплой, ручной запуск)

**Interfaces:**
- Consumes: функция из Task 4; секреты Vault `project_url`, `sync_secret`.
- Produces: задание pg_cron `sync-football`, `* * * * *`, вызывает `net.http_post(url := <project_url>/functions/v1/sync-football, headers := {"Content-Type": "application/json", "x-sync-secret": <sync_secret>})`; значения читаются из `vault.decrypted_secrets` в момент запуска.

- [ ] **Step 1:** Написать миграцию: `create extension if not exists pg_cron; create extension if not exists pg_net;`, `cron.schedule('sync-football', '* * * * *', $$ … $$)`. Секреты в Vault миграция не создаёт.
- [ ] **Step 2:** `supabase db reset` локально — Expected: без ошибок, `select jobname, schedule from cron.job` → `sync-football | * * * * *`.
- [ ] **Step 3: Пользователь** (я не ввожу ключи): `supabase login`, `supabase link --project-ref wgwsdhyrazjzqwvnhgzk`, `supabase secrets set FOOTBALL_DATA_KEY=… SYNC_SECRET=…`, в SQL-редакторе `select vault.create_secret('https://wgwsdhyrazjzqwvnhgzk.supabase.co','project_url'); select vault.create_secret('<тот же SYNC_SECRET>','sync_secret');`.
- [ ] **Step 4:** `supabase db push` и `supabase functions deploy sync-football` — Expected: обе миграции применены, функция задеплоена.
- [ ] **Step 5:** Подождать 2 минуты. Expected: `select count(*) from matches` > 0; `select value from sync_state where key='last_run'` без `error`; `select status_code from net._http_response order by created desc limit 3` → 200.
- [ ] **Step 6: Ручные поля** (Review Focus 1): `update teams set name_ru='Арсенал' where id=57; update competitions set enabled=false where code='FL1';` → дождаться запуска → `name_ru` остался `'Арсенал'`, `enabled` остался `false`; затем `update competitions set enabled=true where code='FL1'`.
- [ ] **Step 7:** Обновить README, коммит `Бэкенд футбола: расписание и деплой`, push.
