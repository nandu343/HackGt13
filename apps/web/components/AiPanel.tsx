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
    cancelLayoutRequest,
    acceptLayout,
    rejectLayout,
    proposeDisagreement,
    disagreement,
    isBusy,
    openIntentModal,
    productMap
  } = useSceneStore();

  const warnings = pendingLayout?.warnings ?? [];
  const hasWarnings = warnings.length > 0;
  const fixedOps = pendingLayout?.fixedOps ?? 0;
  const canAccept = Boolean(pendingLayout?.operations.length);
  const plannerMode = pendingLayout?.plannerMode;
  const valuePicks = pendingLayout?.valuePicks ?? [];
  const bestValueIds = new Set(valuePicks.map((vp) => vp.productId));
  const valueReasonById = new Map(valuePicks.map((vp) => [vp.productId, vp.reason]));
  const proposeLabel = disagreement
    ? disagreement.proposalB
      ? 'Replace proposal B'
      : 'Submit as proposal B'
    : 'Propose (disagreement)';

  return (
    <section className="card panel-enter">
      <div className="panel-title-row">
        <h2>AI layout</h2>
        <button
          type="button"
          className="btn ghost compact"
          onClick={openIntentModal}
          disabled={isBusy}
        >
          Plan with friends
        </button>
      </div>
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
      <div className="btn-row">
        <button
          type="button"
          className="btn primary"
          onClick={() => void requestLayout()}
          disabled={isBusy || !prompt.trim()}
        >
          {isBusy ? 'Thinking…' : 'Generate layout'}
        </button>
        {isBusy ? (
          <button type="button" className="btn ghost" onClick={cancelLayoutRequest}>
            Cancel
          </button>
        ) : null}
      </div>

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
          {valuePicks.length > 0 && (
            <ul className="value-pick-list">
              {valuePicks.map((vp) => {
                const cat = productMap.get(vp.productId);
                const url = cat?.productUrl || cat?.websiteUrl || null;
                return (
                  <li key={`${vp.objectId ?? ''}-${vp.productId}`}>
                    <span className="value-badge">Best value pick</span>{' '}
                    {vp.name ?? vp.productId}
                    {vp.rating != null ? ` · ★${vp.rating.toFixed(1)}` : ''}
                    {vp.price != null ? ` · $${vp.price.toFixed(0)}` : ''}
                    {url ? (
                      <>
                        {' '}
                        <a href={url} target="_blank" rel="noopener noreferrer">
                          Open website
                        </a>
                      </>
                    ) : null}
                    <span className="value-reason">{vp.reason}</span>
                  </li>
                );
              })}
            </ul>
          )}
          <ul className="op-list">
            {pendingLayout.operations.map((op, i) => (
              <li key={`${op.type}-${op.objectId ?? i}`}>
                <code>{op.type}</code>
                {op.objectId ? ` · ${op.objectId}` : ''}
                {op.productId ? ` · ${op.productId}` : ''}
                {op.productId && bestValueIds.has(op.productId) ? (
                  <span
                    className="value-badge inline"
                    title={valueReasonById.get(op.productId)}
                  >
                    Best value pick
                  </span>
                ) : null}
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
              onClick={() => void proposeDisagreement()}
              disabled={isBusy || !canAccept}
            >
              {proposeLabel}
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
