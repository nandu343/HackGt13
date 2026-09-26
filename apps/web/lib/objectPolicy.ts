import type { SceneObject } from '@shared-spatial-ai/schema';

/** Structure stays fixed; scan furniture can be cleared for planning. */
const STRUCTURE_TYPES = new Set([
  'wall',
  'door',
  'window',
  'floor',
  'ceiling',
  'opening'
]);

/** True for walls / openings — not clickable for move/remove. */
export function isStructureObject(obj: SceneObject): boolean {
  return STRUCTURE_TYPES.has(obj.type);
}

/**
 * Furniture (including RoomPlan `source: existing`) can be moved or removed.
 * Walls stay protected even when movable=false.
 */
export function canManipulateObject(obj: SceneObject): boolean {
  if (isStructureObject(obj)) return false;
  if (obj.source === 'existing') return true;
  return obj.movable !== false;
}

export function objectLabel(obj: SceneObject): string {
  const source =
    obj.source === 'existing'
      ? 'in room'
      : obj.source === 'catalog'
        ? 'catalog'
        : '';
  const base = obj.type.replace(/_/g, ' ');
  return source ? `${base} · ${source}` : base;
}
