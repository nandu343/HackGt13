'use client';

import { useSceneStore } from '../lib/sceneStore';

function productWebsiteUrl(item: {
  productUrl?: string | null;
  websiteUrl?: string | null;
}): string | null {
  const raw = item.productUrl || item.websiteUrl || null;
  return raw && /^https?:\/\//i.test(raw) ? raw : null;
}

/**
 * Shop drawer: AI value picks + ADD_OBJECT productIds with Open website links.
 * Survives Accept via recommendedProductIds in the scene store.
 */
export function ShopRecommendations() {
  const {
    catalog,
    productMap,
    pendingLayout,
    recommendedProductIds,
    isBusy,
    addCatalogItem
  } = useSceneStore();

  const reasonById = new Map(
    (pendingLayout?.valuePicks ?? []).map((vp) => [vp.productId, vp.reason])
  );

  const ids =
    recommendedProductIds.length > 0
      ? recommendedProductIds
      : (pendingLayout?.valuePicks ?? []).map((vp) => vp.productId);

  const uniqueIds = [...new Set(ids)];

  const rows = uniqueIds
    .map((id) => {
      const item = productMap.get(id) ?? catalog.find((c) => c.productId === id);
      if (!item) return null;
      if (item.purchasable === false || item.virtualOnly) return null;
      return item;
    })
    .filter(Boolean) as typeof catalog;

  return (
    <section className="card panel-enter">
      <h2>Recommendations</h2>
      {rows.length === 0 ? (
        <p className="panel-hint">
          Generate a layout in Plan — best-value picks and catalog adds show up here with
          store links.
        </p>
      ) : (
        <ul className="catalog-list shop-recs">
          {rows.map((item) => {
            const url = productWebsiteUrl(item);
            const reason = reasonById.get(item.productId);
            return (
              <li key={item.productId} className="catalog-item best-value">
                <div>
                  <strong>
                    {item.name}
                    <span className="value-badge">Recommended</span>
                  </strong>
                  <p>
                    ${item.price.toFixed(0)}
                    {item.rating != null ? ` · ★${item.rating.toFixed(1)}` : ''}
                    {item.category ? ` · ${item.category}` : ''}
                  </p>
                  {reason ? <p className="value-reason">{reason}</p> : null}
                </div>
                <div className="shop-rec-actions">
                  {url ? (
                    <a
                      className="btn compact primary"
                      href={url}
                      target="_blank"
                      rel="noopener noreferrer"
                    >
                      Open website
                    </a>
                  ) : (
                    <span className="panel-hint">No link</span>
                  )}
                  <button
                    type="button"
                    className="btn compact ghost"
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
      )}
    </section>
  );
}
