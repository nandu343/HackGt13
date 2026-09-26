'use client';

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode
} from 'react';
import {
  DrawingStrokeSchema,
  SceneSchema,
  type CatalogItem,
  type DrawingStroke,
  type LayoutRequest,
  type LayoutResponse,
  type PresenceUser,
  type Scene,
  type SceneOperation,
  type Vector3
} from '@shared-spatial-ai/schema';
import {
  ApiError,
  fetchCatalog,
  fetchHealth,
  fetchScene,
  getApiBaseUrl,
  postAiLayout,
  postCheckout,
  postOperations
} from './api';
import { blendScenes } from './lerp';
import { VoiceMesh, type VoiceState } from './voiceMesh';
import {
  createSceneSocket,
  isSceneWsEnabled,
  sendDrawClear,
  sendDrawStroke,
  sendSceneJoin,
  sendSceneLock,
  sendScenePresence,
  sendSceneUnlock
} from './ws';
export const DEMO_SCENE_ID = 'scene_party_001';

function resolveActorId(): string {
  if (typeof window === 'undefined') return 'web_demo_user';
  try {
    const key = 'ssa_actor_id';
    let id = sessionStorage.getItem(key);
    if (!id) {
      id = `web_${Math.random().toString(36).slice(2, 9)}`;
      sessionStorage.setItem(key, id);
    }
    return id;
  } catch {
    return 'web_demo_user';
  }
}

export type ConnectionStatus =
  | 'connecting'
  | 'connected'
  | 'disconnected'
  | 'error'
  | 'syncing';

export type ToastKind = 'info' | 'success' | 'error';

export type Toast = {
  id: number;
  message: string;
  kind: ToastKind;
};

type SceneStoreValue = {
  scene: Scene | null;
  catalog: CatalogItem[];
  connection: ConnectionStatus;
  selectedObjectId: string | null;
  pendingLayout: LayoutResponse | null;
  targetBudget: number;
  guestCount: number;
  prompt: string;
  toasts: Toast[];
  isBusy: boolean;
  canUndo: boolean;
  animating: boolean;
  presence: PresenceUser[];
  actorId: string;
  voice: VoiceState;
  drawMode: boolean;
  strokes: DrawingStroke[];
  setSelectedObjectId: (id: string | null) => void;
  setPrompt: (v: string) => void;
  setTargetBudget: (v: number) => void;
  setGuestCount: (v: number) => void;
  reload: () => Promise<void>;
  dismissToast: (id: number) => void;
  pushToast: (message: string, kind?: ToastKind) => void;
  applyLocalMove: (objectId: string, position: Vector3) => Promise<void>;
  applyLocalRotate: (objectId: string, rotation: [number, number, number, number]) => Promise<void>;
  deleteSelected: () => Promise<void>;
  requestLayout: () => Promise<void>;
  acceptLayout: () => Promise<void>;
  rejectLayout: () => void;
  addCatalogItem: (productId: string) => Promise<void>;
  checkout: () => Promise<void>;
  undo: () => Promise<void>;
  toggleVoice: () => Promise<void>;
  toggleMute: () => void;
  setDrawMode: (on: boolean) => void;
  addStroke: (stroke: Omit<DrawingStroke, 'sceneId' | 'actorId'> & { sceneId?: string; actorId?: string }) => void;
  clearOwnStrokes: () => void;
  clearAllStrokes: () => void;
  productMap: Map<string, CatalogItem>;
  budgetUsed: number;
};

const SceneStoreContext = createContext<SceneStoreValue | null>(null);

function opId(): string {
  return `op_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 8)}`;
}

function cloneScene(scene: Scene): Scene {
  return structuredClone(scene);
}

export function SceneStoreProvider({
  sceneId = DEMO_SCENE_ID,
  children
}: {
  sceneId?: string;
  children: ReactNode;
}) {
  const [scene, setScene] = useState<Scene | null>(null);
  const [catalog, setCatalog] = useState<CatalogItem[]>([]);
  const [connection, setConnection] = useState<ConnectionStatus>('connecting');
  const [selectedObjectId, setSelectedObjectId] = useState<string | null>(null);
  const [pendingLayout, setPendingLayout] = useState<LayoutResponse | null>(null);
  const [targetBudget, setTargetBudget] = useState(2000);
  const [guestCount, setGuestCount] = useState(15);
  const [prompt, setPrompt] = useState(
    'Turn this into a birthday party for 15 people with room for dancing.'
  );
  const [toasts, setToasts] = useState<Toast[]>([]);
  const [isBusy, setIsBusy] = useState(false);
  const [animating, setAnimating] = useState(false);
  const [historyDepth, setHistoryDepth] = useState(0);
  const [presence, setPresence] = useState<PresenceUser[]>([]);
  const [actorId] = useState(() => resolveActorId());
  const [voice, setVoice] = useState<VoiceState>({
    enabled: false,
    muted: true,
    speaking: false,
    error: null
  });
  const [drawMode, setDrawMode] = useState(false);
  const [strokes, setStrokes] = useState<DrawingStroke[]>([]);
  const historyRef = useRef<Scene[]>([]);
  const sceneRef = useRef<Scene | null>(null);
  const toastSeq = useRef(0);
  const animFrameRef = useRef<number | null>(null);
  const socketRef = useRef<WebSocket | null>(null);
  const selectedRef = useRef<string | null>(null);
  const actorIdRef = useRef(actorId);
  const voiceRef = useRef(voice);
  const voiceMeshRef = useRef<VoiceMesh | null>(null);
  const presenceRef = useRef<PresenceUser[]>([]);

  useEffect(() => {
    sceneRef.current = scene;
  }, [scene]);

  useEffect(() => {
    selectedRef.current = selectedObjectId;
  }, [selectedObjectId]);

  useEffect(() => {
    actorIdRef.current = actorId;
  }, [actorId]);

  useEffect(() => {
    voiceRef.current = voice;
  }, [voice]);

  useEffect(() => {
    presenceRef.current = presence;
  }, [presence]);

  const pushToast = useCallback((message: string, kind: ToastKind = 'info') => {
    const id = ++toastSeq.current;
    setToasts((prev) => [...prev.slice(-4), { id, message, kind }]);
    window.setTimeout(() => {
      setToasts((prev) => prev.filter((t) => t.id !== id));
    }, 4200);
  }, []);

  const dismissToast = useCallback((id: number) => {
    setToasts((prev) => prev.filter((t) => t.id !== id));
  }, []);

  const pushHistory = useCallback((snapshot: Scene) => {
    historyRef.current = [...historyRef.current.slice(-24), cloneScene(snapshot)];
    setHistoryDepth(historyRef.current.length);
  }, []);

  const animateToScene = useCallback((from: Scene, to: Scene, durationMs = 680) => {
    return new Promise<void>((resolve) => {
      if (animFrameRef.current != null) {
        cancelAnimationFrame(animFrameRef.current);
      }
      setAnimating(true);
      const start = performance.now();
      const tick = (now: number) => {
        const t = Math.min(1, (now - start) / durationMs);
        setScene(blendScenes(from, to, t));
        if (t < 1) {
          animFrameRef.current = requestAnimationFrame(tick);
        } else {
          setScene(to);
          sceneRef.current = to;
          setAnimating(false);
          animFrameRef.current = null;
          resolve();
        }
      };
      animFrameRef.current = requestAnimationFrame(tick);
    });
  }, []);

  const reload = useCallback(async () => {
    setConnection('connecting');
    setIsBusy(true);
    try {
      await fetchHealth();
      const [nextScene, nextCatalog] = await Promise.all([
        fetchScene(sceneId),
        fetchCatalog()
      ]);
      setScene(nextScene);
      sceneRef.current = nextScene;
      setCatalog(nextCatalog);
      setConnection('connected');
      historyRef.current = [];
      setHistoryDepth(0);
    } catch (err) {
      setConnection('error');
      const msg = err instanceof ApiError ? err.message : 'Failed to load scene';
      pushToast(msg, 'error');
    } finally {
      setIsBusy(false);
    }
  }, [sceneId, pushToast]);

  useEffect(() => {
    void reload();
  }, [reload]);

  // WebSocket /ws/scene/{id} — patches, presence, locks, voice signal, drawing
  useEffect(() => {
    if (!isSceneWsEnabled() || connection === 'error') return;
    let closed = false;

    const applyRemoteScene = (raw: unknown) => {
      if (!raw) return;
      try {
        const remote = SceneSchema.parse(raw);
        const local = sceneRef.current;
        if (!local || remote.version >= local.version) {
          setScene(remote);
          sceneRef.current = remote;
          setConnection('connected');
        }
      } catch {
        // ignore invalid payloads
      }
    };

    const mesh = new VoiceMesh(
      actorIdRef.current,
      () => socketRef.current,
      () => ({
        userId: actorIdRef.current,
        displayName: 'Web demo',
        color: '#6ec8e8',
        selectedObjectId: selectedRef.current,
        voiceEnabled: voiceRef.current.enabled,
        voiceSpeaking: voiceRef.current.speaking && !voiceRef.current.muted
      }),
      setVoice
    );
    voiceMeshRef.current = mesh;

    const socket = createSceneSocket(getApiBaseUrl(), sceneId, {
      onOpen: () => {
        if (closed) return;
        setConnection('connected');
        sendSceneJoin(socket!, {
          userId: actorIdRef.current,
          displayName: 'Web demo',
          color: '#6ec8e8',
          selectedObjectId: selectedRef.current,
          voiceEnabled: voiceRef.current.enabled,
          voiceSpeaking: false
        });
      },
      onClose: () => {
        if (!closed) setConnection((c) => (c === 'syncing' ? c : 'disconnected'));
      },
      onError: () => {
        // Keep HTTP path usable if WS fails
      },
      onMessage: (msg) => {
        if (msg.type === 'welcome') {
          if (Array.isArray(msg.presence)) {
            setPresence(msg.presence as PresenceUser[]);
            mesh.syncPeers(msg.presence as PresenceUser[]);
          }
          if (Array.isArray(msg.strokes)) {
            const parsed: DrawingStroke[] = [];
            for (const raw of msg.strokes) {
              try {
                parsed.push(DrawingStrokeSchema.parse(raw));
              } catch {
                // skip
              }
            }
            setStrokes(parsed);
          }
          applyRemoteScene(msg.scene);
          return;
        }
        if (msg.type === 'presence') {
          if (Array.isArray(msg.presence)) {
            setPresence(msg.presence as PresenceUser[]);
            mesh.syncPeers(msg.presence as PresenceUser[]);
          }
          return;
        }
        if (msg.type === 'scene' || msg.type === 'patch') {
          applyRemoteScene(msg.scene);
          return;
        }
        if (msg.type === 'lock') {
          const lockScene = msg.scene ?? msg.payload?.scene;
          applyRemoteScene(lockScene);
          return;
        }
        if (
          msg.type === 'rtc_offer' ||
          msg.type === 'rtc_answer' ||
          msg.type === 'rtc_ice'
        ) {
          void mesh.handleSignal(msg);
          return;
        }
        if (msg.type === 'draw_stroke' && msg.stroke) {
          try {
            const stroke = DrawingStrokeSchema.parse(msg.stroke);
            setStrokes((prev) => {
              if (prev.some((s) => s.strokeId === stroke.strokeId)) return prev;
              return [...prev, stroke];
            });
          } catch {
            // ignore
          }
          return;
        }
        if (msg.type === 'draw_clear') {
          if (Array.isArray(msg.strokes)) {
            const parsed: DrawingStroke[] = [];
            for (const raw of msg.strokes) {
              try {
                parsed.push(DrawingStrokeSchema.parse(raw));
              } catch {
                // skip
              }
            }
            setStrokes(parsed);
          } else if (msg.scope === 'all') {
            setStrokes([]);
          } else if (msg.actorId) {
            const aid = msg.actorId;
            setStrokes((prev) => prev.filter((s) => s.actorId !== aid));
          }
          return;
        }
        if (msg.type === 'error' && msg.message) {
          // Avoid toast spam for transient RTC peer miss
          if (!String(msg.message).includes('not connected')) {
            pushToast(msg.message, 'error');
          }
        }
      }
    });
    socketRef.current = socket;
    return () => {
      closed = true;
      mesh.dispose();
      voiceMeshRef.current = null;
      socketRef.current = null;
      socket?.close();
    };
  }, [sceneId, connection === 'error', pushToast]);

  const setSelectedObjectIdWithLock = useCallback(
    (id: string | null) => {
      const prev = selectedRef.current;
      const sock = socketRef.current;
      const actor = actorIdRef.current;
      if (sock && prev && prev !== id) {
        sendSceneUnlock(sock, prev, actor);
      }
      setSelectedObjectId(id);
      selectedRef.current = id;
      if (sock && id) {
        sendSceneLock(sock, id, actor);
      }
      if (sock) {
        sendScenePresence(sock, {
          userId: actor,
          displayName: 'Web demo',
          color: '#6ec8e8',
          selectedObjectId: id,
          voiceEnabled: voiceRef.current.enabled,
          voiceSpeaking: voiceRef.current.speaking && !voiceRef.current.muted
        });
      }
    },
    []
  );

  const toggleVoice = useCallback(async () => {
    const mesh = voiceMeshRef.current;
    if (!mesh) {
      pushToast('Connect to scene WS first (voice needs WebSocket)', 'error');
      return;
    }
    try {
      if (voiceRef.current.enabled) {
        await mesh.disable();
        pushToast('Voice left', 'info');
      } else {
        await mesh.enable();
        mesh.syncPeers(presenceRef.current);
        pushToast('Voice joined — unmute peers hear you', 'success');
      }
    } catch (err) {
      pushToast(err instanceof Error ? err.message : 'Mic failed', 'error');
    }
  }, [pushToast]);

  const toggleMute = useCallback(() => {
    voiceMeshRef.current?.toggleMute();
  }, []);

  const addStroke = useCallback(
    (
      partial: Omit<DrawingStroke, 'sceneId' | 'actorId'> & {
        sceneId?: string;
        actorId?: string;
      }
    ) => {
      const current = sceneRef.current;
      if (!current) return;
      const stroke: DrawingStroke = {
        strokeId: partial.strokeId,
        sceneId: partial.sceneId ?? current.sceneId,
        actorId: partial.actorId ?? actorIdRef.current,
        color: partial.color ?? '#6ec8e8',
        width: partial.width ?? 0.02,
        points: partial.points,
        plane: partial.plane,
        createdAt: partial.createdAt ?? new Date().toISOString()
      };
      setStrokes((prev) => {
        if (prev.some((s) => s.strokeId === stroke.strokeId)) return prev;
        return [...prev, stroke];
      });
      const sock = socketRef.current;
      if (sock) sendDrawStroke(sock, stroke);
    },
    []
  );

  const clearOwnStrokes = useCallback(() => {
    const actor = actorIdRef.current;
    setStrokes((prev) => prev.filter((s) => s.actorId !== actor));
    const sock = socketRef.current;
    if (sock) sendDrawClear(sock, actor, 'own');
  }, []);

  const clearAllStrokes = useCallback(() => {
    setStrokes([]);
    const sock = socketRef.current;
    if (sock) sendDrawClear(sock, actorIdRef.current, 'all');
  }, []);

  const commitOps = useCallback(
    async (operations: SceneOperation[], opts?: { animate?: boolean; budget?: number }) => {
      const current = sceneRef.current;
      if (!current) return;
      pushHistory(current);
      setConnection('syncing');
      setIsBusy(true);

      // Optimistic local apply for MOVE/ROTATE/DELETE
      const optimistic = cloneScene(current);
      const byId = new Map(optimistic.objects.map((o) => [o.id, o]));
      for (const op of operations) {
        if (op.type === 'MOVE_OBJECT' && op.objectId && op.targetPosition) {
          const obj = byId.get(op.objectId);
          if (obj) obj.transform.position = [...op.targetPosition] as Vector3;
        } else if (op.type === 'ROTATE_OBJECT' && op.objectId && op.targetRotation) {
          const obj = byId.get(op.objectId);
          if (obj) obj.transform.rotation = [...op.targetRotation];
        } else if (op.type === 'DELETE_OBJECT' && op.objectId) {
          byId.delete(op.objectId);
          optimistic.objects = Array.from(byId.values());
        }
      }
      if (!opts?.animate) {
        setScene({ ...optimistic, objects: Array.from(byId.values()) });
      }

      try {
        const result = await postOperations(
          current.sceneId,
          {
            baseVersion: current.version,
            actorId: actorIdRef.current,
            opId: opId(),
            operations
          },
          opts?.budget
        );
        if (opts?.animate) {
          await animateToScene(current, result.scene);
        } else {
          setScene(result.scene);
          sceneRef.current = result.scene;
        }
        setConnection('connected');
        if (result.warnings?.length) {
          pushToast(result.warnings.join(' · '), 'info');
        }
      } catch (err) {
        // Rollback
        setScene(current);
        sceneRef.current = current;
        historyRef.current.pop();
        setHistoryDepth(historyRef.current.length);
        setConnection(err instanceof ApiError && err.status === 0 ? 'disconnected' : 'error');
        if (err instanceof ApiError && err.status === 409) {
          pushToast('Version conflict — reloading scene', 'error');
          await reload();
        } else {
          pushToast(err instanceof Error ? err.message : 'Operation failed', 'error');
        }
      } finally {
        setIsBusy(false);
      }
    },
    [animateToScene, pushHistory, pushToast, reload]
  );

  const applyLocalMove = useCallback(
    async (objectId: string, position: Vector3) => {
      await commitOps([
        { type: 'MOVE_OBJECT', objectId, targetPosition: position }
      ]);
    },
    [commitOps]
  );

  const applyLocalRotate = useCallback(
    async (objectId: string, rotation: [number, number, number, number]) => {
      await commitOps([
        { type: 'ROTATE_OBJECT', objectId, targetRotation: rotation }
      ]);
    },
    [commitOps]
  );

  const deleteSelected = useCallback(async () => {
    if (!selectedObjectId || !scene) return;
    const obj = scene.objects.find((o) => o.id === selectedObjectId);
    if (!obj || obj.movable === false) {
      pushToast('Cannot delete immovable object', 'error');
      return;
    }
    setSelectedObjectId(null);
    await commitOps([{ type: 'DELETE_OBJECT', objectId: selectedObjectId }]);
    pushToast(`Removed ${obj.type}`, 'success');
  }, [selectedObjectId, scene, commitOps, pushToast]);

  const requestLayout = useCallback(async () => {
    if (!scene) return;
    setIsBusy(true);
    setConnection('syncing');
    try {
      const payload: LayoutRequest = {
        sceneId: scene.sceneId,
        prompt,
        guestCount,
        budget: targetBudget
      };
      const layout = await postAiLayout(payload);
      setPendingLayout(layout);
      setConnection('connected');
      pushToast(`AI ready: ${layout.scenario}`, 'success');
    } catch (err) {
      setConnection('error');
      pushToast(err instanceof Error ? err.message : 'AI layout failed', 'error');
    } finally {
      setIsBusy(false);
    }
  }, [scene, prompt, guestCount, targetBudget, pushToast]);

  const acceptLayout = useCallback(async () => {
    if (!pendingLayout?.operations.length) {
      pushToast('No operations to accept', 'info');
      return;
    }
    const ops = pendingLayout.operations;
    const budget = pendingLayout.constraints.budget ?? targetBudget;
    setPendingLayout(null);
    await commitOps(ops, { animate: true, budget });
    pushToast('Layout applied', 'success');
  }, [pendingLayout, commitOps, targetBudget, pushToast]);

  const rejectLayout = useCallback(() => {
    setPendingLayout(null);
    pushToast('Layout discarded', 'info');
  }, [pushToast]);

  const addCatalogItem = useCallback(
    async (productId: string) => {
      const item = catalog.find((c) => c.productId === productId);
      if (!item || !scene) return;
      const dims = item.dimensions;
      const y = ((dims?.height ?? 0.5) / 2) || 0.25;
      await commitOps(
        [
          {
            type: 'ADD_OBJECT',
            objectId: `${productId}_${Date.now().toString(36)}`,
            objectType: item.category || item.name,
            productId: item.productId,
            assetId: item.assetId,
            source: 'catalog',
            targetPosition: [0, y, 0],
            dimensions: dims,
            movable: true
          }
        ],
        { budget: targetBudget }
      );
      pushToast(`Added ${item.name}`, 'success');
    },
    [catalog, scene, commitOps, targetBudget, pushToast]
  );

  const undo = useCallback(async () => {
    const prev = historyRef.current.pop();
    setHistoryDepth(historyRef.current.length);
    const current = sceneRef.current;
    if (!prev || !current) {
      pushToast('Nothing to undo', 'info');
      return;
    }
    // Rebuild by reloading then... better: rewind via reverse ops is hard.
    // Demo approach: POST a full reconcile by re-applying absolute positions from history snapshot.
    const ops: SceneOperation[] = [];
    const prevIds = new Set(prev.objects.map((o) => o.id));
    const currIds = new Set(current.objects.map((o) => o.id));

    for (const id of currIds) {
      if (!prevIds.has(id)) {
        ops.push({ type: 'DELETE_OBJECT', objectId: id });
      }
    }
    for (const obj of prev.objects) {
      if (!currIds.has(obj.id)) {
        ops.push({
          type: 'ADD_OBJECT',
          objectId: obj.id,
          objectType: obj.type,
          productId: obj.productId,
          assetId: obj.assetId,
          source: obj.source,
          targetPosition: obj.transform.position as Vector3,
          targetRotation: obj.transform.rotation,
          dimensions: obj.dimensions,
          movable: obj.movable
        });
      } else {
        const cur = current.objects.find((o) => o.id === obj.id)!;
        const posChanged =
          cur.transform.position[0] !== obj.transform.position[0] ||
          cur.transform.position[1] !== obj.transform.position[1] ||
          cur.transform.position[2] !== obj.transform.position[2];
        const rotChanged =
          cur.transform.rotation.some((v, i) => v !== obj.transform.rotation[i]);
        if (posChanged) {
          ops.push({
            type: 'MOVE_OBJECT',
            objectId: obj.id,
            targetPosition: obj.transform.position as Vector3
          });
        }
        if (rotChanged) {
          ops.push({
            type: 'ROTATE_OBJECT',
            objectId: obj.id,
            targetRotation: obj.transform.rotation
          });
        }
      }
    }

    if (!ops.length) {
      pushToast('Nothing to undo', 'info');
      return;
    }

    setIsBusy(true);
    setConnection('syncing');
    try {
      const result = await postOperations(current.sceneId, {
        baseVersion: current.version,
        actorId: actorIdRef.current,
        opId: opId(),
        operations: ops
      });
      await animateToScene(current, result.scene, 420);
      setConnection('connected');
      pushToast('Undone', 'success');
    } catch (err) {
      // restore history entry
      historyRef.current.push(prev);
      setHistoryDepth(historyRef.current.length);
      setConnection('error');
      if (err instanceof ApiError && err.status === 409) {
        pushToast('Version conflict — reloading', 'error');
        await reload();
      } else {
        pushToast(err instanceof Error ? err.message : 'Undo failed', 'error');
      }
    } finally {
      setIsBusy(false);
    }
  }, [animateToScene, pushToast, reload]);

  const checkout = useCallback(async () => {
    if (!scene) return;
    setIsBusy(true);
    try {
      const result = await postCheckout({
        sceneId: scene.sceneId,
        successUrl:
          typeof window !== 'undefined'
            ? `${window.location.origin}/?checkout=success`
            : undefined,
        cancelUrl:
          typeof window !== 'undefined'
            ? `${window.location.origin}/?checkout=cancel`
            : undefined
      });
      if (result.message) {
        pushToast(result.message, 'info');
      }
      if (result.checkoutUrl) {
        window.open(result.checkoutUrl, '_blank', 'noopener,noreferrer');
        pushToast(
          `Checkout ${result.mode}: $${result.amountTotal.toFixed(0)} (${result.lineItemCount} items)`,
          'success'
        );
      }
    } catch (err) {
      pushToast(err instanceof Error ? err.message : 'Checkout failed', 'error');
    } finally {
      setIsBusy(false);
    }
  }, [scene, pushToast]);

  const productMap = useMemo(() => {
    const map = new Map<string, CatalogItem>();
    for (const item of catalog) map.set(item.productId, item);
    return map;
  }, [catalog]);

  const budgetUsed = useMemo(() => {
    if (!scene) return 0;
    if (typeof scene.budgetUsed === 'number') return scene.budgetUsed;
    let total = 0;
    for (const obj of scene.objects) {
      if (obj.productId && productMap.has(obj.productId)) {
        total += productMap.get(obj.productId)!.price;
      }
    }
    return total;
  }, [scene, productMap]);

  const value: SceneStoreValue = {
    scene,
    catalog,
    connection,
    selectedObjectId,
    pendingLayout,
    targetBudget,
    guestCount,
    prompt,
    toasts,
    isBusy,
    canUndo: historyDepth > 0,
    animating,
    presence,
    actorId,
    voice,
    drawMode,
    strokes,
    setSelectedObjectId: setSelectedObjectIdWithLock,
    setPrompt,
    setTargetBudget,
    setGuestCount,
    reload,
    dismissToast,
    pushToast,
    applyLocalMove,
    applyLocalRotate,
    deleteSelected,
    requestLayout,
    acceptLayout,
    rejectLayout,
    addCatalogItem,
    checkout,
    undo,
    toggleVoice,
    toggleMute,
    setDrawMode,
    addStroke,
    clearOwnStrokes,
    clearAllStrokes,
    productMap,
    budgetUsed
  };

  return (
    <SceneStoreContext.Provider value={value}>{children}</SceneStoreContext.Provider>
  );
}

export function useSceneStore(): SceneStoreValue {
  const ctx = useContext(SceneStoreContext);
  if (!ctx) throw new Error('useSceneStore must be used within SceneStoreProvider');
  return ctx;
}
