#!/usr/bin/env node
"use strict";

function parsePersistedTimestamp(raw) {
  if (!raw) return null;
  let normalized = String(raw).trim();
  if (!normalized) return null;
  normalized = normalized.replace(" ", "T");
  normalized = normalized.replace(/([+-])(\d{2})(\d{2})$/, "$1$2:$3");
  normalized = normalized.replace(/([+-]\d{2})$/, "$1:00");
  let parsed = new Date(normalized);
  if (!Number.isNaN(parsed.getTime())) return parsed;
  if (!/[zZ]|[+-]\d{2}/.test(normalized)) {
    parsed = new Date(`${normalized}Z`);
  }
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

let failures = 0;
function t_ok(name, ok, detail) {
  if (!ok) failures++;
  console.log((ok ? "PASS" : "FAIL") + "  " + name + (detail ? " — " + detail : ""));
}

const postgresPlus00 = parsePersistedTimestamp("2026-08-29 08:15:00+00");
t_ok("postgres +00 parses", postgresPlus00 instanceof Date, String(postgresPlus00));

const naive = parsePersistedTimestamp("2026-08-29 08:15:00");
t_ok("naive timestamp parses", naive instanceof Date, String(naive));

const iso = parsePersistedTimestamp("2026-08-29T08:15:00.123456+00");
t_ok("fractional +00 parses", iso instanceof Date, String(iso));

t_ok("empty is null", parsePersistedTimestamp("") === null);
t_ok("null is null", parsePersistedTimestamp(null) === null);

if (failures > 0) {
  process.exit(1);
}
console.log("OK");
