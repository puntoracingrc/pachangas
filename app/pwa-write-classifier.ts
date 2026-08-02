const v1WriteRpcNames = new Set([
  "accept_pachanga_admin_invite",
  "append_pachanga_player_rating",
  "complete_pachanga_player_advanced_assessment",
  "complete_pachanga_player_initial_assessment",
  "create_pachanga_admin_invite",
  "create_pachanga_group_backup",
  "finalize_pachanga_match_if_current",
  "join_pachanga_team",
  "patch_pachanga_match_lineup_state",
  "patch_pachanga_match_player_paid",
  "patch_pachanga_match_player_status",
  "patch_pachanga_match_scorers",
  "patch_pachanga_player_profile",
  "request_pachanga_open_match",
  "restore_pachanga_group_backup",
  "review_pachanga_open_match_request",
  "save_pachanga_payload_if_current",
  "set_pachanga_member_role",
  "sync_pachanga_market_profile",
  "sync_pachanga_open_match",
  "update_pachanga_member_name",
  "upsert_pachanga_own_player_profile",
]);

const writeMethods = new Set(["DELETE", "PATCH", "POST", "PUT"]);
const v1DirectTableWriteOperations = new Set([
  "table:pachanga_group_members:post",
  "table:pachanga_groups:delete",
  "table:pachanga_groups:post",
]);
const v1ApplicationWriteOperations = new Set([
  "api:billing-checkout",
  "api:billing-portal",
]);

export function requestMethod(input: RequestInfo | URL, init?: RequestInit) {
  if (init?.method) return init.method.toUpperCase();
  if (typeof Request !== "undefined" && input instanceof Request) return input.method.toUpperCase();
  return "GET";
}

export function classifySupabaseWrite(input: RequestInfo | URL, init?: RequestInit) {
  const method = requestMethod(input, init);
  if (!writeMethods.has(method)) return null;

  const rawUrl = typeof input === "string" || input instanceof URL ? String(input) : input.url;
  let url: URL;
  try {
    url = new URL(rawUrl);
  } catch {
    return null;
  }

  const rpcPrefix = "/rest/v1/rpc/";
  if (url.pathname.startsWith(rpcPrefix)) {
    const rpcName = decodeURIComponent(url.pathname.slice(rpcPrefix.length));
    return v1WriteRpcNames.has(rpcName) ? `rpc:${rpcName}` : null;
  }

  const tablePrefix = "/rest/v1/";
  if (!url.pathname.startsWith(tablePrefix)) return null;
  const tableName = decodeURIComponent(url.pathname.slice(tablePrefix.length)).split("/")[0];
  return tableName ? `table:${tableName}:${method.toLowerCase()}` : null;
}

export function knownV1WriteRpcNames() {
  return [...v1WriteRpcNames].sort();
}

export function isKnownClientWriteOperation(operation: string) {
  if (operation.startsWith("rpc:")) return v1WriteRpcNames.has(operation.slice(4));
  return v1DirectTableWriteOperations.has(operation) || v1ApplicationWriteOperations.has(operation);
}
