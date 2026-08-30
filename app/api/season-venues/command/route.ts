import { clientWriteGateResponse } from "../../client-policy/_contract";
import {
  venueApiError,
  venueApiJson,
  venueApiRecord,
  venueApiSession,
  venueClientMetadata,
  venueUuidPattern,
} from "../../venues/_shared";

export const dynamic = "force-dynamic";
export const revalidate = 0;

const rootCreateActions = new Set([
  "allocation_plan.create",
  "recurring_series.create",
  "venue_pool.create",
]);

const actionFields: Record<string, string[]> = {
  "allocation.cancel": ["reasonCode"],
  "allocation.generate": ["seed", "searchBudget", "reasonCode"],
  "allocation.hold": ["expiresInMinutes", "reasonCode"],
  "allocation.item.assign": ["canonicalMatchId", "pitchId", "reasonCode"],
  "allocation.item.move": ["canonicalMatchId", "pitchId", "reasonCode"],
  "allocation.item.remove": ["canonicalMatchId", "reasonCode"],
  "allocation.item.swap": ["canonicalMatchId", "otherCanonicalMatchId", "reasonCode"],
  "allocation.lock.create": ["lockType", "canonicalMatchId", "roundId", "venueId", "pitchId", "recurringOccurrenceId", "reason"],
  "allocation.lock.remove": ["lockId", "reasonCode"],
  "allocation.publish": ["reasonCode"],
  "allocation.regenerate": ["seed", "searchBudget", "reasonCode"],
  "allocation.validate": ["reasonCode"],
  "allocation_constraint.create": ["constraintKind", "constraintCode", "scopeKind", "scopeId", "weight", "parameters", "reason"],
  "allocation_constraint.remove": ["constraintId", "reasonCode"],
  "allocation_constraint.update": ["constraintId", "weight", "parameters", "reason"],
  "allocation_inputs.freeze": ["reasonCode"],
  "allocation_plan.create": ["competitionId", "editionId", "stageId", "schedulePlanId", "scheduleRevisionId", "ruleRevisionId", "venuePoolId", "mode", "venueRequired", "reasonCode"],
  "recurring_series.accept": ["reasonCode"],
  "recurring_series.cancel": ["reasonCode"],
  "recurring_series.complete": ["reasonCode"],
  "recurring_series.create": ["pitchId", "purpose", "teamId", "competitionId", "modality", "frequency", "timezone", "weekday", "localStartTime", "localOffsetMinutes", "durationMinutes", "bufferMinutes", "startDate", "endDate", "reasonCode"],
  "recurring_series.end": ["reasonCode"],
  "recurring_series.materialize": ["reasonCode"],
  "recurring_series.offer": ["reasonCode"],
  "recurring_series.pause": ["reasonCode"],
  "recurring_series.publish": ["reasonCode"],
  "recurring_series.resume": ["reasonCode"],
  "recurring_series.update": ["pitchId", "modality", "frequency", "timezone", "weekday", "localStartTime", "localOffsetMinutes", "durationMinutes", "bufferMinutes", "startDate", "endDate", "reasonCode"],
  "recurring_series.validate": ["reasonCode"],
  "venue_pool.accept": ["reasonCode"],
  "venue_pool.activate": ["reasonCode"],
  "venue_pool.create": ["competitionId", "editionId", "name", "visibility", "reasonCode"],
  "venue_pool.offer": ["ownerClubId", "venueId", "pitchIds", "modalities", "validFrom", "validUntil", "allowedWeekdays", "localStartTime", "localEndTime", "capacityPerSlot", "priority", "visibility", "sourceKind", "recurringSeriesId", "reservationId", "expiresAt", "reasonCode"],
  "venue_pool.revoke": ["reasonCode"],
  "venue_pool.update": ["name", "visibility", "reasonCode"],
};

function sanitizedPayload(action: string, value: unknown) {
  const source = venueApiRecord(value);
  const allowed = actionFields[action];
  if (!allowed || Object.keys(source).some((key) => !allowed.includes(key))) {
    throw new Error("VENUE_ALLOCATION_COMMAND_PAYLOAD_INVALID");
  }
  const serialized = JSON.stringify(source);
  if (serialized.length > 40_000 || /actorId|serverSequence|resultChecksum|quality|acceptedBy|publishedAt/i.test(serialized)) {
    throw new Error("VENUE_ALLOCATION_COMMAND_PAYLOAD_INVALID");
  }
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
    const aggregateId = typeof body.aggregateId === "string" ? body.aggregateId : "";
    const operationId = typeof body.operationId === "string" ? body.operationId : "";
    const expectedRevision = Number(body.expectedRevision);
    const isRootCreate = rootCreateActions.has(action);
    if (!actionFields[action] || !venueUuidPattern.test(operationId)
        || (isRootCreate ? Boolean(aggregateId) : !venueUuidPattern.test(aggregateId))
        || !Number.isInteger(expectedRevision) || expectedRevision < 0
        || (isRootCreate && expectedRevision !== 0)) {
      throw new Error("VENUE_ALLOCATION_COMMAND_INVALID");
    }
    const result = await client.rpc("command_pachanga_competition_venue_allocation_v1", {
      action,
      aggregate_id: aggregateId || null,
      client_metadata: venueClientMetadata(request, "season_venue_planner_v1"),
      command_payload: sanitizedPayload(action, body.payload),
      expected_revision: expectedRevision,
      operation_id: operationId,
    });
    if (result.error) throw new Error(result.error.message);
    return venueApiJson({ canonical: result.data });
  } catch (error) {
    return venueApiError(error);
  }
}
