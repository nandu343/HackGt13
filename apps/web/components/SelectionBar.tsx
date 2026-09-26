'use client';

import { useState } from 'react';
import { canManipulateObject, objectLabel } from '../lib/objectPolicy';
import { useSceneStore } from '../lib/sceneStore';

/** Floating selection chrome for move / clear-existing furniture. */
export function SelectionBar() {
  const {
    scene,
    selectedObjectId,
    setSelectedObjectId,
    deleteSelected,
    isBusy,
    animating
  } = useSceneStore();
  const [confirming, setConfirming] = useState(false);

  if (!scene || !selectedObjectId) return null;
  const obj = scene.objects.find((o) => o.id === selectedObjectId);
  if (!obj || !canManipulateObject(obj)) return null;

  const isExisting = obj.source === 'existing';
  const busy = isBusy || animating;

  const onRemove = async () => {
    if (!confirming) {
      setConfirming(true);
      return;
    }
    setConfirming(false);
    await deleteSelected();
  };

  return (
    <div className={`selection-bar ${isExisting ? 'is-existing' : ''}`} role="region" aria-label="Selected object">
      <div className="selection-bar-copy">
        <strong>{objectLabel(obj)}</strong>
        <span>
          {isExisting
            ? 'Physical furniture — drag to relocate, or clear out of the way'
            : 'Drag the gizmo to move · Delete to remove'}
        </span>
      </div>
      <div className="selection-bar-actions">
        {confirming ? (
          <>
            <button
              type="button"
              className="btn compact danger"
              onClick={() => void onRemove()}
              disabled={busy}
            >
              Confirm remove
            </button>
            <button
              type="button"
              className="btn ghost compact"
              onClick={() => setConfirming(false)}
              disabled={busy}
            >
              Cancel
            </button>
          </>
        ) : (
          <>
            <button
              type="button"
              className="btn compact danger-soft"
              onClick={() => void onRemove()}
              disabled={busy}
              title="Remove from scene (synced to peers)"
            >
              Remove
            </button>
            <button
              type="button"
              className="btn ghost compact"
              onClick={() => {
                setConfirming(false);
                setSelectedObjectId(null);
              }}
            >
              Deselect
            </button>
          </>
        )}
      </div>
    </div>
  );
}
