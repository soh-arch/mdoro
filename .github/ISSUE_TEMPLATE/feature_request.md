---
name: Feature request
about: Something Mdoro should do and does not
labels: enhancement
---

## What you want to do

## Why the current behaviour gets in the way

## Before you write

Mdoro deliberately leaves some things out. These are not oversights, and each has
a reason written down in `docs/decisions/`:

- cloud sync, accounts, push notifications — it is local-network only, by design
- editing your task file — Mdoro reads it and never writes to it
- tool-specific task syntax (`TODO`, `id::`) — only standard checkboxes are read
- languages other than English in the interface
- ads, subscriptions, analytics

A case for changing one of those is welcome. It just needs to be a case.
