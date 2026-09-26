/**
 * WebSocket client for FastAPI `/ws/scene/{sceneId}`.
 * Server types: welcome | presence | scene | patch | lock | pong | error
 *           | rtc_offer | rtc_answer | rtc_ice | draw_stroke | draw_clear
 *           | intent_open | intent_close | intent_draft | intent_idea
 * Client types: join | leave | presence | ping | lock | unlock
 *           | rtc_offer | rtc_answer | rtc_ice | draw_stroke | draw_clear
 *           | intent_open | intent_close | intent_draft | intent_idea
 * Enabled by default; set NEXT_PUBLIC_SCENE_WS=0 to disable.
 */

import type { DrawingStroke, PresenceUser } from '@shared-spatial-ai/schema';

export type { PresenceUser };

export type IntentDraftPayload = {
  actorId?: string | null;
  displayName?: string | null;
  scenario?: string | null;
  prompt?: string | null;
  guestCount?: number | null;
  budget?: number | null;
};

export type IntentIdeaPayload = {
  ideaId: string;
  sceneId: string;
  actorId: string;
  displayName?: string | null;
  text: string;
  createdAt?: string | null;
};

export type SceneSocketMessage = {
  type:
    | 'welcome'
    | 'presence'
    | 'scene'
    | 'patch'
    | 'lock'
    | 'pong'
    | 'error'
    | 'rtc_offer'
    | 'rtc_answer'
    | 'rtc_ice'
    | 'draw_stroke'
    | 'draw_clear'
    | 'draw_snapshot'
    | 'intent_open'
    | 'intent_close'
    | 'intent_draft'
    | 'intent_idea'
    | 'intent_snapshot'
    | 'timeline'
    | 'disagreement'
    | string;
  sceneId?: string;
  version?: number;
  fromVersion?: number;
  toVersion?: number;
  scene?: unknown;
  presence?: PresenceUser[];
  operations?: unknown[];
  message?: string;
  strokes?: DrawingStroke[];
  stroke?: DrawingStroke;
  scope?: 'own' | 'all';
  actorId?: string;
  removedStrokeIds?: string[];
  fromUserId?: string;
  toUserId?: string;
  sdp?: RTCSessionDescriptionInit;
  candidate?: RTCIceCandidateInit | null;
  intentOpen?: boolean;
  draft?: IntentDraftPayload | null;
  idea?: IntentIdeaPayload;
  ideas?: IntentIdeaPayload[];
  timeline?: unknown[];
  entry?: unknown;
  disagreement?: unknown;
  payload?: {
    ok?: boolean;
    objectId?: string;
    lockedBy?: string | null;
    lockedUntil?: string | null;
    message?: string;
    scene?: unknown;
    [key: string]: unknown;
  };
};

export type SceneSocketHandlers = {
  onMessage?: (msg: SceneSocketMessage) => void;
  onOpen?: () => void;
  onClose?: () => void;
  onError?: (err: Event) => void;
};

function wsFlag(): boolean {
  const raw = process.env.NEXT_PUBLIC_SCENE_WS;
  if (raw === '0' || raw === 'false') return false;
  return true;
}

function httpToWs(base: string): string {
  if (base.startsWith('https://')) return `wss://${base.slice('https://'.length)}`;
  if (base.startsWith('http://')) return `ws://${base.slice('http://'.length)}`;
  return base;
}

export function createSceneSocket(
  apiBaseUrl: string,
  sceneId: string,
  handlers: SceneSocketHandlers = {}
): WebSocket | null {
  if (!wsFlag()) return null;

  const url = `${httpToWs(apiBaseUrl.replace(/\/$/, ''))}/ws/scene/${encodeURIComponent(sceneId)}`;
  try {
    const socket = new WebSocket(url);
    socket.addEventListener('open', () => handlers.onOpen?.());
    socket.addEventListener('close', () => handlers.onClose?.());
    socket.addEventListener('error', (ev) => handlers.onError?.(ev));
    socket.addEventListener('message', (ev) => {
      try {
        const parsed = JSON.parse(String(ev.data)) as SceneSocketMessage;
        handlers.onMessage?.(parsed);
      } catch {
        // ignore malformed frames
      }
    });
    return socket;
  } catch {
    return null;
  }
}

export function isSceneWsEnabled(): boolean {
  return wsFlag();
}

function sendJson(socket: WebSocket, payload: Record<string, unknown>): void {
  if (socket.readyState !== WebSocket.OPEN) return;
  socket.send(JSON.stringify(payload));
}

export type PresencePayload = {
  userId: string;
  displayName: string;
  color?: string;
  selectedObjectId?: string | null;
  voiceEnabled?: boolean;
  voiceSpeaking?: boolean;
  /** Ghost standing point (Y-up meters). */
  position?: [number, number, number] | null;
  /** Optional look / facing direction. */
  lookDirection?: [number, number, number] | null;
};

function presenceUserBody(user: PresencePayload): Record<string, unknown> {
  const body: Record<string, unknown> = {
    userId: user.userId,
    displayName: user.displayName,
    color: user.color,
    selectedObjectId: user.selectedObjectId ?? null,
    voiceEnabled: user.voiceEnabled ?? false,
    voiceSpeaking: user.voiceSpeaking ?? false
  };
  if (user.position) body.position = user.position;
  if (user.lookDirection) body.lookDirection = user.lookDirection;
  return body;
}

export function sendSceneJoin(socket: WebSocket, user: PresencePayload): void {
  sendJson(socket, {
    type: 'join',
    user: presenceUserBody(user)
  });
}

export function sendScenePresence(socket: WebSocket, user: PresencePayload): void {
  sendJson(socket, {
    type: 'presence',
    user: presenceUserBody(user)
  });
}

export function sendSceneLock(
  socket: WebSocket,
  objectId: string,
  actorId: string,
  ttlSeconds?: number
): void {
  sendJson(socket, {
    type: 'lock',
    objectId,
    actorId,
    ...(ttlSeconds != null ? { ttlSeconds } : {})
  });
}

export function sendSceneUnlock(
  socket: WebSocket,
  objectId: string,
  actorId: string
): void {
  sendJson(socket, {
    type: 'unlock',
    objectId,
    actorId
  });
}

export function sendRtcOffer(
  socket: WebSocket,
  fromUserId: string,
  toUserId: string,
  sdp: RTCSessionDescriptionInit
): void {
  sendJson(socket, { type: 'rtc_offer', fromUserId, toUserId, sdp });
}

export function sendRtcAnswer(
  socket: WebSocket,
  fromUserId: string,
  toUserId: string,
  sdp: RTCSessionDescriptionInit
): void {
  sendJson(socket, { type: 'rtc_answer', fromUserId, toUserId, sdp });
}

export function sendRtcIce(
  socket: WebSocket,
  fromUserId: string,
  toUserId: string,
  candidate: RTCIceCandidateInit | null
): void {
  sendJson(socket, { type: 'rtc_ice', fromUserId, toUserId, candidate });
}

export function sendDrawStroke(socket: WebSocket, stroke: DrawingStroke): void {
  sendJson(socket, { type: 'draw_stroke', stroke });
}

export function sendDrawClear(
  socket: WebSocket,
  actorId: string,
  scope: 'own' | 'all' = 'own'
): void {
  sendJson(socket, { type: 'draw_clear', actorId, scope });
}

export function sendIntentOpen(
  socket: WebSocket,
  draft: IntentDraftPayload
): void {
  sendJson(socket, { type: 'intent_open', draft });
}

export function sendIntentClose(socket: WebSocket, actorId?: string): void {
  sendJson(socket, { type: 'intent_close', actorId });
}

export function sendIntentDraft(
  socket: WebSocket,
  draft: IntentDraftPayload
): void {
  sendJson(socket, { type: 'intent_draft', draft });
}

export function sendIntentIdea(
  socket: WebSocket,
  idea: IntentIdeaPayload
): void {
  sendJson(socket, { type: 'intent_idea', idea });
}
