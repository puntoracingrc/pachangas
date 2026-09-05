import {
  INITIAL_TECHNICAL_QUESTIONS,
  RESPONSE_OPTIONS,
  type AdvancedQuestion,
  type AnswerValue,
  type FootballMode,
  type InitialRatingInput,
  type InitialTechnicalQuestionId,
} from "./laboratorio-ficha-jugador/_engine/player-rating-engine";

export const ASSESSMENT_MODE_OPTIONS: Array<{ label: string; mode: FootballMode }> = [
  { mode: "futsal_5", label: "Fútbol sala" },
  { mode: "football_7", label: "Fútbol 7" },
  { mode: "football_11", label: "Fútbol 11" },
];

export const ASSESSMENT_EXPERIENCE_OPTIONS: Array<{ id: InitialRatingInput["experienceLevel"]; label: string }> = [
  { id: "barely_played", label: "Estoy empezando" },
  { id: "occasional_pachangas", label: "Pachangas ocasionales" },
  { id: "regular_pachangas", label: "Pachangas habituales" },
  { id: "social_league", label: "Liga social o amateur" },
  { id: "federated_club", label: "Club federado" },
  { id: "national_semipro", label: "Semipro o superior" },
];

export const ASSESSMENT_YEARS_SINCE_LEVEL_OPTIONS = [
  { value: 0, label: "Juego ahora" },
  { value: 2, label: "Hace 1-2 años" },
  { value: 5, label: "Hace 3-5 años" },
  { value: 10, label: "Hace 6-10 años" },
  { value: 15, label: "Hace más de 10 años" },
];

export const ASSESSMENT_INITIAL_ANSWER_OPTIONS: Record<InitialTechnicalQuestionId, Array<{ label: string; value: Exclude<AnswerValue, null> }>> = {
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

export const ASSESSMENT_INITIAL_QUESTION_GROUPS: Array<{ questionIds: InitialTechnicalQuestionId[]; subtitle: string; title: string }> = [
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

export const ASSESSMENT_INITIAL_STEP_COUNT = 5 + ASSESSMENT_INITIAL_QUESTION_GROUPS.length;

export function assessmentSelectedModes(modeShares: InitialRatingInput["modeShares"]) {
  return modeShares.filter((share) => share.percentage > 0).map((share) => share.mode);
}

export function assessmentSharesFromSelectedModes(modes: FootballMode[]) {
  if (modes.length === 0) {
    return ASSESSMENT_MODE_OPTIONS.map(({ mode }) => ({ mode, percentage: 0 }));
  }
  const base = Math.floor(100 / modes.length);
  let remainder = 100 - base * modes.length;
  return ASSESSMENT_MODE_OPTIONS.map(({ mode }) => {
    const active = modes.includes(mode);
    const extra = active && remainder > 0 ? 1 : 0;
    if (extra) remainder -= 1;
    return { mode, percentage: active ? base + extra : 0 };
  });
}

export function assessmentInitialIsComplete(initial: InitialRatingInput) {
  const allTechnicalAnswered = INITIAL_TECHNICAL_QUESTIONS.every((question) => initial.answers[question.id] !== null);
  const modeTotal = initial.modeShares.reduce((total, share) => total + share.percentage, 0);
  return allTechnicalAnswered && Math.round(modeTotal * 100) / 100 === 100;
}

export function assessmentInitialStepIsComplete(initial: InitialRatingInput, step: number) {
  if (step === -1) return true;
  if (step === 0) return Math.round(initial.modeShares.reduce((total, share) => total + share.percentage, 0) * 100) / 100 === 100;
  if (step === 1) return Boolean(initial.primaryPosition);
  if (step === 2) return Boolean(initial.experienceLevel);
  if (step === 3) return initial.yearsSinceLevel >= 0;
  if (step === 4) return Boolean(initial.frequency);
  const group = ASSESSMENT_INITIAL_QUESTION_GROUPS[step - 5];
  return group ? group.questionIds.every((questionId) => initial.answers[questionId] !== null) : false;
}

export function assessmentAdvancedAnswerOptions(question: AdvancedQuestion): Array<{ label: string; value: Exclude<AnswerValue, null> }> {
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
      { value: 5, label: "Anticipo lo que va a pasar" },
    ];
  }
  return RESPONSE_OPTIONS.filter((option): option is { label: string; score: number; value: Exclude<AnswerValue, null> } => option.value !== null);
}
