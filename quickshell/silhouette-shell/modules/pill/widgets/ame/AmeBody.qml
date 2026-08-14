pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import qs.services

/**
 * 飴 Ame's molten-glass bead body: the radial-gradient bead with its inner
 * swirl and highlight, the flight streak, the landing splash, and every form
 * (`rest`, `caret`, `seam`, `soul`, `tick`, `rowseam`, `ring`, `dock`). All
 * timeline and anchor state lives on the Ame host (`host`); this canvas only
 * repaints it. FrameAnimation on the host drives repaints only while a
 * timeline, glide or splash is live.
 */
Canvas {
    id: canvas

    property real s: 1.1
    property var host: null

    renderStrategy: Canvas.Cooperative
    antialiasing: true

    readonly property real breathe: 1 + 0.0125 * Math.sin(host.swirl * 0.32)

    function bead(ctx, x, y, R, stretch, ang, alpha) {
        ctx.save();
        if (alpha !== undefined)
            ctx.globalAlpha = alpha;
        ctx.translate(x, y);
        ctx.rotate(ang);
        ctx.scale(1 + stretch, 1 / (1 + stretch * 0.55));
        ctx.rotate(-ang);
        const hg = ctx.createRadialGradient(-R * 0.32, -R * 0.38, 0, 0, 0, R);
        hg.addColorStop(0, Theme.flameInk);
        hg.addColorStop(0.55, Theme.vermLit);
        hg.addColorStop(0.92, Theme.verm);
        hg.addColorStop(1, Theme.flameEmber);
        ctx.beginPath();
        ctx.arc(0, 0, R, 0, 7);
        ctx.fillStyle = hg;
        ctx.fill();
        ctx.save();
        ctx.beginPath();
        ctx.arc(0, 0, R, 0, 7);
        ctx.clip();
        ctx.globalAlpha = (alpha === undefined ? 1 : alpha) * 0.35;
        for (let k = 0; k < 2; k++) {
            ctx.beginPath();
            ctx.arc(0, 0, R * (0.45 + k * 0.22),
                    host.swirl * (0.5 + k * 0.25) + k * 2.6,
                    host.swirl * (0.5 + k * 0.25) + k * 2.6 + 2.4);
            ctx.strokeStyle = k ? Theme.flameBurn : Theme.flameTip;
            ctx.lineWidth = 1.6 * root.s;
            ctx.stroke();
        }
        ctx.restore();
        ctx.beginPath();
        ctx.ellipse(-R * 0.34 - R * 0.30, -R * 0.42 - R * 0.18, R * 0.60, R * 0.36);
        ctx.fillStyle = "rgba(255,246,240,0.6)";
        ctx.fill();
        ctx.beginPath();
        ctx.arc(0, 0, Math.max(0.5, R - 0.8 * root.s), Math.PI * 0.25, Math.PI * 0.75);
        ctx.strokeStyle = "rgba(255,217,194,0.45)";
        ctx.lineWidth = 1.2 * root.s;
        ctx.stroke();
        ctx.restore();
    }

    onPaint: {
        const ctx = getContext("2d");
        ctx.reset();
        if (!host.visible)
            return;

        const S = root.s;
        const bx = host.bx;
        const by = host.by;
        const baseR = host.restR;

        if (host.remnant > 0 && host.phase !== "antic") {
            const rr = baseR * 0.5 * host.remnant;
            if (rr > 0.4 * S)
                bead(ctx, host.remnantPoint.x + (1 - host.remnant) * 6 * S, host.remnantPoint.y,
                     rr, 0, 0, host.remnant * 0.9);
        }

        if (host.phase === "antic") {
            const q = host.clamp01(host.prog / host.pAntic);
            const pull = host.smoothstep(q) * 0.55;
            bead(ctx, bx, by, baseR, pull, host.flightAng);
            return;
        }

        if (host.phase === "fly") {
            const q = (host.prog - host.pAntic) / (host.pFly - host.pAntic);
            const u = host.easeInOutQuint(host.clamp01(q));
            const tail = Math.max(0, u - 0.26 * Math.sin(Math.PI * Math.min(1, q * 1.4)));
            const NSEG = 15;
            for (let i = 0; i < NSEG; i++) {
                const u1 = tail + (u - tail) * (i / NSEG);
                const u2 = tail + (u - tail) * ((i + 1) / NSEG);
                const a2 = host.bez(host.fromPoint, host.ctrlPoint, host.point, u1);
                const b2 = host.bez(host.fromPoint, host.ctrlPoint, host.point, u2);
                const fI = i / NSEG;
                ctx.beginPath();
                ctx.moveTo(a2.x, a2.y);
                ctx.lineTo(b2.x, b2.y);
                ctx.strokeStyle = fI > 0.6 ? Theme.vermLit : Theme.verm;
                ctx.lineWidth = (0.8 + 6.5 * fI * fI) * S;
                ctx.lineCap = "round";
                ctx.globalAlpha = 0.12 + 0.55 * fI;
                ctx.stroke();
            }
            ctx.globalAlpha = 1;
            const speed = Math.sin(Math.PI * host.clamp01(q));
            const d1 = host.bez(host.fromPoint, host.ctrlPoint, host.point, Math.min(1, u + 0.01));
            const tang = Math.atan2(d1.y - by, d1.x - bx);
            bead(ctx, bx, by, baseR * 1.62, speed * 1.0, tang);
            return;
        }

        const settling = host.phase === "settle";
        const q = settling ? host.clamp01((host.prog - host.pFly) / (1 - host.pFly)) : 1;
        const e = settling ? host.easeOutBack(q) : 1;
        const fadeIn = settling ? host.smoothstep(host.clamp01(q * 1.8)) : 1;

        if (settling && q < 0.55) {
            const sq = q / 0.55;
            const hop = Math.sin(Math.PI * sq);
            const angles = [-2.35, -1.57, -0.79];
            for (let i = 0; i < 3; i++) {
                const sa = angles[i];
                const sr = 13 * S * hop;
                const sx2 = bx + Math.cos(sa) * sr;
                const sy2 = by + Math.sin(sa) * sr * 1.25;
                ctx.beginPath();
                ctx.arc(sx2, sy2, (2.2 - 0.9 * sq) * S, 0, 7);
                ctx.fillStyle = Theme.vermLit;
                ctx.globalAlpha = hop * 0.85;
                ctx.fill();
            }
            ctx.globalAlpha = 1;
        }

        const f = host.activeForm;

        if (f === "caret") {
            const blink = settling ? 1 : (0.35 + 0.65 * (0.5 + 0.5 * Math.sin(host.swirl * 5.7)));
            const hgt = 15 * S * e;
            const wdt = (2.5 + 6 * (1 - fadeIn)) * S;
            ctx.globalAlpha = blink;
            ctx.beginPath();
            if (typeof ctx.roundedRect === "function") {
                ctx.roundedRect(bx - wdt / 2, by - hgt / 2, wdt, Math.max(2 * S, hgt), Math.min(wdt, hgt) / 2, Math.min(wdt, hgt) / 2);
            } else {
                ctx.ellipse(bx, by, wdt, Math.max(2 * S, hgt));
            }
            ctx.fillStyle = Theme.flameInk;
            ctx.fill();
            ctx.globalAlpha = 1;
            return;
        }

        if (f === "seam") {
            const R = (3.5 + 1.5 * (1 - fadeIn)) * S;
            bead(ctx, bx, by, R * (settling ? (0.8 + 0.2 * e) : 1), 0, 0);
            return;
        }

        if (f === "soul") {
            const r = 2.8 * S * (settling ? (0.7 + 0.3 * e) : 1);
            const wl = 7 * S * fadeIn;
            const wy0 = by + host.wickDir * (r + 1.5 * S);
            const wg = ctx.createLinearGradient(0, wy0, 0, wy0 + host.wickDir * wl);
            wg.addColorStop(0, Qt.rgba(1, 0.851, 0.761, 0.55 * fadeIn));
            wg.addColorStop(1, Qt.alpha(Theme.vermLit, 0));
            ctx.beginPath();
            ctx.moveTo(bx, wy0);
            ctx.lineTo(bx, wy0 + host.wickDir * wl);
            ctx.strokeStyle = wg;
            ctx.lineWidth = 1.1 * S;
            ctx.lineCap = "round";
            ctx.stroke();
            bead(ctx, bx, by, r, settling ? (1 - q) * 0.3 : 0, 0);
            return;
        }

        if (f === "tick") {
            const rx = 5.5 * S * (settling ? (0.75 + 0.25 * e) : 1);
            const ry = 3.1 * S;
            ctx.save();
            ctx.translate(bx, by);
            ctx.scale(rx / ry, 1);
            const tg = ctx.createRadialGradient(-ry * 0.3, -ry * 0.35, 0, 0, 0, ry);
            tg.addColorStop(0, Theme.flameInk);
            tg.addColorStop(0.55, Theme.vermLit);
            tg.addColorStop(0.92, Theme.verm);
            tg.addColorStop(1, Theme.flameEmber);
            ctx.beginPath();
            ctx.arc(0, 0, ry, 0, 7);
            ctx.fillStyle = tg;
            ctx.globalAlpha = Math.max(0.25, fadeIn);
            ctx.fill();
            ctx.restore();
            ctx.beginPath();
            ctx.ellipse(bx - rx * 0.55, by - ry * 0.75, rx * 0.55, ry * 0.4);
            ctx.fillStyle = Qt.rgba(1, 0.965, 0.941, 0.55 * fadeIn);
            ctx.fill();
            return;
        }

        if (f === "rowseam") {
            const sh = 18 * S * (settling ? (0.6 + 0.4 * e) : 1);
            const sw = 4.2 * S;
            const sg3 = ctx.createLinearGradient(0, by - sh / 2, 0, by + sh / 2);
            sg3.addColorStop(0, Qt.alpha(Theme.vermLit, 0.92));
            sg3.addColorStop(0.5, Theme.flameInk);
            sg3.addColorStop(1, Qt.alpha(Theme.vermLit, 0.92));
            ctx.beginPath();
            ctx.roundedRect(bx - sw / 2, by - sh / 2, sw, sh, sw / 2, sw / 2);
            ctx.fillStyle = sg3;
            ctx.globalAlpha = Math.max(0.85, fadeIn);
            ctx.fill();
            ctx.beginPath();
            ctx.ellipse(bx - sw * 0.26, by - sh * 0.3, sw * 0.28, sh * 0.18);
            ctx.fillStyle = Qt.rgba(1, 0.965, 0.941, 0.6);
            ctx.fill();
            ctx.globalAlpha = 1;
            if (fadeIn < 0.7)
                bead(ctx, bx, by, 2.6 * S * (1 - fadeIn), 0, 0, 1 - fadeIn * 1.3);
            return;
        }

        if (f === "ring") {
            const R = (baseR + 6 * S) + 5 * S * host.smoothstep(fadeIn) * e;
            ctx.globalAlpha = 1;
            ctx.beginPath();
            ctx.arc(bx, by, Math.max(2 * S, R), 0, 7);
            ctx.strokeStyle = Theme.vermLit;
            ctx.lineWidth = Math.max(1.6 * S, (7 - 4.8 * fadeIn) * S);
            ctx.stroke();
            ctx.beginPath();
            ctx.arc(bx, by, Math.max(2 * S, R), -1.2, 0.4);
            ctx.strokeStyle = Qt.rgba(1, 0.851, 0.761, 0.7 * fadeIn);
            ctx.lineWidth = 1.4 * S;
            ctx.stroke();
            if (fadeIn < 0.6)
                bead(ctx, bx, by, baseR * (1 - fadeIn), 0, 0, 1 - fadeIn * 1.5);
            return;
        }

        const land = settling ? (0.7 + 0.3 * e) : 1;
        const breathe = (f === "rest") ? canvas.breathe : 1;
        const r = baseR * breathe * land * (f === "dock" ? host.heatScale : 1);
        bead(ctx, bx, by, r, settling ? (1 - q) * 0.4 : 0, host.flightAng);
    }

    /**
     * The blur layer allocates an FBO the size of the whole pill; while the bead
     * is hidden (wallpaper strip, toast, plain hover) that's pure GPU tax on an
     * empty canvas, so the layer only exists while something is drawn or fading.
     */
    layer.enabled: opacity > 0.001 || host.busy
    layer.effect: MultiEffect {
        blurEnabled: true
        blur: 0.34
        blurMax: 8
    }
}
