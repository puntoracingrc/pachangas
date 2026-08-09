import type { SyntheticProvince, SyntheticWorldConfig } from "./types";

export const SYNTHETIC_SOURCE_COMMIT = "4c75d52e15449528fe206e4d542715ec96d42422";
export const DEFAULT_WORLD_SEED = 20260809;
export const DEFAULT_WORLD_START = "2026-09-01T08:00:00.000Z";

export const DEFAULT_WORLD_CONFIG: SyntheticWorldConfig = {
  agentCount: 640,
  attackRate: 0.075,
  guestCount: 30,
  initialFreeAgentCount: 40,
  seasonEnd: "2027-06-30T23:00:00.000Z",
  teamCount: 50,
};

export const SYNTHETIC_PROVINCES: SyntheticProvince[] = [
  { city: "Barcelona", code: "08", communityCode: "CT", communityName: "Cataluña", density: "dense", lat: 41.3874, lng: 2.1686, name: "Barcelona" },
  { city: "Madrid", code: "28", communityCode: "MD", communityName: "Comunidad de Madrid", density: "dense", lat: 40.4168, lng: -3.7038, name: "Madrid" },
  { city: "Valencia", code: "46", communityCode: "VC", communityName: "Comunitat Valenciana", density: "medium", lat: 39.4699, lng: -0.3763, name: "Valencia" },
  { city: "Sevilla", code: "41", communityCode: "AN", communityName: "Andalucía", density: "medium", lat: 37.3891, lng: -5.9845, name: "Sevilla" },
  { city: "Girona", code: "17", communityCode: "CT", communityName: "Cataluña", density: "small", lat: 41.9794, lng: 2.8214, name: "Girona" },
  { city: "Zaragoza", code: "50", communityCode: "AR", communityName: "Aragón", density: "small", lat: 41.6488, lng: -0.8891, name: "Zaragoza" },
  { city: "A Coruña", code: "15", communityCode: "GA", communityName: "Galicia", density: "small", lat: 43.3623, lng: -8.4115, name: "A Coruña" },
  { city: "Murcia", code: "30", communityCode: "MC", communityName: "Región de Murcia", density: "small", lat: 37.9922, lng: -1.1307, name: "Murcia" },
];
export const PROVINCE_WEIGHTS = [
  { value: SYNTHETIC_PROVINCES[0]!, weight: 32 },
  { value: SYNTHETIC_PROVINCES[1]!, weight: 24 },
  { value: SYNTHETIC_PROVINCES[2]!, weight: 14 },
  { value: SYNTHETIC_PROVINCES[3]!, weight: 12 },
  { value: SYNTHETIC_PROVINCES[4]!, weight: 8 },
  { value: SYNTHETIC_PROVINCES[5]!, weight: 4 },
  { value: SYNTHETIC_PROVINCES[6]!, weight: 3 },
  { value: SYNTHETIC_PROVINCES[7]!, weight: 3 },
];
