/**
 * Poll interval settings (pure — no chrome.*).
 * UMD export for Node tests, content script, and popup.
 */

(function (root, factory) {
  const api = factory();
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = api;
  }
  root.ClipSyncPollSettings = api;
})(typeof globalThis !== 'undefined' ? globalThis : this, function pollSettingsFactory() {
  'use strict';

  const DEFAULT_SCRAPE_POLL_MS = 45000;
  const DEFAULT_APPROVED_SEARCH_POLL_MS = 30000;

  function clampPollMs(value, fallback) {
    const n = Number(value);
    if (!Number.isFinite(n)) return fallback;
    return Math.min(300000, Math.max(10000, Math.round(n)));
  }

  function clampPendingOrdersPollMs(value, fallback = DEFAULT_SCRAPE_POLL_MS) {
    return clampPollMs(value, fallback);
  }

  function clampApprovedSearchPollMs(value, fallback = DEFAULT_APPROVED_SEARCH_POLL_MS) {
    return clampPollMs(value, fallback);
  }

  return {
    clampPendingOrdersPollMs,
    clampApprovedSearchPollMs,
    DEFAULT_SCRAPE_POLL_MS,
    DEFAULT_APPROVED_SEARCH_POLL_MS,
  };
});
