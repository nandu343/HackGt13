'use client';

type Props = {
  busy?: boolean;
  error?: string | null;
  onEnterDemo: () => void;
  onContinueExisting?: () => void;
  hasInvite?: boolean;
};

/**
 * Enter-room gate: Camera AR is primary; Map twin is an explicit secondary path.
 */
export function RoomEntryGate({
  busy,
  error,
  onEnterDemo,
  onContinueExisting,
  hasInvite
}: Props) {
  return (
    <div className="room-gate" role="dialog" aria-modal="true" aria-labelledby="room-gate-title">
      <div className="room-gate-card">
        <p className="room-gate-kicker">Shared Spatial</p>
        <h1 id="room-gate-title">Enter Camera AR</h1>
        <p className="room-gate-copy">
          {hasInvite
            ? 'Invite link detected — continue into shared Camera AR (live camera + furniture overlays) on the same scene.'
            : 'Live rear camera fills the world. Furniture, sketches, and friends overlay on top — no synthetic room box. Map twin is optional if you want the 3D model instead.'}
        </p>
        {error ? <p className="room-gate-error">{error}</p> : null}
        <div className="room-gate-actions">
          <button
            type="button"
            className="btn primary"
            disabled={busy}
            onClick={onEnterDemo}
          >
            {busy
              ? 'Loading…'
              : hasInvite
                ? 'Enter shared AR'
                : 'Enter Camera AR'}
          </button>
          {!hasInvite && onContinueExisting ? (
            <button
              type="button"
              className="btn ghost"
              disabled={busy}
              onClick={onContinueExisting}
            >
              Map twin instead
            </button>
          ) : null}
        </div>
        <p className="room-gate-hint">
          You can switch between Camera AR and Map twin anytime in the top bar. Invite keeps the
          same <code>sceneId</code>.
        </p>
      </div>
    </div>
  );
}
