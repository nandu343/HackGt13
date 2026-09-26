export type Vector3 = [number, number, number];
export type Quaternion = [number, number, number, number];

export interface Transform {
  position: Vector3;
  rotation: Quaternion;
  scale?: Vector3;
}

export interface SceneObject {
  id: string;
  type: string;
  source?: 'existing' | 'catalog';
  movable?: boolean;
  transform: Transform;
  dimensions?: {
    width?: number;
    height?: number;
    depth?: number;
  };
  productId?: string;
  assetId?: string;
}

export interface Scene {
  sceneId: string;
  roomId?: string;
  version: number;
  bounds: {
    width: number;
    length: number;
    height: number;
  };
  objects: SceneObject[];
}

export interface SceneOperation {
  type: 'MOVE_OBJECT' | 'ADD_OBJECT' | 'DELETE_OBJECT' | 'REPLACE_OBJECT' | 'ROTATE_OBJECT';
  objectId?: string;
  targetPosition?: Vector3;
  assetId?: string;
  productId?: string;
}
