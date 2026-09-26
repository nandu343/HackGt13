'use client';

import { useEffect } from 'react';
import { AiPanel } from '../components/AiPanel';
import { BudgetPanel } from '../components/BudgetPanel';
import { CatalogPanel } from '../components/CatalogPanel';
import {
  CollaborationBar,
  ConnectionStatusPill
} from '../components/ConnectionStatus';
import { OnboardingStrip } from '../components/OnboardingStrip';
import { SceneCanvas } from '../components/SceneCanvas';
import { ToastStack } from '../components/ToastStack';
import { SceneStoreProvider, useSceneStore } from '../lib/sceneStore';

function Workspace() {
  const {
    scene,
    connection,
    selectedObjectId,
    setSelectedObjectId,
    applyLocalMove,
    applyLocalRotate,
    deleteSelected,
    undo,
    canUndo,
    isBusy,
    animating,
    toasts,
    dismissToast,
    reload,
    presence,
    actorId,
    voice,
    drawMode,
    strokes,
    toggleVoice,
    toggleMute,
    setDrawMode,
    addStroke,
    clearOwnStrokes,
    clearAllStrokes
  } = useSceneStore();

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const tag = (e.target as HTMLElement)?.tagName;
      if (tag === 'INPUT' || tag === 'TEXTAREA') return;

      if (e.key === 'Escape') {
        if (drawMode) {
          setDrawMode(false);
          return;
        }
        setSelectedObjectId(null);
        return;
      }
      if (e.key === 'Delete' || e.key === 'Backspace') {
        if (drawMode) return;
        e.preventDefault();
        void deleteSelected();
        return;
      }
      if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'z') {
        e.preventDefault();
        void undo();
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [deleteSelected, undo, setSelectedObjectId, drawMode, setDrawMode]);

  return (
    <main className="page-shell">
      <div className="atmosphere" aria-hidden />
      <section className="panel">
        <div className="header-row">
          <div>
            <p className="eyebrow">Spatial planning workspace</p>
            <h1>Shared Spatial AI</h1>
          </div>
          <div className="header-actions">
            <ConnectionStatusPill
              status={connection}
              version={scene?.version ?? null}
              presenceCount={presence.length}
            />
            <button
              type="button"
              className="btn ghost compact"
              onClick={() => void reload()}
              disabled={isBusy}
            >
              Reload
            </button>
            <button
              type="button"
              className="btn ghost compact"
              onClick={() => void undo()}
              disabled={!canUndo || isBusy}
            >
              Undo
            </button>
          </div>
        </div>

        <CollaborationBar
          presence={presence}
          actorId={actorId}
          voice={voice}
          drawMode={drawMode}
          onToggleVoice={() => void toggleVoice()}
          onToggleMute={toggleMute}
          onToggleDraw={() => setDrawMode(!drawMode)}
          onClearOwn={clearOwnStrokes}
          onClearAll={clearAllStrokes}
        />

        <OnboardingStrip />

        <div className="content-grid">
          <div
            className={`scene-card ${selectedObjectId ? 'has-selection' : ''} ${
              drawMode ? 'is-drawing' : ''
            }`}
          >
            {!scene && connection === 'connecting' && (
              <div className="scene-overlay">Loading scene from API…</div>
            )}
            {!scene && connection === 'error' && (
              <div className="scene-overlay error">
                Could not reach API. Start the backend, then Reload.
              </div>
            )}
            {scene && (
              <SceneCanvas
                bounds={scene.bounds}
                objects={scene.objects}
                selectedObjectId={selectedObjectId}
                onSelect={setSelectedObjectId}
                onMoveEnd={(id, pos) => void applyLocalMove(id, pos)}
                onRotateEnd={(id, rot) => void applyLocalRotate(id, rot)}
                disabled={isBusy || animating}
                drawMode={drawMode}
                strokes={strokes}
                onStrokeComplete={(points, plane) => {
                  addStroke({
                    strokeId: `stroke_${Date.now().toString(36)}_${Math.random()
                      .toString(36)
                      .slice(2, 6)}`,
                    color: '#e2b45c',
                    width: 0.025,
                    points,
                    plane
                  });
                }}
              />
            )}
            {scene && (
              <div className="scene-footer">
                <span>{scene.sceneId}</span>
                <span>
                  {scene.objects.length} objects
                  {strokes.length ? ` · ${strokes.length} strokes` : ''}
                  {selectedObjectId ? ` · selected ${selectedObjectId}` : ''}
                  {drawMode ? ' · draw on back wall' : ''}
                </span>
              </div>
            )}
          </div>

          <aside className="sidebar">
            <AiPanel />
            <BudgetPanel />
            <CatalogPanel />
          </aside>
        </div>
      </section>
      <ToastStack toasts={toasts} onDismiss={dismissToast} />
    </main>
  );
}

export default function Page() {
  return (
    <SceneStoreProvider>
      <Workspace />
    </SceneStoreProvider>
  );
}
