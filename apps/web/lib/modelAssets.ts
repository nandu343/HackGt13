/** Catalog assetId / productId → GLB under apps/web/public/models (CC0 Kenney + local meshes). */

export const ASSET_MODEL_URL: Record<string, string> = {
  asset_sofa_01: '/models/sofa.glb',
  asset_chair_fold_01: '/models/loungeChair.glb',
  asset_chair_dining_02: '/models/chairDesk.glb',
  asset_stool_bar_01: '/models/stool.glb',
  asset_beanbag_01: '/models/beanbag.glb',
  asset_table_05: '/models/table.glb',
  asset_desk_study_01: '/models/desk.glb',
  asset_table_dining_01: '/models/sideTable.glb',
  asset_lamp_12: '/models/lampRoundFloor.glb',
  asset_party_lights_03: '/models/string_lights.glb',
  asset_lamp_desk_01: '/models/lampSquareTable.glb',
  asset_pendant_dinner_01: '/models/pendant.glb',
  asset_backdrop_12: '/models/backdrop.glb',
  asset_plant_tall_02: '/models/pottedPlant.glb',
  asset_rug_party_01: '/models/rugRectangle.glb',
  asset_projector_screen_01: '/models/projector_screen.glb'
};

export const PRODUCT_MODEL_URL: Record<string, string> = {
  product_sofa_01: '/models/sofa.glb',
  chair_fold_01: '/models/loungeChair.glb',
  chair_dining_02: '/models/chairDesk.glb',
  stool_bar_01: '/models/stool.glb',
  beanbag_01: '/models/beanbag.glb',
  product_table_05: '/models/table.glb',
  desk_study_01: '/models/desk.glb',
  table_dining_01: '/models/sideTable.glb',
  product_39: '/models/lampRoundFloor.glb',
  party_lights_03: '/models/string_lights.glb',
  lamp_desk_01: '/models/lampSquareTable.glb',
  pendant_dinner_01: '/models/pendant.glb',
  backdrop_12: '/models/backdrop.glb',
  plant_tall_02: '/models/pottedPlant.glb',
  rug_party_01: '/models/rugRectangle.glb',
  projector_screen_01: '/models/projector_screen.glb'
};

/** All known model URLs for useGLTF.preload. */
export const ALL_MODEL_URLS = [
  ...new Set([...Object.values(ASSET_MODEL_URL), ...Object.values(PRODUCT_MODEL_URL)])
];

type ModelRef = {
  modelUrl?: string | null;
  assetId?: string | null;
  productId?: string | null;
  type?: string;
};

/** Resolve a GLB path for a scene/catalog object; null → box fallback. */
export function resolveModelUrl(obj: ModelRef): string | null {
  if (obj.modelUrl && obj.modelUrl.length > 0) return obj.modelUrl;
  if (obj.assetId && ASSET_MODEL_URL[obj.assetId]) return ASSET_MODEL_URL[obj.assetId];
  if (obj.productId && PRODUCT_MODEL_URL[obj.productId]) {
    return PRODUCT_MODEL_URL[obj.productId];
  }
  const t = (obj.type || '').toLowerCase();
  if (!t || t === 'wall' || t === 'object') return null;
  if (t.includes('sofa') || t.includes('couch')) return '/models/sofa.glb';
  if (t.includes('bean')) return '/models/beanbag.glb';
  if (t.includes('stool')) return '/models/stool.glb';
  if (t.includes('dining') && t.includes('chair')) return '/models/chairDesk.glb';
  if (t.includes('chair')) return '/models/loungeChair.glb';
  if (t.includes('desk')) return '/models/desk.glb';
  if (t.includes('dining') && t.includes('table')) return '/models/sideTable.glb';
  if (t.includes('table') || t.includes('coffee')) return '/models/table.glb';
  if (t.includes('pendant')) return '/models/pendant.glb';
  if (t.includes('desk_lamp') || t.includes('task')) return '/models/lampSquareTable.glb';
  if (t.includes('string') || t.includes('party_light')) return '/models/string_lights.glb';
  if (t.includes('floor_lamp') || t === 'lamp' || t.includes('floor lamp')) {
    return '/models/lampRoundFloor.glb';
  }
  if (t.includes('lamp')) return '/models/lampRoundFloor.glb';
  if (t.includes('plant')) return '/models/pottedPlant.glb';
  if (t.includes('rug')) return '/models/rugRectangle.glb';
  if (t.includes('backdrop') || t.includes('photo')) return '/models/backdrop.glb';
  if (t.includes('screen') || t.includes('projector')) return '/models/projector_screen.glb';
  if (t.includes('book') || t.includes('shelf')) return '/models/bookcaseClosed.glb';
  return null;
}
