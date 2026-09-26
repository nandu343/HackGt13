'use client';

import { useMemo } from 'react';
import { useSceneStore } from '../lib/sceneStore';

function posKey(p: number[]): string {
  return p.map((n) => n.toFixed(2)).join(',');
}

export function DisagreementPanel() {
  const {
    disagreement,
    disagreementView,
    setDisagreementView,
    compromisePicks,
    setCompromisePick,
    compromiseDisagreement,
    cancelDisagreement,
    pendingLayout,
    proposeDisagreement,
    isBusy
  } = useSceneStore();

  const conflicts = useMemo(() => {
    if (!disagreement?.proposalA.scene || !disagreement.proposalB?.scene) return [];
    const base = new Map(disagreement.baseScene.objects.map((o) => [o.id, o]));
    const a = new Map(disagreement.proposalA.scene.objects.map((o) => [o.id, o]));
    const b = new Map(disagreement.proposalB.scene.objects.map((o) => [o.id, o]));
    const ids = new Set([...base.keys(), ...a.keys(), ...b.keys()]);
    const out: { id: string; type: string }[] = [];
    for (const id of ids) {
      const bo = base.get(id);
      const ao = a.get(id);
      const bobj = b.get(id);
      const aChanged =
        (!bo && !!ao) ||
        (!!bo && !ao) ||
        (!!bo &&
          !!ao &&
          (posKey(bo.transform.position) !== posKey(ao.transform.position) ||
            posKey(bo.transform.rotation) !== posKey(ao.transform.rotation)));
      const bChanged =
        (!bo && !!bobj) ||
        (!!bo && !bobj) ||
        (!!bo &&
          !!bobj &&
          (posKey(bo.transform.position) !== posKey(bobj.transform.position) ||
            posKey(bo.transform.rotation) !== posKey(bobj.transform.rotation)));
      if (aChanged && bChanged) {
        out.push({ id, type: ao?.type || bobj?.type || bo?.type || id });
      }
    }
    return out;
  }, [disagreement]);

  if (!disagreement) {
    return (
      <section className="card panel-enter delay-2">
        <div className="panel-title-row">
          <h2>Disagreement</h2>
        </div>
        <p className="panel-hint">
          Two tabs: Tab A generates AI → <strong>Propose</strong>. Tab B generates an alternate →{' '}
          <strong>Counter</strong>. Compare ghosts, then blend or pick.
        </p>
        {pendingLayout?.operations.length ? (
          <button
            type="button"
            className="btn primary"
            disabled={isBusy}
            onClick={() => void proposeDisagreement()}
          >
            Propose current AI layout
          </button>
        ) : (
          <p className="empty-hint">Generate a layout in AI panel first.</p>
        )}
      </section>
    );
  }

  const aLabel =
    disagreement.proposalA.label ||
    disagreement.proposalA.displayName ||
    disagreement.proposalA.actorId;
  const bLabel = disagreement.proposalB
    ? disagreement.proposalB.label ||
      disagreement.proposalB.displayName ||
      disagreement.proposalB.actorId
    : null;

  return (
    <section className="card panel-enter delay-2 disagreement-card">
      <div className="panel-title-row">
        <h2>Disagreement</h2>
        <span className={`status-chip ${disagreement.status}`}>{disagreement.status}</span>
      </div>
      <div className="proposal-rows">
        <div className="proposal-chip tint-a">
          <span>A</span>
          <p>{aLabel}</p>
          <small>{disagreement.proposalA.operations.length} ops</small>
        </div>
        <div className={`proposal-chip tint-b ${bLabel ? '' : 'is-empty'}`}>
          <span>B</span>
          <p>{bLabel || 'Waiting for counter…'}</p>
          <small>
            {disagreement.proposalB
              ? `${disagreement.proposalB.operations.length} ops`
              : 'open 2nd tab'}
          </small>
        </div>
      </div>

      <div className="view-toggle">
        {(['both', 'A', 'B', 'live'] as const).map((v) => (
          <button
            key={v}
            type="button"
            className={`intent-chip ${disagreementView === v ? 'is-active' : ''}`}
            onClick={() => setDisagreementView(v)}
          >
            {v === 'both' ? 'Both ghosts' : v === 'live' ? 'Live only' : `Show ${v}`}
          </button>
        ))}
      </div>

      {!disagreement.proposalB && pendingLayout?.operations.length ? (
        <button
          type="button"
          className="btn primary"
          disabled={isBusy}
          onClick={() => void proposeDisagreement()}
        >
          Submit as proposal B
        </button>
      ) : null}

      {disagreement.proposalB && (
        <>
          {conflicts.length > 0 && (
            <div className="conflict-list">
              <p className="intent-ideas-label">Conflicts — pick A or B</p>
              <ul>
                {conflicts.map((c) => (
                  <li key={c.id}>
                    <span>
                      {c.type} <code>{c.id}</code>
                    </span>
                    <div className="pick-toggle">
                      <button
                        type="button"
                        className={`pick-btn ${compromisePicks[c.id] === 'A' || !compromisePicks[c.id] ? 'is-a' : ''}`}
                        onClick={() => setCompromisePick(c.id, 'A')}
                      >
                        A
                      </button>
                      <button
                        type="button"
                        className={`pick-btn ${compromisePicks[c.id] === 'B' ? 'is-b' : ''}`}
                        onClick={() => setCompromisePick(c.id, 'B')}
                      >
                        B
                      </button>
                    </div>
                  </li>
                ))}
              </ul>
            </div>
          )}
          <div className="btn-row">
            <button
              type="button"
              className="btn primary"
              disabled={isBusy}
              onClick={() => void compromiseDisagreement('blend')}
            >
              Blend
            </button>
            <button
              type="button"
              className="btn ghost"
              disabled={isBusy}
              onClick={() => void compromiseDisagreement('picks')}
            >
              Apply picks
            </button>
          </div>
          <div className="btn-row">
            <button
              type="button"
              className="btn ghost compact"
              disabled={isBusy}
              onClick={() => void compromiseDisagreement('a')}
            >
              Take A
            </button>
            <button
              type="button"
              className="btn ghost compact"
              disabled={isBusy}
              onClick={() => void compromiseDisagreement('b')}
            >
              Take B
            </button>
          </div>
        </>
      )}

      <button
        type="button"
        className="btn ghost compact danger-link"
        disabled={isBusy}
        onClick={() => void cancelDisagreement()}
      >
        Cancel disagreement
      </button>
    </section>
  );
}
