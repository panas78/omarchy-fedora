import QtQuick 2.0
import SddmComponents 2.0

// omarchy-plus: stock Omarchy greeter + session/username choice.
//
// Prototype opt-in for converted Fedora machines (see
// fedora/sddm-omarchy-plus/README.md). The centre of the screen mirrors
// upstream default/sddm/omarchy/Main.qml (logo, lock/entry art, password
// bullets in JetBrainsMono Nerd Font) so it still reads as the Omarchy login.
// The additions are an editable username field and a session picker.
//
// Kept to the stock theme's imports (QtQuick 2.0 + SddmComponents 2.0): the
// SDDM greeter is not guaranteed to load QtQuick.Controls, so the selector is
// built from plain QtQuick primitives. Inspired by
// xpusostomos/sddm-omarchy-plus, reimplemented here so the file is owned by
// this repo and tracks the stock theme.
//
// COLOUR NOTE: "#1a1b26" and "#ffffff" are the two literals omarchy-plymouth-set
// rewrites when it regenerates the *stock* theme. Because this theme is a
// separate file those substitutions do not reach here — edit them by hand to
// match a new desktop theme.
//
// SDDM 0.21 note: Qt.DisplayRole is NOT implemented on sessionModel (returns
// undefined); the name lives at Qt.UserRole + 4. The stock theme's uwsm scan
// reads DisplayRole and therefore never matches. We use the UserRole + 4 path
// so the uwsm session is genuinely preferred when nothing is remembered.
//
// Function-vs-binding note: a function is not reliably visible to a *child's*
// property binding in this Qt version, so the session label is computed as a
// root property (calling root-local helpers) and children bind to it.

Rectangle {
  id: root
  width: 640
  height: 520
  color: "#1a1b26"

  readonly property string mono: "JetBrainsMono Nerd Font"
  readonly property int sessionNameRole: Qt.UserRole + 4
  readonly property int fieldWidth: 286
  readonly property int fieldHeight: 48

  property bool loginFailed: false

  // First regular account, used to prefill the username when SDDM has no
  // remembered user. Captured via a probe so the binding survives until the
  // model is populated.
  property string firstUserName: ""

  // Session: honour SDDM's RememberLastSession; only prefer uwsm when SDDM has
  // no remembered session to restore.
  property int sessionIndex: sessionModel.lastIndex

  Repeater {
    model: userModel
    delegate: Item {
      width: 0; height: 0
      Component.onCompleted: if (index === 0) root.firstUserName = model.name
    }
  }

  // Hidden probe so the session count/label re-bind once SDDM populates the
  // model. rowCount()/data() are method calls and create no binding dependency;
  // a Repeater (not a hidden ListView, which never instantiates items) gives a
  // real count property to depend on.
  Repeater {
    id: sessionProbe
    model: sessionModel
    delegate: Item { width: 0; height: 0; visible: false }
  }

  readonly property int sessionCount: sessionProbe.count > 0 ? sessionProbe.count : sessionModel.rowCount()

  function sessionNameAt(i) {
    var n = sessionModel.data(sessionModel.index(i, 0), root.sessionNameRole)
    return (n === undefined || n === null) ? "" : n.toString()
  }

  readonly property string sessionLabel: {
    var total = root.sessionCount
    var i = root.sessionIndex
    if (total === 0 || i < 0 || i >= total)
      return "session"
    var n = sessionNameAt(i)
    return n === "" ? "session" : n
  }

  function doLogin() {
    sddm.login(username.text, password.text, root.sessionIndex)
  }

  Connections {
    target: sddm
    function onLoginFailed() {
      root.loginFailed = true
      password.text = ""
      password.focus = true
    }
    function onLoginSucceeded() {
      root.loginFailed = false
    }
  }

  // ---- session picker, top right -----------------------------------------
  Item {
    id: sessionPicker
    anchors.top: parent.top
    anchors.right: parent.right
    anchors.topMargin: 8
    anchors.rightMargin: 24
    width: sessionText.width
    height: sessionText.height
    z: 50

    KeyNavigation.tab: username

    Text {
      id: sessionText
      anchors.right: parent.right
      text: root.sessionLabel + " ▾"
      color: sessionMouse.containsMouse ? "#ffffff" : "#6b7280"
      font.family: root.mono
      font.pixelSize: 14
    }

    MouseArea {
      id: sessionMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: sessionList.visible = !sessionList.visible
    }

    Rectangle {
      id: sessionList
      visible: false
      anchors.top: parent.bottom
      anchors.topMargin: 6
      anchors.right: parent.right
      width: 280
      height: Math.min(root.sessionCount * 30 + 8, 220)
      color: root.color
      border.color: "#45475a"
      border.width: 1
      z: 60

      ListView {
        anchors.fill: parent
        anchors.margins: 4
        clip: true
        model: sessionModel
        delegate: Text {
          width: sessionList.width - 8
          height: 30
          verticalAlignment: Text.AlignVCenter
          elide: Text.ElideRight
          text: model.name
          color: (index === root.sessionIndex) ? "#f7768e"
               : sessionItemMouse.containsMouse ? "#ffffff" : "#9aa0b0"
          font.family: root.mono
          font.pixelSize: 14

          MouseArea {
            id: sessionItemMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              root.sessionIndex = index
              sessionList.visible = false
              password.focus = true
            }
          }
        }
      }
    }
  }

  // ---- main column --------------------------------------------------------
  Column {
    anchors.centerIn: parent
    spacing: 24

    Image {
      id: logo
      source: "logo.png"
      width: Math.min(sourceSize.width, root.width * 0.8)
      height: sourceSize.width > 0 ? Math.round(width * sourceSize.height / sourceSize.width) : 0
      fillMode: Image.PreserveAspectFit
      anchors.horizontalCenter: parent.horizontalCenter
    }

    // Username: editable, prefilled with the remembered user else the first
    // account. No icon: the theme ships no user glyph. The empty Item
    // width-matches the lock icon so this field lines up with the password box.
    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: 15

      Item { width: 34; height: 38 }

      Item {
        width: root.fieldWidth
        height: root.fieldHeight

        Image {
          anchors.centerIn: parent
          source: "entry.png"
        }

        TextInput {
          id: username
          anchors.fill: parent
          anchors.leftMargin: 20
          anchors.rightMargin: 20
          verticalAlignment: TextInput.AlignVCenter
          font.family: root.mono
          font.pixelSize: 20
          font.letterSpacing: 3
          color: "#9aa0b0"
          selectionColor: "#f7768e"
          selectedTextColor: root.color

          text: (userModel.lastUser !== "" && userModel.lastUser !== undefined)
                ? userModel.lastUser : root.firstUserName

          KeyNavigation.tab: password
          KeyNavigation.backtab: sessionPicker

          Keys.onPressed: {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              root.doLogin()
              event.accepted = true
            }
          }
        }
      }
    }

    // ---- password entry (stock) -------------------------------------------
    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: 15

      Image {
        source: root.loginFailed ? "lock-failed.png" : "lock.png"
        width: 34
        height: 38
        fillMode: Image.PreserveAspectFit
        anchors.verticalCenter: parent.verticalCenter
      }

      Item {
        width: entry.width
        height: entry.height

        Image {
          id: entry
          source: root.loginFailed ? "entry-failed.png" : "entry.png"
          anchors.centerIn: parent
        }

        Row {
          anchors.left: parent.left
          anchors.leftMargin: 20
          anchors.verticalCenter: parent.verticalCenter
          spacing: 5

          Repeater {
            model: Math.min(password.text.length, 21)

            Image {
              source: "bullet.png"
              width: 7
              height: 7
            }
          }
        }

        TextInput {
          id: password
          anchors.fill: parent
          anchors.leftMargin: 20
          anchors.rightMargin: 20
          verticalAlignment: TextInput.AlignVCenter
          echoMode: TextInput.Password
          font.family: root.mono
          font.pixelSize: 24
          font.letterSpacing: 5
          passwordCharacter: "\u2022"
          color: "transparent"
          selectionColor: "transparent"
          selectedTextColor: "transparent"
          cursorDelegate: Item {}
          focus: true

          onTextChanged: root.loginFailed = false

          Keys.onPressed: {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              root.doLogin()
              event.accepted = true
            }
          }
        }
      }
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: root.loginFailed ? "Login failed — try again"
                              : "Omarchy Plus — session choice enabled"
      color: root.loginFailed ? "#f7768e" : "#6b7280"
      font.family: root.mono
      font.pixelSize: 12
    }
  }

  Component.onCompleted: {
    // Only fall back to the uwsm session when SDDM has no remembered session.
    if (root.sessionIndex < 0) {
      for (var i = 0; i < root.sessionCount; i++) {
        if (sessionNameAt(i).indexOf("uwsm") !== -1) {
          root.sessionIndex = i
          break
        }
      }
    }
    password.forceActiveFocus()
  }
}
