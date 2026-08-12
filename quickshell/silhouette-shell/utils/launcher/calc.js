/**
 * Safe arithmetic evaluator for the launcher's calc mode. A hand-written
 * recursive-descent parser walks a small grammar (+ - * / ^ %, function calls,
 * named constants, parentheses, decimals, and postfix % as divide by 100), so a
 * typed query never reaches a JS eval and can never run code. evaluate() returns
 * { ok, value, display, ops } where `ops` counts real operations, letting the
 * launcher show a result only when the query is an actual calculation and not a
 * lone number or an app name.
 *
 * Supported functions: sqrt, sin, cos, tan, log, ln, abs, round, floor, ceil
 * Supported constants: π / pi, e
 * Angles for trig functions are in degrees.
 */

/** Recognised named functions and their Math counterparts. */
var FNS = {
    sqrt:  { fn: Math.sqrt,   arity: 1 },
    sin:   { fn: deg(Math.sin),   arity: 1 },
    cos:   { fn: deg(Math.cos),   arity: 1 },
    tan:   { fn: deg(Math.tan),   arity: 1 },
    log:   { fn: Math.log10, arity: 1 },
    ln:    { fn: Math.log,   arity: 1 },
    abs:   { fn: Math.abs,   arity: 1 },
    round: { fn: Math.round, arity: 1 },
    floor: { fn: Math.floor, arity: 1 },
    ceil:  { fn: Math.ceil,  arity: 1 },
};

/** Wraps a trigonometric function so it accepts degrees instead of radians. */
function deg(fn) {
    return function (x) { return fn(x * Math.PI / 180); };
}

/** Named constants recognised as standalone identifiers. */
var CONSTS = {
    pi:   Math.PI,
    "\u03c0": Math.PI,  // π
    e:    Math.E,
};

/**
 * Tokeniser.  Returns an array where 0 = number sentinel (the next slot is the
 * numeric value), a single-character string is an operator or parenthesis, a
 * multi-character string is a function/constant name, and \0 marks end-of-input.
 * Returns null on illegal input.
 */
function tokenize(src) {
    var tokens = [];
    var len = src.length;
    var i = 0;
    while (i < len) {
        var c = src.charCodeAt(i);

        // whitespace
        if (c === 32 || c === 9) { i++; continue; }

        // number literal (leading digit or dot)
        if ((c >= 48 && c <= 57) || c === 46) {
            var start = i;
            var dots = 0;
            while (i < len) {
                c = src.charCodeAt(i);
                if (c === 46) {
                    dots++;
                    if (dots > 1) return null;
                } else if (c < 48 || c > 57) {
                    break;
                }
                i++;
            }
            tokens.push(0);
            tokens.push(parseFloat(src.slice(start, i)));
            continue;
        }

        // named identifier: function or constant
        if ((c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c === 0x3c0 /* π */) {
            var start = i;
            while (i < len) {
                c = src.charCodeAt(i);
                if ((c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c === 0x3c0) {
                    i++;
                } else {
                    break;
                }
            }
            tokens.push(src.slice(start, i));
            continue;
        }

        // single-character operators and parens
        switch (src[i]) {
            case '+': case '-': case '*': case '/': case '^':
            case '%': case '(': case ')': case ',':
                tokens.push(src[i]);
                i++;
                continue;
            default:
                return null;
        }
    }
    return tokens;
}

/**
 * Recursive-descent evaluator.  Throws on parse error; the public `evaluate`
 * wrapper catches and returns { ok: false }.
 */
function evaluate(src) {
    var fail = { ok: false, value: NaN, display: "", ops: 0 };
    if (!src) return fail;
    src = src.trim();
    if (!src) return fail;

    var tokens = tokenize(src);
    if (!tokens || tokens.length === 0) return fail;

    var index = 0;
    var ops = 0;

    function peek() { return tokens[index]; }
    function advance() { return tokens[index++]; }

    function parseExpr() {
        var value = parseTerm();
        while (true) {
            var tok = peek();
            if (tok === '+') { index++; value += parseTerm(); ops++; }
            else if (tok === '-') { index++; value -= parseTerm(); ops++; }
            else return value;
        }
    }

    function parseTerm() {
        var value = parsePower();
        while (true) {
            var tok = peek();
            if (tok === '*') { index++; value *= parsePower(); ops++; }
            else if (tok === '/') { index++; value /= parsePower(); ops++; }
            else return value;
        }
    }

    function parsePower() {
        var value = parseUnary();
        if (peek() === '^') { index++; ops++; return Math.pow(value, parsePower()); }
        return value;
    }

    function parseUnary() {
        var tok = peek();
        if (tok === '-') { index++; return -parseUnary(); }
        if (tok === '+') { index++; return parseUnary(); }
        return parsePostfix();
    }

    function parsePostfix() {
        var value = parsePrimary();
        if (peek() === '%') { index++; ops++; value /= 100; }
        return value;
    }

    function parsePrimary() {
        var tok = peek();
        if (tok === undefined) throw 0;

        // number literal (sentinel 0 followed by value)
        if (tok === 0) { index += 2; return tokens[index - 1]; }

        // named constant
        if (typeof tok === "string" && CONSTS.hasOwnProperty(tok)) {
            index++;
            return CONSTS[tok];
        }

        // function call
        if (typeof tok === "string" && FNS.hasOwnProperty(tok)) {
            var meta = FNS[tok];
            index++;
            if (peek() !== '(') throw 0;
            index++; // consume '('
            var args = [];
            args.push(parseExpr());
            while (peek() === ',') {
                index++;
                args.push(parseExpr());
            }
            if (peek() !== ')') throw 0;
            index++; // consume ')'
            if (args.length !== meta.arity) throw 0;
            ops++;
            return meta.fn.apply(null, args);
        }

        // parenthesised expression
        if (tok === '(') {
            index++;
            var value = parseExpr();
            if (peek() !== ')') throw 0;
            index++;
            return value;
        }

        throw 0;
    }

    var value;
    try { value = parseExpr(); } catch (e) { return fail; }
    if (index !== tokens.length) return fail;
    if (typeof value !== "number" || !isFinite(value)) return fail;
    if (ops < 1) return fail;

    value = parseFloat(value.toPrecision(12));
    if (value === 0) value = 0;

    return { ok: true, value: value, display: String(value), ops: ops };
}
