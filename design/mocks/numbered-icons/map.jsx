// map.jsx — Hand-built stylized topo of the Dalton Highway corridor.
// Two visual variants: 'paper' (warm parchment topo) and 'field' (cool, cleaner Apple Maps lean).

// ─────────────────────────────────────────────────────────────
// Palette
// ─────────────────────────────────────────────────────────────
const MAP_THEMES = {
  paper: {
    bg: '#efe5cf',
    land: '#f3ecd6',
    landHi: '#f8f1dc',
    tundra: '#e3dabf',
    forest: '#aebd87',
    forestDeep: '#94a86b',
    rock: '#cdb791',
    rockShade: '#a78f64',
    snow: '#eef0eb',
    glacier: '#dde6e6',
    water: '#a9c5d3',
    waterEdge: '#6f93a8',
    road: '#2c2a25',
    roadCasing: '#f5ecd4',
    gravel: '#7a6a4a',
    contour: 'rgba(146,114,72,.42)',
    contourMajor: 'rgba(146,114,72,.65)',
    grid: 'rgba(80,60,30,.06)',
    labelMajor: '#2a2520',
    labelMinor: '#6e6452',
    labelWater: '#3a6479',
  },
  field: {
    bg: '#e8eae3',
    land: '#eef0e8',
    landHi: '#f4f6ee',
    tundra: '#e0e2d6',
    forest: '#a9c4a0',
    forestDeep: '#86a87b',
    rock: '#cfcdc2',
    rockShade: '#a8a597',
    snow: '#f3f4f1',
    glacier: '#dee6e8',
    water: '#aac7d2',
    waterEdge: '#6c93a4',
    road: '#1f2120',
    roadCasing: '#fafbf6',
    gravel: '#6e7268',
    contour: 'rgba(60,80,60,.32)',
    contourMajor: 'rgba(60,80,60,.55)',
    grid: 'rgba(40,60,40,.05)',
    labelMajor: '#1b2520',
    labelMinor: '#5a665a',
    labelWater: '#3b6675',
  },
};

// ─────────────────────────────────────────────────────────────
// Geographic features as path data (hand-authored)
// Coordinate system: SVG viewBox 900 × 1700.
// North is up. Dalton Highway runs roughly south-north.
// ─────────────────────────────────────────────────────────────

// Dalton Highway centerline — kinks through the Yukon flats, climbs Brooks Range,
// then runs the Sagavanirktok river plain to Deadhorse.
const DALTON =
  'M 348 1640 ' +              // Fairbanks
  'L 352 1580 L 350 1540 ' +   // Fox / start of haul road
  'L 346 1480 L 338 1430 ' +   // Livengood
  'C 332 1390, 320 1360, 308 1330 ' + // descend to Yukon
  'L 296 1300 ' +
  'C 290 1270, 296 1250, 308 1230 ' +
  'L 326 1190 L 340 1140 ' +   // Finger Mountain
  'L 352 1090 L 360 1050 ' +   // Arctic Circle
  'L 366 1010 L 372 970 ' +
  'L 376 940 L 378 916 ' +     // Coldfoot
  'L 380 880 ' +               // Wiseman
  'C 388 840, 410 800, 420 760 ' +
  'L 418 730 ' +               // Atigun pass
  'C 426 700, 438 670, 440 640 ' +
  'L 438 600 ' +               // Galbraith Lake
  'L 448 540 L 462 480 ' +
  'L 478 420 L 494 360 ' +
  'L 504 300 L 510 240 ' +     // Franklin Bluffs
  'L 514 180 L 512 130';       // Deadhorse / Prudhoe Bay

// Side road to Denali Park entrance (Parks Hwy stub)
const PARKS_TO_DENALI =
  'M 348 1640 ' +
  'C 280 1630, 230 1645, 195 1632 ' +
  'L 158 1610 ' +
  'C 130 1595, 110 1580, 95 1565';

// Yukon River — broad east-flowing river crossing the south of the map
const YUKON =
  'M 30 1290 ' +
  'C 90 1280, 140 1300, 200 1295 ' +
  'C 240 1290, 270 1305, 308 1325 ' +
  'C 350 1342, 400 1340, 440 1320 ' +
  'C 490 1295, 540 1305, 590 1325 ' +
  'C 640 1342, 700 1340, 760 1320 ' +
  'C 810 1305, 850 1320, 870 1340';

// Koyukuk middle fork — flows past Coldfoot/Wiseman from the Brooks
const KOYUKUK =
  'M 220 720 ' +
  'C 240 760, 280 800, 310 840 ' +
  'C 340 880, 370 900, 378 920 ' +
  'C 386 940, 380 970, 372 1000';

// Sagavanirktok River (the "Sag") — runs alongside the haul road through coastal plain
const SAG_RIVER =
  'M 460 760 ' +
  'C 470 720, 480 680, 490 640 ' +
  'C 500 600, 504 540, 504 490 ' +
  'C 504 430, 510 370, 514 310 ' +
  'C 516 260, 520 210, 524 170 ' +
  'L 528 120';

// Atigun River (small tributary across the pass)
const ATIGUN = 'M 420 760 C 432 740, 440 720, 442 700 C 444 680, 448 660, 448 640';

// Brooks Range crest (rocky band)
const BROOKS_CREST = 'M 60 690 C 160 660, 260 680, 360 700 C 460 720, 560 695, 700 685 C 800 678, 860 680, 890 678';

// Forest mask region (taiga south of Brooks)
const FOREST_REGION =
  'M 0 800 L 900 800 L 900 1700 L 0 1700 Z';

// Coastal plain (north of Brooks, tundra)
const TUNDRA_REGION = 'M 0 0 L 900 0 L 900 660 L 0 660 Z';

// Mountain blob shapes for Brooks Range — soft elevation patches
const BROOKS_BLOBS = [
  'M 80 700 C 120 660, 200 670, 260 690 C 300 710, 320 740, 280 770 C 220 790, 140 770, 90 750 Z',
  'M 280 690 C 360 660, 460 670, 540 690 C 580 710, 580 760, 500 780 C 420 790, 340 770, 290 750 Z',
  'M 540 695 C 620 680, 720 680, 810 700 C 860 720, 850 760, 770 770 C 680 780, 590 760, 530 740 Z',
];

// Alaska Range to the southwest (for Denali presence)
const ALASKA_RANGE_BLOBS = [
  'M 30 1580 C 80 1560, 140 1565, 180 1580 C 200 1600, 180 1625, 130 1625 C 80 1622, 40 1610, 30 1595 Z',
  'M 0 1640 C 60 1630, 110 1640, 140 1655 C 130 1680, 80 1685, 30 1680 C 10 1670, 0 1655, 0 1645 Z',
];

// Lakes
const LAKES = [
  { d: 'M 420 590 C 440 585, 460 588, 470 600 C 472 615, 450 622, 428 618 C 416 612, 414 598, 420 590 Z', name: 'Galbraith Lake' },
  { d: 'M 130 1120 C 150 1115, 170 1120, 175 1130 C 170 1142, 145 1140, 130 1132 Z', name: 'Kanuti Lake' },
  { d: 'M 600 1100 C 622 1098, 638 1108, 632 1118 C 618 1126, 596 1120, 596 1110 Z', name: '' },
  { d: 'M 700 1450 C 720 1448, 736 1456, 730 1466 C 712 1472, 696 1466, 696 1458 Z', name: '' },
];

// ─────────────────────────────────────────────────────────────
// POIs along the route
// ─────────────────────────────────────────────────────────────
const POIS = [
  // Cities / towns
  { id: 'fairbanks',  x: 348, y: 1640, kind: 'city',     name: 'Fairbanks',   size: 'lg' },
  { id: 'fox',        x: 350, y: 1540, kind: 'town',     name: 'Fox',         size: 'sm' },
  { id: 'livengood',  x: 338, y: 1430, kind: 'town',     name: 'Livengood',   size: 'sm' },
  { id: 'yukon',      x: 296, y: 1300, kind: 'fuel',     name: 'Yukon River Camp', sub: 'Fuel · Café' },
  { id: 'fingermt',   x: 340, y: 1140, kind: 'view',     name: 'Finger Mountain' },
  { id: 'arctic',     x: 360, y: 1050, kind: 'landmark', name: 'Arctic Circle' },
  { id: 'coldfoot',   x: 378, y: 916,  kind: 'fuel',     name: 'Coldfoot',    sub: 'Fuel · Lodge · Visitor Ctr' },
  { id: 'wiseman',    x: 380, y: 880,  kind: 'camp',     name: 'Wiseman' },
  { id: 'atigun',     x: 418, y: 730,  kind: 'pass',     name: 'Atigun Pass', sub: '4,739 ft · Continental Divide' },
  { id: 'galbraith',  x: 438, y: 600,  kind: 'camp',     name: 'Galbraith Lake', sub: 'Primitive camp' },
  { id: 'franklin',   x: 510, y: 240,  kind: 'view',     name: 'Franklin Bluffs' },
  { id: 'deadhorse',  x: 512, y: 130,  kind: 'fuel',     name: 'Deadhorse',   sub: 'Prudhoe Bay · End of Road', size: 'lg' },
  // Side / context POIs
  { id: 'denali',     x: 95,  y: 1565, kind: 'park',     name: 'Denali National Park', size: 'md' },
  { id: 'marion',     x: 376, y: 905,  kind: 'camp',     name: 'Marion Creek' },
  { id: 'fivemile',   x: 308, y: 1230, kind: 'camp',     name: 'Five Mile' },
  { id: 'arctic_vc',  x: 388, y: 920,  kind: 'visitor', name: 'Arctic Interagency VC' },
];

// ─────────────────────────────────────────────────────────────
// Annotations (typed but rendered with handwritten font)
// ─────────────────────────────────────────────────────────────
const DEFAULT_ANNOTATIONS = [
  {
    id: 'a1',
    text: '240 mi · no fuel\nstart Coldfoot full',
    color: '#c2410c',
    x: 220, y: 1110,
    anchor: { x: 320, y: 1130 },
    rot: -3,
  },
  {
    id: 'a2',
    text: 'check weather\nbefore the pass!',
    color: '#1d4ed8',
    x: 510, y: 690,
    anchor: { x: 420, y: 720 },
    rot: 2,
  },
  {
    id: 'a3',
    text: 'sweet pull-off,\nmuskox in june',
    color: '#15803d',
    x: 600, y: 320,
    anchor: { x: 514, y: 300 },
    rot: -2,
  },
];

// ─────────────────────────────────────────────────────────────
// Contour lines (rough hand-authored elevation strokes)
// ─────────────────────────────────────────────────────────────
const CONTOURS = [
  // Brooks Range — denser
  'M 70 720 C 160 700, 260 712, 360 720 C 460 728, 560 718, 700 712 C 800 708, 860 712, 890 718',
  'M 80 740 C 180 728, 270 740, 360 748 C 460 758, 560 748, 700 740 C 800 736, 860 742, 890 750',
  'M 70 700 C 160 685, 260 695, 360 700 C 460 706, 560 696, 700 692 C 800 690, 860 695, 890 700',
  'M 60 680 C 150 668, 250 678, 350 682 C 450 688, 560 678, 700 672 C 800 668, 860 673, 890 678',
  // Above the range — coastal foothills
  'M 100 640 C 200 632, 320 638, 460 638 C 580 636, 700 638, 880 642',
  'M 120 600 C 220 596, 340 600, 480 600 C 600 600, 720 602, 880 606',
  // North slope plain — wide gentle
  'M 50 480 C 200 478, 380 480, 560 482 C 720 484, 820 484, 890 488',
  'M 50 380 C 200 380, 380 382, 560 384 C 720 386, 820 386, 890 390',
  'M 50 280 C 200 282, 380 282, 560 282 C 720 282, 820 282, 890 286',
  'M 50 200 C 200 200, 380 202, 560 202 C 720 202, 820 202, 890 204',
  // South side — taiga rolls
  'M 30 880 C 160 870, 260 882, 380 882 C 500 880, 620 884, 880 882',
  'M 40 950 C 160 944, 280 950, 400 952 C 540 950, 680 950, 880 954',
  'M 40 1050 C 180 1044, 280 1052, 400 1058 C 540 1054, 680 1056, 880 1060',
  'M 40 1180 C 180 1176, 290 1180, 410 1184 C 540 1184, 680 1182, 880 1186',
  'M 40 1430 C 180 1426, 290 1432, 410 1438 C 540 1436, 680 1436, 880 1438',
  'M 40 1500 C 180 1500, 290 1506, 410 1512 C 540 1508, 680 1510, 880 1512',
  // Alaska Range
  'M 0 1600 C 80 1592, 160 1600, 220 1608 C 280 1616, 360 1614, 460 1612',
  'M 0 1630 C 80 1626, 160 1632, 220 1638 C 280 1644, 360 1642, 460 1640',
];

// Major contours (every 5th)
const CONTOURS_MAJOR = [
  'M 60 680 C 150 668, 250 678, 350 682 C 450 688, 560 678, 700 672 C 800 668, 860 673, 890 678',
  'M 50 380 C 200 380, 380 382, 560 384 C 720 386, 820 386, 890 390',
  'M 40 1050 C 180 1044, 280 1052, 400 1058 C 540 1054, 680 1056, 880 1060',
];

// ─────────────────────────────────────────────────────────────
// Map component
// ─────────────────────────────────────────────────────────────
function ExpeditionMap({
  theme = 'paper',
  panX, panY, zoom = 1,
  routeSegments = [],
  routeStops = {},          // { [poiId]: { number, color } } — POIs on the active trip
  waypointStyle = 'pin',    // 'pin' | 'stamp' | 'dot' | 'tag'
  onPan, onPoiTap, selectedPoi,
  showAnnotations = true,
  annotations = DEFAULT_ANNOTATIONS,
  labelDensity = 'normal', // 'low' | 'normal' | 'high'
  addingAnnotation = false,
  onMapTap,
}) {
  const T = MAP_THEMES[theme] || MAP_THEMES.paper;
  const ref = React.useRef(null);
  const daltonRef = React.useRef(null);
  // POI distance-along-Dalton cache. Computed once after first render by
  // sampling the rendered <path>'s getPointAtLength — paths POIs sit near
  // get a length, others fall back to a straight segment.
  const [poiLen, setPoiLen] = React.useState({ ready: false, lens: {}, total: 0 });
  React.useEffect(() => {
    const path = daltonRef.current;
    if (!path) return;
    const total = path.getTotalLength();
    const SAMPLES = 1200;
    const lens = {};
    POIS.forEach((poi) => {
      let bestL = 0, bestD = Infinity;
      for (let i = 0; i <= SAMPLES; i++) {
        const L = (i / SAMPLES) * total;
        const pt = path.getPointAtLength(L);
        const d = (pt.x - poi.x) ** 2 + (pt.y - poi.y) ** 2;
        if (d < bestD) { bestD = d; bestL = L; }
      }
      // Only accept if the POI lies reasonably close to the road
      if (bestD < 28 * 28) lens[poi.id] = bestL;
    });
    setPoiLen({ ready: true, lens, total });
  }, []);

  // Pan handling
  const panState = React.useRef(null);
  const onPointerDown = (e) => {
    if (addingAnnotation) return; // tap-to-place instead
    const t = e.target;
    // Don't start a pan when tapping a POI / annotation hit area
    if (t.closest && (t.closest('[data-poi]') || t.closest('[data-annot]'))) return;
    panState.current = { x: e.clientX, y: e.clientY, px: panX, py: panY };
    e.currentTarget.setPointerCapture && e.currentTarget.setPointerCapture(e.pointerId);
  };
  const onPointerMove = (e) => {
    if (!panState.current) return;
    const dx = (e.clientX - panState.current.x) / zoom;
    const dy = (e.clientY - panState.current.y) / zoom;
    onPan && onPan(panState.current.px + dx, panState.current.py + dy);
  };
  const onPointerUp = () => { panState.current = null; };

  // Tap-to-place annotation
  const onClick = (e) => {
    if (!addingAnnotation) return;
    const svg = ref.current.querySelector('svg');
    const pt = svg.createSVGPoint();
    pt.x = e.clientX; pt.y = e.clientY;
    const ctm = svg.getScreenCTM();
    if (!ctm) return;
    const { x, y } = pt.matrixTransform(ctm.inverse());
    onMapTap && onMapTap({ x, y });
  };



  return (
    <div
      ref={ref}
      style={{
        position: 'absolute', inset: 0, overflow: 'hidden',
        background: T.bg, touchAction: 'none',
        cursor: addingAnnotation ? 'crosshair' : 'grab',
      }}
      onPointerDown={onPointerDown}
      onPointerMove={onPointerMove}
      onPointerUp={onPointerUp}
      onPointerCancel={onPointerUp}
      onClick={onClick}
    >
      <div style={{
        position: 'absolute',
        left: panX, top: panY,
        transform: `scale(${zoom})`,
        transformOrigin: '0 0',
        width: 900, height: 1700,
        willChange: 'transform',
      }}>
        <svg
          width="900"
          height="1700"
          viewBox="0 0 900 1700"
          xmlns="http://www.w3.org/2000/svg"
          style={{ display: 'block' }}
        >
          <defs>
            {/* Paper grain */}
            <filter id="paperGrain" x="0" y="0" width="100%" height="100%">
              <feTurbulence type="fractalNoise" baseFrequency="0.85" numOctaves="2" seed="3" />
              <feColorMatrix values="0 0 0 0 0.55  0 0 0 0 0.43  0 0 0 0 0.22  0 0 0 0.10 0" />
              <feComposite in2="SourceGraphic" operator="in" />
            </filter>
            {/* Soft shadow under floating cards drawn on map */}
            <filter id="softShadow" x="-50%" y="-50%" width="200%" height="200%">
              <feGaussianBlur stdDeviation="2" />
            </filter>
            {/* Forest stipple pattern */}
            <pattern id="forestStipple" x="0" y="0" width="14" height="14" patternUnits="userSpaceOnUse">
              <rect width="14" height="14" fill={T.forest} opacity="0.55" />
              <circle cx="3" cy="4" r="1.1" fill={T.forestDeep} opacity="0.7" />
              <circle cx="10" cy="2" r="0.9" fill={T.forestDeep} opacity="0.5" />
              <circle cx="7" cy="9" r="1.2" fill={T.forestDeep} opacity="0.8" />
              <circle cx="12" cy="11" r="1" fill={T.forestDeep} opacity="0.6" />
              <circle cx="2" cy="11" r="0.8" fill={T.forestDeep} opacity="0.5" />
            </pattern>
            {/* Tundra / coastal plain pattern */}
            <pattern id="tundraStipple" x="0" y="0" width="22" height="22" patternUnits="userSpaceOnUse">
              <rect width="22" height="22" fill={T.tundra} opacity="0.6" />
              <circle cx="4" cy="6" r="0.7" fill={T.labelMinor} opacity="0.18" />
              <circle cx="14" cy="3" r="0.6" fill={T.labelMinor} opacity="0.16" />
              <circle cx="17" cy="14" r="0.8" fill={T.labelMinor} opacity="0.2" />
              <circle cx="7" cy="17" r="0.7" fill={T.labelMinor} opacity="0.18" />
            </pattern>
            {/* Rocky hatch for mountains */}
            <pattern id="rockHatch" x="0" y="0" width="6" height="6" patternUnits="userSpaceOnUse" patternTransform="rotate(35)">
              <rect width="6" height="6" fill={T.rock} />
              <line x1="0" y1="0" x2="0" y2="6" stroke={T.rockShade} strokeWidth="0.4" opacity="0.55" />
            </pattern>
          </defs>

          {/* ── Base land ── */}
          <rect x="0" y="0" width="900" height="1700" fill={T.land} />

          {/* Gentle elevation tinting (north plain slightly cooler, south slightly warmer) */}
          <rect x="0" y="0" width="900" height="660" fill={T.tundra} opacity="0.55" />
          <rect x="0" y="800" width="900" height="900" fill={T.forest} opacity="0.12" />

          {/* ── Lat/Lon graticule (paper map cross-hatch) ── */}
          <g stroke={T.grid} strokeWidth="0.7">
            {Array.from({ length: 9 }).map((_, i) => (
              <line key={'gx'+i} x1={i*100} y1="0" x2={i*100} y2="1700" />
            ))}
            {Array.from({ length: 17 }).map((_, i) => (
              <line key={'gy'+i} x1="0" y1={i*100} x2="900" y2={i*100} />
            ))}
          </g>

          {/* ── Tundra dotting (north of Brooks) ── */}
          <rect x="0" y="0" width="900" height="660" fill="url(#tundraStipple)" />

          {/* ── Forest stipple (south of Brooks) ── */}
          <path
            d="M 0 820 C 200 810, 400 830, 600 820 C 720 815, 820 825, 900 820 L 900 1700 L 0 1700 Z"
            fill="url(#forestStipple)"
          />
          {/* Pull forest back a bit around Yukon flats */}
          <path
            d="M 60 1280 C 200 1260, 400 1290, 600 1280 C 720 1275, 820 1290, 900 1290 L 900 1380 L 0 1380 Z"
            fill={T.land} opacity="0.7"
          />

          {/* ── Brooks Range mass ── */}
          {BROOKS_BLOBS.map((d, i) => (
            <g key={'br'+i}>
              <path d={d} fill="url(#rockHatch)" />
              <path d={d} fill={T.rockShade} opacity="0.18" />
              <path d={d} fill="none" stroke={T.rockShade} strokeWidth="0.8" opacity="0.6" />
            </g>
          ))}
          {/* Snow caps */}
          <path d="M 220 700 C 240 692, 270 692, 290 702 C 280 712, 240 712, 220 700 Z" fill={T.snow} opacity="0.9" />
          <path d="M 380 695 C 410 686, 460 686, 480 698 C 460 708, 410 708, 380 695 Z" fill={T.snow} opacity="0.9" />
          <path d="M 600 690 C 640 682, 690 684, 720 694 C 690 704, 640 704, 600 690 Z" fill={T.snow} opacity="0.85" />

          {/* ── Alaska Range (Denali area, SW corner) ── */}
          {ALASKA_RANGE_BLOBS.map((d, i) => (
            <g key={'ar'+i}>
              <path d={d} fill="url(#rockHatch)" />
              <path d={d} fill="none" stroke={T.rockShade} strokeWidth="0.8" opacity="0.5" />
            </g>
          ))}
          <path d="M 70 1592 C 90 1584, 120 1584, 140 1594 C 125 1604, 95 1604, 70 1592 Z" fill={T.snow} opacity="0.9" />

          {/* ── Glacier (small patch on Brooks) ── */}
          <path d="M 460 706 C 478 700, 498 702, 506 712 C 498 720, 478 722, 460 718 Z"
                fill={T.glacier} stroke={T.waterEdge} strokeOpacity="0.25" strokeWidth="0.6" />

          {/* ── Contour lines ── */}
          <g fill="none" stroke={T.contour} strokeWidth="0.55">
            {CONTOURS.map((d, i) => <path key={'c'+i} d={d} />)}
          </g>
          <g fill="none" stroke={T.contourMajor} strokeWidth="0.9">
            {CONTOURS_MAJOR.map((d, i) => <path key={'cM'+i} d={d} />)}
          </g>

          {/* ── Rivers ── */}
          {/* Yukon — wide */}
          <path d={YUKON} fill="none" stroke={T.water} strokeWidth="9" strokeLinecap="round" />
          <path d={YUKON} fill="none" stroke={T.waterEdge} strokeWidth="0.7" strokeOpacity="0.6" />
          {/* Koyukuk */}
          <path d={KOYUKUK} fill="none" stroke={T.water} strokeWidth="3.5" strokeLinecap="round" />
          <path d={KOYUKUK} fill="none" stroke={T.waterEdge} strokeWidth="0.5" strokeOpacity="0.5" />
          {/* Sagavanirktok */}
          <path d={SAG_RIVER} fill="none" stroke={T.water} strokeWidth="3.5" strokeLinecap="round" />
          <path d={SAG_RIVER} fill="none" stroke={T.waterEdge} strokeWidth="0.5" strokeOpacity="0.5" />
          {/* Atigun (small) */}
          <path d={ATIGUN} fill="none" stroke={T.water} strokeWidth="1.6" strokeLinecap="round" />

          {/* Lakes */}
          {LAKES.map((l, i) => (
            <g key={'l'+i}>
              <path d={l.d} fill={T.water} stroke={T.waterEdge} strokeWidth="0.6" strokeOpacity="0.7" />
            </g>
          ))}

          {/* ── Roads ── */}
          {/* Dalton casing (light) then dark line, then dashed center (gravel) */}
          <path ref={daltonRef} d={DALTON} fill="none" stroke={T.roadCasing} strokeWidth="6" strokeLinecap="round" />
          <path d={DALTON} fill="none" stroke={T.road} strokeWidth="2.6" strokeLinecap="round" />
          <path d={DALTON} fill="none" stroke={T.gravel} strokeWidth="1.2" strokeLinecap="round" strokeDasharray="3 4" opacity="0.85" />
          {/* Parks Hwy stub (paved — solid) */}
          <path d={PARKS_TO_DENALI} fill="none" stroke={T.roadCasing} strokeWidth="5" strokeLinecap="round" />
          <path d={PARKS_TO_DENALI} fill="none" stroke={T.road} strokeWidth="2.2" strokeLinecap="round" />

          {/* ── Route highlights — translucent marker on top of the road ── */}
          {poiLen.ready && routeSegments.map((seg, i) => {
            const a = poiLen.lens[seg.fromId];
            const b = poiLen.lens[seg.toId];
            if (a == null || b == null) {
              // Straight fallback (one endpoint not on Dalton — e.g., Denali)
              const A = POIS.find(p => p.id === seg.fromId);
              const B = POIS.find(p => p.id === seg.toId);
              if (!A || !B) return null;
              return (
                <line key={'seg' + i}
                      x1={A.x} y1={A.y} x2={B.x} y2={B.y}
                      stroke={seg.color} strokeWidth="7"
                      strokeLinecap="round" opacity="0.34"
                      strokeDasharray="6 5" />
              );
            }
            const L1 = Math.min(a, b), L2 = Math.max(a, b);
            const segLen = L2 - L1;
            // Two strokes per segment: a wide soft marker wash, then a slightly
            // tighter inner highlight — both translucent so the road line, road
            // casing, and the dashed gravel center remain legible underneath.
            return (
              <g key={'seg' + i}>
                <path d={DALTON} fill="none" stroke={seg.color} strokeWidth="11"
                      strokeLinecap="round" opacity="0.18"
                      strokeDasharray={`${segLen} ${poiLen.total}`}
                      strokeDashoffset={-L1} />
                <path d={DALTON} fill="none" stroke={seg.color} strokeWidth="6"
                      strokeLinecap="round" opacity="0.34"
                      strokeDasharray={`${segLen} ${poiLen.total}`}
                      strokeDashoffset={-L1} />
              </g>
            );
          })}

          {/* ── Place labels ── */}
          <RegionLabel x={140} y={420} size={26} theme={T} text="NORTH SLOPE" letterSpacing="6" opacity="0.55" />
          <RegionLabel x={140} y={760} size={22} theme={T} text="BROOKS  RANGE" letterSpacing="5" opacity="0.6" />
          <RegionLabel x={140} y={1180} size={20} theme={T} text="YUKON  FLATS" letterSpacing="5" opacity="0.5" />
          <RegionLabel x={160} y={1660} size={18} theme={T} text="ALASKA  RANGE" letterSpacing="4" opacity="0.5" />

          <text x={170} y={1340} className="map-label" fontSize="13" fill={T.labelWater}
                fontStyle="italic" letterSpacing="2" opacity="0.9">Yukon  River</text>
          <text x={420} y={490} className="map-label" fontSize="11" fill={T.labelWater}
                fontStyle="italic" letterSpacing="1" opacity="0.85"
                transform="rotate(-78 470 480)">Sagavanirktok River</text>
          <text x={320} y={830} className="map-label" fontSize="10" fill={T.labelWater}
                fontStyle="italic" letterSpacing="0.5" opacity="0.85"
                transform="rotate(35 350 830)">Koyukuk</text>

          <text x={450} y={595} className="map-label" fontSize="9" fill={T.labelWater} opacity="0.85">Galbraith L.</text>

          {/* ── POI markers + labels ── */}
          {POIS.map((p) => {
            const stop = routeStops[p.id];
            if (stop) {
              return (
                <WaypointMarker
                  key={p.id}
                  poi={p}
                  number={stop.number}
                  color={stop.color}
                  style={waypointStyle}
                  zoom={zoom}
                  T={T}
                  selected={selectedPoi === p.id}
                  onTap={() => onPoiTap && onPoiTap(p.id)}
                />
              );
            }
            return (
              <PoiMarker
                key={p.id}
                poi={p}
                T={T}
                selected={selectedPoi === p.id}
                onTap={() => onPoiTap && onPoiTap(p.id)}
                labelDensity={labelDensity}
              />
            );
          })}

          {/* ── Annotations ── */}
          {showAnnotations && annotations.map((a) => (
            <Annotation key={a.id} a={a} />
          ))}

          {/* ── Compass rose (top right) ── */}
          <g transform="translate(840, 60)" opacity="0.6">
            <circle r="22" fill="none" stroke={T.labelMinor} strokeWidth="0.7" />
            <path d="M 0 -20 L 4 0 L 0 20 L -4 0 Z" fill={T.labelMajor} opacity="0.8" />
            <path d="M 0 -20 L 4 0 L 0 0 Z" fill={T.labelMajor} />
            <text y="-26" textAnchor="middle" className="map-label" fontSize="10" fontWeight="600" fill={T.labelMajor}>N</text>
          </g>

          {/* ── Scale bar ── */}
          <g transform="translate(40, 1660)" opacity="0.7">
            <line x1="0" y1="0" x2="80" y2="0" stroke={T.labelMajor} strokeWidth="1.3" />
            <line x1="0" y1="-3" x2="0" y2="3" stroke={T.labelMajor} strokeWidth="1.3" />
            <line x1="40" y1="-2" x2="40" y2="2" stroke={T.labelMajor} strokeWidth="1" />
            <line x1="80" y1="-3" x2="80" y2="3" stroke={T.labelMajor} strokeWidth="1.3" />
            <text x="0" y="14" className="map-label" fontSize="9" fill={T.labelMinor}>0</text>
            <text x="78" y="14" className="map-label" fontSize="9" fill={T.labelMinor}>40 mi</text>
          </g>

          {/* Subtle paper grain overlay */}
          {theme === 'paper' && (
            <rect x="0" y="0" width="900" height="1700" fill="black" opacity="0.025" filter="url(#paperGrain)" pointerEvents="none" />
          )}
        </svg>
      </div>
    </div>
  );
}

// Faint region label
function RegionLabel({ x, y, size, theme, text, letterSpacing, opacity = 0.5 }) {
  return (
    <text x={x} y={y}
          fontFamily='"Source Serif 4", Georgia, serif'
          fontSize={size}
          fontWeight="500"
          letterSpacing={letterSpacing}
          fill={theme.labelMinor}
          opacity={opacity}>
      {text}
    </text>
  );
}

// ─────────────────────────────────────────────────────────────
// POI marker
// ─────────────────────────────────────────────────────────────
function PoiMarker({ poi, T, selected, onTap, labelDensity }) {
  const kind = poi.kind;
  const isMajor = poi.size === 'lg' || kind === 'fuel' || kind === 'pass' || kind === 'park';

  // Density gate
  const show =
    labelDensity === 'high' ? true :
    labelDensity === 'normal' ? (isMajor || kind === 'camp' || kind === 'landmark' || kind === 'view') :
    isMajor;

  const fontSize = poi.size === 'lg' ? 13 : (isMajor ? 11 : 10);
  const labelColor = isMajor ? T.labelMajor : T.labelMinor;
  const labelWeight = isMajor ? 600 : 500;

  return (
    <g data-poi style={{ cursor: 'pointer' }} onClick={(e) => { e.stopPropagation(); onTap(); }}>
      {/* Hit area */}
      <circle cx={poi.x} cy={poi.y} r="14" fill="transparent" />
      <PoiGlyph poi={poi} T={T} selected={selected} />
      {show && (
        <text
          x={poi.x + glyphLabelOffset(kind).x}
          y={poi.y + glyphLabelOffset(kind).y}
          fontFamily='"Source Serif 4", Georgia, serif'
          fontSize={fontSize}
          fontWeight={labelWeight}
          fill={labelColor}
          paintOrder="stroke"
          stroke={T.land}
          strokeWidth="3"
          strokeLinejoin="round">
          {poi.name}
        </text>
      )}
      {/* Selected glow */}
      {selected && (
        <circle cx={poi.x} cy={poi.y} r="11"
                fill="none" stroke="#ea580c" strokeWidth="1.6" opacity="0.85">
          <animate attributeName="r" from="9" to="14" dur="1.4s" repeatCount="indefinite" />
          <animate attributeName="opacity" from="0.85" to="0" dur="1.4s" repeatCount="indefinite" />
        </circle>
      )}
    </g>
  );
}

function glyphLabelOffset(kind) {
  if (kind === 'city') return { x: 9, y: 4 };
  if (kind === 'park') return { x: 9, y: 4 };
  return { x: 9, y: 3 };
}

function PoiGlyph({ poi, T, selected }) {
  const { x, y, kind } = poi;
  const stroke = T.labelMajor;
  const sw = 1.2;
  if (kind === 'city') {
    return (
      <>
        <circle cx={x} cy={y} r="5.2" fill="#fff" stroke={stroke} strokeWidth="1.4" />
        <circle cx={x} cy={y} r="2.2" fill={stroke} />
      </>
    );
  }
  if (kind === 'fuel') {
    return (
      <g>
        <circle cx={x} cy={y} r="6.4" fill="#fff" stroke={stroke} strokeWidth="1.2" />
        <path d={`M ${x-2.2} ${y-2.4} h 3.4 v 5 h -3.4 z`} fill="none" stroke={stroke} strokeWidth="1" strokeLinejoin="round" />
        <path d={`M ${x+1.4} ${y-1} l 1.6 0.6 v 2.2`} fill="none" stroke={stroke} strokeWidth="1" strokeLinecap="round" />
      </g>
    );
  }
  if (kind === 'camp') {
    return (
      <g>
        <circle cx={x} cy={y} r="6" fill="#fff" stroke={stroke} strokeWidth="1.1" />
        <path d={`M ${x-3.2} ${y+2.2} L ${x} ${y-2.6} L ${x+3.2} ${y+2.2} Z`} fill="none" stroke={stroke} strokeWidth="1" strokeLinejoin="round" />
      </g>
    );
  }
  if (kind === 'visitor') {
    return (
      <g>
        <circle cx={x} cy={y} r="6" fill="#fff" stroke={stroke} strokeWidth="1.1" />
        <text x={x} y={y+2.4} textAnchor="middle" fontFamily="Georgia, serif" fontSize="7.5" fontStyle="italic" fontWeight="700" fill={stroke}>i</text>
      </g>
    );
  }
  if (kind === 'pass') {
    return (
      <g>
        <path d={`M ${x-6} ${y+2.4} L ${x} ${y-5} L ${x+6} ${y+2.4} Z`} fill="#fff" stroke={stroke} strokeWidth="1.2" strokeLinejoin="round" />
        <line x1={x-2.6} y1={y+0.6} x2={x+2.6} y2={y+0.6} stroke={stroke} strokeWidth="0.9" />
      </g>
    );
  }
  if (kind === 'view') {
    return (
      <g>
        <circle cx={x} cy={y} r="5.4" fill="#fff" stroke={stroke} strokeWidth="1.1" />
        <circle cx={x} cy={y} r="1.7" fill={stroke} />
        <circle cx={x} cy={y} r="3" fill="none" stroke={stroke} strokeWidth="0.8" />
      </g>
    );
  }
  if (kind === 'landmark') {
    return (
      <g>
        <circle cx={x} cy={y} r="6.5" fill="none" stroke={stroke} strokeWidth="1" strokeDasharray="2 1.6" />
        <circle cx={x} cy={y} r="1.6" fill={stroke} />
      </g>
    );
  }
  if (kind === 'park') {
    return (
      <g>
        <path d={`M ${x-5} ${y+3} L ${x-2} ${y-3} L ${x} ${y+1} L ${x+2} ${y-4} L ${x+5} ${y+3} Z`}
              fill={T.forestDeep} stroke={stroke} strokeWidth="0.9" strokeLinejoin="round" opacity="0.9" />
      </g>
    );
  }
  // town / default
  return <circle cx={x} cy={y} r="3" fill="#fff" stroke={stroke} strokeWidth="1.2" />;
}

// ─────────────────────────────────────────────────────────────
// Annotation (handwritten label + arrow to anchor)
// ─────────────────────────────────────────────────────────────
function Annotation({ a }) {
  const { x, y, anchor, text, color, rot = 0, id } = a;
  // Build an arrow path from label to anchor (slightly curved)
  const midX = (x + anchor.x) / 2;
  const midY = (y + anchor.y) / 2 - 18;
  const arrowD = `M ${x} ${y} Q ${midX} ${midY} ${anchor.x} ${anchor.y}`;

  // Highlighter underline width
  const lines = text.split('\n');

  return (
    <g data-annot data-id={id} style={{ pointerEvents: 'none' }}>
      {/* Arrow stroke */}
      <path d={arrowD} fill="none" stroke={color} strokeWidth="1.6" strokeLinecap="round" opacity="0.85" strokeDasharray="0" />
      {/* Arrow head */}
      <ArrowHead x={anchor.x} y={anchor.y} fromX={x} fromY={y} color={color} />
      {/* Label (rotated, handwritten) */}
      <g transform={`translate(${x} ${y}) rotate(${rot})`}>
        {/* highlighter swatches behind each line */}
        {lines.map((l, i) => (
          <rect
            key={'hl'+i}
            x={-4}
            y={i * 18 - 12}
            width={Math.max(40, l.length * 9)}
            height={16}
            fill={color}
            opacity="0.18"
            rx="2"
          />
        ))}
        {lines.map((l, i) => (
          <text
            key={'tx'+i}
            x={0}
            y={i * 18}
            className="hand"
            fontSize="18"
            fontWeight="600"
            fill={color}
            opacity="0.92">
            {l}
          </text>
        ))}
      </g>
    </g>
  );
}

function ArrowHead({ x, y, fromX, fromY, color }) {
  const dx = x - fromX, dy = y - fromY;
  const len = Math.hypot(dx, dy) || 1;
  const ux = dx / len, uy = dy / len;
  // perpendicular
  const px = -uy, py = ux;
  const tip = { x, y };
  const a = { x: x - ux * 8 + px * 4, y: y - uy * 8 + py * 4 };
  const b = { x: x - ux * 8 - px * 4, y: y - uy * 8 - py * 4 };
  return (
    <path d={`M ${tip.x} ${tip.y} L ${a.x} ${a.y} L ${b.x} ${b.y} Z`}
          fill={color} opacity="0.85" />
  );
}

Object.assign(window, { ExpeditionMap, POIS, MAP_THEMES, DEFAULT_ANNOTATIONS });

// ─────────────────────────────────────────────────────────────
// WaypointMarker — renders a numbered route stop in one of four styles.
//
// Counter-scaling: the surrounding map content is rendered inside a
// `transform: scale(zoom)` wrapper, so anything drawn at native size grows
// with the map. Waypoints are UI markers, not cartographic features — they
// need to stay readable at every zoom level. We wrap the icon in a
// `translate(x y) scale(1/zoom)` so the icon's screen size is constant
// across the [0.7, 2.4] zoom range.
//
// Label positioning lives inside the counter-scaled group too, so the text
// offset is in *screen* px rather than scaled map units.
// ─────────────────────────────────────────────────────────────
function WaypointMarker({ poi, number, color, style, zoom, T, selected, onTap }) {
  const inv = 1 / Math.max(0.0001, zoom);
  return (
    <g
      data-poi
      transform={`translate(${poi.x} ${poi.y}) scale(${inv})`}
      style={{ cursor: 'pointer' }}
      onClick={(e) => { e.stopPropagation(); onTap && onTap(); }}>
      {/* Hit area sized to whichever style is selected */}
      <circle cx="0" cy={style === 'pin' ? -12 : 0} r="18" fill="transparent" />

      {style === 'pin'   && <PinWaypoint number={number} color={color} />}
      {style === 'stamp' && <StampWaypoint number={number} color={color} />}
      {style === 'dot'   && <DotWaypoint number={number} color={color} />}
      {style === 'tag'   && <TagWaypoint number={number} color={color} poi={poi} T={T} />}

      {/* Waypoint label — always shown (these are explicit trip stops). */}
      <text
        x={waypointLabelOffset(style).x}
        y={waypointLabelOffset(style).y}
        fontFamily='"Source Serif 4", Georgia, serif'
        fontSize="12.5"
        fontWeight="600"
        fill={T.labelMajor}
        paintOrder="stroke"
        stroke={T.land}
        strokeWidth="3.2"
        strokeLinejoin="round">
        {poi.name}
      </text>

      {/* Selection pulse — counter-scaled too, so it pulses at fixed screen px */}
      {selected && (
        <g>
          <circle cx="0" cy={style === 'pin' ? -12 : 0} r="14"
                  fill="none" stroke={color} strokeWidth="2" opacity="0.85">
            <animate attributeName="r" from="14" to="22" dur="1.4s" repeatCount="indefinite" />
            <animate attributeName="opacity" from="0.85" to="0" dur="1.4s" repeatCount="indefinite" />
          </circle>
        </g>
      )}
    </g>
  );
}

function waypointLabelOffset(style) {
  if (style === 'pin')   return { x: 16, y: -8 };
  if (style === 'tag')   return { x: 22, y: 4 };
  return { x: 16, y: 4 }; // stamp, dot
}

// ─────────────────────────────────────────────────────────────
// Waypoint icon variants
// All variants center their visual at the origin (0, 0) — except `pin`,
// which positions its anchor point at the origin and grows upward.
// ─────────────────────────────────────────────────────────────

// 1. Pin — teardrop map pin. Head ~22px diameter, point lands on the map coord.
//    Best when the user wants their stops to read like classic map pins.
function PinWaypoint({ number, color }) {
  return (
    <g>
      {/* Cast shadow on ground */}
      <ellipse cx="0" cy="0" rx="5" ry="1.6" fill="rgba(0,0,0,0.28)" />
      {/* Teardrop: round head + tapered tail to the anchor point */}
      <path d="M 0 -1 L -8.5 -16 A 11 11 0 1 1 8.5 -16 Z"
            fill={color} stroke="#fff" strokeWidth="1.6" strokeLinejoin="round" />
      {/* Inner highlight to give the pin a hint of dimension */}
      <path d="M 0 -1 L -8.5 -16 A 11 11 0 1 1 8.5 -16 Z"
            fill="none" stroke="rgba(255,255,255,0.25)" strokeWidth="0.6"
            transform="scale(0.86) translate(0 -2.5)" />
      {/* Number */}
      <text x="0" y="-21" textAnchor="middle"
            fontFamily="-apple-system, system-ui"
            fontSize="13" fontWeight="700"
            fill="#fff" dominantBaseline="middle"
            style={{ fontVariantNumeric: 'tabular-nums' }}>{number}</text>
    </g>
  );
}

// 2. Stamp — hexagonal field-tool stamp. Color border, white fill, color number.
//    Reads as a passport stamp / topo waymark. Good with the paper theme.
function StampWaypoint({ number, color }) {
  const R = 13;
  // Pointy-top hexagon
  const pts = Array.from({ length: 6 }).map((_, i) => {
    const a = (i * Math.PI) / 3 - Math.PI / 2;
    return `${(Math.cos(a) * R).toFixed(2)},${(Math.sin(a) * R).toFixed(2)}`;
  }).join(' ');
  return (
    <g>
      <ellipse cx="0" cy="12" rx="6" ry="1.8" fill="rgba(0,0,0,0.18)" />
      <polygon points={pts} fill="#fff" stroke={color} strokeWidth="2.2" />
      {/* Inner hairline for a stamped, etched feel */}
      <polygon points={pts} fill="none" stroke={color} strokeWidth="0.6"
               opacity="0.45" transform="scale(0.72)" />
      <text x="0" y="0.5" textAnchor="middle"
            fontFamily="-apple-system, system-ui"
            fontSize="13" fontWeight="700"
            fill={color} dominantBaseline="middle"
            style={{ fontVariantNumeric: 'tabular-nums' }}>{number}</text>
    </g>
  );
}

// 3. Dot — minimal solid color circle, white number. Densest, cleanest variant.
//    Recommended when the route is long and many waypoints would otherwise
//    clutter the map.
function DotWaypoint({ number, color }) {
  return (
    <g>
      <ellipse cx="0" cy="11" rx="5" ry="1.5" fill="rgba(0,0,0,0.18)" />
      <circle cx="0" cy="0" r="11" fill={color}
              stroke="#fff" strokeWidth="2" />
      {/* Subtle inner ring */}
      <circle cx="0" cy="0" r="9.2" fill="none"
              stroke="rgba(255,255,255,0.22)" strokeWidth="0.7" />
      <text x="0" y="0.5" textAnchor="middle"
            fontFamily="-apple-system, system-ui"
            fontSize="12" fontWeight="700"
            fill="#fff" dominantBaseline="middle"
            style={{ fontVariantNumeric: 'tabular-nums' }}>{number}</text>
    </g>
  );
}

// 4. Tag — the existing POI kind glyph (fuel pump, tent, pass, etc) plus a
//    small numbered chip floating top-right. Preserves category context AND
//    sequence — best when the user cares which kind of stop each one is.
function TagWaypoint({ number, color, poi, T }) {
  return (
    <g>
      {/* Underlying kind glyph at 1.3× to read clearly against the map */}
      <g transform="scale(1.35)">
        <PoiGlyph poi={{ x: 0, y: 0, kind: poi.kind }} T={T} />
      </g>
      {/* Numbered chip */}
      <g transform="translate(10 -10)">
        {/* Soft shadow */}
        <rect x="-10" y="-8.5" width="20" height="16" rx="8"
              fill="rgba(0,0,0,0.18)" transform="translate(0 0.6)" />
        <rect x="-10" y="-8.5" width="20" height="16" rx="8"
              fill={color} stroke="#fff" strokeWidth="1.6" />
        <text x="0" y="0.4" textAnchor="middle"
              fontFamily="-apple-system, system-ui"
              fontSize="11" fontWeight="700"
              fill="#fff" dominantBaseline="middle"
              style={{ fontVariantNumeric: 'tabular-nums' }}>{number}</text>
      </g>
    </g>
  );
}

Object.assign(window, { WaypointMarker });
