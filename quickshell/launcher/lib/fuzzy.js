function haystacks(e) {
    var parts = [];
    if (e.name) parts.push(String(e.name));
    if (e.genericName) parts.push(String(e.genericName));
    if (e.keywords) {
        for (var i = 0; i < e.keywords.length; i++)
            parts.push(String(e.keywords[i]));
    }
    return parts;
}

function prepareEntry(e) {
    if (e._fuzzy)
        return e._fuzzy;

    var fields = haystacks(e);
    var lower = new Array(fields.length);

    for (var i = 0; i < fields.length; i++)
        lower[i] = fields[i].toLowerCase();

    return e._fuzzy = {
        name: (e.name || "").toLowerCase(),
        fields: lower
    };
}

function subsequence(needle, hay) {
    var j = 0;
    for (var i = 0, n = needle.length; i < hay.length && j < n; i++)
        if (hay[i] === needle[j]) j++;
    return j === needle.length;
}

function score(e, q) {
    var data = prepareEntry(e);

    if (data.name.indexOf(q) === 0)
        return 0;

    for (var i = 0; i < data.fields.length; i++) {
        var f = data.fields[i];

        if (f.indexOf(q) !== -1)
            return 1;

        if (subsequence(q, f))
            return 2;
    }

    return 99;
}

function uses(usage, e) {
    if (!usage || !e || !e.id)
        return 0;

    var c = usage[e.id];
    return typeof c === "number" ? c : 0;
}

function nameOf(e) {
    return prepareEntry(e).name;
}

function rank(entries, query, usage) {
    usage = usage || {};

    var visible = [];
    for (var i = 0; i < entries.length; i++) {
        if (!entries[i].noDisplay)
            visible.push(entries[i]);
    }

    var q = (query || "").trim().toLowerCase();

    if (!q) {
        return visible.sort(function (a, b) {
            var ua = uses(usage, a);
            var ub = uses(usage, b);

            if (ua !== ub)
                return ub - ua;

            return nameOf(a).localeCompare(nameOf(b));
        });
    }

    var scored = [];

    for (var k = 0; k < visible.length; k++) {
        var e = visible[k];
        var s = score(e, q);

        if (s !== 99) {
            scored.push({
                e: e,
                s: s,
                u: uses(usage, e),
                n: nameOf(e)
            });
        }
    }

    scored.sort(function (a, b) {
        return a.s - b.s ||
            b.u - a.u ||
            a.n.localeCompare(b.n);
    });

    var result = new Array(scored.length);

    for (var x = 0; x < scored.length; x++)
        result[x] = scored[x].e;

    return result;
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = {
        rank: rank,
        score: score,
        subsequence: subsequence,
        haystacks: haystacks,
        uses: uses,
        prepareEntry: prepareEntry
    };
}
