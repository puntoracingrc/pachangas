import type { DemoWorldPerspectiveId } from "./demo-world-contract";
import type { DemoWorldV33Manifest, DemoWorldV33Snapshot } from "./demo-world-v3-3-contract";

export const DEMO_WORLD_V34_VERSION = 3.4 as const;
export const DEMO_WORLD_V34_AUTHORITY_HASH = "763c8c70cafde739c308a91668f5ca8b9ed6d6b2036935aa4ac1c65e49a8bab1" as const;

export type DemoWorldV34Perspective = Extract<DemoWorldPerspectiveId,
  "team-owner" | "league-organizer" | "player" | "referee" | "platform-reviewer"
> | "club-booking-manager";

export type DemoWorldV34Pitch = {
  availability: string;
  environment: "INDOOR" | "OUTDOOR";
  id: string;
  modalities: Array<"FUTSAL" | "F7" | "F11">;
  name: string;
  status: "ACTIVE" | "MAINTENANCE";
  surface: "ARTIFICIAL_GRASS" | "PARQUET";
  venueId: string;
};

export type DemoWorldV34Venue = {
  generalArea: string;
  id: string;
  name: string;
  publicationConsent: boolean;
  services: string[];
  slug: string;
  visibility: "PRIVATE" | "PUBLIC";
};

export type DemoWorldV34Story = {
  id: string;
  matchBinding?: { lineage: string[]; status: "ACTIVE" | "CONSUMED"; venueChanged: boolean };
  paymentKind?: "CONTACT_CLUB" | "FREE" | "INDICATIVE" | "NEGOTIABLE";
  perspective: DemoWorldV34Perspective;
  pitchId?: string;
  reservationStatus?: string;
  state: "ACTION_REQUIRED" | "CANONICAL" | "EXPIRED" | "HISTORICAL" | "PRIVATE" | "PUBLIC";
  summary: string;
  title: string;
  venueId?: string;
};

export type DemoWorldV34FieldOperations = {
  authority: {
    generatedFrom: "simulation-world";
    operationReceipts: number;
    serverSequenceOrdered: true;
  };
  counts: { pitches: 8; stories: 16; venues: 4 };
  integrity: {
    activeCanonicalMatchBindings: number;
    confirmedOverlaps: 0;
    noAutoCancel: true;
    noAutoForfeit: true;
    refereeReconfirmationCases: 1;
  };
  payment: {
    charges: 0;
    customers: 0;
    notice: "Pago fuera de Pachangas IQ.";
    stripeCalls: 0;
  };
  pitches: DemoWorldV34Pitch[];
  privacy: {
    authIds: false;
    exactPrivateLocationBeforeConfirmation: false;
    pii: false;
  };
  readOnly: true;
  remoteWrites: 0;
  stories: DemoWorldV34Story[];
  venues: DemoWorldV34Venue[];
  version: typeof DEMO_WORLD_V34_VERSION;
};

export type DemoWorldV34PresentationManifest = {
  authority: {
    hash: typeof DEMO_WORLD_V34_AUTHORITY_HASH;
    manifest: "/demo-world/v3-2/manifest.json";
    version: 3.2;
  };
  fieldOperations: {
    hash: string;
    path: string;
    pitches: 8;
    stories: 16;
    venues: 4;
  };
  mode: "field-operations-read-only";
  privacy: { authIds: false; pii: false };
  remoteWrites: 0;
  version: typeof DEMO_WORLD_V34_VERSION;
};

export type DemoWorldV34Manifest = Omit<DemoWorldV33Manifest, "version"> & {
  fieldOperations: DemoWorldV34PresentationManifest;
  version: typeof DEMO_WORLD_V34_VERSION;
};

export type DemoWorldV34Snapshot = Omit<DemoWorldV33Snapshot, "manifest"> & {
  manifest: DemoWorldV34Manifest;
};

export function assertDemoWorldV34FieldOperations(value: DemoWorldV34FieldOperations) {
  if (value.version !== DEMO_WORLD_V34_VERSION) throw new Error("DEMO_WORLD_V34_VERSION_MISMATCH");
  if (value.venues.length !== 4 || value.pitches.length !== 8 || value.stories.length !== 16) throw new Error("DEMO_WORLD_V34_COUNT_MISMATCH");
  if (value.remoteWrites !== 0 || value.payment.stripeCalls !== 0 || value.payment.customers !== 0 || value.payment.charges !== 0) throw new Error("DEMO_WORLD_V34_REMOTE_SIDE_EFFECT");
  if (value.privacy.pii || value.privacy.authIds || value.integrity.confirmedOverlaps !== 0) throw new Error("DEMO_WORLD_V34_INTEGRITY_FAILURE");
  return value;
}
