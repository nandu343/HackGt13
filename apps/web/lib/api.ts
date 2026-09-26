import {
  CartSummarySchema,
  CatalogItemSchema,
  CheckoutResponseSchema,
  LayoutRequestSchema,
  LayoutResponseSchema,
  OperationsResultSchema,
  SceneSchema,
  type CartSummary,
  type CatalogItem,
  type CheckoutRequest,
  type CheckoutResponse,
  type LayoutRequest,
  type LayoutResponse,
  type OperationEnvelope,
  type OperationsResult,
  type Scene
} from '@shared-spatial-ai/schema';

const API_URL = (process.env.NEXT_PUBLIC_API_URL || 'http://localhost:8000').replace(/\/$/, '');

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
