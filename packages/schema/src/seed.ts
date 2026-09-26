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
      productId: 'product_sofa_01'
    },
    {
      id: 'lamp_17',
      type: 'floor_lamp',
      source: 'catalog',
      movable: true,
      assetId: 'asset_lamp_12',
      productId: 'product_39',
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
export const demoCatalog = [
  {
    productId: 'product_sofa_01',
    name: 'Lounge Sofa',
    price: 899,
    currency: 'USD',
    dimensions: { width: 2.1, height: 0.82, depth: 0.91 },
    assetId: 'asset_sofa_01',
    tags: ['seating', 'living'],
    purchasable: true,
    virtualOnly: false,
    category: 'seating'
  },
  {
    productId: 'chair_fold_01',
    name: 'Folding Chair',
    price: 35,
    currency: 'USD',
    dimensions: { width: 0.48, height: 0.86, depth: 0.52 },
    assetId: 'asset_chair_fold_01',
    tags: ['seating', 'party'],
    purchasable: true,
    virtualOnly: false,
    category: 'seating'
  },
  {
    productId: 'chair_dining_02',
    name: 'Dining Chair',
    price: 79,
    currency: 'USD',
    dimensions: { width: 0.46, height: 0.92, depth: 0.5 },
    assetId: 'asset_chair_dining_02',
    tags: ['seating', 'dining'],
    purchasable: true,
    virtualOnly: false,
    category: 'seating'
  },
  {
    productId: 'stool_bar_01',
    name: 'Bar Stool',
    price: 65,
    currency: 'USD',
    dimensions: { width: 0.4, height: 1.05, depth: 0.4 },
    assetId: 'asset_stool_bar_01',
    tags: ['seating', 'party'],
    purchasable: true,
    virtualOnly: false,
    category: 'seating'
  },
  {
    productId: 'beanbag_01',
    name: 'Bean Bag',
    price: 55,
    currency: 'USD',
    dimensions: { width: 0.9, height: 0.7, depth: 0.9 },
    assetId: 'asset_beanbag_01',
    tags: ['seating', 'movie', 'party'],
    purchasable: true,
    virtualOnly: false,
    category: 'seating'
  },
  {
    productId: 'product_table_05',
    name: 'Coffee Table',
    price: 249,
    currency: 'USD',
    dimensions: { width: 1.4, height: 0.75, depth: 1.1 },
    assetId: 'asset_table_05',
    tags: ['table', 'living'],
    purchasable: true,
    virtualOnly: false,
    category: 'tables'
  },
  {
    productId: 'desk_study_01',
    name: 'Study Desk',
    price: 189,
    currency: 'USD',
    dimensions: { width: 1.2, height: 0.75, depth: 0.6 },
    assetId: 'asset_desk_study_01',
    tags: ['desk', 'study', 'table'],
    purchasable: true,
    virtualOnly: false,
    category: 'tables'
  },
  {
    productId: 'table_dining_01',
    name: 'Dining Table',
    price: 420,
    currency: 'USD',
    dimensions: { width: 1.8, height: 0.75, depth: 0.9 },
    assetId: 'asset_table_dining_01',
    tags: ['table', 'dining'],
    purchasable: true,
    virtualOnly: false,
    category: 'tables'
  },
  {
    productId: 'product_39',
    name: 'Arc Floor Lamp',
    price: 129,
    currency: 'USD',
    dimensions: { width: 0.4, height: 1.72, depth: 0.4 },
    assetId: 'asset_lamp_12',
    tags: ['lighting'],
    purchasable: true,
    virtualOnly: false,
    category: 'lighting'
  },
  {
    productId: 'party_lights_03',
    name: 'String Party Lights',
    price: 28,
    currency: 'USD',
    dimensions: { width: 3.0, height: 0.05, depth: 0.05 },
    assetId: 'asset_party_lights_03',
    tags: ['party', 'lighting'],
    purchasable: true,
    virtualOnly: false,
    category: 'lighting'
  },
  {
    productId: 'lamp_desk_01',
    name: 'Task Desk Lamp',
    price: 42,
    currency: 'USD',
    dimensions: { width: 0.2, height: 0.45, depth: 0.2 },
    assetId: 'asset_lamp_desk_01',
    tags: ['lighting', 'study'],
    purchasable: true,
    virtualOnly: false,
    category: 'lighting'
  },
  {
    productId: 'pendant_dinner_01',
    name: 'Pendant Light',
    price: 95,
    currency: 'USD',
    dimensions: { width: 0.45, height: 0.35, depth: 0.45 },
    assetId: 'asset_pendant_dinner_01',
    tags: ['lighting', 'dining'],
    purchasable: true,
    virtualOnly: false,
    category: 'lighting'
  },
  {
    productId: 'backdrop_12',
    name: 'Photo Backdrop',
    price: 45,
    currency: 'USD',
    dimensions: { width: 2.0, height: 2.4, depth: 0.08 },
    assetId: 'asset_backdrop_12',
    tags: ['party', 'decor', 'movie'],
    purchasable: true,
    virtualOnly: false,
    category: 'decor'
  },
  {
    productId: 'plant_tall_02',
    name: 'Tall Floor Plant',
    price: 62,
    currency: 'USD',
    dimensions: { width: 0.45, height: 1.4, depth: 0.45 },
    assetId: 'asset_plant_tall_02',
    tags: ['decor'],
    purchasable: true,
    virtualOnly: false,
    category: 'decor'
  },
  {
    productId: 'rug_party_01',
    name: 'Dance Floor Rug',
    price: 89,
    currency: 'USD',
    dimensions: { width: 2.0, height: 0.02, depth: 2.0 },
    assetId: 'asset_rug_party_01',
    tags: ['party', 'floor'],
    purchasable: true,
    virtualOnly: false,
    category: 'floor'
  },
  {
    productId: 'projector_screen_01',
    name: 'Projector Screen',
    price: 149,
    currency: 'USD',
    dimensions: { width: 2.4, height: 1.5, depth: 0.06 },
    assetId: 'asset_projector_screen_01',
    tags: ['movie', 'decor'],
    purchasable: true,
    virtualOnly: false,
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
    category: 'virtual'
  }
];
