'use client';

import { useMemo, useRef } from 'react';
import { Html } from '@react-three/drei';
import { useFrame } from '@react-three/fiber';
import * as THREE from 'three';
import type { PresenceUser, Vector3 } from '@shared-spatial-ai/schema';

const GHOST_HEIGHT = 0.72;
const BODY_RADIUS = 0.18;
const HEAD_RADIUS = 0.14;

function GhostMesh({
  user,
  showLocalMarker
}: {
  user: PresenceUser;
  showLocalMarker?: boolean;
}) {
  const group = useRef<THREE.Group>(null);
  const bodyMat = useRef<THREE.MeshStandardMaterial>(null);
  const headMat = useRef<THREE.MeshStandardMaterial>(null);
  const color = user.color || '#6ec8e8';
  const speaking = Boolean(user.voiceSpeaking);
  const pos = user.position as Vector3;

  useFrame((state) => {
    const g = group.current;
    if (!g) return;
    const t = state.clock.elapsedTime;
    const bob = Math.sin(t * 1.6 + pos[0] * 3) * 0.03;
    const pulse = speaking ? 1 + Math.sin(t * 8) * 0.12 : 1;
    g.position.set(pos[0], Math.max(0.35, pos[1]) + bob, pos[2]);
    g.scale.setScalar(pulse * (showLocalMarker ? 0.55 : 1));

    const opacity = showLocalMarker
      ? 0.18
      : speaking
        ? 0.42 + Math.sin(t * 8) * 0.12
        : 0.38;
    if (bodyMat.current) bodyMat.current.opacity = opacity;
    if (headMat.current) headMat.current.opacity = opacity + 0.05;

    if (user.lookDirection) {
      const [lx, , lz] = user.lookDirection;
      if (lx * lx + lz * lz > 1e-6) {
        g.rotation.y = Math.atan2(lx, lz);
      }
    }
  });

  return (
    <group ref={group} position={[pos[0], pos[1], pos[2]]}>
      {/* Soft capsule body — no raycast so gizmos / draw stay usable */}
      <mesh position={[0, GHOST_HEIGHT * 0.28, 0]} castShadow={false} raycast={() => null}>
        <capsuleGeometry args={[BODY_RADIUS, GHOST_HEIGHT * 0.45, 6, 12]} />
        <meshStandardMaterial
          ref={bodyMat}
          color={color}
          transparent
          opacity={showLocalMarker ? 0.18 : 0.38}
          roughness={0.35}
          metalness={0.05}
          depthWrite={false}
        />
      </mesh>
      <mesh position={[0, GHOST_HEIGHT * 0.72, 0]} castShadow={false} raycast={() => null}>
        <sphereGeometry args={[HEAD_RADIUS, 16, 16]} />
        <meshStandardMaterial
          ref={headMat}
          color={color}
          transparent
          opacity={showLocalMarker ? 0.22 : 0.45}
          roughness={0.3}
          metalness={0.05}
          depthWrite={false}
        />
      </mesh>
      {!showLocalMarker && (
        <Html
          position={[0, GHOST_HEIGHT + 0.28, 0]}
          center
          distanceFactor={8}
          style={{ pointerEvents: 'none', userSelect: 'none' }}
        >
          <div className={`ghost-label ${speaking ? 'is-speaking' : ''}`}>
            <span className="ghost-swatch" style={{ background: color }} />
            <span className="ghost-name">{user.displayName}</span>
          </div>
        </Html>
      )}
    </group>
  );
}

type Props = {
  presence: PresenceUser[];
  localUserId: string;
  /** When true, local user gets a faint marker instead of a full ghost. */
  showLocalMarker?: boolean;
};

export function GhostAvatars({
  presence,
  localUserId,
  showLocalMarker = false
}: Props) {
  const remotes = useMemo(
    () =>
      presence.filter(
        (p) =>
          p.userId !== localUserId &&
          Array.isArray(p.position) &&
          p.position.length >= 3
      ),
    [presence, localUserId]
  );

  const local = useMemo(() => {
    if (!showLocalMarker) return null;
    return presence.find(
      (p) =>
        p.userId === localUserId &&
        Array.isArray(p.position) &&
        p.position.length >= 3
    );
  }, [presence, localUserId, showLocalMarker]);

  return (
    <group>
      {remotes.map((user) => (
        <GhostMesh key={user.userId} user={user} />
      ))}
      {local && <GhostMesh user={local} showLocalMarker />}
    </group>
  );
}
