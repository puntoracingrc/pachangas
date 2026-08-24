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
