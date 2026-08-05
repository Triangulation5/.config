/**
 * Safe arithmetic evaluator for the launcher's calc mode. A hand written
 * recursive descent parser walks a small grammar (+ - * / ^, parentheses,
 * decimals, and postfix % as divide by 100), so a typed query never reaches a
 * JS eval and can never run code. evaluate() returns { ok, value, display, ops }
 * where `ops` counts real operations, letting the launcher show a result only
 * when the query is an actual calculation and not a lone number or an app name.
 */

function tokenize(src) {
    var tokens = [];
    var len = src.length;
    var i = 0;
    while (i < len) {
        var c = src.charCodeAt(i);
        if (c === 32 || c === 9) {
            i++;
            continue;
        }
        if ((c >= 48 && c <= 57) || c === 46) {
            var start = i;
            var dots = 0;
            while (i < len) {
                c = src.charCodeAt(i);
                if (c === 46) {
                    dots++;
                    if (dots > 1)
                        return null;
                } else if (c < 48 || c > 57) {
                    break;
                }
                i++;
            }
            tokens.push(0);
            tokens.push(parseFloat(src.slice(start, i)));
            continue;
        }

        switch (src[i]) {
            case '+':
            case '-':
            case '*':
            case '/':
            case '^':
            case '%':
            case '(':
            case ')':
                tokens.push(src[i]);
                i++;
                continue;
            default:
                return null;
        }
    }
    return tokens;
}

function evaluate(src) {
    var fail = {
        ok: false,
        value: NaN,
        display: "",
        ops: 0
    };
    if (!src)
        return fail;
    src = src.trim();
    if (!src)
        return fail;
    var tokens = tokenize(src);
    if (!tokens || tokens.length === 0)
        return fail;
    var index = 0;
    var ops = 0;
    function peek() {
        return tokens[index];
    }
    function parseExpr() {
        var value = parseTerm();
        while (true) {
            var tok = peek();
            if (tok === '+') {
                index++;
                value += parseTerm();
                ops++;
            } else if (tok === '-') {
                index++;
                value -= parseTerm();
                ops++;
            } else {
                return value;
            }
        }
    }

    function parseTerm() {
        var value = parsePower();
        while (true) {
            var tok = peek();
            if (tok === '*') {
                index++;
                value *= parsePower();
                ops++;
            } else if (tok === '/') {
                index++;
                value /= parsePower();
                ops++;
            } else {
                return value;
            }
        }
    }

    function parsePower() {
        var value = parseUnary();
        if (peek() === '^') {
            index++;
            ops++;
            return Math.pow(value, parsePower());
        }
        return value;
    }

    function parseUnary() {
        var tok = peek();
        if (tok === '-') {
            index++;
            return -parseUnary();
        }
        if (tok === '+') {
            index++;
            return parseUnary();
        }
        return parsePostfix();
    }

    function parsePostfix() {
        var value = parsePrimary();
        if (peek() === '%') {
            index++;
            ops++;
            value /= 100;
        }
        return value;
    }

    function parsePrimary() {
        var tok = peek();
        if (tok === undefined)
            throw 0;
        if (tok === 0) {
            index += 2;
            return tokens[index - 1];
        }
        if (tok === '(') {
            index++;
            var value = parseExpr();
            if (peek() !== ')')
                throw 0;
            index++;
            return value;
        }
        throw 0;
    }

    var value;
    try {
        value = parseExpr();
    } catch (e) {
        return fail;
    }
    if (index !== tokens.length)
        return fail;
    if (typeof value !== "number" || !isFinite(value))
        return fail;
    if (ops < 1)
        return fail;
    value = parseFloat(value.toPrecision(12));
    if (value === 0)
        value = 0;

    return {
        ok: true,
        value: value,
        display: String(value),
        ops: ops
    };
}
