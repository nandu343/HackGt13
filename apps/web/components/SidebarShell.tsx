'use client';

import { useEffect, useState, type ReactNode } from 'react';

export type HudToolId =
  | 'select'
  | 'draw'
  | 'plan'
  | 'shop'
  | 'timeline'
  | 'disagree'
  | 'voice';

const TOOLS: {
  id: HudToolId;
  label: string;
  icon: string;
  opensDrawer: boolean;
}[] = [
  { id: 'select', label: 'Select', icon: '◇', opensDrawer: false },
  { id: 'draw', label: 'Sketch', icon: '✎', opensDrawer: true },
  { id: 'plan', label: 'Plan', icon: '▦', opensDrawer: true },
  { id: 'shop', label: 'Shop', icon: '$', opensDrawer: true },
  { id: 'timeline', label: 'Timeline', icon: '⏱', opensDrawer: true },
  { id: 'disagree', label: 'Disagree', icon: '⇄', opensDrawer: true },
  { id: 'voice', label: 'Voice', icon: '◎', opensDrawer: true }
];

const DRAWER_TITLES: Record<Exclude<HudToolId, 'select'>, string> = {
  draw: 'AR sketch',
  plan: 'AI layout',
  shop: 'Shop / Recommendations',
  timeline: 'Timeline',
  disagree: 'Disagreement',
  voice: 'Voice & presence'
};

/**
 * Left tool rail + right/bottom drawer. Panels stay mounted while their
 * tool is active so state (forms, scroll) survives open/close cycles.
 */
export function SidebarShell({
  plan,
  shop,
  draw,
  timeline,
  disagree,
  voice,
  drawMode,
  onSelectTool,
  onToggleDraw
}: {
  plan: ReactNode;
  shop: ReactNode;
  draw: ReactNode;
  timeline: ReactNode;
  disagree: ReactNode;
  voice: ReactNode;
  drawMode: boolean;
  onSelectTool: () => void;
  onToggleDraw: (next: boolean) => void;
}) {
  const [active, setActive] = useState<HudToolId | null>(null);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key !== 'Escape') return;
      const tag = (e.target as HTMLElement)?.tagName;
      if (tag === 'INPUT' || tag === 'TEXTAREA') return;
      if (active) {
        setActive(null);
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [active]);

  const open = active != null && active !== 'select';

  const activate = (id: HudToolId) => {
    if (id === 'select') {
      setActive(null);
      onSelectTool();
      if (drawMode) onToggleDraw(false);
      return;
    }
    if (id === 'draw') {
      const nextOpen = active === 'draw' ? null : 'draw';
      setActive(nextOpen);
      if (nextOpen === 'draw' && !drawMode) onToggleDraw(true);
      if (nextOpen == null && drawMode) onToggleDraw(false);
      return;
    }
    setActive((prev) => (prev === id ? null : id));
  };

  const panelFor = (id: HudToolId): ReactNode => {
    switch (id) {
      case 'plan':
        return plan;
      case 'shop':
        return shop;
      case 'draw':
        return draw;
      case 'timeline':
        return timeline;
      case 'disagree':
        return disagree;
      case 'voice':
        return voice;
      default:
        return null;
    }
  };

  const railActive = (id: HudToolId) => {
    if (id === 'select') return active == null && !drawMode;
    if (id === 'draw') return active === 'draw' || drawMode;
    return active === id;
  };

  return (
    <>
      <nav className="hud-tool-rail" aria-label="Tools">
        {TOOLS.map((tool) => (
          <button
            key={tool.id}
            type="button"
            className={`hud-tool ${railActive(tool.id) ? 'is-active' : ''}`}
            aria-pressed={railActive(tool.id)}
            aria-label={tool.label}
            title={tool.label}
            onClick={() => activate(tool.id)}
          >
            <span className="hud-tool-icon" aria-hidden>
              {tool.icon}
            </span>
            <span className="hud-tool-label">{tool.label}</span>
          </button>
        ))}
      </nav>

      {open && active && (
        <aside
          className="hud-drawer"
          role="complementary"
          aria-label={DRAWER_TITLES[active as Exclude<HudToolId, 'select'>]}
        >
          <header className="hud-drawer-head">
            <h2>{DRAWER_TITLES[active as Exclude<HudToolId, 'select'>]}</h2>
            <button
              type="button"
              className="btn ghost compact"
              onClick={() => {
                if (active === 'draw' && drawMode) onToggleDraw(false);
                setActive(null);
              }}
            >
              Close
            </button>
          </header>
          <div className="hud-drawer-body">{panelFor(active)}</div>
        </aside>
      )}
    </>
  );
}
