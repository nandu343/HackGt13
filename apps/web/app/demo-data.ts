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
        position: [1.2, 0.35, -1.4],
        rotation: [0, 0.707, 0, 0.707],
        scale: [1, 1, 1]
      },
      dimensions: { width: 2.1, height: 0.82, depth: 0.91 }
    },
    {
      id: 'lamp_17',
      type: 'floor_lamp',
      source: 'catalog',
      assetId: 'asset_lamp_12',
      productId: 'product_39',
      transform: {
        position: [-1.62, 0, 2.1],
        rotation: [0, 0, 0, 1],
        scale: [1, 1, 1]
      }
    },
    {
      id: 'table_05',
      type: 'table',
      source: 'catalog',
      transform: {
        position: [1.5, 0.4, 0.2],
        rotation: [0, 0, 0, 1],
        scale: [1, 1, 1]
      },
      dimensions: { width: 1.4, height: 0.75, depth: 1.1 }
    }
  ]
};
