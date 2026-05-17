# Spikes

Throwaway code that de-risks the v1 architecture before we commit to it.

## A_maplibre — Map rendering spike

Validates: MapLibre Native iOS + MapLibreSwiftUI + Protomaps PMTiles + a hand-tuned expedition style renders smoothly on iPhone 16 / iOS 26, and that a single annotation stays glued to its coordinate during pan/zoom/rotate.

## B_fts5 — Places search spike

Validates: an OSM-derived SQLite FTS5 places DB built from the Alaska extract returns acceptable hits for real expedition queries — including vague natural-language ones like *"Wrangell visitor center"* and typo'd ones like *"Atagun pas"*. Compares the `unicode61` tokenizer (with prefix index) against the `trigram` tokenizer for fuzzy matches.

Both spikes are throwaway. If they pass, the techniques migrate into the real app under `AlaskaRouter/Map/` and `AlaskaRouter/Search/`.
