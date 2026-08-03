import { NextResponse } from "next/server";

import { authedSupabaseClient, serviceSupabaseClient } from "@/app/api/billing/_shared";
import type { InitialRatingInput } from "@/app/laboratorio-ficha-jugador/_engine/player-rating-engine";
import { calculateSharedAssessmentResult } from "@/app/rating-assessment-contract";

export const runtime = "nodejs";

type AssessmentRequest = {
  assessmentInput: unknown;
  clientMetadata?: Record<string, unknown>;
  expectedRevision: number;
  groupId: string;
  kind: "initial" | "advanced";
  operationId: string;
  playerId: string;
};

function isAssessmentRequest(value: unknown): value is AssessmentRequest {
  if (!value || typeof value !== "object") return false;
  const body = value as Partial<AssessmentRequest>;
  return (
    (body.kind === "initial" || body.kind === "advanced") &&
    typeof body.groupId === "string" &&
    typeof body.playerId === "string" &&
    typeof body.operationId === "string" &&
    typeof body.expectedRevision === "number" &&
    Number.isSafeInteger(body.expectedRevision) &&
    body.expectedRevision >= 0 &&
    (body.clientMetadata === undefined || Boolean(body.clientMetadata && typeof body.clientMetadata === "object" && !Array.isArray(body.clientMetadata))) &&
    Boolean(body.assessmentInput && typeof body.assessmentInput === "object")
  );
}

export async function POST(request: Request) {
  try {
    const { client, user } = await authedSupabaseClient(request);
    const body: unknown = await request.json();
    if (!isAssessmentRequest(body)) return NextResponse.json({ error: "Solicitud de test no válida." }, { status: 400 });

    let initialInput: InitialRatingInput;
    if (body.kind === "initial") {
      initialInput = body.assessmentInput as InitialRatingInput;
    } else {
      const initialAssessment = await client
        .from("pachanga_player_assessments")
        .select("input")
        .eq("user_id", user.id)
        .eq("assessment_kind", "initial")
        .single();
      if (initialAssessment.error || !initialAssessment.data) throw new Error("Completa primero el test inicial.");
      initialInput = initialAssessment.data.input as InitialRatingInput;
    }
    const advancedInput = body.assessmentInput as { answers?: Record<string, 1 | 2 | 3 | 4 | 5 | null> };
    const calculation = calculateSharedAssessmentResult({
      advancedAnswers: advancedInput.answers,
      initialInput,
      kind: body.kind,
    });

    const result = await serviceSupabaseClient().rpc("persist_pachanga_player_assessment_authoritative_v2", {
      p_actor_user_id: user.id,
      p_assessment_input: body.assessmentInput,
      p_assessment_kind: body.kind,
      p_assessment_result: calculation.persisted,
      p_client_metadata: body.clientMetadata ?? {},
      p_expected_revision: body.expectedRevision,
      p_operation_id: body.operationId,
      p_target_group_id: body.groupId,
      p_target_player_id: body.playerId,
    });
    if (result.error) throw new Error(result.error.message);
    return NextResponse.json(result.data, { headers: { "Cache-Control": "private, no-store" } });
  } catch (error) {
    const message = error instanceof Error ? error.message : "No se pudo guardar el test.";
    const status = /Authentication|Invalid session/i.test(message) ? 401 : 400;
    return NextResponse.json({ error: message }, { status, headers: { "Cache-Control": "private, no-store" } });
  }
}
