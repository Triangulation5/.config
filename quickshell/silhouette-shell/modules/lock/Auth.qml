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

    // Retry once if fingerprint initialization immediately fails.
    property bool retryingWithoutFingerprint: false

    function clearState() {
        pendingPassword = ""
        lastError = ""
        statusMessage = ""
        retryingWithoutFingerprint = false
    }

    function submit(password) {
        if (pam.active)
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
                        // Ignore fingerprint availability errors.
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
            auth.failed()
        }
    }
}
