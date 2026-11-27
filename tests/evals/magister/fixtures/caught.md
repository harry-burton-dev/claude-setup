---
date: "2026-11-27T10:00:00Z"
session: "none"
repo: "eval"
scope: "none"
lenses:
  - "analysis"
topic: "Webhook retries: duplicates without an idempotency key"
confidence: "high"
sources:
  - "https://stripe.com/docs/idempotency"
attachments: []
---

# Webhook retries

Retries without an idempotency key will deliver duplicates.
