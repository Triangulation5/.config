/**
 * Shared value formatting for shell timers. fmtTime renders seconds as M:SS
 * with zero-padded seconds and flooring, so a fractional input never leaks
 * decimals into the label. Used by the lock media progress (Content.qml) and
 * the recorder's elapsed timer, which used to carry two copies of the same
 * logic.
 */
function fmtTime(sec) {
    var m = Math.floor(sec / 60);
    var ss = Math.floor(sec % 60);
    return m + ":" + (ss < 10 ? "0" : "") + ss;
}
