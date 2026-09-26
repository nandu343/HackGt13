'use client';

import type { PresenceUser } from '@shared-spatial-ai/schema';
import type { ConnectionStatus } from '../lib/sceneStore';
import type { VoiceState } from '../lib/voiceMesh';

const LABELS: Record<ConnectionStatus, string> = {
  connecting: 'Connecting…',
  connected: 'API connected',
  disconnected: 'Disconnected',
  error: 'Connection error',
  syncing: 'Syncing…'
};

export function ConnectionStatusPill({
  status,
  version,
  presenceCount
}: {
  status: ConnectionStatus;
  version: number | null;
  presenceCount?: number;
}) {
  const peers =
    presenceCount != null && presenceCount > 0
      ? ` · ${presenceCount} online`
      : '';

  return (
    <div className={`status-pill status-${status}`} role="status">
      <span className="status-dot" aria-hidden />
      <span>
        {LABELS[status]}
        {version != null ? ` · v${version}` : ''}
        {peers}
      </span>
    </div>
  );
}

export function CollaborationBar({
  presence,
  actorId,
  voice,
  drawMode,
  onToggleVoice,
  onToggleMute,
  onToggleDraw,
  onClearOwn,
  onClearAll
}: {
  presence: PresenceUser[];
  actorId: string;
  voice: VoiceState;
  drawMode: boolean;
  onToggleVoice: () => void;
  onToggleMute: () => void;
  onToggleDraw: () => void;
  onClearOwn: () => void;
  onClearAll: () => void;
}) {
  return (
    <div className="collab-bar">
      <div className="collab-controls">
        <button
          type="button"
          className={`btn compact ${voice.enabled ? 'primary' : 'ghost'}`}
          onClick={onToggleVoice}
          title={voice.enabled ? 'Leave voice' : 'Join voice chat'}
        >
          {voice.enabled ? 'Leave voice' : 'Join voice'}
        </button>
        {voice.enabled && (
          <button
            type="button"
            className={`btn compact mic-btn ${voice.muted ? 'ghost' : 'primary'} ${
              voice.speaking ? 'speaking' : ''
            }`}
            onClick={onToggleMute}
            title={voice.muted ? 'Unmute' : 'Mute'}
            aria-pressed={!voice.muted}
          >
            <span className="vad-ring" aria-hidden />
            {voice.muted ? 'Unmute' : 'Mute'}
          </button>
        )}
        <button
          type="button"
          className={`btn compact ${drawMode ? 'primary' : 'ghost'}`}
          onClick={onToggleDraw}
          title="Draw on the back wall (shared)"
        >
          {drawMode ? 'Drawing…' : 'Draw'}
        </button>
        {drawMode && (
          <>
            <button type="button" className="btn ghost compact" onClick={onClearOwn}>
              Clear mine
            </button>
            <button type="button" className="btn ghost compact" onClick={onClearAll}>
              Clear all
            </button>
          </>
        )}
      </div>
      {presence.length > 0 && (
        <ul className="presence-list" aria-label="People in room">
          {presence.map((p) => {
            const isSelf = p.userId === actorId;
            return (
              <li
                key={p.userId}
                className={`presence-chip ${p.voiceSpeaking ? 'is-speaking' : ''}`}
                title={p.userId}
              >
                <span
                  className="presence-swatch"
                  style={{ background: p.color || '#6ec8e8' }}
                  aria-hidden
                />
                <span className="presence-name">
                  {p.displayName}
                  {isSelf ? ' (you)' : ''}
                </span>
                {p.voiceEnabled && (
                  <span
                    className={`voice-badge ${p.voiceSpeaking ? 'live' : ''}`}
                    title={p.voiceSpeaking ? 'Speaking' : 'Voice on'}
                  >
                    {p.voiceSpeaking ? '●' : '○'}
                  </span>
                )}
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}
