import QtQuick

import "Api.js" as Api

// Shared modifier-key rules for the shortcut hints. The full player and the
// bar mini-player both track which modifiers are held, so the rules live here
// instead of being written out twice.
QtObject {
  function flagFor(key) {
    if (key === Qt.Key_Control) return Qt.ControlModifier
    if (key === Qt.Key_Shift) return Qt.ShiftModifier
    if (key === Qt.Key_Alt || key === Qt.Key_AltGr) return Qt.AltModifier
    return 0
  }

  function isHintModifierKey(key) {
    return key === Qt.Key_Control || key === Qt.Key_Shift
      || key === Qt.Key_Alt || key === Qt.Key_AltGr
  }

  // Meta counts as a modifier even though holding it reveals no hints.
  function isModifierKey(key) {
    return isHintModifierKey(key) || key === Qt.Key_Meta
  }

  function flagsAfterEvent(reportedFlags, pressed, previousFlags, key) {
    return Api.heldHintModifiers(previousFlags, reportedFlags, pressed, flagFor(key))
  }
}
