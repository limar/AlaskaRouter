#!/usr/bin/env bash
# Filter the Alaska OSM extract down to expedition-relevant POIs.
# Input:  data/alaska-latest.osm.pbf
# Output: data/alaska-filtered.osm.pbf
set -euo pipefail
cd "$(dirname "$0")/.."

osmium tags-filter --overwrite -o data/alaska-filtered.osm.pbf data/alaska-latest.osm.pbf \
  amenity=fuel,drinking_water,restaurant,cafe,fast_food,bar,pub,toilets,shower,bank,atm,hospital,clinic,pharmacy,post_office,ranger_station,shelter,parking,charging_station \
  tourism=camp_site,caravan_site,alpine_hut,wilderness_hut,viewpoint,picnic_site,information,attraction,museum,guest_house,hotel,motel,hostel \
  shop=convenience,supermarket,outdoor,motorcycle,car_repair,car_parts,bicycle,sports,hardware,fishing,hunting \
  highway=ford,services \
  natural=peak,glacier,hot_spring,spring,cave_entrance,volcano \
  place=city,town,village,hamlet,locality,island,suburb,isolated_dwelling \
  aeroway=aerodrome \
  man_made=lighthouse,tower \
  historic=monument,memorial,castle,ruins,wreck \
  waterway=waterfall

ls -lh data/alaska-filtered.osm.pbf
