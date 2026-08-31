import {
  venueApiError,
  venueApiJson,
  venueApiSession,
  venueUuidPattern,
} from "../../venues/_shared";

export const dynamic = "force-dynamic";
export const revalidate = 0;

function uuid(params: URLSearchParams, name: string, required = true) {
  const value = params.get(name) ?? "";
  if (!value && !required) return null;
  if (!venueUuidPattern.test(value)) throw new Error("VENUE_READ_ID_INVALID");
  return value;
}

function date(params: URLSearchParams, name: string) {
  const value = params.get(name) ?? "";
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) throw new Error("VENUE_READ_DATE_INVALID");
  return value;
}

export async function GET(request: Request) {
  try {
    const { client } = await venueApiSession(request);
    const params = new URL(request.url).searchParams;
    const view = params.get("view") ?? "";
    let name = "";
    let args: Record<string, unknown> | undefined;
    if (view === "catalog") {
      name = "get_pachanga_season_venue_catalog_v1";
      args = {
        target_club_id: uuid(params, "clubId", false),
        target_competition_id: uuid(params, "competitionId", false),
      };
      if (!args.target_club_id && !args.target_competition_id) throw new Error("VENUE_READ_ID_INVALID");
    } else if (view === "overview") {
      name = "get_pachanga_competition_venue_allocation_overview_v1";
      args = { target_competition_id: uuid(params, "competitionId") };
    } else if (view === "desk") {
      name = "get_pachanga_competition_venue_allocation_desk_v1";
      args = { target_plan_id: uuid(params, "planId") };
    } else if (view === "revision") {
      name = "get_pachanga_competition_venue_allocation_revision_v1";
      args = { target_revision_id: uuid(params, "revisionId") };
    } else if (view === "diff") {
      name = "get_pachanga_competition_venue_allocation_diff_v1";
      args = {
        target_from_revision_id: uuid(params, "fromRevisionId", false),
        target_to_revision_id: uuid(params, "toRevisionId"),
      };
    } else if (view === "health") {
      name = "get_pachanga_competition_venue_allocation_health_v1";
      args = { target_competition_id: uuid(params, "competitionId") };
    } else if (view === "series") {
      name = "get_pachanga_recurring_reservation_series_v1";
      args = { target_series_id: uuid(params, "seriesId") };
    } else if (view === "calendar") {
      name = "get_pachanga_recurring_reservation_calendar_v1";
      args = {
        range_end: date(params, "end"),
        range_start: date(params, "start"),
        target_series_id: uuid(params, "seriesId"),
      };
    } else if (view === "pool") {
      name = "get_pachanga_competition_venue_pool_v1";
      args = { target_pool_id: uuid(params, "poolId") };
    } else if (view === "match") {
      name = "get_pachanga_venue_allocation_match_v1";
      args = { target_canonical_match_id: uuid(params, "matchId") };
    } else if (view === "platform") {
      name = "get_pachanga_platform_venue_allocation_health_v1";
    } else if (view === "home") {
      name = "get_pachanga_season_venue_home_status_v1";
    } else {
      throw new Error("VENUE_READ_VIEW_INVALID");
    }
    const result = await client.rpc(name, args);
    if (result.error) throw new Error(result.error.message);
    return venueApiJson(result.data);
  } catch (error) {
    return venueApiError(error);
  }
}
