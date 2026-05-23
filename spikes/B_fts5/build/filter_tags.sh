#!/usr/bin/env bash
# Filter the Alaska OSM extract down to expedition-relevant POIs.
# Input:  data/alaska-latest.osm.pbf
# Output: data/alaska-filtered.osm.pbf
set -euo pipefail
cd "$(dirname "$0")/.."

osmium tags-filter --overwrite -o data/alaska-filtered.osm.pbf data/alaska-latest.osm.pbf \
  amenity=fuel,drinking_water,restaurant,cafe,fast_food,bar,pub,toilets,shower,bank,atm,hospital,clinic,pharmacy,post_office,ranger_station,shelter,parking,charging_station,bicycle_rental,motorcycle_rental,car_rental,boat_rental,ferry_terminal,community_centre,library \
  tourism=camp_site,caravan_site,alpine_hut,wilderness_hut,viewpoint,picnic_site,information,attraction,museum,guest_house,hotel,motel,hostel,artwork,gallery \
  shop=convenience,supermarket,outdoor,motorcycle,car_repair,car_parts,bicycle,sports,hardware,fishing,hunting \
  highway=ford,services \
  natural=peak,glacier,hot_spring,spring,cave_entrance,volcano,bay,beach,reef,strait,arch,cliff,ridge,saddle,fjord \
  place=city,town,village,hamlet,locality,island,suburb,isolated_dwelling \
  aeroway=aerodrome,heliport \
  man_made=lighthouse,tower,monument,sign,obelisk,memorial,cairn,pier \
  historic=monument,memorial,castle,ruins,wreck \
  waterway=waterfall \
  leisure=park,nature_reserve,marina,slipway \
  boundary=national_park,protected_area \
  craft=brewery,winery,distillery,bakery,blacksmith \
  office=guide

ls -lh data/alaska-filtered.osm.pbf
