pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import qs.services
import qs.components.icons

/**
 * Lock-screen profile block: the current user's avatar over their username,
 * sitting directly above the password capsule.
 *
 * The avatar resolves from the standard freedesktop user-icon locations in
 * order (XDG ~/.face, ~/Pictures/.face, then the AccountsService icon for the
 * user) so it works across distros and desktop environments; when none of them
 * exist it falls back to a person glyph. The picture is clipped to the tile's
 * circle with the same mask treatment the media cover uses, and a soft shadow
 * keeps it readable over the blurred backdrop.
 */
Item {
    id: profile

    property real s: 1.1
    property string user: ""

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
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: avatarMask
            }
        }

        // Round clip source for the avatar image.
        Item {
            id: avatarMask

            anchors.fill: parent
            visible: false
            layer.enabled: true

            Rectangle {
                anchors.fill: parent
                radius: width / 2
            }
        }

        /**
         * Border ring in the capsule's own surface color, so the avatar reads
         * as one piece with the password capsule sitting beneath it.
         */
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "transparent"
            border.width: 2 * profile.s
            border.color: Theme.capsule
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

        text: profile.user

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
