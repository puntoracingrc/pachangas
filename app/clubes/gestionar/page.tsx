import type { Metadata } from "next";
import { ClubManagerClient } from "./club-manager-client";

export const metadata: Metadata = { robots: { follow: false, index: false }, title: "Gestionar Clubs | Pachangas IQ" };

export default function ClubManagerPage() { return <ClubManagerClient />; }
