# Материалы для App Review — Tribuna 1.0

Чек-лист приёмки, п. 12. Тексты описывают то, что есть в сборке 1.0: футбол, радио, подкасты, профиль по почте. Без НХЛ, гербов, входа через Apple и Mindbox (D34, D38).

## Перед выгрузкой — блокеры

- [x] **Иконка приложения** — «Т» с мячом (D42), временная до иконки от дизайна.
- [ ] **Политика конфиденциальности на публичном URL.** Черновик — [privacy-policy.md](privacy-policy.md): заполнить оператора и контакт, опубликовать, вписать URL в App Store Connect.
- [ ] **Аккаунт для ревьюера.** Отдельный, не личный: почта, к которой у команды есть доступ (код из письма, D31). Пароль — только в поле App Review Information в App Store Connect, не в git.
- [ ] **Скриншоты** 6,9″ (iPhone 17 Pro Max): «Сегодня», карточка матча, «Эфир», плеер подкаста, «Подкасты» с загрузками. Только реальные экраны сборки.
- [ ] **Письма-разрешения радиостанций** — подготовить заранее, по 5.2.3 Apple может их запросить (D34).
- [ ] **App Privacy** в App Store Connect — по `PrivacyInfo.xcprivacy`: почта, имя, пользовательский контент; связаны с человеком; для работы приложения; трекинга нет.

## Метаданные

| Поле | Значение |
|---|---|
| Название | Tribuna *(или новое имя — см. риск бренда tribuna.com, D34)* |
| Подзаголовок (30) | Счёт, радио и подкасты |
| Категория | Спорт; дополнительная — Музыка |
| Возраст | 4+ |
| Ключевые слова (100) | футбол,счёт,матчи,лига чемпионов,апл,радио,подкасты,спорт,таблица,напоминание |

**Описание:**

> Tribuna — счёт матчей и спортивный звук в одном приложении.
>
> • Сегодня: матчи топ-лиг Европы и Лиги чемпионов по дням — время, счёт, статус и таблица турнира.
> • Напоминание за 15 минут до начала матча из закладок.
> • Эфир: разговорные и новостные радиостанции — в фоне и на экране блокировки.
> • Подкасты: русскоязычные спортивные подкасты — подписка, новые выпуски, загрузка и прослушивание без интернета, продолжение с того же места.
> • Профиль по почте с фото: закладки, подписки и позиция прослушивания сохраняются и переезжают на новый iPhone. Смотреть и слушать можно и без профиля.
>
> Данные о матчах — football-data.org.

## Заметка для ревьюера (App Review Information → Notes)

> Tribuna shows football scores and fixtures, streams public radio stations and plays sports podcasts.
>
> **Demo account:** see the credentials in the fields above. You can also sign up with any email: the app sends a 6-digit confirmation code.
>
> **Walkthrough:**
> 1. «Сегодня» (Today): pick a day, open a match — score, status, league table. Tap «Напомнить» to get a local notification 15 minutes before kick-off (the notification permission prompt appears here).
> 2. «Эфир» (Radio): play any station; audio continues in background and on the lock screen.
> 3. «Подкасты»: subscribe to a podcast and download an episode — downloads and subscriptions require a profile, so sign in with the demo account when asked.
> 4. «Профиль»: tap the avatar circle to take a profile photo with the camera (permission prompt) or pick one in the system photo picker (no library permission needed); bookmarks and subscriptions counters, downloads storage, sign out, and «Удалить аккаунт» (deletes the account, its photo and all its data on our server).
>
> **Content rights:**
> - Match data comes from the football-data.org API (free tier). Attribution "Football data provided by the Football-Data.org API" is shown at the bottom of the Today screen, as their terms require. Requests to the API are made by our backend; no API key is shipped in the app. Club crests and league logos are not used.
> - Radio: publicly available streams that broadcasters publish on their own websites (https). Stations with sports-broadcast rights restrictions are excluded.
> - Podcasts: public RSS feeds of the publishers; artwork comes from the feeds; audio is streamed or downloaded from the publishers' own links for offline listening, never re-hosted.

## Что нового (1.0)

> Первая версия.
