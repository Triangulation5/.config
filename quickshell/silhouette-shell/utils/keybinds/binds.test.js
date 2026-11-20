const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const sandbox = {};
const source = fs.readFileSync(path.join(__dirname, "binds.js"), "utf8");
vm.runInNewContext(source + "\nglobalThis.api = { add, parse, rebind };", sandbox);

const added = sandbox.api.add('local mod = "SUPER"\n', "SUPER + X", 'printf "x)"', "test");
assert.equal(added.ok, true);

let parsed = sandbox.api.parse(added.text);
assert.equal(parsed.length, 1);
assert.equal(parsed[0].cmd, 'printf "x)"');
assert.equal(parsed[0].action, 'hl.dsp.exec_cmd("printf \\"x)\\"")');

const rebound = sandbox.api.rebind(added.text, parsed[0].lineIndex, "SUPER + Y");
assert.equal(rebound.ok, true);
parsed = sandbox.api.parse(rebound.text);
assert.equal(parsed.length, 1);
assert.equal(parsed[0].combo, "SUPER + Y");
assert.equal(parsed[0].cmd, 'printf "x)"');
