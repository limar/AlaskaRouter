---
# AlaskaRouter-wq1q
title: Revisit TripPreviewRenderer's async shape now that renders are serialized
status: todo
type: task
priority: low
created_at: 2026-07-31T19:48:08Z
updated_at: 2026-07-31T19:48:08Z
---

`TripPreviewRenderer` is a completion-handler API. The original reason was timing — an `async` shape forces call sites into a `Task`, which used to be the worst possible moment to start a snapshot (AlaskaRouter-pq9g, 1/12 launches OK).

Serializing renders removed that constraint: the same deferred timing measured 12/12 serialized, and 20/20 under the harshest condition. So the async rewrite is viable whenever we want it.

Deliberately not done as part of pq9g: the completion-handler version is the one with 44/44 behind it, and the readability gain is small.

What to watch out for: the depth-1 queue coalesces, so a superseded request must still be resumed exactly once (today it gets `completion(nil)`). With continuations that becomes a resume-exactly-once hazard — easy to get wrong, and a leaked continuation hangs the caller forever.

## Todo
- [ ] Rewrite as `async`, keeping the serialization and the exactly-once contract
- [ ] Re-measure with the AlaskaRouter-pq9g harness before believing it
