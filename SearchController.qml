import QtQuick
import "Api.js" as Api

Item {
  id: root
  required property var api
  property int dataSerial: 0
  signal rememberSearch(string term)
  signal checkSavedItems(var items)
  function safeError(error) { return Api.redact(error) }
  property string searchQuery: ""
  property var searchGroups: Api.searchGroups({}, 128)
  property string searchError: ""
  property string searchResultQuery: ""
  property string searchActiveType: "track"
  property string searchPendingType: ""
  property var searchLoadedTypes: ({})
  property int searchGeneration: 0
  property bool searchLoading: false
  property var pageRequest: null
  property string retryMode: "initial"
  // Search runs while you type, so a term only counts once it has been left alone.
  property string historyTerm: ""
  onDataSerialChanged: clearSearch()

  Timer {
    id: historyDelay
    interval: 2500
    onTriggered: if (root.historyTerm && root.historyTerm === root.searchQuery)
      root.rememberSearch(root.historyTerm)
  }

  function search(term, type, force) {
    var normalized = String(term || "").trim()
    var value = Api.normalizedSearchType(type)
    if (force !== true && searchLoading && searchQuery === normalized
        && searchPendingType === value) return
    cancelSearch(false)
    searchQuery = normalized
    searchActiveType = value
    if (!normalized) {
      clearSearch()
      return
    }
    if (searchResultQuery !== normalized) {
      api.cancelSearch()
      searchGeneration++
      searchResultQuery = normalized
      searchGroups = Api.searchGroups({}, 128)
      searchLoadedTypes = ({})
    }
    if (force === true) {
      const refreshedGroups = Api.shallowCopy(searchGroups)
      refreshedGroups[value] = Api.normalizeSearchPage({}, value, 128)
      searchGroups = refreshedGroups
      const refreshedTypes = Api.shallowCopy(searchLoadedTypes)
      refreshedTypes[value] = false
      searchLoadedTypes = refreshedTypes
    }
    if (searchLoadedTypes[value] === true) {
      api.cancelSearch()
      searchGeneration++
      searchPendingType = ""
      searchLoading = false
      searchError = ""
      return
    }
    retryMode = "initial"
    searchLoading = true
    searchError = ""
    searchPendingType = value
    var expected = dataSerial
    var expectedSearch = ++searchGeneration
    api.search(normalized, value, function(groups, error) {
      if (expected !== root.dataSerial
          || expectedSearch !== root.searchGeneration) return
      if (root.searchQuery !== normalized) return
      root.searchLoading = false
      root.searchPendingType = ""
      if (error) root.searchError = root.safeError(error)
      else {
        const incoming = ({})
        incoming[value] = groups[value]
        root.searchGroups = Api.mergeSearchGroups(root.searchGroups, incoming)
        const loaded = Api.shallowCopy(root.searchLoadedTypes)
        loaded[value] = true
        root.searchLoadedTypes = loaded
        root.searchError = ""
        root.historyTerm = normalized
        historyDelay.restart()
        root.checkSavedItems(root.searchItems(value))
      }
    })
  }

  function searchItems(type) {
    var page = searchGroups[String(type || "track")]
    return page && Array.isArray(page.items) ? page.items : []
  }

  function searchNext(type) {
    var page = searchGroups[String(type || "track")]
    return page ? String(page.next || "") : ""
  }

  function loadMoreSearch(type) {
    var value = Api.normalizedSearchType(type)
    var path = searchNext(value)
    if (!path || searchLoading) return
    var expected = dataSerial
    var expectedQuery = searchResultQuery
    var expectedSearch = ++searchGeneration
    searchLoading = true
    searchError = ""
    searchPendingType = value
    retryMode = "page"
    pageRequest = api.request("GET", path, null, null, function(status, payload, error) {
      if (expected !== root.dataSerial
          || expectedSearch !== root.searchGeneration
          || expectedQuery !== root.searchResultQuery) return
      root.pageRequest = null
      root.searchLoading = false
      root.searchPendingType = ""
      if (error) { root.searchError = root.safeError(error); return }
      var incoming = ({})
      incoming[value] = Api.normalizeSearchPage(payload, value, 128)
      var merged = Api.mergeSearchGroups(root.searchGroups, incoming)
      root.searchGroups = merged
      root.searchError = ""
      root.checkSavedItems(root.searchItems(value))
    }, {
      priority: "interactive",
      timeoutMs: Api.SEARCH_REQUEST_TIMEOUT_MS,
      retryRateLimit: false
    })
  }

  function retrySearch(type) {
    var value = Api.normalizedSearchType(type)
    if (!searchQuery) return
    if (retryMode === "page" && searchNext(value) !== "")
      loadMoreSearch(value)
    else search(searchQuery, value, true)
  }

  function clearSearch() {
    searchGeneration++
    api.cancelSearch()
    api.abortRequest(pageRequest)
    pageRequest = null
    searchLoading = false
    searchQuery = ""
    searchGroups = Api.searchGroups({}, 128)
    searchError = ""
    searchResultQuery = ""
    searchActiveType = "track"
    searchPendingType = ""
    searchLoadedTypes = ({})
  }

  function cancelSearch(clearResults) {
    searchGeneration++
    api.cancelSearch()
    api.abortRequest(pageRequest)
    pageRequest = null
    searchLoading = false
    searchPendingType = ""
    searchError = ""
    if (clearResults === true) clearSearch()
  }

}
