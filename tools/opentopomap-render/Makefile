# Render pipeline orchestration -- run ON THE RENDER SERVER, inside this dir.
# One target per stage; `render-region` runs the whole chain. This replaces
# copy-pasting commands from the docs. See BOOTSTRAP.md for first-time setup and
# docs/RUNBOOK.md for the architecture. Laptop-side packaging is in
# ../build-pack (see BOOTSTRAP.md "Finish on the laptop").
#
#   make render-region REGION=alaska_z11        # full pipeline for a region
#   make dem REGION=alaska_z11                   # a single stage
#   make help
#
# Prereq: the OTM render container is running (see BOOTSTRAP.md) and the
# osm2pgsql sidecar image is built (`make sidecar-image`).

REGION          ?= alaska_z11
CONTAINER       ?= alaskarouter-otm
RENDER_IMAGE    ?= alaskarouter/otm-render:2026-06-10
SIDECAR_IMAGE   ?= alaskarouter/osm2pgsql:1.11
IMAGE_DIR       ?= data/images
CONTOUR_SRC_DEG ?= 0.001        # contour DEM resolution (deg); ~0.001=90m. Hillshade unaffected.
RENDER_PROCS    ?= 8
FLAT_TMPFS      ?= 170g         # tmpfs size for the osm2pgsql flat-nodes (held in RAM)

HERE    := $(CURDIR)
SCRIPTS := $(HERE)/scripts
DATA    := $(HERE)/data/docker/data    # host path bind-mounted at /mnt/data in the container
REGPY   := python3 $(SCRIPTS)/region.py $(REGION)

# Pulled from config/regions.json so nothing is hard-coded.
EXTENT  = $(shell $(REGPY) extent)     # "minlon minlat maxlon maxlat"
BBOX    = $(shell $(REGPY) bbox)       # "minlon,minlat,maxlon,maxlat"
ZOOMS   = $(shell $(REGPY) zooms)
TILEDIR = contour-tiles-$(REGION)
OUTDIR  = contours-$(REGION)

DEXEC = docker exec $(CONTAINER)

.DEFAULT_GOAL := help
.PHONY: help render-image sidecar-image images save-images load-images deps style \
        fetch dem contours import render export pack render-region clean-region check-region

help: ## Show this help
	@echo "Render pipeline (run on the server). REGION=$(REGION)"
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) \
	  | sed -E 's/^([a-zA-Z_-]+):.*## (.*)/  \1\t\2/' | sort | expand -t22

check-region: ## Validate REGION exists in config/regions.json
	@$(REGPY) bbox >/dev/null && echo "REGION=$(REGION) extent=[$(EXTENT)] zooms=[$(ZOOMS)]"

render-image: ## Build the pinned, recreate-safe OTM render image
	docker build -t $(RENDER_IMAGE) $(HERE)/docker/otm-render

sidecar-image: ## Build the modern osm2pgsql 1.11 importer sidecar image
	docker build -t $(SIDECAR_IMAGE) $(HERE)/docker/osm2pgsql-sidecar

images: render-image sidecar-image ## Build both images

save-images: ## Archive both images to $(IMAGE_DIR)/*.tar.gz (own the bytes, no Docker Hub needed)
	mkdir -p $(IMAGE_DIR)
	docker save $(RENDER_IMAGE)  | gzip > $(IMAGE_DIR)/otm-render.tar.gz
	docker save $(SIDECAR_IMAGE) | gzip > $(IMAGE_DIR)/osm2pgsql-sidecar.tar.gz
	@ls -lah $(IMAGE_DIR)/*.tar.gz

load-images: ## Load both images from $(IMAGE_DIR)/*.tar.gz (offline bootstrap)
	gzip -dc $(IMAGE_DIR)/otm-render.tar.gz          | docker load
	gzip -dc $(IMAGE_DIR)/osm2pgsql-sidecar.tar.gz    | docker load

deps: ## Restore in-container deps (python-gdal, tile dirs) + restart Tirex
	bash $(SCRIPTS)/otm-docker.sh deps

style: ## Apply our style patches (relief to z11, drop contours -- f7tt/xymz) + reload Tirex
	$(DEXEC) bash /alaskarouter-scripts/patch-otm-style-vibrant-z11.sh
	bash $(SCRIPTS)/otm-docker.sh deps

fetch: check-region ## Fetch the region's OSM PBF + Copernicus DEM tiles
	bash $(SCRIPTS)/fetch-osm.sh $(REGION)
	python3 $(SCRIPTS)/fetch-copernicus-dem.py $(REGION)

dem: check-region ## Build warp-* (EPSG:3857 hillshade) + geographic warp-60 (contour source)
	$(DEXEC) -e DEM_TARGET_EXTENT="$(EXTENT)" -e CONTOUR_SRC_DEG=$(CONTOUR_SRC_DEG) \
	  /alaskarouter-scripts/prepare-copernicus-dem.sh

contours: check-region ## Retile warp-60 + generate contour PBFs (per-region dirs)
	$(DEXEC) rm -rf /mnt/data/srtm/$(TILEDIR) /mnt/data/srtm/$(OUTDIR)
	$(DEXEC) -e CONTOUR_TILE_DIR=$(TILEDIR) -e CONTOUR_OUTPUT_DIR=$(OUTDIR) -e CONTOUR_JOBS=$(RENDER_PROCS) \
	  /alaskarouter-scripts/prepare-copernicus-contours.sh

import: check-region ## Import contours via the osm2pgsql 1.11 sidecar (osmium sort -> single --create)
	$(DEXEC) cp /home/otm/db/contours.style /mnt/data/contours.style
	$(DEXEC) bash -lc "service tirex-backend-manager stop; service tirex-master stop; sleep 3"
	docker run --rm --network "container:$(CONTAINER)" \
	  -e PGHOST=127.0.0.1 -e PGPORT=5432 -e PGUSER=postgres \
	  --tmpfs /flat:size=$(FLAT_TMPFS) \
	  -v "$(DATA)":/mnt/data -v "$(SCRIPTS)":/alaskarouter-scripts \
	  $(SIDECAR_IMAGE) \
	  bash /alaskarouter-scripts/import-contours-sidecar.sh '$(OUTDIR)/contour-warp-60_*.pbf'
	bash $(SCRIPTS)/otm-docker.sh deps

render: check-region ## Render the region's tiles for all its zooms
	@for z in $(ZOOMS); do \
	  echo "== rendering z$$z =="; \
	  $(DEXEC) tirex-batch -p $(RENDER_PROCS) -d map=opentopomap bbox=$(BBOX) z=$$z; \
	  bash $(SCRIPTS)/wait-tirex-drain.sh $(CONTAINER) $$z; \
	done

export: check-region ## Export rendered tiles to data/tiles/$(REGION)/z/x/y.png
	python3 $(SCRIPTS)/export-region-tiles.py $(REGION) \
	  --base-url http://127.0.0.1:8088/otm --force --jobs 16

pack: check-region ## Pack the exported tiles into data/mbtiles/$(REGION).mbtiles
	python3 $(SCRIPTS)/pack-mbtiles.py \
	  --tiles-dir $(HERE)/data/tiles/$(REGION) \
	  --mbtiles   $(HERE)/data/mbtiles/$(REGION).mbtiles

render-region: dem contours import render export pack ## Full pipeline: dem->contours->import->render->export->pack
	@echo "DONE: $(HERE)/data/mbtiles/$(REGION).mbtiles"
	@ls -lah $(HERE)/data/mbtiles/$(REGION).mbtiles

clean-region: check-region ## Remove this region's scratch (warps/tiles/mbtiles) -- keeps DEM COGs
	$(DEXEC) rm -rf /mnt/data/srtm/$(TILEDIR) /mnt/data/srtm/$(OUTDIR) /mnt/data/srtm/_merged-contours.osm.pbf
	rm -rf $(HERE)/data/tiles/$(REGION) $(HERE)/data/mbtiles/$(REGION).mbtiles
