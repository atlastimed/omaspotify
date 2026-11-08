pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons

// The panel's shortcut hint. Pages live in their own files, so this takes the
// panel explicitly instead of reading it from the surrounding scope.
ShortcutHint {
  property var panel: null
  property string region: ""
  property string action: ""

  ctrlHeld: panel ? panel.hintCtrlHeld : false
  shiftHeld: panel ? panel.hintShiftHeld : false
  altHeld: panel ? panel.hintAltHeld : false
  active: panel ? panel.shortcutHintsActive : false
  foreground: panel ? panel.foreground : Commons.Color.foreground
  accent: panel ? panel.accent : Commons.Color.accent
  navHint: panel && region && action && panel.shortcutHintsActive
    ? panel.navHintFor(region, action) : ""
}
