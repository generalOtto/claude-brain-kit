---
name: example-gotcha
description: "EXAMPLE — the shape of a knowledge note: one hard-won durable fact, written so future-you can act on it"
type: reference
---

# Example: Pi Zero W drops WiFi under power-save

> **EXAMPLE NOTE** — invented content showing the format. A knowledge note captures
> **one** non-obvious fact you'd otherwise have to rediscover. Replace with your real
> gotchas and delete this one.

**The gotcha:** The Raspberry Pi Zero W's WiFi silently drops after ~10 idle minutes
because the driver's power-save mode is on by default. The dashboard looked "randomly
flaky" for two weekends before this surfaced.

**The fix:** disable power save at boot:

```bash
# /etc/rc.local (before exit 0)
iw wlan0 set power_save off
```

**How to verify:** `iw wlan0 get power_save` → should say `off`.

**Why it matters:** any always-on Pi project needs this; check it *first* when a
headless Pi "keeps disconnecting". Used by [[example-project]].
