/**
 * Pending-orders poll interval clamp tests (Task 4).
 */

const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const { clampPendingOrdersPollMs } = require('../poll_settings.js');

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
    assert.strictEqual(clampPendingOrdersPollMs('nope'), 45000);
  });
});
