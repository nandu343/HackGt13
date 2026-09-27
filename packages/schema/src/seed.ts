/** Canonical demo room — shared by API seed and web fallback. Y-up meters. */
export const demoScene = {
  sceneId: 'scene_party_001',
  roomId: 'room_001',
  version: 1,
  bounds: { width: 5.42, length: 6.31, height: 2.68 },
  objects: [
    {
      id: 'sofa_1',
      type: 'sofa',
      source: 'existing',
      movable: true,
      transform: {
        position: [1.2, 0.41, -1.4],
        rotation: [0, 0.707, 0, 0.707],
        scale: [1, 1, 1]
      },
      dimensions: { width: 2.1, height: 0.82, depth: 0.91 },
      productId: 'product_sofa_01',
      modelUrl: '/models/sofa.glb',
      assetId: 'asset_sofa_01'
    },
    {
      id: 'lamp_17',
      type: 'floor_lamp',
      source: 'catalog',
      movable: true,
      assetId: 'asset_lamp_12',
      productId: 'product_39',
      modelUrl: '/models/lampRoundFloor.glb',
      transform: {
        position: [-1.62, 0.86, 2.1],
        rotation: [0, 0, 0, 1],
        scale: [1, 1, 1]
      },
      dimensions: { width: 0.4, height: 1.72, depth: 0.4 }
    },
    {
      id: 'table_05',
      type: 'table',
      source: 'catalog',
      movable: true,
      productId: 'product_table_05',
      modelUrl: '/models/table.glb',
      assetId: 'asset_table_05',
      transform: {
        position: [1.5, 0.375, 0.2],
        rotation: [0, 0, 0, 1],
        scale: [1, 1, 1]
      },
      dimensions: { width: 1.4, height: 0.75, depth: 1.1 }
    },
    {
      id: 'wall_north',
      type: 'wall',
      source: 'existing',
      movable: false,
      transform: {
        position: [0, 1.34, -3.155],
        rotation: [0, 0, 0, 1],
        scale: [1, 1, 1]
      },
      dimensions: { width: 5.42, height: 2.68, depth: 0.12 }
    }
  ],
  budgetUsed: 1277,
  currency: 'USD'
};

/** ~18 curated items — purchasable vs virtualOnly for commerce sandbox. */
const demoCatalogBase = [
  {
    productId: 'product_sofa_01',
    name: 'Lounge Sofa',
    price: 899,
    currency: 'USD',
    dimensions: { width: 2.1, height: 0.82, depth: 0.91 },
    assetId: 'asset_sofa_01',
    modelUrl: '/models/sofa.glb',
    tags: ['seating', 'living'],
    purchasable: true,
    virtualOnly: false,
    rating: 4.6,
    qualityTier: 'premium',
    category: 'seating'
  },
  {
    productId: 'chair_fold_01',
    name: 'Folding Chair',
    price: 35,
    currency: 'USD',
    dimensions: { width: 0.48, height: 0.86, depth: 0.52 },
    assetId: 'asset_chair_fold_01',
    modelUrl: '/models/loungeChair.glb',
    tags: ['seating', 'party'],
    purchasable: true,
    virtualOnly: false,
    rating: 3.2,
    qualityTier: 'budget',
    category: 'seating'
  },
  {
    productId: 'chair_dining_02',
    name: 'Dining Chair',
    price: 79,
    currency: 'USD',
    dimensions: { width: 0.46, height: 0.92, depth: 0.5 },
    assetId: 'asset_chair_dining_02',
    modelUrl: '/models/chairDesk.glb',
    tags: ['seating', 'dining'],
    purchasable: true,
    virtualOnly: false,
    rating: 4.3,
    qualityTier: 'standard',
    category: 'seating'
  },
  {
    productId: 'stool_bar_01',
    name: 'Bar Stool',
    price: 65,
    currency: 'USD',
    dimensions: { width: 0.4, height: 1.05, depth: 0.4 },
    assetId: 'asset_stool_bar_01',
    modelUrl: '/models/stool.glb',
    tags: ['seating', 'party'],
    purchasable: true,
    virtualOnly: false,
    rating: 4.4,
    qualityTier: 'standard',
    category: 'seating'
  },
  {
    productId: 'beanbag_01',
    name: 'Bean Bag',
    price: 55,
    currency: 'USD',
    dimensions: { width: 0.9, height: 0.7, depth: 0.9 },
    assetId: 'asset_beanbag_01',
    modelUrl: '/models/beanbag.glb',
    tags: ['seating', 'movie', 'party'],
    purchasable: true,
    virtualOnly: false,
    rating: 4.1,
    qualityTier: 'budget',
    category: 'seating'
  },
  {
    productId: 'product_table_05',
    name: 'Coffee Table',
    price: 249,
    currency: 'USD',
    dimensions: { width: 1.4, height: 0.75, depth: 1.1 },
    assetId: 'asset_table_05',
    modelUrl: '/models/table.glb',
    tags: ['table', 'living'],
    purchasable: true,
    virtualOnly: false,
    rating: 4.2,
    qualityTier: 'standard',
    category: 'tables'
  },
  {
    productId: 'desk_study_01',
    name: 'Study Desk',
    price: 189,
    currency: 'USD',
    dimensions: { width: 1.2, height: 0.75, depth: 0.6 },
    assetId: 'asset_desk_study_01',
    modelUrl: '/models/desk.glb',
    tags: ['desk', 'study', 'table'],
    purchasable: true,
    virtualOnly: false,
    rating: 4.5,
    qualityTier: 'standard',
    category: 'tables'
  },
  {
    productId: 'table_dining_01',
    name: 'Dining Table',
    price: 420,
    currency: 'USD',
    dimensions: { width: 1.8, height: 0.75, depth: 0.9 },
    assetId: 'asset_table_dining_01',
    modelUrl: '/models/sideTable.glb',
    tags: ['table', 'dining'],
    purchasable: true,
    virtualOnly: false,
    rating: 4.4,
    qualityTier: 'premium',
    category: 'tables'
  },
  {
    productId: 'product_39',
    name: 'Arc Floor Lamp',
    price: 129,
    currency: 'USD',
    dimensions: { width: 0.4, height: 1.72, depth: 0.4 },
    assetId: 'asset_lamp_12',
    modelUrl: '/models/lampRoundFloor.glb',
    tags: ['lighting'],
    purchasable: true,
    virtualOnly: false,
    rating: 4.0,
    qualityTier: 'standard',
    category: 'lighting'
  },
  {
    productId: 'party_lights_03',
    name: 'String Party Lights',
    price: 28,
    currency: 'USD',
    dimensions: { width: 3.0, height: 0.05, depth: 0.05 },
    assetId: 'asset_party_lights_03',
    modelUrl: '/models/string_lights.glb',
    tags: ['party', 'lighting'],
    purchasable: true,
    virtualOnly: false,
    rating: 4.5,
    qualityTier: 'budget',
    category: 'lighting'
  },
  {
    productId: 'lamp_desk_01',
    name: 'Task Desk Lamp',
    price: 42,
    currency: 'USD',
    dimensions: { width: 0.2, height: 0.45, depth: 0.2 },
    assetId: 'asset_lamp_desk_01',
    modelUrl: '/models/lampSquareTable.glb',
    tags: ['lighting', 'study'],
    purchasable: true,
    virtualOnly: false,
    rating: 4.4,
    qualityTier: 'standard',
    category: 'lighting'
  },
  {
    productId: 'pendant_dinner_01',
    name: 'Pendant Light',
    price: 95,
    currency: 'USD',
    dimensions: { width: 0.45, height: 0.35, depth: 0.45 },
    assetId: 'asset_pendant_dinner_01',
    modelUrl: '/models/pendant.glb',
    tags: ['lighting', 'dining'],
    purchasable: true,
    virtualOnly: false,
    rating: 4.3,
    qualityTier: 'standard',
    category: 'lighting'
  },
  {
    productId: 'backdrop_12',
    name: 'Photo Backdrop',
    price: 45,
    currency: 'USD',
    dimensions: { width: 2.0, height: 2.4, depth: 0.08 },
    assetId: 'asset_backdrop_12',
    modelUrl: '/models/backdrop.glb',
    tags: ['party', 'decor', 'movie'],
    purchasable: true,
    virtualOnly: false,
    rating: 4.2,
    qualityTier: 'budget',
    category: 'decor'
  },
  {
    productId: 'plant_tall_02',
    name: 'Tall Floor Plant',
    price: 62,
    currency: 'USD',
    dimensions: { width: 0.45, height: 1.4, depth: 0.45 },
    assetId: 'asset_plant_tall_02',
    modelUrl: '/models/pottedPlant.glb',
    tags: ['decor'],
    purchasable: true,
    virtualOnly: false,
    rating: 4.0,
    qualityTier: 'standard',
    category: 'decor'
  },
  {
    productId: 'rug_party_01',
    name: 'Dance Floor Rug',
    price: 89,
    currency: 'USD',
    dimensions: { width: 2.0, height: 0.02, depth: 2.0 },
    assetId: 'asset_rug_party_01',
    modelUrl: '/models/rugRectangle.glb',
    tags: ['party', 'floor'],
    purchasable: true,
    virtualOnly: false,
    rating: 4.1,
    qualityTier: 'standard',
    category: 'floor'
  },
  {
    productId: 'projector_screen_01',
    name: 'Projector Screen',
    price: 149,
    currency: 'USD',
    dimensions: { width: 2.4, height: 1.5, depth: 0.06 },
    assetId: 'asset_projector_screen_01',
    modelUrl: '/models/projector_screen.glb',
    tags: ['movie', 'decor'],
    purchasable: true,
    virtualOnly: false,
    rating: 4.5,
    qualityTier: 'standard',
    category: 'decor'
  },
  {
    productId: 'virtual_marker_01',
    name: 'Layout Marker',
    price: 0,
    currency: 'USD',
    dimensions: { width: 0.2, height: 0.05, depth: 0.2 },
    assetId: 'asset_virtual_marker_01',
    tags: ['virtual', 'helper'],
    purchasable: false,
    virtualOnly: true,
    rating: 0.0,
    qualityTier: 'budget',
    category: 'virtual'
  },
  {
    productId: 'virtual_glow_orb',
    name: 'Ambient Glow Orb',
    price: 0,
    currency: 'USD',
    dimensions: { width: 0.3, height: 0.3, depth: 0.3 },
    assetId: 'asset_virtual_glow_orb',
    tags: ['virtual', 'lighting', 'party'],
    purchasable: false,
    virtualOnly: true,
    rating: 0.0,
    qualityTier: 'budget',
    category: 'virtual'
  }
];

function retailerUrl(productId: string, name: string): string | undefined {
  if (productId.startsWith('virtual_')) return undefined;
  const slug = name.toLowerCase().replace(/ /g, '-');
  const ikeaIds = new Set([
    'desk_study_01',
    'table_dining_01',
    'plant_tall_02',
    'lamp_desk_01'
  ]);
  if (ikeaIds.has(productId)) {
    return `https://www.ikea.com/us/en/p/${slug}-${productId}/`;
  }
  return `https://www.amazon.com/s?k=${slug.replace(/-/g, '+')}`;
}

/** Curated demo catalog with retailer productUrl / websiteUrl for Shop. */
export const demoCatalog = demoCatalogBase.map((item) => {
  const productUrl = retailerUrl(item.productId, item.name);
  return productUrl
    ? { ...item, productUrl, websiteUrl: productUrl }
    : item;
});

