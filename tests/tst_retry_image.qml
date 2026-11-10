import QtQuick
import QtTest

import ".."

TestCase {
  id: testCase

  name: "RetryImage"

  RetryImage {
    id: artwork
  }

  function cleanup() {
    artwork.requestedSource = ""
    artwork.retryAttempt = 0
    artwork.retryToken = ""
  }

  function test_onlyRemoteArtworkIsRetried() {
    verify(artwork.canRetry("https://i.scdn.co/image/example"))
    verify(artwork.canRetry("http://localhost/cover"))
    verify(!artwork.canRetry("file:///tmp/cover.png"))
    verify(!artwork.canRetry("data:image/png;base64,AAAA"))
    verify(!artwork.canRetry(""))
  }

  function test_retryUrlPreservesQueryAndFragment() {
    compare(artwork.retryUrl("https://i.scdn.co/image/example", "one"),
      "https://i.scdn.co/image/example?omarchy_art_retry=one")
    compare(artwork.retryUrl("https://example.test/cover?size=large#art", "two words"),
      "https://example.test/cover?size=large&omarchy_art_retry=two%20words#art")
    compare(artwork.retryUrl("file:///tmp/cover.png", "one"),
      "file:///tmp/cover.png")
  }

  SignalSpy {
    id: missing
    target: artwork
    signalName: "localSourceMissing"
  }

  function test_aKeptCopyThatHasGoneIsReported() {
    missing.clear()
    // Nothing loads while hidden, and a test item is never shown.
    artwork.active = true
    artwork.requestedSource = "file:///nonexistent/omaspotify-test/cover.img"
    tryCompare(missing, "count", 1, 2000)
    // A remote failure is retried instead, and is nobody else's business.
    compare(artwork.retryAttempt, 0)
  }

  function test_backoffIsBounded() {
    artwork.retryAttempt = 1
    compare(artwork.retryDelayMs, 750)
    artwork.retryAttempt = 4
    compare(artwork.retryDelayMs, 6000)
    artwork.retryAttempt = 8
    compare(artwork.retryDelayMs, 15000)
  }

  function test_newArtworkClearsRetryState() {
    artwork.retryAttempt = 3
    artwork.retryToken = "old"
    artwork.requestedSource = "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg'/%3E"
    compare(artwork.retryAttempt, 0)
    compare(artwork.retryToken, "")
  }
}
