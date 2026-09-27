import { z } from 'zod';

/** Y-up meters; room origin at floor center. */
export type Vector3 = [number, number, number];
export type Quaternion = [number, number, number, number];

export const Vector3Schema = z.tuple([z.number(), z.number(), z.number()]);
export const QuaternionSchema = z.tuple([
  z.number(),
  z.number(),
  z.number(),
  z.number()
]);

export const TransformSchema = z.object({
  position: Vector3Schema,
  rotation: QuaternionSchema,
  scale: Vector3Schema.optional()
});
export type Transform = z.infer<typeof TransformSchema>;

export const DimensionsSchema = z.object({
  width: z.number().optional(),
  height: z.number().optional(),
  depth: z.number().optional()
});
export type Dimensions = z.infer<typeof DimensionsSchema>;

export const SceneObjectSchema = z.object({
  id: z.string(),
  type: z.string(),
  source: z.enum(['existing', 'catalog']).optional(),
  movable: z.boolean().optional(),
  transform: TransformSchema,
  dimensions: DimensionsSchema.optional(),
  // FastAPI/Pydantic serializes missing optionals as null — accept both.
  productId: z.string().nullable().optional(),
  assetId: z.string().nullable().optional(),
  /** GLB/USDZ path e.g. /models/sofa.glb — resolved from catalog when placing. */
  modelUrl: z.string().nullable().optional(),
  lockedBy: z.string().nullable().optional(),
  lockedUntil: z.string().nullable().optional()
});
export type SceneObject = z.infer<typeof SceneObjectSchema>;

export const RoomBoundsSchema = z.object({
  width: z.number(),
  length: z.number(),
  height: z.number()
});
export type RoomBounds = z.infer<typeof RoomBoundsSchema>;

export const SceneSchema = z.object({
  sceneId: z.string(),
  roomId: z.string().optional(),
  version: z.number().int().nonnegative(),
  bounds: RoomBoundsSchema,
  objects: z.array(SceneObjectSchema),
  budgetUsed: z.number().optional(),
  currency: z.string().optional()
});
export type Scene = z.infer<typeof SceneSchema>;

export const OpTypeSchema = z.enum([
  'MOVE_OBJECT',
  'ROTATE_OBJECT',
  'ADD_OBJECT',
  'DELETE_OBJECT',
  'REPLACE_OBJECT'
]);
export type OpType = z.infer<typeof OpTypeSchema>;

/** Prefer ADD_OBJECT with optional productId (ADD_PRODUCT is not a separate op). */
export const SceneOperationSchema = z.object({
  type: OpTypeSchema,
  objectId: z.string().nullish(),
  targetPosition: Vector3Schema.nullish(),
  targetRotation: QuaternionSchema.nullish(),
  assetId: z.string().nullish(),
  productId: z.string().nullish(),
  objectType: z.string().nullish(),
  dimensions: DimensionsSchema.nullish(),
  movable: z.boolean().nullish(),
  source: z.enum(['existing', 'catalog']).nullish(),
  /** Optional GLB/USDZ URL copied from catalog onto ADD_OBJECT. */
  modelUrl: z.string().nullish()
});
export type SceneOperation = z.infer<typeof SceneOperationSchema>;

export const OperationEnvelopeSchema = z.object({
  baseVersion: z.number().int().nonnegative(),
  actorId: z.string().optional(),
  opId: z.string().optional(),
  /** Optional timeline label when ops are accepted. */
  label: z.string().optional(),
  operations: z.array(SceneOperationSchema).min(1)
});
export type OperationEnvelope = z.infer<typeof OperationEnvelopeSchema>;

export const ScenePatchSchema = z.object({
  sceneId: z.string(),
  fromVersion: z.number().int().nonnegative(),
  toVersion: z.number().int().nonnegative(),
  operations: z.array(SceneOperationSchema),
  scene: SceneSchema.optional()
});
export type ScenePatch = z.infer<typeof ScenePatchSchema>;

export const ConstraintSetSchema = z.object({
  budget: z.number().optional(),
  guestCount: z.number().int().optional(),
  mustHave: z.array(z.string()).optional(),
  clearCenter: z.boolean().optional()
});
export type ConstraintSet = z.infer<typeof ConstraintSetSchema>;

export const LayoutRequestSchema = z.object({
  sceneId: z.string(),
  prompt: z.string().min(1),
  guestCount: z.number().int().positive().default(15),
  budget: z.number().nonnegative().default(150),
  constraints: ConstraintSetSchema.optional()
});
export type LayoutRequest = z.infer<typeof LayoutRequestSchema>;

export const LayoutResponseSchema = z.object({
  scenario: z.string(),
  reasoningSummary: z.string(),
  operations: z.array(SceneOperationSchema),
  constraints: ConstraintSetSchema,
  warnings: z.array(z.string()).optional(),
  /** Hybrid planner source: rules always; llm when XAI_API_KEY is set. */
  plannerMode: z.enum(['rules', 'llm']).optional(),
  /** Ops dropped or auto-clamped during postprocess validation. */
  fixedOps: z.number().int().nonnegative().optional(),
  /** Bang-for-buck product choices with light rationale. */
  valuePicks: z
    .array(
      z.object({
        productId: z.string(),
        name: z.string().nullish(),
        score: z.number(),
        reason: z.string(),
        objectId: z.string().nullish(),
        replacedProductId: z.string().nullish(),
        rating: z.number().nullish(),
        price: z.number().nullish()
      })
    )
    .nullish()
});
export type LayoutResponse = z.infer<typeof LayoutResponseSchema>;

export const ProductSchema = z.object({
  productId: z.string(),
  name: z.string(),
  price: z.number().nonnegative(),
  currency: z.string().default('USD'),
  dimensions: DimensionsSchema.optional(),
  assetId: z.string().nullable().optional(),
  /** Public path to GLB (web) / USDZ (iOS) e.g. /models/sofa.glb */
  modelUrl: z.string().nullable().optional(),
  /** Short shop blurb shown in catalog / Place picker. */
  description: z.string().nullable().optional(),
  /** Retailer product page (Amazon / IKEA-style). Open in new tab from Shop. */
  productUrl: z.string().nullable().optional(),
  /** Alias accepted from some feeds — prefer productUrl. */
  websiteUrl: z.string().nullable().optional(),
  tags: z.array(z.string()).optional(),
  purchasable: z.boolean().default(true),
  virtualOnly: z.boolean().default(false),
  /** Customer rating 1–5 for bang-for-buck value scoring. */
  rating: z.number().min(0).max(5).optional(),
  qualityTier: z.enum(['budget', 'standard', 'premium']).optional()
});
export type Product = z.infer<typeof ProductSchema>;

export const CatalogItemSchema = ProductSchema.extend({
  category: z.string().nullable().optional(),
  thumbnailUrl: z.string().nullable().optional()
});
export type CatalogItem = z.infer<typeof CatalogItemSchema>;

export const PresenceUserSchema = z.object({
  userId: z.string(),
  displayName: z.string(),
  color: z.string().optional(),
  selectedObjectId: z.string().nullable().optional(),
  lastSeenAt: z.string().optional(),
  /** Mic joined — peers should negotiate WebRTC audio. */
  voiceEnabled: z.boolean().optional(),
  /** Local VAD / speaking indicator for presence UI. */
  voiceSpeaking: z.boolean().optional(),
  /** Ghost avatar standing point in Y-up meters (orbit focus / presence cursor). */
  position: Vector3Schema.optional(),
  /** Optional facing / look direction (unit-ish vector). */
  lookDirection: Vector3Schema.optional()
});
export type PresenceUser = z.infer<typeof PresenceUserSchema>;

/** Spatial annotation polyline in Y-up meters (free-space / wall / floor). Prefer plane: "free". */
export const DrawingStrokeSchema = z.object({
  strokeId: z.string(),
  sceneId: z.string(),
  actorId: z.string(),
  /** CSS / hex color — synced over WS so peers see the chosen stroke color. */
  color: z.string().default('#6ec8e8'),
  width: z.number().positive().default(0.02),
  points: z.array(Vector3Schema).min(2),
  /** nullish: API may serialize unset plane as null. */
  plane: z.enum(['wall', 'floor', 'free']).nullish(),
  createdAt: z.string().nullish()
});
export type DrawingStroke = z.infer<typeof DrawingStrokeSchema>;

export const CartLineItemSchema = z.object({
  productId: z.string(),
  name: z.string(),
  quantity: z.number().int().positive(),
  unitPrice: z.number().nonnegative(),
  lineTotal: z.number().nonnegative(),
  purchasable: z.boolean().default(true),
  virtualOnly: z.boolean().default(false)
});
export type CartLineItem = z.infer<typeof CartLineItemSchema>;

export const CartSummarySchema = z.object({
  sceneId: z.string(),
  currency: z.string(),
  items: z.array(CartLineItemSchema),
  subtotal: z.number().nonnegative(),
  purchasableSubtotal: z.number().optional(),
  virtualOnlyCount: z.number().int().optional(),
  budget: z.number().optional(),
  remaining: z.number().optional()
});
export type CartSummary = z.infer<typeof CartSummarySchema>;

export const CheckoutRequestSchema = z.object({
  sceneId: z.string(),
  successUrl: z.string().optional(),
  cancelUrl: z.string().optional(),
  customerEmail: z.string().optional()
});
export type CheckoutRequest = z.infer<typeof CheckoutRequestSchema>;

export const CheckoutResponseSchema = z.object({
  mode: z.string(),
  checkoutUrl: z.string(),
  sessionId: z.string(),
  amountTotal: z.number(),
  currency: z.string(),
  lineItemCount: z.number().int(),
  message: z.string().optional()
});
export type CheckoutResponse = z.infer<typeof CheckoutResponseSchema>;

export const SoftLockRequestSchema = z.object({
  objectId: z.string(),
  actorId: z.string(),
  ttlSeconds: z.number().int().positive().optional()
});
export type SoftLockRequest = z.infer<typeof SoftLockRequestSchema>;

export const OperationsResultSchema = z.object({
  accepted: z.boolean(),
  sceneId: z.string(),
  version: z.number().int().nonnegative(),
  applied: z.number().int().nonnegative(),
  scene: SceneSchema,
  warnings: z.array(z.string()).optional()
});
export type OperationsResult = z.infer<typeof OperationsResultSchema>;

/** Version snapshot for collaborative history / restore / branch. */
export const TimelineEntrySchema = z.object({
  entryId: z.string(),
  sceneId: z.string(),
  version: z.number().int().nonnegative(),
  label: z.string(),
  actorId: z.string().nullable().optional(),
  displayName: z.string().nullable().optional(),
  branchId: z.string().default('main'),
  parentEntryId: z.string().nullable().optional(),
  createdAt: z.string(),
  operations: z.array(SceneOperationSchema).nullable().optional(),
  scene: SceneSchema
});
export type TimelineEntry = z.infer<typeof TimelineEntrySchema>;

export const TimelineListSchema = z.object({
  sceneId: z.string(),
  branchId: z.string().default('main'),
  entries: z.array(TimelineEntrySchema)
});
export type TimelineList = z.infer<typeof TimelineListSchema>;

export const TimelineBranchResultSchema = z.object({
  sourceSceneId: z.string(),
  branchId: z.string(),
  branchSceneId: z.string(),
  entry: TimelineEntrySchema,
  scene: SceneSchema
});
export type TimelineBranchResult = z.infer<typeof TimelineBranchResultSchema>;

export const DisagreementProposalSchema = z.object({
  actorId: z.string(),
  displayName: z.string().nullable().optional(),
  label: z.string().nullable().optional(),
  operations: z.array(SceneOperationSchema).min(1),
  scene: SceneSchema.nullable().optional(),
  createdAt: z.string().nullable().optional()
});
export type DisagreementProposal = z.infer<typeof DisagreementProposalSchema>;

export const DisagreementSchema = z.object({
  disagreementId: z.string(),
  sceneId: z.string(),
  status: z.enum(['open', 'countered', 'resolved', 'cancelled']),
  baseVersion: z.number().int().nonnegative(),
  baseScene: SceneSchema,
  proposalA: DisagreementProposalSchema,
  proposalB: DisagreementProposalSchema.nullable().optional(),
  createdAt: z.string(),
  resolvedAt: z.string().nullable().optional(),
  resolveMode: z.string().nullable().optional()
});
export type Disagreement = z.infer<typeof DisagreementSchema>;

/** Shareable room invite — no hard peer cap on WS presence. */
export const SceneInviteSchema = z.object({
  token: z.string(),
  sceneId: z.string(),
  createdAt: z.string(),
  createdBy: z.string().nullable().optional(),
  label: z.string().nullable().optional()
});
export type SceneInvite = z.infer<typeof SceneInviteSchema>;

export const SceneInviteListSchema = z.object({
  sceneId: z.string(),
  invites: z.array(SceneInviteSchema)
});
export type SceneInviteList = z.infer<typeof SceneInviteListSchema>;

export const SceneInviteResolveSchema = z.object({
  token: z.string(),
  sceneId: z.string(),
  joinPath: z.string()
});
export type SceneInviteResolve = z.infer<typeof SceneInviteResolveSchema>;

export { demoScene, demoCatalog } from './seed';
