"use client";

import Image from "next/image";
import { useEffect, useMemo, useRef, useState } from "react";
import styles from "./page.module.css";
import {
  ATTRIBUTE_KEYS,
  ATTRIBUTE_LABELS,
  type AdvancedQuestion,
  type AttributeRatings,
  type AnswerValue,
  type CurrentLimitationInput,
  type FrequencyId,
  FREQUENCIES,
  type FootballMode,
  type InitialRatingInput,
  INITIAL_TECHNICAL_QUESTIONS,
  type InitialTechnicalQuestionId,
  type LifestyleInput,
  type ModeShare,
  POSITION_LABELS,
  POSITION_SHORT_LABELS,
  type PlayerPosition,
  RESPONSE_OPTIONS,
  calculateAdvancedRatings,
  calculateApplicableAdvancedQuestions,
  calculateCurrentRatings,
  calculateInitialRatings,
  roundRating,
} from "./_engine/player-rating-engine";

type LabState = {
  initial: InitialRatingInput;
  advancedAnswers: Record<string, AnswerValue>;
  lifestyle: LifestyleInput;
  limitation: CurrentLimitationInput;
  flow: "advanced" | "initial" | "result";
  initialStep: number;
  advancedStep: number;
};

const STORAGE_KEY = "pachangas-player-evaluation-lab-v3";
const STABLE_LAB_CALCULATION_DATE = "2026-07-31T00:00:00.000Z";
const emptyInitialAnswers = Object.fromEntries(INITIAL_TECHNICAL_QUESTIONS.map((question) => [question.id, null])) as Record<InitialTechnicalQuestionId, AnswerValue>;

const defaultState: LabState = {
  initial: {
    age: 28,
    heightCm: 178,
    weightKg: 76,
    primaryPosition: "central_midfielder",
    secondaryPositions: ["attacking_midfielder"],
    modeShares: [
      { mode: "futsal_5", percentage: 0 },
      { mode: "football_7", percentage: 100 },
      { mode: "football_11", percentage: 0 },
    ],
    experienceLevel: "social_league",
    yearsSinceLevel: 0,
    frequency: "weekly",
    answers: emptyInitialAnswers,
    calculatedAt: STABLE_LAB_CALCULATION_DATE,
  },
  advancedAnswers: {},
  lifestyle: { sleep: null, training: null, recovery: null, habits: null },
  limitation: {
    consent: false,
    recovered: false,
    severity: 0,
    frequency: 0.5,
    actions: [],
  },
  flow: "initial",
  initialStep: 0,
  advancedStep: 0,
};

const modeOptions: Array<{ mode: FootballMode; label: string }> = [
  { mode: "futsal_5", label: "Fútbol sala" },
  { mode: "football_7", label: "Fútbol 7" },
  { mode: "football_11", label: "Fútbol 11" },
];

const experienceOptions: Array<{ id: InitialRatingInput["experienceLevel"]; label: string }> = [
  { id: "barely_played", label: "Estoy empezando" },
  { id: "occasional_pachangas", label: "Pachangas ocasionales" },
  { id: "regular_pachangas", label: "Pachangas habituales" },
  { id: "social_league", label: "Liga social o amateur" },
  { id: "federated_club", label: "Club federado" },
  { id: "national_semipro", label: "Semipro o superior" },
];

const yearsSinceLevelOptions = [
  { value: 0, label: "Juego ahora" },
  { value: 2, label: "Hace 1-2 años" },
  { value: 5, label: "Hace 3-5 años" },
  { value: 10, label: "Hace 6-10 años" },
  { value: 15, label: "Hace más de 10 años" },
];

const initialAnswerOptions: Record<InitialTechnicalQuestionId, Array<{ value: Exclude<AnswerValue, null>; label: string }>> = {
  controlUnderPressure: [
    { value: 1, label: "La pierdo a menudo" },
    { value: 2, label: "Solo con tiempo" },
    { value: 3, label: "Normal en mis partidos" },
    { value: 4, label: "Controlo bajo presión" },
    { value: 5, label: "Destaco controlando" },
  ],
  ballCarrying: [
    { value: 1, label: "Me cuesta conducir" },
    { value: 2, label: "Solo con espacio" },
    { value: 3, label: "Normal en mis partidos" },
    { value: 4, label: "Salgo bien conduciendo" },
    { value: 5, label: "Desbordo con facilidad" },
  ],
  passingExecution: [
    { value: 1, label: "Fallo muchos pases" },
    { value: 2, label: "Pases fáciles" },
    { value: 3, label: "Normal en mis partidos" },
    { value: 4, label: "Paso bien con presión" },
    { value: 5, label: "Creo juego con pases" },
  ],
  decisionMaking: [
    { value: 1, label: "Me precipito" },
    { value: 2, label: "Decido bien con tiempo" },
    { value: 3, label: "Normal en mis partidos" },
    { value: 4, label: "Decido rápido y bien" },
    { value: 5, label: "Leo muy bien el juego" },
  ],
  finishing: [
    { value: 1, label: "Casi no genero peligro" },
    { value: 2, label: "Solo ocasiones claras" },
    { value: 3, label: "Normal en mis partidos" },
    { value: 4, label: "Suelo crear peligro" },
    { value: 5, label: "Marco diferencias arriba" },
  ],
  attackingMovement: [
    { value: 1, label: "Me cuesta ofrecerme" },
    { value: 2, label: "Me muevo poco" },
    { value: 3, label: "Normal en mis partidos" },
    { value: 4, label: "Me desmarco bien" },
    { value: 5, label: "Siempre doy opción" },
  ],
  defensivePositioning: [
    { value: 1, label: "Pierdo la posición" },
    { value: 2, label: "Defiendo a ratos" },
    { value: 3, label: "Normal en mis partidos" },
    { value: 4, label: "Me coloco bien" },
    { value: 5, label: "Anticipo y recupero" },
  ],
  defensiveDuels: [
    { value: 1, label: "Me superan fácil" },
    { value: 2, label: "Me cuesta frenar" },
    { value: 3, label: "Normal en mis partidos" },
    { value: 4, label: "Gano bastantes duelos" },
    { value: 5, label: "Soy muy difícil de superar" },
  ],
  paceComparison: [
    { value: 1, label: "Soy de los más lentos" },
    { value: 2, label: "Me cuesta ganar carreras" },
    { value: 3, label: "Normal en mis partidos" },
    { value: 4, label: "Soy bastante rápido" },
    { value: 5, label: "Soy de los más rápidos" },
  ],
  physicalIntensity: [
    { value: 1, label: "Me falta intensidad" },
    { value: 2, label: "Me cuesta aguantar" },
    { value: 3, label: "Normal en mis partidos" },
    { value: 4, label: "Aguanto bien" },
    { value: 5, label: "Destaco físicamente" },
  ],
};

const initialQuestionGroups: Array<{
  title: string;
  subtitle: string;
  questionIds: InitialTechnicalQuestionId[];
}> = [
  { title: "Control", subtitle: "Recepción bajo presión", questionIds: ["controlUnderPressure"] },
  { title: "Conducción", subtitle: "Giro, conducción y regate", questionIds: ["ballCarrying"] },
  { title: "Pase", subtitle: "Ejecución con presión", questionIds: ["passingExecution"] },
  { title: "Decisión", subtitle: "Elegir antes de que cierre el rival", questionIds: ["decisionMaking"] },
  { title: "Finalización", subtitle: "Ocasiones favorables", questionIds: ["finishing"] },
  { title: "Movimiento", subtitle: "Recibir y crear espacio", questionIds: ["attackingMovement"] },
  { title: "Defensa", subtitle: "Posición, anticipación y recuperación", questionIds: ["defensivePositioning"] },
  { title: "Duelos", subtitle: "Frenar al rival", questionIds: ["defensiveDuels"] },
  { title: "Ritmo", subtitle: "Aceleraciones y carreras", questionIds: ["paceComparison"] },
  { title: "Físico", subtitle: "Intensidad durante el partido", questionIds: ["physicalIntensity"] },
];

const initialStepCount = 5 + initialQuestionGroups.length;

function zeroDisplayRatings(): AttributeRatings {
  return { pace: 0, shooting: 0, passing: 0, dribbling: 0, defending: 0, physical: 0 };
}

function initialTestIsComplete(initial: InitialRatingInput) {
  const allTechnicalAnswered = INITIAL_TECHNICAL_QUESTIONS.every((question) => initial.answers[question.id] !== null);
  const modeTotal = initial.modeShares.reduce((total, share) => total + share.percentage, 0);
  return allTechnicalAnswered && Math.round(modeTotal * 100) / 100 === 100;
}

function initialStepIsComplete(initial: InitialRatingInput, step: number) {
  if (step === 0) {
    return Math.round(initial.modeShares.reduce((total, share) => total + share.percentage, 0) * 100) / 100 === 100;
  }
  if (step === 1) {
    return Boolean(initial.primaryPosition);
  }
  if (step === 2) {
    return Boolean(initial.experienceLevel);
  }
  if (step === 3) {
    return initial.yearsSinceLevel >= 0;
  }
  if (step === 4) {
    return Boolean(initial.frequency);
  }
  const group = initialQuestionGroups[step - 5];
  return group ? group.questionIds.every((questionId) => initial.answers[questionId] !== null) : false;
}

function normalizeModeShares(modeShares: ModeShare[]): ModeShare[] {
  const modes: FootballMode[] = ["futsal_5", "football_7", "football_11"];
  const withAllModes = modes.map((mode) => ({
    mode,
    percentage: clampPercentage(modeShares.find((share) => share.mode === mode)?.percentage ?? 0),
  }));
  const total = withAllModes.reduce((sum, share) => sum + share.percentage, 0);
  if (total === 100) {
    return withAllModes;
  }
  if (total === 0) {
    return [
      { mode: "futsal_5", percentage: 0 },
      { mode: "football_7", percentage: 100 },
      { mode: "football_11", percentage: 0 },
    ] satisfies ModeShare[];
  }
  return withAllModes.map((share, index) => {
    const normalized = index === withAllModes.length - 1 ? 100 - withAllModes.slice(0, -1).reduce((sum, item) => sum + item.percentage, 0) : Math.round((share.percentage / total) * 100);
    return { ...share, percentage: clampPercentage(normalized) };
  });
}

function clampPercentage(value: number) {
  return Math.max(0, Math.min(100, Math.round(value)));
}

function selectedModes(modeShares: ModeShare[]) {
  return modeShares.filter((share) => share.percentage > 0).map((share) => share.mode);
}

function sharesFromSelectedModes(modes: FootballMode[]): ModeShare[] {
  if (modes.length === 0) {
    return modeOptions.map(({ mode }) => ({ mode, percentage: 0 }));
  }
  const base = Math.floor(100 / modes.length);
  let remainder = 100 - base * modes.length;
  return modeOptions.map(({ mode }) => {
    const active = modes.includes(mode);
    const extra = active && remainder > 0 ? 1 : 0;
    if (extra) {
      remainder -= 1;
    }
    return { mode, percentage: active ? base + extra : 0 };
  });
}

function precisionLabel(reliability: number) {
  if (reliability >= 86) {
    return "Muy ajustada";
  }
  if (reliability >= 72) {
    return "Buena";
  }
  return "Provisional";
}

function sanitizeLabState(input: unknown): LabState {
  if (!input || typeof input !== "object") {
    return defaultState;
  }
  const stored = input as Partial<LabState>;
  const storedInitial = stored.initial ?? defaultState.initial;
  return {
    ...defaultState,
    ...stored,
    initial: {
      ...defaultState.initial,
      ...storedInitial,
      modeShares: normalizeModeShares((storedInitial.modeShares ?? defaultState.initial.modeShares) as ModeShare[]),
      answers: { ...defaultState.initial.answers, ...(storedInitial.answers ?? {}) },
      calculatedAt: storedInitial.calculatedAt ?? STABLE_LAB_CALCULATION_DATE,
    },
    advancedAnswers: stored.advancedAnswers ?? defaultState.advancedAnswers,
    lifestyle: { ...defaultState.lifestyle, ...(stored.lifestyle ?? {}) },
    limitation: { ...defaultState.limitation, ...(stored.limitation ?? {}) },
    flow: stored.flow ?? defaultState.flow,
    initialStep: stored.initialStep ?? defaultState.initialStep,
    advancedStep: stored.advancedStep ?? defaultState.advancedStep,
  };
}

export default function PlayerEvaluationLabPage() {
  const [state, setState] = useState<LabState>(defaultState);
  const storageReady = useRef(false);

  useEffect(() => {
    document.body.classList.add("player-evaluation-lab-body");
    return () => document.body.classList.remove("player-evaluation-lab-body");
  }, []);

  useEffect(() => {
    const stored = localStorage.getItem(STORAGE_KEY);
    window.setTimeout(() => {
      if (stored) {
        setState(sanitizeLabState(JSON.parse(stored)));
      }
      storageReady.current = true;
    }, 0);
  }, []);

  useEffect(() => {
    if (storageReady.current) {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
    }
  }, [state]);

  const initialResult = useMemo(() => calculateInitialRatings(state.initial), [state.initial]);
  const initialComplete = useMemo(() => initialTestIsComplete(state.initial), [state.initial]);
  const applicableAdvancedQuestions = useMemo(() => calculateApplicableAdvancedQuestions(initialResult), [initialResult]);
  const advancedResult = useMemo(() => calculateAdvancedRatings({ initial: initialResult, answers: state.advancedAnswers }), [initialResult, state.advancedAnswers]);
  const currentResult = useMemo(
    () =>
      calculateCurrentRatings({
        baseRatings: advancedResult.baseRatings,
        primaryPosition: state.initial.primaryPosition,
        frequencyAdjustment: initialResult.frequencyAdjustment,
        lifestyle: state.lifestyle,
        limitation: state.limitation,
      }),
    [advancedResult.baseRatings, initialResult.frequencyAdjustment, state.initial.primaryPosition, state.lifestyle, state.limitation],
  );
  const advancedStepCount = Math.max(1, applicableAdvancedQuestions.length);
  const advancedQuestion = applicableAdvancedQuestions[Math.min(state.advancedStep, Math.max(0, applicableAdvancedQuestions.length - 1))];
  const advancedAnsweredCount = applicableAdvancedQuestions.filter((question) => state.advancedAnswers[question.id] !== undefined && state.advancedAnswers[question.id] !== null).length;
  const advancedComplete = applicableAdvancedQuestions.length > 0 && advancedAnsweredCount === applicableAdvancedQuestions.length;
  const isTestFlow = state.flow === "initial" || state.flow === "advanced";
  const testStepCount = state.flow === "advanced" ? advancedStepCount : initialStepCount;
  const testStepValue = state.flow === "advanced" ? Math.min(state.advancedStep + 1, advancedStepCount) : state.initialStep + 1;
  const displayRatings = initialComplete ? advancedResult.baseRatings : zeroDisplayRatings();
  const displayBaseOverall = initialComplete ? advancedResult.baseOverall : 0;
  const displayCurrentOverall = initialComplete ? currentResult.currentOverall : 0;
  const displayReliability = initialComplete ? advancedResult.reliability : 0;

  function updateInitial(patch: Partial<InitialRatingInput>) {
    setState((current) => ({ ...current, initial: { ...current.initial, ...patch } }));
  }

  function toggleMode(mode: FootballMode) {
    setState((current) => {
      const currentModes = selectedModes(current.initial.modeShares);
      const nextModes = currentModes.includes(mode) ? currentModes.filter((item) => item !== mode) : [...currentModes, mode];
      return { ...current, initial: { ...current.initial, modeShares: sharesFromSelectedModes(nextModes) } };
    });
  }

  function updateInitialAnswer(id: InitialTechnicalQuestionId, value: AnswerValue) {
    setState((current) => ({
      ...current,
      initial: { ...current.initial, answers: { ...current.initial.answers, [id]: value } },
    }));
  }

  function updateAdvancedAnswer(id: string, value: AnswerValue) {
    setState((current) => ({ ...current, advancedAnswers: { ...current.advancedAnswers, [id]: value } }));
  }

  return (
    <main className={isTestFlow ? styles.testPage : styles.page}>
      {isTestFlow ? (
        <section className={styles.testTop}>
          <button type="button" onClick={() => setState(defaultState)} aria-label="Cerrar test">
            ×
          </button>
          <progress max={testStepCount} value={testStepValue} />
        </section>
      ) : null}

      {!isTestFlow ? (
      <section className={styles.hero}>
        <div className={styles.brand}>
          <Image src="/brand/pachangas-logo-hero.png" alt="Pachangas IQ" width={192} height={192} priority />
          <div>
            <p>Laboratorio local</p>
            <h1>Ficha universal de jugador</h1>
          </div>
        </div>
        <div className={styles.heroActions}>
          <button className={styles.ghostButton} type="button" onClick={() => setState(defaultState)}>
            Reiniciar
          </button>
        </div>
      </section>
      ) : null}

      {!isTestFlow ? (
      <section className={styles.resultsBand} aria-label="Resultados finales">
        <PlayerCard
          overall={roundRating(displayBaseOverall)}
          currentOverall={roundRating(displayCurrentOverall)}
          position={state.initial.primaryPosition}
          ratings={displayRatings}
          ready={initialComplete}
        />
        <div className={styles.resultMetrics}>
          <Metric label="Media inicial" value={roundRating(displayBaseOverall)} />
          <Metric label="Estado actual" value={roundRating(displayCurrentOverall)} />
          <Metric label="Precisión" value={initialComplete ? precisionLabel(displayReliability) : "Pendiente"} />
          <Metric label="Forma" value={initialComplete && currentResult.preparationIndex !== null ? "Añadida" : "Pendiente"} />
        </div>
      </section>
      ) : null}

      {initialComplete && state.flow === "result" ? (
        <section className={styles.panel}>
          <PanelTitle kicker={advancedComplete ? "Ficha actualizada" : "Ficha provisional creada"} title={advancedComplete ? "Resultado de los tests avanzados" : "Resultado del test obligatorio"} aside={precisionLabel(displayReliability)} />
          <div className={styles.nextActions}>
            <button type="button" onClick={() => setState((current) => ({ ...current, flow: "advanced", advancedStep: Math.min(current.advancedStep, Math.max(0, applicableAdvancedQuestions.length - 1)) }))}>
              {advancedAnsweredCount > 0 ? "Seguir mejorando precisión" : "Mejorar precisión de mi ficha"}
            </button>
            <button className={styles.ghostButton} type="button" onClick={() => setState((current) => ({ ...current, flow: "initial", initialStep: 0 }))}>
              Revisar test inicial
            </button>
          </div>
        </section>
      ) : null}

      <section className={isTestFlow ? styles.testGrid : styles.grid}>
        {state.flow === "initial" ? (
        <div className={styles.testCard}>
          <div className={styles.screenList}>
            <InitialProfileControls
              initial={state.initial}
              initialStep={state.initialStep}
              updateInitial={updateInitial}
              updateInitialAnswer={updateInitialAnswer}
              toggleMode={toggleMode}
              onBack={() => setState((current) => ({ ...current, initialStep: Math.max(0, current.initialStep - 1) }))}
              onNext={() =>
                setState((current) => {
                  const nextStep = current.initialStep + 1;
                  if (nextStep >= initialStepCount) {
                    return { ...current, flow: "result", initialStep: initialStepCount - 1 };
                  }
                  return { ...current, initialStep: nextStep };
                })
              }
            />
          </div>
        </div>
        ) : null}

        {state.flow === "advanced" ? (
        <div className={styles.testCard}>
          <div className={styles.screenList}>
            <AdvancedProfileControls
              question={advancedQuestion}
              value={advancedQuestion ? state.advancedAnswers[advancedQuestion.id] ?? null : null}
              advancedStep={state.advancedStep}
              advancedStepCount={advancedStepCount}
              onAnswer={(value) => {
                if (advancedQuestion) {
                  updateAdvancedAnswer(advancedQuestion.id, value);
                }
              }}
              onBack={() => setState((current) => ({ ...current, advancedStep: Math.max(0, current.advancedStep - 1) }))}
              onNext={() =>
                setState((current) => {
                  const nextStep = current.advancedStep + 1;
                  if (nextStep >= applicableAdvancedQuestions.length) {
                    return { ...current, flow: "result", advancedStep: Math.max(0, applicableAdvancedQuestions.length - 1) };
                  }
                  return { ...current, advancedStep: nextStep };
                })
              }
            />
          </div>
        </div>
        ) : null}
      </section>
    </main>
  );
}

function InitialProfileControls({
  initial,
  initialStep,
  updateInitial,
  updateInitialAnswer,
  toggleMode,
  onBack,
  onNext,
}: {
  initial: InitialRatingInput;
  initialStep: number;
  updateInitial: (patch: Partial<InitialRatingInput>) => void;
  updateInitialAnswer: (id: InitialTechnicalQuestionId, value: AnswerValue) => void;
  toggleMode: (mode: FootballMode) => void;
  onBack: () => void;
  onNext: () => void;
}) {
  const activeModes = selectedModes(initial.modeShares);
  const stepReady = initialStepIsComplete(initial, initialStep);
  const technicalGroup = initialQuestionGroups[initialStep - 5];

  return (
    <div className={styles.screen}>
      <div className={styles.stepHeader}>
        <span>
          Paso {initialStep + 1}/{initialStepCount}
        </span>
        <progress max={initialStepCount} value={initialStep + 1} />
      </div>

      {initialStep === 0 ? (
        <>
          <h3>¿A qué juegas normalmente?</h3>
          <p className={styles.multiSelectHint}>Puedes seleccionar varias opciones.</p>
          <div className={styles.choiceGrid}>
            {modeOptions.map((option) => (
              <button
                key={option.mode}
                className={activeModes.includes(option.mode) ? styles.selectedChip : ""}
                type="button"
                aria-pressed={activeModes.includes(option.mode)}
                onClick={() => toggleMode(option.mode)}
              >
                <span className={styles.radioDot} aria-hidden="true" />
                <span>{option.label}</span>
              </button>
            ))}
          </div>
        </>
      ) : null}

      {initialStep === 1 ? (
        <>
          <h3>Posición en el campo</h3>
          <div className={styles.choiceGrid}>
            {Object.entries(POSITION_LABELS).map(([position, label]) => (
              <button
                key={position}
                className={initial.primaryPosition === position ? styles.selectedChip : ""}
                type="button"
                onClick={() => updateInitial({ primaryPosition: position as PlayerPosition, secondaryPositions: [] })}
              >
                {label}
              </button>
            ))}
          </div>
        </>
      ) : null}

      {initialStep === 2 ? (
        <>
          <h3>¿Cuál es o ha sido tu nivel más alto?</h3>
          <div className={styles.choiceGrid}>
            {experienceOptions.map((option) => (
              <button
                key={option.id}
                className={initial.experienceLevel === option.id ? styles.selectedChip : ""}
                type="button"
                onClick={() => updateInitial({ experienceLevel: option.id })}
              >
              {option.label}
            </button>
          ))}
        </div>
        </>
      ) : null}

      {initialStep === 3 ? (
        <>
          <h3>¿Cuándo jugabas a ese nivel?</h3>
          <div className={styles.chipGrid}>
            {yearsSinceLevelOptions.map((option) => (
              <button
                key={option.value}
                className={initial.yearsSinceLevel === option.value ? styles.selectedChip : ""}
                type="button"
                onClick={() => updateInitial({ yearsSinceLevel: option.value })}
              >
                {option.label}
              </button>
            ))}
          </div>
        </>
      ) : null}

      {initialStep === 4 ? (
        <>
          <h3>¿Con qué frecuencia juegas o entrenas?</h3>
          <div className={styles.choiceGrid}>
            {Object.entries(FREQUENCIES).map(([id, frequency]) => (
              <button
                key={id}
                className={initial.frequency === id ? styles.selectedChip : ""}
                type="button"
                onClick={() => updateInitial({ frequency: id as FrequencyId })}
              >
                {frequency.label}
              </button>
            ))}
          </div>
        </>
      ) : null}

      {technicalGroup ? (
        <>
          <div className={styles.questionStack}>
            {technicalGroup.questionIds.map((questionId) => {
              const question = INITIAL_TECHNICAL_QUESTIONS.find((item) => item.id === questionId);
              if (!question) {
                return null;
              }
              return (
                <QuestionControl
                  key={question.id}
                  id={question.label}
                  prompt={question.prompt}
                  value={initial.answers[question.id]}
                  onChange={(value) => updateInitialAnswer(question.id, value)}
                  options={initialAnswerOptions[question.id]}
                  allowUnknown={false}
                />
              );
            })}
          </div>
        </>
      ) : null}

      <div className={styles.stepActions}>
        <button className={styles.ghostButton} type="button" onClick={onBack} disabled={initialStep === 0}>
          Atrás
        </button>
        <button type="button" onClick={onNext} disabled={!stepReady}>
          {initialStep === initialStepCount - 1 ? "Ver mi ficha" : "Continuar"}
        </button>
      </div>
    </div>
  );
}

function AdvancedProfileControls({
  question,
  value,
  advancedStep,
  advancedStepCount,
  onAnswer,
  onBack,
  onNext,
}: {
  question: AdvancedQuestion | undefined;
  value: AnswerValue;
  advancedStep: number;
  advancedStepCount: number;
  onAnswer: (value: AnswerValue) => void;
  onBack: () => void;
  onNext: () => void;
}) {
  const stepReady = value !== null;

  return (
    <div className={styles.screen}>
      <div className={styles.stepHeader}>
        <span>
          Paso {advancedStep + 1}/{advancedStepCount}
        </span>
        <progress max={advancedStepCount} value={advancedStep + 1} />
      </div>

      {question ? (
        <QuestionControl
          id={question.id}
          prompt={question.prompt}
          value={value}
          onChange={onAnswer}
          options={advancedAnswerOptions(question)}
          allowUnknown={false}
        />
      ) : (
        <p className={styles.emptyState}>No hay tests avanzados disponibles para esta ficha.</p>
      )}

      <div className={styles.stepActions}>
        <button className={styles.ghostButton} type="button" onClick={onBack} disabled={advancedStep === 0}>
          Atrás
        </button>
        <button type="button" onClick={onNext} disabled={!stepReady || !question}>
          {advancedStep === advancedStepCount - 1 ? "Ver ficha mejorada" : "Continuar"}
        </button>
      </div>
    </div>
  );
}

function advancedAnswerOptions(question: AdvancedQuestion): Array<{ value: Exclude<AnswerValue, null>; label: string }> {
  if (question.id.startsWith("RIT") || question.targets.pace && (!question.targets.physical || question.targets.pace >= question.targets.physical)) {
    return [
      { value: 1, label: "Me superan casi siempre" },
      { value: 2, label: "Me cuesta ganar ventaja" },
      { value: 3, label: "Normal en mis partidos" },
      { value: 4, label: "Suelo ganar ventaja" },
      { value: 5, label: "Marco diferencias por velocidad" },
    ];
  }
  if (question.id.startsWith("FIS") || question.targets.physical && (!question.targets.pace || question.targets.physical > question.targets.pace)) {
    return [
      { value: 1, label: "Me cuesta aguantar" },
      { value: 2, label: "Bajo pronto el ritmo" },
      { value: 3, label: "Normal en mis partidos" },
      { value: 4, label: "Aguanto bien" },
      { value: 5, label: "Destaco físicamente" },
    ];
  }
  if (question.module === "shooting" || question.targets.shooting) {
    return [
      { value: 1, label: "Casi no genero peligro" },
      { value: 2, label: "Solo en ocasiones claras" },
      { value: 3, label: "Normal en mis partidos" },
      { value: 4, label: "Suelo generar peligro" },
      { value: 5, label: "Marco diferencias arriba" },
    ];
  }
  if (question.module === "defending" || question.targets.defending && !question.targets.passing) {
    return [
      { value: 1, label: "Me superan fácil" },
      { value: 2, label: "Me cuesta sostenerlo" },
      { value: 3, label: "Normal en mis partidos" },
      { value: 4, label: "Lo hago bastante bien" },
      { value: 5, label: "Soy muy fiable atrás" },
    ];
  }
  if (question.module === "passing" || question.targets.passing && !question.targets.dribbling) {
    return [
      { value: 1, label: "Fallo demasiado" },
      { value: 2, label: "Solo si es fácil" },
      { value: 3, label: "Normal en mis partidos" },
      { value: 4, label: "Lo hago con seguridad" },
      { value: 5, label: "Creo ventaja con eso" },
    ];
  }
  if (question.module === "intelligence") {
    return [
      { value: 1, label: "Me cuesta leerlo" },
      { value: 2, label: "Lo veo tarde" },
      { value: 3, label: "Normal en mis partidos" },
      { value: 4, label: "Lo leo bastante bien" },
      { value: 5, label: "Leo el juego muy rápido" },
    ];
  }
  return [
    { value: 1, label: "Me cuesta mucho" },
    { value: 2, label: "Solo a veces" },
    { value: 3, label: "Normal en mis partidos" },
    { value: 4, label: "Lo hago bien" },
    { value: 5, label: "Destaco en esto" },
  ];
}

function QuestionControl({
  id,
  prompt,
  value,
  onChange,
  options,
  allowUnknown = true,
}: {
  id: string;
  prompt: string;
  value: AnswerValue;
  onChange: (value: AnswerValue) => void;
  options?: Array<{ value: AnswerValue; label: string }>;
  allowUnknown?: boolean;
}) {
  const visibleOptions = options ?? (allowUnknown ? RESPONSE_OPTIONS : RESPONSE_OPTIONS.filter((option) => option.value !== null));
  return (
    <fieldset className={styles.question}>
      <legend>
        <small>{id}</small>
        <span>{prompt}</span>
      </legend>
      <div className={styles.answerRow}>
        {visibleOptions.map((option) => (
          <button
            key={option.label}
            className={value === option.value ? styles.selectedAnswer : ""}
            type="button"
            title={option.label}
            onClick={() => onChange(option.value)}
          >
            <span className={styles.radioDot} aria-hidden="true" />
            <span>{option.label}</span>
          </button>
        ))}
      </div>
    </fieldset>
  );
}

function PlayerCard({
  overall,
  currentOverall,
  position,
  ratings,
  ready,
}: {
  overall: number;
  currentOverall: number;
  position: PlayerPosition;
  ratings: AttributeRatings;
  ready: boolean;
}) {
  return (
    <article className={styles.playerCard}>
      <div className={styles.cardTop}>
        <span>{overall}</span>
        <b>{POSITION_SHORT_LABELS[position]}</b>
      </div>
      <div className={styles.cardSilhouette}>IQ</div>
      <strong>{POSITION_LABELS[position]}</strong>
      <div className={styles.cardAttrs}>
        {ATTRIBUTE_KEYS.map((attribute) => (
          <span key={attribute}>
            <b>{roundRating(ratings[attribute])}</b> {ATTRIBUTE_LABELS[attribute]}
          </span>
        ))}
      </div>
      <div className={styles.cardFooter}>
        <span>{ready ? `Actual ${currentOverall}` : "Test pendiente"}</span>
        <span>Ficha inicial</span>
      </div>
    </article>
  );
}

function Metric({ label, value }: { label: string; value: string | number }) {
  return (
    <div className={styles.metric}>
      <span>{label}</span>
      <strong>{value}</strong>
    </div>
  );
}

function PanelTitle({ kicker, title, aside }: { kicker: string; title: string; aside: string }) {
  return (
    <div className={styles.panelTitle}>
      <div>
        <small>{kicker}</small>
        <h2>{title}</h2>
      </div>
      <b>{aside}</b>
    </div>
  );
}
