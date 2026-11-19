#!/usr/bin/env python3
"""Проверка бесплатных API для MVP «Трибуна».

Запуск:  python3 tribuna_api_check.py
Ключ football-data.org спрашивается при запуске (или берётся из FD_KEY),
нигде не сохраняется и не попадает в отчёт. Результат: папка
tribuna_api_report/ рядом со скриптом — report.md и сырые ответы в raw/.
Нужны только curl и python3 (есть на любом Mac с Xcode).
"""
import datetime
import getpass
import json
import os
import subprocess
import urllib.parse
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "tribuna_api_report")
RAW = os.path.join(OUT, "raw")
os.makedirs(RAW, exist_ok=True)
UA = "TribunaMVP-check/1.0"
LINES = []


def log(mark, text):
    LINES.append("- " + mark + " " + text)
    print(mark, text)


def section(title):
    LINES.append("\n## " + title + "\n")
    print("\n== " + title)


def get(name, url, headers=(), max_time=25, extra=()):
    hfile = os.path.join(RAW, name + ".headers.txt")
    bfile = os.path.join(RAW, name + ".body")
    cmd = ["curl", "-sS", "-L", "-m", str(max_time), "-A", UA,
           "-D", hfile, "-o", bfile, "-w", "%{http_code}"] + list(extra)
    for h in headers:
        cmd += ["-H", h]
    r = subprocess.run(cmd + [url], capture_output=True, text=True)
    hdr = open(hfile, errors="replace").read() if os.path.exists(hfile) else ""
    body = open(bfile, "rb").read() if os.path.exists(bfile) else b""
    return r.stdout.strip() or "000", hdr, body, r.stderr.strip()


def get_json(name, url, headers=()):
    code, hdr, body, err = get(name, url, headers)
    try:
        data = json.loads(body)
    except ValueError:
        data = None
    if code != "200" or data is None:
        log("❌", "%s: HTTP %s %s" % (name, code, err[:150]))
        return code, hdr, None
    return code, hdr, data


def header(hdr, key):
    for line in hdr.splitlines():
        if line.lower().startswith(key.lower() + ":"):
            return line.split(":", 1)[1].strip()
    return None


def football(key):
    section("Футбол — football-data.org")
    H = ["X-Auth-Token: " + key]
    code, hdr, d = get_json("fd_competitions", "https://api.football-data.org/v4/competitions", H)
    if d is None:
        log("❌", "Ключ не принят или API недоступно — дальше футбол не проверяю")
        return
    free = [c.get("code") for c in d.get("competitions", []) if c.get("plan") == "TIER_ONE"]
    log("✅", "Турниры бесплатного уровня (TIER_ONE): " + ", ".join(str(c) for c in free))
    log("ℹ️", "Лимит запросов в минуту (заголовок): %s" % header(hdr, "X-Requests-Available-Minute"))

    today = datetime.date.today()
    url = "https://api.football-data.org/v4/matches?dateFrom=%s&dateTo=%s" % (
        today - datetime.timedelta(days=3), today + datetime.timedelta(days=3))
    code, hdr, d = get_json("fd_matches_week", url, H)
    matches = (d or {}).get("matches", [])
    log("✅" if matches else "⚠️", "Матчей ±3 дня: %d" % len(matches))
    if matches:
        m = matches[0]
        log("ℹ️", "Поля матча: " + ", ".join(sorted(m.keys())))
        log("✅" if "matchday" in m else "❌", "Тур (matchday): %s" % m.get("matchday"))
        log("✅" if m.get("venue") else "⚠️", "Стадион (venue): %s" % m.get("venue"))
        ht = m.get("homeTeam", {})
        log("ℹ️", "Поля команды: %s; пример: name=%s, shortName=%s, tla=%s" % (
            ", ".join(sorted(ht.keys())), ht.get("name"), ht.get("shortName"), ht.get("tla")))
        log("ℹ️", "Есть ли русские названия: проверьте пример выше (ожидаем английские)")
        log("ℹ️", "Статусы в выборке: " + ", ".join(sorted({x.get("status", "?") for x in matches})))
        fin = [x for x in matches if x.get("status") == "FINISHED"]
        if fin:
            log("✅", "Итоговый счёт есть: %s" % json.dumps(fin[0].get("score", {}).get("fullTime")))
    code, hdr, d = get_json("fd_matches_live", "https://api.football-data.org/v4/matches?status=IN_PLAY", H)
    live = (d or {}).get("matches", [])
    if not live:
        log("⚠️", "Сейчас нет матчей в игре — минуту и задержку счёта перепроверьте запуском во время матча")
    else:
        m = live[0]
        log("✅" if "minute" in m else "❌", "Минута матча (minute) в бесплатном тарифе: %s" % m.get("minute", "нет поля"))
        log("✅", "Счёт в игре: %s" % json.dumps(m.get("score", {}).get("fullTime")))
        log("ℹ️", "lastUpdated: %s (сравните с текущим временем UTC %s — это и есть задержка)" % (
            m.get("lastUpdated"), datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")))
    code, hdr, d = get_json("fd_standings_PL", "https://api.football-data.org/v4/competitions/PL/standings", H)
    if d:
        row = d["standings"][0]["table"][0]
        log("✅", "Таблица АПЛ: поля строки %s; 1 место: %s, %s очков, %s игр" % (
            ", ".join(sorted(row.keys())), row["team"]["name"], row.get("points"), row.get("playedGames")))
    code, hdr, d = get_json("fd_standings_CL", "https://api.football-data.org/v4/competitions/CL/standings", H)
    if d:
        log("✅", "Таблица ЛЧ отдаётся, групп/этапов: %d" % len(d.get("standings", [])))


def nhl():
    section("Хоккей — NHL Web API (без ключа)")
    code, hdr, d = get_json("nhl_score_now", "https://api-web.nhle.com/v1/score/now")
    if d:
        games = d.get("games", [])
        log("✅", "Матчей в ответе: %d (дата %s)" % (len(games), d.get("currentDate")))
        if games:
            g = games[0]
            log("ℹ️", "Поля матча: " + ", ".join(sorted(g.keys())))
            log("✅" if "gameState" in g else "❌", "Статус (gameState): %s" % g.get("gameState"))
            log("✅" if "clock" in g or "period" in g else "⚠️", "Период/время: period=%s clock=%s" % (
                g.get("period"), json.dumps(g.get("clock"), ensure_ascii=False)))
            name = g.get("homeTeam", {}).get("name", {})
            log("ℹ️", "Языки названия команды: %s (пример: %s)" % (", ".join(name.keys()) or "—", name.get("default")))
            log("ℹ️", "Начало (startTimeUTC): %s; арена: %s" % (g.get("startTimeUTC"), json.dumps(g.get("venue"), ensure_ascii=False)))
    code, hdr, d = get_json("nhl_standings_now", "https://api-web.nhle.com/v1/standings/now")
    if d and d.get("standings"):
        s = d["standings"][0]
        log("✅", "Таблица НХЛ: %s — %s очков, %s игр, дивизион %s" % (
            s.get("teamName", {}).get("default"), s.get("points"), s.get("gamesPlayed"), s.get("divisionName")))


def radio():
    section("Радио — Radio Browser (без ключа)")
    base = "https://de1.api.radio-browser.info/json/stations/search?hidebroken=true&order=votes&reverse=true&limit=15&tag=sport"
    code, hdr, ru = get_json("radio_ru_sport", base + "&countrycode=RU")
    code, hdr, world = get_json("radio_world_sport", base)
    ru, world = ru or [], world or []
    log("✅" if ru else "⚠️", "Спортивных станций с тегом sport в России: %d" % len(ru))
    log("ℹ️", "Спортивных станций в мире (топ-15 по голосам): %d" % len(world))
    sample = (ru or world)[:5]
    for s in sample:
        log("ℹ️", "%s · %s · %s кбит/с · %s · иконка: %s" % (
            s.get("name", "").strip(), s.get("countrycode"), s.get("bitrate"), s.get("codec"), "да" if s.get("favicon") else "нет"))
    for i, s in enumerate(sample[:3]):
        url = s.get("url_resolved") or s.get("url")
        code, hdr, body, err = get("radio_stream_%d" % i, url, ["Icy-MetaData: 1"], max_time=6, extra=["-r", "0-4095"])
        alive = code in ("200", "206") or bool(body)
        log("✅" if alive else "❌", "Поток «%s» отвечает: HTTP %s; ICY-метаданные трека: %s" % (
            s.get("name", "").strip(), code, "есть" if header(hdr, "icy-metaint") else "нет"))


def podcasts():
    section("Подкасты — iTunes Search API + RSS (без ключа)")
    found = []
    for term in ("футбол", "хоккей", "спорт"):
        url = "https://itunes.apple.com/search?media=podcast&country=ru&limit=15&term=" + urllib.parse.quote(term)
        code, hdr, d = get_json("itunes_" + term, url)
        res = (d or {}).get("results", [])
        with_feed = [r for r in res if r.get("feedUrl")]
        log("✅" if with_feed else "⚠️", "«%s»: %d подкастов, с RSS-лентой: %d" % (term, len(res), len(with_feed)))
        found += with_feed
    if not found:
        return
    ids = ",".join(str(r["collectionId"]) for r in found[:3])
    code, hdr, d = get_json("itunes_lookup_batch", "https://itunes.apple.com/lookup?id=" + ids)
    log("✅" if d and d.get("resultCount") == 3 else "⚠️", "Пакетный lookup 3 подкастов одним запросом: %s" % (d or {}).get("resultCount"))
    p = found[0]
    log("ℹ️", "Пример: %s — %s, выпусков %s, обложка: %s" % (
        p.get("collectionName"), p.get("artistName"), p.get("trackCount"), "да" if p.get("artworkUrl600") else "нет"))
    code, hdr, body, err = get("rss_sample", p["feedUrl"])
    try:
        root = ET.fromstring(body)
    except ET.ParseError:
        log("❌", "RSS не разобрался: HTTP %s" % code)
        return
    ns = {"itunes": "http://www.itunes.com/dtds/podcast-1.0.dtd"}
    items = root.findall("./channel/item")
    log("✅" if items else "❌", "Выпусков в RSS: %d" % len(items))
    for it in items[:3]:
        enc = it.find("enclosure")
        log("ℹ️", "%s · %s · длительность %s · mp3: %s" % (
            (it.findtext("title") or "").strip()[:60], it.findtext("pubDate"),
            it.findtext("itunes:duration", namespaces=ns), "да" if enc is not None and enc.get("url") else "нет"))
    etag, lm = header(hdr, "ETag"), header(hdr, "Last-Modified")
    log("✅" if etag or lm else "⚠️", "Кэширование ленты: ETag=%s, Last-Modified=%s" % (bool(etag), bool(lm)))
    if etag:
        code, _, _, _ = get("rss_sample_conditional", p["feedUrl"], ["If-None-Match: " + etag])
        log("✅" if code == "304" else "⚠️", "Повторный запрос с If-None-Match: HTTP %s (304 = лента не перекачивается)" % code)


def main():
    key = os.environ.get("FD_KEY") or getpass.getpass("Ключ football-data.org (Enter — пропустить футбол): ").strip()
    if key:
        football(key)
    else:
        section("Футбол — football-data.org")
        log("⚠️", "Пропущено: ключ не введён")
    nhl()
    radio()
    podcasts()
    path = os.path.join(OUT, "report.md")
    with open(path, "w") as f:
        f.write("# Проверка API «Трибуна» — %s\n" % datetime.datetime.now().strftime("%Y-%m-%d %H:%M"))
        f.write("\n".join(LINES) + "\n")
    print("\nГотово: " + path)


if __name__ == "__main__":
    main()
