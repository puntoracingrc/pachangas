import { mkdir, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import configData from "../../season-ranking-lab/season_score_config.json";
import { isSeasonScoreEvidence } from "../../season-ranking-lab/src/engine";
import { enrichCompetitiveEvidence, evaluateV3Ranking, TROPHY_RULES } from "../../season-ranking-lab/src/integrity-v3";
import { createSimulationWorld } from "../../season-ranking-lab/src/simulator";
import type { SeasonScoreConfig } from "../../season-ranking-lab/src/types";
import { v3Baseline, worldGraph } from "../../season-ranking-lab/src/v3-validation";
import { buildSyntheticRankingFunnelAudit, type SyntheticRankingFunnelAudit } from "../src/ranking-funnel";
import { createRankingCounterfactualClone, type RankingCounterfactualId } from "../src/ranking-counterfactuals";
import { loadSyntheticLocalEnv } from "../src/local-env";
import { deterministicUuid } from "../src/random";
import { SyntheticWorldStore } from "../src/store";

const SOURCE_WORLD_ID = "3df9494d-3b8c-4447-96e8-d5244892af78";
const SOURCE_REVISION = 313;
const root = resolve(new URL("../../..", import.meta.url).pathname);
const generatedDirectory = resolve(root, "simulation/synthetic-world/generated");
const exportsDirectory = resolve(root, "simulation/synthetic-world/exports");

function round(value: number, digits = 3) {
  const factor = 10 ** digits;
  return Math.round(value * factor) / factor;
}

function average(values: number[]) {
  return values.length === 0 ? 0 : values.reduce((sum, value) => sum + value, 0) / values.length;
}

function percentile(values: number[], quantile: number) {
  if (values.length === 0) return 0;
  const sorted = [...values].sort((left, right) => left - right);
  const position = (sorted.length - 1) * quantile;
  const lower = Math.floor(position);
  const upper = Math.ceil(position);
  return lower === upper ? sorted[lower]! : sorted[lower]! + (sorted[upper]! - sorted[lower]!) * (position - lower);
}

function metric(values: number[]) {
  return { mean: round(average(values)), p25: round(percentile(values, 0.25)), p50: round(percentile(values, 0.5)), p75: round(percentile(values, 0.75)), p95: round(percentile(values, 0.95)) };
}

function mathematicalV3Reference() {
  const previous = (configData.candidates as SeasonScoreConfig[]).find(({ id }) => id === "candidate_e_recent20")!;
  const config = v3Baseline(previous);
  const world = createSimulationWorld({ playerCount: 10_000, seasonCount: 1, seed: configData.seed, teamSize: 10 });
  const inputs = world.inputsBySeason.get(world.seasons[0]!.id)!;
  const graph = worldGraph(world, inputs);
  const evaluated = evaluateV3Ranking({ config, graph, inputs, strategy: "exclusion_and_hold", trophyRule: TROPHY_RULES.province });
  const evidence = inputs.map((input) => enrichCompetitiveEvidence(input, graph).filter(({ record }) => isSeasonScoreEvidence(record)));
  const accepted = evidence.map((items) => items.filter(({ confidenceWeight }) => confidenceWeight > 0));
  return {
    acceptedChallengesPerPlayer: metric(accepted.map((items) => items.length)),
    competitiveConfidence: metric(evaluated.map(({ competitiveConfidence }) => competitiveConfidence)),
    eligibleRatio: round(evaluated.filter(({ eligibility }) => eligibility.eligible).length / evaluated.length),
    logicalOpponents: metric(evaluated.map(({ logicalOpponents }) => logicalOpponents)),
    networkDiversity: metric(evaluated.map(({ competitionNetworkDiversity }) => competitionNetworkDiversity)),
    players: evaluated.length,
    ratingReliability: metric(inputs.map(({ player }) => player.ratingReliability)),
    sourceChallengesPerPlayer: metric(inputs.map((input) => input.records.filter(isSeasonScoreEvidence).length)),
    trophyEligibleRatio: round(evaluated.filter(({ certification }) => certification === "eligible").length / evaluated.length),
  };
}

function markdownTable(headers: string[], rows: Array<Array<number | string>>) {
  return `| ${headers.join(" | ")} |\n| ${headers.map(() => "---").join(" | ")} |\n${rows.map((row) => `| ${row.join(" | ")} |`).join("\n")}`;
}

function reportMarkdown(options: {
  audit: SyntheticRankingFunnelAudit;
  clones: Array<{ addedMatches: number; audit: SyntheticRankingFunnelAudit; id: string; label: string; worldId: string }>;
  reference: ReturnType<typeof mathematicalV3Reference>;
}) {
  const { audit, clones, reference } = options;
  const funnel = markdownTable(
    ["Etapa", "Count", "% 640", "Pérdida", "Motivo principal"],
    audit.funnel.map((row) => [row.label, row.count, row.percentage, row.lossFromPrevious, row.mainReasonForLoss]),
  );
  const gates = markdownTable(
    ["Gate", "Falla solo", "Falla + otros", "Total falla", "Pasa"],
    audit.gates.gates.map((row) => [row.gate, row.failedOnlyThisGate, row.failedThisAndOthers, row.totalFailed, row.passed]),
  );
  const leaveOneOut = markdownTable(
    ["Gate eliminado", "Certificables"],
    audit.gates.leaveOneOut.map((row) => [row.removedGate, row.certificable]),
  );
  const counterfactuals = markdownTable(
    ["Clon", "Escenario", "Partidos añadidos", "Ranking", "Trofeo", "Pending", "Orgánico"],
    clones.map((row) => [row.id, row.label, row.addedMatches, row.audit.totals.rankingEligible, row.audit.totals.trophyEligible, row.audit.totals.pendingIntegrityReview, row.audit.totals.organicEligible]),
  );
  const confidence = markdownTable(
    ["Confidence", "Partidos", "Evidencia normal", "Evidencia atacante", "Total jugador-partido"],
    audit.confidence.matchDistribution.map((row, index) => [
      row.label,
      row.total,
      audit.confidence.playerEvidenceDistribution[index]!.normal,
      audit.confidence.playerEvidenceDistribution[index]!.attackers,
      audit.confidence.playerEvidenceDistribution[index]!.total,
    ]),
  );
  const challenges = markdownTable(
    ["Retos/jugador", "Total", "Barcelona", "Madrid", "Valencia", "Sevilla", "Girona", "Otros"],
    audit.retosDistribution.source.map((row) => [row.label, row.total, row.byProvince["08"], row.byProvince["28"], row.byProvince["46"], row.byProvince["41"], row.byProvince["17"], row.other]),
  );
  const top = markdownTable(
    ["#", "Jugador", "Provincia", "Score", "Retos", "Rivales", "Conf.", "Diversidad", "Fiabilidad", "Estado", "Bloqueo"],
    audit.topCandidates.map((row) => [row.rank, row.displayName, row.provinceCode, row.score, row.validChallenges, row.logicalOpponents, row.competitiveConfidence, row.networkDiversity, row.ratingReliability, row.certification, row.certificationBlockers.join(", ") || "none"]),
  );
  const pending = markdownTable(
    ["Matriz", "HOLD", "NO HOLD"],
    [
      ["attacker", audit.integrity.confusionAllRegistered.truePositive, audit.integrity.confusionAllRegistered.falseNegative],
      ["legitimate", audit.integrity.confusionAllRegistered.falsePositive, audit.integrity.confusionAllRegistered.trueNegative],
    ],
  );
  return `# Synthetic World V1.1 - Auditoría del embudo de ranking\n\n## Trazabilidad\n\n- Mundo preservado: \`${audit.checkpoint.worldId}\`.\n- Revisión auditada: \`${audit.checkpoint.revision}\`.\n- Secuencia de servidor: \`${audit.checkpoint.eventSequence}\`.\n- Checkpoint local: \`audit_checkpoint / ranking-funnel-v1.1-pre\`.\n- Reglas de producto: sin cambios; Rating V2 y facetas: solo lectura.\n- Conducta/reportes/no-show: pausados.\n\n## Significado exacto de los estados\n\nLas 135 filas son los jugadores que ya superaron **ranking eligibility** (15 evidencias aceptadas por B, 6 rivales lógicos, fiabilidad 0,45 y actividad reciente). Dentro de esas filas, \`eligible\`, \`not_eligible\` y \`pending_integrity_review\` son estados de **certificación/trofeo provincial**, no de aparición en ranking.\n\n- \`eligible\`: ${audit.stateMeaning.eligible}\n- \`not_eligible\`: ${audit.stateMeaning.notEligible}\n- \`pending_integrity_review\`: ${audit.stateMeaning.pendingIntegrityReview}\n\nResultado persistido: **${audit.totals.rankingEligible} ranking eligible**, **${audit.totals.trophyEligible} trophy eligible**, **${audit.totals.pendingIntegrityReview} pending**. El único trophy eligible depende de nueve partidos de control; sin ellos el mundo orgánico produce **${audit.totals.organicEligible}**.\n\n## Funnel de 640 jugadores\n\n${funnel}\n\n## Gates e intersecciones\n\n${gates}\n\nPatrones completos: \`${JSON.stringify(audit.gates.intersections)}\`.\n\n### Leave-one-gate-out\n\n${leaveOneOut}\n\nEl cuello dominante es \`network_diversity\`: 133/135 rankeados la fallan y retirarla aisladamente eleva el contrafactual estricto de 1 a 17. No es una recomendación para quitarla.\n\n## Qué significan las 950 evidencias\n\nLas 950 son **partidos de Reto confirmados/autoconfirmados marcados como no excluidos en el generador**, no filas player-match. El detalle real es:\n\n- ${audit.evidence.matchLevelChallengeEvidence} partidos de Reto con resultado canónico.\n- ${audit.evidence.matchLevelMarkedValid} partidos marcados válidos y ${audit.evidence.matchLevelMarkedExcluded} marcados excluidos.\n- ${audit.evidence.playerMatchSource} evidencias fuente jugador-partido.\n- ${audit.evidence.playerMatchAccepted} evidencias aceptadas por B.\n- ${audit.evidence.excludedPlayerMatchEvidence} evidencias jugador-partido excluidas por B.\n- ${audit.evidence.sourceMatchesWithoutEvidence.length} source matches elegibles sin evidencia derivada.\n\nNo aparece pérdida de integración player → match → evidence.\n\n## Participación\n\n- Participaciones totales en partidos cerrados: ${audit.participation.total}.\n- Registrados: ${audit.participation.registered}; invitados: ${audit.participation.guests}.\n- Retos: ${audit.participation.retos}; internos: ${audit.participation.internal}.\n- Retos por jugador p10/p25/p50/p75/p90/p95/max: ${Object.values(audit.participation.challengeParticipationsPerRegisteredPlayer).join(" / ")}.\n\n${challenges}\n\n## Rivales lógicos\n\n${audit.opponents.collapseRows.length} jugadores tuvieron >=10 team IDs rivales pero <10 rivales lógicos. Clasificación: \`${JSON.stringify(audit.opponents.collapseClassification)}\`. Los colapsos observados corresponden al anillo sintético de equipos falsos; no se encontró un false positive estructural de colapso.\n\n## Confidence y exclusión B\n\n${confidence}\n\nMotivos multi-label de exclusión: ${audit.evidence.excludedByReason.map((row) => `${row.reason}=${row.evidence}`).join(", ")}.\n\n## Holds C\n\n${pending}\n\nLos ${audit.totals.pendingIntegrityReview} pending incluyen ${audit.integrity.falsePositiveHolds.length} agentes etiquetados como legítimos y 4 atacantes. Todos fallan diversidad; ${audit.integrity.pendingByReason.low_confidence_dependency ?? 0} dependen además de evidencia débil. En la cohorte ranking-eligible hay ${audit.integrity.confusionRankingEligible.falseNegative} atacantes sin hold, pero no son trophy eligible por otros gates.\n\n## Densidad y actividad\n\n- Retos medios/equipo: ${audit.density.meanChallengesPerTeam}.\n- Rivales únicos medios/equipo: ${audit.density.meanUniqueOpponentsPerTeam}.\n- Plantilla media: ${audit.density.meanRoster}.\n- Participación media de plantilla por Reto: ${round(audit.density.meanRosterParticipation * 100, 1)}%.\n- Retos/jugador p50: ${audit.density.playerActivity.challengesPerMonth.p50}/mes; p90: ${audit.density.playerActivity.challengesPerMonth.p90}/mes.\n\nLa rotación no se considera demostrablemente defectuosa: aproximadamente media plantilla participa en cada Reto, coherente con plantillas superiores al equipo de campo. El mundo sí concentra volumen extremo en pocos agentes (máximo ${audit.participation.challengeParticipationsPerRegisteredPlayer.max} Retos) y deja 112 registrados sin Reto.\n\n## Top 50 candidatos\n\n${top}\n\n## Top 20 Barcelona, lectura derivada\n\n${audit.topBarcelonaNarrative.map(({ narrative }) => `- ${narrative}`).join("\n")}\n\n## Comparación con la simulación matemática V3\n\n| Métrica p50 | Synthetic World | V3 10k |\n| --- | ---: | ---: |\n| Evidencias aceptadas/jugador | ${audit.participation.challengeParticipationsPerRegisteredPlayer.p50} fuente / ${round(percentile(audit.players.map(({ acceptedEvidence }) => acceptedEvidence), 0.5))} aceptadas | ${reference.acceptedChallengesPerPlayer.p50} |\n| Rivales lógicos | ${round(percentile(audit.players.map(({ logicalOpponents }) => logicalOpponents), 0.5))} | ${reference.logicalOpponents.p50} |\n| Confidence | ${round(percentile(audit.players.map(({ competitiveConfidence }) => competitiveConfidence), 0.5))} | ${reference.competitiveConfidence.p50} |\n| Network diversity | ${round(percentile(audit.players.map(({ competitionNetworkDiversity }) => competitionNetworkDiversity), 0.5))} | ${reference.networkDiversity.p50} |\n| Reliability | ${round(percentile(audit.players.map(({ ratingReliability }) => ratingReliability), 0.5))} | ${reference.ratingReliability.p50} |\n| Ranking eligible ratio | ${round(audit.totals.rankingEligible / audit.totals.registered)} | ${reference.eligibleRatio} |\n| Trophy eligible ratio | ${round(audit.totals.trophyEligible / audit.totals.registered)} | ${reference.trophyEligibleRatio} |\n\nLa divergencia principal es la estructura social: 50 equipos, redes provinciales pequeñas, repetición y participantes distribuidos de forma muy desigual frente al grafo amplio de 10.000 jugadores.\n\n## Contrafactuales A-E\n\n${counterfactuals}\n\nD no muta el mundo: la auditoría no demostró que la rotación fuese un defecto. E mide el efecto de los holds, no propone desactivarlos.\n\n## Hipótesis A-G\n\n- **A SIMULATION_DENSITY: principal.** 133/135 rankeados fallan diversidad y el grafo solo tiene 50 equipos.\n- **B SYNTHETIC_AGENT_BEHAVIOR: contribuye.** ${audit.evidence.excludedPlayerMatchEvidence}/${audit.evidence.playerMatchSource} evidencias se excluyen y existe una cola extrema de actividad.\n- **C PRODUCT_FLOW_LOSS: no respaldada.** El invariante encuentra ${audit.evidence.sourceMatchesWithoutEvidence.length} pérdidas.\n- **D SEASON_SCORE_INTEGRATION_BUG: no respaldada en creación de evidencia.** Sí se corrigió drift de configuración del adaptador, sin alterar el mundo V1.\n- **E V3_RULE_TOO_STRICT: posible, no decidida.** Diversidad domina en este mundo, pero los clones y V3 10k deben guiar la decisión humana.\n- **F INTEGRITY_FALSE_POSITIVES: visible pero atribuible en gran parte al mundo.** ${audit.integrity.falsePositiveHolds.length} legítimos quedan pending; su red sintética es objetivamente cerrada.\n- **G EXPECTED_BEHAVIOR: parcial.** Casual y low-activity no certifican, como se espera; que el jugador muy activo tampoco pueda hacerlo casi nunca no es deseable.\n\n## Recomendación\n\nMantener por ahora las reglas V3. No hay evidencia para relajar 25/10 sin una nueva población más amplia y orgánica. Corregir Synthetic World V2 para no inyectar elegibilidad, usar la configuración V3 exacta y generar más equipos/rivales independientes de forma natural; repetir entonces esta misma auditoría.\n`;
}

function reportAppendix(audit: SyntheticRankingFunnelAudit) {
  const distributionTable = (rows: typeof audit.playerDistributions.networkDiversity) => markdownTable(
    ["Tramo", "Total", "Barcelona", "Madrid", "Valencia", "Sevilla", "Girona", "Otros"],
    rows.map((row) => [row.label, row.total, row.byProvince["08"], row.byProvince["28"], row.byProvince["46"], row.byProvince["41"], row.byProvince["17"], row.other]),
  );
  const logicalOpponents = markdownTable(
    ["Rivales", "Team IDs", "Logical opponents"],
    audit.opponents.technicalDistribution.map((row, index) => [row.label, row.total, audit.opponents.logicalDistribution[index]!.total]),
  );
  const activityScenarios = markdownTable(
    ["Actividad", "Jugadores", "Ranking", "% ranking", "Trofeo", "% trofeo"],
    audit.density.activityScenarios.map((row) => [row.classification, row.count, row.rankingEligible, row.rankingEligiblePercentage, row.trophyEligible, row.trophyEligiblePercentage]),
  );
  const provinces = markdownTable(
    ["Provincia", "Jugadores", "Retos p50", "Rivales p50", "Confidence p50", "Diversity p50", "Ranking", "Trofeo", "Pending"],
    audit.provinceComparison.map((row) => [row.provinceCode, row.registered, row.medianChallenges, row.medianLogicalOpponents, row.medianConfidence, row.medianDiversity, row.rankingEligible, row.trophyEligible, row.pendingIntegrityReview]),
  );
  const topDiagnostics = markdownTable(
    ["#", "Jugador", "Actividad", "Integridad", "Ranking provincial", "Bloqueos"],
    audit.topCandidates.map((row) => [row.rank, row.displayName, `${row.activityWeeksAgo} semanas`, row.integrityRisk, row.provinceRank ?? "fuera", row.certificationBlockers.join(", ") || "none"]),
  );
  return `
## Distribuciones complementarias

### Team IDs frente a rivales lógicos

${logicalOpponents}

### Network diversity

${distributionTable(audit.playerDistributions.networkDiversity)}

### Rating reliability

${distributionTable(audit.playerDistributions.ratingReliability)}

### Recencia de actividad

${distributionTable(audit.playerDistributions.activityRecency)}

### Escenarios de actividad

${activityScenarios}

### Comparación provincial

${provinces}

### Actividad e integridad del Top 50

${topDiagnostics}

## Incidencias y regresiones

- \`SW-0059\`: separación explícita entre partido y evidencia jugador-partido.
- \`SW-0060\`: la cobertura artificial deja de activarse por defecto; el V1 preservado conserva sus nueve controles como historia.
- \`SW-0061\`: cohorts attacker/legitimate calculadas por propietario de la evidencia, no por partido completo.
- \`SW-0062\`: configuración exacta V3 restaurada en el adaptador sintético.
- \`SW-0063\`: percentiles y narrativa del informe etiquetados sin ambigüedad.
- \`SW-0064\`: identidad única para las etapas duplicadas del funnel, verificada sin errores de consola.
- \`SW-0065\`: runner de concurrencia ejecutado con mundo QA local explícito, sin mutar V1.
- \`SW-0066\`: lint focalizado V1.1 sin símbolos muertos ni avisos.
`;
}

async function main() {
  loadSyntheticLocalEnv();
  const store = new SyntheticWorldStore();
  const source = await store.loadWorld(SOURCE_WORLD_ID);
  if (source.revision !== SOURCE_REVISION) throw new Error(`SOURCE_WORLD_CHANGED expected ${SOURCE_REVISION}, actual ${source.revision}`);
  const audit = buildSyntheticRankingFunnelAudit(source);
  const existing = new Set((await store.listWorlds()).map(({ id }) => id));
  const clones: Array<{ addedMatches: number; audit: SyntheticRankingFunnelAudit; id: string; label: string; worldId: string }> = [];
  for (const id of ["A", "B", "C", "D", "E"] as RankingCounterfactualId[]) {
    const prepared = createRankingCounterfactualClone(source, id);
    let clone = prepared.clone;
    if (!existing.has(clone.id)) {
      await store.saveWorld(clone, {
        expectedRevision: -1,
        operationId: deterministicUuid(`${clone.id}:persist-ranking-counterfactual`, id),
        snapshotKind: "checkpoint",
        snapshotPayload: clone,
      });
    } else {
      clone = await store.loadWorld(clone.id);
    }
    clones.push({ addedMatches: prepared.addedMatches, audit: buildSyntheticRankingFunnelAudit(clone, { strategy: prepared.scenario.strategy, trophyRule: prepared.scenario.trophyRule }), id, label: prepared.scenario.label, worldId: clone.id });
  }
  const reference = mathematicalV3Reference();
  const result = {
    auditedAt: new Date().toISOString(),
    audit,
    clones,
    reference,
    sourceRevision: source.revision,
    sourceWorldId: source.id,
  };
  await mkdir(generatedDirectory, { recursive: true });
  await mkdir(exportsDirectory, { recursive: true });
  await writeFile(resolve(exportsDirectory, "ranking-funnel-v1.1-full.json"), `${JSON.stringify(result, null, 2)}\n`, "utf8");
  await writeFile(resolve(generatedDirectory, "ranking-funnel-v1.1-summary.json"), `${JSON.stringify({
    auditedAt: result.auditedAt,
    clones: clones.map(({ addedMatches, audit: cloneAudit, id, label, worldId }) => ({ addedMatches, id, label, totals: cloneAudit.totals, worldId })),
    reference,
    source: { checkpoint: audit.checkpoint, totals: audit.totals },
  }, null, 2)}\n`, "utf8");
  await writeFile(resolve(root, "RANKING_FUNNEL_V1_1_REPORT.md"), `${reportMarkdown({ audit, clones, reference })}${reportAppendix(audit)}`, "utf8");
  process.stdout.write(`${JSON.stringify({ clones: clones.map(({ addedMatches, audit: cloneAudit, id, worldId }) => ({ addedMatches, id, rankingEligible: cloneAudit.totals.rankingEligible, trophyEligible: cloneAudit.totals.trophyEligible, pending: cloneAudit.totals.pendingIntegrityReview, worldId })), evidence: audit.evidence, reference, source: audit.totals }, null, 2)}\n`);
}

void main().catch((error) => {
  process.stderr.write(`${error instanceof Error ? error.stack ?? error.message : String(error)}\n`);
  process.exitCode = 1;
});
