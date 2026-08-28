import "server-only";
import { createClient } from "@supabase/supabase-js";

type JsonRecord = Record<string, unknown>;

function publicClient() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL?.trim();
  const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY?.trim();
  if (!url || !key) return null;
  return createClient(url, key, { auth: { autoRefreshToken: false, persistSession: false } });
}

export async function getPublicClubBySlug(slug: string): Promise<JsonRecord | null> {
  const client = publicClient();
  if (!client || !/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(slug)) return null;
  const result = await client.rpc("get_pachanga_public_club_v1", { target_slug: slug });
  if (result.error || !result.data || typeof result.data !== "object" || Array.isArray(result.data)) return null;
  return result.data as JsonRecord;
}

export async function getPublicRefereeBySlug(slug: string): Promise<JsonRecord | null> {
  const client = publicClient();
  if (!client || !/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(slug)) return null;
  const result = await client.rpc("get_pachanga_public_referee_v1", { target_slug: slug });
  if (result.error || !result.data || typeof result.data !== "object" || Array.isArray(result.data)) return null;
  return result.data as JsonRecord;
}

export async function searchPublicClubs(filters: JsonRecord, page: number, pageSize: number) {
  const client = publicClient();
  if (!client) return null;
  const result = await client.rpc("search_pachanga_public_clubs_v1", {
    target_filters: filters,
    target_page: page,
    target_page_size: pageSize,
  });
  return result.error ? null : result.data;
}

export async function searchPublicCompetitions(filters: JsonRecord, page: number, pageSize: number) {
  const client = publicClient();
  if (!client) return null;
  const result = await client.rpc("get_pachanga_public_competition_directory_v1", {
    area_filter: typeof filters.area === "string" ? filters.area : null,
    competition_type_filter: typeof filters.type === "string" ? filters.type : null,
    page_offset: Math.max(0, (page - 1) * pageSize),
    page_size: pageSize,
    registration_filter: typeof filters.registration === "string" ? filters.registration : null,
    search_text: typeof filters.search === "string" ? filters.search : null,
    sport_format_filter: typeof filters.sportFormat === "string" ? filters.sportFormat : null,
    state_filter: typeof filters.state === "string" ? filters.state : null,
  });
  return result.error ? null : result.data;
}

export async function getPublicCompetitionBySlug(slug: string): Promise<JsonRecord | null> {
  const client = publicClient();
  if (!client || !/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(slug)) return null;
  const result = await client.rpc("get_pachanga_public_competition_v1", { target_slug: slug });
  if (result.error || !result.data || typeof result.data !== "object" || Array.isArray(result.data)) return null;
  return result.data as JsonRecord;
}

export async function getPublicCompetitionCalendar(slug: string, page = 1, pageSize = 50) {
  const client = publicClient();
  if (!client || !/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(slug)) return null;
  const result = await client.rpc("get_pachanga_public_competition_calendar_v1", {
    page_offset: Math.max(0, (page - 1) * pageSize),
    page_size: pageSize,
    target_slug: slug,
  });
  return result.error ? null : result.data;
}

export async function getPublicCompetitionStandings(slug: string) {
  const client = publicClient();
  if (!client || !/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(slug)) return null;
  const result = await client.rpc("get_pachanga_public_competition_standings_v1", { target_slug: slug });
  return result.error ? null : result.data;
}

export async function getPublicCompetitionBracket(slug: string) {
  const client = publicClient();
  if (!client || !/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(slug)) return null;
  const result = await client.rpc("get_pachanga_public_competition_bracket_v1", { target_slug: slug });
  return result.error ? null : result.data;
}

export async function getPublicCompetitionSitemap() {
  const client = publicClient();
  if (!client) return [] as Array<{ slug: string; updated_at: string }>;
  const result = await client.rpc("get_pachanga_public_competition_sitemap_v1");
  return result.error || !Array.isArray(result.data)
    ? []
    : result.data as Array<{ slug: string; updated_at: string }>;
}
