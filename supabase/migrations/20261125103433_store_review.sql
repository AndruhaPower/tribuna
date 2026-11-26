-- Перед первой выкладкой в App Store (D34).
-- 1. Радио: выключаем зарубежные трансляции с правами на спорт (BBC, WDR/Бундеслига, клубное радио НХЛ, Corus) —
--    права на ретрансляцию у них ограничены, а Apple по 5.2.3 просит документы. Российские общедоступные станции остаются.
update stations set enabled = false where id in ('bbc-5live', 'wdr-bundesliga', 'sj-sharks', 'ched-630');

-- 2. Обложки подкастов — из самих RSS-лент, а не из iTunes Search: условия iTunes разрешают
--    его картинки только для продвижения контента магазина. Проверено 2026-11-25: 200, image/*, https.
update podcasts set artwork_url = 'https://podster.fm/image-storage/609907/conversions/3yKF8HiuwT8KVPUw-3xl.jpg' where id = 'skvoz-sport';
update podcasts set artwork_url = 'https://cdn.mave.digital/storage/podcasts/02c72200-55a7-4aff-b6c8-4b8999c77cfb/images/70dc070a-1d1c-40d4-a651-290a43ac6582.jpg' where id = 'kp-sport-news';
update podcasts set artwork_url = 'https://cdn.mave.digital/storage/podcasts/fa4be7a6-ad12-4a2b-a2d0-350d16ba90cd/images/7efe3233-b93f-4875-9052-a60aabbca9c3.jpg' where id = 'kp-gentlemen';
update podcasts set artwork_url = 'https://cdn.mave.digital/storage/podcasts/6cb8e10a-40dd-4383-97be-1e1ebc359fb6/images/f9f88ef4-c779-4fd3-8e7b-f61ece6bfbe9.png' where id = 'lukomsky-streams';
update podcasts set artwork_url = 'https://i.podster.fm/img/273028/crop/yes/size/default/273028-8.jpg' where id = 'cappuccino-catenaccio';
update podcasts set artwork_url = 'https://podster.fm/image-storage/201850/conversions/vk5TwJuWgqsHCQoa-3xl.jpg' where id = 'gorodnitsky';
update podcasts set artwork_url = 'https://podster.fm/image-storage/662436/conversions/PQrxSOYF5G2uQ5Q0-3xl.jpg' where id = 'rpl-injustice';
update podcasts set artwork_url = 'https://cdn.mave.digital/storage/podcasts/0534a4d0-b3aa-43f6-98cc-9185791c6134/images/b3838027-4b88-4583-94c9-aceb28b62958.jpg' where id = 'four-four-two';
update podcasts set artwork_url = 'https://cdn.mave.digital/storage/podcasts/0e690a2a-8de9-4da7-a7db-9c30aa08559e/images/ec630e8a-752a-416c-a715-207b7fb1c09c.jpg' where id = 'rock-n-roll-football';
update podcasts set artwork_url = 'https://podster.fm/image-storage/441496/conversions/SR6YfkuLdrblCq8s-3xl.jpg' where id = 'spartak-show';
update podcasts set artwork_url = 'https://podster.fm/image-storage/427425/conversions/cqtY9FQ7yZafBokB-3xl.jpg' where id = 'football-wednesday';
update podcasts set artwork_url = 'https://podster.fm/image-storage/213142/conversions/mSwzZES0IEktvFL1-3xl.jpg' where id = 'bettman-calls';
update podcasts set artwork_url = 'https://cdn.mave.digital/storage/podcasts/ace979fb-8c5c-4838-a24d-2486a23364bb/images/2fcdc8fa-14c8-452d-89ee-ab3581218622.jpg' where id = 'shaibovorot';
