/**
 * Comprehensive unit & syntax test suite for all JavaScript modules in
 * silhouette-shell (QML JS libraries with `.pragma library` / `.import`
 * directives as well as plain JS helpers). Zero external dependencies.
 */

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

/** Cross-realm structural equality for plain objects/arrays returned from `vm`. */
function assertPlainEqual(actual, expected) {
    assert.deepEqual(JSON.parse(JSON.stringify(actual)), expected);
}

const ROOT = path.resolve(__dirname, "..");
const MODULE_CACHE = new Map();

/**
 * Recursively loads a QML-style `.js` file into a fresh Node `vm` context,
 * resolving `.pragma library` and `.import "rel.js" as Alias` directives.
 */
function loadQmlJs(relPath, explicitExports) {
    const absPath = path.resolve(ROOT, relPath);
    const cacheKey = absPath + "::" + (explicitExports ? explicitExports.join(",") : "*");
    if (MODULE_CACHE.has(cacheKey))
        return MODULE_CACHE.get(cacheKey);

    const raw = fs.readFileSync(absPath, "utf8");
    const sandbox = {};
    const strippedLines = [];

    for (const line of raw.split("\n")) {
        const imp = /^\s*\.import\s+"([^"]+)"\s+as\s+(\w+)\s*$/.exec(line);
        if (imp) {
            const targetRel = path.relative(ROOT, path.resolve(path.dirname(absPath), imp[1]));
            sandbox[imp[2]] = loadQmlJs(targetRel);
            strippedLines.push("");
            continue;
        }
        if (/^\s*\.pragma\s+library\s*$/.test(line)) {
            strippedLines.push("");
            continue;
        }
        strippedLines.push(line);
    }

    let src = strippedLines.join("\n");
    if (explicitExports && explicitExports.length > 0) {
        src += "\nglobalThis.__exports = { " + explicitExports.join(", ") + " };";
    }
    vm.runInNewContext(src, sandbox, { filename: absPath });
    const result = explicitExports && explicitExports.length > 0 ? sandbox.__exports : sandbox;
    MODULE_CACHE.set(cacheKey, result);
    return result;
}

function collectJsFiles(dir, out = []) {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
        if (entry.name === "target" || entry.name === "__pycache__" || entry.name === "node_modules")
            continue;
        const full = path.join(dir, entry.name);
        if (entry.isDirectory()) {
            collectJsFiles(full, out);
        } else if (entry.isFile() && entry.name.endsWith(".js")) {
            out.push(full);
        }
    }
    return out;
}

let passed = 0;
function test(name, fn) {
    fn();
    passed++;
}

/** 1. Syntax check every .js file in the repo (stripping QML directives). */
test("all .js files parse cleanly", () => {
    const files = collectJsFiles(ROOT);
    assert.ok(files.length >= 15, `expected >= 15 JS files, found ${files.length}`);
    for (const file of files) {
        const src = fs
            .readFileSync(file, "utf8")
            .split("\n")
            .map((l) => (/^\s*\.(pragma|import)\b/.test(l) ? "" : l))
            .join("\n");
        new vm.Script(src, { filename: file });
    }
});

/** 2. utils/launcher/calc.js */
test("launcher/calc.js", () => {
    const { evaluate } = loadQmlJs("utils/launcher/calc.js", ["evaluate"]);

    const r1 = evaluate("2 + 3 * 4");
    assert.equal(r1.ok, true);
    assert.equal(r1.value, 14);
    assert.equal(r1.display, "14");
    assert.ok(r1.ops >= 2);

    assert.equal(evaluate("(2 + 3) * 4").value, 20);
    assert.ok(Math.abs(evaluate("sqrt(81) + sin(90)").value - 10) < 1e-9);
    assert.equal(evaluate("50% * 200").value, 100);
    assert.ok(Math.abs(evaluate("pi * 2").value - Math.PI * 2) < 1e-9);

    assert.equal(evaluate("42").ops, 0);
    assert.equal(evaluate("pi").ok, false);
    assert.equal(evaluate("firefox").ok, false);
    assert.equal(evaluate("process.exit(1)").ok, false);
    assert.equal(evaluate("1 / 0").ok, false);
    assert.equal(evaluate("").ok, false);
});

/** 3. utils/launcher/fuzzy.js */
test("launcher/fuzzy.js", () => {
    const { rank, score } = loadQmlJs("utils/launcher/fuzzy.js", ["rank", "score"]);

    const entries = [
        { id: "firefox.desktop", name: "Firefox", genericName: "Web Browser", keywords: ["internet"] },
        { id: "kitty.desktop", name: "Kitty", genericName: "Terminal", keywords: ["shell", "console"] },
        { id: "code.desktop", name: "Visual Studio Code", genericName: "Editor", keywords: ["ide"] },
        { id: "hidden.desktop", name: "Hidden App", noDisplay: true }
    ];

    const all = rank(entries, "", { "kitty.desktop": 5, "firefox.desktop": 2 });
    assert.equal(all.length, 3);
    assert.equal(all[0].id, "kitty.desktop");
    assert.equal(all[1].id, "firefox.desktop");

    assert.equal(score(entries[0], "fire"), 0);
    assert.equal(score(entries[0], "brow"), 1);
    assert.equal(score(entries[2], "vsc"), 2);
    assert.equal(score(entries[0], "zzz"), 99);

    const hits = rank(entries, "term", {});
    assert.equal(hits.length, 1);
    assert.equal(hits[0].id, "kitty.desktop");
});

/** 4. utils/format.js */
test("format.js", () => {
    const { fmtTime } = loadQmlJs("utils/format.js", ["fmtTime"]);
    assert.equal(fmtTime(0), "0:00");
    assert.equal(fmtTime(5.9), "0:05");
    assert.equal(fmtTime(65), "1:05");
    assert.equal(fmtTime(3661.7), "61:01");
});

/** 5. utils/lua/fields.js */
test("lua/fields.js", () => {
    const { getField, setField, escapeRe } = loadQmlJs("utils/lua/fields.js", [
        "getField",
        "setField",
        "escapeRe"
    ]);

    const lua = 'hl.opt({\n  sensitivity = 0.25,\n  kb_layout = "us,de",\n  enabled = true\n})\n';
    assert.equal(getField(lua, "sensitivity"), "0.25");
    assert.equal(getField(lua, "kb_layout"), "us,de");
    assert.equal(getField(lua, "missing"), "");

    const u1 = setField(lua, "sensitivity", "-0.5");
    assert.equal(u1.ok, true);
    assert.equal(getField(u1.text, "sensitivity"), "-0.5");

    const u2 = setField(lua, "kb_layout", '"gb"');
    assert.equal(u2.ok, true);
    assert.equal(getField(u2.text, "kb_layout"), "gb");

    const u3 = setField(lua, "nonexistent", "1");
    assert.equal(u3.ok, false);
    assert.equal(u3.text, lua);

    assert.equal(escapeRe("a.b+c?"), "a\\.b\\+c\\?");
});

/** 6. utils/lua/insert.js */
test("lua/insert.js", () => {
    const { insertField, insertEnv, appendMonitor } = loadQmlJs("utils/lua/insert.js", [
        "insertField",
        "insertEnv",
        "appendMonitor"
    ]);

    const src = "input = {\n    kb_layout = \"us\",\n}\n";
    const r1 = insertField(src, "input", "repeat_rate", "35");
    assert.equal(r1.ok, true);
    assert.ok(r1.text.includes("    repeat_rate = 35,"));
    assert.equal(insertField(src, "missing", "x", "1").ok, false);

    const envSrc = 'hl.env("XCURSOR_SIZE", "24")\n';
    const r2 = insertEnv(envSrc, "XCURSOR_THEME", "Bibata");
    assert.equal(r2.ok, true);
    assert.ok(r2.text.includes('hl.env("XCURSOR_THEME", "Bibata")'));

    const r3 = appendMonitor("", "DP-1", "2560x1440@144", "0x0", 1);
    assert.equal(r3.ok, true);
    assert.ok(r3.text.includes('output   = "DP-1"'));
    assert.ok(r3.text.includes('mode     = "2560x1440@144"'));
});

/** 7. utils/lua/monitors.js */
test("lua/monitors.js", () => {
    const M = loadQmlJs("utils/lua/monitors.js", [
        "parseMode",
        "parse",
        "mainFromLua",
        "parseWorkspaces",
        "monitorOfWorkspace",
        "setMonitor"
    ]);

    assertPlainEqual(M.parseMode("2560x1440@143.96Hz"), {
        w: 2560,
        h: 1440,
        hz: 144,
        raw: "2560x1440@143.96Hz"
    });
    assert.equal(M.parseMode("bad"), null);

    const mons = M.parse(JSON.stringify([{
        name: "DP-1",
        width: 2560,
        height: 1440,
        refreshRate: 143.9,
        scale: 1,
        x: 0,
        y: 0,
        focused: true,
        availableModes: ["2560x1440@143.96Hz", "invalid"]
    }]));
    assert.equal(mons.length, 1);
    assert.equal(mons[0].refresh, 144);
    assert.equal(mons[0].modes.length, 1);
    assertPlainEqual(M.parse("not json"), []);

    const lua = [
        'hl.monitor({',
        '    output   = "DP-1",',
        '    mode     = "1920x1080@60",',
        '    position = "0x0",',
        '    scale    = 1,',
        '})',
        'for i = 1, 5 do',
        '    hl.workspace_rule({ workspace = i, monitor = "DP-1" })',
        'end'
    ].join("\n");
    assert.equal(M.mainFromLua(lua), "DP-1");

    const ws = M.parseWorkspaces(JSON.stringify([
        { id: 1, monitor: "DP-1" },
        { name: "special:chat", monitor: "DP-1" }
    ]));
    assert.equal(M.monitorOfWorkspace(ws, 1), "DP-1");
    assert.equal(M.monitorOfWorkspace(ws, 99), "");

    const upd = M.setMonitor(lua, "DP-1", "2560x1440@144", "1920x0", 1.25);
    assert.equal(upd.ok, true);
    assert.ok(upd.text.includes('mode     = "2560x1440@144"'));
    assert.ok(upd.text.includes('position = "1920x0"'));
    assert.ok(upd.text.includes("scale    = 1.25"));
    assert.equal(M.setMonitor(lua, "HDMI-1", "1920x1080@60", "0x0", 1).ok, false);
});

/** 8. utils/lua/setAnim.js */
test("lua/setAnim.js", () => {
    const A = loadQmlJs("utils/lua/setAnim.js", [
        "getEnabled",
        "setEnabled",
        "getLeafSpeed",
        "setAllSpeeds",
        "getCurvePoints",
        "setCurvePoints"
    ]);
    const lua = [
        "animations = { enabled = true }",
        'hl.curve("fast", { type = "bezier", points = { { 0.1, 0.2 }, { 0.3, 1.0 } } })',
        'hl.animation({ leaf = "windows", speed = 4 })',
        'hl.animation({ leaf = "fade", speed = 2.5 })'
    ].join("\n");

    assert.equal(A.getEnabled(lua), "true");
    assert.equal(A.getEnabled(A.setEnabled(lua, "false").text), "false");
    assert.equal(A.getLeafSpeed(lua, "windows"), "4");
    const sp = A.setAllSpeeds(lua, "6");
    assert.equal(sp.ok, true);
    assert.equal(sp.count, 2);
    assert.equal(A.getLeafSpeed(sp.text, "fade"), "6");
    assertPlainEqual(A.getCurvePoints(lua, "fast"), [0.1, 0.2, 0.3, 1.0]);
    const cp = A.setCurvePoints(lua, "fast", "0.2", "0.0", "0.0", "1.0");
    assert.equal(cp.ok, true);
    assertPlainEqual(A.getCurvePoints(cp.text, "fast"), [0.2, 0.0, 0.0, 1.0]);
});

/** 9. utils/lua/setDeco.js */
test("lua/setDeco.js", () => {
    const D = loadQmlJs("utils/lua/setDeco.js", [
        "getBlockField",
        "setBlockField",
        "hasNamedRule",
        "addNamedRule",
        "removeNamedRule"
    ]);
    const lua = [
        "decoration = {",
        "    blur = { enabled = true, size = 8 },",
        "    shadow = { enabled = false, range = 12 },",
        "}",
        ""
    ].join("\n");

    assert.equal(D.getBlockField(lua, "blur", "enabled"), "true");
    assert.equal(D.getBlockField(lua, "shadow", "enabled"), "false");
    const u = D.setBlockField(lua, "shadow", "enabled", "true");
    assert.equal(u.ok, true);
    assert.equal(D.getBlockField(u.text, "shadow", "enabled"), "true");
    assert.equal(D.getBlockField(u.text, "blur", "enabled"), "true");

    const rule = 'hl.layer_rule({\n    name = "pill-blur",\n    blur = true,\n})\n';
    assert.equal(D.hasNamedRule(lua, "pill-blur"), false);
    const added = D.addNamedRule(lua, rule);
    assert.equal(added.ok, true);
    assert.equal(D.hasNamedRule(added.text, "pill-blur"), true);
    assert.equal(D.addNamedRule(added.text, rule).ok, false);
    const removed = D.removeNamedRule(added.text, "pill-blur");
    assert.equal(removed.ok, true);
    assert.equal(D.hasNamedRule(removed.text, "pill-blur"), false);
});

/** 10. utils/lua/setInput.js */
test("lua/setInput.js", () => {
    const I = loadQmlJs("utils/lua/setInput.js", ["setEnv", "setCursorLine"]);
    const src = 'hl.env("XCURSOR_THEME", "Old")\nhyprctl setcursor Old 24\n';
    const e = I.setEnv(src, "XCURSOR_THEME", "NewTheme");
    assert.equal(e.ok, true);
    assert.ok(e.text.includes('hl.env("XCURSOR_THEME", "NewTheme")'));
    const c = I.setCursorLine(e.text, "NewTheme", 32);
    assert.equal(c.ok, true);
    assert.ok(c.text.includes("setcursor NewTheme 32"));
});

/** 11. utils/keybinds/keychord.js */
test("keybinds/keychord.js", () => {
    const { chord, keyName } = loadQmlJs("utils/keybinds/keychord.js", ["chord", "keyName"]);
    assert.equal(chord(0x01000020, 0x10000000), null);
    assert.equal(chord(0x4b, 0x10000000), "SUPER + K");
    assert.equal(chord(0x01000004, 0x10000000 | 0x02000000), "SUPER + SHIFT + Return");
    assert.equal(keyName(0x01000030), "F1");
    assert.equal(keyName(0x0100003b), "F12");
    assert.equal(keyName(0x2f), "slash");
});

/** 12. utils/keybinds/spacebinds.js */
test("keybinds/spacebinds.js", () => {
    const S = loadQmlJs("utils/keybinds/spacebinds.js", [
        "modVar",
        "modValue",
        "combos",
        "inUse",
        "specials",
        "has",
        "add",
        "remove"
    ]);
    const lua = [
        'local mainMod = "SUPER"',
        'hl.bind(mainMod .. " + Q", hl.dsp.window.close())',
        '-- hl.bind(mainMod .. " + X", hl.dsp.window.close())',
        'hl.bind(mainMod .. " + M", hl.dsp.workspace.toggle_special("chat"))',
        'hl.bind(mainMod .. " + SHIFT + M", hl.dsp.window.move({ workspace = "special:chat" }))'
    ].join("\n");

    assert.equal(S.modVar(lua), "mainMod");
    assert.equal(S.modValue(lua), "SUPER");
    assert.equal(S.inUse(lua, "SUPER + Q"), true);
    assert.equal(S.inUse(lua, "SUPER + X"), false);
    assert.equal(S.has(lua, "chat"), true);
    assert.equal(S.specials(lua).length, 1);

    const added = S.add(lua, "music", "N");
    assert.equal(added.ok, true);
    assert.equal(S.has(added.text, "music"), true);
    assert.equal(S.add(added.text, "music", "N").ok, false);

    const removed = S.remove(added.text, "music");
    assert.equal(removed.ok, true);
    assert.equal(S.has(removed.text, "music"), false);
});

/** 13. utils/keybinds/cheatsheet.js */
test("keybinds/cheatsheet.js", () => {
    const C = loadQmlJs("utils/keybinds/cheatsheet.js", ["execName", "readable", "parse"]);
    assert.equal(C.execName('quickshell .. " launcher"'), "launcher");
    assert.equal(C.execName('"/home/u/scripts/screenshot.sh"'), "screenshot");
    assert.equal(C.readable("hl.dsp.window.close()"), "Close window");
    assert.equal(C.readable('hl.dsp.global("quickshell:launcher")'), "Shell: launcher");

    const lua = [
        'local mainMod = "SUPER"',
        'hl.bind(mainMod .. " + Q", hl.dsp.window.close()) -- Close active',
        'hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl"), { locked = true, repeating = true })'
    ].join("\n");
    const rows = C.parse(lua);
    assert.equal(rows.length, 2);
    assert.equal(rows[0].combo, "SUPER + Q");
    assert.equal(rows[0].label, "Close active");
    assert.equal(rows[1].locked, true);
    assert.equal(rows[1].repeating, true);
});

/** 14. utils/settings/fields.js, rows.js, utils/rows.js, style.js */
test("settings/fields.js + rows.js + style.js invariants", () => {
    const { FIELDS, get } = loadQmlJs("utils/settings/fields.js", ["FIELDS", "get"]);
    for (const [key, meta] of Object.entries(FIELDS)) {
        if (meta.min !== undefined && meta.max !== undefined) {
            assert.ok(meta.min < meta.max, `${key}: min >= max`);
            assert.ok(meta.step > 0, `${key}: step must be > 0`);
            if (typeof meta.reset === "number") {
                assert.ok(
                    meta.reset >= meta.min && meta.reset <= meta.max,
                    `${key}: reset ${meta.reset} out of [${meta.min}, ${meta.max}]`
                );
            }
        }
        if (meta.options && meta.names) {
            assert.equal(meta.options.length, meta.names.length, `${key}: options/names mismatch`);
        }
        if (meta.options && meta.reset !== undefined) {
            assert.ok(meta.options.includes(meta.reset), `${key}: reset not in options`);
        }
    }
    assert.ok(get("deco", "gapsIn").max === 40);
    assert.equal(get("unknown", "field"), null);

    const Rows = loadQmlJs("utils/rows.js", ["of", "flag"]);
    const fRow = Rows.flag("nightLightTemp", "slider", "Temp", "Warmth", "K", { custom: 1 });
    assert.equal(fRow.key, "nightLightTemp");
    assert.equal(fRow.min, 2200);
    assert.equal(fRow.max, 6000);
    assert.equal(fRow.custom, 1);

    const dRow = Rows.of("deco", "gapsIn", "slider", "Gaps", "", "px");
    assert.equal(dRow.source, "deco");
    assert.equal(dRow.field, "gapsIn");
    assert.equal(dRow.reset, 6);

    const Style = loadQmlJs("utils/settings/style.js", ["profiles", "profile"]);
    const washi = Style.profile("washi");
    const mat = Style.profile("material");
    const matAlias = Style.profile("material-you");
    const fallback = Style.profile("nonexistent");
    assert.equal(mat, matAlias);
    assert.equal(fallback, washi);
    /** Every profile should share the exact same key set. */
    const washiKeys = Object.keys(washi).sort();
    for (const [name, prof] of Object.entries(Style.profiles)) {
        assert.deepEqual(Object.keys(prof).sort(), washiKeys, `style profile ${name} key drift`);
    }
});

/** 15. components/animation/FaderValue.js */
test("components/animation/FaderValue.js", () => {
    const { clamp01, stepPercent } = loadQmlJs("components/animation/FaderValue.js", [
        "clamp01",
        "stepPercent"
    ]);
    assert.equal(clamp01(-0.5), 0);
    assert.equal(clamp01(0.4), 0.4);
    assert.equal(clamp01(1.8), 1);
    assert.ok(Math.abs(stepPercent(0.5, 10) - 0.6) < 1e-9);
    assert.equal(stepPercent(0.95, 20), 1);
    assert.equal(stepPercent(0.05, -20), 0);
});

/** 16. modules/lock/dots/shapeGeometry.js */
test("modules/lock/dots/shapeGeometry.js", () => {
    const G = loadQmlJs("modules/lock/dots/shapeGeometry.js", [
        "SAMPLES",
        "DOT",
        "SHAPES",
        "circleProfile",
        "scaleProfile",
        "lerpProfile"
    ]);
    assert.equal(G.DOT.length, G.SAMPLES);
    assert.equal(G.SHAPES.length, 6);
    for (const s of G.SHAPES) {
        assert.equal(s.flourish.length, G.SAMPLES);
        assert.equal(s.flash.length, G.SAMPLES);
        assert.ok(s.flourish.every((r) => Number.isFinite(r) && r > 0));
    }
    const c = G.circleProfile(5);
    assert.equal(c.length, G.SAMPLES);
    assert.equal(G.scaleProfile(c, 2)[0], 10);
    assert.equal(G.lerpProfile(c, G.circleProfile(15), 0.5)[0], 10);
});

console.log(`js utils tests: all ${passed} suites passed`);
