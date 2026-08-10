import { createClient } from "@supabase/supabase-js";
import { assertSyntheticWorldEnvironment } from "./environment";
import { mergeKnownIncidents } from "./known-incidents";
import { normalizeSyntheticWorldState } from "./normalization";
import { deterministicUuid } from "./random";
import type { SyntheticEvent, SyntheticIncident, SyntheticRankingRow, SyntheticWorld } from "./types";

type SaveOptions = {
  expectedRevision: number;
  operationId?: string;
  snapshotKind?: "checkpoint" | "monthly" | "season_end" | null;
  snapshotPayload?: Record<string, unknown> | SyntheticWorld | null;
};

type WorldRow = {
  config: SyntheticWorld["config"];
  created_at: string;
  id: string;
  mode: SyntheticWorld["mode"];
  name: string;
  revision: number;
  season_id: string;
  seed: number;
  source_commit: string;
  state: SyntheticWorld["state"];
  status: SyntheticWorld["status"];
  virtual_current_date: string;
  virtual_start_date: string;
};

export type SyntheticWorldListItem = Pick<SyntheticWorld, "currentDate" | "id" | "mode" | "name" | "revision" | "seasonId" | "seed" | "status"> & {
  createdAt: string;
  eventCount: number;
  incidentCount: number;
  matchCount: number;
};

export type SyntheticSnapshotListItem = {
  entityId: string;
  entityKind: string;
  id: number;
  kind: string;
  revision: number;
  serverSequence: number;
  virtualDate: string;
};

function mapWorld(row: WorldRow): SyntheticWorld {
  const state = normalizeSyntheticWorldState({
    ...row.state,
    attendanceRecords: row.state.attendanceRecords ?? [],
    conductScenarios: row.state.conductScenarios ?? [],
    agents: row.state.agents.map((agent, index) => ({
      ...agent,
      attendanceProfile: agent.attendanceProfile ?? (index % 20 === 0 ? "occasional_no_show" : index % 13 === 0 ? "late_canceller" : "normal"),
      conductProfile: agent.conductProfile ?? (index % 29 === 0 ? "occasional_unsporting" : "fair"),
      notificationPreferences: agent.notificationPreferences ?? {
        achievement: { email: false, inApp: true, push: false },
        challenge: { email: false, inApp: true, push: false },
        group: { email: false, inApp: true, push: false },
        market: { email: false, inApp: true, push: false },
        match: { email: false, inApp: true, push: false },
        security: { email: false, inApp: false, push: false },
      },
    })),
    notifications: row.state.notifications.map((notification) => ({
      ...notification,
      category: notification.category ?? "group",
      mandatoryInApp: notification.mandatoryInApp ?? false,
      visibleInApp: notification.visibleInApp ?? true,
    })),
  } as SyntheticWorld["state"]);
  return mergeKnownIncidents({
    config: row.config,
    createdAt: row.created_at,
    currentDate: row.virtual_current_date,
    id: row.id,
    mode: row.mode,
    name: row.name,
    revision: Number(row.revision),
    seasonId: row.season_id,
    seed: Number(row.seed),
    sourceCommit: row.source_commit,
    startDate: row.virtual_start_date,
    state,
    status: row.status,
  });
}

function syntheticClient(supabaseUrl: string, serviceRoleKey: string) {
  return createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
    db: { schema: "simulation" },
    global: { headers: { "x-pachangas-synthetic-world": "1" } },
  });
}

export class SyntheticWorldStore {
  private readonly client: ReturnType<typeof syntheticClient>;

  constructor(env: NodeJS.ProcessEnv = process.env) {
    const { supabaseUrl } = assertSyntheticWorldEnvironment(env);
    this.client = syntheticClient(supabaseUrl, env.SUPABASE_SERVICE_ROLE_KEY!);
  }

  async listWorlds(): Promise<SyntheticWorldListItem[]> {
    const { data, error } = await this.client.from("simulation_world_summaries")
      .select("id,name,seed,created_at,virtual_current_date,season_id,status,mode,revision,event_count,incident_count,match_count")
      .order("updated_at", { ascending: false });
    if (error) throw error;
    return (data ?? []).map((row) => ({
      createdAt: row.created_at,
      currentDate: row.virtual_current_date,
      eventCount: Number(row.event_count ?? 0),
      id: row.id,
      incidentCount: Number(row.incident_count ?? 0),
      matchCount: Number(row.match_count ?? 0),
      mode: row.mode,
      name: row.name,
      revision: Number(row.revision),
      seasonId: row.season_id,
      seed: Number(row.seed),
      status: row.status,
    }));
  }

  async loadWorld(id: string): Promise<SyntheticWorld> {
    const { data, error } = await this.client.from("simulation_worlds").select("*").eq("id", id).single();
    if (error) throw error;
    return mapWorld(data as WorldRow);
  }

  async saveWorld(world: SyntheticWorld, options: SaveOptions) {
    const operationId = options.operationId ?? deterministicUuid(`${world.id}:save`, `${options.expectedRevision}:${world.revision}`);
    const { data, error } = await this.client.rpc("save_world", {
      p_expected_revision: options.expectedRevision,
      p_operation_id: operationId,
      p_snapshot_kind: options.snapshotKind ?? null,
      p_snapshot_payload: options.snapshotPayload ?? null,
      p_world: world,
    });
    if (error) throw error;
    return data as { confirmedRevision: number; idempotentReplay: boolean; serverSequence: number; worldId: string };
  }

  async operationReceipt(worldId: string, operationId: string) {
    const { data, error } = await this.client.from("simulation_operation_receipts")
      .select("response")
      .eq("world_id", worldId)
      .eq("operation_id", operationId)
      .maybeSingle();
    if (error) throw error;
    return data?.response as { confirmedRevision: number; idempotentReplay?: boolean; serverSequence: number; worldId: string } | null;
  }

  async timeline(worldId: string, limit = 250): Promise<SyntheticEvent[]> {
    const { data, error } = await this.client.from("simulation_events")
      .select("server_sequence,virtual_date,event_type,flow,actor_agent_id,operation_id,status,expected,payload,related_entity_ids")
      .eq("world_id", worldId)
      .order("server_sequence", { ascending: false })
      .limit(Math.max(1, Math.min(2_000, limit)));
    if (error) throw error;
    return (data ?? []).map((row) => ({
      actorAgentId: row.actor_agent_id,
      entityIds: row.related_entity_ids,
      eventType: row.event_type,
      expected: row.expected,
      flow: row.flow,
      operationId: row.operation_id,
      payload: row.payload,
      sequence: Number(row.server_sequence),
      status: row.status,
      virtualDate: row.virtual_date,
    }));
  }

  async incidents(worldId: string): Promise<SyntheticIncident[]> {
    const { data, error } = await this.client.from("simulation_incidents").select("*").eq("world_id", worldId).order("virtual_date", { ascending: false });
    if (error) throw error;
    return (data ?? []).map((row) => ({
      actual: row.actual,
      actorAgentId: row.actor,
      afterState: row.after_state,
      beforeState: row.before_state,
      category: row.category,
      expected: row.expected,
      id: row.incident_id,
      occurrenceCount: row.occurrence_count,
      operation: row.operation,
      relatedEntityIds: row.related_entity_ids,
      reproductionSteps: row.reproduction_steps,
      severity: row.severity,
      status: row.status,
      virtualDate: row.virtual_date,
    }));
  }

  async rankingHistory(worldId: string, provinceCode?: string, limit = 2_000) {
    let query = this.client.from("simulation_ranking_history")
      .select("virtual_date,territory_code,agent_id,rank,score,movement,certification,explanation")
      .eq("world_id", worldId)
      .order("virtual_date", { ascending: false })
      .order("rank", { ascending: true })
      .limit(limit);
    if (provinceCode) query = query.eq("territory_code", provinceCode);
    const { data, error } = await query;
    if (error) throw error;
    return (data ?? []).map((row): SyntheticRankingRow & { virtualDate: string } => ({
      agentId: row.agent_id,
      certification: row.certification,
      certificationReasons: row.explanation.certificationReasons ?? [],
      competition: Number(row.explanation.competition ?? 0),
      integrityRisk: Number(row.explanation.integrityRisk ?? 0),
      logicalOpponents: Number(row.explanation.logicalOpponents ?? 0),
      movement: Number(row.movement),
      opposition: Number(row.explanation.opposition ?? 0),
      provinceCode: row.territory_code,
      quality: Number(row.explanation.quality ?? 0),
      rank: Number(row.rank),
      score: Number(row.score),
      validChallenges: Number(row.explanation.validChallenges ?? 0),
      virtualDate: row.virtual_date,
    }));
  }

  async snapshots(worldId: string, limit = 100): Promise<SyntheticSnapshotListItem[]> {
    const { data, error } = await this.client.from("simulation_snapshots")
      .select("id,snapshot_kind,virtual_date,entity_kind,entity_id,world_revision,server_sequence")
      .eq("world_id", worldId)
      .order("server_sequence", { ascending: false })
      .order("id", { ascending: false })
      .limit(Math.max(1, Math.min(500, limit)));
    if (error) throw error;
    return (data ?? []).map((row) => ({
      entityId: row.entity_id,
      entityKind: row.entity_kind,
      id: Number(row.id),
      kind: row.snapshot_kind,
      revision: Number(row.world_revision),
      serverSequence: Number(row.server_sequence),
      virtualDate: row.virtual_date,
    }));
  }
}
