// Progressive enhancement only: the page works without this file.
// The one network request is GitHub's public "latest release" answer, used to show the current version and link
// straight to the zip. If it fails for any reason, the static links to the Releases page stay as they are.
(function () {
  "use strict";

  var API = "https://api.github.com/repos/mavr1k/LangCycle/releases/latest";
  var CACHE_KEY = "langcycle-latest";

  function readCache() {
    try {
      var raw = sessionStorage.getItem(CACHE_KEY);
      return raw ? JSON.parse(raw) : null;
    } catch (e) { return null; }
  }

  function writeCache(value) {
    try { sessionStorage.setItem(CACHE_KEY, JSON.stringify(value)); } catch (e) { /* storage unavailable */ }
  }

  function apply(release) {
    document.querySelectorAll("[data-download]").forEach(function (a) { a.href = release.url; });
    document.querySelectorAll("[data-version]").forEach(function (el) { el.textContent = "v" + release.version; });
  }

  function load() {
    var cached = readCache();
    if (cached) { apply(cached); return; }
    if (!window.fetch) return;
    fetch(API, { headers: { Accept: "application/vnd.github+json" } })
      .then(function (r) { if (!r.ok) throw new Error(String(r.status)); return r.json(); })
      .then(function (data) {
        var asset = (data.assets || []).filter(function (a) { return /^LangCycle-.*\.zip$/.test(a.name); })[0];
        var version = String(data.tag_name || "").replace(/^v/, "");
        if (!asset || !/^\d+(\.\d+){1,2}$/.test(version)) return;
        if (data.draft || data.prerelease) return;
        var release = { version: version, url: asset.browser_download_url };
        writeCache(release);
        apply(release);
      })
      .catch(function () { /* keep the static links */ });
  }

  function copyButtons() {
    document.querySelectorAll("[data-copy]").forEach(function (button) {
      var label = button.textContent;
      button.addEventListener("click", function () {
        var target = document.getElementById(button.getAttribute("data-copy"));
        if (!target) return;
        var text = target.textContent.trim();
        function done() {
          button.textContent = button.getAttribute("data-copied") || "Copied";
          setTimeout(function () { button.textContent = label; }, 1800);
        }
        if (navigator.clipboard && navigator.clipboard.writeText) {
          navigator.clipboard.writeText(text).then(done, select);
        } else { select(); }
        function select() {
          var range = document.createRange();
          range.selectNodeContents(target);
          var selection = window.getSelection();
          selection.removeAllRanges();
          selection.addRange(range);
        }
      });
    });
  }

  load();
  copyButtons();
})();
