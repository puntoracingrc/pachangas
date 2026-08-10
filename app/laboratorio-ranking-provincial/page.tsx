import { ProvincialRankingPilot } from "./provincial-ranking-pilot";
import { resolveProvincialFeatureFlags } from "../../simulation/season-ranking-lab/src/territory-award-readiness";
import readiness from "../../simulation/synthetic-world/generated/territory-award-readiness-v1-summary.json";
import type { ProvincialPilotTerritory } from "./provincial-ranking-pilot";

export const metadata = {
  robots: { follow: false, index: false },
  title: "Ranking provincial · Pachangas IQ Lab",
};

export default function ProvincialRankingLabPage() {
  const territories = readiness.sourceTerritories.map(({ provinceCode, provinceName, ranking, snapshot, unranked }) => ({
    provinceCode,
    provinceName,
    ranking,
    snapshot,
    unranked,
  })) as unknown as ProvincialPilotTerritory[];
  return <ProvincialRankingPilot featureFlags={resolveProvincialFeatureFlags(process.env)} territories={territories} />;
}
