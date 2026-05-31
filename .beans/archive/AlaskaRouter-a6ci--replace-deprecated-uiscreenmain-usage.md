---
# AlaskaRouter-a6ci
title: Replace deprecated UIScreen.main usage
status: scrapped
type: task
priority: low
created_at: 2026-05-19T07:17:18Z
updated_at: 2026-05-24T09:55:55Z
parent: AlaskaRouter-xtua
---

RootView.swift:54 uses UIScreen.main.bounds.height — deprecated in iOS 26.0. Compiler warning on every build. Switch to view.window.windowScene.screen via context, or use a GeometryReader.



## Reasons for Scrapping

Already resolved by an earlier refactor. `RootView.swift:54` no longer uses `UIScreen.main` (line is now `private var activeTrip: Trip? { ... }`). Grep confirms ZERO `UIScreen` references across the codebase. The compiler-warning the bean cited no longer exists.

Closing as scrapped (not completed — no commit was made specifically for this).
