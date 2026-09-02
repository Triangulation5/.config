pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Live weather for the pill's hover glance, served by Open-Meteo with no API key.
 * Location resolves once and is cached so a restart never re-hits the network for
 * coordinates: by default the city, latitude and longitude come from a keyless IP
 * lookup (ip-api), but a non-empty `Flags.weatherCity` override geocodes that name
 * via Open-Meteo's geocoder instead. Once coordinates are known the forecast runs
 * immediately and then every 20 minutes, exposing the current conditions plus a
 * 24-hour hourly strip.
 *
 * Everything is async through `Process` + `curl`, mirroring how Sysmon and Devices
 * fetch, so startup never blocks on a slow or absent connection. Every JSON parse
 * is guarded: a partial body or network blip leaves the last good values in place
 * and `ready` simply stays false until the first clean fetch lands.
 *
 * Conditions render as on-brand kanji rather than icons — 晴 clear, 曇 cloud,
 * 雨 rain, 雪 snow, 霧 fog, 雷 thunder, 月 a clear night — keyed off the WMO weather
 * code via `glyphFor`, with `labelFor` giving the short english word.
 */
Singleton {
    id: root

    readonly property string cacheDir: (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/ricelin"

    property int tempNow: 0
    property int codeNow: 0
    property int humidity: 0
    property bool isDay: true
    property string city: ""
    property var hourly: []
    property var daily: []

    /** Sunrise/sunset as "HH:MM" 24h strings (today, from the daily block). */
    property string sunrise: ""
    property string sunset: ""

    /** Moon phase name for today's date, computed locally (no network). */
    property string moonPhase: "New moon"

    /**
     * Moon age as a 0..1 fraction of the synodic month (0 new, 0.25 first
     * quarter, 0.5 full, 0.75 last quarter), for the phase disc on the
     * weather surface. Computed locally from the same epoch as moonPhaseFor.
     */
    property real moonAge: 0

    property bool ready: false

    property real lat: 0
    property real lon: 0
    property bool located: false

    /**
     * Maps a WMO weather code to its on-brand kanji. Clear skies show 月 at night
     * so the glance reads day-versus-night at a glance; every other condition is
     * the same glyph round the clock.
     */
    function glyphFor(code, day) {
        if (code === 0)
            return day ? "sun" : "moon";
        if (code <= 3)
            return "cloud";
        if (code === 45 || code === 48)
            return "cloud-fog";
        if (code >= 95)
            return "cloud-lightning";
        if ((code >= 71 && code <= 77) || code === 85 || code === 86)
            return "cloud-snow";
        if ((code >= 51 && code <= 67) || (code >= 80 && code <= 82))
            return "cloud-rain";
        return "cloud";
    }

    /** Short english word for a WMO weather code, for labels and accessibility. */
    function labelFor(code) {
        if (code === 0)
            return "Clear";
        if (code <= 3)
            return "Cloudy";
        if (code === 45 || code === 48)
            return "Fog";
        if (code >= 95)
            return "Thunder";
        if ((code >= 71 && code <= 77) || code === 85 || code === 86)
            return "Snow";
        if ((code >= 51 && code <= 67) || (code >= 80 && code <= 82))
            return "Rain";
        return "Cloudy";
    }

    /** Persist resolved coordinates so a restart skips the location round-trip. */
    function writeLoc() {
        locCache.setText(JSON.stringify({ city: root.city, lat: root.lat, lon: root.lon }));
    }

    /** Shared landing point for every geolocation source (IP lookups and the city geocoder). */
    function applyLoc(city, lat, lon) {
        root.city = city || "";
        root.lat = lat;
        root.lon = lon;
        root.located = true;
        root.writeLoc();
        root.fetchWeather();
    }

    function fetchWeather() {
        if (!located || wxProc.running)
            return;
        wxProc.running = true;
    }

    /**
     * Cached coordinates, read synchronously at startup (blockLoading) so
     * startup never depends on async FileView signals firing for a file that
     * may not exist: if the cache is absent or malformed the bootstrap below
     * falls through to a fresh location lookup on the spot, every time.
     * `text()` is the read side; `setText` (via writeLoc) persists a resolve.
     */
    FileView {
        id: locCache
        path: root.cacheDir + "/weather-loc.json"
        blockLoading: true
        printErrors: false
    }

    /**
     * Startup bootstrap: try the cached coordinates first, else locate fresh.
     * Kept synchronous in Component.onCompleted (not the FileView's async
     * onLoaded/onLoadFailed signals) so a missing cache file can never stall
     * the chain — a missing cache is the common first-run case, and the async
     * signals do not reliably fire for a file that is simply not there.
     */
    Component.onCompleted: {
        /** Moon phase is computed locally, so it is right even before or
         *  without any forecast — the offline fallback for the phase row. */
        root.moonPhase = root.moonPhaseFor(new Date());
        root.moonAge = root.moonAgeFor(new Date());

        try {
            var c = JSON.parse(locCache.text());
            if (c && typeof c.lat === "number" && typeof c.lon === "number") {
                root.city = c.city || "";
                root.lat = c.lat;
                root.lon = c.lon;
                root.located = true;
                root.fetchWeather();
                return;
            }
        } catch (e) {}
        root.locate();
    }

    /**
     * Geolocator chain, walked in order until one yields usable coordinates.
     * Every provider has its own curl command and a parse that maps its reply
     * to { city, lat, lon } or null. First hit wins; a provider that times
     * out, returns empty, or answers with a shape we can't read falls through
     * to the next. None of them are paid or keyed, and they cover each other's
     * blind spots (ip-api is HTTP-only and blacklists some networks, others
     * rate-limit aggressively), so at least one is expected to answer on any
     * given network.
     */
    readonly property var geolocators: [
        {
            id: "ip-api",
            command: ["curl", "-s", "--max-time", "8", "http://ip-api.com/json?fields=lat,lon,city"],
            parse: function(text) {
                var d = JSON.parse(text);
                if (d && typeof d.lat === "number" && typeof d.lon === "number")
                    return { city: d.city || "", lat: d.lat, lon: d.lon };
                return null;
            }
        },
        {
            id: "ipwho.is",
            command: ["curl", "-s", "--max-time", "8", "https://ipwho.is/"],
            parse: function(text) {
                var d = JSON.parse(text);
                if (d && typeof d.latitude === "number" && typeof d.longitude === "number")
                    return { city: d.city || "", lat: d.latitude, lon: d.longitude };
                return null;
            }
        },
        {
            id: "ipapi.co",
            command: ["curl", "-s", "--max-time", "8", "https://ipapi.co/json/"],
            parse: function(text) {
                var d = JSON.parse(text);
                if (d && typeof d.latitude === "number" && typeof d.longitude === "number")
                    return { city: d.city || "", lat: d.latitude, lon: d.longitude };
                return null;
            }
        },
        {
            id: "geojs.io",
            command: ["curl", "-s", "--max-time", "8", "https://geojs.io/v1/ip/geo.json"],
            parse: function(text) {
                var d = JSON.parse(text);
                if (d && typeof d.latitude === "number" && typeof d.longitude === "number")
                    return { city: d.city || "", lat: d.latitude, lon: d.longitude };
                return null;
            }
        },
        {
            /**
             * Last rung: resolve over encrypted DNS (DoH) before curling, for
             * resolvers that blackhole the plain-DNS answers for IP-lookup
             * hosts (ip-api/ipwho.is/ipapi.co/geojs.io are common blocklist
             * targets). dns.google serves dns-query over HTTPS, so curl can
             * resolve the name itself instead of trusting the system resolver.
             */
            id: "ipwho.is (DoH)",
            command: ["curl", "-s", "--max-time", "8", "--doh-url", "https://dns.google/dns-query", "https://ipwho.is/"],
            parse: function(text) {
                var d = JSON.parse(text);
                if (d && typeof d.latitude === "number" && typeof d.longitude === "number")
                    return { city: d.city || "", lat: d.latitude, lon: d.longitude };
                return null;
            }
        }
    ]

    /** Index of the geolocator currently being tried, -1 when the walk is idle or exhausted. */
    property int locIdx: -1

    /**
     * Try the next geolocator in the chain. Recurses on failure: each
     * entry's process finish lands here again with locIdx advanced, so the
     * walk is one process at a time — never a fan-out. When the list runs
     * out without a hit the walk resets to idle; the 30s retry timer picks
     * it back up from the top.
     */
    function tryNextLoc() {
        if (root.located)
            return;
        root.locIdx++;
        if (root.locIdx >= root.geolocators.length) {
            root.locIdx = -1;
            return;
        }
        locProc.command = root.geolocators[root.locIdx].command;
        locProc.running = true;
    }

    /** Resolve coordinates: geocode the manual city override, else walk the IP chain. */
    function locate() {
        if (locProc.running || geoProc.running || root.locIdx >= 0)
            return;
        if (Flags.weatherCity && Flags.weatherCity.trim().length > 0)
            geoProc.running = true;
        else
            root.tryNextLoc();
    }

    Connections {
        target: Flags
        function onWeatherCityChanged() { root.locate(); }
    }

    /** One shared process for the whole geolocator walk; command is set per hop. */
    Process {
        id: locProc
        stdout: StdioCollector {
            onStreamFinished: {
                var g = (root.locIdx >= 0 && root.locIdx < root.geolocators.length)
                    ? root.geolocators[root.locIdx] : null;
                if (!g)
                    return;
                var hit = null;
                try {
                    hit = g.parse(this.text);
                } catch (e) {}
                if (hit && typeof hit.lat === "number" && typeof hit.lon === "number")
                    root.applyLoc(hit.city, hit.lat, hit.lon);
                else
                    root.tryNextLoc();
            }
        }
    }

    Process {
        id: geoProc
        command: ["curl", "-s", "--max-time", "8", "-G",
            "https://geocoding-api.open-meteo.com/v1/search",
            "--data-urlencode", "name=" + (Flags.weatherCity || ""),
            "--data-urlencode", "count=1"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var d = JSON.parse(this.text);
                    var r = d.results && d.results[0];
                    if (r && typeof r.latitude === "number" && typeof r.longitude === "number")
                        root.applyLoc(r.name || "", r.latitude, r.longitude);
                } catch (e) {}
            }
        }
    }

    Process {
        id: wxProc
        command: ["curl", "-s", "--max-time", "10",
            "https://api.open-meteo.com/v1/forecast?latitude=" + root.lat
            + "&longitude=" + root.lon
            + "&current=temperature_2m,weather_code,is_day,relative_humidity_2m"
            + "&hourly=temperature_2m,weather_code&forecast_hours=24"
            + "&daily=weather_code,temperature_2m_max,relative_humidity_2m_mean,sunrise,sunset&forecast_days=5&timezone=auto"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var d = JSON.parse(this.text);
                    var cur = d.current;
                    if (!cur)
                        return;
                    var rows = [];
                    var h = d.hourly;
                    if (h && h.time && h.temperature_2m && h.weather_code) {
                        var n = Math.min(h.time.length, h.temperature_2m.length, h.weather_code.length);
                        for (var i = 0; i < n; i++) {
                            rows.push({
                                hour: h.time[i].slice(11, 13),
                                temp: Math.round(h.temperature_2m[i]),
                                code: h.weather_code[i]
                            });
                        }
                    }
                    var days = [];
                    var dd = d.daily;
                    if (dd && dd.time && dd.weather_code && dd.temperature_2m_max && dd.relative_humidity_2m_mean) {
                        var dn = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
                        var m = Math.min(dd.time.length, dd.weather_code.length, dd.temperature_2m_max.length, dd.relative_humidity_2m_mean.length);
                        for (var j = 0; j < m; j++) {
                            days.push({
                                day: dn[new Date(dd.time[j]).getDay()],
                                code: dd.weather_code[j],
                                temp: Math.round(dd.temperature_2m_max[j]),
                                rh: Math.round(dd.relative_humidity_2m_mean[j])
                            });
                        }
                        /** "2026-09-02T06:42" — take the time part for today. */
                        if (dd.sunrise && dd.sunrise[0])
                            root.sunrise = dd.sunrise[0].slice(11, 16);
                        if (dd.sunset && dd.sunset[0])
                            root.sunset = dd.sunset[0].slice(11, 16);
                    }
                    root.moonPhase = root.moonPhaseFor(new Date());
                    root.moonAge = root.moonAgeFor(new Date());
                    root.tempNow = Math.round(cur.temperature_2m);
                    root.codeNow = cur.weather_code;
                    root.humidity = Math.round(cur.relative_humidity_2m);
                    root.isDay = cur.is_day === 1;
                    root.hourly = rows;
                    root.daily = days;
                    root.ready = true;
                } catch (e) {}
            }
        }
    }

    /**
     * Local moon phase from the date, no network. Lunar month ≈ 29.53059 days;
     * the epoch is the well-known new moon of 2000-01-06 18:14 UTC. The age
     * within the cycle picks one of the eight classic phase names.
     */
    function moonPhaseFor(date) {
        var age = root.moonAgeFor(date);
        var a = age * 29.53058867;
        if (a < 1.84566) return "New moon";
        if (a < 5.53699) return "Waxing crescent";
        if (a < 9.22831) return "First quarter";
        if (a < 12.91963) return "Waxing gibbous";
        if (a < 16.61096) return "Full moon";
        if (a < 20.30228) return "Waning gibbous";
        if (a < 23.99361) return "Last quarter";
        if (a < 27.68493) return "Waning crescent";
        return "New moon";
    }

    /** Moon age as a 0..1 fraction of the synodic month (0 new, 0.5 full). */
    function moonAgeFor(date) {
        var epoch = Date.UTC(2000, 0, 6, 18, 14, 0);
        var synodic = 29.53058867;
        var days = (date.getTime() - epoch) / 86400000;
        var age = days - Math.floor(days / synodic) * synodic;
        return age / synodic;
    }

    /**
     * One repeating tick whose cadence depends on state: while never located
     * it retries every 30s so a transient geolocation failure (offline boot,
     * blacklisted geocoder) heals in seconds instead of leaving the panel
     * dark for a full refresh cycle; once located it drops to refreshing the
     * forecast every 20 minutes.
     */
    Timer {
        interval: root.located ? 1200000 : 30000
        running: true
        repeat: true
        onTriggered: {
            if (!root.located)
                root.locate();
            else
                root.fetchWeather();
        }
    }
}
