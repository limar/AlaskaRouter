---
# AlaskaRouter-j5w1
title: Delete a stop from the trip (explicit affordance)
status: todo
type: feature
priority: high
created_at: 2026-05-19T12:13:50Z
updated_at: 2026-05-19T12:13:50Z
parent: AlaskaRouter-xtua
---

Today there's swipe-to-delete on stop rows in the bottom sheet via List.onDelete — works but only iOS power users discover it. The user wants delete as a high-priority core capability with a discoverable affordance.

Open design questions:
- Always-visible trash icon on each row vs swipe-only vs both?
- Confirmation alert (matches the trip-delete pattern) or silent?
- Undo toast (we already have AddedToTripToast as a model)?

- [ ] Decide affordance with user
- [ ] Implement
- [ ] Verify with delete + re-add of the same stop
