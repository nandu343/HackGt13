'use client';

import { useSceneStore } from '../lib/sceneStore';

export function CatalogPanel() {
  const { catalog, addCatalogItem, isBusy, productMap, scene } = useSceneStore();

  const inScene = new Set(
    (scene?.objects || []).map((o) => o.productId).filter(Boolean) as string[]
  );

  return (
    <section className="card panel-enter delay-1">
      <h2>Catalog</h2>
      <ul className="catalog-list">
        {catalog.map((item) => (
          <li key={item.productId} className="catalog-item">
            <div>
              <strong>{item.name}</strong>
              <p>
                ${item.price.toFixed(0)}
                {item.category ? ` · ${item.category}` : ''}
                {inScene.has(item.productId) ? ' · in scene' : ''}
              </p>
            </div>
            <button
              type="button"
              className="btn compact"
              disabled={isBusy || !productMap.has(item.productId)}
              onClick={() => void addCatalogItem(item.productId)}
            >
              Add
            </button>
          </li>
        ))}
      </ul>
    </section>
  );
}
