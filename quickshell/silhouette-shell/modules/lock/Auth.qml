import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Pam
import qs.services

/**
 * PAM authentication for the lock. Submits the typed password through a
 * quickshell-lock PamContext, exposes failed/succeeded and the last error, and
 * retries the conversation once when a fingerprint reader fails to initialize so
 * a transient hiccup doesn't lock the user out.
 *
 * The retry lockout is the one piece of auth state that outlives the process: the
 * streak and the deadline it is waiting out are written to a small file beside the
 * shell's other state as they change, and read back when this item is built, so
 * restarting the shell lands mid-lockout instead of clearing it.
 *
 * Past the wait there is an escalation: once the streak reaches the configured
 * limit the lock ends the session instead of only making it wait — log out,
 * restart or shut down, or nothing at all. It is off by default, and both the
 * action and the limit are Lock Screen settings (`lockFailAction`,
 * `lockFailLimit`), so the lock never acts on its own until it is asked to.
 */

Item {
    id: auth

    property string user: ""

    readonly property bool authenticating: pam.active

    signal failed
    signal succeeded

    property string pendingPassword: ""
    property string lastError: ""
    property string statusMessage: ""

    /** Retry once if fingerprint initialization immediately fails. */
    property bool retryingWithoutFingerprint: false

    /**
     * AOSP-style retry lockout: after lockoutThreshold consecutive failures the
     * field locks for lockoutSeconds (doubling per repeat, capped), exactly like
     * the keyguard's device-policy gate. `lockedOut` disables the input and
     * `lockoutRemaining` ticks down live so the surface can show a countdown.
     */
    property int failedAttempts: 0
    property int lockoutThreshold: 5
    property int lockoutSeconds: 30
    property int lockoutMax: 600
    property bool lockedOut: false
    property int lockoutRemaining: 0

    /**
     * Escalation past the lockout. `escalateAction` mirrors the `lockFailAction`
     * flag ("none", "logout", "reboot" or "shutdown") and `escalateLimit` the
     * `lockFailLimit` one, floored at 1 so a zero can never turn every keystroke
     * into a session-ender.
     */
    readonly property string escalateAction: Flags.lockFailAction
    readonly property int escalateLimit: Math.max(1, Flags.lockFailLimit)

    /** Same fallback the rest of the shell's state uses: XDG_STATE_HOME, else ~/.local/state. */
    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/silhouette"

    function clearState() {
        pendingPassword = ""
        lastError = ""
        statusMessage = ""
        retryingWithoutFingerprint = false
        failedAttempts = 0
        lockedOut = false
        lockoutRemaining = 0
    }

    /** Count one real failure; crossing the threshold arms the lockout, and the
     * configured limit escalates to ending the session. */
    function recordFailure() {
        failedAttempts++
        if (failedAttempts >= lockoutThreshold && !lockedOut) {
            var repeat = failedAttempts - lockoutThreshold
            lockoutRemaining = Math.min(lockoutMax, lockoutSeconds * Math.pow(2, repeat))
            lockedOut = true
        }
        if (escalateAction !== "none" && failedAttempts >= escalateLimit)
            escalate()
        persistLockout()
    }

    /**
     * Run the configured end-of-session action, once per streak. The same calls
     * the power surface's tiles make — Hyprland's exit dispatch for a log out, and
     * systemd for the two power actions — and detached on purpose: the session
     * this surface belongs to is going away, so there is nobody left to reap a
     * child.
     *
     * The streak and its penalty are cleared as the action fires, both here and
     * on disk. The session is ending, so both have served their purpose, and the
     * next one must not inherit them: without this, a log out would leave
     * `failedAttempts` at the limit in the state file, and the first mistake after
     * logging back in would end the session again (and a stale deadline would keep
     * the new session's lock locked out). If the action cannot actually run, the
     * user is simply back at the lock with a full allowance.
     */
    function escalate() {
        var action = escalateAction
        if (action !== "logout" && action !== "reboot" && action !== "shutdown")
            return
        failedAttempts = 0
        lockedOut = false
        lockoutRemaining = 0
        if (action === "logout")
            Hyprland.dispatch("hl.dsp.exit()")
        else if (action === "reboot")
            Quickshell.execDetached(["systemctl", "reboot"])
        else
            Quickshell.execDetached(["systemctl", "poweroff"])
    }

    /** Successful auth clears the streak and any active lockout. */
    function clearLockout() {
        failedAttempts = 0
        lockedOut = false
        lockoutRemaining = 0
        persistLockout()
    }

    Timer {
        id: lockoutTick
        interval: 1000
        repeat: true
        running: auth.lockedOut
        onTriggered: {
            if (auth.lockoutRemaining > 1) {
                auth.lockoutRemaining--
            } else {
                auth.lockoutRemaining = 0
                auth.lockedOut = false
                /** The wait is served — drop the deadline so the file never reads as still locked. */
                auth.persistLockout()
            }
        }
    }

    function submit(password) {
        if (pam.active || lockedOut)
            return

        pendingPassword = password
        lastError = ""
        statusMessage = ""
        retryingWithoutFingerprint = false

        pam.start()
    }

    PamContext {
        id: pam

        config: "quickshell-lock"
        user: auth.user

        onResponseRequiredChanged: {
            if (!responseRequired)
                return

            if (auth.pendingPassword.length > 0)
                respond(auth.pendingPassword)
        }

        onPamMessage: {
            if (!message || message.length === 0)
                return

            if (messageIsError) {
                const fingerprintErrors = [
                    "fingerprint",
                    "fprintd",
                    "No fingerprint reader",
                    "No fingerprints enrolled",
                    "No device available",
                    "Device unavailable",
                    "Failed to claim fingerprint device"
                ]

                for (let i = 0; i < fingerprintErrors.length; ++i) {
                    if (message.toLowerCase().indexOf(fingerprintErrors[i].toLowerCase()) !== -1) {
                        /** Ignore fingerprint availability errors. */
                        return
                    }
                }

                auth.lastError = message
            } else {
                auth.statusMessage = message
            }
        }

        onCompleted: result => {
            auth.statusMessage = ""

            if (result === PamResult.Success) {
                auth.pendingPassword = ""
                auth.lastError = ""
                auth.retryingWithoutFingerprint = false
                auth.clearLockout()
                auth.succeeded()
                return
            }

            /**
             * Retry the PAM conversation once. This helps recover from
             * transient fingerprint initialization failures.
             */
            if (!auth.retryingWithoutFingerprint && auth.pendingPassword.length > 0) {
                auth.retryingWithoutFingerprint = true
                pam.start()
                return
            }

            auth.pendingPassword = ""
            auth.retryingWithoutFingerprint = false
            auth.recordFailure()
            auth.failed()
        }

        onError: {
            auth.statusMessage = ""

            if (!auth.retryingWithoutFingerprint && auth.pendingPassword.length > 0) {
                auth.retryingWithoutFingerprint = true
                pam.start()
                return
            }

            auth.pendingPassword = ""

            if (auth.lastError.length === 0)
                auth.lastError = "Authentication failed."

            auth.retryingWithoutFingerprint = false
            auth.recordFailure()
            auth.failed()
        }
    }

    /**
     * Read the persisted streak and deadline back. Both are stored rather than the
     * countdown alone: a remaining-seconds count would restart the full wait on
     * every launch, while an absolute deadline resumes the wait where it actually
     * is — it keeps running through a suspend, because the wall clock does. A
     * deadline further out than lockoutMax can only be stale or hand-edited state,
     * so it is dropped rather than honoured: believing it would lock the session
     * out again on every launch.
     */
    function restoreLockout() {
        var attempts = 0;
        var until = 0;
        try {
            var t = lockoutFile.text();
            if (t && t.trim().length > 0) {
                var saved = JSON.parse(t);
                attempts = Math.max(0, Number(saved.failedAttempts) || 0);
                until = Number(saved.lockoutUntil) || 0;
            }
        } catch (e) {
            attempts = 0;
            until = 0;
        }

        var now = Date.now();
        if (until - now > lockoutMax * 1000)
            until = 0;

        failedAttempts = attempts;
        if (until > now) {
            lockedOut = true;
            lockoutRemaining = Math.ceil((until - now) / 1000);
        } else {
            lockedOut = false;
            lockoutRemaining = 0;
        }
    }

    /**
     * Mirror the streak and the deadline to disk. Written on every failure and at
     * both ends of the wait, so the file is never further behind than one failed
     * attempt. This is continuity, not tamper-proofing: the file is the user's own,
     * and a hand edit still bypasses it — what it closes is the restart.
     */
    function persistLockout() {
        lockoutFile.setText(JSON.stringify({
            failedAttempts: failedAttempts,
            lockoutUntil: lockedOut ? Date.now() + lockoutRemaining * 1000 : 0
        }));
    }

    Component.onCompleted: restoreLockout()

    /**
     * The lockout's state file. Read synchronously at construction (blockLoading,
     * like the shell's other state) so the gate is armed before the first keystroke
     * can land. Never watched: this item is its only writer.
     */
    FileView {
        id: lockoutFile
        path: auth.stateDir + "/lock-auth.json"
        blockLoading: true
        atomicWrites: true
        printErrors: false

        onLoadFailed: function (error) {
            if (error === FileViewError.FileNotFound)
                lockoutFile.setText(JSON.stringify({ failedAttempts: 0, lockoutUntil: 0 }));
        }
    }
}
