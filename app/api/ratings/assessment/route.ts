import { NextResponse } from "next/server";

import { authedSupabaseClient, serviceSupabaseClient } from "@/app/api/billing/_shared";
import type { InitialRatingInput } from "@/app/laboratorio-ficha-jugador/_engine/player-rating-engine";
import {
  calculateSharedAssessmentResult,
  canonicalAdvancedAssessmentInput,
  canonicalInitialAssessmentInput,
} from "@/app/rating-assessment-contract";

export const runtime = "nodejs";

type AssessmentKind = "advanced" | "initial";

type AssessmentRequest = {
  assessmentInput: unknown;
  clientMetadata?: Record<string, unknown>;
  expectedRevision: number;
  groupId?: string | null;
  kind: AssessmentKind;
  operationId: string;
  playerId?: string | null;
};

type GroupContext = {
  groupId: string;
  playerId: string | null;
  revision: number;
};

const noStoreHeaders = { "Cache-Control": "private, no-store" };
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function isAssessmentRequest(value: unknown): value is AssessmentRequest {
  if (!isRecord(value)) return false;
  return (
    (value.kind === "initial" || value.kind === "advanced") &&
    typeof value.operationId === "string" &&
    uuidPattern.test(value.operationId) &&
    typeof value.expectedRevision === "number" &&
    Number.isSafeInteger(value.expectedRevision) &&
    value.expectedRevision >= 0 &&
    (value.groupId === undefined || value.groupId === null || typeof value.groupId === "string") &&
    (value.playerId === undefined || value.playerId === null || typeof value.playerId === "string") &&
    (value.clientMetadata === undefined || isRecord(value.clientMetadata)) &&
    isRecord(value.assessmentInput)
  );
}

function safeMetadata(value: Record<string, unknown> | undefined) {
  const metadata: Record<string, string> = {};
  for (const key of ["clientVersion", "displayMode", "serviceWorkerVersion", "surface"] as const) {
    const entry = value?.[key];
    if (typeof entry === "string" && entry.trim()) metadata[key] = entry.trim().slice(0, 120);
  }
  return metadata;
}

function playerEntries(payload: unknown) {
  if (!isRecord(payload) || !Array.isArray(payload.players)) return [];
  return payload.players.filter(isRecord);
}

async function resolveGroupContext(
  userId: string,
  requestedGroupId?: string | null,
  requestedPlayerId?: string | null,
): Promise<GroupContext | null> {
  const service = serviceSupabaseClient();
  let membershipsQuery = service
    .from("pachanga_group_members")
    .select("group_id,created_at")
    .eq("user_id", userId)
    .order("created_at", { ascending: true })
    .order("group_id", { ascending: true })
    .limit(1);
  if (requestedGroupId) membershipsQuery = membershipsQuery.eq("group_id", requestedGroupId);
  const memberships = await membershipsQuery;
  if (memberships.error) throw new Error(memberships.error.message);
  const membership = memberships.data?.[0];
  if (requestedGroupId && !membership) throw new Error("No perteneces al equipo indicado.");
  if (!membership) return null;

  const group = await service
    .from("pachanga_groups")
    .select("id,payload,payload_revision")
    .eq("id", membership.group_id)
    .single();
  if (group.error || !group.data) throw new Error(group.error?.message ?? "Equipo no encontrado.");

  const players = playerEntries(group.data.payload);
  const ownedPlayer = players.find((player) => player.ownerUserId === userId);
  const requestedPlayer = requestedPlayerId
    ? players.find((player) => player.id === requestedPlayerId)
    : null;
  if (requestedPlayer?.ownerUserId && requestedPlayer.ownerUserId !== userId) {
    throw new Error("La ficha seleccionada pertenece a otro jugador.");
  }

  if (requestedPlayer && !requestedPlayer.ownerUserId) {
    throw new Error("Solicita primero esta ficha y espera la aprobación del administrador.");
  }

  return {
    groupId: group.data.id,
    playerId: typeof ownedPlayer?.id === "string"
      ? ownedPlayer.id
      : typeof requestedPlayer?.id === "string" ? requestedPlayer.id : null,
    revision: Math.max(0, Math.floor(Number(group.data.payload_revision) || 0)),
  };
}

async function canonicalSnapshot(
  client: Awaited<ReturnType<typeof authedSupabaseClient>>["client"],
  userId: string,
  requestedGroupId?: string | null,
) {
  const [profileResult, assessmentResult, groupContext, socialProfileResult] = await Promise.all([
    client
      .from("pachanga_player_profiles")
      .select("id,display_name,avatar,position,outfield_position,current_overall,current_facets,rating_reliability,assessment_summary,profile_version,updated_at")
      .eq("user_id", userId)
      .maybeSingle(),
    client
      .from("pachanga_player_assessments")
      .select("assessment_kind,completed_at,engine_version,input,questionnaire_version,reliability")
      .eq("user_id", userId)
      .order("assessment_kind", { ascending: true }),
    resolveGroupContext(userId, requestedGroupId),
    client
      .from("pachanga_social_player_profiles_v1")
      .select("display_name,primary_position,preferred_modality,general_area")
      .eq("user_id", userId)
      .maybeSingle(),
  ]);
  if (profileResult.error) throw new Error(profileResult.error.message);
  if (assessmentResult.error) throw new Error(assessmentResult.error.message);
  if (socialProfileResult.error) throw new Error(socialProfileResult.error.message);

  const assessments = Object.fromEntries((assessmentResult.data ?? []).map((assessment) => [assessment.assessment_kind, {
    completedAt: assessment.completed_at,
    engineVersion: assessment.engine_version,
    input: assessment.input,
    questionnaireVersion: assessment.questionnaire_version,
    reliability: assessment.reliability,
  }]));
  const profileRevision = Math.max(0, Math.floor(Number(profileResult.data?.profile_version) || 0));
  return {
    assessments,
    onboardingProfileReady: Boolean(
      socialProfileResult.data?.display_name?.trim()
        && socialProfileResult.data?.primary_position?.trim()
        && socialProfileResult.data?.preferred_modality?.trim()
        && socialProfileResult.data?.general_area?.trim(),
    ),
    playerProfile: profileResult.data ?? null,
    writeContext: groupContext
      ? {
          expectedRevision: groupContext.revision,
          groupId: groupContext.groupId,
          playerId: groupContext.playerId,
          scope: "group" as const,
        }
      : {
          expectedRevision: profileRevision,
          groupId: null,
          playerId: null,
          scope: "profile" as const,
        },
  };
}

function errorStatus(message: string, code?: string) {
  if (/Authentication|Invalid session/i.test(message)) return 401;
  if (code === "PT409" || /already completed|newer|different assessment payload/i.test(message)) return 409;
  if (/No perteneces|Current group membership|required/i.test(message)) return 403;
  return 400;
}

export async function GET(request: Request) {
  try {
    const { client, user } = await authedSupabaseClient(request);
    const snapshot = await canonicalSnapshot(client, user.id);
    return NextResponse.json(snapshot, { headers: noStoreHeaders });
  } catch (error) {
    const message = error instanceof Error ? error.message : "No se pudo recuperar el test.";
    return NextResponse.json({ error: message }, { status: errorStatus(message), headers: noStoreHeaders });
  }
}

export async function POST(request: Request) {
  try {
    const { client, user } = await authedSupabaseClient(request);
    const body: unknown = await request.json();
    if (!isAssessmentRequest(body)) {
      return NextResponse.json({ error: "Solicitud de test no válida." }, { status: 400, headers: noStoreHeaders });
    }

    let initialInput: InitialRatingInput;
    let canonicalAssessmentInput: InitialRatingInput | { answers: Record<string, 1 | 2 | 3 | 4 | 5> };
    if (body.kind === "initial") {
      const socialProfile = await client
        .from("pachanga_social_player_profiles_v1")
        .select("display_name,primary_position,preferred_modality,general_area")
        .eq("user_id", user.id)
        .maybeSingle();
      if (socialProfile.error) throw new Error(socialProfile.error.message);
      if (
        !socialProfile.data?.display_name?.trim()
        || !socialProfile.data?.primary_position?.trim()
        || !socialProfile.data?.preferred_modality?.trim()
        || !socialProfile.data?.general_area?.trim()
      ) {
        return NextResponse.json(
          { error: "Completa primero tu perfil y confirma tu ciudad o población." },
          { status: 409, headers: noStoreHeaders },
        );
      }
      initialInput = canonicalInitialAssessmentInput(body.assessmentInput);
      canonicalAssessmentInput = initialInput;
    } else {
      const initialAssessment = await client
        .from("pachanga_player_assessments")
        .select("input")
        .eq("user_id", user.id)
        .eq("assessment_kind", "initial")
        .single();
      if (initialAssessment.error || !initialAssessment.data) throw new Error("Completa primero el test inicial.");
      initialInput = canonicalInitialAssessmentInput(initialAssessment.data.input);
      canonicalAssessmentInput = canonicalAdvancedAssessmentInput(body.assessmentInput, initialInput);
    }
    const calculation = calculateSharedAssessmentResult({
      advancedAnswers: body.kind === "advanced" ? canonicalAssessmentInput.answers : undefined,
      initialInput,
      kind: body.kind,
    });

    const groupContext = await resolveGroupContext(user.id, body.groupId, body.playerId);
    if (groupContext && body.expectedRevision !== groupContext.revision) {
      return NextResponse.json(
        { error: "El equipo cambió en otro dispositivo. Recarga el estado confirmado." },
        { status: 409, headers: noStoreHeaders },
      );
    }

    const service = serviceSupabaseClient();
    const result = groupContext
      ? await service.rpc("persist_pachanga_player_assessment_authoritative_v2", {
          p_actor_user_id: user.id,
          p_assessment_input: canonicalAssessmentInput,
          p_assessment_kind: body.kind,
          p_assessment_result: calculation.persisted,
          p_client_metadata: safeMetadata(body.clientMetadata),
          p_expected_revision: body.expectedRevision,
          p_operation_id: body.operationId,
          p_target_group_id: groupContext.groupId,
          p_target_player_id: groupContext.playerId ?? `assessment-${body.operationId}`,
        })
      : await service.rpc("persist_pachanga_player_assessment_self_authoritative_v1", {
          p_actor_user_id: user.id,
          p_assessment_input: canonicalAssessmentInput,
          p_assessment_kind: body.kind,
          p_assessment_result: calculation.persisted,
          p_client_metadata: safeMetadata(body.clientMetadata),
          p_expected_revision: body.expectedRevision,
          p_operation_id: body.operationId,
        });
    if (result.error) {
      return NextResponse.json(
        { error: result.error.message },
        { status: errorStatus(result.error.message, result.error.code), headers: noStoreHeaders },
      );
    }

    const snapshot = await canonicalSnapshot(client, user.id, groupContext?.groupId);
    return NextResponse.json({
      ...(isRecord(result.data) ? result.data : {}),
      ...snapshot,
    }, { headers: noStoreHeaders });
  } catch (error) {
    const message = error instanceof Error ? error.message : "No se pudo guardar el test.";
    return NextResponse.json({ error: message }, { status: errorStatus(message), headers: noStoreHeaders });
  }
}
