// functions/shared/logger.js
//
// Structured JSON logger for Cloud Functions. Cloud Logging auto-parses JSON
// on stdout into jsonPayload.* fields, which lets the Next.js ops dashboard
// and Cloud Monitoring alerts filter/aggregate on exact fields instead of
// regex-matching free-form strings.
//
// Conventions
// ───────────
//   severity    — INFO | WARNING | ERROR  (maps to Cloud Logging severity)
//   component   — logical subsystem name: 'auto_assign' | 'courier_action' |
//                 'fleet' | 'mirror' | 'redis'
//   event       — dot-separated action: 'dispatched' | 'no_candidate' |
//                 'courier_action.failed' | 'redis.error' | ...
//   dispatchId  — correlation id that threads a single dispatch across
//                 CF-54 (origin) and CF-40 (action consumer)
//   orderId / collection / courierId — the primary entities
//   latencyMs   — wall-clock duration for timed operations
//   reason      — short error code / skip reason (machine-readable)
//   message     — optional human-readable supplement (NOT the primary signal)
//
// Anything else is pass-through. Keep field names stable — metric queries
// break when fields get renamed.

import { randomUUID } from 'crypto';

export function logEvent(fields) {
  const payload = {
    severity: fields.severity || 'INFO',
    timestamp: new Date().toISOString(),
    ...fields,
  };
  // stdout for INFO/DEBUG; stderr for WARNING/ERROR so Cloud Logging
  // categorises them correctly even outside Cloud Functions.
  const line = JSON.stringify(payload);
  if (payload.severity === 'ERROR' || payload.severity === 'WARNING') {
    console.error(line);
  } else {
    console.log(line);
  }
}

export function logInfo(fields)  {logEvent({ ...fields, severity: 'INFO' });}
export function logWarn(fields)  {logEvent({ ...fields, severity: 'WARNING' });}
export function logError(fields) {logEvent({ ...fields, severity: 'ERROR' });}

export function newDispatchId() {
  return randomUUID().split('-')[0] + randomUUID().split('-')[1];
}

export function startTimer() {
  const t0 = Date.now();
  return () => Date.now() - t0;
}
