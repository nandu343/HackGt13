'use client';

import { Canvas } from '@react-three/fiber';
import { OrbitControls } from '@react-three/drei';
import { useMemo } from 'react';

const room = {
  width: 5.4,
  length: 6.3,
  height: 2.7
};

const objects = [
  { id: 'sofa', type: 'sofa', position: [-1.3, 0.35, 1.6], color: '#d9c6a5', size: [2.2, 0.8, 0.9] },
  { id: 'table', type: 'table', position: [1.5, 0.5, 0.1], color: '#b36b41', size: [1.4, 0.2, 1.1] },
  { id: 'lamp', type: 'lamp', position: [-2.1, 0.9, -1.8], color: '#f8d66d', size: [0.4, 1.8, 0.4] },
  { id: 'plant', type: 'plant', position: [2.2, 0.5, -2.2], color: '#4fa07d', size: [0.6, 1.1, 0.6] }
];

function RoomBox() {
  return (
    <group>
      <mesh position={[0, -0.05, 0]} receiveShadow>
        <boxGeometry args={[room.width, 0.1, room.length]} />
        <meshStandardMaterial color="#dfe6d6" />
      </mesh>
      <mesh position={[0, room.height / 2, -room.length / 2]}>
        <boxGeometry args={[room.width, room.height, 0.08]} />
        <meshStandardMaterial color="#f4efe7" />
      </mesh>
      <mesh position={[0, room.height / 2, room.length / 2]}>
        <boxGeometry args={[room.width, room.height, 0.08]} />
        <meshStandardMaterial color="#f4efe7" />
      </mesh>
      <mesh position={[-room.width / 2, room.height / 2, 0]}>
        <boxGeometry args={[0.08, room.height, room.length]} />
        <meshStandardMaterial color="#f4efe7" />
      </mesh>
      <mesh position={[room.width / 2, room.height / 2, 0]}>
        <boxGeometry args={[0.08, room.height, room.length]} />
        <meshStandardMaterial color="#f4efe7" />
      </mesh>
    </group>
  );
}

function SpatialObject({ object }: { object: (typeof objects)[number] }) {
  return (
    <group position={object.position as [number, number, number]}>
      <mesh castShadow>
        <boxGeometry args={object.size as [number, number, number]} />
        <meshStandardMaterial color={object.color} />
      </mesh>
    </group>
  );
}

export default function Page() {
  const sceneObjects = useMemo(() => objects, []);

  return (
    <main className="page-shell">
      <section className="panel">
        <div className="header-row">
          <div>
            <p className="eyebrow">Spatial planning workspace</p>
            <h1>Shared Spatial AI</h1>
          </div>
          <div className="status-pill">Live room sync</div>
        </div>

        <div className="content-grid">
          <div className="scene-card">
            <Canvas camera={{ position: [5.5, 4.2, 7.5], fov: 42 }}>
              <ambientLight intensity={1.2} />
              <directionalLight position={[4, 6, 2]} intensity={1.5} />
              <RoomBox />
              {sceneObjects.map((item) => (
                <SpatialObject key={item.id} object={item} />
              ))}
              <OrbitControls enablePan enableZoom enableRotate />
            </Canvas>
          </div>

          <aside className="sidebar">
            <div className="card">
              <h2>AI prompt</h2>
              <p>Turn this into a birthday party for 15 people under $150 with room for dancing.</p>
            </div>

            <div className="card">
              <h2>Suggested layout</h2>
              <ul>
                <li>Dance floor cleared in center</li>
                <li>Seating pushed to perimeter</li>
                <li>Photo backdrop on west wall</li>
                <li>Ambient lighting and decor accents</li>
              </ul>
            </div>

            <div className="card">
              <h2>Budget</h2>
              <div className="budget-row">
                <span>Current</span>
                <strong>$218</strong>
              </div>
              <div className="budget-row target">
                <span>Target</span>
                <strong>$144</strong>
              </div>
            </div>
          </aside>
        </div>
      </section>
    </main>
  );
}
