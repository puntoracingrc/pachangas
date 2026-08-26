import { leagueBetaRecord, type LeaguePrivateBetaJson } from "../league-private-beta-contract";
import styles from "./competition-configuration-fields.module.css";

export type CompetitionAuthoringMode = "ADVANCED" | "SIMPLE";

function text(form: FormData, key: string, fallback = "") {
  const value = form.get(key);
  return typeof value === "string" ? value.trim() : fallback;
}

function number(form: FormData, key: string, fallback = 0) {
  const value = Number(form.get(key));
  return Number.isFinite(value) ? value : fallback;
}

function boolean(form: FormData, key: string) {
  return form.get(key) === "on";
}

function currentText(data: LeaguePrivateBetaJson, key: string, fallback = "") {
  return typeof data[key] === "string" ? String(data[key]) : fallback;
}

function currentNumber(data: LeaguePrivateBetaJson, key: string, fallback = 0) {
  const value = Number(data[key]);
  return Number.isFinite(value) ? value : fallback;
}

function currentBoolean(data: LeaguePrivateBetaJson, key: string, fallback = false) {
  return typeof data[key] === "boolean" ? Boolean(data[key]) : fallback;
}

function nested(data: LeaguePrivateBetaJson, key: string) {
  return leagueBetaRecord(data[key]);
}

function formOrCurrentNumber(form: FormData, key: string, data: LeaguePrivateBetaJson, fallback: number) {
  return form.has(key) ? number(form, key, fallback) : currentNumber(data, key, fallback);
}

function formOrCurrentText(form: FormData, key: string, data: LeaguePrivateBetaJson, fallback: string) {
  return form.has(key) ? text(form, key, fallback) : currentText(data, key, fallback);
}

function formOrCurrentBoolean(form: FormData, key: string, data: LeaguePrivateBetaJson, fallback: boolean) {
  return form.has(`${key}Rendered`) ? boolean(form, key) : currentBoolean(data, key, fallback);
}

export function competitionConfigurationStepPayload(
  step: number,
  form: FormData,
  current: LeaguePrivateBetaJson,
): LeaguePrivateBetaJson {
  if (step === 1) return {
    description: text(form, "description"),
    generalArea: text(form, "generalArea"),
    imageUrl: text(form, "imageUrl"),
    name: text(form, "name"),
    slug: text(form, "slug"),
  };
  if (step === 2) return { modality: text(form, "modality") };
  if (step === 3) return {
    editionName: text(form, "editionName"),
    endsAt: text(form, "endsAt"),
    seasonLabel: text(form, "seasonLabel"),
    startsAt: text(form, "startsAt"),
    timezone: text(form, "timezone", "Europe/Madrid"),
  };
  if (step === 4) return {
    legs: number(form, "legs", 1),
    registrationClosesAt: new Date(text(form, "registrationClosesAt")).toISOString(),
    registrationMode: "INVITE_ONLY",
    teamCap: number(form, "teamCap", 4),
  };
  if (step === 5) return {
    closeRequiresApprovedRosters: boolean(form, "closeRequiresApprovedRosters"),
    credentialRequired: boolean(form, "credentialRequired"),
    jerseyRequired: boolean(form, "jerseyRequired"),
    maximumRosterSize: number(form, "maximumRosterSize", 18),
    minimumRosterSize: number(form, "minimumRosterSize", 7),
  };
  if (step === 6) return {
    autoOfficialAfterConfirmation: boolean(form, "autoOfficialAfterConfirmation"),
    matchDurationMinutes: number(form, "matchDurationMinutes", 70),
    pointsForDraw: number(form, "pointsForDraw", 1),
    pointsForLoss: number(form, "pointsForLoss", 0),
    pointsForWin: number(form, "pointsForWin", 3),
    requiredBufferMinutes: number(form, "requiredBufferMinutes", 10),
    responseDeadlineHours: number(form, "responseDeadlineHours", 48),
  };
  if (step === 7) return {
    allowTbd: boolean(form, "allowTbd"),
    minimumRestMinutes: number(form, "minimumRestMinutes", 1440),
    useDivision: boolean(form, "useDivision"),
    venueRequired: boolean(form, "venueRequired"),
    weeklyPattern: [{ dayOfWeek: number(form, "dayOfWeek", 6), startTime: text(form, "startTime", "18:00") }],
  };
  if (step === 8) return {
    allowSharedPositions: boolean(form, "allowSharedPositions"),
    allowUnknownScorer: boolean(form, "allowUnknownScorer"),
    scorerDetailPolicy: text(form, "scorerDetailPolicy", "OPTIONAL"),
    tieBreakCriteria: form.getAll("tieBreakCriteria").map(String),
  };
  if (step === 9) return {
    gracePeriodMinutes: number(form, "gracePeriodMinutes", 15),
    maximumMatchDurationMinutes: number(form, "maximumMatchDurationMinutes", 180),
    minimumRestHours: number(form, "minimumRestHours", 24),
    noShowLoserScore: number(form, "noShowLoserScore", 0),
    noShowOutcome: text(form, "noShowOutcome", "NO_SHOW"),
    noShowWinnerScore: number(form, "noShowWinnerScore", 3),
    postponementDeadlinePolicy: text(form, "postponementDeadlinePolicy", "ESCALATE_TO_ORGANIZER"),
    postponementResponseDeadlineHours: number(form, "postponementResponseDeadlineHours", 48),
  };
  if (step === 10) {
    const yellow = nested(current, "yellow");
    const secondYellow = nested(current, "secondYellow");
    const red = nested(current, "red");
    const blue = nested(current, "blue");
    const cycle = nested(current, "cycle");
    const sanction = nested(current, "sanction");
    const appeal = nested(current, "appeal");
    return {
      appeal: {
        deadlineHours: formOrCurrentNumber(form, "appealDeadlineHours", appeal, 72),
        suspensiveEffect: formOrCurrentBoolean(form, "appealSuspensiveEffect", appeal, false),
      },
      blue: {
        durationMinutes: formOrCurrentNumber(form, "blueDurationMinutes", blue, 5),
        enabled: formOrCurrentBoolean(form, "blueEnabled", blue, false),
        mode: formOrCurrentText(form, "blueMode", blue, "MINUTES_OR_GOAL"),
        postMatchOutcome: formOrCurrentText(form, "bluePostMatchOutcome", blue, "NO_SANCTION"),
        replacementPolicy: formOrCurrentText(form, "blueReplacementPolicy", blue, "NO_REPLACEMENT"),
      },
      consent: true,
      cycle: {
        carryPolicy: formOrCurrentText(form, "carryPolicy", cycle, "RESET"),
        scopeType: formOrCurrentText(form, "scopeType", cycle, "EDITION"),
      },
      enabled: formOrCurrentBoolean(form, "disciplineEnabled", current, true),
      red: {
        committeeRequired: formOrCurrentBoolean(form, "redCommitteeRequired", red, true),
        enabled: formOrCurrentBoolean(form, "redEnabled", red, true),
        maximumUnits: formOrCurrentNumber(form, "redMaximumUnits", red, 3),
        minimumUnits: formOrCurrentNumber(form, "redMinimumUnits", red, 1),
        outcome: formOrCurrentText(form, "redOutcome", red, "COMMITTEE_REQUIRED"),
        provisionalUnits: formOrCurrentNumber(form, "redProvisionalUnits", red, 1),
        unitType: formOrCurrentText(form, "redUnitType", red, "MATCHES"),
        units: formOrCurrentNumber(form, "redUnits", red, 1),
      },
      sanction: {
        consumePostponed: formOrCurrentBoolean(form, "consumePostponed", sanction, false),
        eligibleFixtureStatuses: ["official", "played"],
      },
      secondYellow: {
        countsForAccumulation: formOrCurrentBoolean(form, "secondYellowCounts", secondYellow, true),
        dismissal: true,
        enabled: formOrCurrentBoolean(form, "secondYellowEnabled", secondYellow, true),
        outcome: formOrCurrentText(form, "secondYellowOutcome", secondYellow, "FIXED_SANCTION"),
        preserveYellowFacts: true,
        unitType: formOrCurrentText(form, "secondYellowUnitType", secondYellow, "MATCHES"),
        units: formOrCurrentNumber(form, "secondYellowUnits", secondYellow, 1),
      },
      yellow: {
        accumulationEnabled: formOrCurrentBoolean(form, "yellowAccumulationEnabled", yellow, true),
        enabled: formOrCurrentBoolean(form, "yellowEnabled", yellow, true),
        outcome: formOrCurrentText(form, "yellowOutcome", yellow, "FIXED_SANCTION"),
        points: formOrCurrentNumber(form, "yellowPoints", yellow, 1),
        threshold: formOrCurrentNumber(form, "yellowThreshold", yellow, 3),
        unitType: formOrCurrentText(form, "yellowUnitType", yellow, "MATCHES"),
        units: formOrCurrentNumber(form, "yellowUnits", yellow, 1),
      },
    };
  }
  if (step === 11) {
    const authority = nested(current, "authority");
    const fee = nested(current, "fee");
    return {
      acceptanceIsSufficient: formOrCurrentBoolean(form, "acceptanceIsSufficient", current, false),
      authority: {
        observeScore: formOrCurrentBoolean(form, "observeScore", authority, true),
        reportCards: formOrCurrentBoolean(form, "reportCards", authority, true),
        reportIncidents: formOrCurrentBoolean(form, "reportIncidents", authority, true),
      },
      fee: {
        fixedCents: text(form, "fixedCents") ? number(form, "fixedCents", 0) : null,
        mode: text(form, "feeMode", currentText(fee, "mode", "NEGOTIABLE")),
        publicConsent: formOrCurrentBoolean(form, "publicConsent", fee, false),
        travelIncluded: formOrCurrentBoolean(form, "travelIncluded", fee, false),
      },
      modalityRequired: formOrCurrentBoolean(form, "modalityRequired", current, true),
      organizerConfirmationRequired: formOrCurrentBoolean(form, "organizerConfirmationRequired", current, true),
      priorClubRelationshipRequired: formOrCurrentBoolean(form, "priorClubRelationshipRequired", current, false),
      proposerRoles: ["competition_owner", "competition_director", "competition_referee_manager"],
      reconfirmAfterScheduleChange: formOrCurrentBoolean(form, "reconfirmAfterScheduleChange", current, true),
      replacementAllowed: formOrCurrentBoolean(form, "replacementAllowed", current, true),
      requiredBeforeReady: formOrCurrentBoolean(form, "requiredBeforeReady", current, false),
      responseDeadlineHours: formOrCurrentNumber(form, "refereeResponseDeadlineHours", current, 72),
      role: "MAIN_REFEREE",
      serviceAreaRequired: formOrCurrentBoolean(form, "serviceAreaRequired", current, true),
      usage: text(form, "refereeUsage", currentText(current, "usage", "OPTIONAL")),
    };
  }
  return {
    acknowledgeUnavailableFeatures: boolean(form, "acknowledgeUnavailableFeatures"),
    calendarVisibility: "PARTICIPANTS_ONLY",
    competitionVisibility: "PRIVATE",
    consent: boolean(form, "consent"),
    disciplineVisibility: "PRIVATE",
    incidentVisibility: "PRIVATE",
    paymentsAcknowledged: boolean(form, "paymentsAcknowledged"),
    standingsVisibility: "PARTICIPANTS_ONLY",
    tournamentsAcknowledged: boolean(form, "tournamentsAcknowledged"),
  };
}

function Check({ checked, children, name }: { checked: boolean; children: React.ReactNode; name: string }) {
  return <label className={styles.check}><input type="hidden" name={`${name}Rendered`} value="1" /><input name={name} type="checkbox" defaultChecked={checked} />{children}</label>;
}

function Select({ children, defaultValue, name }: { children: React.ReactNode; defaultValue: string; name: string }) {
  return <select name={name} defaultValue={defaultValue}>{children}</select>;
}

export function CompetitionConfigurationFields({
  data,
  mode,
  step,
}: {
  data: LeaguePrivateBetaJson;
  mode: CompetitionAuthoringMode;
  step: number;
}) {
  const advanced = mode === "ADVANCED";
  if (step === 1) return <div className={styles.fields}>
    <label>Nombre<input name="name" required maxLength={120} defaultValue={currentText(data, "name", "Liga privada")} /></label>
    <label>Slug privado<input name="slug" required maxLength={80} pattern="[a-z0-9]+(?:-[a-z0-9]+)*" defaultValue={currentText(data, "slug", "liga-privada")} /></label>
    <label className={styles.wide}>Descripción<textarea name="description" rows={3} maxLength={2400} defaultValue={currentText(data, "description")} /></label>
    <label>Zona general<input name="generalArea" maxLength={160} defaultValue={currentText(data, "generalArea")} /></label>
    <label>Imagen HTTPS opcional<input name="imageUrl" type="url" defaultValue={currentText(data, "imageUrl")} /></label>
    <p className={styles.notice}>Competición privada, organizada por el Team o Club que inició este borrador.</p>
  </div>;
  if (step === 2) return <div className={styles.fields}><label className={styles.wide}>Modalidad<Select name="modality" defaultValue={currentText(data, "modality", "FUTBOL_7")}><option value="FUTBOL_5">Fútbol 5</option><option value="FUTBOL_7">Fútbol 7</option><option value="FUTBOL_11">Fútbol 11</option><option value="FUTSAL">Fútbol sala</option></Select></label><p className={styles.notice}>La modalidad propone el preset inicial, pero cada regla se confirma por separado.</p></div>;
  if (step === 3) return <div className={styles.fields}>
    <label>Nombre de edición<input name="editionName" required defaultValue={currentText(data, "editionName", "Temporada inicial")} /></label>
    <label>Temporada<input name="seasonLabel" required defaultValue={currentText(data, "seasonLabel", String(new Date().getFullYear()))} /></label>
    <label>Inicio<input name="startsAt" type="date" required defaultValue={currentText(data, "startsAt").slice(0, 10)} /></label>
    <label>Fin<input name="endsAt" type="date" required defaultValue={currentText(data, "endsAt").slice(0, 10)} /></label>
    <label className={styles.wide}>Zona horaria<input name="timezone" readOnly value={currentText(data, "timezone", "Europe/Madrid")} /></label>
  </div>;
  if (step === 4) return <div className={styles.fields}>
    <label>Máximo de equipos<input name="teamCap" type="number" min={4} max={20} required defaultValue={currentNumber(data, "teamCap", 12)} /></label>
    <label>Formato<Select name="legs" defaultValue={String(currentNumber(data, "legs", 2))}><option value="1">Una vuelta</option><option value="2">Ida y vuelta</option></Select></label>
    <label className={styles.wide}>Cierre de inscripción<input name="registrationClosesAt" type="datetime-local" required defaultValue={currentText(data, "registrationClosesAt").slice(0, 16)} /></label>
    <p className={styles.notice}>Registro privado, división única opcional y emparejamiento automático Round Robin. Manual asistido e híbrido quedan para R6A.</p>
  </div>;
  if (step === 5) return <div className={styles.fields}>
    <label>Mínimo de plantilla<input name="minimumRosterSize" type="number" min={1} max={50} required defaultValue={currentNumber(data, "minimumRosterSize", 7)} /></label>
    <label>Máximo de plantilla<input name="maximumRosterSize" type="number" min={1} max={50} required defaultValue={currentNumber(data, "maximumRosterSize", 18)} /></label>
    <Check name="credentialRequired" checked={currentBoolean(data, "credentialRequired", true)}>Credencial obligatoria</Check>
    <Check name="jerseyRequired" checked={currentBoolean(data, "jerseyRequired", true)}>Dorsal obligatorio</Check>
    <Check name="closeRequiresApprovedRosters" checked={currentBoolean(data, "closeRequiresApprovedRosters", true)}>Cerrar solo con plantillas aprobadas</Check>
  </div>;
  if (step === 6) return <div className={styles.fields}>
    <label>Duración (min)<input name="matchDurationMinutes" type="number" min={20} max={180} required defaultValue={currentNumber(data, "matchDurationMinutes", 70)} /></label>
    <label>Buffer (min)<input name="requiredBufferMinutes" type="number" min={0} max={120} required defaultValue={currentNumber(data, "requiredBufferMinutes", 10)} /></label>
    <label>Victoria<input name="pointsForWin" type="number" min={0} max={10} required defaultValue={currentNumber(data, "pointsForWin", 3)} /></label>
    <label>Empate<input name="pointsForDraw" type="number" min={0} max={10} required defaultValue={currentNumber(data, "pointsForDraw", 1)} /></label>
    <label>Derrota<input name="pointsForLoss" type="number" min={0} max={10} required defaultValue={currentNumber(data, "pointsForLoss", 0)} /></label>
    <label>Respuesta (h)<input name="responseDeadlineHours" type="number" min={1} max={720} required defaultValue={currentNumber(data, "responseDeadlineHours", 48)} /></label>
    <Check name="autoOfficialAfterConfirmation" checked={currentBoolean(data, "autoOfficialAfterConfirmation", true)}>Oficial tras confirmación bilateral</Check>
  </div>;
  if (step === 7) {
    const pattern = Array.isArray(data.weeklyPattern) ? leagueBetaRecord(data.weeklyPattern[0]) : {};
    return <div className={styles.fields}>
      <label>Día habitual<Select name="dayOfWeek" defaultValue={String(currentNumber(pattern, "dayOfWeek", 6))}><option value="1">Lunes</option><option value="2">Martes</option><option value="3">Miércoles</option><option value="4">Jueves</option><option value="5">Viernes</option><option value="6">Sábado</option><option value="7">Domingo</option></Select></label>
      <label>Hora habitual<input name="startTime" type="time" required defaultValue={currentText(pattern, "startTime", "18:00")} /></label>
      <label>Descanso mínimo (min)<input name="minimumRestMinutes" type="number" min={0} defaultValue={currentNumber(data, "minimumRestMinutes", 1440)} /></label>
      <Check name="venueRequired" checked={currentBoolean(data, "venueRequired", false)}>Sede obligatoria</Check>
      <Check name="allowTbd" checked={currentBoolean(data, "allowTbd", true)}>Permitir sede por confirmar</Check>
      <Check name="useDivision" checked={currentBoolean(data, "useDivision", true)}>Crear división única</Check>
    </div>;
  }
  if (step === 8) {
    const selected = new Set(Array.isArray(data.tieBreakCriteria) ? data.tieBreakCriteria.map(String) : []);
    const criteria = ["POINTS", "GOAL_DIFFERENCE", "GOALS_FOR", "WINS", "HEAD_TO_HEAD_POINTS", "HEAD_TO_HEAD_GOAL_DIFFERENCE", "HEAD_TO_HEAD_GOALS_FOR", "PERSISTED_DRAW_LOT"];
    return <div className={styles.fields}>
      <fieldset className={styles.wide}><legend>Desempates, en orden canónico</legend>{criteria.map((criterion) => <label className={styles.check} key={criterion}><input name="tieBreakCriteria" type="checkbox" value={criterion} defaultChecked={selected.size ? selected.has(criterion) : true} />{criterion.replaceAll("_", " ")}</label>)}</fieldset>
      <label>Goleadores<Select name="scorerDetailPolicy" defaultValue={currentText(data, "scorerDetailPolicy", "OPTIONAL")}><option value="OPTIONAL">Opcionales</option><option value="REQUIRED">Obligatorios</option><option value="DISABLED">Desactivados</option></Select></label>
      <Check name="allowUnknownScorer" checked={currentBoolean(data, "allowUnknownScorer", false)}>Permitir goleador desconocido</Check>
      <Check name="allowSharedPositions" checked={currentBoolean(data, "allowSharedPositions", true)}>Permitir posiciones compartidas</Check>
    </div>;
  }
  if (step === 9) return <div className={styles.fields}>
    <label>Respuesta a aplazamiento (h)<input name="postponementResponseDeadlineHours" type="number" min={1} max={720} defaultValue={currentNumber(data, "postponementResponseDeadlineHours", 48)} /></label>
    <label>Al vencer<Select name="postponementDeadlinePolicy" defaultValue={currentText(data, "postponementDeadlinePolicy", "ESCALATE_TO_ORGANIZER")}><option value="ESCALATE_TO_ORGANIZER">Escalar al organizador</option><option value="AUTO_DENY">Rechazar</option><option value="EXPIRE">Expirar</option></Select></label>
    <label>Margen de llegada (min)<input name="gracePeriodMinutes" type="number" min={0} max={180} defaultValue={currentNumber(data, "gracePeriodMinutes", 15)} /></label>
    <label>Descanso tras cambio (h)<input name="minimumRestHours" type="number" min={0} defaultValue={currentNumber(data, "minimumRestHours", 24)} /></label>
    <label>Máximo partido (min)<input name="maximumMatchDurationMinutes" type="number" min={20} max={300} defaultValue={currentNumber(data, "maximumMatchDurationMinutes", 180)} /></label>
    <label>No-show<Select name="noShowOutcome" defaultValue={currentText(data, "noShowOutcome", "NO_SHOW")}><option value="NO_SHOW">Incomparecencia</option><option value="FORFEIT">Derrota administrativa</option></Select></label>
    <label>Marcador ganador<input name="noShowWinnerScore" type="number" min={0} max={99} defaultValue={currentNumber(data, "noShowWinnerScore", 3)} /></label>
    <label>Marcador perdedor<input name="noShowLoserScore" type="number" min={0} max={99} defaultValue={currentNumber(data, "noShowLoserScore", 0)} /></label>
  </div>;
  if (step === 10) {
    const yellow = nested(data, "yellow"); const second = nested(data, "secondYellow"); const red = nested(data, "red"); const blue = nested(data, "blue"); const cycle = nested(data, "cycle"); const appeal = nested(data, "appeal"); const sanction = nested(data, "sanction");
    return <div className={styles.fields}>
      <Check name="disciplineEnabled" checked={currentBoolean(data, "enabled", true)}>Activar disciplina R5</Check>
      <div className={styles.policy}><strong>Amarillas</strong><Check name="yellowEnabled" checked={currentBoolean(yellow, "enabled", true)}>Activas</Check><Check name="yellowAccumulationEnabled" checked={currentBoolean(yellow, "accumulationEnabled", true)}>Acumulación</Check><label>Threshold<input name="yellowThreshold" type="number" min={1} max={99} defaultValue={currentNumber(yellow, "threshold", 3)} /></label>{advanced ? <><label>Puntos<input name="yellowPoints" type="number" min={0} max={20} defaultValue={currentNumber(yellow, "points", 1)} /></label><label>Sanción<Select name="yellowOutcome" defaultValue={currentText(yellow, "outcome", "FIXED_SANCTION")}><option value="FIXED_SANCTION">Sanción fija</option><option value="WARNING_ONLY">Solo aviso</option><option value="COMMITTEE_REQUIRED">Comité</option></Select></label><label>Unidades<input name="yellowUnits" type="number" min={0} max={20} defaultValue={currentNumber(yellow, "units", 1)} /></label></> : null}</div>
      <div className={styles.policy}><strong>Segunda amarilla</strong><Check name="secondYellowEnabled" checked={currentBoolean(second, "enabled", true)}>Expulsión activa</Check>{advanced ? <><Check name="secondYellowCounts" checked={currentBoolean(second, "countsForAccumulation", true)}>Suma acumulación</Check><label>Sanción<Select name="secondYellowOutcome" defaultValue={currentText(second, "outcome", "FIXED_SANCTION")}><option value="FIXED_SANCTION">Fija</option><option value="COMMITTEE_REQUIRED">Comité</option><option value="NO_SANCTION">Sin sanción posterior</option></Select></label><label>Partidos<input name="secondYellowUnits" type="number" min={0} max={20} defaultValue={currentNumber(second, "units", 1)} /></label></> : null}</div>
      <div className={styles.policy}><strong>Roja directa</strong><Check name="redEnabled" checked={currentBoolean(red, "enabled", true)}>Activa</Check><label>Resolución<Select name="redOutcome" defaultValue={currentText(red, "outcome", "COMMITTEE_REQUIRED")}><option value="NO_SANCTION">Solo expulsión</option><option value="FIXED_SANCTION">Sanción fija</option><option value="PROVISIONAL_SANCTION">Provisional</option><option value="SANCTION_RANGE">Rango</option><option value="COMMITTEE_REQUIRED">Comité obligatorio</option></Select></label>{advanced ? <><label>Provisional<input name="redProvisionalUnits" type="number" min={0} max={20} defaultValue={currentNumber(red, "provisionalUnits", 1)} /></label><label>Mínimo<input name="redMinimumUnits" type="number" min={0} max={20} defaultValue={currentNumber(red, "minimumUnits", 1)} /></label><label>Máximo<input name="redMaximumUnits" type="number" min={0} max={20} defaultValue={currentNumber(red, "maximumUnits", 3)} /></label><Check name="redCommitteeRequired" checked={currentBoolean(red, "committeeRequired", true)}>Revisión de comité</Check></> : null}</div>
      <div className={styles.policy}><strong>Azul</strong><Check name="blueEnabled" checked={currentBoolean(blue, "enabled", false)}>Activa</Check><label>Minutos<input name="blueDurationMinutes" type="number" min={1} max={60} defaultValue={currentNumber(blue, "durationMinutes", 5)} /></label>{advanced ? <><label>Finaliza<Select name="blueMode" defaultValue={currentText(blue, "mode", "MINUTES_OR_GOAL")}><option value="MINUTES">Por minutos</option><option value="UNTIL_OPPONENT_GOAL">Con gol rival</option><option value="MINUTES_OR_GOAL">Minutos o gol</option><option value="MINUTES_AND_GOAL">Minutos y gol</option></Select></label><label>Sustitución<Select name="blueReplacementPolicy" defaultValue={currentText(blue, "replacementPolicy", "NO_REPLACEMENT")}><option value="NO_REPLACEMENT">No permitida</option><option value="REPLACEMENT_ALLOWED">Permitida</option></Select></label></> : null}</div>
      {advanced ? <div className={styles.policy}><strong>Ciclo y apelación</strong><label>Scope<Select name="scopeType" defaultValue={currentText(cycle, "scopeType", "EDITION")}><option value="EDITION">Edición</option><option value="STAGE">Fase futura</option></Select></label><label>Cierre<Select name="carryPolicy" defaultValue={currentText(cycle, "carryPolicy", "RESET")}><option value="RESET">Reset</option><option value="CARRY">Carry</option></Select></label><label>Apelación (h)<input name="appealDeadlineHours" type="number" min={1} max={720} defaultValue={currentNumber(appeal, "deadlineHours", 72)} /></label><Check name="appealSuspensiveEffect" checked={currentBoolean(appeal, "suspensiveEffect", false)}>Efecto suspensivo</Check><Check name="consumePostponed" checked={currentBoolean(sanction, "consumePostponed", false)}>Aplazado consume sanción</Check></div> : null}
    </div>;
  }
  if (step === 11) {
    const authority = nested(data, "authority"); const fee = nested(data, "fee");
    return <div className={styles.fields}>
      <label>Uso<Select name="refereeUsage" defaultValue={currentText(data, "usage", "OPTIONAL")}><option value="NONE">Ninguno</option><option value="OPTIONAL">Opcional</option><option value="REQUIRED">Obligatorio</option></Select></label>
      <label>Respuesta (h)<input name="refereeResponseDeadlineHours" type="number" min={1} max={720} defaultValue={currentNumber(data, "responseDeadlineHours", 72)} /></label>
      <Check name="organizerConfirmationRequired" checked={currentBoolean(data, "organizerConfirmationRequired", true)}>Confirmación del organizador</Check>
      <Check name="acceptanceIsSufficient" checked={currentBoolean(data, "acceptanceIsSufficient", false)}>Aceptación suficiente</Check>
      <Check name="requiredBeforeReady" checked={currentBoolean(data, "requiredBeforeReady", currentText(data, "usage") === "REQUIRED")}>Obligatorio antes de ready</Check>
      <Check name="reconfirmAfterScheduleChange" checked={currentBoolean(data, "reconfirmAfterScheduleChange", true)}>Reconfirmar tras cambio R4D</Check>
      {advanced ? <><Check name="modalityRequired" checked={currentBoolean(data, "modalityRequired", true)}>Modalidad compatible</Check><Check name="serviceAreaRequired" checked={currentBoolean(data, "serviceAreaRequired", true)}>Zona compatible</Check><Check name="priorClubRelationshipRequired" checked={currentBoolean(data, "priorClubRelationshipRequired", false)}>Relación previa con Club</Check><Check name="replacementAllowed" checked={currentBoolean(data, "replacementAllowed", true)}>Reemplazo permitido</Check></> : null}
      <fieldset className={styles.wide}><legend>Autoridad arbitral</legend><Check name="reportCards" checked={currentBoolean(authority, "reportCards", true)}>Reportar tarjetas</Check><Check name="reportIncidents" checked={currentBoolean(authority, "reportIncidents", true)}>Reportar incidencias</Check><Check name="observeScore" checked={currentBoolean(authority, "observeScore", true)}>Observar marcador</Check><p>El resultado oficial, sanciones, standings y Rating permanecen fuera de su autoridad.</p></fieldset>
      <label>Tarifa<Select name="feeMode" defaultValue={currentText(fee, "mode", "NEGOTIABLE")}><option value="FREE">Gratis</option><option value="VOLUNTEER">Voluntario</option><option value="FIXED">Fija</option><option value="NEGOTIABLE">Negociable</option></Select></label>
      <label>Fija (céntimos)<input name="fixedCents" type="number" min={0} max={100000} defaultValue={fee.fixedCents == null ? "" : currentNumber(fee, "fixedCents", 0)} /></label>
      {advanced ? <><Check name="travelIncluded" checked={currentBoolean(fee, "travelIncluded", false)}>Desplazamiento incluido</Check><Check name="publicConsent" checked={currentBoolean(fee, "publicConsent", false)}>Consentimiento para mostrar tarifa</Check></> : null}
      <p className={styles.notice}>Pachangas IQ todavía no procesa el pago. Solo MAIN_REFEREE está disponible.</p>
    </div>;
  }
  return <div className={styles.fields}>
    <div className={`${styles.summary} ${styles.wide}`}><strong>Resumen previo</strong><span>Competition privada</span><span>Calendario y clasificación para participantes</span><span>Disciplina e incidencias privadas</span><span>RuleRevision nueva, congelada y auditable</span></div>
    <div className={`${styles.future} ${styles.wide}`}><strong>Funciones globalmente apagadas</strong><span>Superficies públicas</span><span>Pagos</span><span>Torneos</span><span>Pairing manual asistido e híbrido</span></div>
    <Check name="acknowledgeUnavailableFeatures" checked={currentBoolean(data, "acknowledgeUnavailableFeatures", false)}>Entiendo qué funciones siguen apagadas.</Check>
    <Check name="paymentsAcknowledged" checked={currentBoolean(data, "paymentsAcknowledged", false)}>Entiendo que Pachangas IQ no procesa pagos.</Check>
    <Check name="tournamentsAcknowledged" checked={currentBoolean(data, "tournamentsAcknowledged", false)}>Entiendo que Tournament Engine no forma parte de esta fase.</Check>
    <Check name="consent" checked={currentBoolean(data, "consent", false)}>Confirmo el resumen y autorizo la RuleRevision canónica.</Check>
  </div>;
}
