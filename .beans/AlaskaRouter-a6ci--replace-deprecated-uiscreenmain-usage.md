---
# AlaskaRouter-a6ci
title: Replace deprecated UIScreen.main usage
status: todo
type: task
priority: low
created_at: 2026-05-19T07:17:18Z
updated_at: 2026-05-19T07:17:18Z
parent: AlaskaRouter-xtua
---

RootView.swift:54 uses UIScreen.main.bounds.height — deprecated in iOS 26.0. Compiler warning on every build. Switch to view.window.windowScene.screen via context, or use a GeometryReader.
