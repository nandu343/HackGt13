'use client';

import { useEffect, useRef, useState } from 'react';
import { TransformControls } from '@react-three/drei';
import { useThree } from '@react-three/fiber';
import type { SceneObject, Vector3 } from '@shared-spatial-ai/schema';
import type { Group } from 'three';
import { canManipulateObject } from '../lib/objectPolicy';

type Props = {
  object: SceneObject;
  selected: boolean;
  onSelect: (id: string) => void;
  onMoveEnd: (id: string, position: Vector3) => void;
  onRotateEnd: (id: string, rotation: [number, number, number, number]) => void;
  setDragging: (v: boolean) => void;
  disabled?: boolean;
  /** Camera AR: slightly translucent floating proxy over the live feed. */
  arOverlay?: boolean;
};

const TYPE_COLORS: Record<string, string> = {
  sofa: '#c4a484',
  table: '#8b5a3c',
  floor_lamp: '#e8c547',
  lamp: '#e8c547',
  plant: '#3d8b6e',
  wall: '#ebe4d8',
  backdrop: '#f0e6f6',
  string_lights: '#ffe08a',
  chair: '#9a7b5a',
  rug: '#6b8f71'
};

function materialFor(type: string, selected: boolean, isExisting: boolean) {
  const color = TYPE_COLORS[type] || '#7a90a4';
  return {
    color,
    roughness: type === 'string_lights' ? 0.35 : 0.55,
    metalness: type === 'floor_lamp' || type === 'lamp' ? 0.45 : 0.08,
    emissive: selected
      ? isExisting
        ? '#3a2a12'
        : '#1a3a4a'
      : type.includes('light')
        ? '#4a3a10'
        : '#000000',
    emissiveIntensity: selected ? 0.42 : type.includes('light') ? 0.25 : 0
  };
}

export function ObjectGizmo({
  object,
  selected,
  onSelect,
  onMoveEnd,
  onRotateEnd,
  setDragging,
  disabled,
  arOverlay = false
}: Props) {
  const [group, setGroup] = useState<Group | null>(null);
  const { gl } = useThree();
  const startPos = useRef<Vector3 | null>(null);
  const startRot = useRef<[number, number, number, number] | null>(null);

  const [px, py, pz] = object.transform.position;
  const [rx, ry, rz, rw] = object.transform.rotation;

  useEffect(() => {
    if (!group) return;
    group.position.set(px, py, pz);
    group.quaternion.set(rx, ry, rz, rw);
  }, [group, px, py, pz, rx, ry, rz, rw]);

  const dims = object.dimensions;
  const w = dims?.width ?? 0.6;
  const h = dims?.height ?? 0.6;
  const d = dims?.depth ?? 0.6;
  const isExisting = object.source === 'existing';
  const mat = materialFor(object.type, selected, isExisting);
  const isWall = object.type === 'wall';
  const isLights = object.type === 'string_lights' || object.type.includes('light');
  const isRug = object.type === 'rug' || (h < 0.05 && w > 1);
  const manipulable = canManipulateObject(object) && !disabled;

  return (
    <>
      <group
        ref={(node) => {
          if (node !== group) setGroup(node);
        }}
      >
        <mesh
          castShadow={!isWall && !isRug}
          receiveShadow={isRug || isWall}
          onClick={(e) => {
            e.stopPropagation();
            if (!canManipulateObject(object)) return;
            onSelect(object.id);
          }}
          onPointerOver={(e) => {
            if (!manipulable) return;
            e.stopPropagation();
            gl.domElement.style.cursor = 'pointer';
          }}
          onPointerOut={() => {
            if (gl.domElement.style.cursor === 'pointer') {
              gl.domElement.style.cursor = 'auto';
            }
          }}
        >
          {isLights ? (
            <cylinderGeometry args={[0.04, 0.04, Math.max(w, 1.2), 12]} />
          ) : (
            <boxGeometry args={[w, Math.max(h, 0.02), d]} />
          )}
          <meshStandardMaterial
            color={mat.color}
            roughness={mat.roughness}
            metalness={mat.metalness}
            emissive={mat.emissive}
            emissiveIntensity={
              arOverlay && !isWall
                ? Math.max(mat.emissiveIntensity, 0.18)
                : mat.emissiveIntensity
            }
            transparent={isWall || arOverlay}
            opacity={isWall ? 0.35 : arOverlay ? 0.88 : 1}
            depthWrite={!arOverlay || isWall}
          />
        </mesh>
        {selected && manipulable && (
          <mesh position={[0, h / 2 + 0.1, 0]}>
            <sphereGeometry args={[0.07, 14, 14]} />
            <meshBasicMaterial color={isExisting ? '#e2b45c' : '#5ec8ff'} />
          </mesh>
        )}
        {selected && manipulable && (
          <mesh position={[0, 0.02, 0]} rotation={[-Math.PI / 2, 0, 0]}>
            <ringGeometry args={[Math.max(w, d) * 0.42, Math.max(w, d) * 0.52, 48]} />
            <meshBasicMaterial
              color={isExisting ? '#e2b45c' : '#5ec8ff'}
              transparent
              opacity={0.55}
              depthWrite={false}
            />
          </mesh>
        )}
      </group>
      {selected && manipulable && group && (
        <TransformControls
          object={group}
          mode="translate"
          showX
          showY={false}
          showZ
          size={0.85}
          onMouseDown={() => {
            setDragging(true);
            startPos.current = [group.position.x, group.position.y, group.position.z];
            const q = group.quaternion;
            startRot.current = [q.x, q.y, q.z, q.w];
            gl.domElement.style.cursor = 'grabbing';
          }}
          onMouseUp={() => {
            setDragging(false);
            gl.domElement.style.cursor = 'auto';
            const pos: Vector3 = [group.position.x, py, group.position.z];
            group.position.y = pos[1];
            const q = group.quaternion;
            const rot: [number, number, number, number] = [q.x, q.y, q.z, q.w];

            const moved =
              !startPos.current ||
              Math.hypot(pos[0] - startPos.current[0], pos[2] - startPos.current[2]) > 0.01;
            const rotated =
              !!startRot.current &&
              startRot.current.some((v, i) => Math.abs(v - rot[i]) > 0.002);

            if (moved) onMoveEnd(object.id, pos);
            else if (rotated) onRotateEnd(object.id, rot);
          }}
        />
      )}
    </>
  );
}
