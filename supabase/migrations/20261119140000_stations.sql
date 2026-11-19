-- Каталог радиостанций (D16): ведёт редакция, клиент только читает включённые.
-- Потоки отобраны через Radio Browser и проверены (HTTP 200, audio/* или HLS) 2026-11-19.

create table stations (
  id text primary key,
  name text not null,
  stream_url text not null,
  homepage text,
  country text not null,
  bitrate int,
  codec text,
  genres text[] not null default '{}',
  subtitle text not null,
  featured_order int,
  enabled bool not null default true
);

alter table stations enable row level security;
create policy stations_read on stations for select to anon, authenticated using (enabled);

-- featured_order: сначала спорт (1–4), затем новости (5–9); пусто — не в подборке.
-- Русскоязычных спортивных станций в Radio Browser нет, спорт — международные станции; русский каталог — новости и разговорное радио.
insert into stations (id, name, stream_url, homepage, country, bitrate, codec, genres, subtitle, featured_order) values
  ('bbc-5live', 'BBC Radio 5 Live', 'http://as-hls-ww-live.akamaized.net/pool_89021708/live/ww/bbc_radio_five_live/bbc_radio_five_live.isml/bbc_radio_five_live-audio%3d128000.norewind.m3u8', 'https://www.bbc.co.uk/5live', 'Великобритания', null, 'HLS', '{sport,football,news}', 'Спорт · репортажи и новости (на английском)', 1),
  ('wdr-bundesliga', 'Bundesliga: Konferenz', 'https://wdr-sportschau-liga1konferenz.icecastssl.wdr.de/wdr/sportschau/liga1konferenz/mp3/high', 'https://livecenter.sportschau.de/', 'Германия', 128, 'MP3', '{football,sport}', 'Футбол · репортажи с матчей Бундеслиги (на немецком)', 2),
  ('sj-sharks', 'San Jose Sharks Audio Network', 'https://sjsharks.streamguys1.com/sharks-player', 'http://sjsharks.com/listen', 'США', 128, 'MP3', '{hockey,sport}', 'Хоккей · НХЛ, «Сан-Хосе Шаркс» (на английском)', 3),
  ('ched-630', '630 CHED', 'https://corus.leanstream.co/CHEDAM-MP3', 'https://globalnews.ca/radio/630ched/player/', 'Канада', 128, 'MP3', '{hockey,sport,news}', 'Хоккей · спорт и новости, Эдмонтон (на английском)', 4),
  ('vesti-fm', 'Вести FM', 'http://icecast.vgtrk.cdnvideo.ru/vestifm', 'http://radiovesti.ru/', 'Россия', 320, 'MP3', '{news}', 'Новости · разговорное радио', 5),
  ('mayak', 'Радио Маяк', 'http://icecast.vgtrk.cdnvideo.ru/mayakfm_mp3_192kbps', 'http://www.radiomayak.ru/', 'Россия', 192, 'MP3', '{news}', 'Новости · разговорное радио', 6),
  ('kommersant-fm', 'Коммерсантъ FM', 'https://kommersant77.hostingradio.ru:8085/kommersant128.mp3', 'https://www.kommersant.ru/fm', 'Россия', 128, 'MP3', '{news}', 'Новости · экономика и политика', 7),
  ('govorit-moskva', 'Говорит Москва', 'https://media.govoritmoskva.ru/radio/ru64.mp3', 'https://govoritmoskva.ru/', 'Россия', null, 'MP3', '{news}', 'Новости · разговорное радио', 8),
  ('zvezda', 'Звезда', 'https://icecast-zvezda.mediacdn.ru/radio/zvezda/zvezda_128', 'https://radiozvezda.ru/', 'Россия', 128, 'MP3', '{news}', 'Новости · разговорное радио', 9),
  ('kp-radio', 'Радио «Комсомольская правда»', 'http://kpradio.hostingradio.ru:8000/russia.radiokp128.mp3', 'https://www.kp.ru/radio', 'Россия', 128, 'MP3', '{news}', 'Новости · разговорное радио', null),
  ('bfm', 'Business FM', 'https://bfm.hostingradio.ru:9075/fm', 'https://www.bfm.ru/page/radio', 'Россия', 256, 'MP3', '{news}', 'Новости · бизнес и экономика', null),
  ('silver-rain', 'Серебряный дождь', 'http://213.59.4.27:8000/silver128.mp3', 'http://www.silver.ru/', 'Россия', 128, 'MP3', '{news}', 'Новости · разговорное радио и музыка', null);
