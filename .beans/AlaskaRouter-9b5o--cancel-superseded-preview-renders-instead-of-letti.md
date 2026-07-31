---
# AlaskaRouter-9b5o
title: Cancel superseded preview renders instead of letting them finish
status: completed
type: task
priority: normal
created_at: 2026-07-31T19:54:38Z
updated_at: 2026-07-31T20:56:52Z
---

`TripPreviewRenderer` serializes renders behind a depth-1 newest-wins queue (AlaskaRouter-pq9g). A request that arrives mid-render supersedes the queued one, but the *active* render still runs to completion even when its result is already unwanted — a full 600x600 MapLibre snapshot plus a ~6 MB image, thrown away on arrival.

`MLNMapSnapshotter.cancel()` exists. The catch is that cancelling is exactly the manoeuvre that could reintroduce pq9g: if the cancelled snapshotter's PMTiles requests are still draining when the next one starts, we are back to two overlapping readers of the same archive — the thing the queue exists to prevent.

So this is not a one-liner. It needs the semantics established, then measured.

## Open questions
- Does `cancel()` invoke the completion handler? If not, `active` never clears on its own and the queue would deadlock unless we clear it at cancel time.
- Does destroying the snapshotter synchronously drop its in-flight file-source requests, or do they drain afterwards?

## Todo
- [x] Extracted as `PreviewRenderSlot` — `start` is the only MapLibre-shaped thing, injected
- [x] 8 unit tests, 5 ms, no MapLibre
- [x] Implemented — and it let the queue slot go away entirely
- [x] Re-measured: 48 launches, 0 PMTiles errors, including ~200 mid-flight cancels
- [x] Recorded below; verified in the share sheet itself

## Answers to the open questions

Probed directly against a real snapshotter (temporary test, since deleted):

- **`cancel()` is silent.** Cancelled at 0 ms, 20 ms and 60 ms, the completion handler never fired — not with an error, not at all. So the caller must be settled by whoever cancels, or it waits forever. This is why `PreviewRenderSlot` settles superseded requests itself with nil.
- **A render takes ~190-320 ms** (317 ms cold, then 189/188 ms). That is the entire window in which a supersede can save anything — worth knowing before assuming cancellation buys much.
- **Cancelling after completion is a no-op** — at 300 ms the render had already delivered its image.

## Does cancelling reintroduce AlaskaRouter-pq9g?

No. Measured across four conditions, **48 launches, 0 PMTiles errors**:

| condition | consumers | supersedes | result |
|---|---|---|---|
| M | 2 | burst of 5, same turn | 0 errors |
| O | 1 | burst of 10, same turn | 12/12, 0 errors |
| P | 1 | burst of 5, 100 ms apart (mid-flight cancels) | 12/12, 0 errors |
| Q | 2 | burst of 5, 100 ms apart | 12/12, 0 errors |

P and Q are the ones that matter: 100 ms into a ~190 ms render the snapshotter is actively fetching tiles, so those are ~200 genuinely mid-flight cancels with no corruption. For contrast, the unserialized burst-of-5 condition from pq9g failed 6/12 — the harness surfaces this race readily when it exists.

## Summary of Changes

`PreviewRenderSlot` (new) owns the concurrency rules; `TripPreviewRenderer` keeps only the MapLibre `start` closure and the compositing. A newer request now **cancels** the running render instead of queueing behind it, which:

- stops burning a ~200-300 ms render whose result is already unwanted,
- removes the flash of a stale preview before the newer one lands,
- and deleted the queue slot — with cancellation nothing ever waits, so `queued` and its branch are gone.

The generation counter stays: `cancel()` racing a completion that was already dispatched would otherwise settle a request twice. There is a test for exactly that.

Trade-off accepted: a caller submitting faster than ~200 ms starves. Fine here — requests come from trip edits, and the preview only has to be right by the time the share sheet opens.

Verified in the failure surface: bottom sheet → Export Trip… → the share sheet shows the map thumbnail with its name pill, not the app-icon fallback. 141 tests pass, build is warning-clean.
