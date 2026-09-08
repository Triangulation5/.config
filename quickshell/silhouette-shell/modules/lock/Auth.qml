import QtQuick
import Quickshell.Services.Pam

/**
 * PAM authentication for the lock. Submits the typed password through a
 * quickshell-lock PamContext, exposes failed/succeeded and the last error, and
 * retries the conversation once when a fingerprint reader fails to initialize so
 * a transient hiccup doesn't lock the user out.
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

    function clearState() {
        pendingPassword = ""
        lastError = ""
        statusMessage = ""
        retryingWithoutFingerprint = false
        failedAttempts = 0
        lockedOut = false
        lockoutRemaining = 0
    }

    /** Count one real failure; crossing the threshold arms the lockout. */
    function recordFailure() {
        failedAttempts++
        if (failedAttempts >= lockoutThreshold && !lockedOut) {
            var repeat = failedAttempts - lockoutThreshold
            lockoutRemaining = Math.min(lockoutMax, lockoutSeconds * Math.pow(2, repeat))
            lockedOut = true
        }
    }

    /** Successful auth clears the streak and any active lockout. */
    function clearLockout() {
        failedAttempts = 0
        lockedOut = false
        lockoutRemaining = 0
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
}
