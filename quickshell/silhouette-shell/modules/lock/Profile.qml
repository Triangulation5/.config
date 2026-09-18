pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import qs.services
import qs.components.icons

/**
 * Lock-screen profile block: the current user's avatar over their real name,
 * sitting directly above the password capsule.
 *
 * The avatar resolves from the standard freedesktop user-icon locations in
 * order (XDG ~/.face, ~/Pictures/.face, then the AccountsService icon for the
 * user) so it works across distros and desktop environments; when none of them
 * exist it falls back to a person glyph. The picture is clipped to the tile's
 * circle with the same mask treatment the media cover uses, and a soft shadow
 * keeps it readable over the blurred backdrop.
 *
 * The label shows the user's real name instead of the login name: the GECOS
 * field from /etc/passwd (first comma-separated part), falling back to the
 * login name when no real name is set. The AccountsService RealName would be
 * the canonical source, but its store is root-only, so /etc/passwd (world
 * readable) is the reliable pick from the user session. PAM still
 * authenticates against `user`, so `user` stays the login name and only the
 * display text switches to the real name.
 */
Item {
    id: profile

    property real s: 1.1
    property string user: ""

    /**
     * The user's display name: the GECOS field of their /etc/passwd entry, or
     * the login name when none is set. Read once per lock via a blockLoading
     * FileView, so it never blocks the reveal with a process spawn.
     */
    readonly property string realName: {
        if (profile.user.length === 0)
            return "";

        var lines = passwdFile.text().split("\n");
        var prefix = profile.user + ":";
        for (var i = 0; i < lines.length; i++) {
            if (lines[i].indexOf(prefix) !== 0)
                continue;
            var fields = lines[i].split(":");
            var gecos = fields.length > 4 ? fields[4] : "";
            var name = gecos.split(",")[0].trim();
            return name.length > 0 ? name : profile.user;
        }
        return profile.user;
    }

    FileView {
        id: passwdFile
        path: "/etc/passwd"
        blockLoading: true
        printErrors: false
    }

    readonly property real avatarSize: Flags.lockAvatarSize * s

    width: avatarSize
    height: avatarSize + 14 * s + nameText.implicitHeight

    readonly property var avatarSources: {
        var list = [];
        if (user.length === 0)
            return list;
        var home = Quickshell.env("HOME") || "";
        if (home.length > 0) {
            list.push("file://" + home + "/.face");
            list.push("file://" + home + "/Pictures/.face");
        }
        list.push("file:///var/lib/AccountsService/icons/" + user);
        return list;
    }

    onUserChanged: avatarImg.refresh()

    Component.onCompleted: avatarImg.refresh()

    /**
     * Existence probe for the avatar candidates, walked in order on the load
     * signals. The Image is never handed a path that is not there: an Image
     * pointed at a missing file logs a QML warning of its own ("Cannot open:
     * ..."), and having no avatar at all is the common case, so the probe is
     * what keeps the lock-screen log quiet. `printErrors: false` silences the
     * probe's own read failures, which are the expected outcome here.
     *
     * Only the load of the candidate currently being probed is honoured (a
     * superseded read that lands late must not hand the Image the wrong file
     * or skip a candidate), which is what the `reading` comparison is for.
     */
    FileView {
        id: avatarProbe
        printErrors: false

        /** Plain filesystem path of the candidate being read right now. */
        readonly property string reading: avatarImg.probedUrl.replace(/^file:\/\//, "")

        onLoaded: if (String(path) === reading) avatarImg.source = avatarImg.probedUrl
        onLoadFailed: if (String(path) === reading) Qt.callLater(avatarImg.probeNext)
    }

    Rectangle {
        id: tile

        width: profile.avatarSize
        height: width
        radius: width / 2

        color: Theme.capsule

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.rgba(0, 0, 0, 0.45)
            shadowBlur: 1.2
            shadowVerticalOffset: 2
        }

        Image {
            id: avatarImg

            anchors.fill: parent
            anchors.margins: 1

            fillMode: Image.PreserveAspectCrop
            smooth: true
            mipmap: true
            cache: false
            asynchronous: true

            source: ""
            visible: status === Image.Ready

            /** Index into `avatarSources` of the candidate being probed. */
            property int srcIndex: 0
            /** `file://` URL of that candidate, or "" when the list ran out. */
            property string probedUrl: ""

            function refresh() {
                srcIndex = 0;
                probeCandidate();
            }

            /**
             * Hand the candidate at `srcIndex` to the probe; nothing reaches the
             * Image until the probe has actually read it. The source is left
             * alone (rather than cleared) so a re-probe cannot flash the fallback
             * glyph over an avatar that is still valid; when the list runs out
             * the source is dropped for real and the glyph takes over.
             *
             * A candidate that is already the probe's path — the ordinary
             * re-lock case — is re-read with reload() rather than re-assigned,
             * because assigning the same path again is a no-op and would leave
             * the walk with no signal to answer. The step to the next candidate
             * is deferred through Qt.callLater: jumping straight on from inside
             * the failure signal starts the next read before Quickshell has torn
             * the failed one down, which it logs about as a dropped operation.
             */
            function probeCandidate() {
                var list = profile.avatarSources;
                if (srcIndex >= list.length) {
                    probedUrl = "";
                    source = "";
                    return;
                }
                probedUrl = String(list[srcIndex]);
                var plain = probedUrl.replace(/^file:\/\//, "");
                if (avatarProbe.path === plain)
                    avatarProbe.reload();
                else
                    avatarProbe.path = plain;
            }

            /** The probe could not read this candidate: walk to the next one,
             *  and leave the Image empty (falling back to the glyph) at the end. */
            function probeNext() {
                srcIndex++;
                probeCandidate();
            }

            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: avatarMask
            }
        }

        Item {
            id: avatarMask

            anchors.fill: avatarImg
            visible: false

            Rectangle {
                anchors.fill: parent
                radius: width / 2
            }
        }

        /**
         * Border ring in the same hairline treatment as the password capsule
         * beneath it, so the avatar reads as one piece with the capsule.
         */
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "transparent"
            border.width: 1
            border.color: Theme.capsuleBorder
        }

        GlyphIcon {
            id: fallback

            anchors.fill: parent
            anchors.margins: 24 * profile.s

            name: "user"
            color: Theme.dim
            stroke: 1.6

            visible: !avatarImg.visible
        }
    }

    Text {
        id: nameText

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: tile.bottom
        anchors.topMargin: 12 * profile.s

        text: profile.realName

        color: Theme.cream
        opacity: 0.85

        font.family: Theme.font
        font.weight: 600
        font.pixelSize: 12 * profile.s
        font.letterSpacing: 3.2 * profile.s
        font.capitalization: Font.AllUppercase

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.rgba(0, 0, 0, 0.45)
            shadowBlur: 0.6
            shadowVerticalOffset: 1
        }
    }
}
