---
# AlaskaRouter-f0t2
title: Force a leg to use or avoid the ferry (→ transport mode per leg)
status: draft
type: feature
priority: high
created_at: 2026-07-27T22:41:21Z
updated_at: 2026-07-27T22:41:21Z
---

From the Alaska field trip, July 2026. **Real incident:** the ferry was closed for bad weather and a land route was needed *immediately*, with no way to tell the app so.

## What is wanted
A quick, obvious per-leg switch: use the ferry, or avoid it. Changeable in seconds, in the field, possibly with no signal.

## Where it stands today
Routing goes through Valhalla with `use_ferry=1.0` — a global preference baked in for AlaskaRouter-y3g3 (AMHS sailings render correctly). It is not per-leg and not user-visible. So today the only workaround is adding intermediate waypoints to force a land path, which is exactly the fiddling you don't want on a bad-weather day.

## To discuss
- **Scope now vs later.** The narrow fix is a two-state ferry toggle per leg. The general shape is "transport mode per leg" (drive / ferry / walk / …), which the user raised as the natural extension. Doing the narrow one badly could foreclose the general one — the persisted model should probably carry a mode enum from the start even if the UI only offers two values.
- **Where does the control live?** The leg is the gap *between* two stops. The bottom sheet's timeline rail already draws per-leg distance (AlaskaRouter-jhw8), so the rail segment is the natural target — but it is small. Alternatives: a leg-tap on the map, or an entry in the stop callout for "leg to next".
- **Offline behaviour.** Re-routing needs the network. If the ferry is cancelled and there is no signal, what does the app show? This matters — bad weather and no signal correlate. Interacts with the pendingSnap / unroutable-leg machinery (AlaskaRouter-2l0i, AlaskaRouter-2i03).
- Does the setting survive a reorder that changes which stops the leg connects?

Blocked-ish on nothing, but the offline question may argue for doing this after real offline routing (AlaskaRouter-p6ow, v2).
