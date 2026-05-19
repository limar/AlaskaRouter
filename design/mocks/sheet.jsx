// sheet.jsx — Bottom sheet with 3 snap points, drag-resize, and drag-reorder route points.

function BottomSheet({
  snapPoints = [120, 380, 640],    // collapsed / half / expanded (heights in px)
  snapIndex = 0,
  onSnapChange,
  containerHeight = 874,
  route = [],
  blocks = [],
  onRouteReorder,
  onRouteRemove,
  onPoiSelect,
  onBlockEdit,
  onBlockToggleBreak,
  tripName = 'Dalton Highway — North',
}) {
  const height = snapPoints[snapIndex];
  const [dragOffset, setDragOffset] = React.useState(0);
  const dragRef = React.useRef(null);
  const [reorderId, setReorderId] = React.useState(null);

  const onHandleDown = (e) => {
    dragRef.current = { startY: e.clientY, startH: height };
    e.currentTarget.setPointerCapture && e.currentTarget.setPointerCapture(e.pointerId);
  };
  const onHandleMove = (e) => {
    if (!dragRef.current) return;
    const dy = dragRef.current.startY - e.clientY;
    setDragOffset(dy);
  };
  const onHandleUp = () => {
    if (!dragRef.current) return;
    const target = dragRef.current.startH + dragOffset;
    let best = 0, bestD = Infinity;
    snapPoints.forEach((s, i) => {
      const d = Math.abs(s - target);
      if (d < bestD) { bestD = d; best = i; }
    });
    onSnapChange && onSnapChange(best);
    dragRef.current = null;
    setDragOffset(0);
  };

  const currentH = Math.max(80, Math.min(containerHeight - 60, height + dragOffset));

  // Drag-reorder — flag a row and let downstream handle reorder logic.
  const onRowDown = (id, e) => {
    e.preventDefault();
    e.stopPropagation();
    setReorderId(id);
    const ROW_H = 52;
    const startY = e.clientY;
    const initialIdx = route.findIndex(r => r.id === id);

    const onMove = (ev) => {
      const dy = ev.clientY - startY;
      const shift = Math.round(dy / ROW_H);
      const curIdx = route.findIndex(r => r.id === id);
      const newIdx = Math.max(0, Math.min(route.length - 1, initialIdx + shift));
      if (newIdx !== curIdx) {
        const next = route.filter(r => r.id !== id);
        // Preserve the moved stop's blockBreak flag but make sure block
        // structure stays sane — the receiving block adopts it.
        const moved = route.find(r => r.id === id);
        next.splice(newIdx, 0, moved);
        onRouteReorder && onRouteReorder(next);
      }
    };
    const onUp = () => {
      setReorderId(null);
      window.removeEventListener('pointermove', onMove);
      window.removeEventListener('pointerup', onUp);
    };
    window.addEventListener('pointermove', onMove);
    window.addEventListener('pointerup', onUp);
  };

  // Compute block grouping for display
  const groups = groupByBlock(route);
  // Derived trip stats
  const dist = 414;
  const fuelGap = 240;

  return (
    <div
      style={{
        position: 'absolute', left: 0, right: 0, bottom: 0,
        height: currentH,
        background: 'rgba(252,250,244,0.86)',
        backdropFilter: 'blur(28px) saturate(170%)',
        WebkitBackdropFilter: 'blur(28px) saturate(170%)',
        borderTopLeftRadius: 22, borderTopRightRadius: 22,
        boxShadow: '0 -8px 30px rgba(60,40,10,0.10), 0 -0.5px 0 rgba(0,0,0,0.07) inset',
        borderTop: '0.5px solid rgba(0,0,0,0.06)',
        display: 'flex', flexDirection: 'column',
        overflow: 'hidden',
        transition: dragRef.current ? 'none' : 'height 320ms cubic-bezier(.22,.9,.27,1)',
        zIndex: 30,
        touchAction: 'none',
      }}
    >
      {/* Drag handle */}
      <div
        onPointerDown={onHandleDown}
        onPointerMove={onHandleMove}
        onPointerUp={onHandleUp}
        onPointerCancel={onHandleUp}
        style={{
          padding: '8px 0 6px',
          display: 'flex', justifyContent: 'center',
          cursor: 'ns-resize', flexShrink: 0,
          touchAction: 'none',
        }}>
        <div style={{
          width: 38, height: 5, borderRadius: 3,
          background: 'rgba(60,50,20,0.22)',
        }} />
      </div>

      <div style={{
        flex: 1, overflowY: snapIndex === 2 ? 'auto' : 'hidden',
        overflowX: 'hidden',
        WebkitOverflowScrolling: 'touch',
      }}>
        {/* Trip header */}
        <div style={{
          padding: '4px 18px 12px',
          display: 'flex', alignItems: 'baseline', justifyContent: 'space-between',
          gap: 12,
        }}>
          <div style={{ minWidth: 0 }}>
            <div style={{
              fontFamily: '-apple-system, system-ui',
              fontSize: 11, letterSpacing: 1.2, textTransform: 'uppercase',
              color: 'rgba(60,50,20,0.55)', fontWeight: 600,
            }}>Active Trip · Aug 2026</div>
            <div style={{
              fontFamily: '"Source Serif 4", Georgia, serif',
              fontSize: 22, fontWeight: 600, color: '#1a1a1a',
              lineHeight: 1.15, marginTop: 3,
              whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
            }}>{tripName}</div>
          </div>
          <div style={{
            width: 32, height: 32, borderRadius: 16,
            background: 'rgba(0,0,0,0.05)',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            flexShrink: 0,
          }}>
            <svg width="14" height="14" viewBox="0 0 14 14">
              <circle cx="3" cy="7" r="1.4" fill="#3a3a3a" />
              <circle cx="7" cy="7" r="1.4" fill="#3a3a3a" />
              <circle cx="11" cy="7" r="1.4" fill="#3a3a3a" />
            </svg>
          </div>
        </div>

        {/* Stat strip */}
        <div style={{
          padding: '0 18px 14px', display: 'flex', gap: 0,
        }}>
          <Stat label="Distance" value={`${dist} mi`} />
          <Sep />
          <Stat label="Stops" value={`${route.length}`} />
          <Sep />
          <Stat label="Longest fuel gap" value={`${fuelGap} mi`} warn />
          <Sep />
          <Stat label="Offline" value="Ready" ok />
        </div>

        {/* Stops list with embedded block dividers (half + expanded). */}
        {snapIndex >= 1 && (
          <div style={{ padding: '0 14px 8px' }}>
            <SectionHeader label="Route" trailing={
              <button style={chipBtnStyle}>
                <svg width="11" height="11" viewBox="0 0 11 11"><path d="M5.5 1v9M1 5.5h9" stroke="#3a3a3a" strokeWidth="1.6" strokeLinecap="round"/></svg>
                <span>Add stop</span>
              </button>
            } />

            <div style={{
              background: 'rgba(255,255,255,0.55)',
              borderRadius: 16,
              border: '0.5px solid rgba(0,0,0,0.06)',
              overflow: 'hidden',
            }}>
              {groups.map((g, gi) => (
                <React.Fragment key={'b' + gi}>
                  <BlockHeader
                    blockNum={gi + 1}
                    block={blocks[g.blockIdx] || {}}
                    autoName={autoNameBlock(g)}
                    stopCount={g.stops.length}
                    isFirst={gi === 0}
                    canRemove={gi > 0}
                    onRemove={() => onBlockToggleBreak && onBlockToggleBreak(g.stops[0].id, false)}
                    onRename={(name) => onBlockEdit && onBlockEdit(g.blockIdx, { name })}
                  />
                  {g.stops.map((stop, si) => (
                    <StopRow
                      key={stop.id}
                      poi={POIS.find(p => p.id === stop.id)}
                      number={g.startIndex + si + 1}
                      isLastInBlock={si === g.stops.length - 1}
                      isLastOverall={gi === groups.length - 1 && si === g.stops.length - 1}
                      isFirstInBlock={si === 0}
                      blockColor={(blocks[g.blockIdx] || {}).color}
                      reordering={reorderId === stop.id}
                      // The first stop already sits under its block header —
                      // suppress its own "split here" action to avoid creating
                      // empty blocks.
                      canBreak={!(gi === 0 && si === 0) && !(si === 0)}
                      onDown={(e) => onRowDown(stop.id, e)}
                      onTap={() => onPoiSelect && onPoiSelect(stop.id)}
                      onRemove={() => onRouteRemove && onRouteRemove(stop.id)}
                      onSplit={() => onBlockToggleBreak && onBlockToggleBreak(stop.id, true)}
                    />
                  ))}
                </React.Fragment>
              ))}
            </div>

            <div style={{
              padding: '10px 4px 0',
              fontFamily: '-apple-system, system-ui',
              fontSize: 11, color: 'rgba(60,50,20,0.5)',
            }}>Drag <DotsSm /> to reorder. Tap <SplitSm /> next to a stop to start a new block there.</div>
          </div>
        )}
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// Stat / section helpers
// ─────────────────────────────────────────────────────────────
function Stat({ label, value, warn, ok }) {
  return (
    <div style={{ flex: 1, minWidth: 0 }}>
      <div style={{
        fontFamily: '-apple-system, system-ui',
        fontSize: 10, letterSpacing: 0.5, textTransform: 'uppercase',
        color: 'rgba(60,50,20,0.5)', fontWeight: 600,
      }}>{label}</div>
      <div style={{
        marginTop: 2,
        fontFamily: '"Source Serif 4", Georgia, serif',
        fontSize: 15, fontWeight: 600,
        color: warn ? '#9a3412' : ok ? '#166534' : '#1a1a1a',
        whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
      }}>{value}</div>
    </div>
  );
}

function Sep() {
  return <div style={{ width: 1, background: 'rgba(0,0,0,0.07)', margin: '4px 10px' }} />;
}

function SectionHeader({ label, trailing }) {
  return (
    <div style={{
      display: 'flex', alignItems: 'center', justifyContent: 'space-between',
      padding: '6px 4px 8px',
    }}>
      <div style={{
        fontFamily: '-apple-system, system-ui',
        fontSize: 11, letterSpacing: 1.2, textTransform: 'uppercase',
        color: 'rgba(60,50,20,0.6)', fontWeight: 700,
      }}>{label}</div>
      {trailing}
    </div>
  );
}

const chipBtnStyle = {
  border: '0.5px solid rgba(0,0,0,0.08)',
  background: 'rgba(255,255,255,0.7)',
  borderRadius: 999,
  padding: '4px 9px 4px 7px',
  display: 'inline-flex', alignItems: 'center', gap: 5,
  fontFamily: '-apple-system, system-ui',
  fontSize: 12, fontWeight: 500, color: '#3a3a3a',
  cursor: 'pointer',
};

// ─────────────────────────────────────────────────────────────
// Block grouping helpers
// ─────────────────────────────────────────────────────────────
function groupByBlock(route) {
  // Walk route, start a new group on first stop and on blockBreak=true.
  // blockIdx increments per group.
  const groups = [];
  let cur = null;
  let blockIdx = -1;
  route.forEach((stop, i) => {
    if (i === 0 || stop.blockBreak) {
      blockIdx += 1;
      cur = { blockIdx, startIndex: i, stops: [] };
      groups.push(cur);
    }
    cur.stops.push(stop);
  });
  return groups;
}

// "Yukon River Camp → Coldfoot" style fallback, falling back to "Block 2"
// when only one stop. The user can override by tapping the title.
function autoNameBlock(g) {
  const first = POIS.find(p => p.id === g.stops[0].id);
  const last = POIS.find(p => p.id === g.stops[g.stops.length - 1].id);
  if (!first) return '';
  if (!last || first.id === last.id) return shortName(first.name);
  return `${shortName(first.name)} → ${shortName(last.name)}`;
}

function shortName(name) {
  return name.replace(/ National Park.*/, '').replace(/ Camp.*$/, '');
}

// ─────────────────────────────────────────────────────────────
// Block header — inline row between stops, with editable name
// ─────────────────────────────────────────────────────────────
function BlockHeader({ blockNum, block, autoName, stopCount, isFirst, canRemove, onRemove, onRename }) {
  const [editing, setEditing] = React.useState(false);
  const [draft, setDraft] = React.useState(block.name || '');
  React.useEffect(() => { setDraft(block.name || ''); }, [block.name]);

  const inputRef = React.useRef(null);
  React.useEffect(() => { if (editing && inputRef.current) inputRef.current.focus(); }, [editing]);

  const color = block.color || '#7a6a4a';
  const labelStyle = {
    fontFamily: '"Source Serif 4", Georgia, serif',
    fontSize: 14, fontWeight: 600, color: '#1a1a1a',
    letterSpacing: -0.1,
  };

  return (
    <div style={{
      position: 'relative',
      display: 'flex', alignItems: 'center', gap: 10,
      padding: '12px 14px 8px',
      background: 'rgba(0,0,0,0.018)',
      borderTop: isFirst ? 0 : '0.5px solid rgba(0,0,0,0.07)',
    }}>
      {/* Color chip with number */}
      <div style={{
        width: 22, height: 22, borderRadius: 6,
        background: color,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        boxShadow: `0 0 0 0.5px ${color}55`,
        fontFamily: '-apple-system, system-ui',
        fontSize: 11, fontWeight: 700,
        color: '#fff', flexShrink: 0,
      }}>{blockNum}</div>

      {/* Name (editable) */}
      <div style={{ flex: 1, minWidth: 0 }}>
        {editing ? (
          <input
            ref={inputRef}
            value={draft}
            placeholder={autoName}
            onChange={(e) => setDraft(e.target.value)}
            onBlur={() => { onRename && onRename(draft); setEditing(false); }}
            onKeyDown={(e) => {
              if (e.key === 'Enter') { onRename && onRename(draft); setEditing(false); }
              if (e.key === 'Escape') { setDraft(block.name || ''); setEditing(false); }
            }}
            style={{
              width: '100%', border: 0, background: 'transparent', outline: 'none',
              padding: 0, ...labelStyle,
            }}
          />
        ) : (
          <div onClick={() => setEditing(true)}
               style={{
                 ...labelStyle,
                 cursor: 'text',
                 color: block.name ? '#1a1a1a' : 'rgba(60,50,20,0.55)',
                 fontStyle: block.name ? 'normal' : 'italic',
                 whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
               }}>
            {block.name || autoName}
          </div>
        )}
        <div style={{
          fontFamily: '-apple-system, system-ui',
          fontSize: 10.5, letterSpacing: 0.4, color: 'rgba(60,50,20,0.5)',
          marginTop: 1,
        }}>
          {stopCount} stop{stopCount === 1 ? '' : 's'}
        </div>
      </div>

      {/* Merge-into-previous (only on inner blocks) */}
      {canRemove && (
        <button onClick={onRemove} title="Merge with previous block" style={{
          width: 24, height: 24, borderRadius: 12,
          border: 0, background: 'transparent',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          cursor: 'pointer', color: 'rgba(60,50,20,0.55)',
        }}>
          <svg width="12" height="12" viewBox="0 0 12 12">
            <path d="M2 4h8M2 8h8" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round"/>
          </svg>
        </button>
      )}
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// Stop row — indented under its block
// ─────────────────────────────────────────────────────────────
function StopRow({
  poi, number, isLastInBlock, isLastOverall, isFirstInBlock,
  blockColor, reordering, canBreak,
  onDown, onTap, onRemove, onSplit,
}) {
  if (!poi) return null;
  return (
    <div data-row style={{
      display: 'flex', alignItems: 'center',
      padding: '0 12px 0 24px',     // <-- indent: block content nests one tab in
      minHeight: 52,
      position: 'relative',
      background: reordering ? 'rgba(234,88,12,0.06)' : 'transparent',
      zIndex: reordering ? 2 : 1,
      transition: reordering ? 'none' : 'background 120ms',
    }}>
      {/* Drag handle */}
      <div
        onPointerDown={onDown}
        style={{
          width: 22, marginLeft: -4,
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          cursor: 'grab', touchAction: 'none', alignSelf: 'stretch',
        }}>
        <svg width="12" height="14" viewBox="0 0 12 14">
          <circle cx="4" cy="3" r="1" fill="rgba(0,0,0,0.32)" />
          <circle cx="8" cy="3" r="1" fill="rgba(0,0,0,0.32)" />
          <circle cx="4" cy="7" r="1" fill="rgba(0,0,0,0.32)" />
          <circle cx="8" cy="7" r="1" fill="rgba(0,0,0,0.32)" />
          <circle cx="4" cy="11" r="1" fill="rgba(0,0,0,0.32)" />
          <circle cx="8" cy="11" r="1" fill="rgba(0,0,0,0.32)" />
        </svg>
      </div>

      {/* Block-colored connector + numbered pip */}
      <div style={{
        position: 'relative', width: 20, alignSelf: 'stretch',
        display: 'flex', flexDirection: 'column', alignItems: 'center',
      }}>
        {/* top half of connector — hide on first row of block (so it touches the header instead) */}
        {!isFirstInBlock && (
          <div style={{
            position: 'absolute', top: 0, height: 16, width: 1.5,
            background: `${blockColor || '#7a6a4a'}66`, borderRadius: 1,
          }} />
        )}
        {/* bottom half of connector */}
        {!isLastOverall && (
          <div style={{
            position: 'absolute', top: 30, bottom: 0, width: 1.5,
            background: `${blockColor || '#7a6a4a'}66`, borderRadius: 1,
          }} />
        )}
        <div style={{
          marginTop: 16,
          width: 16, height: 16, borderRadius: 8,
          background: '#fff',
          border: `1.6px solid ${blockColor || '#7a6a4a'}`,
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          fontFamily: '-apple-system, system-ui', fontSize: 9, fontWeight: 700,
          color: blockColor || '#3a3a3a', zIndex: 1,
          fontVariantNumeric: 'tabular-nums',
        }}>{number}</div>
      </div>

      {/* Name + hint */}
      <div onClick={onTap} style={{ flex: 1, padding: '10px 8px 10px 10px', cursor: 'pointer', minWidth: 0 }}>
        <div style={{
          fontFamily: '"Source Serif 4", Georgia, serif',
          fontSize: 15, fontWeight: 600, color: '#1a1a1a',
          whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
        }}>{poi.name}</div>
        <div style={{
          fontFamily: '-apple-system, system-ui',
          fontSize: 11.5, color: 'rgba(60,50,20,0.55)',
          marginTop: 1,
        }}>{kindToHint(poi)}</div>
      </div>

      {/* Inline actions: split here (start new block above this stop) + remove */}
      {canBreak && (
        <button onClick={onSplit} title="Start a new block here" style={{
          width: 26, height: 26, borderRadius: 13, marginRight: 4,
          border: 0, background: 'rgba(0,0,0,0.04)',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          cursor: 'pointer',
        }}>
          <SplitSm />
        </button>
      )}
      <button onClick={onRemove} style={{
        width: 26, height: 26, borderRadius: 13,
        border: 0, background: 'rgba(0,0,0,0.05)',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        cursor: 'pointer',
      }}>
        <svg width="9" height="2" viewBox="0 0 9 2">
          <rect width="9" height="2" rx="1" fill="rgba(0,0,0,0.45)" />
        </svg>
      </button>

      {!isLastInBlock && (
        <div style={{
          position: 'absolute', bottom: 0, right: 12, left: 70,
          height: 0.5, background: 'rgba(0,0,0,0.06)',
        }} />
      )}
    </div>
  );
}

function SplitSm() {
  return (
    <svg width="12" height="12" viewBox="0 0 12 12" style={{ verticalAlign: 'middle' }}>
      <path d="M1 6h3M8 6h3M6 1v3M6 8v3" stroke="rgba(60,50,20,0.6)" strokeWidth="1.4" strokeLinecap="round"/>
    </svg>
  );
}

function DotsSm() {
  return (
    <svg width="10" height="12" viewBox="0 0 10 12" style={{ verticalAlign: 'middle' }}>
      <circle cx="3" cy="3" r="1" fill="rgba(60,50,20,0.55)" />
      <circle cx="7" cy="3" r="1" fill="rgba(60,50,20,0.55)" />
      <circle cx="3" cy="6" r="1" fill="rgba(60,50,20,0.55)" />
      <circle cx="7" cy="6" r="1" fill="rgba(60,50,20,0.55)" />
      <circle cx="3" cy="9" r="1" fill="rgba(60,50,20,0.55)" />
      <circle cx="7" cy="9" r="1" fill="rgba(60,50,20,0.55)" />
    </svg>
  );
}

function kindToHint(p) {
  if (p.sub) return p.sub;
  if (p.kind === 'city') return 'City · supplies & lodging';
  if (p.kind === 'town') return 'Small settlement';
  if (p.kind === 'camp') return 'Primitive campground';
  if (p.kind === 'fuel') return 'Fuel · provisions';
  if (p.kind === 'pass') return 'Mountain pass';
  if (p.kind === 'view') return 'Viewpoint';
  if (p.kind === 'landmark') return 'Landmark';
  if (p.kind === 'park') return 'National park';
  if (p.kind === 'visitor') return 'Visitor center';
  return '';
}

Object.assign(window, { BottomSheet, groupByBlock, autoNameBlock });
