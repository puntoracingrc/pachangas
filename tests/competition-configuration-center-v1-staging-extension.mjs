import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";

function configurationCommand(client, metadata, {
  action,
  aggregateId,
  expectedRevision,
  operationId = randomUUID(),
  payload = {},
}) {
  return client.rpc("command_pachanga_competition_configuration_v1", {
    aggregate_id: aggregateId,
    client_metadata: metadata("competition-configuration-staging"),
    command_action: action,
    command_payload: payload,
    expected_revision: expectedRevision,
    operation_id: operationId,
  });
}

async function configurationCommandOk(client, metadata, input) {
  const result = await configurationCommand(client, metadata, input);
  if (result.error) {
    throw new Error(
      `${input.action}@${input.expectedRevision} [${result.error.code}] ${result.error.message}`,
      { cause: result.error },
    );
  }
  return result.data;
}

function expectConfigurationError(result, pattern, code) {
  assert.ok(result.error, `Expected configuration error ${pattern}`);
  const diagnostic = [
    result.error.code,
    result.error.message,
    result.error.details,
    result.error.hint,
  ].filter(Boolean).join(" ");
  assert.equal(result.error.code, code, diagnostic);
  assert.match(diagnostic, pattern);
}

export function createCompetitionConfigurationStagingState() {
  return {
    activeDraftRevisions: new Map(),
    advancedRuleRevisionId: null,
    competitionId: null,
    configurationDraftIds: [],
    futureRuleRevisionId: null,
  };
}

export async function runCompetitionConfigurationBeforeRegistration({
  actor,
  competitionId,
  fixtureAdmin,
  metadata,
  rpc,
  state,
}) {
  state.competitionId = competitionId;
  const initial = await rpc(actor, "get_pachanga_competition_configuration_v1", {
    target_competition_id: competitionId,
  });
  assert.equal(initial.capabilities.edit, true);
  assert.equal(initial.freezePoint, "DRAFT");

  const createOperationId = randomUUID();
  const createInput = {
    action: "draft.create",
    aggregateId: competitionId,
    expectedRevision: initial.competition.revision,
    operationId: createOperationId,
    payload: {
      authoringMode: "ADVANCED",
      presetKey: "LEAGUE_F11",
      reason: "Wave 5A staging advanced configuration",
    },
  };
  let receipt = await configurationCommandOk(actor, metadata, createInput);
  assert.deepEqual(await configurationCommandOk(actor, metadata, createInput), receipt);

  const draftId = receipt.snapshot.id;
  state.configurationDraftIds.push(draftId);
  state.activeDraftRevisions.set(draftId, receipt.confirmedRevision);

  const discipline = structuredClone(receipt.snapshot.steps["10"]);
  discipline.yellow.threshold = 4;
  discipline.blue.enabled = true;
  discipline.blue.durationMinutes = 7;
  receipt = await configurationCommandOk(actor, metadata, {
    action: "draft.section.save",
    aggregateId: draftId,
    expectedRevision: receipt.confirmedRevision,
    payload: { data: discipline, reason: "Wave 5A staging discipline", step: 10 },
  });
  state.activeDraftRevisions.set(draftId, receipt.confirmedRevision);

  const referee = structuredClone(receipt.snapshot.steps["11"]);
  referee.usage = "REQUIRED";
  referee.requiredBeforeReady = true;
  referee.fee.mode = "FIXED";
  referee.fee.fixedCents = 6500;
  referee.fee.publicConsent = false;
  receipt = await configurationCommandOk(actor, metadata, {
    action: "draft.section.save",
    aggregateId: draftId,
    expectedRevision: receipt.confirmedRevision,
    payload: { data: referee, reason: "Wave 5A staging referee policy", step: 11 },
  });
  state.activeDraftRevisions.set(draftId, receipt.confirmedRevision);

  const visibility = structuredClone(receipt.snapshot.steps["12"]);
  visibility.consent = true;
  visibility.acknowledgeUnavailableFeatures = true;
  visibility.paymentsAcknowledged = true;
  visibility.tournamentsAcknowledged = true;
  receipt = await configurationCommandOk(actor, metadata, {
    action: "draft.section.save",
    aggregateId: draftId,
    expectedRevision: receipt.confirmedRevision,
    payload: { data: visibility, reason: "Wave 5A staging publication consent", step: 12 },
  });
  state.activeDraftRevisions.set(draftId, receipt.confirmedRevision);

  receipt = await configurationCommandOk(actor, metadata, {
    action: "draft.validate",
    aggregateId: draftId,
    expectedRevision: receipt.confirmedRevision,
    payload: {
      effectiveFrom: new Date(Date.now() + 15 * 60_000).toISOString(),
      effectiveScope: "FUTURE_ONLY",
      reason: "Wave 5A staging advanced validation",
    },
  });
  state.activeDraftRevisions.set(draftId, receipt.confirmedRevision);
  assert.equal(receipt.snapshot.health.complete, true);
  assert.equal(receipt.snapshot.impact.freezePoint, "DRAFT");
  assert.equal(receipt.snapshot.comparison.discipline.changed, true);
  assert.equal(receipt.snapshot.comparison.referees.changed, true);

  receipt = await configurationCommandOk(actor, metadata, {
    action: "draft.publish",
    aggregateId: draftId,
    expectedRevision: receipt.confirmedRevision,
    payload: {
      confirmImpact: true,
      confirmRuleSummary: true,
      reason: "Wave 5A staging advanced publication",
    },
  });
  state.activeDraftRevisions.delete(draftId);
  state.advancedRuleRevisionId = receipt.snapshot.ruleRevision.ruleRevisionId;
  assert.equal(receipt.snapshot.appliedToCurrentEdition, true);
  assert.equal(receipt.snapshot.ruleRevision.sections.referees.usage, "REQUIRED");

  const revision = await fixtureAdmin
    .from("pachanga_competition_rule_revisions")
    .select("id,rule_document,version")
    .eq("id", state.advancedRuleRevisionId)
    .single();
  if (revision.error) throw revision.error;
  assert.equal(revision.data.rule_document.discipline.policy.cardTypeCatalog[2].code, "BLUE");
  assert.equal(revision.data.rule_document.operations.refereePolicy.fee.fixedCents, 6500);

  const catalog = await fixtureAdmin
    .from("pachanga_competition_discipline_rule_catalogs")
    .select("card_type_catalog,rule_revision_id")
    .eq("rule_revision_id", state.advancedRuleRevisionId)
    .single();
  if (catalog.error) throw catalog.error;
  assert.equal(catalog.data.card_type_catalog.some(({ code }) => code === "BLUE"), true);

  return {
    advancedRuleRevisionId: state.advancedRuleRevisionId,
    configurationDraftId: draftId,
    sourceRuleRevisionId: initial.currentRuleRevision.id,
  };
}

export async function runCompetitionConfigurationAfterRegistration({
  actor,
  competitionId,
  editionId,
  fixtureAdmin,
  metadata,
  rpc,
  state,
}) {
  const frozen = await rpc(actor, "get_pachanga_competition_configuration_v1", {
    target_competition_id: competitionId,
  });
  assert.equal(frozen.freezePoint, "REGISTRATION_OPEN");
  assert.equal(frozen.currentRuleRevision.id, state.advancedRuleRevisionId);

  let receipt = await configurationCommandOk(actor, metadata, {
    action: "draft.clone",
    aggregateId: competitionId,
    expectedRevision: frozen.competition.revision,
    payload: {
      authoringMode: "ADVANCED",
      reason: "Wave 5A staging future revision",
      sourceRuleRevisionId: state.advancedRuleRevisionId,
    },
  });
  const draftId = receipt.snapshot.id;
  state.configurationDraftIds.push(draftId);
  state.activeDraftRevisions.set(draftId, receipt.confirmedRevision);

  const frozenFormatEdit = await configurationCommand(actor, metadata, {
    action: "draft.section.save",
    aggregateId: draftId,
    expectedRevision: receipt.confirmedRevision,
    payload: {
      data: receipt.snapshot.steps["4"],
      reason: "Wave 5A staging frozen structural edit",
      step: 4,
    },
  });
  expectConfigurationError(
    frozenFormatEdit,
    /COMPETITION_CONFIGURATION_FROZEN:REGISTRATION_OPEN/,
    "PT409",
  );

  const scoring = structuredClone(receipt.snapshot.steps["6"]);
  scoring.pointsForWin = 2;
  receipt = await configurationCommandOk(actor, metadata, {
    action: "draft.section.save",
    aggregateId: draftId,
    expectedRevision: receipt.confirmedRevision,
    payload: { data: scoring, reason: "Wave 5A staging future scoring", step: 6 },
  });
  state.activeDraftRevisions.set(draftId, receipt.confirmedRevision);

  receipt = await configurationCommandOk(actor, metadata, {
    action: "draft.validate",
    aggregateId: draftId,
    expectedRevision: receipt.confirmedRevision,
    payload: {
      effectiveFrom: new Date(Date.now() + 60 * 60_000).toISOString(),
      effectiveScope: "FUTURE_ONLY",
      reason: "Wave 5A staging future validation",
    },
  });
  state.activeDraftRevisions.set(draftId, receipt.confirmedRevision);
  assert.equal(receipt.snapshot.health.complete, true);
  assert.equal(receipt.snapshot.impact.freezePoint, "REGISTRATION_OPEN");
  assert.equal(receipt.snapshot.comparison.scoring.changed, true);

  receipt = await configurationCommandOk(actor, metadata, {
    action: "draft.publish",
    aggregateId: draftId,
    expectedRevision: receipt.confirmedRevision,
    payload: {
      confirmImpact: true,
      confirmRuleSummary: true,
      reason: "Wave 5A staging future publication",
    },
  });
  state.activeDraftRevisions.delete(draftId);
  state.futureRuleRevisionId = receipt.snapshot.ruleRevision.ruleRevisionId;
  assert.equal(receipt.snapshot.appliedToCurrentEdition, false);
  assert.equal(receipt.snapshot.currentEditionPreserved, true);

  const edition = await fixtureAdmin
    .from("pachanga_competition_editions")
    .select("id,rule_revision_id,status")
    .eq("id", editionId)
    .single();
  if (edition.error) throw edition.error;
  assert.equal(edition.data.status, "registration_open");
  assert.equal(edition.data.rule_revision_id, state.advancedRuleRevisionId);

  const controlCenter = await rpc(
    actor,
    "get_pachanga_competition_configuration_v1",
    { target_competition_id: competitionId },
  );
  assert.equal(controlCenter.draft, null);
  assert.equal(controlCenter.revisions[0].id, state.futureRuleRevisionId);
  assert.equal(controlCenter.currentRuleRevision.id, state.advancedRuleRevisionId);

  return {
    activeConfigurationDrafts: state.activeDraftRevisions.size,
    advancedRuleRevisionId: state.advancedRuleRevisionId,
    freezePoint: controlCenter.freezePoint,
    futureRuleRevisionId: state.futureRuleRevisionId,
  };
}

export async function cleanupCompetitionConfigurationStaging({ actor, metadata, rpc, state }) {
  for (const [draftId, rememberedRevision] of state.activeDraftRevisions) {
    let expectedRevision = rememberedRevision;
    const model = await rpc(actor, "get_pachanga_competition_configuration_v1", {
      target_competition_id: state.competitionId,
    });
    if (model.draft?.id === draftId) expectedRevision = model.draft.revision;
    const result = await configurationCommand(actor, metadata, {
      action: "draft.cancel",
      aggregateId: draftId,
      expectedRevision,
      payload: { reason: "Wave 5A staging failure cleanup" },
    });
    if (result.error && result.error.code !== "P0002") throw result.error;
    state.activeDraftRevisions.delete(draftId);
  }
}
