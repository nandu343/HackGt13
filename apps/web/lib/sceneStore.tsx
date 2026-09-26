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
  DisagreementSchema,
  DrawingStrokeSchema,
  SceneSchema,
  TimelineEntrySchema,
  type CatalogItem,
  type Disagreement,
  type DrawingStroke,
  type LayoutRequest,
  type LayoutResponse,
  type PresenceUser,
  type Scene,
  type SceneObject,
  type SceneOperation,
  type TimelineEntry,
  type Vector3
} from '@shared-spatial-ai/schema';
import {
  ApiError,
  fetchCatalog,
  fetchDisagreement,
  fetchHealth,
  fetchScene,
  fetchTimeline,
  getApiBaseUrl,
  postAiLayout,
  postCheckout,
  postDisagreement,
  postDisagreementCompromise,
  postDisagreementCounter,
  postDisagreementResolve,
  postOperations,
  postTimelineBranch,
  postTimelineRestore
} from './api';
import { blendScenes } from './lerp';
import { canManipulateObject } from './objectPolicy';
import { VoiceMesh, type VoiceState } from './voiceMesh';
import {
  createSceneSocket,
  isSceneWsEnabled,
  sendDrawClear,
  sendDrawStroke,
  sendIntentDraft,
  sendIntentIdea,
  sendIntentOpen,
  sendSceneJoin,
  sendSceneLock,
  sendScenePresence,
  sendSceneUnlock,
  type IntentDraftPayload,
  type IntentIdeaPayload
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

/** Stable pastel-ish chip color from actor id (distinct per browser tab). */
function colorFromId(id: string): string {
  let h = 216;
  for (let i = 0; i < id.length; i++) {
    h = (h * 31 + id.charCodeAt(i)) >>> 0;
  }
  const hue = h % 360;
  return `hsl(${hue} 52% 58%)`;
}

function intentSeenKey(sceneId: string): string {
  return `ssa_intent_seen_${sceneId}`;
}

const DISPLAY_NAME_KEY = 'ssa_display_name';

function resolveDisplayName(actorId: string): string {
  if (typeof window === 'undefined') return 'Guest';
  try {
    const saved = localStorage.getItem(DISPLAY_NAME_KEY)?.trim();
    if (saved) return saved.slice(0, 40);
  } catch {
    // ignore
  }
  return `Web ${actorId.replace(/^web_/, '').slice(0, 4) || 'demo'}`;
}

function persistDisplayName(name: string): void {
  try {
    localStorage.setItem(DISPLAY_NAME_KEY, name.slice(0, 40));
  } catch {
    // ignore
  }
}


export type IntentIdea = IntentIdeaPayload;

export type IntentDraft = IntentDraftPayload;

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
  displayName: string;
  setDisplayName: (name: string) => void;
  voice: VoiceState;
  drawMode: boolean;
  strokes: DrawingStroke[];
  intentModalOpen: boolean;
  intentIdeas: IntentIdea[];
  intentDraft: IntentDraft | null;
  intentSessionActive: boolean;
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
  requestLayout: (overrides?: {
    prompt?: string;
    guestCount?: number;
    budget?: number;
  }) => Promise<void>;
  acceptLayout: () => Promise<void>;
  rejectLayout: () => void;
  timeline: TimelineEntry[];
  disagreement: Disagreement | null;
  disagreementView: 'both' | 'A' | 'B' | 'live';
  compromisePicks: Record<string, 'A' | 'B'>;
  ghostObjectsA: SceneObject[];
  ghostObjectsB: SceneObject[];
  proposeDisagreement: () => Promise<void>;
  counterDisagreement: () => Promise<void>;
  compromiseDisagreement: (mode: 'blend' | 'picks' | 'a' | 'b') => Promise<void>;
  cancelDisagreement: () => Promise<void>;
  setDisagreementView: (v: 'both' | 'A' | 'B' | 'live') => void;
  setCompromisePick: (objectId: string, side: 'A' | 'B') => void;
  restoreTimelineEntry: (entryId: string) => Promise<void>;
  branchTimelineEntry: (entryId: string, name: string) => Promise<void>;
  addCatalogItem: (productId: string) => Promise<void>;
  checkout: () => Promise<void>;
  undo: () => Promise<void>;
  toggleVoice: () => Promise<void>;
  toggleMute: () => void;
  setDrawMode: (on: boolean) => void;
  addStroke: (stroke: Omit<DrawingStroke, 'sceneId' | 'actorId'> & { sceneId?: string; actorId?: string }) => void;
  clearOwnStrokes: () => void;
  clearAllStrokes: () => void;
  openIntentModal: () => void;
  closeIntentModal: () => void;
  broadcastIntentDraft: (draft: Partial<IntentDraft>) => void;
  addIntentIdea: (text: string) => void;
  markIntentSeen: () => void;
  /** Broadcast local camera/orbit focus as ghost presence (throttled by caller). */
  reportPresencePose: (
    position: Vector3,
    lookDirection?: Vector3 | null
  ) => void;
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
  const [displayName, setDisplayNameState] = useState(() =>
    resolveDisplayName(resolveActorId())
  );
  const [voice, setVoice] = useState<VoiceState>({
    enabled: false,
    muted: true,
    speaking: false,
    error: null
  });
  const [drawMode, setDrawMode] = useState(false);
  const [strokes, setStrokes] = useState<DrawingStroke[]>([]);
  const [intentModalOpen, setIntentModalOpen] = useState(false);
  const [intentIdeas, setIntentIdeas] = useState<IntentIdea[]>([]);
  const [intentDraft, setIntentDraft] = useState<IntentDraft | null>(null);
  const [intentSessionActive, setIntentSessionActive] = useState(false);
  const [timeline, setTimeline] = useState<TimelineEntry[]>([]);
  const [disagreement, setDisagreement] = useState<Disagreement | null>(null);
  const [disagreementView, setDisagreementView] = useState<
    'both' | 'A' | 'B' | 'live'
  >('both');
  const [compromisePicks, setCompromisePicks] = useState<Record<string, 'A' | 'B'>>(
    {}
  );
  const historyRef = useRef<Scene[]>([]);
  const sceneRef = useRef<Scene | null>(null);
  const toastSeq = useRef(0);
  const animFrameRef = useRef<number | null>(null);
  const socketRef = useRef<WebSocket | null>(null);
  const selectedRef = useRef<string | null>(null);
  const actorIdRef = useRef(actorId);
  const displayNameRef = useRef(displayName);
  const voiceRef = useRef(voice);
  const voiceMeshRef = useRef<VoiceMesh | null>(null);
  const presenceRef = useRef<PresenceUser[]>([]);
  const poseRef = useRef<{
    position: Vector3 | null;
    lookDirection: Vector3 | null;
  }>({ position: null, lookDirection: null });
  const intentAutoOpenedRef = useRef(false);
  const draftTimerRef = useRef<number | null>(null);

  const actorColor = useMemo(() => colorFromId(actorId), [actorId]);

  const setDisplayName = useCallback((name: string) => {
    const next = (name.trim() || 'Guest').slice(0, 40);
    setDisplayNameState(next);
    persistDisplayName(next);
    displayNameRef.current = next;
    const sock = socketRef.current;
    if (sock) {
      sendScenePresence(sock, {
        userId: actorIdRef.current,
        displayName: next,
        color: actorColor,
        selectedObjectId: selectedRef.current,
        voiceEnabled: voiceRef.current.enabled,
        voiceSpeaking: voiceRef.current.speaking && !voiceRef.current.muted,
        position: poseRef.current.position ?? undefined,
        lookDirection: poseRef.current.lookDirection ?? undefined
      });
    }
  }, [actorColor]);

  const buildPresencePayload = useCallback(
    (overrides?: {
      selectedObjectId?: string | null;
      voiceSpeaking?: boolean;
      position?: Vector3 | null;
      lookDirection?: Vector3 | null;
    }) => {
      const pos =
        overrides?.position !== undefined
          ? overrides.position
          : poseRef.current.position;
      const look =
        overrides?.lookDirection !== undefined
          ? overrides.lookDirection
          : poseRef.current.lookDirection;
      return {
        userId: actorIdRef.current,
        displayName: displayNameRef.current,
        color: actorColor,
        selectedObjectId:
          overrides?.selectedObjectId !== undefined
            ? overrides.selectedObjectId
            : selectedRef.current,
        voiceEnabled: voiceRef.current.enabled,
        voiceSpeaking:
          overrides?.voiceSpeaking ??
          (voiceRef.current.speaking && !voiceRef.current.muted),
        position: pos ?? undefined,
        lookDirection: look ?? undefined
      };
    },
    [actorColor]
  );

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
    displayNameRef.current = displayName;
  }, [displayName]);

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
      const [nextScene, nextCatalog, nextTimeline, nextDisagreement] =
        await Promise.all([
          fetchScene(sceneId),
          fetchCatalog(),
          fetchTimeline(sceneId).catch(() => null),
          fetchDisagreement(sceneId).catch(() => null)
        ]);
      setScene(nextScene);
      sceneRef.current = nextScene;
      setCatalog(nextCatalog);
      if (nextTimeline) setTimeline(nextTimeline.entries);
      setDisagreement(
        nextDisagreement &&
          (nextDisagreement.status === 'open' ||
            nextDisagreement.status === 'countered')
          ? nextDisagreement
          : null
      );
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

  const applyIntentSnapshot = useCallback(
    (msg: {
      intentOpen?: boolean;
      draft?: IntentDraft | null;
      ideas?: IntentIdea[];
      idea?: IntentIdea;
    }) => {
      if (typeof msg.intentOpen === 'boolean') {
        setIntentSessionActive(msg.intentOpen);
      }
      if (msg.draft !== undefined) {
        setIntentDraft(msg.draft);
      }
      if (Array.isArray(msg.ideas)) {
        setIntentIdeas(msg.ideas);
      } else if (msg.idea) {
        setIntentIdeas((prev) => {
          if (prev.some((i) => i.ideaId === msg.idea!.ideaId)) return prev;
          return [...prev, msg.idea!];
        });
      }
    },
    []
  );

  // First load after scan / demo room: primary intent modal (once per browser)
  useEffect(() => {
    if (!scene || connection === 'error' || connection === 'connecting') return;
    if (intentAutoOpenedRef.current) return;
    intentAutoOpenedRef.current = true;
    let seen = false;
    try {
      seen = Boolean(localStorage.getItem(intentSeenKey(sceneId)));
    } catch {
      seen = false;
    }
    if (!seen) {
      setIntentModalOpen(true);
      setIntentSessionActive(true);
    }
  }, [scene, connection, sceneId]);

  // Broadcast intent_open once WS is up and modal is showing (first-time + re-open)
  useEffect(() => {
    if (!intentModalOpen) return;
    if (connection !== 'connected' && connection !== 'syncing') return;
    const sock = socketRef.current;
    if (!sock || sock.readyState !== WebSocket.OPEN) return;
    sendIntentOpen(sock, {
      actorId: actorIdRef.current,
      displayName: displayNameRef.current,
      prompt,
      guestCount,
      budget: targetBudget
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps -- only on open / reconnect
  }, [intentModalOpen, connection]);

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
      () => buildPresencePayload(),
      setVoice
    );
    voiceMeshRef.current = mesh;

    const socket = createSceneSocket(getApiBaseUrl(), sceneId, {
      onOpen: () => {
        if (closed) return;
        setConnection('connected');
        sendSceneJoin(socket!, buildPresencePayload({ voiceSpeaking: false }));
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
          applyIntentSnapshot({
            intentOpen: msg.intentOpen,
            draft: msg.draft ?? null,
            ideas: msg.ideas
          });
          if (msg.intentOpen) {
            setIntentModalOpen(true);
          }
          if (Array.isArray(msg.timeline)) {
            const parsed: TimelineEntry[] = [];
            for (const raw of msg.timeline) {
              try {
                parsed.push(TimelineEntrySchema.parse(raw));
              } catch {
                // skip
              }
            }
            setTimeline(parsed);
          }
          if (msg.disagreement !== undefined) {
            if (msg.disagreement == null) {
              setDisagreement(null);
            } else {
              try {
                const d = DisagreementSchema.parse(msg.disagreement);
                setDisagreement(
                  d.status === 'open' || d.status === 'countered' ? d : null
                );
              } catch {
                // ignore
              }
            }
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
        if (
          msg.type === 'intent_open' ||
          msg.type === 'intent_close' ||
          msg.type === 'intent_draft' ||
          msg.type === 'intent_idea' ||
          msg.type === 'intent_snapshot'
        ) {
          applyIntentSnapshot({
            intentOpen: msg.intentOpen,
            draft: msg.draft,
            ideas: msg.ideas,
            idea: msg.idea
          });
          if (msg.type === 'intent_open' && msg.actorId !== actorIdRef.current) {
            setIntentModalOpen(true);
            pushToast('A friend opened Plan with friends', 'info');
          }
          if (msg.type === 'intent_idea' && msg.idea?.actorId !== actorIdRef.current) {
            pushToast(`Idea from ${msg.idea?.displayName || 'friend'}`, 'info');
          }
          return;
        }
        if (msg.type === 'timeline') {
          if (Array.isArray(msg.timeline)) {
            const parsed: TimelineEntry[] = [];
            for (const raw of msg.timeline) {
              try {
                parsed.push(TimelineEntrySchema.parse(raw));
              } catch {
                // skip
              }
            }
            setTimeline(parsed);
          } else if (msg.entry) {
            try {
              const entry = TimelineEntrySchema.parse(msg.entry);
              setTimeline((prev) => {
                if (prev.some((e) => e.entryId === entry.entryId)) return prev;
                return [...prev, entry];
              });
            } catch {
              // ignore
            }
          }
          return;
        }
        if (msg.type === 'disagreement') {
          if (msg.disagreement == null) {
            setDisagreement(null);
            return;
          }
          try {
            const d = DisagreementSchema.parse(msg.disagreement);
            if (d.status === 'open' || d.status === 'countered') {
              setDisagreement(d);
              if (d.proposalA.actorId !== actorIdRef.current) {
                pushToast('Layout disagreement opened', 'info');
              }
            } else {
              setDisagreement(null);
              if (d.status === 'resolved') {
                pushToast('Disagreement resolved', 'success');
              }
            }
          } catch {
            // ignore
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
  }, [sceneId, connection === 'error', pushToast, applyIntentSnapshot, buildPresencePayload]);

  const reportPresencePose = useCallback(
    (position: Vector3, lookDirection?: Vector3 | null) => {
      poseRef.current = {
        position,
        lookDirection: lookDirection ?? poseRef.current.lookDirection
      };
      const sock = socketRef.current;
      if (!sock || sock.readyState !== WebSocket.OPEN) return;
      sendScenePresence(
        sock,
        buildPresencePayload({
          position,
          lookDirection: lookDirection ?? poseRef.current.lookDirection
        })
      );
    },
    [buildPresencePayload]
  );

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
        sendScenePresence(sock, buildPresencePayload({ selectedObjectId: id }));
      }
    },
    [buildPresencePayload]
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
    async (
      operations: SceneOperation[],
      opts?: { animate?: boolean; budget?: number; label?: string }
    ) => {
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
            label: opts?.label,
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
    if (!obj || !canManipulateObject(obj)) {
      pushToast('Walls stay fixed — pick furniture to clear', 'error');
      return;
    }
    const id = selectedObjectId;
    setSelectedObjectId(null);
    await commitOps([{ type: 'DELETE_OBJECT', objectId: id }]);
    pushToast(
      obj.source === 'existing'
        ? `Cleared ${obj.type.replace(/_/g, ' ')} out of the way`
        : `Removed ${obj.type.replace(/_/g, ' ')}`,
      'success'
    );
  }, [selectedObjectId, scene, commitOps, pushToast]);

  const requestLayout = useCallback(
    async (overrides?: { prompt?: string; guestCount?: number; budget?: number }) => {
      if (!scene) return;
      const nextPrompt = overrides?.prompt ?? prompt;
      const nextGuests = overrides?.guestCount ?? guestCount;
      const nextBudget = overrides?.budget ?? targetBudget;
      if (overrides?.prompt != null) setPrompt(overrides.prompt);
      if (overrides?.guestCount != null) setGuestCount(overrides.guestCount);
      if (overrides?.budget != null) setTargetBudget(overrides.budget);
      setIsBusy(true);
      setConnection('syncing');
      try {
        const payload: LayoutRequest = {
          sceneId: scene.sceneId,
          prompt: nextPrompt,
          guestCount: nextGuests,
          budget: nextBudget
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
    },
    [scene, prompt, guestCount, targetBudget, pushToast]
  );

  const markIntentSeen = useCallback(() => {
    try {
      localStorage.setItem(intentSeenKey(sceneId), '1');
    } catch {
      // ignore
    }
  }, [sceneId]);

  const openIntentModal = useCallback(() => {
    setIntentModalOpen(true);
    setIntentSessionActive(true);
  }, []);

  const closeIntentModal = useCallback(() => {
    // Local dismiss only — keep friends' session alive unless they close too.
    setIntentModalOpen(false);
  }, []);

  const broadcastIntentDraft = useCallback((partial: Partial<IntentDraft>) => {
    const draft: IntentDraft = {
      actorId: actorIdRef.current,
      displayName: displayNameRef.current,
      scenario: partial.scenario ?? null,
      prompt: partial.prompt ?? null,
      guestCount: partial.guestCount ?? null,
      budget: partial.budget ?? null
    };
    setIntentDraft(draft);
    if (draftTimerRef.current != null) {
      window.clearTimeout(draftTimerRef.current);
    }
    draftTimerRef.current = window.setTimeout(() => {
      const sock = socketRef.current;
      if (sock) sendIntentDraft(sock, draft);
    }, 220);
  }, []);

  const addIntentIdea = useCallback(
    (text: string) => {
      const trimmed = text.trim();
      if (!trimmed || !scene) return;
      const idea: IntentIdea = {
        ideaId: `idea_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 6)}`,
        sceneId: scene.sceneId,
        actorId: actorIdRef.current,
        displayName: displayNameRef.current,
        text: trimmed.slice(0, 280),
        createdAt: new Date().toISOString()
      };
      setIntentIdeas((prev) => {
        if (prev.some((i) => i.ideaId === idea.ideaId)) return prev;
        return [...prev, idea];
      });
      const sock = socketRef.current;
      if (sock) sendIntentIdea(sock, idea);
    },
    [scene]
  );

  const acceptLayout = useCallback(async () => {
    if (!pendingLayout?.operations.length) {
      pushToast('No operations to accept', 'info');
      return;
    }
    const ops = pendingLayout.operations;
    const budget = pendingLayout.constraints.budget ?? targetBudget;
    const scenario = pendingLayout.scenario;
    setPendingLayout(null);
    await commitOps(ops, {
      animate: true,
      budget,
      label: `AI accept · ${scenario}`
    });
    pushToast('Layout applied', 'success');
  }, [pendingLayout, commitOps, targetBudget, pushToast]);

  const rejectLayout = useCallback(() => {
    setPendingLayout(null);
    pushToast('Layout discarded', 'info');
  }, [pushToast]);

  const proposeDisagreement = useCallback(async () => {
    if (!scene || !pendingLayout?.operations.length) {
      pushToast('Generate a layout first, then Propose', 'info');
      return;
    }
    setIsBusy(true);
    try {
      if (disagreement && (disagreement.status === 'open' || disagreement.status === 'countered')) {
        const updated = await postDisagreementCounter(
          scene.sceneId,
          disagreement.disagreementId,
          {
            actorId: actorIdRef.current,
            displayName: displayName,
            label: `Alt · ${pendingLayout.scenario}`,
            operations: pendingLayout.operations
          }
        );
        setDisagreement(updated);
        setPendingLayout(null);
        pushToast('Counter-proposal sent', 'success');
      } else {
        const created = await postDisagreement(scene.sceneId, {
          actorId: actorIdRef.current,
          displayName: displayName,
          label: `Proposal · ${pendingLayout.scenario}`,
          operations: pendingLayout.operations,
          baseVersion: scene.version
        });
        setDisagreement(created);
        setPendingLayout(null);
        setDisagreementView('both');
        pushToast('Proposed for disagreement — open a 2nd tab', 'success');
      }
    } catch (err) {
      pushToast(err instanceof Error ? err.message : 'Propose failed', 'error');
    } finally {
      setIsBusy(false);
    }
  }, [scene, pendingLayout, disagreement, displayName, pushToast]);

  const counterDisagreement = useCallback(async () => {
    await proposeDisagreement();
  }, [proposeDisagreement]);

  const setCompromisePick = useCallback((objectId: string, side: 'A' | 'B') => {
    setCompromisePicks((prev) => ({ ...prev, [objectId]: side }));
  }, []);

  const compromiseDisagreement = useCallback(
    async (mode: 'blend' | 'picks' | 'a' | 'b') => {
      if (!scene || !disagreement) return;
      setIsBusy(true);
      try {
        const result = await postDisagreementCompromise(
          scene.sceneId,
          disagreement.disagreementId,
          {
            actorId: actorIdRef.current,
            displayName: displayName,
            mode,
            picks: mode === 'picks' ? compromisePicks : undefined
          }
        );
        pushHistory(scene);
        await animateToScene(scene, result.scene);
        setDisagreement(null);
        setCompromisePicks({});
        setConnection('connected');
        pushToast(
          mode === 'blend'
            ? 'Compromise blended'
            : mode === 'picks'
              ? 'Compromise applied (picks)'
              : `Accepted proposal ${mode.toUpperCase()}`,
          'success'
        );
      } catch (err) {
        pushToast(err instanceof Error ? err.message : 'Compromise failed', 'error');
      } finally {
        setIsBusy(false);
      }
    },
    [
      scene,
      disagreement,
      compromisePicks,
      displayName,
      animateToScene,
      pushHistory,
      pushToast
    ]
  );

  const cancelDisagreement = useCallback(async () => {
    if (!scene || !disagreement) return;
    setIsBusy(true);
    try {
      await postDisagreementResolve(scene.sceneId, disagreement.disagreementId, {
        actorId: actorIdRef.current,
        choice: 'cancel',
        displayName: displayName
      });
      setDisagreement(null);
      setCompromisePicks({});
      pushToast('Disagreement cancelled', 'info');
    } catch (err) {
      pushToast(err instanceof Error ? err.message : 'Cancel failed', 'error');
    } finally {
      setIsBusy(false);
    }
  }, [scene, disagreement, displayName, pushToast]);

  const restoreTimelineEntry = useCallback(
    async (entryId: string) => {
      if (!scene) return;
      setIsBusy(true);
      setConnection('syncing');
      try {
        pushHistory(scene);
        const result = await postTimelineRestore(scene.sceneId, {
          entryId,
          actorId: actorIdRef.current,
          displayName: displayName
        });
        await animateToScene(scene, result.scene, 520);
        setConnection('connected');
        pushToast('Restored timeline point', 'success');
      } catch (err) {
        setConnection('error');
        pushToast(err instanceof Error ? err.message : 'Restore failed', 'error');
      } finally {
        setIsBusy(false);
      }
    },
    [scene, displayName, animateToScene, pushHistory, pushToast]
  );

  const branchTimelineEntry = useCallback(
    async (entryId: string, name: string) => {
      if (!scene) return;
      const trimmed = name.trim();
      if (!trimmed) {
        pushToast('Enter a branch name', 'info');
        return;
      }
      setIsBusy(true);
      try {
        const result = await postTimelineBranch(scene.sceneId, {
          entryId,
          name: trimmed,
          actorId: actorIdRef.current,
          displayName: displayName
        });
        pushToast(
          `Branch “${trimmed}” → ${result.branchSceneId} (open ?scene=…)`,
          'success'
        );
        if (typeof window !== 'undefined') {
          const url = new URL(window.location.href);
          url.searchParams.set('scene', result.branchSceneId);
          window.open(url.toString(), '_blank', 'noopener,noreferrer');
        }
      } catch (err) {
        pushToast(err instanceof Error ? err.message : 'Branch failed', 'error');
      } finally {
        setIsBusy(false);
      }
    },
    [scene, displayName, pushToast]
  );

  const ghostObjectsA = useMemo(() => {
    if (!disagreement?.proposalA.scene) return [];
    if (disagreementView === 'B' || disagreementView === 'live') return [];
    return disagreement.proposalA.scene.objects;
  }, [disagreement, disagreementView]);

  const ghostObjectsB = useMemo(() => {
    if (!disagreement?.proposalB?.scene) return [];
    if (disagreementView === 'A' || disagreementView === 'live') return [];
    return disagreement.proposalB.scene.objects;
  }, [disagreement, disagreementView]);

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
        label: 'Undo',
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
    displayName,
    setDisplayName,
    voice,
    drawMode,
    strokes,
    intentModalOpen,
    intentIdeas,
    intentDraft,
    intentSessionActive,
    timeline,
    disagreement,
    disagreementView,
    compromisePicks,
    ghostObjectsA,
    ghostObjectsB,
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
    proposeDisagreement,
    counterDisagreement,
    compromiseDisagreement,
    cancelDisagreement,
    setDisagreementView,
    setCompromisePick,
    restoreTimelineEntry,
    branchTimelineEntry,
    addCatalogItem,
    checkout,
    undo,
    toggleVoice,
    toggleMute,
    setDrawMode,
    addStroke,
    clearOwnStrokes,
    clearAllStrokes,
    openIntentModal,
    closeIntentModal,
    broadcastIntentDraft,
    addIntentIdea,
    markIntentSeen,
    reportPresencePose,
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
