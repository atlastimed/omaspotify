import QtQuick
import QtTest

import ".."

TestCase {
  name: "ShortcutModifiers"

  ShortcutModifiers {
    id: modifiers
  }

  function test_flagsAfterEvent_tracksTheModifierKeysThemselves() {
    var held = modifiers.flagsAfterEvent(Qt.ControlModifier, true, 0, Qt.Key_Control)
    compare(held, Qt.ControlModifier)
    // A letter typed with it changes nothing, pressed or released.
    compare(modifiers.flagsAfterEvent(Qt.ControlModifier, true, held, Qt.Key_S), held)
    compare(modifiers.flagsAfterEvent(0, false, held, Qt.Key_S), held)
    compare(modifiers.flagsAfterEvent(0, false, held, Qt.Key_Control), 0)
    // A chord whose modifier key was never seen leaves nothing held.
    compare(modifiers.flagsAfterEvent(Qt.ControlModifier, true, 0, Qt.Key_A), 0)
  }

  function test_flagFor_mapsEachHintModifierKey() {
    compare(modifiers.flagFor(Qt.Key_Control), Qt.ControlModifier)
    compare(modifiers.flagFor(Qt.Key_Shift), Qt.ShiftModifier)
    compare(modifiers.flagFor(Qt.Key_Alt), Qt.AltModifier)
    compare(modifiers.flagFor(Qt.Key_AltGr), Qt.AltModifier)
  }

  function test_flagFor_isZeroForKeysThatDoNotShowHints() {
    compare(modifiers.flagFor(Qt.Key_Meta), 0)
    compare(modifiers.flagFor(Qt.Key_A), 0)
  }

  function test_isHintModifierKey_acceptsOnlyKeysThatRevealHints() {
    verify(modifiers.isHintModifierKey(Qt.Key_Control))
    verify(modifiers.isHintModifierKey(Qt.Key_Shift))
    verify(modifiers.isHintModifierKey(Qt.Key_Alt))
    verify(modifiers.isHintModifierKey(Qt.Key_AltGr))
    verify(!modifiers.isHintModifierKey(Qt.Key_Meta))
    verify(!modifiers.isHintModifierKey(Qt.Key_A))
  }

  // Meta is a modifier for the purpose of "did the user press a real key",
  // even though holding it reveals no hints.
  function test_isModifierKey_alsoCountsMeta() {
    verify(modifiers.isModifierKey(Qt.Key_Meta))
    verify(modifiers.isModifierKey(Qt.Key_Control))
    verify(!modifiers.isModifierKey(Qt.Key_A))
  }

  function test_flagsAfterEvent_keepsHeldModifiersOnPlainKeyRelease() {
    var held = Qt.ControlModifier
    compare(modifiers.flagsAfterEvent(0, false, held, Qt.Key_A), held)
  }

  function test_flagsAfterEvent_clearsTheReleasedModifier() {
    compare(modifiers.flagsAfterEvent(Qt.ControlModifier, false,
      Qt.ControlModifier, Qt.Key_Control), 0)
  }

  function test_flagsAfterEvent_addsThePressedModifier() {
    compare(modifiers.flagsAfterEvent(0, true, 0, Qt.Key_Shift),
      Qt.ShiftModifier)
  }
}
