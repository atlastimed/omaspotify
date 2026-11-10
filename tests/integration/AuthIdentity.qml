import QtQuick
import Quickshell
import "../.." as Plugin

ShellRoot {
  Plugin.AuthManager { id: auth; pluginDir: "/nonexistent" }
  function check(condition, message) {
    if (!condition) throw new Error(message)
  }
  Timer {
    interval: 1
    running: true
    onTriggered: {
    check(!auth.validClientId && auth.resolvedClientId === "",
      "An unconfigured install borrowed another application's identity")
    auth.beginLogin()
    check(!auth.loginBusy, "An unconfigured install started authorization")
    var signOuts = 0
    auth.loggedOut.connect(function() { signOuts++ })
    auth.customClientId = "22222222222222222222222222222222"
    check(signOuts === 0, "Settings arriving at startup signed the user out")
    auth.accessToken = "old"
    auth.accessTokenExpiresAt = Date.now() + 3600000
    auth.loggedIn = true
    auth.customClientId = "invalid"
    check(signOuts === 1, "Changing identity did not sign the user out")
    check(auth.accessToken === "", "Old access token survived identity change")
    check(!auth.loggedIn && !auth.validClientId, "Invalid identity was accepted")
    check(auth.resolvedClientId === "", "Invalid identity fell back silently")
    var error = ""
    auth.withAccessToken(function(token, reason) {
      check(token === "", "Old identity token reached a consumer")
      error = reason
    })
    check(error.indexOf("32") >= 0, "Invalid ID has no actionable error")
    var request = {
      readyState: 1, status: 200, responseText: "{}", aborted: false,
      open: function() {}, setRequestHeader: function() {}, send: function() {},
      abort: function() { this.aborted = true }
    }
    auth.xhrFactory = function() { return request }
    auth.customClientId = "11111111111111111111111111111111"
    var delivered = false
    auth.postTokenRequest("", "", function() { delivered = true })
    auth.customClientId = "invalid"
    request.readyState = XMLHttpRequest.DONE
    request.onreadystatechange()
    check(request.aborted, "Old token request was not aborted")
    check(!delivered, "Old identity response reached a new identity")

    // A brief network failure while refreshing must not read as a sign-out.
    auth.customClientId = "33333333333333333333333333333333"
    var transient = {
      readyState: 1, status: 0, responseText: "", open: function() {},
      setRequestHeader: function() {}, send: function() {}, abort: function() {}
    }
    auth.xhrFactory = function() { return transient }
    auth.loggedIn = true
    auth.accessToken = "expired"
    signOuts = 0
    var answered = ""
    auth.tokenWaiters = [function(token, reason) { answered = reason }]
    auth.refreshWithToken("kept-in-keyring", "restore")
    transient.readyState = XMLHttpRequest.DONE
    transient.onreadystatechange()
    check(auth.loggedIn, "A network failure signed the user out")
    check(auth.accessToken === "", "A failed refresh kept the old token")
    check(!auth.refreshBusy, "A failed refresh stayed busy")
    check(signOuts === 0, "A network failure emitted a sign-out")
    check(answered !== "", "A restore that failed never answered its waiters")
    var earlyReason = ""
    auth.withAccessToken(function(token, reason) { earlyReason = reason })
    check(earlyReason !== "", "The refresh was retried straight away during an outage")
    check(!auth.refreshBusy && auth.tokenWaiters.length === 0,
      "A request during the outage started another refresh")
    auth.refreshRetryAt = 0

    // A refresh token Spotify refuses really is the end of the session.
    var refused = {
      readyState: 1, status: 400, responseText: '{"error":"invalid_grant"}',
      open: function() {}, setRequestHeader: function() {}, send: function() {},
      abort: function() {}
    }
    auth.xhrFactory = function() { return refused }
    auth.loggedIn = true
    auth.refreshWithToken("revoked", "request")
    refused.readyState = XMLHttpRequest.DONE
    refused.onreadystatechange()
    check(!auth.loggedIn, "A revoked session stayed signed in")

    // A refresh dropped by a newer sign-in must not leave the flag stuck.
    var pendingRefresh = {
      readyState: 1, status: 0, responseText: "", open: function() {},
      setRequestHeader: function() {}, send: function() {}, abort: function() {}
    }
    auth.xhrFactory = function() { return pendingRefresh }
    auth.refreshWithToken("rt", "request")
    check(auth.refreshBusy, "Refresh did not start")
    auth.loginBusy = true
    auth.exchangeAuthorizationCode("code")
    check(!auth.refreshBusy, "A superseded refresh left the session wedged")
    auth.cancelLogin()

    // A callback whose state does not match says nothing the sender chose.
    auth.loginBusy = true
    auth.oauthState = "expected-state"
    auth.callbackHandled = false
    auth.handleCallbackLine("GET /login?error=x&error_description=%3Cimg%20src%3Dhttp%3A%2F%2Fevil%3E&state=wrong HTTP/1.1")
    check(auth.lastError.indexOf("evil") < 0 && auth.lastError.indexOf("<") < 0,
      "A forged callback chose the error text")
    auth.cancelLogin()
    auth.loginBusy = true
    auth.oauthState = "expected-state"
    auth.callbackHandled = false
    auth.handleCallbackLine("GET /login?error=access_denied&state=expected-state HTTP/1.1")
    check(auth.lastError.indexOf("access_denied") >= 0, "Spotify's own refusal was hidden")
    auth.cancelLogin()

    identitySettled.start()
    }
  }
  // A changed client id takes a moment to drain before sign-in is allowed.
  Timer {
    id: identitySettled
    interval: 200
    onTriggered: {
      // A helper that cannot start must not leave sign-in busy for ever.
      auth.beginLogin()
      check(auth.loginBusy, "Sign-in did not start")
      startFailure.start()
    }
  }
  Timer {
    id: startFailure
    interval: 400
    onTriggered: {
    check(!auth.loginBusy, "A helper that failed to start left sign-in busy")
    console.log("AUTH_IDENTITY_PASS")
    Qt.quit()
    }
  }
}
