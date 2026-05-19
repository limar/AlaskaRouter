---
# AlaskaRouter-limu
title: Pin MapLibreSwiftUI to a tag/commit (currently main)
status: todo
type: task
priority: normal
created_at: 2026-05-19T07:17:24Z
updated_at: 2026-05-19T07:17:24Z
parent: AlaskaRouter-xtua
---

project.yml has 'branch: main' for the swiftui-dsl package. Reproducibility risk: a breaking change on main breaks our build. Pin to a verified-good commit SHA or tagged release. Also: the DSL has known broken iconImage(featurePropertyNamed:mappings:default:) macro that we work around — pinning insulates us from drift.
