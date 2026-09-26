'use client';

import { useEffect, useRef, useState } from 'react';
import { AiPanel } from '../components/AiPanel';
import { BudgetPanel } from '../components/BudgetPanel';
import { CatalogPanel } from '../components/CatalogPanel';
import {
  CollaborationBar,
  ConnectionStatusPill
} from '../components/ConnectionStatus';
import { DisagreementPanel } from '../components/DisagreementPanel';
import { IntentModal } from '../components/IntentModal';
import { InviteModal } from '../components/InviteModal';
import { CameraARBackground } from '../components/CameraARBackground';
import { RoomEntryGate } from '../components/RoomEntryGate';
import { SceneCanvas, xrStore, type ViewMode } from '../components/SceneCanvas';
import { SelectionBar } from '../components/SelectionBar';
import { SidebarShell } from '../components/SidebarShell';
import { TimelinePanel } from '../components/TimelinePanel';
import { ToastStack } from '../components/ToastStack';
import { canManipulateObject } from '../lib/objectPolicy';
import {
  DEMO_SCENE_ID,
  SceneStoreProvider,
  useSceneStore
} from '../lib/sceneStore';

const ROOM_ENTERED_KEY = 'ssa_room_entered';

function roomEnteredStorageKey(sceneId: string) {
  return `${ROOM_ENTERED_KEY}_${sceneId}`;
}

function Workspace({
  inviteOpen,
  onInviteOpen,
  onInviteClose,
  hasInvite,
  forceGate
}: {
  inviteOpen: boolean;
  onInviteOpen: () => void;
  onInviteClose: () => void;
  hasInvite: boolean;
  forceGate: boolean;
}) {
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
    clearAllStrokes,
    openIntentModal,
    reportPresencePose,
    disagreement,
    ghostObjectsA,
    ghostObjectsB,
    disagreementView
  } = useSceneStore();

  const [deleteArmed, setDeleteArmed] = useState(false);
  const deleteTimer = useRef<number | null>(null);
  /** Hero: Camera AR. Secondary: Map twin. Mutually exclusive. */
  const [viewMode, setViewMode] = useState<ViewMode>('ar');
  const [entered, setEntered] = useState(false);
  const [xrSupported, setXrSupported] = useState(false);

  useEffect(() => {
    let cancelled = false;
    const check = async () => {
      try {
        const nav = navigator as Navigator & {
          xr?: { isSessionSupported?: (m: string) => Promise<boolean> };
        };
        const ok = Boolean(
          await nav.xr?.isSessionSupported?.('immersive-ar')
        );
        if (!cancelled) setXrSupported(ok);
      } catch {
        if (!cancelled) setXrSupported(false);
      }
    };
    void check();
    return () => {
      cancelled = true;
    };
  }, []);

  useEffect(() => {
    try {
      if (forceGate) {
        setEntered(false);
        return;
      }
      if (hasInvite) {
        setEntered(true);
        return;
      }
      const key = roomEnteredStorageKey(scene?.sceneId ?? DEMO_SCENE_ID);
      setEntered(sessionStorage.getItem(key) === '1');
    } catch {
      setEntered(false);
    }
  }, [hasInvite, forceGate, scene?.sceneId]);

  const markEntered = () => {
    setEntered(true);
    try {
      sessionStorage.setItem(
        roomEnteredStorageKey(scene?.sceneId ?? DEMO_SCENE_ID),
        '1'
      );
    } catch {
      // ignore
    }
  };

  useEffect(() => {
    setDeleteArmed(false);
  }, [selectedObjectId]);

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
        setDeleteArmed(false);
        return;
      }
      if (e.key === 'Delete' || e.key === 'Backspace') {
        if (drawMode) return;
        e.preventDefault();
        if (!selectedObjectId || !scene) return;
        const obj = scene.objects.find((o) => o.id === selectedObjectId);
        if (!obj || !canManipulateObject(obj)) return;
        if (!deleteArmed) {
          setDeleteArmed(true);
          if (deleteTimer.current != null) window.clearTimeout(deleteTimer.current);
          deleteTimer.current = window.setTimeout(() => {
            setDeleteArmed(false);
          }, 2200);
          return;
        }
        setDeleteArmed(false);
        void deleteSelected();
        return;
      }
      if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'z') {
        e.preventDefault();
        void undo();
      }
    };
    window.addEventListener('keydown', onKey);
    return () => {
      window.removeEventListener('keydown', onKey);
      if (deleteTimer.current != null) window.clearTimeout(deleteTimer.current);
    };
  }, [
    deleteSelected,
    undo,
    setSelectedObjectId,
    drawMode,
    setDrawMode,
    selectedObjectId,
    scene,
    deleteArmed
  ]);

  const showGhosts = Boolean(disagreement) && disagreementView !== 'live';
  const selected = scene?.objects.find((o) => o.id === selectedObjectId);
  const deleteHint = deleteArmed ? ' · Del again' : '';
  const showGate = !entered;

  return (
    <main
      className={`hud-shell ${
        viewMode === 'ar' && entered ? 'ar-active' : ''
      }`}
    >
      <div
        className={`hud-viewport ${selectedObjectId ? 'has-selection' : ''} ${
          drawMode ? 'is-drawing' : ''
        } ${showGhosts ? 'has-ghosts' : ''} ${
          viewMode === 'ar' ? 'ar-view' : 'map-view'
        }`}
      >
        {entered && viewMode === 'ar' ? (
          <CameraARBackground active />
        ) : null}
        {!scene && connection === 'connecting' && (
          <div className="scene-overlay">
            <div className="scene-empty">
              <span className="scene-empty-pulse" aria-hidden />
              <strong>Loading scene…</strong>
              <p>Connecting to the shared scene graph.</p>
            </div>
          </div>
        )}
        {!scene && connection === 'error' && (
          <div className="scene-overlay error">
            <div className="scene-empty">
              <strong>API unreachable</strong>
              <p>Start the backend, then retry.</p>
              <button
                type="button"
                className="btn primary compact"
                onClick={() => void reload()}
              >
                Retry
              </button>
            </div>
          </div>
        )}
        {!scene && connection === 'disconnected' && (
          <div className="scene-overlay">
            <div className="scene-empty">
              <strong>Disconnected</strong>
              <p>Reload to reconnect.</p>
              <button
                type="button"
                className="btn primary compact"
                onClick={() => void reload()}
              >
                Reload
              </button>
            </div>
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
            disabled={isBusy || animating || showGate}
            drawMode={drawMode && !showGate}
            strokes={strokes}
            presence={presence}
            localUserId={actorId}
            onPresencePose={reportPresencePose}
            ghostObjectsA={showGhosts ? ghostObjectsA : []}
            ghostObjectsB={showGhosts ? ghostObjectsB : []}
            ghostMode="overlay"
            viewMode={viewMode}
            onStrokeComplete={(points, plane) => {
              addStroke({
                strokeId: `stroke_${Date.now().toString(36)}_${Math.random()
                  .toString(36)
                  .slice(2, 6)}`,
                color: '#e2b45c',
                width: 0.025,
                points,
                plane: plane ?? 'free'
              });
            }}
          />
        )}

        {showGate && (
          <RoomEntryGate
            busy={isBusy || (!scene && connection === 'connecting')}
            error={
              !scene && connection === 'error'
                ? 'API unreachable — start the backend, then retry.'
                : null
            }
            hasInvite={hasInvite}
            onEnterDemo={() => {
              if (!scene && connection === 'error') {
                void reload();
                return;
              }
              setViewMode('ar');
              markEntered();
            }}
            onContinueExisting={() => {
              setViewMode('map');
              markEntered();
            }}
          />
        )}

        {!showGate && <SelectionBar />}

        {showGhosts && !showGate && (
          <div className="ghost-legend" aria-hidden>
            <span className="ghost-a">A</span>
            <span className="ghost-b">B</span>
          </div>
        )}

        {scene && !showGate && (
          <div className="hud-scene-meta" aria-live="polite">
            <span>{scene.sceneId}</span>
            <span>
              {scene.objects.length} obj
              {strokes.length ? ` · ${strokes.length} stroke` : ''}
              {selected
                ? ` · ${selected.type.replace(/_/g, ' ')}${
                    selected.source === 'existing' ? ' (room)' : ''
                  }`
                : ''}
              {deleteHint}
              {drawMode ? ' · AR sketch' : ''}
              {showGhosts ? ' · ghosts' : ''}
              {viewMode === 'ar' ? ' · Camera AR' : ' · Map twin'}
            </span>
          </div>
        )}
      </div>

      {!showGate && (
        <>
          <header className="hud-topbar">
            <div className="hud-brand">
              <span className="hud-logo" aria-hidden />
              <span className="hud-title">Shared Spatial</span>
            </div>
            <div className="hud-top-actions">
              <ConnectionStatusPill
                status={connection}
                version={scene?.version ?? null}
                presenceCount={presence.length}
              />
              <div className="view-mode-toggle" role="group" aria-label="View mode">
                <button
                  type="button"
                  className={`btn compact ${viewMode === 'ar' ? 'primary' : 'ghost'}`}
                  onClick={() => setViewMode('ar')}
                  title="Camera AR — live camera + overlays only"
                  aria-pressed={viewMode === 'ar'}
                >
                  Camera AR
                </button>
                <button
                  type="button"
                  className={`btn compact ${viewMode === 'map' ? 'primary' : 'ghost'}`}
                  onClick={() => setViewMode('map')}
                  title="Map twin — full 3D room model, no camera"
                  aria-pressed={viewMode === 'map'}
                >
                  Map twin
                </button>
              </div>
              {xrSupported && viewMode === 'ar' ? (
                <button
                  type="button"
                  className="btn accent compact"
                  onClick={() => void xrStore.enterAR()}
                  title="Enter WebXR immersive-ar (Android Chrome / supported headsets)"
                >
                  WebXR AR
                </button>
              ) : null}
              <button
                type="button"
                className="btn ghost compact"
                onClick={openIntentModal}
                disabled={!scene || isBusy}
                title="Plan with friends"
              >
                Plan
              </button>
              <button
                type="button"
                className="btn ghost compact"
                onClick={onInviteOpen}
                disabled={!scene || isBusy}
                title="Invite friends"
              >
                Invite
              </button>
              <button
                type="button"
                className={`btn compact mic-btn ${voice.enabled && !voice.muted ? 'primary' : 'ghost'} ${
                  voice.speaking ? 'speaking' : ''
                }`}
                onClick={() => {
                  if (!voice.enabled) void toggleVoice();
                  else toggleMute();
                }}
                disabled={!scene}
                title={
                  !voice.enabled
                    ? 'Join voice'
                    : voice.muted
                      ? 'Unmute'
                      : 'Mute'
                }
                aria-pressed={voice.enabled && !voice.muted}
              >
                <span className="vad-ring" aria-hidden />
                {!voice.enabled ? 'Mic' : voice.muted ? 'Muted' : 'Mic'}
              </button>
              <button
                type="button"
                className="btn ghost compact"
                onClick={() => void undo()}
                disabled={!canUndo || isBusy}
                title="Undo"
              >
                Undo
              </button>
              <button
                type="button"
                className="btn ghost compact"
                onClick={() => void reload()}
                disabled={isBusy}
                title="Reload scene"
              >
                Reload
              </button>
            </div>
          </header>

          <SidebarShell
            drawMode={drawMode}
            onSelectTool={() => setSelectedObjectId(null)}
            onToggleDraw={(next) => setDrawMode(next)}
            plan={<AiPanel />}
            shop={
              <>
                <BudgetPanel />
                <CatalogPanel />
              </>
            }
            draw={
              <section className="card">
                <p className="panel-hint">
                  Draw in space — free 3D strokes along your pointer ray (not stuck to a
                  wall). Syncs live to everyone in the room.
                </p>
                <div className="btn-row">
                  <button
                    type="button"
                    className={`btn ${drawMode ? 'primary' : 'ghost'}`}
                    onClick={() => setDrawMode(!drawMode)}
                  >
                    {drawMode ? 'Exit sketch' : 'AR sketch'}
                  </button>
                  <button type="button" className="btn ghost" onClick={clearOwnStrokes}>
                    Clear mine
                  </button>
                  <button type="button" className="btn ghost" onClick={clearAllStrokes}>
                    Clear all
                  </button>
                </div>
              </section>
            }
            timeline={<TimelinePanel />}
            disagree={<DisagreementPanel />}
            voice={
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
                onInvite={onInviteOpen}
              />
            }
          />

          <IntentModal />
          <InviteModal open={inviteOpen} onClose={onInviteClose} />
        </>
      )}

      <ToastStack toasts={toasts} onDismiss={dismissToast} />
    </main>
  );
}

export default function Page() {
  const [sceneId, setSceneId] = useState(DEMO_SCENE_ID);
  const [inviteOpen, setInviteOpen] = useState(false);
  const [inviteToken, setInviteToken] = useState<string | null>(null);
  const [forceGate, setForceGate] = useState(false);

  useEffect(() => {
    try {
      const params = new URLSearchParams(window.location.search);
      const q = params.get('scene');
      if (q?.trim()) setSceneId(q.trim());
      const invite = params.get('invite');
      if (invite?.trim()) {
        setInviteToken(invite.trim());
        setInviteOpen(true);
      }
      // Optional reset: ?gate=1 forces the enter-room prompt again.
      if (params.get('gate') === '1') setForceGate(true);
    } catch {
      // keep demo id
    }
  }, []);

  return (
    <SceneStoreProvider key={sceneId} sceneId={sceneId}>
      <Workspace
        inviteOpen={inviteOpen}
        onInviteOpen={() => setInviteOpen(true)}
        onInviteClose={() => setInviteOpen(false)}
        hasInvite={Boolean(inviteToken)}
        forceGate={forceGate}
      />
      {inviteToken ? (
        <span className="sr-only" data-invite={inviteToken}>
          Joined via invite
        </span>
      ) : null}
    </SceneStoreProvider>
  );
}
