/**
 * Pending-orders poll interval settings (pure — no chrome.*).
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

  function clampPendingOrdersPollMs(value, fallback = 45000) {
    const n = Number(value);
    if (!Number.isFinite(n)) return fallback;
    return Math.min(300000, Math.max(10000, Math.round(n)));
  }

  return { clampPendingOrdersPollMs };
});
