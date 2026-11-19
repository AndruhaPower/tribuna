-- Расписание синка футбола: каждую минуту дёргаем Edge Function sync-football.
-- Секреты project_url и sync_secret создаются вручную в Vault (см. README), здесь их нет.
create extension if not exists pg_cron;
create extension if not exists pg_net with schema extensions;

-- cron.schedule с тем же именем обновляет задание, повторный запуск безопасен.
-- Без секретов в Vault url = null и http_post падает только в этом запуске.
select cron.schedule(
  'sync-football',
  '* * * * *',
  $$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url')
           || '/functions/v1/sync-football',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-sync-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'sync_secret')
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 30000
  );
  $$
);
