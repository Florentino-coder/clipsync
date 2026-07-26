/**
 * Poll interval clamp tests.
 */

const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const {
  clampPendingOrdersPollMs,
  clampApprovedSearchPollMs,
  DEFAULT_SCRAPE_POLL_MS,
  DEFAULT_APPROVED_SEARCH_POLL_MS,
} = require('../poll_settings.js');

describe('clampPendingOrdersPollMs', () => {
  it('keeps default-range values', () => {
    assert.strictEqual(clampPendingOrdersPollMs(45000), 45000);
  });

  it('clamps below minimum to 10s', () => {
    assert.strictEqual(clampPendingOrdersPollMs(1000), 10000);
  });

  it('clamps above maximum to 300s', () => {
    assert.strictEqual(clampPendingOrdersPollMs(999999), 300000);
  });

  it('returns fallback for non-numeric input', () => {
    assert.strictEqual(clampPendingOrdersPollMs('nope'), DEFAULT_SCRAPE_POLL_MS);
  });
});

describe('clampApprovedSearchPollMs', () => {
  it('defaults fallback to 30s', () => {
    assert.strictEqual(clampApprovedSearchPollMs('x'), DEFAULT_APPROVED_SEARCH_POLL_MS);
    assert.strictEqual(DEFAULT_APPROVED_SEARCH_POLL_MS, 30000);
  });

  it('clamps to 10s–300s', () => {
    assert.strictEqual(clampApprovedSearchPollMs(5000), 10000);
    assert.strictEqual(clampApprovedSearchPollMs(400000), 300000);
    assert.strictEqual(clampApprovedSearchPollMs(15000), 15000);
  });
});
