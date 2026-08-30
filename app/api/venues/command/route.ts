import { clientWriteGateResponse } from "../../client-policy/_contract";
import {
  venueApiError,
  venueApiJson,
  venueApiRecord,
  venueApiSession,
  venueClientMetadata,
  venueUuidPattern,
} from "../_shared";

export const dynamic = "force-dynamic";
export const revalidate = 0;

const createActions = new Set([
  "availability.exception.create",
  "availability.template.create",
  "pitch.create",
  "reservation.request.create",
  "venue.create",
]);

const actionFields: Record<string, string[]> = {
  "availability.exception.cancel": ["reasonCode"],
  "availability.exception.create": ["pitchId", "kind", "startsAt", "endsAt", "publicReason", "privateReason", "visibility", "priority", "reasonCode"],
  "availability.template.create": ["pitchId", "weekday", "startLocalTime", "endLocalTime", "slotMinutes", "bufferMinutes", "validFrom", "validUntil", "timezone", "modalities", "capacity", "visibility", "reasonCode"],
  "availability.template.disable": ["reasonCode"],
  "availability.template.update": ["weekday", "startLocalTime", "endLocalTime", "slotMinutes", "bufferMinutes", "validFrom", "validUntil", "timezone", "modalities", "capacity", "visibility", "reasonCode"],
  "pitch.archive": ["reasonCode"],
  "pitch.create": ["venueId", "parentPitchId", "name", "slug", "modalities", "surface", "environment", "widthM", "lengthM", "hasLighting", "hasChangingRooms", "hasShowers", "isAccessible", "hasParking", "spectatorCapacity", "publicRateKind", "publicRateAmountMinor", "publicRateCurrency", "publicRateNote", "visibility", "minimumSlotMinutes", "bufferMinutes", "reasonCode"],
  "pitch.maintenance": ["reasonCode"],
  "pitch.restore": ["reasonCode"],
  "pitch.update": ["parentPitchId", "name", "slug", "modalities", "surface", "environment", "widthM", "lengthM", "hasLighting", "hasChangingRooms", "hasShowers", "isAccessible", "hasParking", "spectatorCapacity", "publicRateKind", "publicRateAmountMinor", "publicRateCurrency", "publicRateNote", "visibility", "minimumSlotMinutes", "bufferMinutes", "reasonCode"],
  "reservation.accept": ["pitchId", "localStart", "localEnd", "timezone", "offsetMinutes", "terms", "reasonCode"],
  "reservation.bind_match": ["canonicalMatchId", "competitionMatchContextId", "scheduleItemId", "ruleRevisionId", "reasonCode"],
  "reservation.cancel": ["reasonCode"],
  "reservation.confirm": ["reasonCode"],
  "reservation.counter": ["pitchId", "localStart", "localEnd", "timezone", "offsetMinutes", "terms", "message", "reasonCode"],
  "reservation.hold": ["pitchId", "localStart", "localEnd", "timezone", "offsetMinutes", "expiresInMinutes", "reasonCode"],
  "reservation.reject": ["message", "reasonCode"],
  "reservation.replace_venue": ["competitionMatchContextId", "expectedContextRevision", "reasonCode", "publicSummary"],
  "reservation.request.create": ["venueId", "pitchId", "requesterKind", "requesterTeamId", "requesterClubId", "competitionId", "canonicalMatchId", "ruleRevisionId", "purpose", "modality", "localStart", "localEnd", "timezone", "offsetMinutes", "criteria", "alternatives", "message", "reasonCode"],
  "reservation.request.submit": ["reasonCode"],
  "reservation.request.update": ["pitchId", "canonicalMatchId", "ruleRevisionId", "purpose", "modality", "localStart", "localEnd", "timezone", "offsetMinutes", "criteria", "alternatives", "message", "reasonCode"],
  "reservation.request.withdraw": ["reasonCode"],
  "reservation.review.start": ["reasonCode"],
  "reservation.unbind_match": ["reasonCode"],
  "venue.activate": ["reasonCode"],
  "venue.archive": ["reasonCode"],
  "venue.create": ["clubId", "name", "slug", "description", "municipality", "generalArea", "timezone", "placeId", "privateAddress", "publicAddress", "privateLatitude", "privateLongitude", "publicLatitude", "publicLongitude", "privateAccessInstructions", "privateContactName", "privateContactPhone", "privateContactEmail", "visibility", "reasonCode"],
  "venue.publication.consent": ["selectedFields", "addressMode", "publicRateAllowed", "reasonCode"],
  "venue.submit_review": ["reasonCode"],
  "venue.suspend": ["reasonCode"],
  "venue.update": ["name", "slug", "description", "municipality", "generalArea", "timezone", "placeId", "privateAddress", "publicAddress", "privateLatitude", "privateLongitude", "publicLatitude", "publicLongitude", "privateAccessInstructions", "privateContactName", "privateContactPhone", "privateContactEmail", "visibility", "reasonCode"],
};

function sanitizedPayload(action: string, value: unknown) {
  const source = venueApiRecord(value);
  const allowed = actionFields[action];
  if (!allowed || Object.keys(source).some((key) => !allowed.includes(key))) {
    throw new Error("VENUE_COMMAND_PAYLOAD_INVALID");
  }
  const serialized = JSON.stringify(source);
  if (serialized.length > 30_000) throw new Error("VENUE_COMMAND_PAYLOAD_INVALID");
  return source;
}

export async function POST(request: Request) {
  try {
    const origin = request.headers.get("origin");
    if (!origin || origin !== new URL(request.url).origin) throw new Error("VENUE_ORIGIN_REQUIRED");
    const gated = clientWriteGateResponse(request);
    if (gated) return gated;
    const { client } = await venueApiSession(request);
    const body = venueApiRecord(await request.json());
    const action = typeof body.action === "string" ? body.action.trim().toLowerCase() : "";
    const operationId = typeof body.operationId === "string" ? body.operationId : "";
    const aggregateId = typeof body.aggregateId === "string" ? body.aggregateId : "";
    const expectedRevision = Number(body.expectedRevision);
    if (!actionFields[action] || !venueUuidPattern.test(operationId)
        || (!createActions.has(action) && !venueUuidPattern.test(aggregateId))
        || (createActions.has(action) && aggregateId)
        || !Number.isInteger(expectedRevision) || expectedRevision < 0
        || (createActions.has(action) && expectedRevision !== 0)) {
      throw new Error("VENUE_COMMAND_INVALID");
    }
    const result = await client.rpc("command_pachanga_venue_reservation_v1", {
      action,
      aggregate_id: aggregateId || null,
      client_metadata: venueClientMetadata(request, "venue_operations_v1"),
      command_payload: sanitizedPayload(action, body.payload),
      expected_revision: expectedRevision,
      operation_id: operationId,
    });
    if (result.error) throw result.error;
    return venueApiJson({ canonical: result.data });
  } catch (error) {
    return venueApiError(error);
  }
}
