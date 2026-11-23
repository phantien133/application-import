#!/usr/bin/env node
/**
 * Strategic Compact Suggester
 *
 * Cross-platform (Windows, macOS, Linux)
 *
 * Runs on PreToolUse or periodically to suggest manual compaction at logical intervals
 *
 * Why manual over auto-compact:
 * - Auto-compact happens at arbitrary points, often mid-task
 * - Strategic compacting preserves context through logical phases
 * - Compact after exploration, before execution
 * - Compact after completing a milestone, before starting next
 */

const fs = require('fs');
const path = require('path');
const {
  getClaudeDir,
  ensureDir,
  log
} = require('./lib/utils');

async function main() {
  // Track tool call count (increment in a temp file)
  // Use a session-specific counter file based on session ID from environment
  // or parent PID as fallback
  const sessionId = (process.env.CLAUDE_SESSION_ID || 'default').replace(/[^a-zA-Z0-9_-]/g, '') || 'default';
  // Keep the counter in a private directory under ~/.claude, not the shared
  // system temp dir where another user could plant a symlink at a predictable path.
  const counterDir = path.join(getClaudeDir(), 'tmp');
  ensureDir(counterDir);
  try { fs.chmodSync(counterDir, 0o700); } catch { /* best effort */ }
  const counterFile = path.join(counterDir, `claude-tool-count-${sessionId}`);
  const rawThreshold = parseInt(process.env.COMPACT_THRESHOLD || '50', 10);
  const threshold = Number.isFinite(rawThreshold) && rawThreshold > 0 && rawThreshold <= 10000
    ? rawThreshold
    : 50;

  let count = 1;

  // Read existing count or start at 1
  // Use fd-based read+write to reduce (but not eliminate) race window
  // between concurrent hook invocations
  try {
    // O_NOFOLLOW: never follow a symlink planted at the counter path.
    const flags = fs.constants.O_RDWR | fs.constants.O_CREAT | (fs.constants.O_NOFOLLOW || 0);
    const fd = fs.openSync(counterFile, flags, 0o600);
    try {
      const buf = Buffer.alloc(64);
      const bytesRead = fs.readSync(fd, buf, 0, 64, 0);
      if (bytesRead > 0) {
        const parsed = parseInt(buf.toString('utf8', 0, bytesRead).trim(), 10);
        // Clamp to reasonable range — corrupted files could contain huge values
        // that pass Number.isFinite() (e.g., parseInt('9'.repeat(30)) => 1e+29)
        count = (Number.isFinite(parsed) && parsed > 0 && parsed <= 1000000)
          ? parsed + 1
          : 1;
      }
      // Truncate and write new value
      fs.ftruncateSync(fd, 0);
      fs.writeSync(fd, String(count), 0);
    } finally {
      fs.closeSync(fd);
    }
  } catch {
    // Counter is best effort: on failure (e.g. symlink refused) keep count = 1.
  }

  // Suggest compact after threshold tool calls
  if (count === threshold) {
    log(`[StrategicCompact] ${threshold} tool calls reached - consider /compact if transitioning phases`);
  }

  // Suggest at regular intervals after threshold (every 25 calls from threshold)
  if (count > threshold && (count - threshold) % 25 === 0) {
    log(`[StrategicCompact] ${count} tool calls - good checkpoint for /compact if context is stale`);
  }

  process.exit(0);
}

main().catch(err => {
  console.error('[StrategicCompact] Error:', err.message);
  process.exit(0);
});
