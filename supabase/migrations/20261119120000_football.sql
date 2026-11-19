-- Футбольные данные: пишет Edge Function sync-football (service_role), клиент только читает.

create table competitions (
  id int primary key,
  code text unique not null,
  name text not null,
  name_ru text,
  emblem_url text,
  enabled bool not null default false,
  standings_updated_at timestamptz
);

create table teams (
  id int primary key,
  name text not null,
  short_name text,
  tla text,
  crest_url text,
  name_ru text,
  short_name_ru text,
  updated_at timestamptz not null default now()
);

create table matches (
  id int primary key,
  competition_id int not null references competitions (id),
  utc_date timestamptz not null,
  status text not null,
  matchday int,
  stage text,
  group_name text,
  home_team_id int references teams (id),
  away_team_id int references teams (id),
  home_score int,
  away_score int,
  winner text,
  source_updated_at timestamptz,
  synced_at timestamptz not null default now()
);
create index matches_utc_date_idx on matches (utc_date);
create index matches_competition_utc_date_idx on matches (competition_id, utc_date);

create table standings (
  competition_id int not null references competitions (id),
  stage text not null,
  group_name text not null default '',
  position int not null,
  team_id int not null references teams (id),
  played int,
  won int,
  draw int,
  lost int,
  goals_for int,
  goals_against int,
  goal_difference int,
  points int,
  form text,
  primary key (competition_id, stage, group_name, team_id)
);

create table sync_state (
  key text primary key,
  value jsonb not null,
  updated_at timestamptz not null default now()
);

alter table competitions enable row level security;
alter table teams enable row level security;
alter table matches enable row level security;
alter table standings enable row level security;
alter table sync_state enable row level security;

create policy competitions_read on competitions for select to anon, authenticated using (true);
create policy teams_read on teams for select to anon, authenticated using (true);
create policy matches_read on matches for select to anon, authenticated using (true);
create policy standings_read on standings for select to anon, authenticated using (true);

-- Атомарная замена таблицы турнира: delete + insert в одной транзакции функции.
create function replace_standings(p_competition_id int, p_rows jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from standings where competition_id = p_competition_id;

  insert into standings (
    competition_id, stage, group_name, position, team_id, played, won, draw, lost,
    goals_for, goals_against, goal_difference, points, form
  )
  select
    p_competition_id, r.stage, coalesce(r.group_name, ''), r.position, r.team_id, r.played, r.won,
    r.draw, r.lost, r.goals_for, r.goals_against, r.goal_difference, r.points, r.form
  from jsonb_to_recordset(p_rows) as r(
    stage text, group_name text, position int, team_id int, played int, won int, draw int,
    lost int, goals_for int, goals_against int, goal_difference int, points int, form text
  );

  update competitions set standings_updated_at = now() where id = p_competition_id;
end;
$$;

revoke execute on function replace_standings(int, jsonb) from public, anon, authenticated;
grant execute on function replace_standings(int, jsonb) to service_role;

insert into competitions (id, code, name, enabled) values
  (2021, 'PL', 'Premier League', true),
  (2014, 'PD', 'Primera Division', true),
  (2002, 'BL1', 'Bundesliga', true),
  (2019, 'SA', 'Serie A', true),
  (2015, 'FL1', 'Ligue 1', true),
  (2001, 'CL', 'UEFA Champions League', true),
  (2013, 'BSA', 'Campeonato Brasileiro Série A', false),
  (2016, 'ELC', 'Championship', false),
  (2018, 'EC', 'European Championship', false),
  (2003, 'DED', 'Eredivisie', false),
  (2017, 'PPL', 'Primeira Liga', false),
  (2152, 'CLI', 'Copa Libertadores', false),
  (2000, 'WC', 'FIFA World Cup', false);
