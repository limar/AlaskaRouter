// app.jsx — Alaska Router: expedition planner

const TWEAK_DEFAULTS = /*EDITMODE-BEGIN*/{
  "variant": "paper",
  "accent": ["#ea580c", "#9a3412"],
  "labelDensity": "normal",
  "showAnnotations": true,
  "searchShape": "rounded",
  "waypointStyle": "pin"
}/*EDITMODE-END*/;

// Visual presets for the two main variants (paper / field)
const VARIANT_PRESETS = {
  paper:  { sheetBg: 'rgba(252,250,244,0.86)', sheetTint: '#f6efde', searchTint: 'rgba(255,253,247,0.78)' },
  field:  { sheetBg: 'rgba(247,249,243,0.88)', sheetTint: '#eef2e8', searchTint: 'rgba(250,251,247,0.82)' },
};

const TRIP_NAME = 'Dalton Highway — North';

// Route is a flat list. `blockBreak: true` on a stop means a new block starts AT
// that stop — the first stop is implicitly the start of block 1. Blocks are
// referenced positionally (block N = the Nth group), with custom names/colors
// stored in BLOCKS keyed by ordinal index.
const INITIAL_ROUTE = [
  { id: 'fairbanks' },
  { id: 'yukon' },
  { id: 'coldfoot',  blockBreak: true },
  { id: 'atigun',    blockBreak: true },
  { id: 'galbraith' },
  { id: 'deadhorse', blockBreak: true },
];

// Distinct block colors that read well against the paper-topo map and don't
// clash with each other. Block N takes BLOCK_COLORS[N % len] by default; users
// override individual block names via the inline editor.
const BLOCK_COLORS = ['#0369a1', '#ea580c', '#7c3aed', '#15803d', '#b91c1c', '#a16207'];

const INITIAL_BLOCKS = [
  { name: '', color: BLOCK_COLORS[0] },
  { name: '', color: BLOCK_COLORS[1] },
  { name: '', color: BLOCK_COLORS[2] },
  { name: '', color: BLOCK_COLORS[3] },
];

// Map starts roughly centered on Coldfoot / Atigun in the iPhone viewport.
// Phone inner content area ≈ 402 × 874. Map SVG is 900 × 1700.
const PHONE_W = 402;
const PHONE_H = 874;
const INITIAL_PAN = { x: -110, y: -640 };

function App() {
  const [t, setTweak] = useTweaks(TWEAK_DEFAULTS);
  const accentColor = t.accent[0];
  const preset = VARIANT_PRESETS[t.variant] || VARIANT_PRESETS.paper;

  // Map pan + zoom
  const [pan, setPan] = React.useState(INITIAL_PAN);
  const [zoom, setZoom] = React.useState(1);
  const [hasPanned, setHasPanned] = React.useState(false);

  // Bottom sheet
  const [snap, setSnap] = React.useState(0); // 0=collapsed, 1=half, 2=expanded
  const [route, setRoute] = React.useState(INITIAL_ROUTE);
  const [blocks, setBlocks] = React.useState(INITIAL_BLOCKS);

  // Selected POI
  const [selectedPoi, setSelectedPoi] = React.useState(null);

  // Annotation creation
  const [addingAnnot, setAddingAnnot] = React.useState(false);
  const [draftAnnot, setDraftAnnot] = React.useState(null); // {x, y}
  const [annotations, setAnnotations] = React.useState(DEFAULT_ANNOTATIONS);

  // Search focus
  const [searchFocused, setSearchFocused] = React.useState(false);

  // Search is compact whenever user has panned/zoomed away from initial,
  // or sheet is past half. Expanded only when at idle + collapsed sheet + not focused.
  const isIdle = !hasPanned && snap === 0 && !searchFocused;
  const searchExpanded = isIdle;

  const handlePan = (x, y) => {
    setPan({ x, y });
    if (!hasPanned) setHasPanned(true);
  };

  // Zoom buttons — keep viewport center pinned on the same map coordinate so
  // the user doesn't lose their place. Find what map coord is under (W/2,H/2)
  // at the old zoom, then solve for the pan that keeps it there at the new zoom.
  const ZOOM_MIN = 0.7, ZOOM_MAX = 2.4;
  const handleZoom = (mult) => {
    setZoom((prev) => {
      const next = Math.max(ZOOM_MIN, Math.min(ZOOM_MAX, prev * mult));
      if (next === prev) return prev;
      const W = PHONE_W, H = PHONE_H;
      const mx = (W / 2 - pan.x) / prev;
      const my = (H / 2 - pan.y) / prev;
      setPan({ x: W / 2 - mx * next, y: H / 2 - my * next });
      return next;
    });
    if (!hasPanned) setHasPanned(true);
  };

  const handlePoiTap = (id) => {
    setSelectedPoi(id);
    if (snap === 2) setSnap(1);
  };

  const handleAddToTrip = () => {
    if (!selectedPoi) return;
    if (!route.find(r => r.id === selectedPoi)) {
      // Insert in geographic order along the highway (south → north = larger y → smaller y).
      // Preserve every existing stop's blockBreak flag; the new stop adopts no flag
      // so it joins the block of whatever sits before it.
      const all = [...route, { id: selectedPoi }];
      all.sort((a, b) => {
        const pa = POIS.find(p => p.id === a.id);
        const pb = POIS.find(p => p.id === b.id);
        return pb.y - pa.y;
      });
      // First stop must never carry blockBreak (it's always implicit block 1).
      if (all[0]) delete all[0].blockBreak;
      setRoute(all);
    }
    setSelectedPoi(null);
  };

  const handleRouteRemove = (id) => {
    const idx = route.findIndex(r => r.id === id);
    if (idx < 0) return;
    const next = route.filter(r => r.id !== id);
    // If we removed a block-starting stop, push the break onto the next stop
    // so we don't collapse two blocks into one accidentally.
    if (route[idx].blockBreak && idx < route.length - 1 && next[idx]) {
      next[idx] = { ...next[idx], blockBreak: true };
    }
    // First stop can't carry a blockBreak flag.
    if (next[0]) next[0] = { ...next[0], blockBreak: false };
    setRoute(next);
  };

  // Block name edit
  const handleBlockEdit = (blockIdx, patch) => {
    setBlocks((bs) => {
      const next = [...bs];
      while (next.length <= blockIdx) next.push({ name: '', color: BLOCK_COLORS[next.length % BLOCK_COLORS.length] });
      next[blockIdx] = { ...next[blockIdx], ...patch };
      return next;
    });
  };

  // Toggle a blockBreak on/off at a stop. Used to merge a block back into the
  // previous one (off) or to split a block at a particular stop (on).
  const handleBlockToggleBreak = (stopId, shouldBreak) => {
    setRoute(route.map((r, i) => {
      if (r.id !== stopId) return r;
      if (i === 0) return r; // first stop never carries the flag
      return { ...r, blockBreak: !!shouldBreak };
    }));
  };

  const handleMapTap = (pt) => {
    if (!addingAnnot) return;
    setDraftAnnot({ x: pt.x - 100, y: pt.y - 30, anchor: { x: pt.x, y: pt.y } });
  };

  const handleSaveAnnot = (text, color) => {
    if (!draftAnnot) return;
    setAnnotations([...annotations, {
      id: 'a' + Date.now(),
      text, color,
      x: draftAnnot.x, y: draftAnnot.y,
      anchor: draftAnnot.anchor,
      rot: (Math.random() * 6) - 3,
    }]);
    setDraftAnnot(null);
    setAddingAnnot(false);
  };

  const handleCancelAnnot = () => {
    setDraftAnnot(null);
    setAddingAnnot(false);
  };

  const recenter = () => {
    setPan(INITIAL_PAN);
    setZoom(1);
    setHasPanned(false);
    setSelectedPoi(null);
  };

  // Selected POI details
  const selPoi = selectedPoi ? POIS.find(p => p.id === selectedPoi) : null;

  // Derive (a) per-stop block index and (b) map route segments per block.
  // Walking once: blockIdx increments on the first stop and on every blockBreak.
  // For each adjacent pair, the segment color = destination's block color (so the
  // road "enters" the new block on the leg that arrives at its first stop).
  const routeWithBlock = React.useMemo(() => {
    let bi = -1;
    return route.map((r, i) => {
      if (i === 0 || r.blockBreak) bi += 1;
      return { ...r, blockIdx: bi };
    });
  }, [route]);

  const ensuredBlocks = React.useMemo(() => {
    const maxIdx = routeWithBlock.reduce((m, r) => Math.max(m, r.blockIdx), 0);
    const out = [...blocks];
    while (out.length <= maxIdx) {
      out.push({ name: '', color: BLOCK_COLORS[out.length % BLOCK_COLORS.length] });
    }
    return out;
  }, [blocks, routeWithBlock]);

  const routeSegments = React.useMemo(() => {
    const segs = [];
    for (let i = 0; i < routeWithBlock.length - 1; i++) {
      const a = routeWithBlock[i];
      const b = routeWithBlock[i + 1];
      const color = (ensuredBlocks[b.blockIdx] || ensuredBlocks[a.blockIdx] || {}).color || '#7a6a4a';
      segs.push({ fromId: a.id, toId: b.id, color });
    }
    return segs;
  }, [routeWithBlock, ensuredBlocks]);

  // Per-stop number + block color for waypoint icons on the map.
  const routeStops = React.useMemo(() => {
    const out = {};
    routeWithBlock.forEach((r, i) => {
      const color = (ensuredBlocks[r.blockIdx] || {}).color || '#7a6a4a';
      out[r.id] = { number: i + 1, color };
    });
    return out;
  }, [routeWithBlock, ensuredBlocks]);

  return (
    <>
      <IOSDevice width={PHONE_W} height={PHONE_H} dark={false}>
        <div style={{
          position: 'absolute', inset: 0,
          overflow: 'hidden',
        }}>
          {/* MAP */}
          <ExpeditionMap
            theme={t.variant}
            panX={pan.x}
            panY={pan.y}
            zoom={zoom}
            routeSegments={routeSegments}
            routeStops={routeStops}
            waypointStyle={t.waypointStyle}
            onPan={handlePan}
            onPoiTap={handlePoiTap}
            selectedPoi={selectedPoi}
            showAnnotations={t.showAnnotations}
            annotations={annotations}
            labelDensity={t.labelDensity}
            addingAnnotation={addingAnnot}
            onMapTap={handleMapTap}
          />

          {/* TOP — Search bar */}
          <SearchBar
            expanded={searchExpanded}
            tripName={TRIP_NAME}
            shape={t.searchShape}
            preset={preset}
            focused={searchFocused}
            onFocus={() => setSearchFocused(true)}
            onBlur={() => setSearchFocused(false)}
          />

          {/* RIGHT — Floating controls */}
          {!addingAnnot && !draftAnnot && (
            <FloatingControls
              onRecenter={recenter}
              onAddAnnotation={() => { setAddingAnnot(true); setSelectedPoi(null); setSnap(0); }}
              onZoomIn={() => handleZoom(1.4)}
              onZoomOut={() => handleZoom(1 / 1.4)}
              zoomInDisabled={zoom >= ZOOM_MAX - 0.001}
              zoomOutDisabled={zoom <= ZOOM_MIN + 0.001}
            />
          )}

          {/* ANNOTATION instruction toast */}
          {addingAnnot && !draftAnnot && (
            <AnnotInstruction onCancel={handleCancelAnnot} />
          )}

          {/* ANNOTATION draft editor */}
          {draftAnnot && (
            <AnnotEditor
              draft={draftAnnot}
              onSave={handleSaveAnnot}
              onCancel={handleCancelAnnot}
              accent={accentColor}
            />
          )}

          {/* POI CARD */}
          {selPoi && !addingAnnot && (
            <PoiCard
              poi={selPoi}
              inRoute={!!route.find(r => r.id === selPoi.id)}
              onAdd={handleAddToTrip}
              onClose={() => setSelectedPoi(null)}
              accent={accentColor}
            />
          )}

          {/* BOTTOM SHEET (hides when POI card or annot open) */}
          {!selPoi && !addingAnnot && !draftAnnot && (
            <BottomSheet
              snapPoints={[120, 380, 640]}
              snapIndex={snap}
              onSnapChange={setSnap}
              containerHeight={PHONE_H}
              route={route}
              blocks={ensuredBlocks}
              onRouteReorder={setRoute}
              onRouteRemove={handleRouteRemove}
              onPoiSelect={(id) => { setSelectedPoi(id); setSnap(0); }}
              onBlockEdit={handleBlockEdit}
              onBlockToggleBreak={handleBlockToggleBreak}
              tripName={TRIP_NAME}
            />
          )}
        </div>
      </IOSDevice>

      <TweaksPanel title="Tweaks">
        <TweakSection label="Visual variant">
          <TweakRadio label="Style"
            value={t.variant}
            options={[{ value: 'paper', label: 'Paper' }, { value: 'field', label: 'Field' }]}
            onChange={(v) => setTweak('variant', v)} />
        </TweakSection>

        <TweakSection label="Route color">
          <TweakColor label="Accent"
            value={t.accent}
            options={[
              ['#ea580c', '#9a3412'],     // burnt orange
              ['#1d4ed8', '#1e3a8a'],     // ink blue
              ['#15803d', '#14532d'],     // forest
              ['#b91c1c', '#7f1d1d'],     // red
              ['#7c3aed', '#5b21b6'],     // violet
            ]}
            onChange={(v) => setTweak('accent', v)} />
        </TweakSection>

        <TweakSection label="Waypoint icons">
          <TweakSelect label="Style"
            value={t.waypointStyle}
            options={[
              { value: 'pin',   label: 'Pin — classic map pin' },
              { value: 'stamp', label: 'Stamp — hexagonal' },
              { value: 'dot',   label: 'Dot — minimal numbered' },
              { value: 'tag',   label: 'Tag — kind glyph + chip' },
            ]}
            onChange={(v) => setTweak('waypointStyle', v)} />
        </TweakSection>

        <TweakSection label="Map">
          <TweakRadio label="Label density"
            value={t.labelDensity}
            options={[
              { value: 'low', label: 'Low' },
              { value: 'normal', label: 'Med' },
              { value: 'high', label: 'High' },
            ]}
            onChange={(v) => setTweak('labelDensity', v)} />
          <TweakToggle label="Annotations"
            value={t.showAnnotations}
            onChange={(v) => setTweak('showAnnotations', v)} />
        </TweakSection>

        <TweakSection label="Search bar">
          <TweakRadio label="Shape"
            value={t.searchShape}
            options={[
              { value: 'rounded', label: 'Rounded' },
              { value: 'pill', label: 'Pill' },
            ]}
            onChange={(v) => setTweak('searchShape', v)} />
        </TweakSection>
      </TweaksPanel>
    </>
  );
}

// ─────────────────────────────────────────────────────────────
// Search Bar — expanded ↔ compact
// ─────────────────────────────────────────────────────────────
// The expanded → compact transition morphs a single rounded rect's geometry
// (left / top / width / height / border-radius) over ~440ms with an iOS-style
// curve, while children cross-fade. The compact target is a 40×40 puck
// centered just below the Dynamic Island, so the user can watch the bar shrink
// up into it. Trip name reappears as a small chip hanging below the puck.
function SearchBar({ expanded, tripName, shape, preset, onFocus, onBlur }) {
  const radius = shape === 'pill' ? 999 : 16;
  // Phone width is fixed at 402 inside the iOS frame, so pixel values are stable.
  const COMPACT = { left: 181, top: 56, width: 40, height: 40, radius: 999 };
  const EXPANDED = { left: 14, top: 58, width: 374, height: 48, radius };
  const G = expanded ? EXPANDED : COMPACT;
  const ease = 'cubic-bezier(.62,.04,.32,1)';
  const transition =
    `top 440ms ${ease}, left 440ms ${ease}, width 440ms ${ease}, ` +
    `height 440ms ${ease}, border-radius 440ms ${ease}, ` +
    `padding 440ms ${ease}, gap 440ms ${ease}, box-shadow 320ms ease`;

  return (
    <>
      <div
        onClick={onFocus}
        style={{
          position: 'absolute', zIndex: 25,
          top: G.top, left: G.left, width: G.width, height: G.height,
          borderRadius: G.radius,
          padding: expanded ? '0 12px 0 14px' : 0,
          background: preset.searchTint,
          backdropFilter: 'blur(24px) saturate(180%)',
          WebkitBackdropFilter: 'blur(24px) saturate(180%)',
          border: '0.5px solid rgba(0,0,0,0.06)',
          boxShadow: expanded
            ? '0 1px 1px rgba(0,0,0,0.04), 0 8px 28px rgba(60,40,10,0.10)'
            : '0 4px 14px rgba(60,40,10,0.20), 0 1px 2px rgba(0,0,0,0.06)',
          display: 'flex', alignItems: 'center',
          gap: expanded ? 10 : 0,
          overflow: 'hidden',
          cursor: 'pointer',
          transition,
        }}>
        {/* Search icon — present in both states. Flex centers it when compact. */}
        <div style={{
          flex: expanded ? '0 0 auto' : 1,
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          height: '100%',
          transition: `flex 440ms ${ease}`,
        }}>
          <SearchIcon size={16} />
        </div>
        {/* Input — fades + collapses on the way to compact */}
        <input
          placeholder="Search Alaska, the Yukon…"
          onFocus={onFocus}
          onBlur={onBlur}
          onClick={(e) => e.stopPropagation()}
          style={{
            border: 0, background: 'transparent', outline: 'none',
            fontFamily: '-apple-system, system-ui',
            fontSize: 16, color: '#1a1a1a',
            minWidth: 0,
            flex: expanded ? 1 : 0,
            width: expanded ? 'auto' : 0,
            opacity: expanded ? 1 : 0,
            pointerEvents: expanded ? 'auto' : 'none',
            transition: `opacity 220ms ease, flex 380ms ${ease}`,
          }}
        />
        {/* Profile chip — fades out */}
        <div style={{
          opacity: expanded ? 1 : 0,
          pointerEvents: expanded ? 'auto' : 'none',
          width: expanded ? 'auto' : 0,
          transition: `opacity 220ms ease, width 380ms ${ease}`,
          overflow: 'hidden',
        }}>
          <ProfileChip />
        </div>
      </div>

      {/* Category chips below the bar — only in expanded mode.
         Fade + small upward translate so they feel like they tuck back in. */}
      <div style={{
        position: 'absolute',
        top: 114, left: 14, right: 14, zIndex: 24,
        display: 'flex', gap: 6, overflowX: 'auto',
        opacity: expanded ? 1 : 0,
        transform: expanded ? 'translateY(0)' : 'translateY(-10px)',
        pointerEvents: expanded ? 'auto' : 'none',
        transition: `opacity 260ms ease, transform 320ms ${ease}`,
      }}>
        {['Fuel', 'Camp', 'Visitor', 'Pass', 'Lodging', 'Water'].map((c) => (
          <button key={c} style={{
            border: '0.5px solid rgba(0,0,0,0.08)',
            background: 'rgba(255,255,255,0.7)',
            backdropFilter: 'blur(8px)',
            WebkitBackdropFilter: 'blur(8px)',
            borderRadius: 999,
            padding: '6px 13px',
            fontFamily: '-apple-system, system-ui',
            fontSize: 13, fontWeight: 500, color: '#2a2520',
            whiteSpace: 'nowrap',
            cursor: 'pointer',
            flexShrink: 0,
          }}>{c}</button>
        ))}
      </div>

      {/* Trip-name chip — hangs from the puck while compact so the user still
         sees the active trip context without giving up real estate. */}
      <div style={{
        position: 'absolute',
        top: 102, left: 50, right: 50, zIndex: 23,
        display: 'flex', justifyContent: 'center',
        opacity: expanded ? 0 : 1,
        transform: expanded ? 'translateY(-6px)' : 'translateY(0)',
        pointerEvents: 'none',
        transition: `opacity 240ms ease 80ms, transform 320ms ${ease} 80ms`,
      }}>
        <div style={{
          padding: '3px 10px',
          background: 'rgba(255,253,247,0.78)',
          backdropFilter: 'blur(14px) saturate(180%)',
          WebkitBackdropFilter: 'blur(14px) saturate(180%)',
          borderRadius: 999,
          border: '0.5px solid rgba(0,0,0,0.05)',
          fontFamily: '-apple-system, system-ui',
          fontSize: 11, fontWeight: 500,
          color: 'rgba(60,50,20,0.7)',
          whiteSpace: 'nowrap', maxWidth: '100%',
          overflow: 'hidden', textOverflow: 'ellipsis',
          boxShadow: '0 2px 6px rgba(60,40,10,0.08)',
        }}>{tripName}</div>
      </div>
    </>
  );
}

function SearchIcon({ size = 16, color = '#5a5446' }) {
  return (
    <svg width={size} height={size} viewBox="0 0 16 16" style={{ flexShrink: 0 }}>
      <circle cx="7" cy="7" r="5" fill="none" stroke={color} strokeWidth="1.5" />
      <line x1="10.8" y1="10.8" x2="14" y2="14" stroke={color} strokeWidth="1.5" strokeLinecap="round" />
    </svg>
  );
}

function ProfileChip() {
  return (
    <div style={{
      width: 28, height: 28, borderRadius: 14,
      background: 'linear-gradient(135deg, #c2a888, #8b6f4d)',
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      fontFamily: '"Source Serif 4", Georgia, serif',
      fontSize: 12, fontWeight: 700, color: '#fff',
      flexShrink: 0,
      boxShadow: 'inset 0 1px 0 rgba(255,255,255,0.3), 0 1px 2px rgba(0,0,0,0.1)',
    }}>K</div>
  );
}

// ─────────────────────────────────────────────────────────────
// Floating right-side controls — glove-friendly zoom pair + utility stack
// ─────────────────────────────────────────────────────────────
function FloatingControls({ onRecenter, onAddAnnotation, onZoomIn, onZoomOut, zoomInDisabled, zoomOutDisabled }) {
  return (
    <>
      {/* Zoom pair — Apple Maps-style stacked pill, oversized for gloved use.
         50px wide × 52px per button (104px tall total). Single rounded
         container with a hairline divider, so the pair reads as one object. */}
      <div style={{
        position: 'absolute',
        right: 12, top: 150,
        width: 50, borderRadius: 16,
        background: 'rgba(252,250,244,0.90)',
        backdropFilter: 'blur(20px) saturate(180%)',
        WebkitBackdropFilter: 'blur(20px) saturate(180%)',
        border: '0.5px solid rgba(0,0,0,0.07)',
        boxShadow: '0 6px 18px rgba(60,40,10,0.14), 0 1px 2px rgba(0,0,0,0.04)',
        overflow: 'hidden',
        zIndex: 22,
      }}>
        <ZoomBtn onClick={onZoomIn} disabled={zoomInDisabled} label="Zoom in">
          <svg width="22" height="22" viewBox="0 0 22 22" fill="none">
            <line x1="11" y1="4" x2="11" y2="18" stroke="#1a1a1a" strokeWidth="2" strokeLinecap="round" />
            <line x1="4" y1="11" x2="18" y2="11" stroke="#1a1a1a" strokeWidth="2" strokeLinecap="round" />
          </svg>
        </ZoomBtn>
        <div style={{ height: 0.5, background: 'rgba(0,0,0,0.10)', margin: '0 8px' }} />
        <ZoomBtn onClick={onZoomOut} disabled={zoomOutDisabled} label="Zoom out">
          <svg width="22" height="22" viewBox="0 0 22 22" fill="none">
            <line x1="4" y1="11" x2="18" y2="11" stroke="#1a1a1a" strokeWidth="2" strokeLinecap="round" />
          </svg>
        </ZoomBtn>
      </div>

      {/* Utility stack — below the zoom pair. */}
      <div style={{
        position: 'absolute',
        right: 12, top: 280,
        display: 'flex', flexDirection: 'column', gap: 8,
        zIndex: 22,
      }}>
        <CtlBtn title="Layers">
          <svg width="18" height="18" viewBox="0 0 18 18" fill="none">
            <path d="M9 2 L16 6 L9 10 L2 6 Z" stroke="#1a1a1a" strokeWidth="1.4" strokeLinejoin="round"/>
            <path d="M3.5 9 L9 12 L14.5 9" stroke="#1a1a1a" strokeWidth="1.4" strokeLinejoin="round" opacity="0.6"/>
            <path d="M3.5 12 L9 15 L14.5 12" stroke="#1a1a1a" strokeWidth="1.4" strokeLinejoin="round" opacity="0.4"/>
          </svg>
        </CtlBtn>
        <CtlBtn title="Recenter" onClick={onRecenter}>
          <svg width="18" height="18" viewBox="0 0 18 18" fill="none">
            <circle cx="9" cy="9" r="3.2" stroke="#1a1a1a" strokeWidth="1.4" />
            <line x1="9" y1="1" x2="9" y2="3.5" stroke="#1a1a1a" strokeWidth="1.4" strokeLinecap="round" />
            <line x1="9" y1="14.5" x2="9" y2="17" stroke="#1a1a1a" strokeWidth="1.4" strokeLinecap="round" />
            <line x1="1" y1="9" x2="3.5" y2="9" stroke="#1a1a1a" strokeWidth="1.4" strokeLinecap="round" />
            <line x1="14.5" y1="9" x2="17" y2="9" stroke="#1a1a1a" strokeWidth="1.4" strokeLinecap="round" />
          </svg>
        </CtlBtn>
        <CtlBtn title="Annotate" onClick={onAddAnnotation}>
          <svg width="18" height="18" viewBox="0 0 18 18" fill="none">
            <path d="M2.5 14 L4 12 L13 3 L15 5 L6 14 L4 15.5 Z" stroke="#1a1a1a" strokeWidth="1.4" strokeLinejoin="round" />
            <path d="M11 5 L13 7" stroke="#1a1a1a" strokeWidth="1.4" />
          </svg>
        </CtlBtn>
      </div>
    </>
  );
}

function ZoomBtn({ children, onClick, disabled, label }) {
  return (
    <button onClick={onClick} disabled={disabled} title={label} aria-label={label} style={{
      width: 50, height: 52, border: 0, background: 'transparent',
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      cursor: disabled ? 'default' : 'pointer',
      opacity: disabled ? 0.32 : 1,
      padding: 0,
      transition: 'background 120ms',
    }}
    onPointerDown={(e) => { if (!disabled) e.currentTarget.style.background = 'rgba(0,0,0,0.06)'; }}
    onPointerUp={(e) => { e.currentTarget.style.background = 'transparent'; }}
    onPointerLeave={(e) => { e.currentTarget.style.background = 'transparent'; }}
    >
      {children}
    </button>
  );
}

function CtlBtn({ children, onClick, title }) {
  return (
    <button onClick={onClick} title={title} style={{
      width: 44, height: 44, borderRadius: 14,
      border: '0.5px solid rgba(0,0,0,0.06)',
      background: 'rgba(252,250,244,0.86)',
      backdropFilter: 'blur(20px) saturate(180%)',
      WebkitBackdropFilter: 'blur(20px) saturate(180%)',
      boxShadow: '0 4px 14px rgba(60,40,10,0.10)',
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      cursor: 'pointer', padding: 0,
    }}>
      {children}
    </button>
  );
}

// ─────────────────────────────────────────────────────────────
// POI Card (contextual)
// ─────────────────────────────────────────────────────────────
function PoiCard({ poi, inRoute, onAdd, onClose, accent }) {
  return (
    <div style={{
      position: 'absolute',
      left: 12, right: 12, bottom: 18,
      background: 'rgba(252,250,244,0.92)',
      backdropFilter: 'blur(28px) saturate(170%)',
      WebkitBackdropFilter: 'blur(28px) saturate(170%)',
      border: '0.5px solid rgba(0,0,0,0.06)',
      borderRadius: 22,
      boxShadow: '0 -8px 30px rgba(60,40,10,0.10), 0 10px 40px rgba(60,40,10,0.14)',
      padding: '14px 16px 16px',
      zIndex: 35,
      animation: 'poi-slide-up 240ms cubic-bezier(.22,.9,.27,1)',
    }}>
      <style>{`@keyframes poi-slide-up { from { transform: translateY(20px); opacity: 0 } to { transform: none; opacity: 1 } }`}</style>

      {/* Header */}
      <div style={{ display: 'flex', alignItems: 'flex-start', gap: 12 }}>
        <div style={{
          width: 38, height: 38, borderRadius: 19,
          background: '#fff', border: '0.5px solid rgba(0,0,0,0.08)',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          flexShrink: 0,
        }}>
          <PoiKindIcon kind={poi.kind} />
        </div>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{
            fontFamily: '-apple-system, system-ui',
            fontSize: 11, letterSpacing: 1.2, textTransform: 'uppercase',
            color: 'rgba(60,50,20,0.55)', fontWeight: 600,
          }}>{kindLabel(poi.kind)}</div>
          <div style={{
            fontFamily: '"Source Serif 4", Georgia, serif',
            fontSize: 20, fontWeight: 600, color: '#1a1a1a', lineHeight: 1.15,
            marginTop: 1,
          }}>{poi.name}</div>
          {poi.sub && (
            <div style={{
              fontFamily: '-apple-system, system-ui',
              fontSize: 13, color: 'rgba(60,50,20,0.6)', marginTop: 3,
            }}>{poi.sub}</div>
          )}
        </div>
        <button onClick={onClose} style={{
          width: 28, height: 28, borderRadius: 14,
          border: 0, background: 'rgba(0,0,0,0.06)',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          cursor: 'pointer', flexShrink: 0,
        }}>
          <svg width="10" height="10" viewBox="0 0 10 10">
            <path d="M1 1l8 8M9 1L1 9" stroke="#3a3a3a" strokeWidth="1.6" strokeLinecap="round" />
          </svg>
        </button>
      </div>

      {/* Metadata strip */}
      <div style={{
        display: 'flex', gap: 0, marginTop: 12,
        padding: '10px 0', borderTop: '0.5px solid rgba(0,0,0,0.06)',
        borderBottom: '0.5px solid rgba(0,0,0,0.06)',
      }}>
        <MetaItem label="Coords" value={poiCoords(poi)} />
        <MetaItem label="Elevation" value={poiElev(poi)} />
        <MetaItem label="From last" value={poiFromLast(poi)} />
      </div>

      {/* Primary action */}
      <button onClick={onAdd} style={{
        marginTop: 12,
        width: '100%',
        height: 46, borderRadius: 13,
        border: 0,
        background: inRoute ? 'rgba(0,0,0,0.06)' : accent,
        color: inRoute ? '#3a3a3a' : '#fff',
        fontFamily: '-apple-system, system-ui',
        fontSize: 15, fontWeight: 600,
        display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8,
        cursor: 'pointer',
        boxShadow: inRoute ? 'none' : `0 6px 16px ${accent}40`,
      }}>
        {!inRoute && (
          <svg width="14" height="14" viewBox="0 0 14 14">
            <path d="M7 1v12M1 7h12" stroke="#fff" strokeWidth="1.8" strokeLinecap="round" />
          </svg>
        )}
        <span>{inRoute ? '✓  On this trip' : 'Add to trip'}</span>
      </button>

      {/* Secondary actions */}
      <div style={{ display: 'flex', gap: 8, marginTop: 8 }}>
        <SecondaryBtn icon={
          <svg width="14" height="14" viewBox="0 0 14 14"><path d="M3 2 L11 7 L3 12 Z" stroke="#1a1a1a" strokeWidth="1.4" strokeLinejoin="round" fill="none" /></svg>
        } label="Navigate" />
        <SecondaryBtn icon={
          <svg width="14" height="14" viewBox="0 0 14 14"><path d="M2 11 L4 9 L10 3 L11.5 4.5 L5.5 10.5 L4 12 Z" stroke="#1a1a1a" strokeWidth="1.4" strokeLinejoin="round" fill="none" /></svg>
        } label="Note" />
        <SecondaryBtn icon={
          <svg width="14" height="14" viewBox="0 0 14 14"><path d="M3 2 v10 l4-2 l4 2 V2 z" stroke="#1a1a1a" strokeWidth="1.4" strokeLinejoin="round" fill="none" /></svg>
        } label="Save" />
      </div>

      {/* Nav delegation hint */}
      <div style={{
        marginTop: 10, padding: '8px 10px',
        background: 'rgba(0,0,0,0.03)', borderRadius: 9,
        fontFamily: '-apple-system, system-ui',
        fontSize: 11.5, color: 'rgba(60,50,20,0.6)',
        display: 'flex', alignItems: 'center', gap: 6,
      }}>
        <svg width="11" height="11" viewBox="0 0 11 11" style={{ flexShrink: 0 }}><circle cx="5.5" cy="5.5" r="4.5" fill="none" stroke="#5a5446" strokeWidth="1"/><path d="M5.5 3v3l2 1.5" stroke="#5a5446" strokeWidth="1" strokeLinecap="round"/></svg>
        <span>Navigate opens in Apple Maps · Google Maps · Waze · Organic Maps</span>
      </div>
    </div>
  );
}

function MetaItem({ label, value }) {
  return (
    <div style={{ flex: 1, paddingLeft: 0 }}>
      <div style={{
        fontFamily: '-apple-system, system-ui',
        fontSize: 10, letterSpacing: 0.4, textTransform: 'uppercase',
        color: 'rgba(60,50,20,0.5)', fontWeight: 600,
      }}>{label}</div>
      <div style={{
        marginTop: 2,
        fontFamily: '"Source Serif 4", Georgia, serif',
        fontSize: 13, fontWeight: 500, color: '#1a1a1a',
        fontVariantNumeric: 'tabular-nums',
      }}>{value}</div>
    </div>
  );
}

function SecondaryBtn({ icon, label }) {
  return (
    <button style={{
      flex: 1, height: 38, borderRadius: 11,
      border: '0.5px solid rgba(0,0,0,0.08)',
      background: 'rgba(255,255,255,0.7)',
      display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 5,
      fontFamily: '-apple-system, system-ui',
      fontSize: 12.5, fontWeight: 500, color: '#1a1a1a',
      cursor: 'pointer',
    }}>
      {icon}<span>{label}</span>
    </button>
  );
}

function PoiKindIcon({ kind }) {
  if (kind === 'fuel') return (<svg width="18" height="18" viewBox="0 0 18 18"><rect x="4" y="3" width="7" height="11" rx="1.2" fill="none" stroke="#1a1a1a" strokeWidth="1.4" /><path d="M11 6 l2 1 v5 a1 1 0 001 1" fill="none" stroke="#1a1a1a" strokeWidth="1.4" /></svg>);
  if (kind === 'camp') return (<svg width="18" height="18" viewBox="0 0 18 18"><path d="M3 14 L9 4 L15 14 Z" fill="none" stroke="#1a1a1a" strokeWidth="1.4" strokeLinejoin="round" /></svg>);
  if (kind === 'pass') return (<svg width="18" height="18" viewBox="0 0 18 18"><path d="M2 14 L9 4 L16 14 Z" fill="none" stroke="#1a1a1a" strokeWidth="1.4" strokeLinejoin="round" /><line x1="6" y1="10.5" x2="12" y2="10.5" stroke="#1a1a1a" strokeWidth="1.2" /></svg>);
  if (kind === 'visitor') return (<svg width="18" height="18" viewBox="0 0 18 18"><circle cx="9" cy="9" r="6.5" fill="none" stroke="#1a1a1a" strokeWidth="1.4" /><text x="9" y="12.3" textAnchor="middle" fontFamily="Georgia, serif" fontStyle="italic" fontWeight="700" fontSize="9" fill="#1a1a1a">i</text></svg>);
  if (kind === 'view') return (<svg width="18" height="18" viewBox="0 0 18 18"><circle cx="9" cy="9" r="5" fill="none" stroke="#1a1a1a" strokeWidth="1.4" /><circle cx="9" cy="9" r="1.6" fill="#1a1a1a" /></svg>);
  if (kind === 'city') return (<svg width="18" height="18" viewBox="0 0 18 18"><circle cx="9" cy="9" r="3.4" fill="#1a1a1a" /></svg>);
  if (kind === 'park') return (<svg width="18" height="18" viewBox="0 0 18 18"><path d="M3 14 L6 8 L8 11 L10 6 L12 9 L15 14 Z" fill="#1a1a1a" /></svg>);
  return <svg width="18" height="18" viewBox="0 0 18 18"><circle cx="9" cy="9" r="3.4" fill="#1a1a1a" /></svg>;
}

function kindLabel(k) {
  return {
    fuel: 'Fuel · Provisions', camp: 'Campground', city: 'City',
    town: 'Settlement', pass: 'Mountain Pass', view: 'Viewpoint',
    landmark: 'Landmark', park: 'National Park', visitor: 'Visitor Center',
  }[k] || 'Point of Interest';
}

function poiCoords(p) {
  // Faked but deterministic from x/y
  const lat = 64.0 + (1700 - p.y) / 1700 * 6.5;
  const lon = -149.0 - (450 - p.x) / 900 * 4;
  return `${lat.toFixed(2)}°N  ${Math.abs(lon).toFixed(2)}°W`;
}

function poiElev(p) {
  if (p.id === 'deadhorse') return '40 ft';
  if (p.id === 'atigun') return '4,739 ft';
  if (p.id === 'coldfoot') return '1,030 ft';
  if (p.id === 'yukon') return '320 ft';
  if (p.id === 'fairbanks') return '440 ft';
  if (p.id === 'galbraith') return '2,665 ft';
  if (p.id === 'franklin') return '300 ft';
  return '—';
}

function poiFromLast(p) {
  return { fairbanks: '—', yukon: '136 mi', coldfoot: '119 mi', atigun: '60 mi',
           galbraith: '20 mi', deadhorse: '79 mi' }[p.id] || '—';
}

// ─────────────────────────────────────────────────────────────
// Annotation: instruction toast + editor
// ─────────────────────────────────────────────────────────────
function AnnotInstruction({ onCancel }) {
  return (
    <div style={{
      position: 'absolute', left: 14, right: 14, top: 110,
      background: 'rgba(252,250,244,0.92)',
      backdropFilter: 'blur(22px) saturate(170%)',
      WebkitBackdropFilter: 'blur(22px) saturate(170%)',
      border: '0.5px solid rgba(0,0,0,0.06)',
      borderRadius: 14,
      padding: '11px 13px',
      display: 'flex', alignItems: 'center', gap: 10,
      boxShadow: '0 8px 24px rgba(60,40,10,0.12)',
      zIndex: 26,
    }}>
      <div style={{
        width: 26, height: 26, borderRadius: 13,
        background: '#fef3c7',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        flexShrink: 0,
      }}>
        <svg width="13" height="13" viewBox="0 0 13 13">
          <path d="M2 11 L3 9 L9 3 L10.5 4.5 L4.5 10.5 L3 11.5 Z" stroke="#92400e" strokeWidth="1.3" strokeLinejoin="round" fill="none" />
        </svg>
      </div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{
          fontFamily: '-apple-system, system-ui',
          fontSize: 14, fontWeight: 600, color: '#1a1a1a',
        }}>Tap the map to drop a note</div>
        <div style={{
          fontFamily: '-apple-system, system-ui',
          fontSize: 12, color: 'rgba(60,50,20,0.6)', marginTop: 1,
        }}>The arrow will point from your note to that spot</div>
      </div>
      <button onClick={onCancel} style={{
        width: 28, height: 28, borderRadius: 14,
        border: 0, background: 'rgba(0,0,0,0.06)',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        cursor: 'pointer', flexShrink: 0,
      }}>
        <svg width="10" height="10" viewBox="0 0 10 10">
          <path d="M1 1l8 8M9 1L1 9" stroke="#3a3a3a" strokeWidth="1.6" strokeLinecap="round" />
        </svg>
      </button>
    </div>
  );
}

function AnnotEditor({ draft, onSave, onCancel, accent }) {
  const [text, setText] = React.useState('');
  const [color, setColor] = React.useState('#c2410c');
  const colors = [
    { c: '#c2410c', name: 'amber' },
    { c: '#1d4ed8', name: 'ink' },
    { c: '#15803d', name: 'pine' },
    { c: '#9333ea', name: 'plum' },
    { c: '#1a1a1a', name: 'graphite' },
  ];

  React.useEffect(() => {
    // autofocus
    const ta = document.getElementById('annot-ta');
    if (ta) ta.focus();
  }, []);

  return (
    <div style={{
      position: 'absolute',
      left: 12, right: 12, bottom: 18,
      background: 'rgba(252,250,244,0.94)',
      backdropFilter: 'blur(28px) saturate(170%)',
      WebkitBackdropFilter: 'blur(28px) saturate(170%)',
      border: '0.5px solid rgba(0,0,0,0.06)',
      borderRadius: 22,
      boxShadow: '0 -8px 30px rgba(60,40,10,0.10), 0 10px 40px rgba(60,40,10,0.14)',
      padding: '14px 16px 16px',
      zIndex: 35,
    }}>
      <div style={{
        display: 'flex', alignItems: 'baseline', justifyContent: 'space-between',
        marginBottom: 8,
      }}>
        <div>
          <div style={{
            fontFamily: '-apple-system, system-ui',
            fontSize: 11, letterSpacing: 1.2, textTransform: 'uppercase',
            color: 'rgba(60,50,20,0.55)', fontWeight: 600,
          }}>New annotation</div>
          <div style={{
            fontFamily: '"Source Serif 4", Georgia, serif',
            fontSize: 18, fontWeight: 600, color: '#1a1a1a', marginTop: 1,
          }}>Note for this spot</div>
        </div>
        <button onClick={onCancel} style={{
          width: 28, height: 28, borderRadius: 14,
          border: 0, background: 'rgba(0,0,0,0.06)',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          cursor: 'pointer',
        }}>
          <svg width="10" height="10" viewBox="0 0 10 10">
            <path d="M1 1l8 8M9 1L1 9" stroke="#3a3a3a" strokeWidth="1.6" strokeLinecap="round" />
          </svg>
        </button>
      </div>

      <textarea
        id="annot-ta"
        placeholder="e.g. 240 mi — no fuel until Coldfoot"
        value={text}
        onChange={(e) => setText(e.target.value)}
        rows="2"
        style={{
          width: '100%',
          padding: '10px 12px',
          border: '0.5px solid rgba(0,0,0,0.10)',
          background: 'rgba(255,255,255,0.6)',
          borderRadius: 12,
          fontFamily: '"Caveat", "Bradley Hand", cursive',
          fontSize: 22, lineHeight: 1.15,
          color: color, fontWeight: 600,
          outline: 'none',
          resize: 'none',
        }}
      />

      <div style={{ marginTop: 12, display: 'flex', alignItems: 'center', gap: 10 }}>
        <div style={{
          fontFamily: '-apple-system, system-ui',
          fontSize: 11, letterSpacing: 1, textTransform: 'uppercase',
          color: 'rgba(60,50,20,0.55)', fontWeight: 600,
        }}>Ink</div>
        <div style={{ display: 'flex', gap: 8 }}>
          {colors.map((co) => (
            <button key={co.c} onClick={() => setColor(co.c)} style={{
              width: 22, height: 22, borderRadius: 11,
              border: color === co.c ? `2px solid #1a1a1a` : '0.5px solid rgba(0,0,0,0.15)',
              padding: 0, cursor: 'pointer',
              background: co.c,
              boxShadow: color === co.c ? '0 0 0 2px #fff inset' : 'none',
            }} />
          ))}
        </div>
        <div style={{ flex: 1 }} />
        <button onClick={() => onSave(text || 'note', color)} disabled={!text.trim()} style={{
          height: 36, padding: '0 16px', borderRadius: 11,
          border: 0,
          background: text.trim() ? accent : 'rgba(0,0,0,0.08)',
          color: text.trim() ? '#fff' : 'rgba(0,0,0,0.4)',
          fontFamily: '-apple-system, system-ui',
          fontSize: 14, fontWeight: 600,
          cursor: text.trim() ? 'pointer' : 'default',
          boxShadow: text.trim() ? `0 4px 12px ${accent}40` : 'none',
        }}>Drop note</button>
      </div>
    </div>
  );
}

// Mount
ReactDOM.createRoot(document.getElementById('root')).render(<App />);
