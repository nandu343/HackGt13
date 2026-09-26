'use client';

import { Suspense, useMemo, useRef, useState } from 'react';
import { Canvas, type ThreeEvent, useThree } from '@react-three/fiber';
import { ContactShadows, Line, OrbitControls } from '@react-three/drei';
import * as THREE from 'three';
import type {
  DrawingStroke,
  RoomBounds,
  SceneObject,
  Vector3
} from '@shared-spatial-ai/schema';
import { ObjectGizmo } from './ObjectGizmo';

function RoomShell({ bounds }: { bounds: RoomBounds }) {
  const { width, length, height } = bounds;
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
        <meshStandardMaterial color="#f3eee6" roughness={0.85} transparent opacity={0.92} />
      </mesh>
      <mesh position={[-width / 2, height / 2, 0]} receiveShadow>
        <boxGeometry args={[0.06, height, length]} />
        <meshStandardMaterial color="#efe9e0" roughness={0.85} transparent opacity={0.75} />
      </mesh>
      <mesh position={[width / 2, height / 2, 0]} receiveShadow>
        <boxGeometry args={[0.06, height, length]} />
        <meshStandardMaterial color="#efe9e0" roughness={0.85} transparent opacity={0.75} />
      </mesh>
    </group>
  );
}

function StrokeLines({ strokes }: { strokes: DrawingStroke[] }) {
  return (
    <group>
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

/** Invisible back-wall plane for pointer drawing (Y-up meters). */
function DrawSurface({
  bounds,
  active,
  color,
  onStrokeComplete
}: {
  bounds: RoomBounds;
  active: boolean;
  color: string;
  onStrokeComplete: (points: Vector3[], plane: 'wall') => void;
}) {
  const { width, length, height } = bounds;
  const drawing = useRef(false);
  const points = useRef<Vector3[]>([]);
  const [preview, setPreview] = useState<Vector3[]>([]);
  const { gl } = useThree();

  const hitPoint = (e: ThreeEvent<PointerEvent>): Vector3 | null => {
    if (!e.point) return null;
    // Snap slightly in front of the wall to avoid z-fighting
    return [e.point.x, e.point.y, -length / 2 + 0.04];
  };

  if (!active) return null;

  return (
    <group>
      <mesh
        position={[0, height / 2, -length / 2 + 0.03]}
        onPointerDown={(e) => {
          e.stopPropagation();
          gl.domElement.style.cursor = 'crosshair';
          const p = hitPoint(e);
          if (!p) return;
          drawing.current = true;
          points.current = [p];
          setPreview([p]);
        }}
        onPointerMove={(e) => {
          if (!drawing.current) return;
          e.stopPropagation();
          const p = hitPoint(e);
          if (!p) return;
          const last = points.current[points.current.length - 1];
          const dx = p[0] - last[0];
          const dy = p[1] - last[1];
          if (dx * dx + dy * dy < 0.0004) return;
          points.current = [...points.current, p];
          setPreview([...points.current]);
        }}
        onPointerUp={(e) => {
          e.stopPropagation();
          gl.domElement.style.cursor = '';
          if (!drawing.current) return;
          drawing.current = false;
          const pts = points.current;
          points.current = [];
          setPreview([]);
          if (pts.length >= 2) onStrokeComplete(pts, 'wall');
        }}
        onPointerLeave={() => {
          if (!drawing.current) return;
          drawing.current = false;
          const pts = points.current;
          points.current = [];
          setPreview([]);
          if (pts.length >= 2) onStrokeComplete(pts, 'wall');
        }}
      >
        <planeGeometry args={[width * 0.98, height * 0.95]} />
        <meshBasicMaterial
          color="#6ec8e8"
          transparent
          opacity={0.08}
          side={THREE.DoubleSide}
        />
      </mesh>
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
  onStrokeComplete?: (points: Vector3[], plane: 'wall') => void;
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
  onStrokeComplete
}: Props) {
  const [dragging, setDragging] = useState(false);
  const strokeList = useMemo(() => strokes, [strokes]);

  return (
    <div className={`scene-canvas ${drawMode ? 'draw-mode' : ''}`}>
      <Canvas
        shadows
        camera={{ position: [5.8, 4.4, 7.8], fov: 40, near: 0.1, far: 80 }}
        onPointerMissed={() => {
          if (!dragging && !drawMode) onSelect(null);
        }}
      >
        <color attach="background" args={['#cfe8f4']} />
        <fog attach="fog" args={['#cfe8f4', 14, 32]} />
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
        <hemisphereLight args={['#e8f4ff', '#9aaf8c', 0.45]} />
        <Suspense fallback={null}>
          <RoomShell bounds={bounds} />
          <StrokeLines strokes={strokeList} />
          {drawMode && onStrokeComplete && (
            <DrawSurface
              bounds={bounds}
              active={drawMode}
              color={drawColor}
              onStrokeComplete={onStrokeComplete}
            />
          )}
          {objects.map((obj) => (
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
            />
          ))}
          <ContactShadows
            position={[0, 0.01, 0]}
            opacity={0.35}
            scale={Math.max(bounds.width, bounds.length) * 1.4}
            blur={2.4}
            far={6}
          />
        </Suspense>
        <OrbitControls
          makeDefault
          enabled={!dragging && !drawMode}
          enablePan
          enableZoom
          enableRotate
          maxPolarAngle={Math.PI / 2.05}
          minDistance={3}
          maxDistance={18}
        />
      </Canvas>
    </div>
  );
}
