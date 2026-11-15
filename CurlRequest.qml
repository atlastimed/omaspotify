pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io

// Qt's XMLHttpRequest sends DELETE without its body, and Spotify only takes a
// playlist removal as one. This stands in for it with the same few members the
// transport uses, and hands the token to curl on stdin, never on its command line.
Item {
  id: root

  visible: false

  property int readyState: 0
  property int status: 0
  property string responseText: ""
  property string retryAfter: ""
  property var onreadystatechange: null

  property string method: "GET"
  property string url: ""
  property var headers: []
  property string config: ""
  property bool finished: false
  property string executable: "curl"

  function open(verb, target) {
    method = String(verb || "GET")
    url = String(target || "")
    headers = []
  }

  function setRequestHeader(name, value) {
    headers.push(String(name) + ": " + String(value))
  }

  function getResponseHeader(name) {
    return String(name || "").toLowerCase() === "retry-after" && retryAfter
      ? retryAfter : null
  }

  // curl reads a quoted value with backslash escapes.
  function quoted(value) {
    return '"' + String(value).replace(/\\/g, "\\\\").replace(/"/g, '\\"')
      .replace(/\n/g, "\\n").replace(/\r/g, "\\r") + '"'
  }

  function send(body) {
    var lines = ["url = " + quoted(url), "request = " + quoted(method),
      "proto = \"=https\"", "silent", "max-time = 20",
      "write-out = \"\\n%{http_code} %header{retry-after}\""]
    for (var i = 0; i < headers.length; i++) lines.push("header = " + quoted(headers[i]))
    if (body !== undefined && body !== null) lines.push("data-binary = " + quoted(body))
    config = lines.join("\n") + "\n"
    curl.running = true
  }

  function abort() {
    if (finished) return
    finished = true
    config = ""
    if (curl.running) curl.running = false
    destroy(1000)
  }

  // The answer is the body, then a last line holding the status and Retry-After.
  function finish(output) {
    if (finished) return
    finished = true
    config = ""
    var text = String(output || "")
    var cut = text.lastIndexOf("\n")
    var tail = (cut >= 0 ? text.slice(cut + 1) : "").trim().split(" ")
    status = Math.floor(Number(tail[0])) || 0
    retryAfter = tail.length > 1 ? String(tail[1]) : ""
    responseText = cut >= 0 ? text.slice(0, cut) : ""
    readyState = 4
    if (typeof onreadystatechange === "function") onreadystatechange()
    destroy(1000)
  }

  Process {
    id: curl
    // -q first, so a personal curlrc cannot redirect or log the request.
    command: [root.executable, "-q", "--config", "-"]
    stdinEnabled: true
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.finish(text)
    }
    stderr: StdioCollector { waitForEnd: true }
    onStarted: {
      write(root.config)
      root.config = ""
      stdinEnabled = false
    }
    onExited: function(exitCode) {
      // A curl that never ran, or died, still has to end the request.
      if (exitCode !== 0) Qt.callLater(function() { if (root) root.finish("") })
    }
  }
}
