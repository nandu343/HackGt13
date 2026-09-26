import type { Scene, SceneObject, Vector3 } from '@shared-spatial-ai/schema';

export function lerp(a: number, b: number, t: number): number {
  return a + (b - a) * t;
}

export function lerpVec3(a: Vector3, b: Vector3, t: number): Vector3 {
  return [lerp(a[0], b[0], t), lerp(a[1], b[1], t), lerp(a[2], b[2], t)];
}

export function easeOutCubic(t: number): number {
  return 1 - Math.pow(1 - t, 3);
}

/** Blend object positions/rotations from `from` toward `to` for animation frames. */
export function blendScenes(from: Scene, to: Scene, t: number): Scene {
  const eased = easeOutCubic(Math.min(1, Math.max(0, t)));
  const fromMap = new Map(from.objects.map((o) => [o.id, o]));
  const objects: SceneObject[] = to.objects.map((target) => {
    const prev = fromMap.get(target.id);
    if (!prev) return target;
    return {
      ...target,
      transform: {
        ...target.transform,
        position: lerpVec3(
          prev.transform.position as Vector3,
          target.transform.position as Vector3,
          eased
        ),
        rotation: [
          lerp(prev.transform.rotation[0], target.transform.rotation[0], eased),
          lerp(prev.transform.rotation[1], target.transform.rotation[1], eased),
          lerp(prev.transform.rotation[2], target.transform.rotation[2], eased),
          lerp(prev.transform.rotation[3], target.transform.rotation[3], eased)
        ]
      }
    };
  });
  return { ...to, objects };
}
