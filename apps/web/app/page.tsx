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
import { SceneCanvas } from '../components/SceneCanvas';
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

function Workspace({
  inviteOpen,
  onInviteOpen,
  onInviteClose
}: {
  inviteOpen: boolean;
  onInviteOpen: () => void;
  onInviteClose: () => void;
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

  return (
    <main className="hud-shell">
      <div
        className={`hud-viewport ${selectedObjectId ? 'has-selection' : ''} ${
          drawMode ? 'is-drawing' : ''
        } ${showGhosts ? 'has-ghosts' : ''}`}
      >
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
            disabled={isBusy || animating}
            drawMode={drawMode}
            strokes={strokes}
            presence={presence}
            localUserId={actorId}
            onPresencePose={reportPresencePose}
            ghostObjectsA={showGhosts ? ghostObjectsA : []}
            ghostObjectsB={showGhosts ? ghostObjectsB : []}
            ghostMode="overlay"
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

        <SelectionBar />

        {showGhosts && (
          <div className="ghost-legend" aria-hidden>
            <span className="ghost-a">A</span>
            <span className="ghost-b">B</span>
          </div>
        )}

        {scene && (
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
              {drawMode ? ' · draw' : ''}
              {showGhosts ? ' · ghosts' : ''}
            </span>
          </div>
        )}
      </div>

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
              Paint on the back wall — strokes sync live to everyone in the room.
            </p>
            <div className="btn-row">
              <button
                type="button"
                className={`btn ${drawMode ? 'primary' : 'ghost'}`}
                onClick={() => setDrawMode(!drawMode)}
              >
                {drawMode ? 'Exit draw' : 'Start drawing'}
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
      <ToastStack toasts={toasts} onDismiss={dismissToast} />
    </main>
  );
}

export default function Page() {
  const [sceneId, setSceneId] = useState(DEMO_SCENE_ID);
  const [inviteOpen, setInviteOpen] = useState(false);
  const [inviteToken, setInviteToken] = useState<string | null>(null);

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
      />
      {inviteToken ? (
        <span className="sr-only" data-invite={inviteToken}>
          Joined via invite
        </span>
      ) : null}
    </SceneStoreProvider>
  );
}
