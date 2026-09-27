'use client';

import { useSceneStore } from '../lib/sceneStore';

export function CatalogPanel() {
  const { catalog, addCatalogItem, isBusy, productMap, scene, pendingLayout } =
    useSceneStore();

  const inScene = new Set(
    (scene?.objects || []).map((o) => o.productId).filter(Boolean) as string[]
  );

  const bestValueIds = new Set(
    (pendingLayout?.valuePicks ?? []).map((vp) => vp.productId)
  );
  const valueReasonById = new Map(
    (pendingLayout?.valuePicks ?? []).map((vp) => [vp.productId, vp.reason])
  );

  return (
    <section className="card panel-enter delay-1">
      <h2>Catalog</h2>
      <ul className="catalog-list">
        {catalog.map((item) => {
          const isBestValue = bestValueIds.has(item.productId);
          const url = item.productUrl || item.websiteUrl || null;
          return (
            <li
              key={item.productId}
              className={`catalog-item${isBestValue ? ' best-value' : ''}`}
            >
              <div>
                <strong>
                  {item.name}
                  {isBestValue ? (
                    <span
                      className="value-badge"
                      title={valueReasonById.get(item.productId) ?? 'Best value pick'}
                    >
                      Best value pick
                    </span>
                  ) : null}
                </strong>
                <p>
                  ${item.price.toFixed(0)}
                  {item.rating != null ? ` · ★${item.rating.toFixed(1)}` : ''}
                  {item.category ? ` · ${item.category}` : ''}
                  {inScene.has(item.productId) ? ' · in scene' : ''}
                </p>
              </div>
              <div className="shop-rec-actions">
                {url && item.purchasable !== false && !item.virtualOnly ? (
                  <a
                    className="btn compact ghost"
                    href={url}
                    target="_blank"
                    rel="noopener noreferrer"
                  >
                    Open website
                  </a>
                ) : null}
                <button
                  type="button"
                  className="btn compact"
                  disabled={isBusy || !productMap.has(item.productId)}
                  onClick={() => void addCatalogItem(item.productId)}
                >
                  Add
                </button>
              </div>
            </li>
          );
        })}
      </ul>
    </section>
  );
}
