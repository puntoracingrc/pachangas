"use client";

import Link from "next/link";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { OfficialProductShellV2 } from "../../_components/official-product-shell-v2";
import { PlayerCosmeticCard } from "../../_components/player-cosmetic-card";
import { CLIENT_VERSION } from "../../client-version-contract";
import {
  ADVANCED_TEST_VERSION,
  ATTRIBUTE_KEYS,
  FOOTBALL_RATING_ENGINE_VERSION,
  FREQUENCIES,
  INITIAL_TECHNICAL_QUESTIONS,
  INITIAL_TEST_VERSION,
  POSITION_LABELS,
  calculateAdvancedRatings,
  calculateApplicableAdvancedQuestions,
  calculateInitialRatings,
  type AnswerValue,
  type AttributeRatings,
  type FootballMode,
  type FrequencyId,
  type InitialRatingInput,
  type InitialTechnicalQuestionId,
  type PlayerPosition,
} from "../../laboratorio-ficha-jugador/_engine/player-rating-engine";
import {
  ASSESSMENT_EXPERIENCE_OPTIONS,
  ASSESSMENT_INITIAL_ANSWER_OPTIONS,
  ASSESSMENT_INITIAL_QUESTION_GROUPS,
  ASSESSMENT_INITIAL_STEP_COUNT,
  ASSESSMENT_MODE_OPTIONS,
  ASSESSMENT_YEARS_SINCE_LEVEL_OPTIONS,
  assessmentAdvancedAnswerOptions,
  assessmentInitialIsComplete,
  assessmentInitialStepIsComplete,
  assessmentSelectedModes,
  assessmentSharesFromSelectedModes,
} from "../../player-assessment-flow-contract";
import { clientWriteFetch, currentClientDisplayMode, pwaBridgeSnapshot } from "../../pwa-client-bridge";
import { supabase } from "../../supabaseClient";
import { ThemeToggle } from "../../theme-toggle";
import styles from "./page.module.css";

type AssessmentKind = "advanced" | "initial";

type AssessmentEntry = {
  completedAt: string;
  engineVersion: string;
  input: InitialRatingInput | { answers?: Record<string, AnswerValue> };
  questionnaireVersion: string;
  reliability: number | null;
};

type PlayerProfile = {
  assessment_summary: unknown;
  avatar: string | null;
  current_facets: Record<string, number> | null;
  current_overall: number | null;
  display_name: string;
  id: string;
  outfield_position: string | null;
  position: string;
  profile_version: number;
  rating_reliability: number;
  updated_at: string;
};

type AssessmentSnapshot = {
  assessments: Partial<Record<AssessmentKind, AssessmentEntry>>;
  onboardingProfileReady: boolean;
  playerProfile: PlayerProfile | null;
  writeContext: {
    expectedRevision: number;
    groupId: string | null;
    playerId: string | null;
    scope: "group" | "profile";
  };
};

type AssessmentFlow = {
  advancedAnswers: Record<string, AnswerValue>;
  initial: InitialRatingInput;
  kind: AssessmentKind;
  operationId: string;
  saving: boolean;
  step: number;
};

const emptyAnswers = Object.fromEntries(
  INITIAL_TECHNICAL_QUESTIONS.map((question) => [question.id, null]),
) as Record<InitialTechnicalQuestionId, AnswerValue>;

const assessmentPositionLabels: Record<PlayerPosition, string> = POSITION_LABELS;

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function normalizeSnapshot(value: unknown): AssessmentSnapshot | null {
  if (!isRecord(value) || !isRecord(value.assessments) || !isRecord(value.writeContext)) return null;
  const context = value.writeContext;
  const scope = context.scope === "group" ? "group" : "profile";
  const expectedRevision = Math.max(0, Math.floor(Number(context.expectedRevision) || 0));
  return {
    assessments: value.assessments as AssessmentSnapshot["assessments"],
    onboardingProfileReady: value.onboardingProfileReady === true,
    playerProfile: isRecord(value.playerProfile) ? value.playerProfile as PlayerProfile : null,
    writeContext: {
      expectedRevision,
      groupId: typeof context.groupId === "string" ? context.groupId : null,
      playerId: typeof context.playerId === "string" ? context.playerId : null,
      scope,
    },
  };
}

function makeInitialInput(): InitialRatingInput {
  return {
    primaryPosition: "central_midfielder",
    secondaryPositions: [],
    modeShares: ASSESSMENT_MODE_OPTIONS.map(({ mode }) => ({ mode, percentage: mode === "football_7" ? 100 : 0 })),
    experienceLevel: "regular_pachangas",
    yearsSinceLevel: 0,
    frequency: "weekly",
    answers: { ...emptyAnswers },
    calculatedAt: new Date().toISOString(),
  };
}

function draftKey(userId: string, kind: AssessmentKind) {
  return `pachangas-player-assessment-draft-v1:${userId}:${kind}`;
}

function safeAssessmentReturnPath(search: string) {
  const requested = new URLSearchParams(search).get("next");
  if (!requested || !requested.startsWith("/") || requested.startsWith("//")) return "/";
  try {
    const url = new URL(requested, "https://pachangasiq.local");
    if (url.origin !== "https://pachangasiq.local" || url.search || url.hash) return "/";
    const isPlayerInvitation = /^\/invitacion\/grupo\/piq_[0-9a-f]{64}$/i.test(url.pathname);
    const isAdminInvitation = /^\/invitacion\/admin\/[0-9a-f_-]{20,64}$/i.test(url.pathname);
    return isPlayerInvitation || isAdminInvitation ? url.pathname : "/";
  } catch {
    return "/";
  }
}

function readDraft(userId: string, kind: AssessmentKind): AssessmentFlow | null {
  try {
    const value = JSON.parse(window.localStorage.getItem(draftKey(userId, kind)) ?? "null") as unknown;
    if (!isRecord(value) || value.kind !== kind || typeof value.operationId !== "string" || !isRecord(value.initial)) return null;
    return {
      advancedAnswers: isRecord(value.advancedAnswers) ? value.advancedAnswers as Record<string, AnswerValue> : {},
      initial: value.initial as unknown as InitialRatingInput,
      kind,
      operationId: value.operationId,
      saving: false,
      step: Math.max(-1, Math.floor(Number(value.step) || 0)),
    };
  } catch {
    return null;
  }
}

function shortPosition(position: string) {
  const normalized = position.toLowerCase();
  if (normalized.includes("delanter")) return "DEL";
  if (normalized.includes("extremo")) return "EXT";
  if (normalized.includes("defensa")) return "DFC";
  if (normalized.includes("lateral")) return "LAT";
  if (normalized.includes("pivote")) return "PIV";
  return "MC";
}

function assessmentMetadata() {
  const bridge = pwaBridgeSnapshot();
  return {
    clientVersion: CLIENT_VERSION,
    displayMode: currentClientDisplayMode(),
    serviceWorkerVersion: bridge.serviceWorkerVersion,
    surface: "player-initial-assessment-onboarding",
  };
}

export default function PlayerInitialAssessmentPage() {
  const [flow, setFlow] = useState<AssessmentFlow | null>(null);
  const [message, setMessage] = useState("");
  const [snapshot, setSnapshot] = useState<AssessmentSnapshot | null>(null);
  const [status, setStatus] = useState<"error" | "loading" | "offline" | "ready" | "signed-out">(supabase ? "loading" : "error");
  const [userId, setUserId] = useState("");
  const accessTokenRef = useRef("");
  const advancedDeepLinkHandled = useRef(false);
  const initialDeepLinkHandled = useRef(false);
  const onboardingReturnHref = typeof window === "undefined"
    ? "/"
    : safeAssessmentReturnPath(window.location.search);

  const loadCanonical = useCallback(async (accessToken: string, preserveMessage = false) => {
    if (!navigator.onLine) {
      setStatus("offline");
      setMessage("Sin conexión: el test no puede confirmarse hasta volver a conectar.");
      return null;
    }
    const response = await fetch("/api/ratings/assessment", {
      cache: "no-store",
      headers: { Authorization: `Bearer ${accessToken}` },
    });
    const payload = await response.json() as unknown;
    if (!response.ok) throw new Error(isRecord(payload) && typeof payload.error === "string" ? payload.error : "No pudimos recuperar tu ficha.");
    const canonical = normalizeSnapshot(payload);
    if (!canonical) throw new Error("El servidor devolvió una ficha no válida.");
    setSnapshot(canonical);
    setStatus("ready");
    if (!preserveMessage) setMessage("");
    return canonical;
  }, []);

  useEffect(() => {
    if (!supabase) return;
    let active = true;
    void supabase.auth.getSession().then(async ({ data }) => {
      if (!active) return;
      const session = data.session;
      if (!session) {
        setStatus("signed-out");
        return;
      }
      accessTokenRef.current = session.access_token;
      setUserId(session.user.id);
      try {
        await loadCanonical(session.access_token);
      } catch (error) {
        if (!active) return;
        setStatus("error");
        setMessage(error instanceof Error ? error.message : "No pudimos recuperar tu ficha.");
      }
    });
    return () => { active = false; };
  }, [loadCanonical]);

  useEffect(() => {
    if (!supabase || !userId) return;
    const supabaseClient = supabase;
    const activeGroupId = snapshot?.writeContext.groupId ?? null;
    let active = true;
    let refreshInFlight = false;

    const refreshCanonical = () => {
      if (!active || refreshInFlight || !navigator.onLine) return;
      refreshInFlight = true;
      void (async () => {
        try {
          let accessToken = accessTokenRef.current;
          if (!accessToken) {
            const session = (await supabaseClient.auth.getSession()).data.session;
            accessToken = session?.access_token ?? "";
            accessTokenRef.current = accessToken;
          }
          if (accessToken) await loadCanonical(accessToken, true);
        } catch {
          // Realtime is an invalidation signal. The canonical read retries on reconnect.
        } finally {
          refreshInFlight = false;
        }
      })();
    };

    window.addEventListener("online", refreshCanonical);
    let channel = supabaseClient
      .channel(`player-assessment-onboarding:${userId}`)
      .on("postgres_changes", {
        event: "INSERT",
        filter: `audience_user_id=eq.${userId}`,
        schema: "public",
        table: "pachanga_social_invalidations_v1",
      }, (event) => {
        if (event.new?.entity_type === "rating_profile") refreshCanonical();
      });
    if (activeGroupId) {
      channel = channel.on("postgres_changes", {
        event: "INSERT",
        filter: `group_id=eq.${activeGroupId}`,
        schema: "public",
        table: "pachanga_group_events",
      }, refreshCanonical);
    }
    channel.subscribe((subscriptionStatus) => {
      if (subscriptionStatus === "SUBSCRIBED") refreshCanonical();
    });

    return () => {
      active = false;
      window.removeEventListener("online", refreshCanonical);
      void supabaseClient.removeChannel(channel);
    };
  }, [loadCanonical, snapshot?.writeContext.groupId, userId]);

  useEffect(() => {
    if (!flow || !userId || flow.saving) return;
    try {
      window.localStorage.setItem(draftKey(userId, flow.kind), JSON.stringify(flow));
    } catch {
      // A draft is useful but never required for the canonical write.
    }
  }, [flow, userId]);

  const initialInput = flow?.initial ?? (snapshot?.assessments.initial?.input as InitialRatingInput | undefined);
  const initialResult = useMemo(() => {
    if (!initialInput) return null;
    try {
      return calculateInitialRatings(initialInput);
    } catch {
      return null;
    }
  }, [initialInput]);
  const advancedQuestions = useMemo(
    () => initialResult ? calculateApplicableAdvancedQuestions(initialResult) : [],
    [initialResult],
  );
  const advancedResult = useMemo(() => {
    if (!initialResult || flow?.kind !== "advanced") return null;
    try {
      return calculateAdvancedRatings({ initial: initialResult, answers: flow.advancedAnswers });
    } catch {
      return null;
    }
  }, [flow, initialResult]);

  const beginAssessment = useCallback((kind: AssessmentKind, source = snapshot) => {
    if (!userId || !source) return;
    if (source.assessments[kind]) {
      setMessage(kind === "initial" ? "El test inicial ya está completado." : "El test avanzado ya está completado.");
      return;
    }
    const existing = readDraft(userId, kind);
    if (existing) {
      setFlow(existing);
      setMessage("");
      return;
    }
    const canonicalInitial = source.assessments.initial?.input as InitialRatingInput | undefined;
    if (kind === "advanced" && !canonicalInitial) {
      setMessage("Completa primero el test inicial.");
      return;
    }
    setFlow({
      advancedAnswers: {},
      initial: canonicalInitial ?? makeInitialInput(),
      kind,
      operationId: crypto.randomUUID(),
      saving: false,
      step: -1,
    });
    setMessage("");
  }, [snapshot, userId]);

  useEffect(() => {
    if (!snapshot || !userId || advancedDeepLinkHandled.current) return;
    advancedDeepLinkHandled.current = true;
    let active = true;
    if (new URLSearchParams(window.location.search).get("tipo") === "avanzado") {
      queueMicrotask(() => {
        if (active) beginAssessment("advanced", snapshot);
      });
    }
    return () => { active = false; };
  }, [beginAssessment, snapshot, userId]);

  useEffect(() => {
    if (!snapshot || !userId || initialDeepLinkHandled.current) return;
    initialDeepLinkHandled.current = true;
    let active = true;
    const params = new URLSearchParams(window.location.search);
    if (params.get("onboarding") === "1" && snapshot.onboardingProfileReady && !snapshot.assessments.initial) {
      queueMicrotask(() => {
        if (active) beginAssessment("initial", snapshot);
      });
    }
    return () => { active = false; };
  }, [beginAssessment, snapshot, userId]);

  const previewRatings: AttributeRatings | null = flow?.kind === "advanced"
    ? advancedResult?.baseRatings ?? initialResult?.profile.baseRatings ?? null
    : initialResult?.profile.baseRatings ?? null;
  const previewOverall = flow?.kind === "advanced"
    ? advancedResult?.baseOverall ?? initialResult?.profile.baseOverall ?? 50
    : initialResult?.profile.baseOverall ?? 50;
  const previewPosition = initialResult?.profile.primaryPosition ?? "central_midfielder";
  const technicalGroup = flow?.kind === "initial" ? ASSESSMENT_INITIAL_QUESTION_GROUPS[flow.step - 5] : undefined;
  const advancedQuestion = flow?.kind === "advanced" ? advancedQuestions[Math.max(0, flow.step)] : undefined;
  const totalSteps = flow?.kind === "initial" ? ASSESSMENT_INITIAL_STEP_COUNT : advancedQuestions.length;
  const stepReady = flow?.kind === "initial"
    ? assessmentInitialStepIsComplete(flow.initial, flow.step)
    : Boolean(flow && (flow.step === -1 || advancedQuestion && flow.advancedAnswers[advancedQuestion.id] != null));
  const profile = snapshot?.playerProfile ?? null;
  const initialAssessmentRequired = status !== "ready" || !snapshot?.assessments.initial;
  const displayedFacets = ATTRIBUTE_KEYS.map((key) => ({
    key,
    label: ({ pace: "RIT", shooting: "TIR", passing: "PAS", dribbling: "REG", defending: "DEF", physical: "FIS" } as const)[key],
    value: Math.round(Number(profile?.current_facets?.[key] ?? previewRatings?.[key] ?? 50)),
  }));

  useEffect(() => {
    if (!initialAssessmentRequired) return;
    document.body.classList.add("first-time-onboarding-active");
    return () => document.body.classList.remove("first-time-onboarding-active");
  }, [initialAssessmentRequired]);

  async function completeAssessment() {
    if (!flow || !snapshot || !supabase || !navigator.onLine) {
      setMessage("Sin conexión: ninguna ficha se ha confirmado.");
      return;
    }
    if (flow.kind === "initial" && !assessmentInitialIsComplete(flow.initial)) {
      setMessage("Completa todas las respuestas del test inicial.");
      return;
    }
    if (flow.kind === "advanced" && advancedQuestions.some((question) => flow.advancedAnswers[question.id] == null)) {
      setMessage("Completa todas las respuestas del test avanzado.");
      return;
    }

    const session = (await supabase.auth.getSession()).data.session;
    if (!session) {
      setStatus("signed-out");
      return;
    }
    setFlow((current) => current ? { ...current, saving: true } : current);
    setMessage(flow.kind === "initial" ? "Creando tu ficha confirmada..." : "Mejorando la precisión de tu ficha...");
    try {
      const response = await clientWriteFetch("api:ratings-assessment", "/api/ratings/assessment", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${session.access_token}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          assessmentInput: flow.kind === "initial"
            ? { ...flow.initial, engineVersion: FOOTBALL_RATING_ENGINE_VERSION, questionnaireVersion: INITIAL_TEST_VERSION }
            : { answers: flow.advancedAnswers, engineVersion: FOOTBALL_RATING_ENGINE_VERSION, questionnaireVersion: ADVANCED_TEST_VERSION },
          clientMetadata: assessmentMetadata(),
          expectedRevision: snapshot.writeContext.expectedRevision,
          groupId: snapshot.writeContext.groupId,
          kind: flow.kind,
          operationId: flow.operationId,
          playerId: snapshot.writeContext.playerId,
        }),
      });
      const payload = await response.json() as unknown;
      if (!response.ok) {
        if (response.status === 409) await loadCanonical(session.access_token);
        throw new Error(isRecord(payload) && typeof payload.error === "string" ? payload.error : "No se pudo guardar el test.");
      }
      const canonical = normalizeSnapshot(payload);
      if (!canonical) throw new Error("El servidor no devolvió la ficha confirmada.");
      setSnapshot(canonical);
      window.localStorage.removeItem(draftKey(userId, flow.kind));
      setFlow(null);
      setMessage(flow.kind === "initial" ? "Ficha creada con test inicial" : "Ficha afinada con test avanzado");
      if (flow.kind === "initial") {
        const returnPath = safeAssessmentReturnPath(window.location.search);
        if (returnPath !== "/") {
          window.location.replace(returnPath);
          return;
        }
        const params = new URLSearchParams(window.location.search);
        params.delete("onboarding");
        window.history.replaceState(null, "", params.size ? `${window.location.pathname}?${params.toString()}` : window.location.pathname);
      }
    } catch (error) {
      setFlow((current) => current ? { ...current, saving: false } : current);
      setMessage(error instanceof Error ? error.message : "No se pudo guardar el test.");
    }
  }

  function updateInitial(patch: Partial<InitialRatingInput>) {
    setFlow((current) => current ? { ...current, initial: { ...current.initial, ...patch } } : current);
  }

  function toggleMode(mode: FootballMode) {
    setFlow((current) => {
      if (!current) return current;
      const modes = assessmentSelectedModes(current.initial.modeShares);
      const next = modes.includes(mode) ? modes.filter((entry) => entry !== mode) : [...modes, mode];
      return { ...current, initial: { ...current.initial, modeShares: assessmentSharesFromSelectedModes(next) } };
    });
  }

  const cardName = profile?.display_name ?? "Tu primera ficha";
  const cardScore = Math.round(Number(profile?.current_overall ?? previewOverall));
  const cardPosition = shortPosition(profile?.position ?? assessmentPositionLabels[previewPosition]);

  const pageContent = (
    <main className={styles.page} data-assessment-onboarding="v1" data-assessment-status={status}>
        <nav className={styles.topbar}>
          <Link href={initialAssessmentRequired ? onboardingReturnHref : "/perfil"}>Volver</Link>
          <strong>Mi carta</strong>
          <div className={styles.topbarMeta}>
            <span>{profile ? `Rev. ${profile.profile_version}` : "Nueva"}</span>
            {initialAssessmentRequired ? <ThemeToggle compact defaultPreference="dark" /> : null}
          </div>
        </nav>

        {status === "loading" ? <section className={styles.state}><strong>Recuperando tu ficha confirmada...</strong></section> : null}
        {status === "signed-out" ? <section className={styles.state}><h1>Inicia sesión para crear tu ficha</h1><Link href="/">Ir a Inicio</Link></section> : null}
        {status === "error" ? <section className={styles.state}><h1>No pudimos abrir el test</h1><p>{message}</p><Link href="/">Volver al inicio</Link></section> : null}
        {status === "offline" ? <section className={styles.state}><h1>Necesitas conexión para crear la ficha</h1><p>{message}</p><button type="button" onClick={() => window.location.reload()}>Reintentar</button></section> : null}

        {status === "ready" && snapshot ? (
          <section className={`top-panel player-assessment-panel ${styles.panel}`} aria-label={flow?.kind === "advanced" ? "Test avanzado de ficha" : "Test inicial de ficha"}>
            <div className="player-assessment-preview">
              <PlayerCosmeticCard
                ariaLabel={`Ficha de ${cardName}`}
                className="fifa-card-gold readonly-card"
                facets={displayedFacets}
                meta={flow ? flow.kind === "initial" ? "Test inicial" : "Test avanzado" : `${Math.round(profile?.rating_reliability ?? 0)}% fiabilidad`}
                name={cardName}
                photoAlt={`Foto de ${cardName}`}
                photoSrc={profile?.avatar}
                position={cardPosition}
                score={cardScore}
              />
            </div>

            <div className="player-assessment-flow">
              {!flow ? (
                <div className={styles.summary}>
                  <span>{snapshot.assessments.initial ? "Test inicial completado" : "Primera valoración"}</span>
                  <h1>{snapshot.assessments.initial ? "Tu ficha ya está creada" : "Crea tu primera ficha"}</h1>
                  {snapshot.assessments.initial ? (
                    <p className={styles.spinReward}>Has conseguido <strong>1 giro gratis en la ruleta</strong> por completar el test inicial.</p>
                  ) : null}
                  {!snapshot.assessments.initial ? (
                    snapshot.onboardingProfileReady ? (
                      <>
                        <p>Responde unas preguntas sobre cómo juegas. Crearemos tu primera media y tus atributos. Después evolucionarán con partidos y valoraciones.</p>
                        <button className="primary-button" type="button" onClick={() => beginAssessment("initial")}>Hacer test inicial y crear mi carta</button>
                      </>
                    ) : (
                      <>
                        <p>Completa primero tu nombre, preferencias y ciudad o población. Después podrás crear tu carta.</p>
                        <div className={styles.summaryActions}><Link href="/">Completar pasos 1 y 2</Link></div>
                      </>
                    )
                  ) : (
                    <div className={styles.summaryActions}>
                      <Link href={onboardingReturnHref}>Entrar en Pachangas IQ</Link>
                      <Link href="/personalizar-carta?returnTo=%2Fperfil%2Ftest-inicial">Personalizar mi carta</Link>
                      {!snapshot.assessments.advanced ? (
                        <div className={styles.advancedAction}>
                          <button className="primary-button" type="button" aria-describedby="advanced-test-reward" onClick={() => beginAssessment("advanced")}>Mejorar precisión de mi carta</button>
                          <p id="advanced-test-reward">Completa el test avanzado para definir mejor tu carta y conseguir <strong>otro giro gratis en la ruleta.</strong></p>
                        </div>
                      ) : <strong>Test avanzado completado</strong>}
                    </div>
                  )}
                </div>
              ) : (
                <>
                  <div className="player-assessment-title">
                    <span>{flow.kind === "initial" ? "Test obligatorio" : "Test opcional"}</span>
                    <strong>{flow.kind === "initial" ? "Crea tu ficha inicial" : "Afina tu ficha"}</strong>
                    <button type="button" onClick={() => setFlow(null)} aria-label="Cerrar test" disabled={flow.saving}>×</button>
                  </div>
                  <div className="player-assessment-progress">
                    <progress max={Math.max(1, totalSteps)} value={flow.step < 0 ? 0 : Math.min(flow.step + 1, totalSteps)} />
                    <small>{flow.step < 0 ? "Aviso inicial" : `Paso ${flow.step + 1}/${totalSteps}`}</small>
                  </div>

                  {flow.step === -1 ? (
                    <div className="player-assessment-intro">
                      <p>Este test crea tu ficha real y solo se puede completar una vez por usuario. Responde con la máxima sinceridad: después evolucionará con partidos y valoraciones.</p>
                      <p>Si sales antes de terminar, solo conservaremos un borrador en este dispositivo. No existirá ninguna ficha confirmada hasta que responda el servidor.</p>
                      <button className="primary-button" type="button" onClick={() => setFlow((current) => current ? { ...current, step: 0 } : current)}>{flow.kind === "initial" ? "Empezar test" : "Empezar test avanzado"}</button>
                    </div>
                  ) : null}

                  {flow.kind === "initial" && flow.step === 0 ? <div className="player-assessment-step"><h3>¿A qué juegas normalmente?</h3><div className="player-assessment-choice-grid">{ASSESSMENT_MODE_OPTIONS.map((option) => <button aria-pressed={assessmentSelectedModes(flow.initial.modeShares).includes(option.mode)} className={assessmentSelectedModes(flow.initial.modeShares).includes(option.mode) ? "selected" : ""} key={option.mode} onClick={() => toggleMode(option.mode)} type="button">{option.label}</button>)}</div></div> : null}
                  {flow.kind === "initial" && flow.step === 1 ? <div className="player-assessment-step"><h3>Posición en el campo</h3><div className="player-assessment-choice-grid">{Object.entries(assessmentPositionLabels).map(([position, label]) => <button className={flow.initial.primaryPosition === position ? "selected" : ""} key={position} onClick={() => updateInitial({ primaryPosition: position as PlayerPosition, secondaryPositions: [] })} type="button">{label}</button>)}</div></div> : null}
                  {flow.kind === "initial" && flow.step === 2 ? <div className="player-assessment-step"><h3>¿Cuál es o ha sido tu nivel más alto?</h3><div className="player-assessment-choice-grid">{ASSESSMENT_EXPERIENCE_OPTIONS.map((option) => <button className={flow.initial.experienceLevel === option.id ? "selected" : ""} key={option.id} onClick={() => updateInitial({ experienceLevel: option.id })} type="button">{option.label}</button>)}</div></div> : null}
                  {flow.kind === "initial" && flow.step === 3 ? <div className="player-assessment-step"><h3>¿Cuándo jugabas a ese nivel?</h3><div className="player-assessment-choice-grid compact">{ASSESSMENT_YEARS_SINCE_LEVEL_OPTIONS.map((option) => <button className={flow.initial.yearsSinceLevel === option.value ? "selected" : ""} key={option.value} onClick={() => updateInitial({ yearsSinceLevel: option.value })} type="button">{option.label}</button>)}</div></div> : null}
                  {flow.kind === "initial" && flow.step === 4 ? <div className="player-assessment-step"><h3>¿Con qué frecuencia juegas o entrenas?</h3><div className="player-assessment-choice-grid">{Object.entries(FREQUENCIES).map(([frequencyId, frequency]) => <button className={flow.initial.frequency === frequencyId ? "selected" : ""} key={frequencyId} onClick={() => updateInitial({ frequency: frequencyId as FrequencyId })} type="button">{frequency.label}</button>)}</div></div> : null}
                  {flow.kind === "initial" && technicalGroup ? <div className="player-assessment-step"><span>{technicalGroup.subtitle}</span><h3>{technicalGroup.title}</h3>{technicalGroup.questionIds.map((questionId) => { const question = INITIAL_TECHNICAL_QUESTIONS.find((entry) => entry.id === questionId); return question ? <div className="player-assessment-question" key={question.id}><p>{question.prompt}</p><div className="player-assessment-choice-grid">{ASSESSMENT_INITIAL_ANSWER_OPTIONS[question.id].map((option) => <button className={flow.initial.answers[question.id] === option.value ? "selected" : ""} key={option.value} onClick={() => setFlow((current) => current ? { ...current, initial: { ...current.initial, answers: { ...current.initial.answers, [question.id]: option.value } } } : current)} type="button">{option.label}</button>)}</div></div> : null; })}</div> : null}
                  {flow.kind === "advanced" && flow.step >= 0 && advancedQuestion ? <div className="player-assessment-step"><span>{advancedQuestion.id}</span><h3>{advancedQuestion.prompt}</h3><div className="player-assessment-choice-grid">{assessmentAdvancedAnswerOptions(advancedQuestion).map((option) => <button className={flow.advancedAnswers[advancedQuestion.id] === option.value ? "selected" : ""} key={option.value} onClick={() => setFlow((current) => current ? { ...current, advancedAnswers: { ...current.advancedAnswers, [advancedQuestion.id]: option.value } } : current)} type="button">{option.label}</button>)}</div></div> : null}

                  {flow.step >= 0 ? <div className="player-assessment-actions"><button className="ghost-form-button" disabled={flow.saving || flow.step <= 0} onClick={() => setFlow((current) => current ? { ...current, step: Math.max(0, current.step - 1) } : current)} type="button">Atrás</button><button className="primary-button" disabled={flow.saving || !stepReady} onClick={() => { if (flow.step >= totalSteps - 1) void completeAssessment(); else setFlow((current) => current ? { ...current, step: current.step + 1 } : current); }} type="button">{flow.saving ? "Guardando..." : flow.step >= totalSteps - 1 ? flow.kind === "initial" ? "Crear ficha" : "Guardar test avanzado" : "Continuar"}</button></div> : null}
                </>
              )}
              {message ? <p className="player-assessment-message" role="status">{message}</p> : null}
            </div>
          </section>
        ) : null}
    </main>
  );

  if (initialAssessmentRequired) {
    return <div className={styles.requiredShell} data-player-card-onboarding-gate="assessment">{pageContent}</div>;
  }

  return (
    <OfficialProductShellV2
      active="perfil"
      context={{
        detail: snapshot?.writeContext.scope === "group" ? "Sincronizada con tu equipo" : "Ficha universal",
        eyebrow: "Mi carta",
        status: status === "ready" ? "Servidor conectado" : status === "offline" ? "Sin conexión" : "Comprobando",
        title: "Test de nivel",
      }}
      links={{ perfil: "/perfil" }}
      perspective="free-agent"
    >
      {pageContent}
    </OfficialProductShellV2>
  );
}
