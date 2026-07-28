---
name: example-project
description: "EXAMPLE — the shape of a project note: current state, decisions, links; one note per initiative"
type: project
---

# Example: Garden Sensor Dashboard

> **EXAMPLE NOTE** — invented content showing the format. Replace with your real
> projects (one note each) and delete this one.

**What:** A Raspberry Pi + soil-moisture sensors in the vegetable garden, graphing to
a small dashboard. Repo: `github.com/yourname/garden-sensors` (the code lives there —
this note is mission control, not documentation).

**Status (2026-01-01):** Sensors 1–3 live; dashboard shows realtime but not history yet.

**Current focus:** Persist readings to SQLite so the dashboard can chart the last 30 days.

**Decisions:**
- Chose plain SQLite over InfluxDB — one Pi, three sensors; a time-series DB is overkill (2025-12-14)
- Sensor 2 reads ~8% high; corrected in software rather than replacing it (2025-12-20)

**Gotchas learned:** see [[example-gotcha]]

**Next:** waterproof the sensor 3 enclosure before spring rain.
