'use client';

import { useState } from 'react';
import { useSceneStore } from '../lib/sceneStore';

function formatTime(iso: string): string {
  try {
    const d = new Date(iso);
    return d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' });
  } catch {
    return iso;
  }
}

export function TimelinePanel() {
  const {
    timeline,
    isBusy,
    restoreTimelineEntry,
    branchTimelineEntry
  } = useSceneStore();
  const [branchFor, setBranchFor] = useState<string | null>(null);
  const [branchName, setBranchName] = useState('alt');

  const entries = [...timeline].reverse();

  return (
    <section className="card panel-enter delay-1">
      <div className="panel-title-row">
        <h2>Timeline</h2>
        <span className="muted-pill">{timeline.length} entries</span>
      </div>
      <p className="panel-hint">
        Accepted ops and restores are saved. Restore rewinds; Branch forks a new scene id.
      </p>
      {!entries.length && <p className="empty-hint">No history yet — move something or accept AI.</p>}
      <ul className="timeline-list">
        {entries.map((entry) => (
          <li key={entry.entryId} className="timeline-item">
            <div className="timeline-meta">
              <strong>v{entry.version}</strong>
              <span>{formatTime(entry.createdAt)}</span>
            </div>
            <p className="timeline-label">{entry.label}</p>
            <p className="timeline-actor">
              {entry.displayName || entry.actorId || 'system'}
              {entry.branchId && entry.branchId !== 'main' ? ` · ${entry.branchId}` : ''}
            </p>
            <div className="btn-row tight">
              <button
                type="button"
                className="btn ghost compact"
                disabled={isBusy}
                onClick={() => void restoreTimelineEntry(entry.entryId)}
              >
                Restore
              </button>
              <button
                type="button"
                className="btn ghost compact"
                disabled={isBusy}
                onClick={() => {
                  setBranchFor(entry.entryId);
                  setBranchName(`alt-v${entry.version}`);
                }}
              >
                Branch
              </button>
            </div>
            {branchFor === entry.entryId && (
              <div className="timeline-branch-row">
                <input
                  value={branchName}
                  onChange={(e) => setBranchName(e.target.value)}
                  placeholder="branch name"
                  disabled={isBusy}
                />
                <button
                  type="button"
                  className="btn primary compact"
                  disabled={isBusy || !branchName.trim()}
                  onClick={() => {
                    void branchTimelineEntry(entry.entryId, branchName);
                    setBranchFor(null);
                  }}
                >
                  Fork
                </button>
                <button
                  type="button"
                  className="btn ghost compact"
                  onClick={() => setBranchFor(null)}
                >
                  Cancel
                </button>
              </div>
            )}
          </li>
        ))}
      </ul>
    </section>
  );
}
