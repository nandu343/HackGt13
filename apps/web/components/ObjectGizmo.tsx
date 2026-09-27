'use client';

import { Suspense, useEffect, useLayoutEffect, useRef, useState } from 'react';
import { Clone, TransformControls, useGLTF } from '@react-three/drei';
import { useThree, type ThreeEvent } from '@react-three/fiber';
import type { SceneObject, Vector3 } from '@shared-spatial-ai/schema';
import * as THREE from 'three';
import type { Group } from 'three';
import { canManipulateObject } from '../lib/objectPolicy';
import { ALL_MODEL_URLS, resolveModelUrl } from '../lib/modelAssets';

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
  /**
   * Tap/select then drag on a ground-parallel plane (object Y).
   * Preferred in Camera AR where TransformControls feel broken on touch.
   */
  floorDrag?: boolean;
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

function materialFor(
  type: string,
  selected: boolean,
  isExisting: boolean,
  dragging = false
) {
  const color = TYPE_COLORS[type] || '#7a90a4';
  return {
    color,
    roughness: type === 'string_lights' ? 0.35 : 0.55,
    metalness: type === 'floor_lamp' || type === 'lamp' ? 0.45 : 0.08,
    emissive: selected
      ? isExisting
        ? dragging
          ? '#6a4a18'
          : '#3a2a12'
        : dragging
          ? '#2a5a6a'
          : '#1a3a4a'
      : type.includes('light')
        ? '#4a3a10'
        : '#000000',
    emissiveIntensity: dragging
      ? 0.85
      : selected
        ? 0.42
        : type.includes('light')
          ? 0.25
          : 0
  };
}

/** GLB mesh scaled to catalog dimensions; last-resort box is BoxFallback. */
function GltfFurniture({
  url,
  width,
  height,
  depth,
  onSelect,
  manipulable
}: {
  url: string;
  width: number;
  height: number;
  depth: number;
  selected: boolean;
  arOverlay: boolean;
  onSelect: () => void;
  manipulable: boolean;
}) {
  const { scene } = useGLTF(url);
  const root = useRef<Group>(null);
  const { gl } = useThree();

  useLayoutEffect(() => {
    const g = root.current;
    if (!g) return;
    // Reset before measuring the fresh Clone child.
    g.scale.set(1, 1, 1);
    g.position.set(0, 0, 0);
    const box = new THREE.Box3().setFromObject(g);
    const size = new THREE.Vector3();
    box.getSize(size);
    if (size.x < 1e-6 || size.y < 1e-6 || size.z < 1e-6) return;
    g.scale.set(width / size.x, height / size.y, depth / size.z);
    const box2 = new THREE.Box3().setFromObject(g);
    const center = new THREE.Vector3();
    box2.getCenter(center);
    g.position.set(-center.x, -center.y, -center.z);
  }, [scene, width, height, depth]);

  return (
    <group
      onClick={(e) => {
        e.stopPropagation();
        if (!manipulable) return;
        onSelect();
      }}
      onPointerOver={(e) => {
        if (!manipulable) return;
        e.stopPropagation();
        gl.domElement.style.cursor = 'grab';
      }}
      onPointerOut={() => {
        if (
          gl.domElement.style.cursor === 'pointer' ||
          gl.domElement.style.cursor === 'grab'
        ) {
          gl.domElement.style.cursor = 'auto';
        }
      }}
    >
      <group ref={root}>
        <Clone object={scene} castShadow receiveShadow />
      </group>
    </group>
  );
}

function BoxFallback({
  object,
  w,
  h,
  d,
  selected,
  arOverlay,
  dragging,
  onSelect,
  manipulable
}: {
  object: SceneObject;
  w: number;
  h: number;
  d: number;
  selected: boolean;
  arOverlay: boolean;
  dragging?: boolean;
  onSelect: () => void;
  manipulable: boolean;
}) {
  const { gl } = useThree();
  const isExisting = object.source === 'existing';
  const mat = materialFor(object.type, selected, isExisting, dragging);
  const isWall = object.type === 'wall';
  const isLights = object.type === 'string_lights' || object.type.includes('light');
  const isRug = object.type === 'rug' || (h < 0.05 && w > 1);

  return (
    <mesh
      castShadow={!isWall && !isRug}
      receiveShadow={isRug || isWall}
      onClick={(e) => {
        e.stopPropagation();
        if (!canManipulateObject(object)) return;
        onSelect();
      }}
      onPointerOver={(e) => {
        if (!manipulable) return;
        e.stopPropagation();
        gl.domElement.style.cursor = 'grab';
      }}
      onPointerOut={() => {
        if (
          gl.domElement.style.cursor === 'pointer' ||
          gl.domElement.style.cursor === 'grab'
        ) {
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
        transparent={isWall || arOverlay || !!dragging}
        opacity={isWall ? 0.35 : dragging ? 0.95 : arOverlay ? 0.88 : 1}
        depthWrite={!arOverlay || isWall}
      />
    </mesh>
  );
}

/**
 * Invisible catcher so the finger can leave the mesh while dragging
 * (touch-friendly Camera AR).
 */
function FloorDragPlane({
  y,
  active,
  onMove,
  onUp
}: {
  y: number;
  active: boolean;
  onMove: (e: ThreeEvent<PointerEvent>) => void;
  onUp: (e: ThreeEvent<PointerEvent>) => void;
}) {
  if (!active) return null;
  return (
    <mesh
      position={[0, y, 0]}
      rotation={[-Math.PI / 2, 0, 0]}
      onPointerMove={onMove}
      onPointerUp={onUp}
      onPointerCancel={onUp}
    >
      <planeGeometry args={[80, 80]} />
      <meshBasicMaterial
        transparent
        opacity={0}
        depthWrite={false}
        side={THREE.DoubleSide}
      />
    </mesh>
  );
}

export function ObjectGizmo({
  object,
  selected,
  onSelect,
  onMoveEnd,
  onRotateEnd,
  setDragging,
  disabled,
  arOverlay = false,
  floorDrag = false
}: Props) {
  const [group, setGroup] = useState<Group | null>(null);
  const { gl } = useThree();
  const startPos = useRef<Vector3 | null>(null);
  const startRot = useRef<[number, number, number, number] | null>(null);
  const dragOffset = useRef(new THREE.Vector3());
  const dragPlane = useRef(new THREE.Plane());
  const hitPoint = useRef(new THREE.Vector3());
  const draggingRef = useRef(false);
  const [isDragging, setIsDragging] = useState(false);
  /** Keep Y locked for the current gesture (floor-parallel drag). */
  const lockY = useRef(0);

  const [px, py, pz] = object.transform.position;
  const [rx, ry, rz, rw] = object.transform.rotation;

  useEffect(() => {
    if (!group || draggingRef.current) return;
    group.position.set(px, py, pz);
    group.quaternion.set(rx, ry, rz, rw);
  }, [group, px, py, pz, rx, ry, rz, rw]);

  const dims = object.dimensions;
  const w = dims?.width ?? 0.6;
  const h = dims?.height ?? 0.6;
  const d = dims?.depth ?? 0.6;
  const isExisting = object.source === 'existing';
  const isWall = object.type === 'wall';
  const manipulable = canManipulateObject(object) && !disabled;
  const modelUrl = isWall ? null : resolveModelUrl(object);
  const useFloorDrag = floorDrag && manipulable;
  const accent = isExisting ? '#e2b45c' : '#5ec8ff';

  const applyPlaneHit = (ray: THREE.Ray) => {
    if (!group) return false;
    if (!ray.intersectPlane(dragPlane.current, hitPoint.current)) return false;
    group.position.set(
      hitPoint.current.x + dragOffset.current.x,
      lockY.current,
      hitPoint.current.z + dragOffset.current.z
    );
    return true;
  };

  const beginFloorDrag = (e: ThreeEvent<PointerEvent>) => {
    if (!group || !useFloorDrag) return;
    e.stopPropagation();
    if (!selected) onSelect(object.id);

    draggingRef.current = true;
    setIsDragging(true);
    setDragging(true);
    lockY.current = group.position.y;
    dragPlane.current.setFromNormalAndCoplanarPoint(
      new THREE.Vector3(0, 1, 0),
      new THREE.Vector3(0, lockY.current, 0)
    );
    startPos.current = [group.position.x, group.position.y, group.position.z];

    if (e.ray.intersectPlane(dragPlane.current, hitPoint.current)) {
      dragOffset.current.set(
        group.position.x - hitPoint.current.x,
        0,
        group.position.z - hitPoint.current.z
      );
    } else {
      dragOffset.current.set(0, 0, 0);
    }

    try {
      gl.domElement.setPointerCapture(e.pointerId);
    } catch {
      /* ignore — some browsers reject capture mid-gesture */
    }
    gl.domElement.style.cursor = 'grabbing';
  };

  const moveFloorDrag = (e: ThreeEvent<PointerEvent>) => {
    if (!draggingRef.current) return;
    e.stopPropagation();
    applyPlaneHit(e.ray);
  };

  const endFloorDrag = (e?: ThreeEvent<PointerEvent>) => {
    if (!draggingRef.current || !group) return;
    if (e) e.stopPropagation();
    draggingRef.current = false;
    setIsDragging(false);
    setDragging(false);
    gl.domElement.style.cursor = 'auto';
    if (e) {
      try {
        gl.domElement.releasePointerCapture(e.pointerId);
      } catch {
        /* already released */
      }
    }

    const pos: Vector3 = [group.position.x, lockY.current, group.position.z];
    group.position.y = pos[1];
    const moved =
      !startPos.current ||
      Math.hypot(pos[0] - startPos.current[0], pos[2] - startPos.current[2]) >
        0.01;
    if (moved) onMoveEnd(object.id, pos);
  };

  return (
    <>
      <group
        ref={(node) => {
          if (node !== group) setGroup(node);
        }}
        onPointerDown={
          useFloorDrag
            ? (e) => {
                beginFloorDrag(e);
              }
            : undefined
        }
        onPointerMove={useFloorDrag ? moveFloorDrag : undefined}
        onPointerUp={useFloorDrag ? endFloorDrag : undefined}
        onPointerCancel={useFloorDrag ? endFloorDrag : undefined}
      >
        {modelUrl ? (
          <Suspense
            fallback={
              <BoxFallback
                object={object}
                w={w}
                h={h}
                d={d}
                selected={selected}
                arOverlay={arOverlay}
                dragging={isDragging}
                onSelect={() => onSelect(object.id)}
                manipulable={manipulable}
              />
            }
          >
            <GltfFurniture
              url={modelUrl}
              width={w}
              height={Math.max(h, 0.02)}
              depth={d}
              selected={selected}
              arOverlay={arOverlay}
              onSelect={() => onSelect(object.id)}
              manipulable={manipulable}
            />
          </Suspense>
        ) : (
          <BoxFallback
            object={object}
            w={w}
            h={h}
            d={d}
            selected={selected}
            arOverlay={arOverlay}
            dragging={isDragging}
            onSelect={() => onSelect(object.id)}
            manipulable={manipulable}
          />
        )}
        {selected && manipulable && (
          <mesh position={[0, h / 2 + 0.1, 0]}>
            <sphereGeometry args={[isDragging ? 0.09 : 0.07, 14, 14]} />
            <meshBasicMaterial color={accent} />
          </mesh>
        )}
        {selected && manipulable && (
          <mesh position={[0, 0.02, 0]} rotation={[-Math.PI / 2, 0, 0]}>
            <ringGeometry
              args={[
                Math.max(w, d) * (isDragging ? 0.38 : 0.42),
                Math.max(w, d) * (isDragging ? 0.58 : 0.52),
                48
              ]}
            />
            <meshBasicMaterial
              color={accent}
              transparent
              opacity={isDragging ? 0.85 : 0.55}
              depthWrite={false}
            />
          </mesh>
        )}
        {/* Soft glow disc while dragging — works for GLTF meshes too */}
        {isDragging && (
          <mesh position={[0, 0.03, 0]} rotation={[-Math.PI / 2, 0, 0]}>
            <circleGeometry args={[Math.max(w, d) * 0.55, 32]} />
            <meshBasicMaterial
              color={accent}
              transparent
              opacity={0.28}
              depthWrite={false}
            />
          </mesh>
        )}
      </group>

      <FloorDragPlane
        y={lockY.current || py}
        active={useFloorDrag && isDragging}
        onMove={moveFloorDrag}
        onUp={endFloorDrag}
      />

      {/* Map twin can still use TransformControls when floor drag is off */}
      {!floorDrag && selected && manipulable && group && (
        <TransformControls
          object={group}
          mode="translate"
          showX
          showY={false}
          showZ
          size={0.85}
          onMouseDown={() => {
            setDragging(true);
            startPos.current = [
              group.position.x,
              group.position.y,
              group.position.z
            ];
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
              Math.hypot(
                pos[0] - startPos.current[0],
                pos[2] - startPos.current[2]
              ) > 0.01;
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

// Warm the GLTF cache for catalog furniture.
for (const url of ALL_MODEL_URLS) {
  useGLTF.preload(url);
}
