// Строки БД (snake_case, как в миграции football.sql). Поля *_ru и enabled синк не пишет.
export interface CompetitionRow {
  id: number;
  code: string;
  name: string;
  emblem_url: string | null;
}

export interface TeamRow {
  id: number;
  name: string;
  short_name: string;
  tla: string | null;
  crest_url: string | null;
}

export interface MatchRow {
  id: number;
  competition_id: number;
  utc_date: string;
  status: string;
  matchday: number | null;
  stage: string | null;
  group_name: string | null;
  home_team_id: number | null;
  away_team_id: number | null;
  home_score: number | null;
  away_score: number | null;
  winner: string | null;
  source_updated_at: string | null;
}

export interface StandingRow {
  stage: string;
  group_name: string;
  position: number;
  team_id: number;
  played: number | null;
  won: number | null;
  draw: number | null;
  lost: number | null;
  goals_for: number | null;
  goals_against: number | null;
  goal_difference: number | null;
  points: number | null;
  form: string | null;
}
