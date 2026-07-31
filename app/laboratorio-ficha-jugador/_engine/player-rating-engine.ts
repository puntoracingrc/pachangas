export const FOOTBALL_RATING_ENGINE_VERSION = "football-rating-v1";
export const INITIAL_TEST_VERSION = "initial-test-v1";
export const ADVANCED_TEST_VERSION = "advanced-test-v1";
export const CURRENT_FORM_VERSION = "current-form-v1";
export const SELF_ASSESSMENT_ATTRIBUTE_MAX = 92;
export const SELF_ASSESSMENT_RELIABILITY_MAX = 65;
export const LIFESTYLE_VALIDITY_DAYS = 30;
export const LIMITATION_REVIEW_DAYS = 90;

export type AttributeKey = "pace" | "shooting" | "passing" | "dribbling" | "defending" | "physical";
export type FootballMode = "futsal_5" | "football_7" | "football_11";
export type PlayerPosition =
  | "centre_back"
  | "full_back"
  | "defensive_midfielder"
  | "central_midfielder"
  | "attacking_midfielder"
  | "winger"
  | "striker";
export type AnswerValue = 1 | 2 | 3 | 4 | 5 | null;
export type AdvancedContext = "short" | "medium" | "large" | "universal";
export type AdvancedModuleId =
  | "technique"
  | "passing"
  | "shooting"
  | "defending"
  | "pace_physical"
  | "intelligence"
  | "mode"
  | "position";

export interface AttributeRatings {
  pace: number;
  shooting: number;
  passing: number;
  dribbling: number;
  defending: number;
  physical: number;
}

export interface ModeShare {
  mode: FootballMode;
  percentage: number;
}

export interface StoredAnswer {
  questionId: string;
  value: AnswerValue;
  answeredAt: string;
  questionnaireVersion: string;
}

export interface PlayerAnswer {
  questionId: string;
  value: AnswerValue;
}

export interface PlayerEvaluationProfile {
  age?: number;
  heightCm?: number;
  weightKg?: number;
  primaryPosition: PlayerPosition;
  secondaryPositions: PlayerPosition[];
  modeShares: ModeShare[];
  initialTestAnswers: StoredAnswer[];
  advancedTestAnswers: StoredAnswer[];
  currentFormAnswers: StoredAnswer[];
  baseRatings: AttributeRatings;
  currentRatings: AttributeRatings;
  baseOverall: number;
  currentOverall: number;
  reliability: number;
  engineVersion: string;
  calculatedAt: string;
}

export interface AdvancedQuestion {
  id: string;
  module: AdvancedModuleId;
  prompt: string;
  context: AdvancedContext;
  targets: Partial<Record<AttributeKey, number>>;
  applicableModes?: FootballMode[];
  applicablePositions?: PlayerPosition[];
}

export interface RatingExplanation {
  attribute: AttributeKey;
  previousValue: number;
  calculatedValue: number;
  finalValue: number;
  evidence: Array<{
    questionId: string;
    answerScore: number;
    baseWeight: number;
    modalityMultiplier: number;
    positionMultiplier: number;
    consistencyMultiplier: number;
    effectiveWeight: number;
  }>;
  currentFormAdjustment: number;
  injuryAdjustment: number;
  clampApplied: boolean;
}

export interface InitialRatingInput {
  age?: number;
  heightCm?: number;
  weightKg?: number;
  primaryPosition: PlayerPosition;
  secondaryPositions: PlayerPosition[];
  modeShares: ModeShare[];
  experienceLevel: ExperienceLevelId;
  yearsSinceLevel: number;
  frequency: FrequencyId;
  answers: Record<InitialTechnicalQuestionId, AnswerValue>;
  calculatedAt?: string;
}

export interface InitialRatingResult {
  profile: PlayerEvaluationProfile;
  modeConfidence: AttributeRatings;
  technicalComposites: Record<"C" | "P" | "A" | "D" | "V" | "H", number>;
  adjustedAnswers: Partial<Record<InitialTechnicalQuestionId, number>>;
  explanations: RatingExplanation[];
  experienceEffective: number;
  frequencyAdjustment: number;
  formulasApplied: string[];
}

export interface AdvancedRatingInput {
  initial: InitialRatingResult;
  answers: Record<string, AnswerValue>;
  calculatedAt?: string;
}

export interface AdvancedRatingResult {
  baseRatings: AttributeRatings;
  baseOverall: number;
  reliability: number;
  explanations: RatingExplanation[];
  moduleSummaries: ModuleSummary[];
  contradictionCount: number;
  storedAnswers: StoredAnswer[];
}

export interface ModuleSummary {
  module: AdvancedModuleId;
  label: string;
  completed: number;
  total: number;
  reliabilityBefore: number;
  reliabilityAfter: number;
  changes: Partial<Record<AttributeKey, { before: number; after: number }>>;
}

export type LimitationAction =
  | "sprinting"
  | "change_direction"
  | "striking"
  | "jumping"
  | "contacts"
  | "stamina"
  | "braking_defending";

export interface CurrentLimitationInput {
  consent: boolean;
  recovered: boolean;
  severity: 0 | 0.2 | 0.4 | 0.7 | 1;
  frequency: 0.25 | 0.5 | 0.75 | 1;
  actions: LimitationAction[];
}

export interface LifestyleInput {
  sleep: AnswerValue;
  training: AnswerValue;
  recovery: AnswerValue;
  habits: AnswerValue;
}

export interface CurrentRatingResult {
  currentRatings: AttributeRatings;
  currentOverall: number;
  lifestyleAdjustment: AttributeRatings;
  injuryPenalty: AttributeRatings;
  preparationIndex: number | null;
  usedLifestyleModule: boolean;
  explanations: RatingExplanation[];
}

export const ATTRIBUTE_KEYS: AttributeKey[] = ["pace", "shooting", "passing", "dribbling", "defending", "physical"];

export const ATTRIBUTE_LABELS: Record<AttributeKey, string> = {
  pace: "RIT",
  shooting: "TIR",
  passing: "PAS",
  dribbling: "REG",
  defending: "DEF",
  physical: "FIS",
};

export const POSITION_LABELS: Record<PlayerPosition, string> = {
  centre_back: "Defensa central",
  full_back: "Lateral",
  defensive_midfielder: "Mediocentro defensivo",
  central_midfielder: "Centrocampista",
  attacking_midfielder: "Mediapunta",
  winger: "Extremo",
  striker: "Delantero",
};

export const POSITION_SHORT_LABELS: Record<PlayerPosition, string> = {
  centre_back: "DFC",
  full_back: "LAT",
  defensive_midfielder: "MCD",
  central_midfielder: "MC",
  attacking_midfielder: "MP",
  winger: "EXT",
  striker: "DC",
};

export const MODE_LABELS: Record<FootballMode, string> = {
  futsal_5: "Fútbol sala/5",
  football_7: "Fútbol 7",
  football_11: "Fútbol 11",
};

export type ExperienceLevelId =
  | "barely_played"
  | "occasional_pachangas"
  | "regular_pachangas"
  | "social_league"
  | "amateur_club"
  | "federated_club"
  | "national_semipro"
  | "professional";

export const EXPERIENCE_LEVELS: Record<ExperienceLevelId, { label: string; experienceScore: number; experience5: number }> = {
  barely_played: { label: "Apenas he jugado", experienceScore: 25, experience5: 1 },
  occasional_pachangas: { label: "Pachangas ocasionales", experienceScore: 35, experience5: 1.5 },
  regular_pachangas: { label: "Pachangas habituales", experienceScore: 45, experience5: 2 },
  social_league: { label: "Liga social organizada", experienceScore: 55, experience5: 2.75 },
  amateur_club: { label: "Club amateur o liga municipal", experienceScore: 65, experience5: 3.5 },
  federated_club: { label: "Club federado", experienceScore: 75, experience5: 4.2 },
  national_semipro: { label: "Categoría nacional o semiprofesional", experienceScore: 85, experience5: 4.7 },
  professional: { label: "Profesional", experienceScore: 92, experience5: 5 },
};

export type FrequencyId = "less_monthly" | "monthly_twice" | "weekly" | "two_three_weekly" | "four_plus_weekly";

export const FREQUENCIES: Record<FrequencyId, { label: string; frequency5: number; provisionalAdjustment: number }> = {
  less_monthly: { label: "Menos de una vez al mes", frequency5: 1, provisionalAdjustment: -6 },
  monthly_twice: { label: "Una o dos veces al mes", frequency5: 2, provisionalAdjustment: -3 },
  weekly: { label: "Una vez por semana", frequency5: 3, provisionalAdjustment: 0 },
  two_three_weekly: { label: "Dos o tres veces por semana", frequency5: 4, provisionalAdjustment: 2 },
  four_plus_weekly: { label: "Cuatro o más veces por semana", frequency5: 5, provisionalAdjustment: 3 },
};

export type InitialTechnicalQuestionId =
  | "controlUnderPressure"
  | "ballCarrying"
  | "passingExecution"
  | "decisionMaking"
  | "finishing"
  | "attackingMovement"
  | "defensivePositioning"
  | "defensiveDuels"
  | "paceComparison"
  | "physicalIntensity";

export const INITIAL_TECHNICAL_QUESTIONS: Array<{ id: InitialTechnicalQuestionId; label: string; prompt: string }> = [
  { id: "controlUnderPressure", label: "INIT-CONTROL", prompt: "Con rival cerca, ¿controlas sin perderla?" },
  { id: "ballCarrying", label: "INIT-DRIBBLE", prompt: "¿Conduces o giras sin perder el balón?" },
  { id: "passingExecution", label: "INIT-PASS", prompt: "¿Das pases útiles con presión?" },
  { id: "decisionMaking", label: "INIT-DECISION", prompt: "Con poco tiempo, ¿eliges bien qué hacer?" },
  { id: "finishing", label: "INIT-FINISH", prompt: "¿Generas peligro cuando tienes ocasión?" },
  { id: "attackingMovement", label: "INIT-OFFBALL", prompt: "¿Te mueves bien para recibir?" },
  { id: "defensivePositioning", label: "INIT-DEFENCE", prompt: "¿Mantienes posición y recuperas balón?" },
  { id: "defensiveDuels", label: "INIT-DUELS", prompt: "¿Frenas al rival en los duelos?" },
  { id: "paceComparison", label: "INIT-PACE", prompt: "¿Eres rápido comparado con tus rivales?" },
  { id: "physicalIntensity", label: "INIT-PHYSICAL", prompt: "¿Mantienes la intensidad todo el partido?" },
];

export const RESPONSE_OPTIONS: Array<{ value: AnswerValue; label: string; score: number | null }> = [
  { value: 1, label: "Muy bajo", score: 25 },
  { value: 2, label: "Algo bajo", score: 40 },
  { value: 3, label: "Normal", score: 55 },
  { value: 4, label: "Bueno", score: 70 },
  { value: 5, label: "Muy bueno", score: 85 },
  { value: null, label: "No lo sé", score: null },
];

export const MODE_CONFIDENCE: Record<FootballMode, AttributeRatings> = {
  futsal_5: { pace: 0.85, shooting: 0.9, passing: 0.95, dribbling: 0.98, defending: 0.88, physical: 0.75 },
  football_7: { pace: 0.93, shooting: 0.91, passing: 0.92, dribbling: 0.93, defending: 0.91, physical: 0.9 },
  football_11: { pace: 0.94, shooting: 0.92, passing: 0.94, dribbling: 0.88, defending: 0.98, physical: 0.98 },
};

export const CONTEXT_MULTIPLIERS: Record<AdvancedContext, Record<FootballMode, number>> = {
  short: { futsal_5: 1.15, football_7: 1.05, football_11: 0.9 },
  medium: { futsal_5: 0.95, football_7: 1.15, football_11: 1 },
  large: { futsal_5: 0.8, football_7: 0.95, football_11: 1.15 },
  universal: { futsal_5: 1, football_7: 1, football_11: 1 },
};

export const OVERALL_WEIGHTS: Record<PlayerPosition, AttributeRatings> = {
  centre_back: { pace: 0.15, shooting: 0.03, passing: 0.14, dribbling: 0.08, defending: 0.35, physical: 0.25 },
  full_back: { pace: 0.22, shooting: 0.05, passing: 0.16, dribbling: 0.14, defending: 0.25, physical: 0.18 },
  defensive_midfielder: { pace: 0.12, shooting: 0.05, passing: 0.24, dribbling: 0.15, defending: 0.25, physical: 0.19 },
  central_midfielder: { pace: 0.12, shooting: 0.1, passing: 0.28, dribbling: 0.22, defending: 0.13, physical: 0.15 },
  attacking_midfielder: { pace: 0.15, shooting: 0.18, passing: 0.23, dribbling: 0.26, defending: 0.05, physical: 0.13 },
  winger: { pace: 0.25, shooting: 0.18, passing: 0.16, dribbling: 0.28, defending: 0.03, physical: 0.1 },
  striker: { pace: 0.2, shooting: 0.32, passing: 0.1, dribbling: 0.18, defending: 0.03, physical: 0.17 },
};

export const POSITION_ATTRIBUTE_ROLE: Record<PlayerPosition, { primary: AttributeKey[]; secondary: AttributeKey[] }> = {
  centre_back: { primary: ["defending", "physical"], secondary: ["passing"] },
  full_back: { primary: ["pace", "defending"], secondary: ["passing", "physical"] },
  defensive_midfielder: { primary: ["defending", "passing"], secondary: ["physical", "dribbling"] },
  central_midfielder: { primary: ["passing", "dribbling"], secondary: ["physical", "defending"] },
  attacking_midfielder: { primary: ["passing", "dribbling"], secondary: ["shooting"] },
  winger: { primary: ["pace", "dribbling"], secondary: ["shooting", "passing"] },
  striker: { primary: ["shooting"], secondary: ["pace", "physical", "dribbling"] },
};

const MODULE_LABELS: Record<AdvancedModuleId, string> = {
  technique: "Técnica y control",
  passing: "Pase y creación",
  shooting: "Tiro y ataque",
  defending: "Defensa",
  pace_physical: "Ritmo y físico",
  intelligence: "Inteligencia de juego",
  mode: "Modalidad",
  position: "Posición",
};

export const ADVANCED_QUESTIONS: AdvancedQuestion[] = [
  { id: "TEC-01", module: "technique", prompt: "Cuando recibes con un rival cerca, ¿con qué frecuencia controlas sin perder el balón?", context: "short", targets: { dribbling: 1, passing: 0.25 } },
  { id: "TEC-02", module: "technique", prompt: "¿Con qué frecuencia orientas el primer control hacia tu siguiente acción?", context: "universal", targets: { dribbling: 0.85, passing: 0.35 } },
  { id: "TEC-03", module: "technique", prompt: "Cuando recibes de espaldas, ¿con qué frecuencia proteges el balón y consigues girarte o pasar?", context: "short", targets: { dribbling: 0.7, physical: 0.3, passing: 0.15 } },
  { id: "TEC-04", module: "technique", prompt: "¿Con qué frecuencia superas o desequilibras a un rival mediante regate o cambio de dirección?", context: "short", targets: { dribbling: 1, pace: 0.2 } },
  { id: "TEC-05", module: "technique", prompt: "¿Con qué frecuencia puedes conducir a velocidad sin perder demasiado control?", context: "medium", targets: { dribbling: 0.75, pace: 0.45 } },
  { id: "TEC-06", module: "technique", prompt: "¿Con qué seguridad utilizas tu pierna menos hábil para controlar o conducir?", context: "universal", targets: { dribbling: 0.6, passing: 0.25 } },
  { id: "PAS-01", module: "passing", prompt: "¿Con qué frecuencia completas pases cortos cuando te presionan inmediatamente?", context: "short", targets: { passing: 1, dribbling: 0.15 } },
  { id: "PAS-02", module: "passing", prompt: "¿Con qué frecuencia puedes jugar de primeras sin perder precisión?", context: "short", targets: { passing: 0.85, dribbling: 0.2 } },
  { id: "PAS-03", module: "passing", prompt: "¿Con qué frecuencia encuentras compañeros entre líneas o en posiciones ventajosas?", context: "medium", targets: { passing: 1 } },
  { id: "PAS-04", module: "passing", prompt: "¿Con qué frecuencia completas pases largos o cambios de orientación?", context: "large", targets: { passing: 0.9 } },
  { id: "PAS-05", module: "passing", prompt: "¿Con qué frecuencia realizas centros o pases atrás que encuentran a un compañero?", context: "medium", targets: { passing: 0.75, shooting: 0.15 } },
  { id: "PAS-06", module: "passing", prompt: "¿Con qué frecuencia decides antes de que el rival cierre el espacio?", context: "universal", targets: { passing: 0.85, defending: 0.15, dribbling: 0.1 } },
  { id: "TIR-01", module: "shooting", prompt: "¿Con qué frecuencia conviertes ocasiones claras cerca del área?", context: "short", targets: { shooting: 1 } },
  { id: "TIR-02", module: "shooting", prompt: "¿Con qué frecuencia realizas disparos lejanos bien dirigidos que generan peligro?", context: "large", targets: { shooting: 0.85 } },
  { id: "TIR-03", module: "shooting", prompt: "¿Con qué frecuencia puedes rematar de primeras o con poco tiempo?", context: "short", targets: { shooting: 0.9, dribbling: 0.15 } },
  { id: "TIR-04", module: "shooting", prompt: "¿Con qué frecuencia finalizas correctamente con tu pierna menos hábil?", context: "universal", targets: { shooting: 0.65 } },
  { id: "TIR-05", module: "shooting", prompt: "¿Con qué frecuencia ganas la posición y rematas balones altos?", context: "large", targets: { shooting: 0.55, physical: 0.3 } },
  { id: "TIR-06", module: "shooting", prompt: "¿Con qué frecuencia haces desmarques que te permiten recibir en una posición peligrosa?", context: "medium", targets: { shooting: 0.5, pace: 0.3, passing: 0.15 } },
  { id: "DEF-01", module: "defending", prompt: "¿Con qué frecuencia frenas a un rival en una situación de uno contra uno?", context: "universal", targets: { defending: 1, physical: 0.15 } },
  { id: "DEF-02", module: "defending", prompt: "¿Con qué frecuencia interceptas un pase antes de que el rival controle?", context: "universal", targets: { defending: 0.95, passing: 0.15 } },
  { id: "DEF-03", module: "defending", prompt: "¿Con qué frecuencia mantienes controlado a tu rival directo sin perder tu posición?", context: "medium", targets: { defending: 0.85, physical: 0.1 } },
  { id: "DEF-04", module: "defending", prompt: "¿Con qué frecuencia haces una cobertura cuando un compañero abandona su posición?", context: "medium", targets: { defending: 0.9, passing: 0.15 } },
  { id: "DEF-05", module: "defending", prompt: "Tras perder el balón, ¿con qué rapidez recuperas la posición o presionas de forma útil?", context: "short", targets: { defending: 0.75, pace: 0.25, physical: 0.15 } },
  { id: "DEF-06", module: "defending", prompt: "¿Con qué frecuencia ganas duelos aéreos defensivos o impides remates cómodos?", context: "large", targets: { defending: 0.65, physical: 0.4 } },
  { id: "RIT-01", module: "pace_physical", prompt: "En los primeros metros, ¿con qué frecuencia consigues ventaja sobre un rival?", context: "universal", targets: { pace: 1 } },
  { id: "RIT-02", module: "pace_physical", prompt: "En carreras largas, ¿cómo se compara tu velocidad con la de tus rivales?", context: "large", targets: { pace: 0.9 } },
  { id: "RIT-03", module: "pace_physical", prompt: "¿Con qué rapidez puedes frenar, girar y volver a acelerar?", context: "short", targets: { pace: 0.75, dribbling: 0.25 } },
  { id: "RIT-04", module: "pace_physical", prompt: "¿Con qué frecuencia puedes realizar varios esprints seguidos sin perder demasiado rendimiento?", context: "medium", targets: { pace: 0.55, physical: 0.55 } },
  { id: "FIS-01", module: "pace_physical", prompt: "¿Durante cuánto tiempo mantienes aproximadamente tu intensidad habitual?", context: "large", targets: { physical: 1, pace: 0.15 } },
  { id: "FIS-02", module: "pace_physical", prompt: "¿Con qué frecuencia mantienes el equilibrio o proteges el balón en los contactos?", context: "universal", targets: { physical: 0.9, defending: 0.15, dribbling: 0.1 } },
  { id: "FIS-03", module: "pace_physical", prompt: "¿Con qué frecuencia continúas una jugada después de recibir contacto?", context: "universal", targets: { physical: 0.65, dribbling: 0.25 } },
  { id: "INT-01", module: "intelligence", prompt: "Antes de recibir, ¿con qué frecuencia observas dónde están compañeros, rivales y espacios?", context: "universal", targets: { passing: 0.6, dribbling: 0.25, defending: 0.15 } },
  { id: "INT-02", module: "intelligence", prompt: "¿Con qué frecuencia ocupas una posición que ayuda al equipo aunque no recibas?", context: "universal", targets: { defending: 0.55, passing: 0.35 } },
  { id: "INT-03", module: "intelligence", prompt: "¿Con qué frecuencia identificas rápidamente si debes atacar, conservar, presionar o replegar?", context: "universal", targets: { defending: 0.4, passing: 0.4, pace: 0.15 } },
  { id: "INT-04", module: "intelligence", prompt: "¿Con qué frecuencia sabes cuándo jugar rápido y cuándo conservar el balón?", context: "universal", targets: { passing: 0.7, dribbling: 0.15 } },
  { id: "INT-05", module: "intelligence", prompt: "¿Con qué frecuencia ayudas a tus compañeros mediante avisos y organización?", context: "universal", targets: { defending: 0.4, passing: 0.3 } },
  { id: "INT-06", module: "intelligence", prompt: "¿Con qué facilidad mantienes tu rendimiento al cambiar de posición, sistema o modalidad?", context: "universal", targets: { passing: 0.25, defending: 0.25, dribbling: 0.2, physical: 0.1 } },
];

export const MODE_SPECIFIC_QUESTIONS: AdvancedQuestion[] = [
  { id: "MOD-F5-01", module: "mode", prompt: "Control y decisión con un rival muy cerca.", context: "short", applicableModes: ["futsal_5"], targets: { dribbling: 0.8, passing: 0.4 } },
  { id: "MOD-F5-02", module: "mode", prompt: "Juego de primeras en combinaciones rápidas.", context: "short", applicableModes: ["futsal_5"], targets: { passing: 0.9, dribbling: 0.2 } },
  { id: "MOD-F5-03", module: "mode", prompt: "Participación continua en ataque y defensa.", context: "short", applicableModes: ["futsal_5"], targets: { defending: 0.5, pace: 0.35, passing: 0.2 } },
  { id: "MOD-F5-04", module: "mode", prompt: "Repetición de aceleraciones cortas.", context: "short", applicableModes: ["futsal_5"], targets: { pace: 0.65, physical: 0.4 } },
  { id: "MOD-F5-05", module: "mode", prompt: "Finalización con poco espacio.", context: "short", applicableModes: ["futsal_5"], targets: { shooting: 0.8, dribbling: 0.2 } },
  { id: "MOD-F7-01", module: "mode", prompt: "Crear líneas de pase y apoyos.", context: "medium", applicableModes: ["football_7"], targets: { passing: 0.65, dribbling: 0.25 } },
  { id: "MOD-F7-02", module: "mode", prompt: "Reaccionar en las transiciones.", context: "medium", applicableModes: ["football_7"], targets: { defending: 0.45, pace: 0.35, physical: 0.2 } },
  { id: "MOD-F7-03", module: "mode", prompt: "Aprovechar espacios intermedios.", context: "medium", applicableModes: ["football_7"], targets: { passing: 0.5, dribbling: 0.4 } },
  { id: "MOD-F7-04", module: "mode", prompt: "Cubrir zonas amplias sin romper la estructura.", context: "medium", applicableModes: ["football_7"], targets: { defending: 0.45, physical: 0.4 } },
  { id: "MOD-F7-05", module: "mode", prompt: "Finalizar después de una carrera o conducción.", context: "medium", applicableModes: ["football_7"], targets: { shooting: 0.6, pace: 0.3 } },
  { id: "MOD-F11-01", module: "mode", prompt: "Mantener la posición dentro de un sistema.", context: "large", applicableModes: ["football_11"], targets: { defending: 0.6, passing: 0.25 } },
  { id: "MOD-F11-02", module: "mode", prompt: "Orientarse antes de recibir en espacios grandes.", context: "large", applicableModes: ["football_11"], targets: { passing: 0.6, dribbling: 0.25 } },
  { id: "MOD-F11-03", module: "mode", prompt: "Ejecutar pases largos.", context: "large", applicableModes: ["football_11"], targets: { passing: 0.85 } },
  { id: "MOD-F11-04", module: "mode", prompt: "Competir en duelos aéreos.", context: "large", applicableModes: ["football_11"], targets: { defending: 0.35, physical: 0.45, shooting: 0.15 } },
  { id: "MOD-F11-05", module: "mode", prompt: "Mantener el rendimiento durante partidos largos.", context: "large", applicableModes: ["football_11"], targets: { physical: 0.8, pace: 0.2 } },
];

export const POSITION_SPECIFIC_QUESTIONS: AdvancedQuestion[] = [
  { id: "POS-CB-01", module: "position", prompt: "Temporizar y elegir el momento de entrar.", context: "universal", applicablePositions: ["centre_back"], targets: { defending: 0.8, passing: 0.15 } },
  { id: "POS-CB-02", module: "position", prompt: "Defender balones aéreos.", context: "large", applicablePositions: ["centre_back"], targets: { defending: 0.65, physical: 0.4 } },
  { id: "POS-CB-03", module: "position", prompt: "Cubrir la espalda de otros defensores.", context: "large", applicablePositions: ["centre_back"], targets: { defending: 0.85, pace: 0.15 } },
  { id: "POS-CB-04", module: "position", prompt: "Iniciar jugadas desde atrás.", context: "large", applicablePositions: ["centre_back"], targets: { passing: 0.65, dribbling: 0.15 } },
  { id: "POS-CB-05", module: "position", prompt: "Ganar duelos físicos sin cometer falta.", context: "universal", applicablePositions: ["centre_back"], targets: { defending: 0.65, physical: 0.45 } },
  { id: "POS-FB-01", module: "position", prompt: "Defender en espacios abiertos.", context: "large", applicablePositions: ["full_back"], targets: { defending: 0.7, pace: 0.35 } },
  { id: "POS-FB-02", module: "position", prompt: "Recuperar la posición después de atacar.", context: "large", applicablePositions: ["full_back"], targets: { defending: 0.55, pace: 0.35, physical: 0.25 } },
  { id: "POS-FB-03", module: "position", prompt: "Elegir cuándo incorporarse.", context: "medium", applicablePositions: ["full_back"], targets: { passing: 0.4, defending: 0.3 } },
  { id: "POS-FB-04", module: "position", prompt: "Centrar o encontrar un pase atrás.", context: "medium", applicablePositions: ["full_back"], targets: { passing: 0.75, shooting: 0.15 } },
  { id: "POS-FB-05", module: "position", prompt: "Repetir carreras durante el partido.", context: "large", applicablePositions: ["full_back"], targets: { pace: 0.45, physical: 0.55 } },
  { id: "POS-DM-01", module: "position", prompt: "Recibir de espaldas bajo presión.", context: "short", applicablePositions: ["defensive_midfielder"], targets: { dribbling: 0.55, passing: 0.4, physical: 0.15 } },
  { id: "POS-DM-02", module: "position", prompt: "Cerrar líneas de pase.", context: "universal", applicablePositions: ["defensive_midfielder"], targets: { defending: 0.8, passing: 0.15 } },
  { id: "POS-DM-03", module: "position", prompt: "Cambiar la orientación del juego.", context: "large", applicablePositions: ["defensive_midfielder"], targets: { passing: 0.85 } },
  { id: "POS-DM-04", module: "position", prompt: "Proteger la zona central.", context: "large", applicablePositions: ["defensive_midfielder"], targets: { defending: 0.85, physical: 0.25 } },
  { id: "POS-DM-05", module: "position", prompt: "Controlar el ritmo.", context: "universal", applicablePositions: ["defensive_midfielder"], targets: { passing: 0.75, defending: 0.2 } },
  { id: "POS-CM-01", module: "position", prompt: "Recibir entre líneas.", context: "medium", applicablePositions: ["central_midfielder", "attacking_midfielder"], targets: { passing: 0.5, dribbling: 0.45 } },
  { id: "POS-CM-02", module: "position", prompt: "Encontrar el último pase.", context: "medium", applicablePositions: ["central_midfielder", "attacking_midfielder"], targets: { passing: 0.75, shooting: 0.15 } },
  { id: "POS-CM-03", module: "position", prompt: "Girarse bajo presión.", context: "short", applicablePositions: ["central_midfielder", "attacking_midfielder"], targets: { dribbling: 0.7, passing: 0.25 } },
  { id: "POS-CM-04", module: "position", prompt: "Llegar desde segunda línea.", context: "medium", applicablePositions: ["central_midfielder", "attacking_midfielder"], targets: { shooting: 0.45, pace: 0.2, physical: 0.15 } },
  { id: "POS-CM-05", module: "position", prompt: "Presionar después de perder el balón.", context: "short", applicablePositions: ["central_midfielder", "attacking_midfielder"], targets: { defending: 0.55, pace: 0.2, physical: 0.2 } },
  { id: "POS-W-01", module: "position", prompt: "Conseguir ventaja con la primera aceleración.", context: "short", applicablePositions: ["winger"], targets: { pace: 0.75, dribbling: 0.25 } },
  { id: "POS-W-02", module: "position", prompt: "Superar defensores en uno contra uno.", context: "short", applicablePositions: ["winger"], targets: { dribbling: 0.85, pace: 0.3 } },
  { id: "POS-W-03", module: "position", prompt: "Centrar con precisión.", context: "medium", applicablePositions: ["winger"], targets: { passing: 0.75, shooting: 0.1 } },
  { id: "POS-W-04", module: "position", prompt: "Entrar hacia dentro y finalizar.", context: "medium", applicablePositions: ["winger"], targets: { shooting: 0.55, dribbling: 0.35 } },
  { id: "POS-W-05", module: "position", prompt: "Ayudar defensivamente.", context: "large", applicablePositions: ["winger"], targets: { defending: 0.45, pace: 0.2, physical: 0.15 } },
  { id: "POS-ST-01", module: "position", prompt: "Desmarcarse a la espalda.", context: "large", applicablePositions: ["striker"], targets: { shooting: 0.45, pace: 0.35 } },
  { id: "POS-ST-02", module: "position", prompt: "Proteger el balón de espaldas.", context: "short", applicablePositions: ["striker"], targets: { physical: 0.35, dribbling: 0.45, passing: 0.15 } },
  { id: "POS-ST-03", module: "position", prompt: "Finalizar de primeras.", context: "short", applicablePositions: ["striker"], targets: { shooting: 0.85 } },
  { id: "POS-ST-04", module: "position", prompt: "Rematar balones aéreos.", context: "large", applicablePositions: ["striker"], targets: { shooting: 0.55, physical: 0.35 } },
  { id: "POS-ST-05", module: "position", prompt: "Presionar la salida rival.", context: "medium", applicablePositions: ["striker"], targets: { defending: 0.35, pace: 0.25, physical: 0.25 } },
];

export const ALL_ADVANCED_QUESTIONS = [...ADVANCED_QUESTIONS, ...MODE_SPECIFIC_QUESTIONS, ...POSITION_SPECIFIC_QUESTIONS];

export const FREQUENCY_MULTIPLIERS: AttributeRatings = {
  pace: 1,
  shooting: 0.4,
  passing: 0.3,
  dribbling: 0.4,
  defending: 0.5,
  physical: 1,
};

export const LIMITATION_IMPACT: Record<LimitationAction, AttributeRatings> = {
  sprinting: { pace: 0.8, shooting: 0, passing: 0, dribbling: 0.05, defending: 0.05, physical: 0.1 },
  change_direction: { pace: 0.35, shooting: 0, passing: 0.05, dribbling: 0.4, defending: 0.15, physical: 0.05 },
  striking: { pace: 0, shooting: 0.65, passing: 0.25, dribbling: 0.1, defending: 0, physical: 0 },
  jumping: { pace: 0.05, shooting: 0.15, passing: 0, dribbling: 0, defending: 0.35, physical: 0.45 },
  contacts: { pace: 0, shooting: 0.05, passing: 0, dribbling: 0.15, defending: 0.3, physical: 0.5 },
  stamina: { pace: 0.2, shooting: 0, passing: 0.05, dribbling: 0, defending: 0.1, physical: 0.65 },
  braking_defending: { pace: 0.2, shooting: 0, passing: 0, dribbling: 0.1, defending: 0.55, physical: 0.15 },
};

export function clamp(value: number, min: number, max: number) {
  return Math.min(max, Math.max(min, value));
}

export function roundRating(value: number) {
  return Math.round(value);
}

export function responseToScore(answer: AnswerValue): number | null {
  return answer === null ? null : 25 + 15 * (answer - 1);
}

export function validateModeShares(modeShares: ModeShare[]) {
  const sum = modeShares.reduce((total, share) => total + share.percentage, 0);
  if (Math.round(sum * 100) / 100 !== 100) {
    throw new Error(`Los porcentajes de modalidades deben sumar 100. Suma actual: ${sum}.`);
  }
}

export function calculateOverall(ratings: AttributeRatings, position: PlayerPosition) {
  const weights = OVERALL_WEIGHTS[position];
  return ATTRIBUTE_KEYS.reduce((overall, key) => overall + ratings[key] * weights[key], 0);
}

export function calculateAllPositionOveralls(ratings: AttributeRatings) {
  return Object.fromEntries(
    (Object.keys(OVERALL_WEIGHTS) as PlayerPosition[]).map((position) => [position, calculateOverall(ratings, position)]),
  ) as Record<PlayerPosition, number>;
}

export function overallWeightsAreValid() {
  return Object.values(OVERALL_WEIGHTS).every((weights) => Math.abs(ATTRIBUTE_KEYS.reduce((total, key) => total + weights[key], 0) - 1) < 0.00001);
}

export function calculateModeConfidence(modeShares: ModeShare[]): AttributeRatings {
  validateModeShares(modeShares);
  return mapAttributes((attribute) =>
    modeShares.reduce((total, share) => total + (share.percentage * MODE_CONFIDENCE[share.mode][attribute]) / 100, 0),
  );
}

export function calculateInitialRatings(input: InitialRatingInput): InitialRatingResult {
  validateModeShares(input.modeShares);
  const calculatedAt = input.calculatedAt ?? new Date().toISOString();
  const experience = EXPERIENCE_LEVELS[input.experienceLevel];
  const frequency = FREQUENCIES[input.frequency];
  const experienceEffective =
    input.yearsSinceLevel <= 0 ? experience.experienceScore : 50 + (experience.experienceScore - 50) * Math.exp(-0.12 * input.yearsSinceLevel);
  const limit5 = Math.min(5, 1.2 + 0.55 * experience.experience5 + 0.25 * frequency.frequency5);
  const adjustedAnswers: Partial<Record<InitialTechnicalQuestionId, number>> = {};

  for (const question of INITIAL_TECHNICAL_QUESTIONS) {
    const answer = input.answers[question.id];
    if (answer !== null) {
      adjustedAnswers[question.id] = answer - 0.5 * Math.max(0, answer - limit5);
    }
  }

  const score = (id: InitialTechnicalQuestionId) => {
    const adjustedAnswer = adjustedAnswers[id];
    return adjustedAnswer === undefined ? null : 25 + 15 * (adjustedAnswer - 1);
  };
  const C = weightedAverage([
    [score("controlUnderPressure"), 0.6],
    [score("ballCarrying"), 0.4],
  ]);
  const P = weightedAverage([
    [score("passingExecution"), 0.6],
    [score("decisionMaking"), 0.4],
  ]);
  const A = weightedAverage([
    [score("finishing"), 0.7],
    [score("attackingMovement"), 0.3],
  ]);
  const D = weightedAverage([
    [score("defensivePositioning"), 0.6],
    [score("defensiveDuels"), 0.4],
  ]);
  const V = score("paceComparison") ?? 50;
  const H = score("physicalIntensity") ?? 50;

  const raw: AttributeRatings = {
    pace: 0.7 * V + 0.15 * C + 0.1 * A + 0.05 * D,
    shooting: 0.75 * A + 0.1 * C + 0.1 * P + 0.05 * V,
    passing: 0.7 * P + 0.15 * C + 0.1 * D + 0.05 * A,
    dribbling: 0.7 * C + 0.15 * V + 0.1 * P + 0.05 * A,
    defending: 0.7 * D + 0.1 * H + 0.1 * P + 0.05 * V + 0.05 * C,
    physical: 0.7 * H + 0.15 * V + 0.1 * D + 0.05 * A,
  };

  const baseRatings = mapAttributes((attribute) => clamp(0.82 * raw[attribute] + 0.18 * experienceEffective, 20, 90));
  const currentRatings = applyFrequencyAdjustment(baseRatings, frequency.provisionalAdjustment);
  const modeConfidence = calculateModeConfidence(input.modeShares);
  const baseOverall = calculateOverall(baseRatings, input.primaryPosition);
  const currentOverall = calculateOverall(currentRatings, input.primaryPosition);
  const regularModeCount = input.modeShares.filter((share) => share.percentage > 0).length;
  const reliability = calculateInitialReliability(experience.experience5, frequency.frequency5, regularModeCount);
  const initialTestAnswers = storeAnswers(
    Object.entries(input.answers).map(([questionId, value]) => ({ questionId, value })),
    INITIAL_TEST_VERSION,
    calculatedAt,
  );
  const profile: PlayerEvaluationProfile = {
    age: input.age,
    heightCm: input.heightCm,
    weightKg: input.weightKg,
    primaryPosition: input.primaryPosition,
    secondaryPositions: input.secondaryPositions,
    modeShares: input.modeShares,
    initialTestAnswers,
    advancedTestAnswers: [],
    currentFormAnswers: [],
    baseRatings,
    currentRatings,
    baseOverall,
    currentOverall,
    reliability,
    engineVersion: FOOTBALL_RATING_ENGINE_VERSION,
    calculatedAt,
  };

  return {
    profile,
    modeConfidence,
    technicalComposites: { C, P, A, D, V, H },
    adjustedAnswers,
    explanations: ATTRIBUTE_KEYS.map((attribute) => ({
      attribute,
      previousValue: 50,
      calculatedValue: raw[attribute],
      finalValue: baseRatings[attribute],
      evidence: [],
      currentFormAdjustment: currentRatings[attribute] - baseRatings[attribute],
      injuryAdjustment: 0,
      clampApplied: baseRatings[attribute] !== 0.82 * raw[attribute] + 0.18 * experienceEffective,
    })),
    experienceEffective,
    frequencyAdjustment: frequency.provisionalAdjustment,
    formulasApplied: [FOOTBALL_RATING_ENGINE_VERSION, INITIAL_TEST_VERSION],
  };
}

export function calculateInitialReliability(experience5: number, frequency5: number, regularModeCount: number) {
  const experienceNormalized = (experience5 - 1) / 4;
  const frequencyNormalized = (frequency5 - 1) / 4;
  return clamp(20 + 15 * experienceNormalized + 10 * frequencyNormalized + 5 * Math.min(2, regularModeCount - 1), 20, 55);
}

export function calculateApplicableAdvancedQuestions(input: InitialRatingResult) {
  const regularModes = input.profile.modeShares.filter((share) => share.percentage > 0).map((share) => share.mode);
  return ALL_ADVANCED_QUESTIONS.filter((question) => {
    const modeApplies = !question.applicableModes || question.applicableModes.some((mode) => regularModes.includes(mode));
    const positionApplies =
      !question.applicablePositions ||
      question.applicablePositions.includes(input.profile.primaryPosition) ||
      input.profile.secondaryPositions.some((position) => question.applicablePositions?.includes(position));
    return modeApplies && positionApplies;
  });
}

export function calculateAdvancedRatings(input: AdvancedRatingInput): AdvancedRatingResult {
  const questions = calculateApplicableAdvancedQuestions(input.initial);
  const calculatedAt = input.calculatedAt ?? new Date().toISOString();
  const answersByModule = groupQuestionsByModule(questions);
  const moduleConsistency = calculateModuleConsistency(input.answers);
  const contradictionCount = Object.values(moduleConsistency).reduce((total, item) => total + item.contradictions, 0);
  const initialBase = input.initial.profile.baseRatings;
  const explanations: RatingExplanation[] = [];
  const result = mapAttributes((attribute) => {
    const initialEvidenceWeight = 4 * input.initial.modeConfidence[attribute];
    let weightedScore = initialEvidenceWeight * initialBase[attribute];
    let totalWeight = initialEvidenceWeight;
    const evidence: RatingExplanation["evidence"] = [];

    for (const question of questions) {
      const answer = input.answers[question.id];
      const answerScore = responseToScore(answer ?? null);
      const baseWeight = question.targets[attribute] ?? 0;
      if (answerScore === null || baseWeight === 0) {
        continue;
      }
      const modalityMultiplier = calculateQuestionModeMultiplier(question, input.initial.profile.modeShares);
      const positionMultiplier = calculatePositionMultiplier(question, attribute, input.initial.profile.primaryPosition);
      const consistencyMultiplier = moduleConsistency[question.module]?.factor ?? 1;
      const effectiveWeight = baseWeight * modalityMultiplier * positionMultiplier * consistencyMultiplier;
      weightedScore += effectiveWeight * answerScore;
      totalWeight += effectiveWeight;
      evidence.push({ questionId: question.id, answerScore, baseWeight, modalityMultiplier, positionMultiplier, consistencyMultiplier, effectiveWeight });
    }

    const calculatedValue = weightedScore / totalWeight;
    const effectiveEvidence = evidence.reduce((total, item) => total + item.effectiveWeight, 0);
    const coverage = Math.min(1, effectiveEvidence / 8);
    const maxDelta = 5 + 13 * coverage;
    const finalValue = clamp(calculatedValue, initialBase[attribute] - maxDelta, Math.min(SELF_ASSESSMENT_ATTRIBUTE_MAX, initialBase[attribute] + maxDelta));
    explanations.push({
      attribute,
      previousValue: initialBase[attribute],
      calculatedValue,
      finalValue,
      evidence,
      currentFormAdjustment: 0,
      injuryAdjustment: 0,
      clampApplied: finalValue !== calculatedValue,
    });
    return finalValue;
  });

  const coreQuestions = questions.filter((question) => question.module !== "mode" && question.module !== "position");
  const completedCore = coreQuestions.filter((question) => responseToScore(input.answers[question.id] ?? null) !== null).length;
  const modeQuestions = questions.filter((question) => question.module === "mode");
  const positionQuestions = questions.filter((question) => question.module === "position" && question.applicablePositions?.includes(input.initial.profile.primaryPosition));
  const modeCompleted = modeQuestions.length > 0 && modeQuestions.every((question) => responseToScore(input.answers[question.id] ?? null) !== null) ? 1 : 0;
  const positionCompleted = positionQuestions.length > 0 && positionQuestions.every((question) => responseToScore(input.answers[question.id] ?? null) !== null) ? 1 : 0;
  const coreCompletion = coreQuestions.length === 0 ? 0 : completedCore / coreQuestions.length;
  const reliability = clamp(
    input.initial.profile.reliability + 18 * coreCompletion + 4 * modeCompleted + 4 * positionCompleted - 3 * contradictionCount,
    input.initial.profile.reliability,
    SELF_ASSESSMENT_RELIABILITY_MAX,
  );
  const baseOverall = calculateOverall(result, input.initial.profile.primaryPosition);
  const moduleSummaries = Object.entries(answersByModule).map(([module, moduleQuestions]) => {
    const completed = moduleQuestions.filter((question) => responseToScore(input.answers[question.id] ?? null) !== null).length;
    const changes: ModuleSummary["changes"] = {};
    for (const attribute of ATTRIBUTE_KEYS) {
      const touched = moduleQuestions.some((question) => question.targets[attribute]);
      if (touched && Math.abs(result[attribute] - initialBase[attribute]) >= 0.05) {
        changes[attribute] = { before: initialBase[attribute], after: result[attribute] };
      }
    }
    return {
      module: module as AdvancedModuleId,
      label: MODULE_LABELS[module as AdvancedModuleId],
      completed,
      total: moduleQuestions.length,
      reliabilityBefore: input.initial.profile.reliability,
      reliabilityAfter: reliability,
      changes,
    };
  });

  return {
    baseRatings: result,
    baseOverall,
    reliability,
    explanations,
    moduleSummaries,
    contradictionCount,
    storedAnswers: storeAnswers(
      Object.entries(input.answers).map(([questionId, value]) => ({ questionId, value })),
      ADVANCED_TEST_VERSION,
      calculatedAt,
    ),
  };
}

export function calculateQuestionModeMultiplier(question: AdvancedQuestion, modeShares: ModeShare[]) {
  return modeShares.reduce((total, share) => total + (share.percentage * CONTEXT_MULTIPLIERS[question.context][share.mode]) / 100, 0);
}

export function calculatePositionMultiplier(question: AdvancedQuestion, attribute: AttributeKey, primaryPosition: PlayerPosition) {
  if (question.applicablePositions?.includes(primaryPosition)) {
    return 1.15;
  }
  const role = POSITION_ATTRIBUTE_ROLE[primaryPosition];
  if (role.primary.includes(attribute)) {
    return 1.1;
  }
  if (role.secondary.includes(attribute)) {
    return 1.05;
  }
  return 1;
}

export function calculateLifestyleAdjustment(input: LifestyleInput): { adjustment: AttributeRatings; preparationIndex: number | null } {
  const values = [input.sleep, input.training, input.recovery, input.habits];
  if (values.some((value) => value === null)) {
    return { adjustment: zeroRatings(), preparationIndex: null };
  }
  const score = (value: AnswerValue) => (value === null ? 0 : value * 20);
  const preparationIndex = 0.3 * score(input.sleep) + 0.3 * score(input.training) + 0.25 * score(input.recovery) + 0.15 * score(input.habits);
  const positiveMax: AttributeRatings = { pace: 3, shooting: 1, passing: 1, dribbling: 1, defending: 1, physical: 3 };
  const negativeMax: AttributeRatings = { pace: 6, shooting: 3, passing: 3, dribbling: 3, defending: 3, physical: 6 };
  if (preparationIndex >= 50) {
    const ratio = (preparationIndex - 50) / 50;
    return { adjustment: mapAttributes((attribute) => ratio * positiveMax[attribute]), preparationIndex };
  }
  const ratio = (preparationIndex - 50) / 50;
  return { adjustment: mapAttributes((attribute) => ratio * negativeMax[attribute]), preparationIndex };
}

export function calculateInjuryPenalty(input: CurrentLimitationInput): AttributeRatings {
  if (!input.consent || input.recovered || input.severity === 0 || input.actions.length === 0) {
    return zeroRatings();
  }
  return mapAttributes((attribute) => {
    const combinedImpact = 1 - input.actions.reduce((product, action) => {
      const individualImpact = input.severity * input.frequency * LIMITATION_IMPACT[action][attribute];
      return product * (1 - individualImpact);
    }, 1);
    return Math.min(12, 12 * combinedImpact);
  });
}

export function calculateCurrentRatings(params: {
  baseRatings: AttributeRatings;
  primaryPosition: PlayerPosition;
  frequencyAdjustment: number;
  lifestyle: LifestyleInput;
  limitation: CurrentLimitationInput;
}): CurrentRatingResult {
  const lifestyle = calculateLifestyleAdjustment(params.lifestyle);
  const usedLifestyleModule = lifestyle.preparationIndex !== null;
  const lifestyleAdjustment = usedLifestyleModule ? lifestyle.adjustment : applyFrequencyAdjustment(zeroRatings(), params.frequencyAdjustment);
  const injuryPenalty = calculateInjuryPenalty(params.limitation);
  const currentRatings = mapAttributes((attribute) =>
    clamp(params.baseRatings[attribute] + lifestyleAdjustment[attribute] - injuryPenalty[attribute], 0, SELF_ASSESSMENT_ATTRIBUTE_MAX),
  );
  return {
    currentRatings,
    currentOverall: calculateOverall(currentRatings, params.primaryPosition),
    lifestyleAdjustment,
    injuryPenalty,
    preparationIndex: lifestyle.preparationIndex,
    usedLifestyleModule,
    explanations: ATTRIBUTE_KEYS.map((attribute) => ({
      attribute,
      previousValue: params.baseRatings[attribute],
      calculatedValue: params.baseRatings[attribute] + lifestyleAdjustment[attribute] - injuryPenalty[attribute],
      finalValue: currentRatings[attribute],
      evidence: [],
      currentFormAdjustment: lifestyleAdjustment[attribute],
      injuryAdjustment: -injuryPenalty[attribute],
      clampApplied: currentRatings[attribute] !== params.baseRatings[attribute] + lifestyleAdjustment[attribute] - injuryPenalty[attribute],
    })),
  };
}

export function applyFrequencyAdjustment(baseRatings: AttributeRatings, frequencyAdjustment: number): AttributeRatings {
  return mapAttributes((attribute) => clamp(baseRatings[attribute] + frequencyAdjustment * FREQUENCY_MULTIPLIERS[attribute], 0, SELF_ASSESSMENT_ATTRIBUTE_MAX));
}

export function buildEvaluationProfile(params: {
  initial: InitialRatingResult;
  advanced: AdvancedRatingResult;
  current: CurrentRatingResult;
  calculatedAt?: string;
}): PlayerEvaluationProfile {
  return {
    ...params.initial.profile,
    advancedTestAnswers: params.advanced.storedAnswers,
    currentFormAnswers: [],
    baseRatings: params.advanced.baseRatings,
    currentRatings: params.current.currentRatings,
    baseOverall: params.advanced.baseOverall,
    currentOverall: params.current.currentOverall,
    reliability: params.advanced.reliability,
    calculatedAt: params.calculatedAt ?? new Date().toISOString(),
  };
}

export function zeroRatings(): AttributeRatings {
  return { pace: 0, shooting: 0, passing: 0, dribbling: 0, defending: 0, physical: 0 };
}

function mapAttributes(mapper: (attribute: AttributeKey) => number): AttributeRatings {
  return {
    pace: mapper("pace"),
    shooting: mapper("shooting"),
    passing: mapper("passing"),
    dribbling: mapper("dribbling"),
    defending: mapper("defending"),
    physical: mapper("physical"),
  };
}

function weightedAverage(items: Array<[number | null, number]>) {
  const available = items.filter((item): item is [number, number] => item[0] !== null);
  const weight = available.reduce((total, item) => total + item[1], 0);
  if (weight === 0) {
    return 50;
  }
  return available.reduce((total, [value, itemWeight]) => total + value * itemWeight, 0) / weight;
}

function storeAnswers(answers: PlayerAnswer[], questionnaireVersion: string, answeredAt: string): StoredAnswer[] {
  return answers.map((answer) => ({ ...answer, questionnaireVersion, answeredAt }));
}

function groupQuestionsByModule(questions: AdvancedQuestion[]) {
  return questions.reduce<Partial<Record<AdvancedModuleId, AdvancedQuestion[]>>>((groups, question) => {
    groups[question.module] = [...(groups[question.module] ?? []), question];
    return groups;
  }, {});
}

function calculateModuleConsistency(answers: Record<string, AnswerValue>) {
  const pairs: Array<{ module: AdvancedModuleId; high: string; low: string }> = [
    { module: "technique", high: "TEC-01", low: "PAS-01" },
    { module: "pace_physical", high: "FIS-01", low: "RIT-04" },
    { module: "defending", high: "DEF-01", low: "DEF-03" },
    { module: "shooting", high: "TIR-04", low: "TIR-01" },
  ];
  const byModule = Object.fromEntries((Object.keys(MODULE_LABELS) as AdvancedModuleId[]).map((module) => [module, { contradictions: 0, factor: 1 }])) as Record<
    AdvancedModuleId,
    { contradictions: number; factor: number }
  >;
  for (const pair of pairs) {
    const high = responseToScore(answers[pair.high] ?? null);
    const low = responseToScore(answers[pair.low] ?? null);
    if (high !== null && low !== null && high >= 80 && low <= 40) {
      byModule[pair.module].contradictions += 1;
    }
  }
  for (const moduleId of Object.keys(byModule) as AdvancedModuleId[]) {
    byModule[moduleId].factor = consistencyFactor(byModule[moduleId].contradictions);
  }
  return byModule;
}

function consistencyFactor(contradictionCount: number) {
  if (contradictionCount === 0) {
    return 1;
  }
  if (contradictionCount === 1) {
    return 0.95;
  }
  if (contradictionCount === 2) {
    return 0.9;
  }
  return 0.85;
}
