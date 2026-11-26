# Бэкенд Tribuna (Supabase)

Бэкенд приложения: PostgreSQL с миграциями, pg_cron → Edge Function `sync-football`
(синхронизация football-data.org раз в минуту), Edge Function `delete-account`
(удаление аккаунта, App Review 5.1.1), Auth (email + Sign in with Apple — на паузе, D35).

Проект: `tribuna_db`, ref `wgwsdhyrazjzqwvnhgzk`. В том же аккаунте Supabase есть чужие
проекты (`swap-dev`, `trading-bot`) — их не трогаем.

## Структура

```
config.toml    конфиг проекта (Auth, email-шаблоны через env)
migrations/    миграции БД (применяются `supabase db push` по порядку имён)
functions/     edge-функции: sync-football, delete-account (Deno, тесты — *_test.ts)
snippets/      вспомогательные SQL-сниппеты
```

## Разворачивание с нуля

Предусловия: [Supabase CLI](https://supabase.com/docs/guides/cli) (`brew install supabase/tap/supabase`),
аккаунт supabase.com с доступом к проекту.

```bash
supabase login
supabase link --project-ref wgwsdhyrazjzqwvnhgzk
supabase db push                                  # миграции
supabase functions deploy sync-football
supabase functions deploy delete-account
```

## Секреты

**Edge-функции** (`supabase secrets set ...`, Dashboard → Edge Functions → Secrets):

| Секрет | Зачем |
|---|---|
| `FOOTBALL_DATA_KEY` | ключ football-data.org; только бэкенд, в приложение не попадает (README корня) |
| `SYNC_SECRET` | подпись вызовов sync-football от pg_cron (заголовок `x-sync-secret`) |

`SUPABASE_URL` / `SUPABASE_ANON_KEY` / `SUPABASE_SERVICE_ROLE_KEY` функции получают автоматически.

**Vault** (Dashboard → Database → Vault, вручную — в миграциях их нет, см.
`20261119120100_football_cron.sql`): `project_url` (https://wgwsdhyrazjzqwvnhgzk.supabase.co)
и `sync_secret` (то же значение, что `SYNC_SECRET`) — pg_cron вызывает функцию по HTTP.

**Auth / OAuth** (через env-подстановку в `config.toml`, в git секреты не коммитим):
`SUPABASE_AUTH_EXTERNAL_APPLE_SECRET` — секрет Sign in with Apple, понадобится после снятия
паузы (D35).

## Auth

- Email + пароль, подтверждение почты включено; шаблоны писем — по
  `docs/supabase-email-templates.md`.
- Провайдер Apple: Dashboard → Authentication → Providers → Apple, Client ID = `com.tribuna.app`
  — включается после добавления entitlement (D33/D35, сейчас на паузе).

## Проверка

```bash
supabase functions serve sync-football   # локально, нужен .env с секретами
deno test supabase/functions/            # тесты функций (или через задачи редактора)
```

После `db push`: в таблицах `matches`/`standings` данные появятся в течение минуты
(pg_cron), каталоги `podcasts`/`stations` — сразу из seed-миграций.
