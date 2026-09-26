'use client';

import type { Toast } from '../lib/sceneStore';

export function ToastStack({
  toasts,
  onDismiss
}: {
  toasts: Toast[];
  onDismiss: (id: number) => void;
}) {
  if (!toasts.length) return null;
  return (
    <div className="toast-stack" aria-live="polite">
      {toasts.map((t) => (
        <button
          key={t.id}
          type="button"
          className={`toast toast-${t.kind}`}
          onClick={() => onDismiss(t.id)}
        >
          {t.message}
        </button>
      ))}
    </div>
  );
}
