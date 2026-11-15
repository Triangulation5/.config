function clamp01(value) {
    return Math.max(0, Math.min(1, value));
}

function stepPercent(value, deltaPct) {
    return clamp01(value + deltaPct / 100);
}
