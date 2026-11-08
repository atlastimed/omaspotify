import QtQuick

// Every key chord the full player answers to. All the work happens in the panel.
Item {
  id: part

  property var panel: null

  Shortcut {
    sequence: "/"
    enabled: part.panel.searchBarVisible && !part.panel.shortcutsBlocked
      && !part.panel.textInputFocused()
    onActivated: {
      part.panel.latchShortcutMode(sequence)
      part.panel.activateSearch()
    }
  }
  Shortcut {
    sequence: "Ctrl+F"
    enabled: part.panel.searchBarVisible && !part.panel.shortcutsBlocked
      && !part.panel.searchFieldFocused
    onActivated: {
      part.panel.latchShortcutMode(sequence)
      part.panel.activateSearch()
    }
  }
  Shortcut {
    sequence: "C"
    enabled: !part.panel.shortcutsBlocked && !part.panel.textInputFocused()
    onActivated: {
      part.panel.latchShortcutMode(sequence)
      part.panel.openCurrentContextMenu()
    }
  }
  Shortcut {
    sequence: "Menu"
    enabled: !part.panel.shortcutsBlocked && !part.panel.textInputFocused()
    onActivated: {
      part.panel.latchShortcutMode(sequence)
      part.panel.openCurrentContextMenu()
    }
  }
  Shortcut {
    sequence: "Shift+F10"
    enabled: !part.panel.shortcutsBlocked && !part.panel.textInputFocused()
    onActivated: {
      part.panel.latchShortcutMode(sequence)
      part.panel.openCurrentContextMenu()
    }
  }
  Shortcut {
    sequence: "Alt+Left"
    enabled: !part.panel.shortcutsBlocked
      && (part.panel.currentTab === "detail" || part.panel.navigationStack.length > 0)
    onActivated: {
      part.panel.latchShortcutMode(sequence)
      part.panel.goBack()
    }
  }
  Shortcut {
    sequence: "Ctrl+,"
    enabled: part.panel.accountConnected && !part.panel.shortcutsBlocked
    onActivated: {
      part.panel.latchShortcutMode(sequence)
      part.panel.chooseTab("setup")
    }
  }
  Shortcut {
    sequence: "Alt+Shift+H"
    enabled: part.panel.accountConnected && !part.panel.shortcutsBlocked
    onActivated: {
      part.panel.latchShortcutMode(sequence)
      part.panel.chooseTab("home")
    }
  }
  Shortcut {
    sequence: "Alt+Shift+Q"
    enabled: part.panel.accountConnected && !part.panel.shortcutsBlocked
    onActivated: {
      part.panel.latchShortcutMode(sequence)
      part.panel.chooseTab("queue")
    }
  }
  Shortcut {
    sequence: "Alt+Shift+I"
    enabled: part.panel.accountConnected && !part.panel.shortcutsBlocked
    onActivated: {
      part.panel.latchShortcutMode(sequence)
      part.panel.chooseTab("stats")
    }
  }
  Shortcut {
    sequence: "Alt+Shift+N"
    enabled: part.panel.accountConnected && !part.panel.shortcutsBlocked
    onActivated: {
      part.panel.latchShortcutMode(sequence)
      part.panel.toggleNowPlayingExpanded()
    }
  }
  Shortcut {
    sequence: "Alt+Shift+D"
    enabled: part.panel.accountConnected && !part.panel.shortcutsBlocked
    onActivated: {
      part.panel.latchShortcutMode(sequence)
      part.panel.chooseTab("devices")
    }
  }
  Shortcut {
    sequence: "Ctrl+Shift+A"
    enabled: part.panel.accountConnected && !part.panel.shortcutsBlocked
      && part.panel.service && part.panel.service.currentArtistContextAvailable
    onActivated: {
      part.panel.latchShortcutMode(sequence)
      part.panel.openCurrentArtist()
    }
  }
  Shortcut {
    sequence: "Ctrl+Shift+B"
    enabled: part.panel.accountConnected && !part.panel.shortcutsBlocked
      && part.panel.service && part.panel.service.currentAlbumContextAvailable
    onActivated: {
      part.panel.latchShortcutMode(sequence)
      part.panel.openCurrentAlbum()
    }
  }
  Shortcut {
    sequence: "Ctrl+Shift+L"
    enabled: !part.panel.shortcutsBlocked && !part.panel.textInputFocused()
      && part.panel.service && part.panel.service.lyricsAvailable
    onActivated: {
      part.panel.latchShortcutMode(sequence)
      part.panel.openLyrics()
    }
  }
  Shortcut {
    sequence: "Space"
    enabled: !part.panel.shortcutsBlocked && !part.panel.textInputFocused()
      && part.panel.service && part.panel.service.playbackStartable
    onActivated: {
      part.panel.latchShortcutMode(sequence)
      if (part.panel.service) part.panel.service.togglePlayback()
    }
  }
  Shortcut {
    sequence: "Ctrl+Right"
    enabled: !part.panel.shortcutsBlocked && !part.panel.textInputFocused()
      && part.panel.service && part.panel.service.playbackControllable
    onActivated: {
      part.panel.latchShortcutMode(sequence)
      if (part.panel.service) part.panel.service.next()
    }
  }
  Shortcut {
    sequence: "Ctrl+Left"
    enabled: !part.panel.shortcutsBlocked && !part.panel.textInputFocused()
      && part.panel.service && part.panel.service.playbackControllable
    onActivated: {
      part.panel.latchShortcutMode(sequence)
      if (part.panel.service) part.panel.service.previous()
    }
  }
  Shortcut {
    sequence: "M"
    enabled: !part.panel.shortcutsBlocked && !part.panel.textInputFocused()
      && part.panel.service && part.panel.service.volumeSupported
    onActivated: {
      part.panel.latchShortcutMode(sequence)
      part.panel.toggleMute()
    }
  }
  Shortcut {
    sequence: "V"
    enabled: !part.panel.shortcutsBlocked && !part.panel.textInputFocused()
      && part.panel.nowPlayingExpanded
    onActivated: {
      part.panel.latchShortcutMode(sequence)
      part.panel.cycleEqualizerMode()
    }
  }
  Shortcut {
    sequence: "E"
    enabled: !part.panel.shortcutsBlocked && !part.panel.textInputFocused()
      && part.panel.currentTab !== "login"
    onActivated: {
      part.panel.latchShortcutMode(sequence)
      part.panel.toggleNowPlayingExpanded()
    }
  }
  Shortcut {
    sequence: "Ctrl+S"
    enabled: !part.panel.shortcutsBlocked && !part.panel.textInputFocused()
      && part.panel.service && part.panel.service.playbackControllable
    onActivated: {
      part.panel.latchShortcutMode(sequence)
      part.panel.service.setShuffle(!part.panel.service.shuffle)
    }
  }
  Shortcut {
    sequence: "Ctrl+R"
    enabled: !part.panel.shortcutsBlocked && !part.panel.textInputFocused()
      && part.panel.service && part.panel.service.playbackControllable
    onActivated: {
      part.panel.latchShortcutMode(sequence)
      part.panel.service.cycleRepeat()
    }
  }
  Shortcut {
    sequence: "Shift+Left"
    enabled: !part.panel.shortcutsBlocked && !part.panel.textInputFocused()
      && part.panel.service && part.panel.service.playbackControllable
    onActivated: {
      part.panel.latchShortcutMode(sequence)
      part.panel.seekBy(-10)
    }
  }
  Shortcut {
    sequence: "Shift+Right"
    enabled: !part.panel.shortcutsBlocked && !part.panel.textInputFocused()
      && part.panel.service && part.panel.service.playbackControllable
    onActivated: {
      part.panel.latchShortcutMode(sequence)
      part.panel.seekBy(10)
    }
  }
  Shortcut {
    sequence: "Ctrl+Up"
    autoRepeat: false
    enabled: !part.panel.shortcutsBlocked && !part.panel.textInputFocused()
      && part.panel.service && part.panel.service.volumeSupported
    onActivated: {
      part.panel.latchShortcutMode(sequence)
      part.panel.adjustVolume(0.05)
    }
  }
  Shortcut {
    sequence: "Ctrl+Down"
    autoRepeat: false
    enabled: !part.panel.shortcutsBlocked && !part.panel.textInputFocused()
      && part.panel.service && part.panel.service.volumeSupported
    onActivated: {
      part.panel.latchShortcutMode(sequence)
      part.panel.adjustVolume(-0.05)
    }
  }
  Shortcut {
    sequence: "Ctrl+/"
    enabled: !part.panel.textInputFocused()
      && (!part.panel.shortcutsBlocked || part.panel.shortcutHelpOpen)
    onActivated: {
      part.panel.latchShortcutMode(sequence)
      part.panel.toggleShortcutHelp()
    }
  }
  Shortcut {
    sequence: "Ctrl+H"
    enabled: part.panel.shortcutHintsActive
    onActivated: part.panel.disableShortcutHints()
  }
}
