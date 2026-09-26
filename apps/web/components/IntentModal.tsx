'use client';

import { useEffect, useMemo, useState } from 'react';
import { useSceneStore, type IntentIdea } from '../lib/sceneStore';

export const SCENARIO_CHIPS = [
  {
    id: 'party',
    label: 'Party',
    prompt: 'Turn this into a lively party space with room for dancing and mingling.'
  },
  {
    id: 'study',
    label: 'Study',
    prompt: 'Turn this into a focused study / coworking space with desks and quiet zones.'
  },
  {
    id: 'dinner',
    label: 'Dinner',
    prompt: 'Turn this into a dinner gathering with a clear dining area and seating for guests.'
  },
  {
    id: 'movie',
    label: 'Movie night',
    prompt: 'Turn this into a cozy movie-night lounge with seating facing a screen wall.'
  },
  {
    id: 'custom',
    label: 'Custom',
    prompt: ''
  }
] as const;

export type ScenarioId = (typeof SCENARIO_CHIPS)[number]['id'];

function composePrompt(
  scenarioId: ScenarioId,
  notes: string,
  ideas: IntentIdea[]
): string {
  const chip = SCENARIO_CHIPS.find((c) => c.id === scenarioId);
  const base =
    scenarioId === 'custom'
      ? notes.trim()
      : [chip?.prompt ?? '', notes.trim() ? `Extra notes: ${notes.trim()}` : '']
          .filter(Boolean)
          .join(' ');
  const friendBits = ideas
    .map((i) => i.text.trim())
    .filter(Boolean)
    .slice(0, 12);
  if (!friendBits.length) return base;
  return `${base}${base ? ' ' : ''}Friends suggested: ${friendBits.join('; ')}.`;
}

export function IntentModal() {
  const {
    scene,
    intentModalOpen,
    closeIntentModal,
    intentIdeas,
    intentDraft,
    broadcastIntentDraft,
    addIntentIdea,
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
    isBusy,
    actorId,
    presence,
    markIntentSeen
  } = useSceneStore();

  const [scenarioId, setScenarioId] = useState<ScenarioId>('party');
  const [notes, setNotes] = useState('');
  const [ideaDraft, setIdeaDraft] = useState('');
  const [step, setStep] = useState<'compose' | 'preview'>('compose');

  // Sync remote draft from peers (don't clobber local typing from self)
  useEffect(() => {
    if (!intentDraft || intentDraft.actorId === actorId) return;
    if (intentDraft.scenario) {
      const match = SCENARIO_CHIPS.find((c) => c.id === intentDraft.scenario);
      if (match) setScenarioId(match.id);
    }
    if (typeof intentDraft.guestCount === 'number') setGuestCount(intentDraft.guestCount);
    if (typeof intentDraft.budget === 'number') setTargetBudget(intentDraft.budget);
    if (intentDraft.prompt != null && scenarioId === 'custom') {
      setNotes(intentDraft.prompt);
    }
  }, [intentDraft, actorId, setGuestCount, setTargetBudget, scenarioId]);

  useEffect(() => {
    if (pendingLayout && intentModalOpen) setStep('preview');
  }, [pendingLayout, intentModalOpen]);

  useEffect(() => {
    if (!intentModalOpen) {
      setStep('compose');
      return;
    }
    broadcastIntentDraft({
      scenario: scenarioId,
      prompt: scenarioId === 'custom' ? notes : SCENARIO_CHIPS.find((c) => c.id === scenarioId)?.prompt,
      guestCount,
      budget: targetBudget
    });
  }, [intentModalOpen]); // eslint-disable-line react-hooks/exhaustive-deps -- open once

  const peerCount = Math.max(0, presence.length - 1);
  const composed = useMemo(
    () => composePrompt(scenarioId, notes, intentIdeas),
    [scenarioId, notes, intentIdeas]
  );

  if (!intentModalOpen || !scene) return null;

  const canGenerate = Boolean(composed.trim()) && !isBusy;
  const canAccept = Boolean(pendingLayout?.operations.length);

  const onGenerate = async () => {
    setPrompt(composed);
    setStep('preview');
    const layout = await requestLayout({
      prompt: composed,
      guestCount,
      budget: targetBudget
    });
    if (!layout) setStep('compose');
  };

  const onAccept = async () => {
    await acceptLayout();
    markIntentSeen();
    closeIntentModal();
  };

  const onSkip = () => {
    markIntentSeen();
    closeIntentModal();
  };

  const onAddIdea = () => {
    const text = ideaDraft.trim();
    if (!text) return;
    addIntentIdea(text);
    setIdeaDraft('');
  };

  const pushDraft = (next: {
    scenario?: ScenarioId;
    notes?: string;
    guests?: number;
    budget?: number;
  }) => {
    const sid = next.scenario ?? scenarioId;
    const n = next.notes ?? notes;
    const g = next.guests ?? guestCount;
    const b = next.budget ?? targetBudget;
    broadcastIntentDraft({
      scenario: sid,
      prompt: sid === 'custom' ? n : SCENARIO_CHIPS.find((c) => c.id === sid)?.prompt,
      guestCount: g,
      budget: b
    });
  };

  return (
    <div className="intent-backdrop" role="dialog" aria-modal="true" aria-labelledby="intent-title">
      <div className="intent-modal">
        <header className="intent-header">
          <div>
            <p className="eyebrow">Intent</p>
            <h2 id="intent-title">Plan this space</h2>
            <p className="intent-sub">
              {peerCount > 0
                ? `${peerCount} peer${peerCount === 1 ? '' : 's'} can add ideas.`
                : 'Pick a scenario, add notes, generate a layout.'}
            </p>
          </div>
          <button
            type="button"
            className="btn ghost compact"
            onClick={() => {
              if (isBusy) cancelLayoutRequest();
              onSkip();
            }}
          >
            Close
          </button>
        </header>

        {step === 'compose' && (
          <>
            <div className="intent-chips" role="listbox" aria-label="Scenario">
              {SCENARIO_CHIPS.map((chip) => (
                <button
                  key={chip.id}
                  type="button"
                  role="option"
                  aria-selected={scenarioId === chip.id}
                  className={`intent-chip ${scenarioId === chip.id ? 'is-active' : ''}`}
                  onClick={() => {
                    setScenarioId(chip.id);
                    pushDraft({ scenario: chip.id });
                  }}
                  disabled={isBusy}
                >
                  {chip.label}
                </button>
              ))}
            </div>

            <label className="field">
              <span>{scenarioId === 'custom' ? 'Describe the vibe' : 'Optional notes'}</span>
              <textarea
                rows={3}
                value={notes}
                placeholder={
                  scenarioId === 'custom'
                    ? 'e.g. cozy reading nook with soft lighting…'
                    : 'Add details friends agree on…'
                }
                onChange={(e) => {
                  setNotes(e.target.value);
                  pushDraft({ notes: e.target.value });
                }}
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
                  onChange={(e) => {
                    const v = Number(e.target.value) || 1;
                    setGuestCount(v);
                    pushDraft({ guests: v });
                  }}
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
                  onChange={(e) => {
                    const v = Number(e.target.value) || 0;
                    setTargetBudget(v);
                    pushDraft({ budget: v });
                  }}
                  disabled={isBusy}
                />
              </label>
            </div>

            <div className="intent-ideas">
              <p className="intent-ideas-label">Friend ideas</p>
              {intentIdeas.length === 0 ? (
                <p className="intent-empty">No suggestions yet — drop a short idea below.</p>
              ) : (
                <ul className="intent-idea-list">
                  {intentIdeas.map((idea) => (
                    <li key={idea.ideaId}>
                      <span className="intent-idea-who">
                        {idea.displayName || idea.actorId}
                        {idea.actorId === actorId ? ' (you)' : ''}
                      </span>
                      <span>{idea.text}</span>
                    </li>
                  ))}
                </ul>
              )}
              <div className="intent-idea-row">
                <input
                  type="text"
                  value={ideaDraft}
                  maxLength={280}
                  placeholder="Suggest: bean bags near the window…"
                  onChange={(e) => setIdeaDraft(e.target.value)}
                  onKeyDown={(e) => {
                    if (e.key === 'Enter') {
                      e.preventDefault();
                      onAddIdea();
                    }
                  }}
                  disabled={isBusy}
                />
                <button
                  type="button"
                  className="btn compact"
                  onClick={onAddIdea}
                  disabled={isBusy || !ideaDraft.trim()}
                >
                  Add
                </button>
              </div>
            </div>

            <div className="btn-row intent-actions">
              {isBusy ? (
                <button
                  type="button"
                  className="btn ghost"
                  onClick={cancelLayoutRequest}
                >
                  Cancel
                </button>
              ) : null}
              <button
                type="button"
                className="btn primary"
                onClick={() => void onGenerate()}
                disabled={!canGenerate}
              >
                {isBusy ? 'Planning…' : 'Generate layout'}
              </button>
            </div>
          </>
        )}

        {step === 'preview' && (
          <div className="intent-preview">
            {!pendingLayout && isBusy && (
              <div className="intent-loading">
                <p className="ai-reasoning">Asking the hybrid planner…</p>
                <button
                  type="button"
                  className="btn ghost compact"
                  onClick={cancelLayoutRequest}
                >
                  Cancel
                </button>
              </div>
            )}
            {pendingLayout && (
              <>
                <p className="ai-scenario">
                  Scenario: <strong>{pendingLayout.scenario}</strong>
                  {pendingLayout.plannerMode ? (
                    <>
                      {' '}
                      · mode <strong>{pendingLayout.plannerMode}</strong>
                    </>
                  ) : null}
                </p>
                <p className="ai-reasoning">{pendingLayout.reasoningSummary}</p>
                {(pendingLayout.valuePicks?.length ?? 0) > 0 && (
                  <ul className="value-pick-list">
                    {pendingLayout.valuePicks!.map((vp) => (
                      <li key={`${vp.objectId ?? ''}-${vp.productId}`}>
                        <span className="value-badge">Best value pick</span>{' '}
                        {vp.name ?? vp.productId}
                        {vp.rating != null ? ` · ★${vp.rating.toFixed(1)}` : ''}
                        {vp.price != null ? ` · $${vp.price.toFixed(0)}` : ''}
                      </li>
                    ))}
                  </ul>
                )}
                <ul className="op-list">
                  {pendingLayout.operations.map((op, i) => {
                    const isBest = (pendingLayout.valuePicks ?? []).some(
                      (vp) => vp.productId === op.productId
                    );
                    return (
                      <li key={`${op.type}-${op.objectId ?? i}`}>
                        <code>{op.type}</code>
                        {op.objectId ? ` · ${op.objectId}` : ''}
                        {op.productId ? ` · ${op.productId}` : ''}
                        {isBest ? (
                          <span className="value-badge inline">Best value pick</span>
                        ) : null}
                      </li>
                    );
                  })}
                </ul>
                {!canAccept && (
                  <p className="warn-text">No valid ops left after validation — Accept disabled.</p>
                )}
                {(pendingLayout.warnings?.length ?? 0) > 0 && (
                  <ul className="warn-list">
                    {pendingLayout.warnings!.map((w) => (
                      <li key={w}>{w}</li>
                    ))}
                  </ul>
                )}
              </>
            )}
            <div className="btn-row">
              <button
                type="button"
                className="btn ghost"
                onClick={() => {
                  rejectLayout();
                  setStep('compose');
                }}
                disabled={isBusy}
              >
                Back
              </button>
              <button
                type="button"
                className="btn primary"
                onClick={() => void onAccept()}
                disabled={isBusy || !canAccept}
              >
                Accept into scene
              </button>
            </div>
          </div>
        )}

        <p className="intent-foot">
          Reopen anytime from the top bar or Plan tool.
        </p>
      </div>
    </div>
  );
}
