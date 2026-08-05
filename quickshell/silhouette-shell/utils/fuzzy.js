function haystacks(e) {
    var parts = [];
    if (e.name)
        parts.push(String(e.name));
    if (e.genericName)
        parts.push(String(e.genericName));
    var keywords = e.keywords;
    if (keywords) {
        for (var i = 0; i < keywords.length; i++)
            parts.push(String(keywords[i]));
    }
    return parts;
}

function prepareEntry(e) {
    var cached = e._fuzzy;
    if (cached)
        return cached;
    var fields = haystacks(e);
    var lower = new Array(fields.length);
    for (var i = 0; i < fields.length; i++)
        lower[i] = fields[i].toLowerCase();
    return e._fuzzy = {
        name: e.name ? String(e.name).toLowerCase() : "",
        fields: lower
    };
}

function subsequence(needle, hay) {
    var j = 0;
    var n = needle.length;
    for (var i = 0, len = hay.length; i < len && j < n; i++) {
        if (hay[i] === needle[j])
            j++;
    }
    return j === n;
}

function score(e, q) {
    var data = prepareEntry(e);
    if (data.name.indexOf(q) === 0)
        return 0;
    var fields = data.fields;
    for (var i = 0; i < fields.length; i++) {
        var f = fields[i];
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
    var count = usage[e.id];
    return typeof count === "number" ? count : 0;
}

function nameOf(e) {
    return prepareEntry(e).name;
}

function rank(entries, query, usage) {
    usage = usage || {};
    var visible = [];
    var length = entries.length;
    for (var i = 0; i < length; i++) {
        var e = entries[i];
        if (!e.noDisplay)
            visible.push(e);
    }
    var q = query ? query.trim().toLowerCase() : "";
    if (!q) {
        visible.sort(function (a, b) {
            var ua = uses(usage, a);
            var ub = uses(usage, b);
            if (ua !== ub)
                return ub - ua;
            return nameOf(a) < nameOf(b) ? -1 :
                nameOf(a) > nameOf(b) ? 1 : 0;
        });

        return visible;
    }

    var scored = [];

    for (var k = 0; k < visible.length; k++) {
        var entry = visible[k];
        var s = score(entry, q);

        if (s !== 99) {
            scored.push([
                entry,
                s,
                uses(usage, entry),
                nameOf(entry)
            ]);
        }
    }

    scored.sort(function (a, b) {
        if (a[1] !== b[1])
            return a[1] - b[1];
        if (a[2] !== b[2])
            return b[2] - a[2];
        return a[3] < b[3] ? -1 :
            a[3] > b[3] ? 1 : 0;
    });

    var result = new Array(scored.length);
    for (var x = 0; x < scored.length; x++)
        result[x] = scored[x][0];

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
