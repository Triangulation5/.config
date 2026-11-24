/**
 * Unit tests for silhouette-shell's pure JS utility modules (calc, fuzzy,
 * format, lua/fields, keybinds/keychord). Uses Node's built-in assert and vm
 * modules, matching utils/keybinds/binds.test.js.
 */

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const ROOT = path.resolve(__dirname, "..");

function loadModule(relPath, exportsList) {
    const sandbox = {};
    const src = fs.readFileSync(path.join(ROOT, relPath), "utf8");
    const tail = "\nglobalThis.__exports = { " + exportsList.join(", ") + " };";
    vm.runInNewContext(src + tail, sandbox);
    return sandbox.__exports;
}

/** ---- utils/launcher/calc.js ---- */
{
    const { evaluate } = loadModule("utils/launcher/calc.js", ["evaluate"]);

    const r1 = evaluate("2 + 3 * 4");
    assert.equal(r1.ok, true);
    assert.equal(r1.value, 14);
    assert.equal(r1.display, "14");
    assert.ok(r1.ops >= 2);

    const r2 = evaluate("(2 + 3) * 4");
    assert.equal(r2.ok, true);
    assert.equal(r2.value, 20);

    const r3 = evaluate("sqrt(81) + sin(90)");
    assert.equal(r3.ok, true);
    assert.ok(Math.abs(r3.value - 10) < 1e-9);

    const r4 = evaluate("50% * 200");
    assert.equal(r4.ok, true);
    assert.equal(r4.value, 100);

    const r5 = evaluate("pi * 2");
    assert.equal(r5.ok, true);
    assert.ok(Math.abs(r5.value - Math.PI * 2) < 1e-9);

    /** Safety & rejection cases: lone number/constant or arbitrary text must not eval as calc. */
    assert.equal(evaluate("42").ops, 0);
    assert.equal(evaluate("pi").ok, false);
    assert.equal(evaluate("firefox").ok, false);
    assert.equal(evaluate("process.exit(1)").ok, false);
    assert.equal(evaluate("1 / 0").ok, false);
    assert.equal(evaluate("").ok, false);
}

/** ---- utils/launcher/fuzzy.js ---- */
{
    const { rank, score } = loadModule("utils/launcher/fuzzy.js", ["rank", "score"]);

    const entries = [
        { id: "firefox.desktop", name: "Firefox", genericName: "Web Browser", keywords: ["internet"] },
        { id: "kitty.desktop", name: "Kitty", genericName: "Terminal", keywords: ["shell", "console"] },
        { id: "code.desktop", name: "Visual Studio Code", genericName: "Editor", keywords: ["ide"] },
        { id: "hidden.desktop", name: "Hidden App", noDisplay: true }
    ];

    /** Hidden entries are excluded. */
    const all = rank(entries, "", { "kitty.desktop": 5, "firefox.desktop": 2 });
    assert.equal(all.length, 3);
    assert.equal(all[0].id, "kitty.desktop");
    assert.equal(all[1].id, "firefox.desktop");

    /** Prefix beats substring beats subsequence. */
    assert.equal(score(entries[0], "fire"), 0);
    assert.equal(score(entries[0], "brow"), 1);
    assert.equal(score(entries[2], "vsc"), 2);
    assert.equal(score(entries[0], "zzz"), 99);

    const hits = rank(entries, "term", {});
    assert.equal(hits.length, 1);
    assert.equal(hits[0].id, "kitty.desktop");
}

/** ---- utils/format.js ---- */
{
    const { fmtTime } = loadModule("utils/format.js", ["fmtTime"]);
    assert.equal(fmtTime(0), "0:00");
    assert.equal(fmtTime(5.9), "0:05");
    assert.equal(fmtTime(65), "1:05");
    assert.equal(fmtTime(3661.7), "61:01");
}

/** ---- utils/lua/fields.js ---- */
{
    const { getField, setField, escapeRe } = loadModule("utils/lua/fields.js", [
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

    /** Commas inside quoted values must be replaced whole. */
    const u2 = setField(lua, "kb_layout", '"gb"');
    assert.equal(u2.ok, true);
    assert.equal(getField(u2.text, "kb_layout"), "gb");

    const u3 = setField(lua, "nonexistent", "1");
    assert.equal(u3.ok, false);
    assert.equal(u3.text, lua);

    assert.equal(escapeRe("a.b+c?"), "a\\.b\\+c\\?");
}

/** ---- utils/keybinds/keychord.js ---- */
{
    const { chord, keyName } = loadModule("utils/keybinds/keychord.js", ["chord", "keyName"]);
    /** Bare modifier key returns null. */
    assert.equal(chord(0x01000020, 0x10000000), null);
    /** SUPER + K */
    assert.equal(chord(0x4b, 0x10000000), "SUPER + K");
    /** SUPER + SHIFT + Return */
    assert.equal(chord(0x01000004, 0x10000000 | 0x02000000), "SUPER + SHIFT + Return");
    /** F-keys and punctuation */
    assert.equal(keyName(0x01000030), "F1");
    assert.equal(keyName(0x0100003b), "F12");
    assert.equal(keyName(0x2f), "slash");
}

console.log("js utils tests: all passed");
