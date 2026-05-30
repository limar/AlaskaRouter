---
# AlaskaRouter-fdha
title: 'Try: lighter type — stop name medium + rail-distance label regular'
status: todo
type: task
priority: normal
created_at: 2026-05-30T09:08:35Z
updated_at: 2026-05-30T09:08:35Z
parent: AlaskaRouter-e0vm
---

Currently the stop name is sheetSerif(15, .semibold) and the rail-distance label is sheetSans(9.5, .semibold). Both contribute to the 'thick' feel. TRY:
- Stop name → sheetSerif(15, .medium) (serif at this size still reads as the primary line)
- Rail-distance label → sheetSans(9.5, .regular)

Reject if names lose visual primacy. Probably better to land AFTER the row chrome lightens (steps 1–3) so we judge on the new baseline.
