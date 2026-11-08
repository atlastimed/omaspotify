import QtQuick
import Quickshell.Io

import "Api.js" as Api

// Artwork kept on disk by source url, fetched in small batches. Rows read through
// artworkFor(), which points at the kept copy only once it is really there.
Item {
  id: root

  visible: false
  width: 0
  height: 0

  property string directory: ""
  property bool wanted: false
  // The rows that always come first once a fetch settles.
  property var priorityItems: []

  property var cached: ({})
  property bool scanned: false
  property var queue: []
  property var namesOnDisk: ({})
  property var lastItems: []
  // Failed downloads are not retried until the next launch.
  property var failed: ({})
  readonly property int fileLimit: 3000

  // A zero-byte file is a download that never finished.
  readonly property string scanScript: 'mkdir -p "$1" && chmod 700 "$1" && cd "$1" || exit 0\n'
    + 'find . -maxdepth 1 -type f -size 0 -delete\n'
    + 'ls -1t | tail -n +"$(($2 + 1))" | while IFS= read -r name; do rm -f -- "$name"; done\n'
    + 'ls -1\n'

  onWantedChanged: if (wanted) keep(priorityItems)

  function artworkFor(url) {
    var text = String(url || "")
    if (!text) return ""
    return cached[text] ? "file://" + directory + "/" + Api.artworkCacheName(text) : text
  }

  function scan() {
    if (!directory || scanProcess.running) return
    scanProcess.command = ["/usr/bin/sh", "-c", scanScript, "sh", directory, String(fileLimit)]
    scanProcess.running = true
  }

  function noteOnDisk(listing) {
    var names = ({})
    var rows = String(listing || "").split("\n")
    for (var i = 0; i < rows.length; i++) {
      var name = rows[i].trim()
      if (name) names[name] = true
    }
    namesOnDisk = names
    scanned = true
    if (queue.length > 0) {
      var known = Api.shallowCopy(cached)
      var nextFailed = Api.shallowCopy(failed)
      for (var j = 0; j < queue.length; j++) {
        if (names[Api.artworkCacheName(queue[j])]) known[queue[j]] = true
        else nextFailed[queue[j]] = true
      }
      cached = known
      failed = nextFailed
      queue = []
    }
    // Keep going: the priority rows first, then whatever list last asked.
    var last = lastItems
    keep(priorityItems)
    if (!fetchProcess.running) keep(last)
  }

  function keep(items) {
    if (!wanted || !scanned) return
    lastItems = Array.isArray(items) ? items : []
    var wanted = Api.artworkUrls(lastItems, cached)
    var known = null
    var missing = []
    for (var i = 0; i < wanted.length; i++) {
      if (namesOnDisk[Api.artworkCacheName(wanted[i])]) {
        if (!known) known = Api.shallowCopy(cached)
        known[wanted[i]] = true
      } else if (!failed[wanted[i]]) missing.push(wanted[i])
    }
    if (known) cached = known
    if (missing.length === 0 || fetchProcess.running || scanProcess.running) return

    queue = missing.slice(0, 200)
    var args = ["--silent", "--fail", "--parallel", "--parallel-max", "6",
      "--max-time", "20", "--max-filesize", "10485760", "--remove-on-error",
      "--create-dirs", "--proto", "=https", "--proto-redir", "=https"]
    for (var j = 0; j < queue.length; j++) {
      args.push("-o")
      args.push(directory + "/" + Api.artworkCacheName(queue[j]))
      args.push(queue[j])
    }
    fetchProcess.command = ["/usr/bin/curl"].concat(args)
    fetchProcess.running = true
  }

  // Part of signing out: the covers of a library say what is in it.
  function clear() {
    if (fetchProcess.running) fetchProcess.running = false
    cached = ({})
    namesOnDisk = ({})
    queue = []
    lastItems = []
    failed = ({})
    if (!directory || clearProcess.running) return
    clearProcess.command = ["/usr/bin/sh", "-c",
      'rm -rf -- "$1" && mkdir -p "$1" && chmod 700 "$1"', "sh", directory]
    clearProcess.running = true
  }

  Process {
    id: scanProcess
    stdout: StdioCollector {
      onStreamFinished: root.noteOnDisk(text)
    }
  }

  // Which downloads landed is read back from disk, not assumed from the exit code.
  Process {
    id: fetchProcess
    onRunningChanged: if (!running) Qt.callLater(function() {
      if (root && root.queue.length > 0 && !fetchProcess.running) root.scan()
    })
  }

  Process {
    id: clearProcess
  }
}
