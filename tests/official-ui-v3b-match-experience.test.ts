import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import "./official-ui-v3c-simple-challenges.test";
import "./official-ui-v3e-social-onboarding.test";

const root = process.cwd();
const source = (file: string) => readFile(path.join(root, file), "utf8");

test("Partidos opens a real Próximos and Historial overview", async () => {
  const [page, experience] = await Promise.all([
    source("app/page.tsx"),
    source("app/_components/official-match-experience.tsx"),
  ]);
  assert.match(experience, /Próximos <b>\{upcoming\.length\}<\/b>/);
  assert.match(experience, /Historial <b>\{history\.length\}<\/b>/);
  assert.match(page, /const matchOverviewUpcoming = openMatches\.map\(officialMatchSummary\)/);
  assert.match(page, /const matchOverviewHistory = closedMatches\.map\(officialMatchSummary\)/);
  assert.match(page, /function openMatchesByDate\(matches: Match\[\]\)[\s\S]*dateDelta[\s\S]*localeCompare/);
  assert.match(page, /const closedMatches = matches[\s\S]*sort\(\(a, b\) => new Date\(b\.date\)\.getTime\(\) - new Date\(a\.date\)\.getTime\(\)\)/);
  assert.match(page, /setMatchExperienceView\("overview"\)/);
});

test("the quick creator has exactly three progressive steps and folded advanced fields", async () => {
  const experience = await source("app/_components/official-match-experience.tsx");
  assert.match(experience, /useState<1 \| 2 \| 3>\(1\)/);
  assert.match(experience, /\[1, 2, 3\]\.map/);
  assert.match(experience, /Cuándo y dónde/);
  assert.match(experience, /Jugadores y plazas/);
  assert.match(experience, /Revisar y crear/);
  assert.match(experience, /<details className=\{styles\.advanced\}>/);
  assert.match(experience, /Coste del campo/);
  assert.match(experience, /Máximo reservas/);
});

test("one draft is resumed and repeat never copies sporting outcomes", async () => {
  const page = await source("app/page.tsx");
  assert.match(page, /const existingDraft = matches\.find/);
  assert.match(page, /if \(!discardedMatchDraftIds\.has\(existingDraft\.id\)\)/);
  assert.match(page, /function resumeQuickMatchWizard/);
  const factory = page.slice(page.indexOf("function createMatch"), page.indexOf("async function toggleLineupClosed"));
  assert.match(factory, /players: \[\]/);
  assert.match(factory, /payerId: undefined/);
  assert.doesNotMatch(factory, /scoreA:/);
  assert.doesNotMatch(factory, /scoreB:/);
  assert.doesNotMatch(factory, /scorers:/);
  assert.doesNotMatch(factory, /teamA:/);
  assert.doesNotMatch(factory, /teamB:/);
});

test("attendance is one touch, role-aware and grouped without exposing full cards", async () => {
  const [page, experience] = await Promise.all([
    source("app/page.tsx"),
    source("app/_components/official-match-experience.tsx"),
  ]);
  assert.match(experience, /\["voy", "duda", "no"\] as const/);
  assert.match(experience, /aria-pressed=\{currentStatus === status\}/);
  assert.match(experience, /Confirmados/);
  assert.match(experience, /Sin respuesta/);
  assert.match(experience, /No van/);
  assert.match(page, /canRespond=\{canRespondToActiveMatch\}/);
  assert.match(page, /onManagePlayer=\{canUseAdminControls/);
  assert.match(page, /if \(hasRealTeam\) \{[\s\S]*Tu asistencia no se ha guardado/);
  assert.doesNotMatch(experience, /rating|facets|phone|telephone/i);
});

test("the match detail exposes one role and state aware primary action", async () => {
  const page = await source("app/page.tsx");
  assert.match(page, /const matchPrimaryAction = matchFinalized/);
  assert.match(page, /label: "Gestionar convocatoria"/);
  assert.match(page, /label: "Crear equipos"/);
  assert.match(page, /label: "Añadir resultado"/);
  assert.match(page, /label: "Ver resultado"/);
  assert.match(page, /label: "Confirmar asistencia"/);
  assert.match(page, /status: matchPrimaryAction \? \(/);
  assert.doesNotMatch(page, /status: canToggleLineupFromContext/);
});

test("teams stay empty before generation and preserve the game pitch afterwards", async () => {
  const page = await source("app/page.tsx");
  assert.match(page, /const teamsPrepared = Boolean\(savedLineup \|\| lineupClosed \|\| matchFinalized\)/);
  assert.match(page, /Los equipos todavía no están preparados/);
  assert.match(page, /Generar equipos equilibrados/);
  assert.match(page, /<MatchPitch/);
  assert.match(page, /onPlayerSwap=\{swapLineupPlayers\}/);
  assert.match(page, /Equipo A/);
  assert.match(page, /Equipo B/);
});

test("result entry is two-step and finalized matches are read-only by default", async () => {
  const page = await source("app/page.tsx");
  assert.match(page, /useState<1 \| 2>\(1\)/);
  assert.match(page, /1 · Marcador/);
  assert.match(page, /2 · Goleadores opcionales/);
  assert.match(page, /Confirmar resultado/);
  assert.match(page, /className="final-result-hero"/);
  assert.match(page, /Corregir resultado/);
  assert.match(page, /saveResultCorrection/);
  assert.match(page, /resultCorrectionScorers/);
  assert.match(page, /if \(matchFinalized && resultCorrectionOpen\) \{[\s\S]*?setResultCorrectionScorers\(cleanScorers\);[\s\S]*?return;/);
  assert.match(page, /const scorers = resultCorrectionScorers;/);
  assert.match(page, /patch_pachanga_match_scorers_authoritative_v2/);
  assert.match(page, /final-team-photo/);
  assert.match(page, /Resultado pendiente/);
});

test("deep links, sharing and offline match writes stay explicit", async () => {
  const page = await source("app/page.tsx");
  assert.match(page, /function openMatchFromInicio\(matchId: string, pane: MatchManagerPane = "proximo"\)/);
  assert.match(page, /setMatchExperienceView\("detail"\)/);
  assert.match(page, /navigateMobileTab\("partido"\)/);
  assert.match(page, /typeof navigator\.share === "function"/);
  assert.match(page, /await navigator\.share/);
  assert.match(page, /La corrección no se ha guardado/);
  assert.match(page, /Los goleadores no se han guardado/);
  assert.match(page, /El pago no se ha guardado/);
});

test("the social Demo implements the same local journey with zero remote writes", async () => {
  const demo = await source("app/demo-world/demo-world-app.tsx");
  assert.match(demo, /OfficialMatchesOverview/);
  assert.match(demo, /OfficialQuickMatchWizard/);
  assert.match(demo, /demo_session_social_match/);
  assert.match(demo, /Solicitud de plaza creada solo en esta sesión demo/);
  assert.match(demo, /Resultado confirmado en la sesión demo/);
  assert.match(demo, /Sin goleadores registrados/);
  assert.match(demo, /remoteWrites = 0/);
  assert.match(demo, /externalNotifications = 0/);
  assert.match(demo, /realEntities = 0/);
  assert.match(demo, /StripeCalls = 0/);
  assert.match(demo, /demoAttendanceKey\(currentPlayer\.id, match\.id\)/);
  assert.match(demo, /demoSocialMatchJourney/);
  assert.match(demo, /slice\(0, 11\)/);
  assert.match(demo, /confirmedPlayerIds: \[\]/);
  assert.match(demo, /homePlayerIds: \[\]/);
  assert.match(demo, /Los equipos todavía no están preparados/);
  assert.match(demo, /Generar equipos equilibrados/);
  assert.doesNotMatch(demo, /supabaseClient|\.rpc\(|method:\s*["'](?:POST|PUT|PATCH|DELETE)/);
});

test("V3A destinations and role separation remain intact", async () => {
  const [page, nav, demo, challenges, externalResults] = await Promise.all([
    source("app/page.tsx"),
    source("app/_components/product-navigation-contract.ts"),
    source("app/demo-world/demo-world-app.tsx"),
    source("app/mercado/team-challenges-panel.tsx"),
    source("app/mercado/external-results-panel.tsx"),
  ]);
  assert.match(nav, /inicio/);
  assert.match(nav, /partido/);
  assert.match(nav, /retos/);
  assert.match(nav, /mercado/);
  assert.match(page, /canUseAdminControls/);
  assert.match(demo, /perspective\.role === "admin"/);
  assert.match(demo, /perspective\.role === "player"/);
  assert.match(challenges, /matchChallengeId/);
  assert.match(challenges, />Ver partido<\/button>/);
  assert.match(challenges, /initialChallengeId=\{matchChallengeId\}/);
  assert.match(externalResults, /match\.challengeId === initialChallengeId/);
});

test("V3B is responsive, reduced-motion aware and no longer claims V2 Preview", async () => {
  const [styles, matchStyles, demoStyles, contract, page] = await Promise.all([
    source("app/_components/official-match-experience.module.css"),
    source("app/_components/official-match-game-hub.module.css"),
    source("app/demo-world/demo-world.module.css"),
    source("app/_design-v2/official-ui-v2-contract.ts"),
    source("app/page.tsx"),
  ]);
  assert.match(styles, /@media \(max-width: 760px\) and \(orientation: portrait\)/);
  assert.match(styles, /@media \(orientation: landscape\) and \(max-height: 600px\)/);
  assert.match(styles, /prefers-reduced-motion/);
  assert.match(matchStyles, /data-official-match-hub="v3b"/);
  assert.match(demoStyles, /\.toast\s*\{[\s\S]*?background:\s*#142119;[\s\S]*?color:\s*#f1f6f2;/);
  assert.match(demoStyles, /\.demoResultEntry\s*\{[\s\S]*?--demo-ink:\s*#f1f6f2;[\s\S]*?--demo-lime:\s*#c8ef5d;/);
  assert.match(contract, /"3\.2\.0"/);
  assert.doesNotMatch(contract, /preview/i);
  assert.doesNotMatch(page, /Mundo Demo V1/);
});
