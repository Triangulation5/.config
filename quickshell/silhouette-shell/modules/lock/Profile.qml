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

    readonly property real avatarSize: 120 * s

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

            property int srcIndex: 0

            function refresh() {
                srcIndex = 0;
                source = profile.avatarSources.length > 0 ? profile.avatarSources[0] : "";
            }

            onStatusChanged: {
                if (status === Image.Error && srcIndex < profile.avatarSources.length - 1) {
                    srcIndex++;
                    source = profile.avatarSources[srcIndex];
                }
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
