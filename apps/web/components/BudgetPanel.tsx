'use client';

import { useSceneStore } from '../lib/sceneStore';

export function BudgetPanel() {
  const { budgetUsed, targetBudget, scene, productMap, checkout, isBusy } = useSceneStore();
  const over = budgetUsed > targetBudget;
  const currency = scene?.currency || 'USD';

  const lines = (scene?.objects || [])
    .filter((o) => o.productId && productMap.has(o.productId))
    .map((o) => {
      const p = productMap.get(o.productId!)!;
      return {
        id: o.id,
        name: p.name,
        price: p.price,
        purchasable: p.purchasable !== false && !p.virtualOnly
      };
    });

  const purchasableCount = lines.filter((l) => l.purchasable).length;

  return (
    <section className="card panel-enter delay-2">
      <h2>Budget</h2>
      <div className="budget-row">
        <span>Current</span>
        <strong className={over ? 'over' : ''}>
          ${budgetUsed.toFixed(0)}
        </strong>
      </div>
      <div className="budget-row target">
        <span>Target</span>
        <strong>${targetBudget.toFixed(0)}</strong>
      </div>
      <p className="budget-meta">
        {currency} · {lines.length} priced object{lines.length === 1 ? '' : 's'}
        {over ? ' · over budget' : ''}
      </p>
      {lines.length > 0 && (
        <ul className="budget-lines">
          {lines.map((l) => (
            <li key={l.id}>
              <span>
                {l.name}
                {!l.purchasable ? ' (virtual)' : ''}
              </span>
              <span>${l.price.toFixed(0)}</span>
            </li>
          ))}
        </ul>
      )}
      <button
        type="button"
        className="btn primary"
        style={{ marginTop: 12, width: '100%' }}
        disabled={isBusy || purchasableCount === 0}
        onClick={() => void checkout()}
      >
        Checkout
      </button>
    </section>
  );
}
