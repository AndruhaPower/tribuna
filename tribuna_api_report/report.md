# Проверка API «Трибуна» — 2026-11-18 14:06

## Футбол — football-data.org

- ✅ Турниры бесплатного уровня (TIER_ONE): BSA, ELC, PL, CL, EC, FL1, BL1, SA, DED, PPL, PD, WC
- ℹ️ Лимит запросов в минуту (заголовок): 9
- ✅ Матчей ±3 дня: 12
- ℹ️ Поля матча: area, awayTeam, competition, group, homeTeam, id, lastUpdated, matchday, odds, referees, score, season, stage, status, utcDate
- ✅ Тур (matchday): 35
- ⚠️ Стадион (venue): None
- ℹ️ Поля команды: crest, id, name, shortName, tla; пример: name=Coritiba FBC, shortName=Coritiba, tla=COR
- ℹ️ Есть ли русские названия: проверьте пример выше (ожидаем английские)
- ℹ️ Статусы в выборке: TIMED
- ⚠️ Сейчас нет матчей в игре — минуту и задержку счёта перепроверьте запуском во время матча
- ✅ Таблица АПЛ: поля строки draw, form, goalDifference, goalsAgainst, goalsFor, lost, playedGames, points, position, team, won; 1 место: Arsenal FC, 27 очков, 10 игр
- ✅ Таблица ЛЧ отдаётся, групп/этапов: 1

## Хоккей — NHL Web API (без ключа)

- ✅ Матчей в ответе: 11 (дата 2026-11-17)
- ℹ️ Поля матча: awayTeam, clock, condensedGame, easternUTCOffset, gameCenterLink, gameDate, gameOutcome, gameScheduleState, gameState, gameType, goals, homeTeam, id, neutralSite, period, periodDescriptor, season, startTimeUTC, threeMinRecap, threeMinRecapFr, tvBroadcasts, venue, venueTimezone, venueUTCOffset
- ✅ Статус (gameState): OFF
- ✅ Период/время: period=3 clock={"timeRemaining": "00:00", "secondsRemaining": 0, "running": false, "inIntermission": false}
- ℹ️ Языки названия команды: default (пример: Bruins)
- ℹ️ Начало (startTimeUTC): 2026-11-18T00:00:00Z; арена: {"default": "TD Garden"}
- ✅ Таблица НХЛ: Edmonton Oilers — 37 очков, 23 игр, дивизион Pacific

## Радио — Radio Browser (без ключа)

- ✅ Спортивных станций с тегом sport в России: 1
- ℹ️ Спортивных станций в мире (топ-15 по голосам): 15
- ℹ️ Радио 19-22 · RU · 192 кбит/с · MP3 · иконка: нет
- ✅ Поток «Радио 19-22» отвечает: HTTP 200; ICY-метаданные трека: есть

## Подкасты — iTunes Search API + RSS (без ключа)

- ✅ «футбол»: 15 подкастов, с RSS-лентой: 15
- ✅ «хоккей»: 5 подкастов, с RSS-лентой: 5
- ✅ «спорт»: 15 подкастов, с RSS-лентой: 15
- ✅ Пакетный lookup 3 подкастов одним запросом: 3
- ℹ️ Пример: Футбол для дружбы — Детское Радио, выпусков 17, обложка: да
- ✅ Выпусков в RSS: 17
- ℹ️ Футбольная форма. Как изменилась экипировка за 200 лет? · Fri, 17 Feb 2023 08:48:57 +0000 · длительность 00:05:54 · mp3: да
- ℹ️ Трофеи. Почему каждый футболист мечтает получить в качестве  · Fri, 10 Feb 2023 15:48:53 +0000 · длительность 00:05:41 · mp3: да
- ℹ️ Хобби знаменитых спортсменов. Кто из футболистов пишет стихи · Tue, 07 Feb 2023 09:54:50 +0000 · длительность 00:05:59 · mp3: да
- ⚠️ Кэширование ленты: ETag=False, Last-Modified=False
