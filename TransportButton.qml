import QtQuick
import qs.Commons
import qs.Ui

// Transport glyphs have very different font advances and ink bounds
// (especially play/pause, shuffle and repeat). Give each one the same hit
// target and center its painted bounds so a Row produces an even rhythm.
Button {
  id: root

  property string glyphText: ""
  property real glyphSize: Style.font.icon
  property real controlSize: Style.space(30)
  // On, for modes like shuffle and repeat: accent glyph with a dot under it, so
  // the state is not carried by colour alone.
  property bool indicator: false

  width: controlSize
  height: controlSize
  horizontalPadding: 0
  verticalPadding: 0

  readonly property int renderedGlyphSize: Math.max(1, Math.round(glyphSize))
  readonly property real tightGlyphWidth: Math.max(1,
    glyphMetrics.tightBoundingRect.width)
  readonly property real tightGlyphHeight: Math.max(1,
    glyphMetrics.tightBoundingRect.height)

  TextMetrics {
    id: glyphMetrics
    font.family: root.fontFamily
    font.pixelSize: root.renderedGlyphSize
    text: root.glyphText
  }

  Text {
    id: glyph
    anchors.centerIn: parent
    anchors.horizontalCenterOffset: implicitWidth / 2
      - (glyphMetrics.tightBoundingRect.x + root.tightGlyphWidth / 2)
    anchors.verticalCenterOffset: implicitHeight / 2
      - (baselineOffset + glyphMetrics.tightBoundingRect.y
        + root.tightGlyphHeight / 2) - (root.indicator ? Style.space(2) : 0)
    text: root.glyphText
    textFormat: Text.PlainText
    font.family: root.fontFamily
    font.pixelSize: root.renderedGlyphSize
    renderType: Text.NativeRendering
    color: root.indicator ? root.accent
      : (root.selected ? Style.selectedStateColor(root.foreground, root.accent)
        : root.foreground)
    opacity: root.enabled ? 1 : 0.45
  }

  Rectangle {
    visible: root.indicator
    width: Math.max(3, Style.space(3))
    height: width
    radius: width / 2
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Style.space(4)
    color: root.accent
  }
}
