# Data Sources and Integration Plan for an Alaska Campgrounds Database

## Overview

This report identifies practical data sources for building a unified SQLite database of campsites and campgrounds in Alaska, with an emphasis on programmatically accessible datasets (APIs, GIS layers, downloadable files) and scrape‑able web directories. It also proposes concrete actions that an automated system ("Computer" or similar) could perform to ingest, normalize, and merge these sources into a single schema with at least name, coordinates, booking method, and direct contact details.[^1][^2][^3]

## Target Minimum Schema

A reasonable minimum schema for a unified Alaska campgrounds SQLite DB could be:

- camp_id (internal primary key)
- source_id (enum or foreign key referencing data source table)
- source_camp_key (original ID or URL)
- name
- latitude
- longitude
- address_text
- region/admin_area (e.g., borough, park)
- booking_method (enum: `online_portal`, `phone_email`, `walk_in`, `no_reservations`, `unknown`)
- booking_details (free text; URL or instructions)
- contact_phone
- contact_email
- website_url
- open_season (free text; e.g., "May–Sep")
- office_hours (free text)
- photos_url (single or JSON list)
- original_source_url
- last_seen_utc

This can be extended later for amenities, capacity, price, etc., but it is sufficient for first pass ingestion from the sources below.

## National‑Level APIs and Datasets

### Recreation Information Database (RIDB / Recreation.gov)

The U.S. Recreation Information Database (RIDB) is the main official API for federal recreation facilities (including many Alaska campgrounds) and backs Recreation.gov. It exposes endpoints for facilities, campsites, media, links, and more.[^2][^1]

Key properties:
- Base: `https://ridb.recreation.gov/api/v1`.[^1][^2]
- Resources: `facilities`, `campsites`, `recareas`, `media`, `links`, etc., with support for filtering by state abbreviation (`AK`) and activity type.[^2][^1]
- Returns structured JSON, with coordinates, names, facility types, reservation URLs (usually pointing back to Recreation.gov), and sometimes contact info.

Suggested actions for Computer:
- Call RIDB `/facilities` with `state=AK` and facility types related to camping, then `/campsites` for facility‑linked campsites.
- Extract: name, `FacilityLatitude`, `FacilityLongitude`, `FacilityTypeDescription`, `FacilityPhone`, `FacilityEmail`, `FacilityURL`, `OrgFacilityID`, `RESERVATION_URL` (from links or media).
- Map booking_method:
  - If `FacilityReservationURL` or Recreation.gov URL exists → `online_portal`.
  - If only phone/email and texts like "first‑come" → `walk_in` or `no_reservations`.
- Store facility and campsite records; use facility IDs as foreign keys.

### Active / ReserveAmerica Campgrounds API

Active/ReserveAmerica provides a Campground Search API that covers a very high percentage of U.S. and Canadian national and state/provincial park campgrounds, including many Alaska state park and partner facilities. It is read‑only and returns registration links on ReserveAmerica.com.[^4][^5][^6]

Key properties:
- Base URL (OpenAPI listing): `https://www.active.com/api` with campground search at `http://api.amp.active.com/camping/campgrounds` using query parameters and an API key.[^5][^6][^4]
- State filtering via `pstate=AK` and additional filters (amenities, pets, etc.).[^6]
- Response format: XML listing campgrounds with coordinates, name, `facilityID`s, and booking URLs.

Suggested actions for Computer:
- Request API key and run paginated calls with `pstate=AK`.
- Extract: campground name, lat/long, description, `facilityID`, `contractID`, reservation URL, and any phone/email fields.
- Map booking_method as `online_portal` when reservation URL is present.
- De‑duplicate against RIDB/Recreation.gov using shared identifiers or URL patterns.

### National Park Service and BLM Recreation Services

National Park Service and Bureau of Land Management expose recreation data through ArcGIS and other feeds; these include some Alaska campground locations.[^7][^8]

- BLM Alaska Recreation FeatureServer: an ArcGIS FeatureServer with point and polygon layers for BLM recreation sites (overnight sites, campgrounds, etc.).[^8]
- NPS "Public Campgrounds in Alaska" page (textual): lists public campgrounds around the state; primarily a content source and pointer to park‑level campground data.[^7]

Suggested actions for Computer:
- Query BLM Alaska recreation FeatureServer layers for features whose type/category corresponds to campgrounds and overnight sites within Alaska.[^8]
- Extract: `NAME`, coordinates, facility type, and any contact fields from attributes.
- For each NPS Alaska park that supports camping, query NPS APIs or park GIS if available; otherwise treat park pages as scrape candidates.

## Alaska State and Local GIS / Open Data

### Alaska State Park Boundaries and Facilities

The Alaska Department of Natural Resources maintains an open ArcGIS dataset "Alaska State Park Boundary and Facility" that includes park boundaries, facilities, trails, and roads, with an associated web service for visualization and download.[^9][^3]

Key properties:
- Hosted as a web service and map layer on the Alaska DNR Open Data portal.[^3]
- Represents state park managed boundaries and facilities; facility layer typically includes campground points and attributes.[^3]

Suggested actions for Computer:
- Access the ArcGIS REST endpoint for the "State Park Boundary and Facility" service.[^3]
- Filter features whose facility type corresponds to campgrounds, RV parks, or public use cabins.
- Extract: facility name, coordinates (geometry), any attributes like `Facility_Type`, `Open_Season`, `Contact`, `URL`.
- Map to DB fields: name, lat/long, region, open_season, website_url, booking_method (if facility indicates reservation required).

### Kenai Peninsula Borough Campgrounds Layer

The Alaska Geoportal includes a "KPB Campgrounds" dataset for Kenai Peninsula Borough, compiled from various sources.[^10]

Key properties:
- GIS layer for Kenai Peninsula Borough campgrounds.
- Contains at least location and some metadata about each campground.[^10]

Suggested actions for Computer:
- Download the Kenai Peninsula Borough campgrounds layer via the provided Open Data/ArcGIS service.[^10]
- Extract: campground name, geometry, any contact or website fields, and categorization.
- Reproject coordinates to WGS84 if needed; store as latitude/longitude.

### BLM Alaska Spatial Data Management System (SDMS)

The BLM Alaska SDMS portal provides access to BLM Alaska land record documents and web map apps, with a path to download GIS datasets from the BLM Alaska GIS Data page. Some layers correspond to recreation and may denote campgrounds and related infrastructure.[^11]

Suggested actions for Computer:
- From SDMS, navigate to BLM Alaska GIS Data and identify recreation‑related layers that include campgrounds or overnight recreation sites.[^11]
- Download shapefiles or feature services and extract any campground features, mapping attributes into the unified schema.

## OpenStreetMap and Overpass

### OSM Camping Features and Overpass Turbo/API

OpenStreetMap (OSM) has global coverage of camping features including `tourism=camp_site` and `tourism=caravan_site` tags, plus subkeys like `camp_site=*` for level of facilities. Overpass Turbo (and Overpass API) allow querying these features for a specified bounding box or region.[^12][^13]

Key properties:
- Overpass Turbo is a front‑end to Overpass API; queries can filter by tags and bounding box.[^12]
- Typical query for campsites uses `tourism=camp_site` for nodes and ways within a bounding box.[^12]
- OSM tags provide rich, semi‑structured attributes: `name`, `phone`, `email`, `website`, `opening_hours`, `operator`, `fee`, `addr:*`, etc.[^13]

Suggested actions for Computer:
- Construct Overpass queries covering Alaska (e.g., by state polygon or bounding boxes tiled over Alaska) for `tourism=camp_site` and `tourism=caravan_site`.
- Export as GeoJSON or XML and parse into SQLite.
- Extract: 
  - `name` → name
  - centroid of geometry → latitude/longitude
  - `phone`, `email`, `website` → contact fields
  - `opening_hours`, `operator`, `seasonal` tags → open_season/office_hours (free text)
- Mark booking_method:
  - If tags or website indicate "reservation" or link to booking portal → `online_portal`.
  - If tags include `reservation=no` or similar → `no_reservations`.

OSM data is under the ODbL license; downstream usage should respect attribution and share‑alike requirements.[^13]

## Web Directories and Scraping Candidates

### Alaska Campground Owners Association (ACOA)

ACOA is a non‑profit association representing many privately owned campgrounds and RV parks in Alaska and publishes a campground guide/directory. It is a key source for private facilities that may not appear in federal/state APIs.[^14][^15]

Properties:
- Official website and membership directory for private campgrounds across regions in Alaska.[^14]
- Campground guide intended for trip planning, listing parks and RV parks statewide.[^15]

Scraping feasibility:
- The main ACOA site and its directory pages likely present tabular or card‑style listings with campground names, locations, and contacts.[^14]
- Before scraping, "Computer" must check `robots.txt` on `akcampgrounds.com` and terms of use.

Suggested actions for Computer:
- If `robots.txt` allows, crawl the ACOA campground directory pages and extract:
  - Campground name
  - Region and city
  - Website, phone, email
  - Short description
- Use website URLs and names as keys to match/merge with other sources.

### Alaska RV Parks and Private Campground Lists

There are curated lists of private RV parks and campgrounds with structured tables including sites count, website, address, nearest city, map link, phone, etc.[^16][^17]

Examples:
- Alaska Private RV Campsite List and Links (Alaska Family Motorhomes) – a table of RV campsites with columns for site count, website, address, nearest city, map link, and local phone.[^16]
- Alaska RV Parks – similar table listing private RV parks and campgrounds across Alaska with website, address, city, map link, and phone.[^17]

Scraping feasibility:
- Both examples use HTML tables, which are straightforward to parse programmatically.[^17][^16]
- They include at least name, address, nearest city, website URL, and phone; coordinates may need to be derived by geocoding the address or by following "MAP" links.[^16][^17]

Suggested actions for Computer:
- Respect each site’s `robots.txt` and terms.
- If allowed, programmatically fetch the table pages, parse rows into structured records.
- For each row:
  - Use address and city to geocode coordinates (e.g., via a geocoding API).
  - Set booking_method to `phone_email` when only phone/email/website is provided.
  - Store original page URL as `original_source_url`.

### Legacy Alaska CVB/ACVB Campground Listing

An older Alaska visitors bureau page lists numerous private and public RV parks and campgrounds grouped by geographic areas, with rich text including address, contact numbers, space counts, and open season information.[^18]

Scraping feasibility:
- Content is long‑form HTML but structured with headings by region and campgrounds described in consistent patterns (name, address, phone, season, capacity).[^18]
- Parsing will require more regex/heuristic extraction compared to a strict table.

Suggested actions for Computer:
- If allowed by `robots.txt`, crawl the listing page.[^18]
- For each campground block:
  - Extract name, address, phone, opening dates (e.g., "May 15–Sept 15"), and any marketing blurb.
  - Geocode address to coordinates.
- Use this source primarily to enrich seasonal information and additional contact numbers.

### Alaska.org Regional Campground Pages

Alaska.org provides curated regional campground and RV park listings (e.g., Denali State Park RV Parks & Campgrounds, Tongass National Forest camping, Palmer/Wasilla area campgrounds), with descriptions, approximate locations, and sometimes seasonal and rate info.[^19][^20][^21]

Properties:
- Pages list multiple campgrounds with consistent cards: name, short description, sometimes operating season and nightly rate, and links to further details.[^20][^21][^19]

Scraping feasibility:
- The pages are structured but may require HTML parsing of repeated blocks.
- Terms of use and `robots.txt` must be respected; scraping may or may not be permitted.

Suggested actions for Computer:
- Check `robots.txt` for `www.alaska.org`.
- If permitted, parse regional campground lists for:
  - Name, description, rough location (mile marker, nearby town), and any info about open season and pricing.[^21][^19][^20]
  - Follow detail pages to extract photos URLs and more detailed contact info if available.
- Use this data mainly to augment descriptive fields (`open_season`, `photos_url`, narrative description).

### Other Directories via SaaS Scrapers

Commercial scraping platforms offer pre‑built scrapers for large campground directories such as AllStays and Campendium, and separate modules specifically for Recreation.gov and National Park Service data.[^22][^23][^24]

Examples:
- Allstays Scraper: extracts name, type, location, coordinates, phone, amenities, and price tier for 90,000+ campgrounds and overnight stops.[^24]
- Campendium Scraper: extracts campground, RV park, and boondocking data from Campendium, including reviews, ratings, amenities, photos, and coordinates.[^23][^22]
- Recreation.gov Campsite Availability Scraper: uses Recreation.gov’s public API to pull availability data for specified campgrounds.[^22][^23]

Suggested actions for Computer:
- Decide whether to license/use a third‑party scraper or replicate functionality via direct API use.
- If using the platform:
  - Configure jobs limited to Alaska (by state filter, bounding box, or keyword) and export CSV/JSON.
  - Ingest exported data: name, coordinates, phone, website, booking links, photos, and amenity metadata.
- If self‑implementing, copy concepts but call the platforms’ underlying APIs (where permitted) rather than full HTML scraping.

## Datasets and Catalogs

### Data.gov and Other Federal Catalogs

U.S. federal open data catalogs list multiple campground‑related datasets (shapefiles or other geospatial formats), although many focus on areas outside Alaska. However, they are still useful as a pattern for how campground data is structured and may contain Alaska‑relevant entries.[^25][^26][^27]

Suggested actions for Computer:
- Search Data.gov and related catalogs for "Campgrounds" and filter for Alaska or agencies operating Alaska sites.[^27]
- For any Alaska‑relevant dataset:
  - Download the geospatial file (e.g., shapefile) via the provided download URL.[^28]
  - Convert to GeoJSON and ingest name, geometry, and attributes.

## Booking and Availability Layers

### Recreation.gov Internal API Usage

Beyond RIDB, Recreation.gov exposes an internal JSON API for campsite availability that various scripts and tools use. This is more for dynamic availability than base facility metadata, but base endpoints can contribute campsite‑level IDs and names.[^29][^30][^31]

Suggested actions for Computer:
- For campgrounds already known via RIDB/Recreation.gov, optionally call the availability endpoints for structure discovery and verifying facility IDs.[^30][^31][^29]
- Do not rely on scraped HTML; use documented or de facto JSON endpoints where possible.

## Unified Ingestion and De‑duplication Strategy

### Source Prioritization

A pragmatic ingestion order for Alaska might be:

1. RIDB/Recreation.gov (federal baseline).[^1][^2]
2. Active/ReserveAmerica Campground Search API (state and partner additions).[^4][^5][^6]
3. Alaska DNR State Park facilities and Kenai Peninsula Borough campgrounds (state/local).[^3][^10]
4. BLM Alaska recreation features.[^8]
5. OpenStreetMap via Overpass (to fill in gaps and add free/boondocking spots).[^13][^12]
6. Private directories (ACOA, Alaska RV park lists, Alaska.org, ACVB etc.) for private/commercial campgrounds.[^19][^20][^21][^17][^16][^18]
7. Optional: commercial scrapers (Allstays, Campendium) if licensing allows.[^23][^24][^22]

### Identifier Strategy

For each source, maintain a `sources` table with:
- source_id
- name (e.g., `RIDB`, `ACTIVE_RESERVEAMERICA`, `AK_DNR_PARKS`, `OSM`, `ACOA`, `ALASKA_RV_PARKS`, `ALASKA_ORG`, `ALLSTAYS`, `CAMPENDIUM`)
- license_terms
- priority_rank (for conflict resolution)

In the main `campgrounds` table, store `source_id` plus `source_camp_key` (original facility ID, URL, OSM node/way ID, etc.). De‑duplicate by:
- Normalized name and geographic proximity (within a small radius threshold).
- Shared URLs (same official website or reservation portal).
- Shared external IDs (RIDB facility ID matching ReserveAmerica facility ID, etc.).

### Booking Method and Contact Normalization

To standardize booking and contact fields across mixed sources, Computer can:

- booking_method:
  - `online_portal` if any source provides a reservation or booking URL (Recreation.gov, ReserveAmerica, private booking engine).
  - `phone_email` if only phone/email are present and copy indicates reservations by phone/email.
  - `walk_in` if text includes "first‑come, first‑served" or similar.
  - `no_reservations` if text explicitly says no reservations.
- booking_details:
  - Concatenate relevant texts and URLs, including reservation links and notes from directories.
- contact_phone/contact_email:
  - Take highest‑priority (authoritative) source where multiple values exist, but optionally store alternates in a separate `campground_contacts` table.

### Photos and Original Source Links

Photos are typically not directly hosted in APIs but via links:
- RIDB `media` and `links` endpoints provide photo URLs and official website links.[^2]
- Private directories such as Alaska.org and Campendium provide photo URLs on their pages or via scrapers.[^20][^19][^22][^23]

Computer can:
- Store the first available photo URL per campground in `photos_url` and maintain a separate `campground_media` table for additional assets.
- Always store the original page/API URL as `original_source_url` for traceability and debugging.

## Example Task List for an Automated System

Below is a concise set of concrete tasks phrased as actions for an automated system to populate a SQLite database.

1. **Create SQLite schema** with `sources`, `campgrounds`, and optional `campground_media` and `campground_contacts` tables as outlined in the Target Minimum Schema section.
2. **Ingest RIDB/Recreation.gov data**:
   - Query `/facilities` with `state=AK` and relevant filters; store each facility as a campground record with coordinates and contact info.[^1][^2]
   - Query `/campsites` for each facility to add campsite‑level details where desired.[^2]
3. **Ingest Active/ReserveAmerica campgrounds**:
   - Call the Campground Search API with `pstate=AK`, parse XML, and insert campground rows with booking URLs and coordinates.[^5][^6][^4]
4. **Ingest Alaska DNR and local GIS**:
   - Download and parse the Alaska State Park Boundary and Facility dataset, inserting campground‑type facilities.[^3]
   - Download and parse the Kenai Peninsula Borough campgrounds layer and insert records.[^10]
   - From BLM Alaska recreation FeatureServer, extract campground features and insert them.[^8]
5. **Ingest OpenStreetMap camping features**:
   - Run Overpass API queries for Alaska for `tourism=camp_site` and `tourism=caravan_site`; parse results and insert campgrounds with tags mapped into name, contact, and seasonal fields.[^12][^13]
6. **Ingest private directories (if permitted)**:
   - Scrape ACOA’s campground directory, Alaska RV parks lists, and other Alaska‑specific directories; parse tables or text blocks into campground records with addresses and contact info.[^15][^17][^16][^18][^14]
   - Geocode addresses to coordinates.
7. **Ingest curated regional lists**:
   - For each Alaska.org campground region page, parse campgrounds, extract seasonal information, and link to existing campgrounds by name and region.[^21][^19][^20]
8. **Optionally ingest third‑party directory exports**:
   - Configure Allstays and Campendium scrapers (or equivalents) for Alaska, export to CSV/JSON, and import for enriched amenities, ratings, and photos.[^24][^22][^23]
9. **Run de‑duplication and merging**:
   - For each newly inserted campground candidate, attempt to match against existing rows based on proximity, name similarity, and shared URLs; merge attributes according to source priority.
10. **Normalize booking and contact fields**:
    - For each campground, infer `booking_method` and compile `booking_details` from all sources; select canonical `contact_phone` and `contact_email` while preserving alternates in a contacts table.
11. **Maintain refresh logic**:
    - For API‑based sources (RIDB, Active/ReserveAmerica, OSM), schedule periodic re‑ingest/updates and update `last_seen_utc`.
    - For scraped sources, re‑fetch at a lower frequency and diff changes.

This workflow yields a reasonably complete and extensible Alaska campgrounds database that satisfies the minimum fields (name, coordinates, booking method, direct contact) and provides hooks for richer attributes over time.[^17][^19][^20][^21][^16][^18][^1][^2][^10][^3]

---

## References

1. [Recreation Information Database API - PublicAPI](https://publicapi.dev/recreation-information-database-api) - Recreation Information Database API provides Recreational areas, federal lands, historic sites, muse...

2. [Overview:](https://ridb.recreation.gov/shared/swagger/ridb.yaml)

3. [Alaska State Park Boundary and Facility - Alaska DNR Open Data](https://data-soa-dnr.opendata.arcgis.com/maps/8a439547724041a5aa9045d2c8f8fd3b) - Web service showing Alaska State Park managed boundaries, facilities, trails and roads. See other ma...

4. [ACTIVE Network API - Campground API](https://developer.active.com/docs/read/Campground_APIs)

5. [Active.com Camping API - FindAPIs](https://findapis.com/fr/api/activecom-camping) - The Active.com Camping API, backed by Reserve America's database, provides access to campground data...

6. [Campground Search API - ACTIVE Network API](https://developer.active.com/docs/read/campground_search_api)

7. [Public Campgrounds in Alaska - National Park Service](https://www.nps.gov/anch/planyourvisit/public-campgrounds-in-alaska.htm) - Download the NPS app to navigate the parks on the go. Download on the App Store Get it on Google Pla...

8. [Recreation/BLM_AK_Recreation (FeatureServer)](https://gis.blm.gov/akarcgis/rest/services/Recreation/BLM_AK_Recreation/FeatureServer)

9. [State Park Boundary | State of Alaska Geoportal](https://gis.data.alaska.gov/datasets/SOA-DNR::state-park-boundary/about) - This dataset is for mapping and for identifying areas available for public recreation. Boundaries of...

10. [KPB Campgrounds | State of Alaska Geoportal](https://gis.data.alaska.gov/datasets/KPB::kpb-campgrounds/about) - KPB Campgrounds. Kenai Peninsula Borough area campgrounds. Data compiled from various sources. Recre...

11. [Alaska Spatial Data Management System (SDMS)](https://www.blm.gov/services/land-records/sdms) - This portal page provides access to online BLM Alaska land record documents, reports, and an interac...

12. [Finding campsites using OpenStreetMap and Overpass Turbo](https://morris.cloud/osm-campsites/) - The best tool is a service called “Overpass Turbo“. It allows you to make a request for one type of ...

13. [Key:camp_site - OpenStreetMap Wiki](https://wiki.openstreetmap.org/wiki/Key:camp_site) - camp_site. Description. A subkey to tourism = camp_site used to categorize camp sites according to t...

14. [ACOA Member Information | ACOA Alaska Campgrounds](https://akcampgrounds.com/news-events/) - Alaska Campground Owners Association membership directory lists privately owned RV Parks, cabin vaca...

15. [Alaska Campground Owners' Association](https://visitsoldotna.com/listing/alaska-campground-owners-association/) - ACOA is non-profit association of privately owned campground & RV park members and tourism related c...

16. [Alaska Private RV Campsite List and Links](https://alaskafamilymotorhomes.com/alaska-private-rv-campsite-list-links/) - Discover hidden gems among Alaska's private RV campsites with our curated list. Plan your journey, f...

17. [Alaska RV Parks](https://alaskafamilymotorhomes.com/alaska-rv-parks/) - Immerse yourself in the beauty of Alaska with our guide to RV parks. From breathtaking landscapes to...

18. [ACVB Camping-Private/Public/RV Parks Listing - Alaska Net](http://www.alaska.net/~acvb/155.htm)

19. [Denali State Park RV Parks & Campgrounds | ALASKA.ORG](https://www.alaska.org/destination/denali-state-park/rv-parks-and-campgrounds) - Park your RV or pitch your tent in the state park just south of Denali (Mt. McKinley).

20. [Tongass Nat'l Forest RV Parks & Campgrounds | ALASKA.ORG](https://www.alaska.org/destination/tongass-national-forest/rv-parks-and-campgrounds) - Plan your cruise, land tour, or custom package. Discover Alaska's best destinations and excursions. ...

21. [Palmer / Wasilla Area RV Parks & Campgrounds - Alaska.org](https://www.alaska.org/destination/palmer-wasilla/rv-parks-and-campgrounds) - Here’s where to park your RV or set up your tent in the Palmer / Wasilla area

22. [Recreation.gov Campsite Availability Scraper API - Apify](https://apify.com/jungle_synthesizer/recreation-gov-campsite-availability-scraper/api) - Learn how to interact with Recreation.gov Campsite Availability Scraper via API. Includes an example...

23. [Recreation.gov Campsite Availability Scraper MCP server - Apify](https://apify.com/jungle_synthesizer/recreation-gov-campsite-availability-scraper/api/mcp) - Learn how to interact with Recreation.gov Campsite Availability Scraper via Model Context Protocol (...

24. [Allstays Scraper API in JavaScript - Apify](https://apify.com/chimerical_quicklime/allstays-scraper/api/javascript) - Learn how to interact with Allstays Scraper API in JavaScript. Includes an example JavaScript code s...

25. [campsite - Dataset - Catalog - Data.gov](https://catalog.data.gov/dataset/?tags=campsite) - The Home of the U.S. Government's Open Data

26. [National Park Service - 3 - Dataset - Catalog](https://catalog.data.gov/dataset/?organization_type=Federal+Government&tags=structure&bureauCode=010%3A24&publisher=National+Park+Service) - The Home of the U.S. Government's Open Data

27. [76 datasets found for "Campgrounds"](https://catalog.data.gov/dataset?metadata_type=geospatial&_metadata_type_limit=0&q=Campgrounds) - The Home of the U.S. Government's Open Data

28. [BLM AK Survey System - Shapefile - Catalog](https://catalog.data.gov/dataset/blm-ak-survey-system/resource/71aa950c-e5a3-4019-9bcf-3331aa0588ff) - BLM Alaska PLSS Intersected: This dataset represents the GIS Version of the Public Land Survey Syste...

29. [recreation-gov-campsite-checker/README.md at master · banool/recreation-gov-campsite-checker](https://github.com/banool/recreation-gov-campsite-checker/blob/master/README.md) - Scrapes the recreation.gov website to check for campsite availabilities 🏕🏕 - banool/recreation-gov-c...

30. [GitHub - banool/recreation-gov-campsite-checker: Scrapes the recreation.gov website to check for campsite availabilities 🏕🏕](https://github.com/banool/recreation-gov-campsite-checker) - Scrapes the recreation.gov website to check for campsite availabilities 🏕🏕 - banool/recreation-gov-c...

31. [Retrieve campsite availability by month for US Federal campgrounds](https://gist.github.com/carlin-q-scott/dfdeeab55746466701a0dfec5cc7bb2d) - Retrieve campsite availability by month for US Federal campgrounds - query.bat

