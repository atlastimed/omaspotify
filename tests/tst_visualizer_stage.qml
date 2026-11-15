pragma ComponentBehavior: Bound

import QtQuick
import QtTest

import ".." as Plugin

TestCase {
  id: testCase
  name: "VisualizerStage"

  Component {
    id: stageComponent

    Plugin.VisualizerStage {
      width: 320
      height: 180
      bandCount: 4
      // Driven by hand here, one frame at a time.
      visible: false
    }
  }

  function test_aHitLandsQuicklyAndFallsSlowly() {
    var stage = createTemporaryObject(stageComponent, testCase)
    verify(stage)
    stage.running = true
    stage.levels = [1, 0.5, 0, 0]
    stage.advance(1 / 60)
    verify(stage.shown[0] > 0.4, "one frame in, a full hit showed only " + stage.shown[0])
    for (var i = 0; i < 6; i++) stage.advance(1 / 60)
    verify(stage.shown[0] > 0.95)
    fuzzyCompare(stage.shown[1], 0.5, 0.03)
    stage.levels = [0, 0, 0, 0]
    stage.advance(1 / 60)
    verify(stage.shown[0] > 0.8, "it dropped to " + stage.shown[0] + " in one frame")
  }

  function test_capsHangAboveAFallingBar() {
    var stage = createTemporaryObject(stageComponent, testCase)
    stage.running = true
    stage.levels = [1, 0, 0, 0]
    for (var i = 0; i < 12; i++) stage.advance(1 / 60)
    stage.levels = [0, 0, 0, 0]
    for (i = 0; i < 12; i++) stage.advance(1 / 60)
    verify(stage.held[0] > stage.shown[0] + 0.2,
      "cap " + stage.held[0] + " over bar " + stage.shown[0])
    verify(stage.held[0] < 1)
  }

  function test_sensitivityScalesAndNeverOverflows() {
    var stage = createTemporaryObject(stageComponent, testCase)
    stage.running = true
    stage.sensitivity = 1.9
    stage.levels = [0.9, 0.2, 0, 0]
    for (var i = 0; i < 30; i++) stage.advance(1 / 60)
    verify(stage.shown[0] <= 1)
    fuzzyCompare(stage.shown[1], 0.38, 0.03)
  }

  function test_fewerLevelsThanBandsLeavesTheRestAtRest() {
    var stage = createTemporaryObject(stageComponent, testCase)
    stage.running = true
    stage.levels = [1]
    for (var i = 0; i < 10; i++) stage.advance(1 / 60)
    compare(stage.shown.length, 4)
    compare(stage.shown[3], 0)
  }

  // Nothing is drawn, and no frame asked for, once the picture has come to rest.
  function test_itComesToRestAndStopsTheClock() {
    var stage = createTemporaryObject(stageComponent, testCase)
    stage.running = true
    stage.levels = [1, 1, 1, 1]
    for (var i = 0; i < 10; i++) stage.advance(1 / 60)
    verify(!stage.settled)
    verify(stage.clock > 0)
    verify(stage.bass > 0.9)
    stage.running = false
    for (i = 0; i < 400 && !stage.settled; i++) stage.advance(1 / 60)
    verify(stage.settled, "still moving after " + i + " frames")
    compare(stage.shown[0], 0)
    compare(stage.held[0], 0)
    var stopped = stage.clock
    stage.advance(1 / 60)
    compare(stage.clock, stopped)
    stage.running = true
    verify(!stage.settled, "starting again must wake it")
  }

  function test_anUnknownStyleDrawsAsBars() {
    var stage = createTemporaryObject(stageComponent, testCase)
    stage.style = "lasers"
    compare(stage.shaderStyle, "bars")
    stage.style = "halo"
    compare(stage.shaderStyle, "halo")
  }
}
