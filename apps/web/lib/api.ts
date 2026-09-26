import {
  CartSummarySchema,
  CatalogItemSchema,
  CheckoutResponseSchema,
  DisagreementSchema,
  LayoutRequestSchema,
  LayoutResponseSchema,
  OperationsResultSchema,
  SceneInviteListSchema,
  SceneInviteResolveSchema,
  SceneInviteSchema,
  SceneSchema,
  TimelineBranchResultSchema,
  TimelineListSchema,
  type CartSummary,
  type CatalogItem,
  type CheckoutRequest,
  type CheckoutResponse,
  type Disagreement,
  type LayoutRequest,
  type LayoutResponse,
  type OperationEnvelope,
  type OperationsResult,
  type Scene,
  type SceneInvite,
  type SceneInviteList,
  type SceneInviteResolve,
  type SceneOperation,
  type TimelineBranchResult,
  type TimelineList
} from '@shared-spatial-ai/schema';

// Prefer 127.0.0.1 over "localhost" — on Windows, localhost often resolves to ::1
// while uvicorn --host 127.0.0.1 is IPv4-only, which makes the browser see "API unreachable".
const API_URL = (process.env.NEXT_PUBLIC_API_URL || 'http://127.0.0.1:8000').replace(/\/$/, '');

export class ApiError extends Error {
  status: number;
  body: unknown;

  constructor(message: string, status: number, body?: unknown) {
    super(message);
    this.name = 'ApiError';
    this.status = status;
    this.body = body;
  }
}

async function request<T>(
  path: string,
  init?: RequestInit,
  parse?: (data: unknown) => T
): Promise<T> {
  let res: Response;
  try {
    res = await fetch(`${API_URL}${path}`, {
      ...init,
      headers: {
        'Content-Type': 'application/json',
        ...(init?.headers || {})
      }
    });
  } catch (err) {
    throw new ApiError(
      err instanceof Error ? err.message : 'Network error',
      0,
      err
    );
  }

  const text = await res.text();
  let data: unknown = null;
  if (text) {
    try {
      data = JSON.parse(text);
    } catch {
      data = text;
    }
  }

  if (!res.ok) {
    const detail =
      typeof data === 'object' && data && 'detail' in data
        ? JSON.stringify((data as { detail: unknown }).detail)
        : text || res.statusText;
    throw new ApiError(detail || `HTTP ${res.status}`, res.status, data);
  }

  return parse ? parse(data) : (data as T);
}

export function getApiBaseUrl(): string {
  return API_URL;
}

export async function fetchHealth(): Promise<{ status: string }> {
  return request('/health');
}

export async function fetchScene(sceneId: string): Promise<Scene> {
  return request(`/scene/${encodeURIComponent(sceneId)}`, undefined, (data) =>
    SceneSchema.parse(data)
  );
}

export async function postOperations(
  sceneId: string,
  envelope: OperationEnvelope,
  budget?: number
): Promise<OperationsResult> {
  const qs =
    budget != null && Number.isFinite(budget) ? `?budget=${encodeURIComponent(String(budget))}` : '';
  return request(
    `/scene/${encodeURIComponent(sceneId)}/operations${qs}`,
    {
      method: 'POST',
      body: JSON.stringify(envelope)
    },
    (data) => OperationsResultSchema.parse(data)
  );
}

export async function fetchCatalog(): Promise<CatalogItem[]> {
  return request('/catalog', undefined, (data) => {
    if (!Array.isArray(data)) throw new ApiError('Invalid catalog response', 500, data);
    return data.map((item) => CatalogItemSchema.parse(item));
  });
}

export async function postAiLayout(payload: LayoutRequest): Promise<LayoutResponse> {
  const body = LayoutRequestSchema.parse(payload);
  return request(
    '/ai/layout',
    {
      method: 'POST',
      body: JSON.stringify(body)
    },
    (data) => LayoutResponseSchema.parse(data)
  );
}

export async function postCartSummary(
  sceneId: string,
  budget?: number
): Promise<CartSummary> {
  return request(
    '/commerce/cart/summary',
    {
      method: 'POST',
      body: JSON.stringify({ sceneId, budget })
    },
    (data) => CartSummarySchema.parse(data)
  );
}

export async function postCheckout(
  payload: CheckoutRequest
): Promise<CheckoutResponse> {
  return request(
    '/commerce/checkout',
    {
      method: 'POST',
      body: JSON.stringify(payload)
    },
    (data) => CheckoutResponseSchema.parse(data)
  );
}

export async function fetchTimeline(sceneId: string): Promise<TimelineList> {
  return request(
    `/scene/${encodeURIComponent(sceneId)}/timeline`,
    undefined,
    (data) => TimelineListSchema.parse(data)
  );
}

export async function postTimelineRestore(
  sceneId: string,
  payload: { entryId: string; actorId: string; displayName?: string }
): Promise<OperationsResult> {
  return request(
    `/scene/${encodeURIComponent(sceneId)}/timeline/restore`,
    { method: 'POST', body: JSON.stringify(payload) },
    (data) => OperationsResultSchema.parse(data)
  );
}

export async function postTimelineBranch(
  sceneId: string,
  payload: { entryId: string; name: string; actorId: string; displayName?: string }
): Promise<TimelineBranchResult> {
  return request(
    `/scene/${encodeURIComponent(sceneId)}/timeline/branch`,
    { method: 'POST', body: JSON.stringify(payload) },
    (data) => TimelineBranchResultSchema.parse(data)
  );
}

export async function fetchDisagreement(
  sceneId: string
): Promise<Disagreement | null> {
  return request(`/scene/${encodeURIComponent(sceneId)}/disagreement`, undefined, (data) => {
    if (data == null) return null;
    return DisagreementSchema.parse(data);
  });
}

export async function postDisagreement(
  sceneId: string,
  payload: {
    actorId: string;
    displayName?: string;
    label?: string;
    operations: SceneOperation[];
    baseVersion?: number;
  }
): Promise<Disagreement> {
  return request(
    `/scene/${encodeURIComponent(sceneId)}/disagreement`,
    { method: 'POST', body: JSON.stringify(payload) },
    (data) => DisagreementSchema.parse(data)
  );
}

export async function postDisagreementCounter(
  sceneId: string,
  disagreementId: string,
  payload: {
    actorId: string;
    displayName?: string;
    label?: string;
    operations: SceneOperation[];
  }
): Promise<Disagreement> {
  return request(
    `/scene/${encodeURIComponent(sceneId)}/disagreement/${encodeURIComponent(disagreementId)}/counter`,
    { method: 'POST', body: JSON.stringify(payload) },
    (data) => DisagreementSchema.parse(data)
  );
}

export async function postDisagreementCompromise(
  sceneId: string,
  disagreementId: string,
  payload: {
    actorId: string;
    displayName?: string;
    mode: 'blend' | 'picks' | 'a' | 'b';
    picks?: Record<string, 'A' | 'B'>;
  }
): Promise<OperationsResult> {
  return request(
    `/scene/${encodeURIComponent(sceneId)}/disagreement/${encodeURIComponent(disagreementId)}/compromise`,
    { method: 'POST', body: JSON.stringify(payload) },
    (data) => OperationsResultSchema.parse(data)
  );
}

export async function postDisagreementResolve(
  sceneId: string,
  disagreementId: string,
  payload: {
    actorId: string;
    choice: 'A' | 'B' | 'cancel';
    displayName?: string;
  }
): Promise<Disagreement | OperationsResult> {
  return request(
    `/scene/${encodeURIComponent(sceneId)}/disagreement/${encodeURIComponent(disagreementId)}/resolve`,
    { method: 'POST', body: JSON.stringify(payload) }
  );
}

export async function createSceneInvite(
  sceneId: string,
  payload?: { actorId?: string; label?: string }
): Promise<SceneInvite> {
  return request(
    `/scene/${encodeURIComponent(sceneId)}/invites`,
    {
      method: 'POST',
      body: JSON.stringify(payload ?? {})
    },
    (data) => SceneInviteSchema.parse(data)
  );
}

export async function fetchSceneInvites(sceneId: string): Promise<SceneInviteList> {
  return request(
    `/scene/${encodeURIComponent(sceneId)}/invites`,
    undefined,
    (data) => SceneInviteListSchema.parse(data)
  );
}

export async function fetchDefaultInvite(sceneId: string): Promise<SceneInvite> {
  return request(
    `/scene/${encodeURIComponent(sceneId)}/invites/default`,
    undefined,
    (data) => SceneInviteSchema.parse(data)
  );
}

export async function resolveInvite(token: string): Promise<SceneInviteResolve> {
  return request(
    `/invite/${encodeURIComponent(token)}`,
    undefined,
    (data) => SceneInviteResolveSchema.parse(data)
  );
}

/** Build a browser join URL for a scene (+ optional invite token). */
export function buildInviteJoinUrl(sceneId: string, token?: string | null): string {
  if (typeof window === 'undefined') {
    const qs = token
      ? `?scene=${encodeURIComponent(sceneId)}&invite=${encodeURIComponent(token)}`
      : `?scene=${encodeURIComponent(sceneId)}`;
    return qs;
  }
  const url = new URL(window.location.href);
  url.searchParams.set('scene', sceneId);
  if (token) url.searchParams.set('invite', token);
  else url.searchParams.delete('invite');
  return url.toString();
}
