'use client';

import {
  Suspense,
  useEffect,
  useMemo,
  useRef,
  useState,
  type RefObject
} from 'react';
import { Canvas, useFrame, useThree } from '@react-three/fiber';
import { ContactShadows, Line, OrbitControls } from '@react-three/drei';
import { XR, createXRStore } from '@react-three/xr';
import type { OrbitControls as OrbitControlsImpl } from 'three-stdlib';
import * as THREE from 'three';
import type {
  DrawingStroke,
  PresenceUser,
  RoomBounds,
  SceneObject,
  Vector3
} from '@shared-spatial-ai/schema';
import { isStructureObject } from '../lib/objectPolicy';
import { GhostAvatars } from './GhostAvatars';
import { ObjectGizmo } from './ObjectGizmo';

/** `ar` = live camera + overlays only; `map` = digital twin room (no camera). */
export type ViewMode = 'ar' | 'map';

export const xrStore = createXRStore();

/** Semi-transparent dual-tint layout ghosts (disagreement A/B). */
function GhostLayoutObjects({
  objects,
  tint,
  offsetX = 0
}: {
  objects: SceneObject[];
  tint: string;
  offsetX?: number;
}) {
  return (
    <group position={[offsetX, 0, 0]}>
      {objects.map((obj) => {
        const dims = obj.dimensions;
        const w = dims?.width ?? 0.6;
        const h = dims?.height ?? 0.6;
        const d = dims?.depth ?? 0.6;
        const [px, py, pz] = obj.transform.position;
        const [rx, ry, rz, rw] = obj.transform.rotation;
        return (
          <mesh
            key={`ghost-${tint}-${obj.id}`}
            position={[px, py, pz]}
            quaternion={[rx, ry, rz, rw]}
          >
            <boxGeometry args={[w, Math.max(h, 0.02), d]} />
            <meshStandardMaterial
              color={tint}
              transparent
              opacity={0.32}
              depthWrite={false}
              roughness={0.4}
              metalness={0.05}
              emissive={tint}
              emissiveIntensity={0.25}
            />
          </mesh>
        );
      })}
    </group>
  );
}

/** Push orbit focus + look dir onto the presence channel (throttled). */
function PresencePoseBroadcaster({
  controlsRef,
  onPose
}: {
  controlsRef: RefObject<OrbitControlsImpl | null>;
  onPose?: (position: Vector3, lookDirection: Vector3) => void;
}) {
  const { camera } = useThree();
  const lastSent = useRef(0);
  const lastPos = useRef(new THREE.Vector3(NaN, NaN, NaN));
  const look = useRef(new THREE.Vector3());
  const ghostPos = useRef(new THREE.Vector3());

  useFrame(() => {
    if (!onPose) return;
    const controls = controlsRef.current;
    if (!controls) return;
    const now = performance.now();
    if (now - lastSent.current < 120) return;

    ghostPos.current.set(
      controls.target.x,
      Math.max(0.55, controls.target.y + 0.55),
      controls.target.z
    );
    camera.getWorldDirection(look.current);

    const moved =
      !Number.isFinite(lastPos.current.x) ||
      ghostPos.current.distanceToSquared(lastPos.current) > 0.0025;
    if (!moved && now - lastSent.current < 900) return;

    lastSent.current = now;
    lastPos.current.copy(ghostPos.current);
    onPose(
      [ghostPos.current.x, ghostPos.current.y, ghostPos.current.z],
      [look.current.x, look.current.y, look.current.z]
    );
  });

  return null;
}

/** Map twin only — full synthetic room (walls / floor / slab). Never used in Camera AR. */
function RoomShell({ bounds }: { bounds: RoomBounds }) {
  const { width, length, height } = bounds;
  const wallOpacity = 0.92;
  const sideOpacity = 0.75;
  return (
    <group>
      <mesh position={[0, -0.04, 0]} receiveShadow rotation={[-Math.PI / 2, 0, 0]}>
        <planeGeometry args={[width, length]} />
        <meshStandardMaterial color="#d8e2d4" roughness={0.92} metalness={0.02} />
      </mesh>
      <mesh position={[0, -0.08, 0]} receiveShadow>
        <boxGeometry args={[width + 0.12, 0.08, length + 0.12]} />
        <meshStandardMaterial color="#c5d0c0" roughness={1} />
      </mesh>
      <mesh position={[0, height / 2, -length / 2]} receiveShadow>
        <boxGeometry args={[width, height, 0.06]} />
        <meshStandardMaterial
          color="#f3eee6"
          roughness={0.85}
          transparent
          opacity={wallOpacity}
        />
      </mesh>
      <mesh position={[-width / 2, height / 2, 0]} receiveShadow>
        <boxGeometry args={[0.06, height, length]} />
        <meshStandardMaterial
          color="#efe9e0"
          roughness={0.85}
          transparent
          opacity={sideOpacity}
        />
      </mesh>
      <mesh position={[width / 2, height / 2, 0]} receiveShadow>
        <boxGeometry args={[0.06, height, length]} />
        <meshStandardMaterial
          color="#efe9e0"
          roughness={0.85}
          transparent
          opacity={sideOpacity}
        />
      </mesh>
    </group>
  );
}

function StrokeLines({ strokes }: { strokes: DrawingStroke[] }) {
  // Key by stroke set so clears remount geometry (drei Line can retain GPU state).
  const setKey = strokes.map((s) => s.strokeId).join('|') || 'empty';
  return (
    <group key={setKey}>
      {strokes.map((s) => (
        <Line
          key={s.strokeId}
          points={s.points.map((p) => new THREE.Vector3(p[0], p[1], p[2]))}
          color={s.color || '#6ec8e8'}
          lineWidth={Math.max(2, (s.width ?? 0.02) * 120)}
          worldUnits={false}
        />
      ))}
    </group>
  );
}

/** Draw depth in front of camera (meters) — keeps strokes under the pointer. */
const DRAW_DEPTH_M = 1.35;

/**
 * Free-space drawing: CSS-pixel NDC → camera ray → camera-facing plane at fixed
 * depth. Does not use mesh `e.point` (volume/plane hits caused AR offset).
 */
function DrawingLayer({
  bounds,
  active,
  color,
  onStrokeComplete
}: {
  bounds: RoomBounds;
  active: boolean;
  color: string;
  onStrokeComplete: (points: Vector3[], plane: 'free') => void;
}) {
  const drawing = useRef(false);
  const points = useRef<Vector3[]>([]);
  const [preview, setPreview] = useState<Vector3[]>([]);
  const { camera, gl, raycaster } = useThree();
  const ndc = useRef(new THREE.Vector2());
  const drawPlane = useRef(new THREE.Plane());
  const hit = useRef(new THREE.Vector3());
  const camDir = useRef(new THREE.Vector3());
  const boundsRef = useRef(bounds);
  boundsRef.current = bounds;
  const completeRef = useRef(onStrokeComplete);
  completeRef.current = onStrokeComplete;

  const sampleWorldPoint = (clientX: number, clientY: number): Vector3 | null => {
    const canvas = gl.domElement;
    const rect = canvas.getBoundingClientRect();
    if (rect.width < 1 || rect.height < 1) return null;
    // CSS pixels → NDC (not buffer pixels × dpr).
    const x = ((clientX - rect.left) / rect.width) * 2 - 1;
    const y = -((clientY - rect.top) / rect.height) * 2 + 1;
    ndc.current.set(x, y);
    raycaster.setFromCamera(ndc.current, camera);

    camera.getWorldDirection(camDir.current);
    const planePoint = camera.position
      .clone()
      .addScaledVector(camDir.current, DRAW_DEPTH_M);
    drawPlane.current.setFromNormalAndCoplanarPoint(camDir.current, planePoint);

    if (!raycaster.ray.intersectPlane(drawPlane.current, hit.current)) {
      hit.current
        .copy(raycaster.ray.origin)
        .addScaledVector(raycaster.ray.direction, DRAW_DEPTH_M);
    }

    const b = boundsRef.current;
    const hw = b.width / 2 + 0.75;
    const hl = b.length / 2 + 0.75;
    return [
      Math.max(-hw, Math.min(hw, hit.current.x)),
      Math.max(0.05, Math.min(b.height + 0.6, hit.current.y)),
      Math.max(-hl, Math.min(hl, hit.current.z))
    ];
  };

  useEffect(() => {
    if (!active) {
      drawing.current = false;
      points.current = [];
      setPreview([]);
      gl.domElement.style.cursor = '';
      return;
    }

    const el = gl.domElement;
    el.style.cursor = 'crosshair';
    el.style.touchAction = 'none';

    const finish = () => {
      if (!drawing.current) return;
      drawing.current = false;
      const pts = points.current;
      points.current = [];
      setPreview([]);
      if (pts.length >= 2) completeRef.current(pts, 'free');
    };

    const onDown = (e: PointerEvent) => {
      if (e.button !== 0) return;
      e.preventDefault();
      e.stopPropagation();
      try {
        el.setPointerCapture(e.pointerId);
      } catch {
        // ignore
      }
      const p = sampleWorldPoint(e.clientX, e.clientY);
      if (!p) return;
      drawing.current = true;
      points.current = [p];
      setPreview([p]);
    };

    const onMove = (e: PointerEvent) => {
      if (!drawing.current) return;
      e.preventDefault();
      const p = sampleWorldPoint(e.clientX, e.clientY);
      if (!p) return;
      const last = points.current[points.current.length - 1];
      const dx = p[0] - last[0];
      const dy = p[1] - last[1];
      const dz = p[2] - last[2];
      if (dx * dx + dy * dy + dz * dz < 0.00025) return;
      points.current = [...points.current, p];
      setPreview([...points.current]);
    };

    const onUp = (e: PointerEvent) => {
      try {
        el.releasePointerCapture(e.pointerId);
      } catch {
        // ignore
      }
      finish();
    };

    el.addEventListener('pointerdown', onDown, { capture: true });
    el.addEventListener('pointermove', onMove, { capture: true });
    el.addEventListener('pointerup', onUp, { capture: true });
    el.addEventListener('pointercancel', onUp, { capture: true });
    return () => {
      el.removeEventListener('pointerdown', onDown, true);
      el.removeEventListener('pointermove', onMove, true);
      el.removeEventListener('pointerup', onUp, true);
      el.removeEventListener('pointercancel', onUp, true);
      el.style.cursor = '';
      el.style.touchAction = '';
      drawing.current = false;
      points.current = [];
    };
    // sampleWorldPoint closes over camera/gl/raycaster from this render
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [active, gl, camera, raycaster]);

  if (!active) return null;

  return (
    <group>
      {preview.length >= 2 && (
        <Line
          points={preview.map((p) => new THREE.Vector3(p[0], p[1], p[2]))}
          color={color}
          lineWidth={3}
        />
      )}
    </group>
  );
}

type Props = {
  bounds: RoomBounds;
  objects: SceneObject[];
  selectedObjectId: string | null;
  onSelect: (id: string | null) => void;
  onMoveEnd: (id: string, position: Vector3) => void;
  onRotateEnd: (id: string, rotation: [number, number, number, number]) => void;
  disabled?: boolean;
  drawMode?: boolean;
  strokes?: DrawingStroke[];
  drawColor?: string;
  onStrokeComplete?: (points: Vector3[], plane: 'free' | 'wall' | 'floor') => void;
  presence?: PresenceUser[];
  localUserId?: string;
  onPresencePose?: (position: Vector3, lookDirection: Vector3) => void;
  ghostObjectsA?: SceneObject[];
  ghostObjectsB?: SceneObject[];
  ghostMode?: 'overlay' | 'side';
  /** ar = camera + overlays; map = digital twin dollhouse. Mutually exclusive. */
  viewMode?: ViewMode;
};

export function SceneCanvas({
  bounds,
  objects,
  selectedObjectId,
  onSelect,
  onMoveEnd,
  onRotateEnd,
  disabled,
  drawMode = false,
  strokes = [],
  drawColor = '#e2b45c',
  onStrokeComplete,
  presence = [],
  localUserId = '',
  onPresencePose,
  ghostObjectsA = [],
  ghostObjectsB = [],
  ghostMode = 'overlay',
  viewMode = 'ar'
}: Props) {
  const [dragging, setDragging] = useState(false);
  const strokeList = useMemo(() => strokes, [strokes]);
  const controlsRef = useRef<OrbitControlsImpl | null>(null);
  const sideOffset = ghostMode === 'side' ? Math.max(bounds.width * 0.55, 2.2) : 0;
  const arMode = viewMode === 'ar';
  const mapMode = viewMode === 'map';
  const bg = '#cfe8f4';
  // AR: eye-height looking into the room; Map: elevated dollhouse orbit.
  const camPos: [number, number, number] = arMode
    ? [0, 1.55, Math.max(bounds.length * 0.35, 1.6)]
    : [5.8, 4.4, 7.8];
  const overlayObjects = useMemo(
    () => (arMode ? objects.filter((o) => !isStructureObject(o)) : objects),
    [arMode, objects]
  );

  return (
    <div
      className={`scene-canvas ${drawMode ? 'draw-mode' : ''} ${
        arMode ? 'ar-mode' : 'map-mode'
      }`}
    >
      <Canvas
        shadows={mapMode}
        gl={{ alpha: arMode, antialias: true, premultipliedAlpha: false }}
        camera={{ position: camPos, fov: arMode ? 70 : 40, near: 0.05, far: 80 }}
        onPointerMissed={() => {
          if (!dragging && !drawMode) onSelect(null);
        }}
        style={arMode ? { background: 'transparent' } : undefined}
      >
        <XR store={xrStore}>
          {mapMode ? <color attach="background" args={[bg]} /> : null}
          {mapMode ? <fog attach="fog" args={[bg, 14, 32]} /> : null}
          {arMode ? (
            <>
              <ambientLight intensity={1.05} />
              <directionalLight position={[2, 4, 2]} intensity={0.55} />
            </>
          ) : (
            <>
              <ambientLight intensity={0.55} />
              <directionalLight
                castShadow
                position={[5.5, 9, 3.5]}
                intensity={1.35}
                shadow-mapSize-width={2048}
                shadow-mapSize-height={2048}
                shadow-camera-far={40}
                shadow-camera-left={-8}
                shadow-camera-right={8}
                shadow-camera-top={8}
                shadow-camera-bottom={-8}
              />
              <hemisphereLight args={['#dceaf5', '#8a9e7a', 0.45]} />
            </>
          )}
          <Suspense fallback={null}>
            {mapMode ? <RoomShell bounds={bounds} /> : null}
            <StrokeLines strokes={strokeList} />
            {drawMode && onStrokeComplete && (
              <DrawingLayer
                bounds={bounds}
                active={drawMode}
                color={drawColor}
                onStrokeComplete={onStrokeComplete}
              />
            )}
            {overlayObjects.map((obj) => (
              <ObjectGizmo
                key={obj.id}
                object={obj}
                selected={!drawMode && selectedObjectId === obj.id}
                onSelect={(id) => {
                  if (!drawMode) onSelect(id);
                }}
                onMoveEnd={onMoveEnd}
                onRotateEnd={onRotateEnd}
                setDragging={setDragging}
                disabled={disabled || drawMode}
                arOverlay={arMode}
                // Floor-plane drag: Camera AR (touch) + Map twin.
                floorDrag
              />
            ))}
            {ghostObjectsA.length > 0 && (
              <GhostLayoutObjects
                objects={ghostObjectsA}
                tint="#3db8e8"
                offsetX={-sideOffset}
              />
            )}
            {ghostObjectsB.length > 0 && (
              <GhostLayoutObjects
                objects={ghostObjectsB}
                tint="#e8a03d"
                offsetX={sideOffset}
              />
            )}
            {localUserId && (
              <GhostAvatars presence={presence} localUserId={localUserId} />
            )}
            {mapMode ? (
              <ContactShadows
                position={[0, 0.01, 0]}
                opacity={0.35}
                scale={Math.max(bounds.width, bounds.length) * 1.4}
                blur={2.4}
                far={6}
              />
            ) : null}
          </Suspense>
          <PresencePoseBroadcaster
            controlsRef={controlsRef}
            onPose={onPresencePose}
          />
          <OrbitControls
            ref={controlsRef}
            makeDefault
            enabled={!dragging && !drawMode}
            enablePan={mapMode}
            enableZoom={mapMode || !drawMode}
            enableRotate
            // AR: light peek around overlays — not a free dollhouse flyaround.
            maxPolarAngle={arMode ? Math.PI / 2.05 : Math.PI / 2.05}
            minPolarAngle={arMode ? Math.PI / 2.35 : 0}
            minAzimuthAngle={arMode ? -Math.PI / 3 : undefined}
            maxAzimuthAngle={arMode ? Math.PI / 3 : undefined}
            minDistance={arMode ? 1.2 : 3}
            maxDistance={arMode ? 4.5 : 18}
            rotateSpeed={arMode ? 0.45 : 1}
            zoomSpeed={arMode ? 0.55 : 1}
            target={arMode ? [0, 1.15, 0] : [0, 0, 0]}
          />
        </XR>
      </Canvas>
      {arMode ? <div className="ar-reticle" aria-hidden /> : null}
    </div>
  );
}
