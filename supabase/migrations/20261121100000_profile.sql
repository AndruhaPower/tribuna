-- Данные профиля (D31): закладки, подписки, позиции прослушивания. Каждый видит и меняет только свои строки,
-- anon — ничего. Удаление пользователя (Edge Function delete-account) уносит строки каскадом.
-- match_id — MatchID.rawValue («football:12345»), podcast_id — id каталога podcasts, episode_id — EpisodeID.rawValue
-- («<id подкаста>:<guid>»); внешних ключей на матчи и выпуски нет: НХЛ и выпусков на сервере нет.

create table bookmarks (
  user_id uuid not null references auth.users on delete cascade,
  match_id text not null,
  created_at timestamptz not null default now(),
  primary key (user_id, match_id)
);

create table podcast_subscriptions (
  user_id uuid not null references auth.users on delete cascade,
  podcast_id text not null,
  subscribed_at timestamptz not null default now(),
  primary key (user_id, podcast_id)
);

create table listening_progress (
  user_id uuid not null references auth.users on delete cascade,
  episode_id text not null,
  position double precision not null default 0,
  is_finished boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (user_id, episode_id)
);

alter table bookmarks enable row level security;
alter table podcast_subscriptions enable row level security;
alter table listening_progress enable row level security;

revoke all on bookmarks, podcast_subscriptions, listening_progress from anon;
grant select, insert, update, delete on bookmarks, podcast_subscriptions, listening_progress to authenticated;

-- (select auth.uid()) — один вызов на запрос, а не на строку.
create policy bookmarks_select on bookmarks for select to authenticated using (user_id = (select auth.uid()));
create policy bookmarks_insert on bookmarks for insert to authenticated with check (user_id = (select auth.uid()));
create policy bookmarks_update on bookmarks for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy bookmarks_delete on bookmarks for delete to authenticated using (user_id = (select auth.uid()));

create policy podcast_subscriptions_select on podcast_subscriptions for select to authenticated using (user_id = (select auth.uid()));
create policy podcast_subscriptions_insert on podcast_subscriptions for insert to authenticated with check (user_id = (select auth.uid()));
create policy podcast_subscriptions_update on podcast_subscriptions for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy podcast_subscriptions_delete on podcast_subscriptions for delete to authenticated using (user_id = (select auth.uid()));

create policy listening_progress_select on listening_progress for select to authenticated using (user_id = (select auth.uid()));
create policy listening_progress_insert on listening_progress for insert to authenticated with check (user_id = (select auth.uid()));
create policy listening_progress_update on listening_progress for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy listening_progress_delete on listening_progress for delete to authenticated using (user_id = (select auth.uid()));
