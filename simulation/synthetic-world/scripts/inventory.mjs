import { mkdir, readFile, readdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(scriptDir, "../../..");
const outputDir = path.join(repoRoot, "simulation/synthetic-world/generated");

async function filesBelow(directory, extensions) {
  const entries = await readdir(directory, { withFileTypes: true });
  const nested = await Promise.all(entries.map(async (entry) => {
    const target = path.join(directory, entry.name);
    if (entry.isDirectory()) return filesBelow(target, extensions);
    return extensions.some((extension) => entry.name.endsWith(extension)) ? [target] : [];
  }));
  return nested.flat();
}

function unique(values) {
  return [...new Set(values)].sort((left, right) => left.localeCompare(right));
}

function relative(file) {
  return path.relative(repoRoot, file);
}

function extractAll(source, pattern, group = 1) {
  return [...source.matchAll(pattern)].map((match) => match[group]).filter(Boolean);
}

function extractAchievementKeys(source) {
  const blocks = extractAll(
    source,
    /insert\s+into\s+public\.pachanga_achievement_definitions\s*\([\s\S]*?\)\s*values\s*([\s\S]*?)(?:on\s+conflict|;)/gi,
  );
  return unique(blocks.flatMap((block) => extractAll(block, /(?:^|,)\s*\(\s*'([a-z][a-z0-9_]+)'/g)));
}

function classifyRpc(name, clientRpcNames) {
  const calledByClient = clientRpcNames.has(name);
  const readOnly = /^(get_|search_|lookup_|list_|pachanga_.*snapshot|pachanga_.*context)/.test(name);
  return {
    calledByClient,
    classification: calledByClient ? "implemented" : "partially_implemented",
    mutation: !readOnly,
    name,
  };
}

function categoryForRpc(name) {
  if (/rating|assessment/.test(name)) return "rating";
  if (/achievement|reward|progression|crest|cosmetic/.test(name)) return "progression";
  if (/notification/.test(name)) return "notifications";
  if (/challenge|opponent/.test(name)) return "challenges";
  if (/market|open_match/.test(name)) return "market";
  if (/external_result|external_match|scorer/.test(name)) return "results";
  if (/match|lineup|player_paid/.test(name)) return "matches";
  if (/group|team|member|invite/.test(name)) return "teams";
  return "other";
}

const requestedCapabilities = [
  ["teams", "Crear equipo", ["pachanga_groups"]],
  ["teams", "Invitar y aceptar miembro", ["create_pachanga_admin_invite", "accept_pachanga_admin_invite", "join_pachanga_team"]],
  ["teams", "Abandonar grupo", ["leave_pachanga_group"]],
  ["challenges", "Crear reto", ["create_pachanga_team_challenge_authoritative"]],
  ["challenges", "Aceptar, rechazar o contrapropuesta", ["respond_pachanga_team_challenge_authoritative"]],
  ["challenges", "Caducar reto", ["expire_pachanga_team_challenge"]],
  ["market", "Equipo busca jugador", ["sync_pachanga_open_match_authoritative_v2", "request_pachanga_open_match_authoritative_v2"]],
  ["market", "Jugador busca equipo", ["sync_pachanga_market_profile_authoritative_v2"]],
  ["matches", "Confirmar asistencia", ["patch_pachanga_match_player_status_authoritative_v2"]],
  ["matches", "Modificar alineacion", ["patch_pachanga_match_lineup_authoritative_v2"]],
  ["matches", "Finalizar partido interno", ["finalize_pachanga_match_authoritative_v2"]],
  ["results", "Publicar resultado externo", ["publish_pachanga_external_result_v1"]],
  ["results", "Confirmar, rechazar o corregir resultado", ["confirm_pachanga_external_result_v1", "reject_pachanga_external_result_change_v1", "propose_pachanga_external_result_change_v1"]],
  ["results", "Auto-confirmar por plazo", ["run_pachanga_external_result_expiry_v1"]],
  ["rating", "Assessment inicial y avanzado", ["persist_pachanga_player_assessment_authoritative_v2"]],
  ["rating", "Valoracion entre jugadores", ["record_pachanga_individual_rating_authoritative_v2"]],
  ["progression", "Evaluar logros", ["get_pachanga_progression_snapshot_v1"]],
  ["progression", "Abrir caja", ["open_pachanga_reward_box_v2"]],
  ["notifications", "Leer y marcar notificaciones", ["get_pachanga_notification_center_v1", "mark_pachanga_notification_read_v1"]],
  ["integrity", "Season Score V3", []],
];

const sqlFiles = await filesBelow(path.join(repoRoot, "supabase/migrations"), [".sql"]);
const appFiles = await filesBelow(path.join(repoRoot, "app"), [".ts", ".tsx"]);
const sqlSources = await Promise.all(sqlFiles.map(async (file) => ({ file, source: await readFile(file, "utf8") })));
const appSources = await Promise.all(appFiles.map(async (file) => ({ file, source: await readFile(file, "utf8") })));

const clientRpcCalls = appSources.flatMap(({ file, source }) =>
  extractAll(source, /\.rpc\(\s*["']([^"']+)["']/g).map((name) => ({ file: relative(file), name })),
);
const clientRpcNames = new Set(clientRpcCalls.map(({ name }) => name));
const rpcDefinitions = sqlSources.flatMap(({ file, source }) =>
  extractAll(source, /create\s+(?:or\s+replace\s+)?function\s+(?:public|private)\.([a-zA-Z0-9_]+)/gi)
    .map((name) => ({ file: relative(file), name })),
);
const canonicalRpcNames = unique(rpcDefinitions.map(({ name }) => name));
const tables = unique(sqlSources.flatMap(({ source }) => extractAll(source, /create\s+table\s+(?:if\s+not\s+exists\s+)?(?:public|private)\.([a-zA-Z0-9_]+)/gi)));
const appTableWrites = unique(appSources.flatMap(({ source }) =>
  extractAll(source, /\.from\(\s*["']([^"']+)["']\s*\)[\s\S]{0,180}?\.(?:insert|update|upsert|delete)\s*\(/g),
));
const allSql = sqlSources.map(({ source }) => source).join("\n");
const statuses = unique(extractAll(allSql, /check\s*\([^;]{0,400}?\bin\s*\(([^)]+)\)/gi)
  .flatMap((list) => extractAll(list, /'([^']+)'/g))
  .filter((value) => value.length <= 80));
const notificationKinds = unique(extractAll(allSql, /'([a-z][a-z0-9_]*(?:notification|invite|invitation|challenge|attendance|achievement|reward|result|market|member|availability)[a-z0-9_]*)'/g));
const achievementKeys = unique([
  ...sqlSources.flatMap(({ source }) => extractAchievementKeys(source)),
  ...extractAll(allSql, /'((?:player|team)\.[a-z0-9_.]+)'/g),
]);
const timeDependencies = sqlSources.flatMap(({ file, source }) => source.split("\n").flatMap((line, index) =>
  /\bnow\(\)|clock_timestamp\(\)|current_timestamp|expires_at|auto_confirmation|make_interval/i.test(line)
    ? [{ file: relative(file), line: index + 1, text: line.trim().slice(0, 240) }]
    : [],
));

const rpcInventory = canonicalRpcNames.map((name) => ({ ...classifyRpc(name, clientRpcNames), category: categoryForRpc(name) }));
const canonicalNames = new Set([...canonicalRpcNames, ...tables]);
const capabilities = requestedCapabilities.map(([category, label, candidates]) => {
  const implemented = candidates.filter((candidate) => canonicalNames.has(candidate));
  const called = implemented.filter((candidate) => clientRpcNames.has(candidate) || appTableWrites.includes(candidate));
  return {
    called,
    candidates,
    category,
    classification: implemented.length === 0
      ? (category === "integrity" ? "implemented_lab" : "not_implemented")
      : called.length === implemented.length ? "implemented" : "partially_implemented",
    implemented,
    label,
  };
});

const inventory = {
  generatedAt: new Date().toISOString(),
  sourceCommit: process.env.SYNTHETIC_WORLD_SOURCE_COMMIT ?? "4c75d52e15449528fe206e4d542715ec96d42422",
  counts: {
    achievements: achievementKeys.length,
    appRpcCalls: unique(clientRpcCalls.map(({ name }) => name)).length,
    appTableWrites: appTableWrites.length,
    capabilities: capabilities.length,
    notificationKinds: notificationKinds.length,
    rpcDefinitions: canonicalRpcNames.length,
    tables: tables.length,
    timeDependencies: timeDependencies.length,
  },
  capabilities,
  rpcs: rpcInventory,
  clientRpcCalls,
  appTableWrites,
  tables,
  states: statuses,
  notificationKinds,
  achievementKeys,
  timeDependencies,
};

const capabilityRows = capabilities.map((item) =>
  `| ${item.category} | ${item.label} | ${item.classification} | ${item.implemented.join(", ") || "-"} | ${item.called.join(", ") || "-"} |`,
).join("\n");
const markdown = `# Synthetic World product inventory\n\nGenerated from product SQL and client code at \`${inventory.sourceCommit}\`. This file distinguishes definitions from active client call sites; it is not proof that a remote environment has applied a migration.\n\n## Counts\n\n- RPC definitions: ${inventory.counts.rpcDefinitions}\n- RPC called by the web client: ${inventory.counts.appRpcCalls}\n- Product tables: ${inventory.counts.tables}\n- Mutable table targets in the web client: ${inventory.counts.appTableWrites}\n- Achievement keys found: ${inventory.counts.achievements}\n- Notification/status literals found: ${inventory.counts.notificationKinds}\n- Time-dependent SQL lines: ${inventory.counts.timeDependencies}\n\n## Capability matrix\n\n| Area | Flow | Classification | Located contracts | Active web call sites |\n| --- | --- | --- | --- | --- |\n${capabilityRows}\n\n## Interpretation\n\n- \`implemented\`: a product contract exists and the current web client invokes every located candidate.\n- \`partially_implemented\`: at least one contract exists, but part of the requested flow lacks an active web call site.\n- \`not_implemented\`: no matching product contract was located.\n- \`implemented_lab\`: implemented only by the isolated Season Score laboratory and never presented as production behaviour.\n\nThe machine-readable inventory is \`product-inventory.json\`.\n`;

await mkdir(outputDir, { recursive: true });
await writeFile(path.join(outputDir, "product-inventory.json"), `${JSON.stringify(inventory, null, 2)}\n`);
await writeFile(path.join(outputDir, "product-inventory.md"), markdown);
console.log(JSON.stringify(inventory.counts, null, 2));
