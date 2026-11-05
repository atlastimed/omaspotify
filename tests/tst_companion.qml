import QtQuick
import QtTest
import "../Companion.js" as Companion

TestCase {
  name: "CompanionProtocol"
  function test_commandsAreExplicitAndBounded() {
    compare(Companion.command('{"v":1,"action":"seek","value":12}').value, 12)
    compare(Companion.command('{"v":1,"action":"volume","value":2}'), null)
    compare(Companion.command('{"v":1,"action":"seek","value":"12"}'), null)
    compare(Companion.command('{"v":2,"action":"playPause"}'), null)
    compare(Companion.command('{"v":1,"action":"logout"}'), null)
    compare(Companion.command('[]'), null)
    compare(Companion.command('not json'), null)
    compare(Companion.command(' '.repeat(4097)), null)
  }
  function test_snapshotContainsOnlyPublicBoundedData() {
    var result = Companion.snapshot({title: "x".repeat(9000), accessToken: "secret",
      queue: [{name: "Song", subtitle: "Artist", uri: "spotify:track:x", token: "secret"}],
      devices: [{id: "device", name: "Desk", active: true, accessToken: "secret"}],
      volume: NaN, positionSeconds: Infinity, lengthSeconds: -1})
    compare(result.v, 1)
    compare(result.title.length, 512)
    verify(JSON.stringify(result).indexOf("secret") < 0)
    compare(result.volume, 0)
    compare(result.position, 0)
    compare(result.length, 0)
    compare(result.queue[0].title, "Song")
    compare(result.devices[0].name, "Desk")
  }
  function test_artworkAndCollectionsAreBounded() {
    compare(Companion.artwork("file:///etc/passwd"), "")
    compare(Companion.artwork("https://attacker.invalid/image"), "")
    compare(Companion.artwork("https://i.scdn.co/image/abc"), "https://i.scdn.co/image/abc")
    var result = Companion.snapshot({queue: new Array(1000).fill({name:"Song"}),
      devices: new Array(1000).fill({id:"a"})})
    compare(result.queue.length, 10)
    compare(result.devices.length, 32)
  }
}
