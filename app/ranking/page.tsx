import type { Metadata } from "next";
import { ProvincialRankingProduct } from "./provincial-ranking-product";

export const metadata: Metadata = {
  title: "Ranking provincial · Pachangas IQ",
  description: "Clasificación provincial oficial de Pachangas IQ.",
};

export default function ProvincialRankingPage() {
  return <ProvincialRankingProduct />;
}
