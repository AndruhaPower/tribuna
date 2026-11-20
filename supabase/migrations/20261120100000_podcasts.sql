-- Каталог подкастов (D16): ведёт редакция, клиент только читает включённые. Выпуски клиент берёт из RSS-лент сам.
-- Подкасты найдены через iTunes Search (country=ru) и проверены 2026-11-20: лента 200 и XML, ≥ 30 выпусков,
-- последний выпуск не старше 3 месяцев, все enclosure по https, аудио последнего выпуска 206 audio/mpeg, обложка 200 image/jpeg.
-- Только https: http-медиа блокирует ATS (см. «Грабли» в docs/decisions.md).
-- Обложка — artworkUrl600 из iTunes (600×600), а не оригинал ленты (бывает 3000×3000).

create table podcasts (
  id text primary key,
  title text not null,
  author text not null,
  feed_url text not null,
  artwork_url text not null,
  featured_order int,
  enabled bool not null default true
);

alter table podcasts enable row level security;
create policy podcasts_read on podcasts for select to anon, authenticated using (enabled);

-- featured_order: общий спорт (1–3), футбол (4–11), хоккей (12–13), теннис (14).
insert into podcasts (id, title, author, feed_url, artwork_url, featured_order) values
  ('skvoz-sport', 'Сквозь Спорт', 'Алексей Бибиков', 'https://podster.fm/rss.xml?pid=100138', 'https://is1-ssl.mzstatic.com/image/thumb/Podcasts211/v4/ae/fe/42/aefe420e-f011-e07e-5991-815550cbdae5/mza_16765462091896871357.jpg/600x600bb.jpg', 1),
  ('kp-sport-news', 'Новости спорта', 'Радио «Комсомольская правда»', 'https://cloud.mave.digital/36130', 'https://is1-ssl.mzstatic.com/image/thumb/Podcasts126/v4/69/f4/37/69f437a4-6199-6ff6-faec-c1ed59c041ed/mza_11842677910032958963.jpg/600x600bb.jpg', 2),
  ('kp-gentlemen', 'Джентльмены спорта', 'Радио «Комсомольская правда»', 'https://cloud.mave.digital/64722', 'https://is1-ssl.mzstatic.com/image/thumb/Podcasts211/v4/1f/9c/89/1f9c8903-7afc-f985-0377-0b1ad7f855ae/mza_4796521957040591022.jpg/600x600bb.jpg', 3),
  ('lukomsky-streams', 'Стримы Лукомского', 'Вадим Лукомский', 'https://cloud.mave.digital/34002', 'https://is1-ssl.mzstatic.com/image/thumb/Podcasts115/v4/db/1a/f7/db1af79f-aa75-139c-e62b-47bbc7782d0f/mza_385123065108061007.png/600x600bb.jpg', 4),
  ('cappuccino-catenaccio', 'Cappuccino & Catenaccio', 'Порошин, Лукомский', 'https://podster.fm/rss.xml?pid=45624', 'https://is1-ssl.mzstatic.com/image/thumb/Podcasts126/v4/46/9a/9e/469a9ee1-11be-e58a-ed63-b55d273dc09d/mza_18018936975419332712.png/600x600bb.jpg', 5),
  ('gorodnitsky', 'Городницкий | АиБ и Вечные', 'Павел Городницкий', 'https://podster.fm/rss.xml?pid=91369', 'https://is1-ssl.mzstatic.com/image/thumb/Podcasts211/v4/a5/fd/1b/a5fd1b72-4d8c-2a6b-94ee-b03f8db7f49a/mza_13002021941689764910.jpg/600x600bb.jpg', 6),
  ('rpl-injustice', 'Премьер-лига несправедливости', 'Championat.com', 'https://podster.fm/rss.xml?pid=82226', 'https://is1-ssl.mzstatic.com/image/thumb/Podcasts221/v4/0f/91/5d/0f915de8-2809-e4fb-76ea-34ecc4c8acd0/mza_8947281236624103013.jpg/600x600bb.jpg', 7),
  ('four-four-two', '4-4-2', 'Фёдор Замыцкий', 'https://cloud.mave.digital/32729', 'https://is1-ssl.mzstatic.com/image/thumb/Podcasts211/v4/f7/84/79/f7847917-4e5d-e619-9488-05c7899dc892/mza_3324083100343931127.jpg/600x600bb.jpg', 8),
  ('rock-n-roll-football', 'Рок-н-ролл футбол', 'Рок-н-ролл футбол', 'https://cloud.mave.digital/73797', 'https://is1-ssl.mzstatic.com/image/thumb/Podcasts221/v4/ea/83/f4/ea83f459-2503-ceb9-048f-d6317fb463a0/mza_12365224177653961179.jpg/600x600bb.jpg', 9),
  ('spartak-show', 'Спартак Шоу', 'Артём Ермолаев, Денис Шефер', 'https://podster.fm/rss.xml?pid=97001', 'https://is1-ssl.mzstatic.com/image/thumb/Podcasts221/v4/e9/52/1e/e9521e9d-b81e-aa2a-97c0-b966221d6216/mza_7254200979748018378.jpg/600x600bb.jpg', 10),
  ('football-wednesday', 'Футбольная среда', 'Илья Саввин', 'https://podster.fm/rss.xml?pid=96136', 'https://is1-ssl.mzstatic.com/image/thumb/Podcasts221/v4/02/6b/f4/026bf42d-1ed5-ef10-5e06-c840a5812e0d/mza_14490843354147653673.jpg/600x600bb.jpg', 11),
  ('bettman-calls', 'Беттмэн позвонит', 'Эмиль Абдулов', 'https://podster.fm/rss.xml?pid=91666', 'https://is1-ssl.mzstatic.com/image/thumb/Podcasts221/v4/ea/bd/2c/eabd2cfa-7374-deaf-1b39-ab3c77b0b4bc/mza_15269898940806161491.jpg/600x600bb.jpg', 12),
  ('shaibovorot', 'Шайбоворот Ткачева', 'Александр Ткачев', 'https://cloud.mave.digital/54729', 'https://is1-ssl.mzstatic.com/image/thumb/Podcasts221/v4/c6/dd/0c/c6dd0c2b-174a-5e10-0046-2642f7e7b1c5/mza_17234498207233401191.jpg/600x600bb.jpg', 13),
  ('okko-tennis', 'Выход к сетке', 'Okko Tennis', 'https://cloud.mave.digital/36633', 'https://is1-ssl.mzstatic.com/image/thumb/Podcasts116/v4/f7/01/a3/f701a339-2042-3b9c-e403-9c421e9fe320/mza_2192722762668020214.jpg/600x600bb.jpg', 14);
