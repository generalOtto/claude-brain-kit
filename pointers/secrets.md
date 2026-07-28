---
name: secrets
description: The brain stores no secret values, ever — pointers only; where credentials actually live
type: reference
---

# Secrets policy — pointers, never values

**This repo must never contain a secret value.** Not a password, token, API key,
private key, connection string with credentials, or recovery code. Not "temporarily".
Not in a code block. Not in a journal entry quoting a terminal session.

## Where secrets actually live

> Fill this in for your setup — these are *pointers to locations*, not values:

- Password manager: … (e.g. "1Password vault *Personal*", "Bitwarden")
- Per-project: gitignored `.env` files inside each project's own repo
- Cloud consoles: … (the provider's own secret manager)

## How to reference a secret from a brain note

Write a pointer with enough context to find it, nothing more:

> Grafana admin password → password manager item **"garden-dashboard admin"**

## Enforcement layers (backstops, not the policy)

1. `.gitignore` blocks common secret files (`.env`, `*.pem`, `*.key`, …)
2. Optional gitleaks pre-commit hook (offered by `setup.sh`)
3. gitleaks CI on every push (`.github/workflows/gitleaks.yml`)

If Claude is ever about to write a secret value into this repo: **stop and write a
pointer instead.** A brain leak must never be a credential leak.
