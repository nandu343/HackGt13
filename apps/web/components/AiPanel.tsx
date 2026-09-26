'use client';

import { useSceneStore } from '../lib/sceneStore';

export function AiPanel() {
  const {
    prompt,
    setPrompt,
    guestCount,
    setGuestCount,
    targetBudget,
    setTargetBudget,
    pendingLayout,
    requestLayout,
    acceptLayout,
    rejectLayout,
    isBusy
  } = useSceneStore();

  const warnings = pendingLayout?.warnings ?? [];
  const hasWarnings = warnings.length > 0;
  const fixedOps = pendingLayout?.fixedOps ?? 0;
  const canAccept = Boolean(pendingLayout?.operations.length);
  const plannerMode = pendingLayout?.plannerMode;

  return (
    <section className="card panel-enter">
      <h2>AI layout</h2>
      <label className="field">
        <span>Prompt</span>
        <textarea
          rows={3}
          value={prompt}
          onChange={(e) => setPrompt(e.target.value)}
          disabled={isBusy}
        />
      </label>
      <div className="field-row">
        <label className="field">
          <span>Guests</span>
          <input
            type="number"
            min={1}
            max={100}
            value={guestCount}
            onChange={(e) => setGuestCount(Number(e.target.value) || 1)}
            disabled={isBusy}
          />
        </label>
        <label className="field">
          <span>Budget $</span>
          <input
            type="number"
            min={0}
            step={10}
            value={targetBudget}
            onChange={(e) => setTargetBudget(Number(e.target.value) || 0)}
            disabled={isBusy}
          />
        </label>
      </div>
      <button
        type="button"
        className="btn primary"
        onClick={() => void requestLayout()}
        disabled={isBusy || !prompt.trim()}
      >
        {isBusy ? 'Thinking…' : 'Generate layout'}
      </button>

      {pendingLayout && (
        <div className="ai-result">
          <p className="ai-scenario">
            Scenario: <strong>{pendingLayout.scenario}</strong>
            {plannerMode ? (
              <>
                {' '}
                · mode <strong>{plannerMode}</strong>
              </>
            ) : null}
          </p>
          <p className="ai-reasoning">{pendingLayout.reasoningSummary}</p>
          <ul className="op-list">
            {pendingLayout.operations.map((op, i) => (
              <li key={`${op.type}-${op.objectId ?? i}`}>
                <code>{op.type}</code>
                {op.objectId ? ` · ${op.objectId}` : ''}
                {op.productId ? ` · ${op.productId}` : ''}
              </li>
            ))}
          </ul>
          {!canAccept && (
            <p className="warn-text">No valid ops left after validation — Accept disabled.</p>
          )}
          {fixedOps > 0 && (
            <p className="ai-meta">
              Auto-fixed <strong>{fixedOps}</strong> op{fixedOps === 1 ? '' : 's'} during validation.
            </p>
          )}
          {hasWarnings && (
            <ul className="warn-list">
              {warnings.map((w) => (
                <li key={w}>{w}</li>
              ))}
            </ul>
          )}
          <div className="btn-row">
            <button
              type="button"
              className="btn primary"
              onClick={() => void acceptLayout()}
              disabled={isBusy || !canAccept}
            >
              Accept
            </button>
            <button
              type="button"
              className="btn ghost"
              onClick={rejectLayout}
              disabled={isBusy}
            >
              Reject
            </button>
          </div>
        </div>
      )}
    </section>
  );
}
