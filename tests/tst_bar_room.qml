pragma ComponentBehavior: Bound

import QtQuick
import QtTest

import ".." as Plugin

TestCase {
  id: testCase
  name: "BarRoom"
  when: windowShown
  width: 400
  height: 40

  Component {
    id: holderComponent

    Item {
      id: holder
      width: 120
      property alias room: room

      Plugin.BarRoom {
        id: room
        widget: holder
      }
    }
  }

  Loader {
    id: loader
    active: false
    sourceComponent: holderComponent
  }

  // The bar unloads a widget whenever it rebuilds, often with a measure queued.
  // Unloading takes the item's functions away before the item itself goes.
  function test_measureQueuedBeforeUnloadingNeverRuns() {
    failOnWarning(/is not a function/)
    for (var i = 0; i < 5; i++) {
      loader.active = true
      verify(loader.item)
      loader.item.room.schedule()
      loader.active = false
      wait(20)
    }
  }

  function test_withoutABarItStepsAside() {
    var holder = createTemporaryObject(holderComponent, testCase)
    verify(holder)
    wait(20)
    compare(holder.room.allowance, Infinity)
  }
}
