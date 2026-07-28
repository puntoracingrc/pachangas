"use client";

import { CSSProperties, FormEvent, Fragment, useEffect, useMemo, useRef, useState } from "react";
import type { User } from "@supabase/supabase-js";
import { supabase } from "./supabaseClient";

const googleClientId = process.env.NEXT_PUBLIC_GOOGLE_CLIENT_ID;
const googleAuthNonceKey = "pachanga-google-auth-nonce";
const googleAuthReturnKey = "pachanga-google-auth-return";

function createGoogleRawNonce() {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return btoa(String.fromCharCode(...bytes));
}

async function sha256Hex(value: string) {
  const encoded = new TextEncoder().encode(value);
  const buffer = await crypto.subtle.digest("SHA-256", encoded);
  return Array.from(new Uint8Array(buffer))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

type RatingFacet = "ritmo" | "tiro" | "pase" | "regate" | "defensa" | "fisico";

type RatingVote = {
  id: string;
  voterId: string;
  voterName?: string;
  matchCount: number;
  createdAt: string;
  facets: Record<RatingFacet, number>;
};

type PositionLine = "Porteria" | "Defensa" | "Medio" | "Ataque";

type PlayerPosition =
  | "Portero"
  | "Defensa central"
  | "Lateral derecho"
  | "Lateral izquierdo"
  | "Carrilero"
  | "Pivote defensivo"
  | "Interior / volante"
  | "Mediapunta"
  | "Extremo derecho"
  | "Extremo izquierdo"
  | "Delantero centro"
  | "Segundo delantero"
  | "Mediocentro / pivote"
  | "Delantero / punta"
  | "Cierre"
  | "Ala derecha"
  | "Ala izquierda"
  | "Pívot"
  | "Porteria"
  | "Defensa"
  | "Medio"
  | "Ataque";

type Player = {
  id: string;
  ownerUserId?: string;
  name: string;
  avatar?: string;
  phone?: string;
  goalkeeperOnly?: boolean;
  injured?: boolean;
  inactive?: boolean;
  rating: number;
  ratings?: number[];
  ratingVotes?: RatingVote[];
  position: PlayerPosition;
  goals: number;
  assists: number;
  appearances: number;
  wins: number;
  lateCancels: number;
};

type MatchPlayer = {
  playerId: string;
  status: "voy" | "duda" | "no";
  joinedAt?: string;
  paid?: boolean;
};

type MatchKind = "sala" | "futbol7" | "futbol11";

type Venue = {
  id: string;
  name: string;
  defaultCost: number;
  kind?: MatchKind;
};

type SiteSettings = {
  brand: string;
  title: string;
  subtitle: string;
  teamAColor: string;
  teamBColor: string;
};

type Match = {
  id: string;
  title: string;
  date: string;
  place: string;
  configured?: boolean;
  venueId?: string;
  kind?: MatchKind;
  targetPlayers: number;
  fieldCost?: number;
  price?: number;
  payerId?: string;
  players: MatchPlayer[];
  reservesAttend?: boolean;
  reserveLimit?: number;
  scorers?: Array<{ playerId: string; goals: number }>;
  closed?: boolean;
  lineupClosed?: boolean;
  scoreA?: number;
  scoreB?: number;
  teamA?: string[];
  teamB?: string[];
};

type AppPayload = {
  activeMatchId: string;
  matches: Match[];
  players: Player[];
  siteSettings: SiteSettings;
  venues: Venue[];
};

type MemberRole = "owner" | "admin" | "player";

type RemoteTeam = {
  id: string;
  inviteToken: string;
  name: string;
  payload: AppPayload;
  role: MemberRole;
  teamCode: string;
};

type RemoteMember = {
  displayName: string;
  role: MemberRole;
  userId: string;
};

function demoVotes(playerId: string, rows: Array<[number, string, Record<RatingFacet, number>]>): RatingVote[] {
  return rows.map(([matchCount, createdAt, facets], index) => ({
    id: `rv-${playerId}-${index + 1}`,
    voterId: "demo",
    voterName: "Demo",
    matchCount,
    createdAt,
    facets,
  }));
}

const seedPlayers: Player[] = [
  { id: "p1", name: "Carlos", phone: "600 111 222", goalkeeperOnly: false, rating: 8, position: "Delantero / punta", goals: 18, assists: 7, appearances: 12, wins: 7, lateCancels: 1, ratingVotes: demoVotes("p1", [[3, "2026-06-10T23:00:00", { ritmo: 7, tiro: 8, pase: 6, regate: 7, defensa: 4, fisico: 7 }], [6, "2026-06-24T23:00:00", { ritmo: 8, tiro: 8, pase: 7, regate: 8, defensa: 5, fisico: 8 }], [9, "2026-07-08T23:00:00", { ritmo: 8, tiro: 9, pase: 7, regate: 8, defensa: 5, fisico: 8 }], [12, "2026-07-23T23:00:00", { ritmo: 8, tiro: 9, pase: 8, regate: 8, defensa: 5, fisico: 8 }]]) },
  { id: "p2", name: "Manu", phone: "600 222 333", rating: 7, position: "Mediocentro / pivote", goals: 10, assists: 13, appearances: 11, wins: 8, lateCancels: 0, ratingVotes: demoVotes("p2", [[3, "2026-06-10T23:00:00", { ritmo: 6, tiro: 5, pase: 8, regate: 6, defensa: 6, fisico: 7 }], [6, "2026-06-24T23:00:00", { ritmo: 6, tiro: 6, pase: 8, regate: 7, defensa: 7, fisico: 7 }], [8, "2026-07-08T23:00:00", { ritmo: 6, tiro: 6, pase: 9, regate: 7, defensa: 7, fisico: 7 }], [11, "2026-07-23T23:00:00", { ritmo: 7, tiro: 6, pase: 9, regate: 7, defensa: 8, fisico: 7 }]]) },
  { id: "p3", name: "Pablo", phone: "600 333 444", rating: 6, position: "Defensa central", goals: 5, assists: 4, appearances: 10, wins: 5, lateCancels: 2, ratingVotes: demoVotes("p3", [[3, "2026-06-10T23:00:00", { ritmo: 5, tiro: 4, pase: 5, regate: 5, defensa: 7, fisico: 6 }], [6, "2026-06-24T23:00:00", { ritmo: 5, tiro: 4, pase: 6, regate: 5, defensa: 8, fisico: 7 }], [10, "2026-07-23T23:00:00", { ritmo: 6, tiro: 4, pase: 6, regate: 5, defensa: 8, fisico: 7 }]]) },
  { id: "p4", name: "Rafa", phone: "600 444 555", goalkeeperOnly: true, rating: 7, position: "Portero", goals: 1, assists: 2, appearances: 9, wins: 4, lateCancels: 0, ratingVotes: demoVotes("p4", [[3, "2026-06-10T23:00:00", { ritmo: 6, tiro: 4, pase: 6, regate: 5, defensa: 8, fisico: 7 }], [6, "2026-07-03T23:00:00", { ritmo: 6, tiro: 4, pase: 7, regate: 5, defensa: 9, fisico: 7 }], [9, "2026-07-23T23:00:00", { ritmo: 6, tiro: 4, pase: 7, regate: 6, defensa: 9, fisico: 7 }]]) },
  { id: "p5", name: "Dani", phone: "600 555 666", rating: 5, position: "Interior / volante", goals: 6, assists: 3, appearances: 8, wins: 3, lateCancels: 1, ratingVotes: demoVotes("p5", [[3, "2026-06-10T23:00:00", { ritmo: 5, tiro: 5, pase: 5, regate: 6, defensa: 5, fisico: 5 }], [6, "2026-06-24T23:00:00", { ritmo: 6, tiro: 5, pase: 6, regate: 6, defensa: 5, fisico: 5 }], [8, "2026-07-23T23:00:00", { ritmo: 6, tiro: 6, pase: 6, regate: 6, defensa: 5, fisico: 6 }]]) },
  { id: "p6", name: "Alex", phone: "600 666 777", rating: 6, position: "Defensa central", goals: 4, assists: 8, appearances: 9, wins: 6, lateCancels: 0, ratingVotes: demoVotes("p6", [[3, "2026-06-10T23:00:00", { ritmo: 5, tiro: 4, pase: 6, regate: 5, defensa: 7, fisico: 6 }], [6, "2026-06-24T23:00:00", { ritmo: 6, tiro: 4, pase: 6, regate: 5, defensa: 8, fisico: 7 }], [9, "2026-07-23T23:00:00", { ritmo: 6, tiro: 5, pase: 7, regate: 5, defensa: 8, fisico: 7 }]]) },
  { id: "p7", name: "Sergio", phone: "600 777 888", rating: 8, position: "Delantero / punta", goals: 15, assists: 5, appearances: 8, wins: 5, lateCancels: 1, ratingVotes: demoVotes("p7", [[3, "2026-06-10T23:00:00", { ritmo: 7, tiro: 7, pase: 6, regate: 7, defensa: 4, fisico: 7 }], [5, "2026-07-07T23:00:00", { ritmo: 8, tiro: 8, pase: 6, regate: 8, defensa: 4, fisico: 7 }], [8, "2026-07-23T23:00:00", { ritmo: 9, tiro: 8, pase: 6, regate: 8, defensa: 4, fisico: 7 }]]) },
  { id: "p8", name: "Javi", phone: "600 888 999", rating: 5, position: "Lateral derecho", goals: 3, assists: 6, appearances: 7, wins: 2, lateCancels: 3, ratingVotes: demoVotes("p8", [[3, "2026-06-10T23:00:00", { ritmo: 6, tiro: 4, pase: 5, regate: 5, defensa: 5, fisico: 5 }], [7, "2026-07-23T23:00:00", { ritmo: 7, tiro: 4, pase: 5, regate: 6, defensa: 6, fisico: 5 }]]) },
  { id: "p9", name: "Nico", phone: "600 999 000", rating: 5, position: "Ala izquierda", goals: 2, assists: 2, appearances: 2, wins: 1, lateCancels: 0 },
  { id: "p10", name: "Pedro", phone: "601 111 222", rating: 6, position: "Cierre", goals: 7, assists: 2, appearances: 4, wins: 2, lateCancels: 0 },
  { id: "p11", name: "Alberto", phone: "601 222 333", rating: 5, position: "Mediapunta", goals: 0, assists: 1, appearances: 1, wins: 0, lateCancels: 0 },
  { id: "p12", name: "Carlitos", phone: "601 333 444", rating: 6, position: "Extremo derecho", goals: 9, assists: 4, appearances: 6, wins: 4, lateCancels: 1 },
  { id: "p13", name: "Vicente", phone: "601 444 555", rating: 5, position: "Lateral izquierdo", goals: 1, assists: 2, appearances: 5, wins: 2, lateCancels: 0 },
  { id: "p14", name: "Mario", phone: "601 555 666", goalkeeperOnly: true, rating: 6, position: "Portero", goals: 0, assists: 0, appearances: 3, wins: 1, lateCancels: 0 },
  { id: "p15", name: "Hugo", phone: "601 666 777", injured: true, rating: 7, position: "Defensa central", goals: 4, assists: 1, appearances: 6, wins: 2, lateCancels: 0 },
  { id: "p16", name: "Rubén", phone: "601 777 888", inactive: true, rating: 6, position: "Interior / volante", goals: 6, assists: 7, appearances: 9, wins: 4, lateCancels: 1 },
  { id: "p17", name: "Iván", phone: "601 888 999", rating: 4, position: "Ala derecha", goals: 1, assists: 1, appearances: 0, wins: 0, lateCancels: 0 },
  { id: "p18", name: "Óscar", phone: "601 999 000", rating: 7, position: "Pívot", goals: 12, assists: 3, appearances: 5, wins: 3, lateCancels: 0 },
];

const seedVenues: Venue[] = [
  { id: "v1", name: "Polideportivo La Mina", defaultCost: 56, kind: "futbol7" },
  { id: "v2", name: "Pista El Parque", defaultCost: 42, kind: "sala" },
  { id: "v3", name: "Municipal Norte", defaultCost: 110, kind: "futbol11" },
];

function demoMatchPlayers(playerIds: string[], paidIds: string[] = playerIds): MatchPlayer[] {
  return playerIds.map((playerId) => ({ playerId, status: "voy" as const, paid: paidIds.includes(playerId) }));
}

const seedMatches: Match[] = [
  {
    id: "m1",
    title: "Demo jueves 21:00",
    date: "2026-07-30T21:00",
    place: "Polideportivo La Mina",
    venueId: "v1",
    kind: "futbol7",
    targetPlayers: 14,
    fieldCost: 56,
    configured: true,
    payerId: "p2",
    reservesAttend: true,
    reserveLimit: 2,
    lineupClosed: false,
    players: [
      { playerId: "p4", status: "voy", joinedAt: "2026-07-20T09:00:00", paid: true },
      { playerId: "p14", status: "voy", joinedAt: "2026-07-20T09:03:00", paid: false },
      { playerId: "p1", status: "voy", joinedAt: "2026-07-20T09:10:00", paid: true },
      { playerId: "p2", status: "voy", joinedAt: "2026-07-20T09:14:00", paid: false },
      { playerId: "p3", status: "voy", joinedAt: "2026-07-20T09:21:00", paid: true },
      { playerId: "p5", status: "voy", joinedAt: "2026-07-20T09:28:00", paid: false },
      { playerId: "p6", status: "voy", joinedAt: "2026-07-20T09:35:00", paid: true },
      { playerId: "p7", status: "voy", joinedAt: "2026-07-20T09:40:00", paid: false },
      { playerId: "p8", status: "voy", joinedAt: "2026-07-20T09:45:00", paid: false },
      { playerId: "p10", status: "voy", joinedAt: "2026-07-20T09:51:00", paid: false },
      { playerId: "p11", status: "voy", joinedAt: "2026-07-20T09:58:00", paid: false },
      { playerId: "p12", status: "voy", joinedAt: "2026-07-20T10:02:00", paid: true },
      { playerId: "p13", status: "voy", joinedAt: "2026-07-20T10:10:00", paid: false },
      { playerId: "p18", status: "voy", joinedAt: "2026-07-20T10:15:00", paid: false },
      { playerId: "p9", status: "voy", joinedAt: "2026-07-20T10:35:00", paid: false },
      { playerId: "p17", status: "voy", joinedAt: "2026-07-20T10:46:00", paid: false },
      { playerId: "p15", status: "no" },
      { playerId: "p16", status: "no" },
    ],
  },
  {
    id: "m2",
    title: "Demo sala rápida",
    date: "2026-07-23T21:00",
    place: "Pista El Parque",
    venueId: "v2",
    kind: "sala",
    targetPlayers: 10,
    fieldCost: 42,
    configured: true,
    payerId: "p1",
    closed: true,
    scoreA: 5,
    scoreB: 3,
    teamA: ["p4", "p1", "p2", "p7", "p12"],
    teamB: ["p14", "p3", "p5", "p6", "p8"],
    scorers: [
      { playerId: "p1", goals: 2 },
      { playerId: "p7", goals: 2 },
      { playerId: "p12", goals: 1 },
      { playerId: "p5", goals: 1 },
      { playerId: "p6", goals: 1 },
      { playerId: "p8", goals: 1 },
    ],
    players: demoMatchPlayers(["p4", "p1", "p2", "p7", "p12", "p14", "p3", "p5", "p6", "p8"]),
  },
  {
    id: "m3",
    title: "Demo 7v7 igualada",
    date: "2026-07-16T21:00",
    place: "Polideportivo La Mina",
    venueId: "v1",
    kind: "futbol7",
    targetPlayers: 14,
    fieldCost: 56,
    configured: true,
    payerId: "p2",
    closed: true,
    scoreA: 4,
    scoreB: 4,
    teamA: ["p4", "p6", "p8", "p13", "p1", "p7", "p10"],
    teamB: ["p14", "p3", "p5", "p2", "p11", "p12", "p18"],
    scorers: [
      { playerId: "p1", goals: 2 },
      { playerId: "p7", goals: 1 },
      { playerId: "p10", goals: 1 },
      { playerId: "p18", goals: 2 },
      { playerId: "p12", goals: 1 },
      { playerId: "p5", goals: 1 },
    ],
    players: demoMatchPlayers(["p4", "p6", "p8", "p13", "p1", "p7", "p10", "p14", "p3", "p5", "p2", "p11", "p12", "p18"], ["p4", "p6", "p1", "p14", "p3", "p2", "p18"]),
  },
  {
    id: "m4",
    title: "Demo lunes sala",
    date: "2026-07-09T20:30",
    place: "Pista El Parque",
    venueId: "v2",
    kind: "sala",
    targetPlayers: 10,
    fieldCost: 42,
    configured: true,
    payerId: "p3",
    closed: true,
    scoreA: 6,
    scoreB: 2,
    teamA: ["p4", "p1", "p2", "p7", "p18"],
    teamB: ["p14", "p3", "p5", "p6", "p12"],
    scorers: [
      { playerId: "p18", goals: 3 },
      { playerId: "p1", goals: 2 },
      { playerId: "p7", goals: 1 },
      { playerId: "p12", goals: 1 },
      { playerId: "p5", goals: 1 },
    ],
    players: demoMatchPlayers(["p4", "p1", "p2", "p7", "p18", "p14", "p3", "p5", "p6", "p12"], ["p1", "p2", "p18", "p3", "p12"]),
  },
  {
    id: "m5",
    title: "Demo jueves 7v7",
    date: "2026-07-02T21:00",
    place: "Polideportivo La Mina",
    venueId: "v1",
    kind: "futbol7",
    targetPlayers: 14,
    fieldCost: 56,
    configured: true,
    payerId: "p6",
    closed: true,
    scoreA: 3,
    scoreB: 5,
    teamA: ["p4", "p3", "p8", "p13", "p5", "p11", "p12"],
    teamB: ["p14", "p6", "p10", "p2", "p1", "p7", "p18"],
    scorers: [
      { playerId: "p12", goals: 2 },
      { playerId: "p5", goals: 1 },
      { playerId: "p1", goals: 2 },
      { playerId: "p7", goals: 2 },
      { playerId: "p18", goals: 1 },
    ],
    players: demoMatchPlayers(["p4", "p3", "p8", "p13", "p5", "p11", "p12", "p14", "p6", "p10", "p2", "p1", "p7", "p18"], ["p4", "p8", "p12", "p14", "p6", "p1", "p7"]),
  },
  {
    id: "m6",
    title: "Demo municipal 11",
    date: "2026-06-25T22:00",
    place: "Municipal Norte",
    venueId: "v3",
    kind: "futbol11",
    targetPlayers: 22,
    fieldCost: 110,
    configured: true,
    payerId: "p7",
    closed: true,
    scoreA: 2,
    scoreB: 1,
    teamA: ["p4", "p3", "p6", "p8", "p13", "p2", "p5", "p11", "p1", "p7", "p12"],
    teamB: ["p14", "p10", "p15", "p16", "p9", "p17", "p18"],
    scorers: [
      { playerId: "p7", goals: 1 },
      { playerId: "p1", goals: 1 },
      { playerId: "p18", goals: 1 },
    ],
    players: demoMatchPlayers(["p4", "p3", "p6", "p8", "p13", "p2", "p5", "p11", "p1", "p7", "p12", "p14", "p10", "p15", "p16", "p9", "p17", "p18"], ["p4", "p3", "p6", "p2", "p1", "p7", "p14", "p10", "p18"]),
  },
  {
    id: "m7",
    title: "Demo primera prueba",
    date: "2026-06-18T21:00",
    place: "Polideportivo La Mina",
    venueId: "v1",
    kind: "futbol7",
    targetPlayers: 14,
    fieldCost: 50,
    configured: true,
    payerId: "p4",
    closed: true,
    scoreA: 1,
    scoreB: 3,
    teamA: ["p4", "p3", "p8", "p13", "p5", "p11", "p12"],
    teamB: ["p14", "p6", "p10", "p2", "p1", "p7", "p18"],
    scorers: [
      { playerId: "p12", goals: 1 },
      { playerId: "p1", goals: 1 },
      { playerId: "p7", goals: 1 },
      { playerId: "p18", goals: 1 },
    ],
    players: demoMatchPlayers(["p4", "p3", "p8", "p13", "p5", "p11", "p12", "p14", "p6", "p10", "p2", "p1", "p7", "p18"], ["p4", "p3", "p12", "p14", "p2", "p7"]),
  },
];

const storageKey = "pachanga-iq-v3";
const profileNameKey = "pachanga-iq-profile-name";

function defaultPayload(): AppPayload {
  return {
    activeMatchId: seedMatches[0].id,
    matches: seedMatches,
    players: seedPlayers,
    siteSettings: defaultSiteSettings,
    venues: seedVenues,
  };
}

const defaultSiteSettings: SiteSettings = {
  brand: "Pachangas IQ",
  title: "El grupo del partido, pero con memoria.",
  subtitle: "Confirma gente, guarda resultados y monta equipos equilibrados sin discutir media hora en WhatsApp.",
  teamAColor: "#2157a8",
  teamBColor: "#d93025",
};

function WhatsAppLogo() {
  return (
    <svg aria-hidden="true" viewBox="0 0 24 24">
      <path d="M12 3.3a8.5 8.5 0 0 0-7.2 13L4 20.8l4.6-1.2A8.5 8.5 0 1 0 12 3.3Zm0 1.7a6.8 6.8 0 1 1-3.1 12.8l-.3-.2-2.4.6.6-2.3-.2-.4A6.8 6.8 0 0 1 12 5Zm-3.1 3.6c-.2 0-.5.1-.7.4-.2.3-.8.8-.8 1.9s.8 2.2 1 2.4c.1.2 1.7 2.8 4.2 3.8 2.1.8 2.5.5 3 .5.4 0 1.4-.6 1.6-1.1.2-.5.2-1 .1-1.1-.1-.1-.2-.2-.5-.3l-1.6-.8c-.2-.1-.4-.1-.6.2l-.7.9c-.1.2-.3.2-.5.1-.3-.1-1.1-.4-2-1.2-.7-.7-1.2-1.5-1.4-1.7-.1-.3 0-.4.1-.5l.4-.5c.1-.2.2-.3.3-.5.1-.2 0-.3 0-.5L10 9c-.2-.4-.4-.4-.6-.4h-.5Z" />
    </svg>
  );
}

function CopyLogo() {
  return (
    <svg aria-hidden="true" viewBox="0 0 24 24">
      <path d="M8 7.5A2.5 2.5 0 0 1 10.5 5h7A2.5 2.5 0 0 1 20 7.5v7a2.5 2.5 0 0 1-2.5 2.5H16v1.5A2.5 2.5 0 0 1 13.5 21h-7A2.5 2.5 0 0 1 4 18.5v-7A2.5 2.5 0 0 1 6.5 9H8V7.5Zm2 1.5h3.5A2.5 2.5 0 0 1 16 11.5V15h1.5a.5.5 0 0 0 .5-.5v-7a.5.5 0 0 0-.5-.5h-7a.5.5 0 0 0-.5.5V9Zm-3.5 2a.5.5 0 0 0-.5.5v7a.5.5 0 0 0 .5.5h7a.5.5 0 0 0 .5-.5v-7a.5.5 0 0 0-.5-.5h-7Z" />
    </svg>
  );
}

function TrashLogo() {
  return (
    <svg aria-hidden="true" viewBox="0 0 24 24">
      <path d="M9 4a2 2 0 0 1 2-2h2a2 2 0 0 1 2 2h4v2H5V4h4Zm-2 4h10l-.7 11.2A3 3 0 0 1 13.3 22h-2.6a3 3 0 0 1-3-2.8L7 8Zm3 2 .4 9h1.7l-.3-9H10Zm3.2 0-.3 9h1.7l.4-9h-1.8Z" />
    </svg>
  );
}

function HospitalLogo() {
  return (
    <svg aria-hidden="true" viewBox="0 0 24 24">
      <path d="M4 21V5a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v16h-6v-5h-4v5H4Zm2-2h2v-5h8v5h2V5H6v14Zm5-6v-3H8V8h3V5h2v3h3v2h-3v3h-2Z" />
    </svg>
  );
}

function UserOffLogo() {
  return (
    <svg aria-hidden="true" viewBox="0 0 24 24">
      <path d="M10 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8Zm0 2c-3.6 0-7 1.8-7 4.8V20h10.7A6.9 6.9 0 0 1 13 17c0-1.4.4-2.7 1.1-3.8A12 12 0 0 0 10 13Zm8 1a4 4 0 1 0 0 8 4 4 0 0 0 0-8Zm-2.2 3.2 1.4-1.4.8.8.8-.8 1.4 1.4-.8.8.8.8-1.4 1.4-.8-.8-.8.8-1.4-1.4.8-.8-.8-.8Z" />
    </svg>
  );
}

const matchKinds: Record<MatchKind, { label: string; targetPlayers: number; teamSize: number }> = {
  sala: { label: "Fútbol sala", targetPlayers: 10, teamSize: 5 },
  futbol7: { label: "Fútbol 7", targetPlayers: 14, teamSize: 7 },
  futbol11: { label: "Fútbol 11", targetPlayers: 22, teamSize: 11 },
};

function starterMatch(baseDate = "2026-07-30T21:00", kind: MatchKind = "futbol7"): Match {
  return {
    id: id(),
    title: "Nueva pachanga",
    date: nextMatchDate(baseDate),
    place: "Campo por confirmar",
    configured: false,
    kind,
    targetPlayers: matchKinds[kind].targetPlayers,
    fieldCost: 0,
    players: [],
    reservesAttend: false,
    reserveLimit: 0,
  };
}

function emptyTeamPayload(teamName: string): AppPayload {
  const match = starterMatch(undefined, "futbol7");
  return {
    activeMatchId: match.id,
    matches: [match],
    players: [],
    siteSettings: {
      ...defaultSiteSettings,
      brand: displayName(teamName) || defaultSiteSettings.brand,
      title: "Tu equipo pachanguero, desde cero.",
      subtitle: "Añade jugadores, campos y partidos para empezar a organizar tu grupo.",
    },
    venues: [],
  };
}

const positionOptionsByKind: Record<MatchKind, Array<{ value: PlayerPosition; line: PositionLine; short: string }>> = {
  futbol11: [
    { value: "Portero", line: "Porteria", short: "POR" },
    { value: "Defensa central", line: "Defensa", short: "DFC" },
    { value: "Lateral derecho", line: "Defensa", short: "LD" },
    { value: "Lateral izquierdo", line: "Defensa", short: "LI" },
    { value: "Carrilero", line: "Defensa", short: "CAR" },
    { value: "Pivote defensivo", line: "Medio", short: "MCD" },
    { value: "Interior / volante", line: "Medio", short: "INT" },
    { value: "Mediapunta", line: "Medio", short: "MP" },
    { value: "Extremo derecho", line: "Ataque", short: "ED" },
    { value: "Extremo izquierdo", line: "Ataque", short: "EI" },
    { value: "Delantero centro", line: "Ataque", short: "DC" },
    { value: "Segundo delantero", line: "Ataque", short: "SD" },
  ],
  futbol7: [
    { value: "Portero", line: "Porteria", short: "POR" },
    { value: "Defensa central", line: "Defensa", short: "DFC" },
    { value: "Lateral derecho", line: "Defensa", short: "LD" },
    { value: "Lateral izquierdo", line: "Defensa", short: "LI" },
    { value: "Mediocentro / pivote", line: "Medio", short: "MC" },
    { value: "Interior / volante", line: "Medio", short: "INT" },
    { value: "Delantero / punta", line: "Ataque", short: "DEL" },
  ],
  sala: [
    { value: "Portero", line: "Porteria", short: "POR" },
    { value: "Cierre", line: "Defensa", short: "CIE" },
    { value: "Ala derecha", line: "Medio", short: "ALD" },
    { value: "Ala izquierda", line: "Medio", short: "ALI" },
    { value: "Pívot", line: "Ataque", short: "PIV" },
  ],
};

const legacyPositionMeta: Record<"Porteria" | "Defensa" | "Medio" | "Ataque", { line: PositionLine; label: string; short: string }> = {
  Porteria: { line: "Porteria", label: "Portero", short: "POR" },
  Defensa: { line: "Defensa", label: "Defensa", short: "DEF" },
  Medio: { line: "Medio", label: "Medio", short: "MED" },
  Ataque: { line: "Ataque", label: "Delantero / punta", short: "DEL" },
};

const ratingReviewInterval = 3;

const ratingFacets: Array<{ key: RatingFacet; label: string }> = [
  { key: "ritmo", label: "Ritmo" },
  { key: "tiro", label: "Tiro" },
  { key: "pase", label: "Pase" },
  { key: "regate", label: "Regate" },
  { key: "defensa", label: "Defensa" },
  { key: "fisico", label: "Físico" },
];

const teamPalette = [
  { name: "Azul", value: "#2157a8" },
  { name: "Rojo", value: "#d93025" },
  { name: "Verde", value: "#16803f" },
  { name: "Amarillo", value: "#f2c94c" },
  { name: "Naranja", value: "#f97316" },
  { name: "Morado", value: "#7c3aed" },
  { name: "Negro", value: "#202820" },
  { name: "Blanco", value: "#f8fafc" },
];

function id() {
  return crypto.randomUUID();
}

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function compactUuid(value: string) {
  if (!uuidPattern.test(value)) return value;

  const hex = value.replaceAll("-", "");
  const raw = Array.from({ length: 16 }, (_, index) => String.fromCharCode(Number.parseInt(hex.slice(index * 2, index * 2 + 2), 16))).join("");
  return btoa(raw).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

function expandCompactUuid(value: string | null) {
  if (!value) return null;
  if (uuidPattern.test(value)) return value;

  try {
    const padded = value.replaceAll("-", "+").replaceAll("_", "/").padEnd(Math.ceil(value.length / 4) * 4, "=");
    const raw = atob(padded);
    if (raw.length !== 16) return value;

    const hex = Array.from(raw, (char) => char.charCodeAt(0).toString(16).padStart(2, "0")).join("");
    return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
  } catch {
    return value;
  }
}

function nextMatchDate(previousDate: string) {
  const base = new Date(previousDate);
  const next = Number.isNaN(base.getTime()) ? new Date() : base;
  next.setDate(next.getDate() + 7);
  return toDateTimeLocal(next);
}

function toDateTimeLocal(date: Date) {
  const pad = (value: number) => String(value).padStart(2, "0");
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

function scorePlayer(player: Player) {
  return peerAverage(player);
}

function clampRating(value: number) {
  return Math.max(1, Math.min(10, Number.isFinite(value) ? value : 5));
}

function displayName(name: string) {
  return name
    .trim()
    .split(/\s+/)
    .map((word) => word.charAt(0).toLocaleUpperCase("es-ES") + word.slice(1).toLocaleLowerCase("es-ES"))
    .join(" ");
}

function monthLabel(date: string) {
  const label = new Date(date).toLocaleDateString("es-ES", { month: "long", year: "numeric" });
  return label.charAt(0).toLocaleUpperCase("es-ES") + label.slice(1);
}

function joinedAtLabel(date?: string) {
  if (!date) return "";

  const parsed = new Date(date);
  if (Number.isNaN(parsed.getTime())) return "";

  return parsed.toLocaleString("es-ES", {
    day: "2-digit",
    month: "short",
    hour: "2-digit",
    minute: "2-digit",
  });
}

function playerDisplayName(player: Player) {
  return displayName(player.name);
}

function normalizeSiteSettings(settings?: Partial<SiteSettings>): SiteSettings {
  return {
    ...defaultSiteSettings,
    ...settings,
    teamAColor: settings?.teamAColor ?? defaultSiteSettings.teamAColor,
    teamBColor: settings?.teamBColor ?? defaultSiteSettings.teamBColor,
  };
}

function normalizePayload(payload?: Partial<AppPayload>): AppPayload {
  const fallback = defaultPayload();
  const venues = payload?.venues ? payload.venues : fallback.venues;
  const rawMatches = payload?.matches ? payload.matches : fallback.matches;
  const matches = rawMatches.length
    ? rawMatches.map((match) => ({
        ...match,
        venueId: match.venueId ?? venues.find((venue) => venue.name === match.place)?.id,
        fieldCost: match.fieldCost ?? (match.price ? match.price * Math.max(match.targetPlayers, 1) : 0),
        configured: match.configured ?? Boolean(match.closed || match.scoreA !== undefined || match.players?.length || match.venueId),
        lineupClosed: match.lineupClosed ?? false,
        reservesAttend: match.reservesAttend ?? false,
        reserveLimit: Math.max(0, Math.floor(match.reserveLimit ?? 0)),
      }))
    : [starterMatch()];
  const players = (payload?.players ? payload.players : fallback.players).map((player) => ({
    ...player,
    injured: Boolean(player.injured),
    inactive: Boolean(player.inactive),
    ratingVotes: normalizeRatingVotes(player.ratingVotes),
  }));

  return {
    activeMatchId: payload?.activeMatchId && matches.some((match) => match.id === payload.activeMatchId) ? payload.activeMatchId : matches[0].id,
    matches,
    players,
    siteSettings: normalizeSiteSettings(payload?.siteSettings),
    venues,
  };
}

function normalizeRatingVotes(votes?: RatingVote[]) {
  return (votes ?? [])
    .map((vote) => {
      const facets = ratingFacets.reduce((next, facet) => {
        next[facet.key] = clampRating(Number(vote.facets?.[facet.key] ?? 5));
        return next;
      }, {} as Record<RatingFacet, number>);

      return {
        id: vote.id || id(),
        voterId: vote.voterId || "legacy",
        voterName: vote.voterName,
        matchCount: Math.max(0, Math.floor(Number(vote.matchCount) || 0)),
        createdAt: vote.createdAt || new Date().toISOString(),
        facets,
      };
    })
    .filter((vote) => vote.voterId);
}

function peerAverage(player: Player) {
  const facetScores = ratingFacets.map((facet) => facetAverage(player, facet.key));
  if (facetScores.length > 0) return facetScores.reduce((sum, rating) => sum + rating, 0) / facetScores.length;
  if (player.ratings?.length) return player.ratings.reduce((sum, rating) => sum + rating, 0) / player.ratings.length;
  return player.rating;
}

function voteAverage(vote: RatingVote) {
  return ratingFacets.reduce((sum, facet) => sum + clampRating(vote.facets[facet.key]), 0) / ratingFacets.length;
}

function facetAverage(player: Player, facet: RatingFacet) {
  const votes = player.ratingVotes ?? [];
  const facetVotes = votes.map((vote) => vote.facets?.[facet]).filter((value): value is number => Number.isFinite(value));
  if (facetVotes.length > 0) return facetVotes.reduce((sum, rating) => sum + rating, 0) / facetVotes.length;
  if (player.ratings?.length) return player.ratings.reduce((sum, rating) => sum + rating, 0) / player.ratings.length;
  return player.rating;
}

function ratingHistory(player: Player) {
  return [...(player.ratingVotes ?? [])].sort((a, b) => a.matchCount - b.matchCount || a.createdAt.localeCompare(b.createdAt));
}

function ratingWindow(player: Player, voterId: string) {
  const ownVote = ratingHistory(player).filter((vote) => vote.voterId === voterId).at(-1);
  const nextMatchCount = ownVote ? ownVote.matchCount + ratingReviewInterval : ratingReviewInterval;
  const waitMatches = Math.max(0, nextMatchCount - player.appearances);
  return {
    canRate: !player.inactive && player.appearances >= nextMatchCount,
    nextMatchCount,
    ownVote,
    waitMatches,
  };
}

function makeFacetRatings(base = 5) {
  return ratingFacets.reduce((next, facet) => {
    next[facet.key] = clampRating(base);
    return next;
  }, {} as Record<RatingFacet, number>);
}

type FaceDetectorLike = new (options?: { fastMode?: boolean; maxDetectedFaces?: number }) => {
  detect: (source: HTMLImageElement) => Promise<
    Array<{
      boundingBox: { x: number; y: number; width: number; height: number };
      landmarks?: Array<{ type?: string; locations?: Array<{ x: number; y: number }> }>;
    }>
  >;
};

type AvatarFace = {
  box: { x: number; y: number; width: number; height: number };
  eyes?: { x: number; y: number };
};

function readFileDataUrl(file: File) {
  return new Promise<string>((resolve, reject) => {
    const reader = new FileReader();
    reader.onerror = () => reject(new Error("No se pudo leer la imagen"));
    reader.onload = () => resolve(String(reader.result ?? ""));
    reader.readAsDataURL(file);
  });
}

function loadAvatarImage(source: string) {
  return new Promise<HTMLImageElement>((resolve, reject) => {
    const image = new Image();
    image.onerror = () => reject(new Error("No se pudo preparar la imagen"));
    image.onload = () => resolve(image);
    image.src = source;
  });
}

async function detectAvatarFace(image: HTMLImageElement) {
  const FaceDetector = (window as unknown as { FaceDetector?: FaceDetectorLike }).FaceDetector;
  if (!FaceDetector) return null;

  const faces = await new FaceDetector({ fastMode: true, maxDetectedFaces: 1 }).detect(image);
  const face = faces
    .map((face) => face.boundingBox)
    .sort((a, b) => b.width * b.height - a.width * a.height)[0];
  const original = faces.find((item) => item.boundingBox === face) ?? faces[0];
  const eyePoints = (original?.landmarks ?? [])
    .filter((landmark) => landmark.type?.toLocaleLowerCase("es-ES").includes("eye"))
    .flatMap((landmark) => landmark.locations ?? []);

  if (!face) return null;
  return {
    box: face,
    eyes: eyePoints.length > 0
      ? {
          x: eyePoints.reduce((sum, point) => sum + point.x, 0) / eyePoints.length,
          y: eyePoints.reduce((sum, point) => sum + point.y, 0) / eyePoints.length,
        }
      : undefined,
  } satisfies AvatarFace;
}

function avatarCropArea(image: HTMLImageElement, face: AvatarFace | null) {
  const targetAspect = 560 / 720;
  const imageWidth = image.naturalWidth || image.width;
  const imageHeight = image.naturalHeight || image.height;
  const fallbackHeight = Math.min(imageHeight, imageWidth / targetAspect);
  let cropHeight = fallbackHeight;
  let centerX = imageWidth / 2;
  let anchorY = imageHeight * 0.38;

  if (face) {
    centerX = face.eyes?.x ?? face.box.x + face.box.width / 2;
    anchorY = face.eyes?.y ?? face.box.y + face.box.height * 0.42;
    cropHeight = Math.max(face.box.height * 2.8, imageHeight * 0.42);
  }

  let cropWidth = cropHeight * targetAspect;
  if (cropWidth > imageWidth) {
    cropWidth = imageWidth;
    cropHeight = cropWidth / targetAspect;
  }
  if (cropHeight > imageHeight) {
    cropHeight = imageHeight;
    cropWidth = cropHeight * targetAspect;
  }

  const x = Math.min(Math.max(centerX - cropWidth / 2, 0), Math.max(0, imageWidth - cropWidth));
  const eyeTarget = face?.eyes ? 0.31 : 0.34;
  const y = Math.min(Math.max(anchorY - cropHeight * eyeTarget, 0), Math.max(0, imageHeight - cropHeight));
  return { x, y, width: cropWidth, height: cropHeight };
}

async function avatarDataUrl(file: File) {
  if (!file.type.startsWith("image/")) throw new Error("El archivo no es una imagen");

  const source = await readFileDataUrl(file);
  const image = await loadAvatarImage(source);
  const face = await detectAvatarFace(image).catch(() => null);
  const crop = avatarCropArea(image, face);
  const canvas = document.createElement("canvas");
  canvas.width = 560;
  canvas.height = 720;
  const context = canvas.getContext("2d");
  if (!context) return source;

  context.fillStyle = "#f4df9a";
  context.fillRect(0, 0, canvas.width, canvas.height);
  context.drawImage(image, crop.x, crop.y, crop.width, crop.height, 0, 0, canvas.width, canvas.height);
  return canvas.toDataURL("image/jpeg", 0.86);
}

function positionMeta(position: PlayerPosition) {
  const option = Object.values(positionOptionsByKind).flat().find((item) => item.value === position);
  if (option) return { line: option.line, label: option.value, short: option.short };
  if (position === "Porteria" || position === "Defensa" || position === "Medio" || position === "Ataque") return legacyPositionMeta[position];
  return { line: "Medio" as PositionLine, label: position, short: "MED" };
}

function playerPosition(player: Player): PositionLine {
  return player.goalkeeperOnly ? "Porteria" : positionMeta(player.position).line;
}

function positionRank(player: Player) {
  const order: Record<PositionLine, number> = { Porteria: 0, Defensa: 1, Medio: 2, Ataque: 3 };
  return order[playerPosition(player)];
}

function sortedLineupPlayers(players: Player[]) {
  return [...players].sort((a, b) => positionRank(a) - positionRank(b) || scorePlayer(b) - scorePlayer(a) || a.name.localeCompare(b.name, "es"));
}

function positionLabel(player: Player) {
  return player.goalkeeperOnly ? "Portero" : positionMeta(player.position).label;
}

function positionShort(player: Player) {
  return player.goalkeeperOnly ? "POR" : positionMeta(player.position).short;
}

function defaultPositionForKind(kind: MatchKind): PlayerPosition {
  if (kind === "sala") return "Ala derecha";
  if (kind === "futbol11") return "Interior / volante";
  return "Mediocentro / pivote";
}

function equivalentPositionForKind(position: PlayerPosition, kind: MatchKind): PlayerPosition {
  if (positionOptionsByKind[kind].some((option) => option.value === position)) return position;
  const line = positionMeta(position).line;

  if (kind === "sala") {
    if (line === "Porteria") return "Portero";
    if (line === "Defensa") return "Cierre";
    if (line === "Ataque") return "Pívot";
    return "Ala derecha";
  }

  if (kind === "futbol11") {
    if (line === "Porteria") return "Portero";
    if (line === "Defensa") return "Defensa central";
    if (line === "Ataque") return "Delantero centro";
    return "Interior / volante";
  }

  if (line === "Porteria") return "Portero";
  if (line === "Defensa") return "Defensa central";
  if (line === "Ataque") return "Delantero / punta";
  return "Mediocentro / pivote";
}

function balanceTeams(players: Player[]) {
  const ordered = [...players].sort((a, b) => scorePlayer(b) - scorePlayer(a));
  const teamA: Player[] = [];
  const teamB: Player[] = [];

  ordered.forEach((player) => {
    const totalA = teamA.reduce((sum, item) => sum + scorePlayer(item), 0);
    const totalB = teamB.reduce((sum, item) => sum + scorePlayer(item), 0);
    const needsKeeperA = !teamA.some((item) => playerPosition(item) === "Porteria");
    const needsKeeperB = !teamB.some((item) => playerPosition(item) === "Porteria");

    if (playerPosition(player) === "Porteria" && needsKeeperA !== needsKeeperB) {
      (needsKeeperA ? teamA : teamB).push(player);
      return;
    }

    if (teamA.length < teamB.length || (teamA.length === teamB.length && totalA <= totalB)) {
      teamA.push(player);
    } else {
      teamB.push(player);
    }
  });

  return separateGoalkeepers({ teamA, teamB });
}

function randomTeams(players: Player[]) {
  const shuffled = [...players]
    .map((player) => ({ player, order: Math.random() }))
    .sort((a, b) => a.order - b.order)
    .map((item) => item.player);

  return separateGoalkeepers({
    teamA: shuffled.filter((_, index) => index % 2 === 0),
    teamB: shuffled.filter((_, index) => index % 2 === 1),
  });
}

function separateGoalkeepers(teams: { teamA: Player[]; teamB: Player[] }) {
  const keepersA = teams.teamA.filter((player) => playerPosition(player) === "Porteria");
  const keepersB = teams.teamB.filter((player) => playerPosition(player) === "Porteria");

  if ((keepersA.length === 0 && keepersB.length === 0) || (keepersA.length > 0 && keepersB.length > 0)) return teams;

  const sourceKey = keepersA.length > 0 ? "teamA" : "teamB";
  const targetKey = sourceKey === "teamA" ? "teamB" : "teamA";
  const sourceTeam = teams[sourceKey];
  const targetTeam = teams[targetKey];
  const keeperToMove = sourceTeam.find((player) => playerPosition(player) === "Porteria");
  const fieldPlayerToSwap = targetTeam.find((player) => playerPosition(player) !== "Porteria");

  if (!keeperToMove) return teams;

  const nextSource = sourceTeam.filter((player) => player.id !== keeperToMove.id);
  const nextTarget = targetTeam.filter((player) => player.id !== fieldPlayerToSwap?.id);

  if (fieldPlayerToSwap) nextSource.push(fieldPlayerToSwap);
  nextTarget.push(keeperToMove);

  return sourceKey === "teamA"
    ? { teamA: nextSource, teamB: nextTarget }
    : { teamA: nextTarget, teamB: nextSource };
}

function savedTeams(match: Match, players: Player[], confirmedIds: string[]) {
  if (!match.teamA?.length || !match.teamB?.length) return undefined;

  const teamA = match.teamA
    .filter((playerId) => confirmedIds.includes(playerId))
    .map((playerId) => players.find((player) => player.id === playerId))
    .filter((player): player is Player => Boolean(player));
  const teamB = match.teamB
    .filter((playerId) => confirmedIds.includes(playerId))
    .map((playerId) => players.find((player) => player.id === playerId))
    .filter((player): player is Player => Boolean(player));
  const assigned = new Set([...teamA, ...teamB].map((player) => player.id));
  const unassigned = players.filter((player) => confirmedIds.includes(player.id) && !assigned.has(player.id));

  unassigned.forEach((player) => {
    if (teamA.length <= teamB.length) {
      teamA.push(player);
    } else {
      teamB.push(player);
    }
  });

  return separateGoalkeepers({ teamA, teamB });
}

function reserveCapacity(match: Match) {
  return match.reservesAttend ? Math.max(0, Math.floor(match.reserveLimit ?? 0)) : 0;
}

function orderedGoingPlayers(match: Match) {
  return match.players
    .map((entry, index) => ({ entry, index }))
    .filter(({ entry }) => entry.status === "voy")
    .sort((a, b) => {
      const timeA = a.entry.joinedAt ? Date.parse(a.entry.joinedAt) || 0 : a.index;
      const timeB = b.entry.joinedAt ? Date.parse(b.entry.joinedAt) || 0 : b.index;
      return timeA - timeB || a.index - b.index;
    });
}

function matchPlayingIds(match: Match) {
  return orderedGoingPlayers(match)
    .slice(0, match.targetPlayers)
    .map(({ entry }) => entry.playerId);
}

function matchPayingIds(match: Match) {
  return orderedGoingPlayers(match)
    .slice(0, match.targetPlayers + reserveCapacity(match))
    .map(({ entry }) => entry.playerId);
}

function nextPayer(players: Player[], matches: Match[], activeMatch: Match, confirmedIds: string[]) {
  if (confirmedIds.length === 0) return undefined;

  const orderedIds = players.map((player) => player.id);
  const pickAfter = (lastPayerId: string | undefined, candidateIds: string[]) => {
    const previousIndex = lastPayerId ? orderedIds.indexOf(lastPayerId) : -1;
    const startIndex = previousIndex >= 0 ? previousIndex + 1 : 0;

    for (let offset = 0; offset < orderedIds.length; offset += 1) {
      const candidateId = orderedIds[(startIndex + offset) % orderedIds.length];
      if (candidateIds.includes(candidateId)) return candidateId;
    }

    return candidateIds[0];
  };

  const orderedMatches = matches
    .map((match, index) => ({ index, match }))
    .sort((a, b) => {
      const dateDiff = new Date(a.match.date).getTime() - new Date(b.match.date).getTime();
      return dateDiff === 0 ? a.index - b.index : dateDiff;
    });

  let lastPayerId: string | undefined;

  for (const { match } of orderedMatches) {
    if (match.id === activeMatch.id) break;
    const matchConfirmedIds = matchPayingIds(match);
    if (matchConfirmedIds.length === 0) continue;
    lastPayerId = match.payerId && matchConfirmedIds.includes(match.payerId) ? match.payerId : pickAfter(lastPayerId, matchConfirmedIds);
  }

  return pickAfter(lastPayerId, confirmedIds);
}

export default function Home() {
  const [players, setPlayers] = useState<Player[]>(seedPlayers);
  const [venues, setVenues] = useState<Venue[]>(seedVenues);
  const [matches, setMatches] = useState<Match[]>(seedMatches);
  const [activeMatchId, setActiveMatchId] = useState(seedMatches[0].id);
  const [selectedPlayerId, setSelectedPlayerId] = useState<string | null>(null);
  const [newPlayer, setNewPlayer] = useState("");
  const [newVenue, setNewVenue] = useState({ name: "", cost: "56", kind: "futbol7" as MatchKind });
  const [newFacetRatings, setNewFacetRatings] = useState<Record<RatingFacet, number>>(makeFacetRatings());
  const [openQuickForm, setOpenQuickForm] = useState<"player" | "venue" | "team" | null>(null);
  const [showSettings, setShowSettings] = useState(false);
  const [siteSettings, setSiteSettings] = useState<SiteSettings>(defaultSiteSettings);
  const [result, setResult] = useState({ a: "", b: "" });
  const [remoteGroupId, setRemoteGroupId] = useState<string | null>(null);
  const [remoteInviteToken, setRemoteInviteToken] = useState<string | null>(null);
  const [remoteReady, setRemoteReady] = useState(false);
  const [syncStatus, setSyncStatus] = useState<"connecting" | "error" | "live" | "local">("local");
  const [syncError, setSyncError] = useState("");
  const [remoteTeams, setRemoteTeams] = useState<RemoteTeam[]>([]);
  const [teamMembers, setTeamMembers] = useState<RemoteMember[]>([]);
  const [currentRole, setCurrentRole] = useState<MemberRole | null>(null);
  const [currentUserId, setCurrentUserId] = useState<string | null>(null);
  const [authUser, setAuthUser] = useState<User | null>(null);
  const [profileName, setProfileName] = useState("");
  const [newTeamName, setNewTeamName] = useState("Mi equipo pachanguero");
  const [adminInviteToken, setAdminInviteToken] = useState<string | null>(null);
  const [avatarMessage, setAvatarMessage] = useState("");
  const [localHydrated, setLocalHydrated] = useState(false);
  const applyingRemoteRef = useRef(false);
  const saveTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const playerProfileRef = useRef<HTMLDivElement>(null);
  const cameraVideoRef = useRef<HTMLVideoElement>(null);
  const cameraStreamRef = useRef<MediaStream | null>(null);
  const [cameraPlayerId, setCameraPlayerId] = useState<string | null>(null);
  const [cameraError, setCameraError] = useState("");

  function currentPayload(): AppPayload {
    return {
      activeMatchId,
      matches,
      players,
      siteSettings,
      venues,
    };
  }

  function applyPayload(payload: AppPayload) {
    applyingRemoteRef.current = true;
    setPlayers(payload.players);
    setVenues(payload.venues);
    setSiteSettings(payload.siteSettings);
    setMatches(payload.matches);
    setActiveMatchId(payload.activeMatchId);
    window.setTimeout(() => {
      applyingRemoteRef.current = false;
    }, 0);
  }

  function isAnonymousAuthUser(user: User | null) {
    return Boolean(user && (user as User & { is_anonymous?: boolean }).is_anonymous);
  }

  function authDisplayName(user: User | null) {
    const metadata = user?.user_metadata as { full_name?: string; name?: string } | undefined;
    return metadata?.full_name || metadata?.name || user?.email || "Usuario";
  }

  function updateAuthState(user: User | null) {
    setAuthUser(user);
    setCurrentUserId(user?.id ?? null);
  }

  async function getSignedUser(client: NonNullable<typeof supabase>) {
    const sessionResult = await client.auth.getSession();
    const user = sessionResult.data.session?.user ?? null;
    updateAuthState(user);
    return user;
  }

  async function ensureRegisteredUser(client: NonNullable<typeof supabase>) {
    const user = await getSignedUser(client);
    if (!user || isAnonymousAuthUser(user)) {
      throw new Error("Entra con Google para crear equipos o ser admin.");
    }

    return user.id;
  }

  async function ensureInvitedUser(client: NonNullable<typeof supabase>) {
    return ensureRegisteredUser(client);
  }

  async function signInWithGoogle() {
    if (!supabase) {
      setSyncStatus("error");
      setSyncError("Supabase no está configurado.");
      return;
    }

    if (!googleClientId) {
      setSyncStatus("error");
      setSyncError("Falta NEXT_PUBLIC_GOOGLE_CLIENT_ID.");
      return;
    }

    const rawNonce = createGoogleRawNonce();
    const hashedNonce = await sha256Hex(rawNonce);
    localStorage.setItem(googleAuthNonceKey, rawNonce);
    localStorage.setItem(googleAuthReturnKey, window.location.href);

    const authUrl = new URL("https://accounts.google.com/o/oauth2/v2/auth");
    authUrl.searchParams.set("client_id", googleClientId);
    authUrl.searchParams.set("redirect_uri", `${window.location.origin}/auth/google`);
    authUrl.searchParams.set("response_type", "id_token");
    authUrl.searchParams.set("scope", "openid email profile");
    authUrl.searchParams.set("nonce", hashedNonce);
    authUrl.searchParams.set("prompt", "select_account");

    window.location.assign(authUrl.toString());
  }

  async function signOut() {
    if (!supabase) return;

    await supabase.auth.signOut();
    updateAuthState(null);
    setRemoteGroupId(null);
    setRemoteInviteToken(null);
    setRemoteReady(false);
    setRemoteTeams([]);
    setTeamMembers([]);
    setCurrentRole(null);
    setSyncStatus("local");
    setSyncError("");
  }

  async function loadTeamMembers(client: NonNullable<typeof supabase>, groupId: string) {
    const members = await client
      .from("pachanga_group_members")
      .select("user_id, role, display_name")
      .eq("group_id", groupId)
      .order("created_at", { ascending: true });

    if (members.error) throw new Error(members.error.message);

    setTeamMembers(
      (members.data ?? []).map((member, index) => ({
        displayName: displayName(String(member.display_name || `Jugador ${index + 1}`)),
        role: (member.role as MemberRole | null) ?? "player",
        userId: String(member.user_id),
      })),
    );

    const ownMember = (members.data ?? []).find((member) => String(member.user_id) === currentUserId);
    if (ownMember?.display_name) setProfileName(displayName(String(ownMember.display_name)));
  }

  function prettyTeamParams(team: RemoteTeam, extra?: Record<string, string | undefined>) {
    const params = new URLSearchParams();
    params.set("equipo", team.teamCode);
    params.set("i", compactUuid(team.inviteToken));
    Object.entries(extra ?? {}).forEach(([key, value]) => {
      if (value) params.set(key, value);
    });
    return params;
  }

  async function loadTeams(client: NonNullable<typeof supabase>, preferredGroupId?: string | null, preferredTeamCode?: string | null) {
    const memberships = await client
      .from("pachanga_group_members")
      .select("group_id, role, pachanga_groups(id, name, team_code, invite_token, payload)")
      .order("created_at", { ascending: true });

    if (memberships.error) throw new Error(memberships.error.message);

    const teams = (memberships.data ?? [])
      .map((membership) => {
        const group = Array.isArray(membership.pachanga_groups)
          ? membership.pachanga_groups[0]
          : membership.pachanga_groups;
        if (!group) return null;

        return {
          id: String(group.id),
          inviteToken: String(group.invite_token),
          name: String(group.name ?? "Equipo pachanguero"),
          payload: normalizePayload(group.payload as Partial<AppPayload>),
          role: (membership.role as MemberRole | null) ?? "player",
          teamCode: String(group.team_code ?? group.id).toUpperCase(),
        } satisfies RemoteTeam;
      })
      .filter((team): team is RemoteTeam => Boolean(team));

    setRemoteTeams(teams);

    const selectedTeam =
      teams.find((team) => team.id === preferredGroupId) ??
      teams.find((team) => team.teamCode === preferredTeamCode?.toUpperCase()) ??
      teams[0];
    if (!selectedTeam) {
      setRemoteGroupId(null);
      setRemoteInviteToken(null);
      setCurrentRole(null);
      setTeamMembers([]);
      setRemoteReady(false);
      setSyncStatus("local");
      return;
    }

    setRemoteGroupId(selectedTeam.id);
    setRemoteInviteToken(selectedTeam.inviteToken);
    setCurrentRole(selectedTeam.role);
    setAdminInviteToken(null);
    applyPayload(selectedTeam.payload);
    const currentParams = new URLSearchParams(window.location.search);
    const sharedMatchId = expandCompactUuid(currentParams.get("p") ?? currentParams.get("partido"));
    if (sharedMatchId && selectedTeam.payload.matches.some((match) => match.id === sharedMatchId)) {
      setActiveMatchId(sharedMatchId);
    }
    setRemoteReady(true);
    setSyncStatus("live");
    setSyncError("");
    await loadTeamMembers(client, selectedTeam.id);

    const nextParams = prettyTeamParams(selectedTeam, { p: sharedMatchId ? compactUuid(sharedMatchId) : undefined });
    window.history.replaceState(null, "", `${window.location.pathname}?${nextParams.toString()}`);
  }

  useEffect(() => {
    setProfileName(localStorage.getItem(profileNameKey) ?? "");
    const saved = localStorage.getItem(storageKey);
    if (!saved) {
      setLocalHydrated(true);
      return;
    }

    try {
      const parsed = JSON.parse(saved) as { players: Player[]; venues?: Venue[]; matches: Match[]; activeMatchId: string; siteSettings?: SiteSettings };
      const payload = normalizePayload(parsed);
      setPlayers(payload.players);
      setVenues(payload.venues);
      setSiteSettings(payload.siteSettings);
      setMatches(payload.matches);
      setActiveMatchId(payload.activeMatchId);
    } catch {
      localStorage.removeItem(storageKey);
    }
    setLocalHydrated(true);
  }, []);

  useEffect(() => {
    localStorage.setItem(profileNameKey, profileName.trim());
  }, [profileName]);

  useEffect(() => {
    if (!supabase) return;

    const client = supabase;
    let cancelled = false;

    void client.auth.getSession().then(({ data }) => {
      if (cancelled) return;
      updateAuthState(data.session?.user ?? null);
    });

    const {
      data: { subscription },
    } = client.auth.onAuthStateChange((_event, session) => {
      updateAuthState(session?.user ?? null);
      const userName = authDisplayName(session?.user ?? null);
      if (session?.user && !profileName.trim() && userName !== "Usuario") {
        setProfileName(displayName(userName));
      }
    });

    return () => {
      cancelled = true;
      subscription.unsubscribe();
    };
  }, [profileName]);

  useEffect(() => {
    if (!localHydrated || !supabase) return;

    const client = supabase;
    let cancelled = false;

    async function connectGroup() {
      setSyncStatus("connecting");
      setSyncError("");

      try {
        const params = new URLSearchParams(window.location.search);
        const inviteToken = expandCompactUuid(params.get("i") ?? params.get("invite"));
        const adminInviteToken = expandCompactUuid(params.get("a") ?? params.get("admin"));
        const teamCode = params.get("equipo");
        let groupId = params.get("grupo");

        if (adminInviteToken) {
          const userId = await ensureRegisteredUser(client);
          const user = authUser?.id === userId ? authUser : (await getSignedUser(client));
          const adminJoinResult = await client.rpc("accept_pachanga_admin_invite", {
            admin_token: adminInviteToken,
            member_name: profileName.trim() || authDisplayName(user) || "Admin",
          });
          if (adminJoinResult.error || !adminJoinResult.data) throw new Error(adminJoinResult.error?.message ?? "No se pudo aceptar la invitación de admin");
          groupId = String(adminJoinResult.data);
        } else if (inviteToken) {
          await ensureInvitedUser(client);
          const joinResult = await client.rpc("join_pachanga_team", {
            member_name: profileName.trim() || "Jugador",
            token: inviteToken,
          });
          if (joinResult.error || !joinResult.data) throw new Error(joinResult.error?.message ?? "No se pudo entrar al grupo");
          groupId = String(joinResult.data);
        } else {
          const user = await getSignedUser(client);
          if (!user) {
            if (!cancelled) {
              setRemoteGroupId(null);
              setRemoteInviteToken(null);
              setRemoteReady(false);
              setRemoteTeams([]);
              setTeamMembers([]);
              setCurrentRole(null);
              setSyncStatus("local");
            }
            return;
          }
        }

        await loadTeams(client, groupId, teamCode);

        if (cancelled) return;
      } catch (error) {
        setSyncStatus("error");
        setSyncError(error instanceof Error ? error.message : "No se pudo cargar el equipo");
        return;
      }
    }

    void connectGroup();

    return () => {
      cancelled = true;
    };
  }, [localHydrated]);

  useEffect(() => {
    if (!supabase || !remoteGroupId || !remoteReady) return;

    const client = supabase;
    const channel = client
      .channel(`pachanga-group-${remoteGroupId}`)
      .on(
        "postgres_changes",
        { event: "UPDATE", schema: "public", table: "pachanga_groups", filter: `id=eq.${remoteGroupId}` },
        (payload) => {
          const nextPayload = normalizePayload(payload.new.payload as Partial<AppPayload>);
          applyPayload(nextPayload);
        },
      )
      .subscribe();

    return () => {
      void client.removeChannel(channel);
    };
  }, [remoteGroupId, remoteReady]);

  useEffect(() => {
    localStorage.setItem(storageKey, JSON.stringify({ players, venues, matches, activeMatchId, siteSettings }));

    if (!supabase || !remoteGroupId || !remoteReady || applyingRemoteRef.current) return;
    const client = supabase;
    if (saveTimerRef.current) clearTimeout(saveTimerRef.current);
    saveTimerRef.current = setTimeout(() => {
      void client
        .from("pachanga_groups")
        .update({ payload: currentPayload() })
        .eq("id", remoteGroupId);
    }, 450);
  }, [players, venues, matches, activeMatchId, siteSettings]);

  useEffect(() => {
    if (!selectedPlayerId) return;
    playerProfileRef.current?.scrollIntoView({ behavior: "smooth", block: "start" });
  }, [selectedPlayerId]);

  useEffect(() => {
    if (!cameraPlayerId) return;

    let cancelled = false;
    cameraStreamRef.current?.getTracks().forEach((track) => track.stop());
    cameraStreamRef.current = null;

    async function startCamera() {
      if (!navigator.mediaDevices?.getUserMedia) {
        setCameraError("Este navegador no permite usar la cámara aquí.");
        return;
      }

      try {
        const stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: "user" }, audio: false });
        if (cancelled) {
          stream.getTracks().forEach((track) => track.stop());
          return;
        }
        cameraStreamRef.current = stream;
        if (cameraVideoRef.current) {
          cameraVideoRef.current.srcObject = stream;
          await cameraVideoRef.current.play().catch(() => undefined);
        }
      } catch {
        setCameraError("No se pudo abrir la cámara.");
      }
    }

    void startCamera();

    return () => {
      cancelled = true;
      cameraStreamRef.current?.getTracks().forEach((track) => track.stop());
      cameraStreamRef.current = null;
    };
  }, [cameraPlayerId]);

  const activeMatch = matches.find((match) => match.id === activeMatchId) ?? matches[0];
  const activeKind = activeMatch.kind ?? "futbol7";
  const activeVenue = venues.find((venue) => venue.id === activeMatch.venueId);
  const reserveLimit = reserveCapacity(activeMatch);
  const orderedGoingEntries = orderedGoingPlayers(activeMatch);
  const playingEntries = orderedGoingEntries.slice(0, activeMatch.targetPlayers);
  const reserveEntries = orderedGoingEntries.slice(activeMatch.targetPlayers, activeMatch.targetPlayers + reserveLimit);
  const waitingEntries = orderedGoingEntries.slice(activeMatch.targetPlayers + reserveLimit);
  const confirmedIds = playingEntries.map(({ entry }) => entry.playerId);
  const reserveIds = reserveEntries.map(({ entry }) => entry.playerId);
  const waitingIds = waitingEntries.map(({ entry }) => entry.playerId);
  const payingIds = [...confirmedIds, ...reserveIds];
  const confirmedPlayers = players.filter((player) => confirmedIds.includes(player.id));
  const reservePlayers = reserveIds.map((playerId) => players.find((player) => player.id === playerId)).filter((player): player is Player => Boolean(player));
  const waitingPlayers = waitingIds.map((playerId) => players.find((player) => player.id === playerId)).filter((player): player is Player => Boolean(player));
  const openMatches = matches.filter((match) => match.configured && match.scoreA === undefined && !match.closed);
  const closedMatches = matches
    .filter((match) => match.scoreA !== undefined)
    .sort((a, b) => new Date(b.date).getTime() - new Date(a.date).getTime());
  const doubtfulCount = activeMatch.players.filter((entry) => entry.status === "duda").length;
  const missing = Math.max(activeMatch.targetPlayers - confirmedPlayers.length, 0);
  const fieldCost = activeMatch.fieldCost ?? 0;
  const sharePerPlayer = payingIds.length > 0 ? fieldCost / payingIds.length : 0;
  const paidCount = activeMatch.players.filter((entry) => payingIds.includes(entry.playerId) && entry.paid).length;
  const suggestedPayerId = nextPayer(players, matches, activeMatch, payingIds);
  const payerId = activeMatch.payerId && payingIds.includes(activeMatch.payerId) ? activeMatch.payerId : suggestedPayerId;
  const payer = players.find((player) => player.id === payerId);
  const balancedLineup = useMemo(() => balanceTeams(confirmedPlayers), [confirmedPlayers]);
  const suggested = savedTeams(activeMatch, players, confirmedIds) ?? balancedLineup;
  const lineupClosed = activeMatch.lineupClosed ?? false;
  const matchFinalized = Boolean(activeMatch.closed || activeMatch.scoreA !== undefined);
  const matchConfigured = Boolean(activeMatch.configured);
  const scoreAValue = result.a.trim() === "" ? undefined : Number(result.a);
  const scoreBValue = result.b.trim() === "" ? undefined : Number(result.b);
  const resultIsReady =
    Number.isInteger(scoreAValue) &&
    Number.isInteger(scoreBValue) &&
    Number(scoreAValue) >= 0 &&
    Number(scoreBValue) >= 0;

  useEffect(() => {
    setResult({
      a: activeMatch.scoreA === undefined ? "" : String(activeMatch.scoreA),
      b: activeMatch.scoreB === undefined ? "" : String(activeMatch.scoreB),
    });
  }, [activeMatch.id, activeMatch.scoreA, activeMatch.scoreB]);

  function updateMatch(next: Match) {
    setMatches((current) => current.map((match) => (match.id === next.id ? next : match)));
  }

  function openPlayerProfile(playerId: string) {
    setSelectedPlayerId(playerId);
  }

  function setStatus(playerId: string, status: MatchPlayer["status"]) {
    const player = players.find((item) => item.id === playerId);
    const canChangeStatus = matchConfigured && (isDemoMode || canUseAdminControls || (hasRealTeam && isRegisteredUser && player?.ownerUserId === currentUserId));
    if (!canChangeStatus) return;
    if (matchFinalized && !canUseAdminControls) return;
    if (status === "voy" && (player?.injured || player?.inactive)) return;
    const existing = activeMatch.players.find((entry) => entry.playerId === playerId);
    if (existing?.status === "voy" && status !== "voy") {
      const confirmed = window.confirm("Si cambias de “Voy”, perderás tu posición. Si hay reservas, el primero ocupará tu plaza. ¿Continuar?");
      if (!confirmed) return;
    }
    const joinedAt = status === "voy" ? (existing?.status === "voy" ? existing.joinedAt : new Date().toISOString()) : undefined;
    const nextPlayers = existing
      ? activeMatch.players.map((entry) => (entry.playerId === playerId ? { ...entry, status, joinedAt, paid: status === "voy" ? entry.paid : false } : entry))
      : [...activeMatch.players, { playerId, status, joinedAt, paid: false }];
    const wasConfirmed = existing?.status === "voy";
    const willBeConfirmed = status === "voy";
    const previousGoals = activeMatch.scorers?.find((entry) => entry.playerId === playerId)?.goals ?? 0;
    const finalizedScoreA = activeMatch.scoreA ?? 0;
    const finalizedScoreB = activeMatch.scoreB ?? 0;
    const finalizedWinningIds = finalizedScoreA === finalizedScoreB ? [] : finalizedScoreA > finalizedScoreB ? activeMatch.teamA ?? [] : activeMatch.teamB ?? [];
    const nextMatch = {
      ...activeMatch,
      players: nextPlayers,
      scorers: matchFinalized && wasConfirmed && !willBeConfirmed ? activeMatch.scorers?.filter((entry) => entry.playerId !== playerId) : activeMatch.scorers,
    };

    updateMatch(nextMatch);

    if (matchFinalized && wasConfirmed !== willBeConfirmed) {
      const direction = willBeConfirmed ? 1 : -1;
      setPlayers((current) =>
        current.map((item) =>
          item.id === playerId
            ? {
                ...item,
                appearances: Math.max(0, item.appearances + direction),
                goals: Math.max(0, item.goals + direction * previousGoals),
                wins: Math.max(0, item.wins + (finalizedWinningIds.includes(playerId) ? direction : 0)),
              }
            : item,
        ),
      );
    }
  }

  function setPlayerInjured(playerId: string, injured: boolean) {
    updatePlayer(playerId, { injured });
    if (!injured) return;

    setMatches((current) =>
      current.map((match) => {
        const existing = match.players.find((entry) => entry.playerId === playerId);
        if (!existing) return match;

        return {
          ...match,
          players: match.players.map((entry) =>
            entry.playerId === playerId
              ? { ...entry, status: "no", joinedAt: undefined, paid: false }
              : entry,
          ),
        };
      }),
    );
  }

  function deactivatePlayer(playerId: string) {
    if (!canUseAdminControls) return;
    const player = players.find((item) => item.id === playerId);
    if (!player) return;
    if (!window.confirm(`¿Eliminar a ${playerDisplayName(player)} del grupo?`)) return;
    if (!window.confirm("Confirmación final: conservará ranking e histórico, pero no podrá apuntarse.")) return;

    updatePlayer(playerId, { inactive: true, injured: false });
    setMatches((current) =>
      current.map((match) => {
        if (match.closed || match.scoreA !== undefined) return match;
        const existing = match.players.find((entry) => entry.playerId === playerId);
        if (!existing) return match;

        return {
          ...match,
          payerId: match.payerId === playerId ? undefined : match.payerId,
          players: match.players.map((entry) =>
            entry.playerId === playerId
              ? { ...entry, status: "no", joinedAt: undefined, paid: false }
              : entry,
          ),
          scorers: match.scorers?.filter((entry) => entry.playerId !== playerId),
          teamA: match.teamA?.filter((id) => id !== playerId),
          teamB: match.teamB?.filter((id) => id !== playerId),
        };
      }),
    );
  }

  function togglePaid(playerId: string) {
    if (!matchConfigured) return;
    updateMatch({
      ...activeMatch,
      players: activeMatch.players.map((entry) => (entry.playerId === playerId ? { ...entry, paid: !entry.paid } : entry)),
    });
  }

  function addPlayer(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!canUseAdminControls) return;
    const name = displayName(newPlayer);
    if (!name) return;

    const player: Player = {
      id: id(),
      name,
      phone: "",
      goalkeeperOnly: false,
      injured: false,
      rating: 5,
      ratings: [],
      ratingVotes: [],
      position: defaultPositionForKind(activeKind),
      goals: 0,
      assists: 0,
      appearances: 0,
      wins: 0,
      lateCancels: 0,
    };

    setPlayers((current) => [...current, player]);
    setNewPlayer("");
    setOpenQuickForm(null);
  }

  function createMatch() {
    if (!canUseAdminControls) return;
    const existingDraft = matches.find((match) => !match.configured && !match.closed && match.scoreA === undefined);
    if (existingDraft) {
      setActiveMatchId(existingDraft.id);
      return;
    }

    const defaultVenue = venues.find((venue) => venue.id === activeMatch.venueId) ?? venues[0];
    const nextKind = activeMatch.kind ?? defaultVenue?.kind ?? "futbol7";
    const next: Match = {
      id: id(),
      title: "Nueva pachanga",
      date: nextMatchDate(activeMatch.date),
      place: defaultVenue?.name ?? "Campo por confirmar",
      configured: false,
      venueId: defaultVenue?.id,
      kind: nextKind,
      targetPlayers: matchKinds[nextKind].targetPlayers,
      fieldCost: activeMatch.fieldCost ?? defaultVenue?.defaultCost ?? 56,
      payerId: undefined,
      players: [],
      reservesAttend: activeMatch.reservesAttend ?? false,
      reserveLimit: activeMatch.reserveLimit ?? 0,
    };
    setMatches((current) => [next, ...current]);
    setActiveMatchId(next.id);
  }

  function toggleLineupClosed() {
    if (!canUseAdminControls) return;
    if (matchFinalized) return;
    updateMatch({
      ...activeMatch,
      lineupClosed: !lineupClosed,
      teamA: suggested.teamA.map((player) => player.id),
      teamB: suggested.teamB.map((player) => player.id),
    });
  }

  function applyRandomTeams() {
    if (!canUseAdminControls) return;
    if (lineupClosed) return;
    if (matchFinalized) return;
    const next = randomTeams(confirmedPlayers);
    updateMatch({
      ...activeMatch,
      teamA: next.teamA.map((player) => player.id),
      teamB: next.teamB.map((player) => player.id),
    });
  }

  function applyBalancedTeams() {
    if (!canUseAdminControls) return;
    if (lineupClosed) return;
    if (matchFinalized) return;
    updateMatch({
      ...activeMatch,
      teamA: balancedLineup.teamA.map((player) => player.id),
      teamB: balancedLineup.teamB.map((player) => player.id),
    });
  }

  function assignPlayerTeam(playerId: string, team: "A" | "B") {
    if (!canUseAdminControls) return;
    if (lineupClosed) return;
    if (matchFinalized) return;
    const baseTeamA = suggested.teamA.map((player) => player.id).filter((id) => id !== playerId);
    const baseTeamB = suggested.teamB.map((player) => player.id).filter((id) => id !== playerId);

    updateMatch({
      ...activeMatch,
      teamA: team === "A" ? [...baseTeamA, playerId] : baseTeamA,
      teamB: team === "B" ? [...baseTeamB, playerId] : baseTeamB,
    });
  }

  function setPlayerGoals(playerId: string, goals: number) {
    if (!canUseAdminControls) return;
    if (!resultIsReady) return;

    const scorers = activeMatch.scorers ?? [];
    const isTeamA = suggested.teamA.some((player) => player.id === playerId);
    const teamPlayers = isTeamA ? suggested.teamA : suggested.teamB;
    const teamLimit = Number(isTeamA ? scoreAValue : scoreBValue);
    const currentOtherGoals = teamPlayers.reduce(
      (sum, player) => sum + (player.id === playerId ? 0 : scorers.find((entry) => entry.playerId === player.id)?.goals ?? 0),
      0,
    );
    const nextGoals = Math.max(0, Math.min(goals, Math.max(teamLimit - currentOtherGoals, 0)));
    const existing = scorers.find((entry) => entry.playerId === playerId);
    const nextScorers = existing
      ? scorers.map((entry) => (entry.playerId === playerId ? { ...entry, goals: nextGoals } : entry))
      : [...scorers, { playerId, goals: nextGoals }];
    const cleanScorers = nextScorers.filter((entry) => entry.goals > 0);
    const goalDelta = nextGoals - (existing?.goals ?? 0);

    updateMatch({
      ...activeMatch,
      scorers: cleanScorers,
    });

    if (matchFinalized && goalDelta !== 0) {
      setPlayers((current) =>
        current.map((player) => (player.id === playerId ? { ...player, goals: Math.max(0, player.goals + goalDelta) } : player)),
      );
    }
  }

  function scorerRows(teamPlayers: Player[], variant: "team-a" | "team-b") {
    const teamLimit = Number(variant === "team-a" ? scoreAValue : scoreBValue);
    const assignedTeamGoals = teamPlayers.reduce(
      (sum, teamPlayer) => sum + (activeMatch.scorers?.find((entry) => entry.playerId === teamPlayer.id)?.goals ?? 0),
      0,
    );
    const teamHasNoGoals = resultIsReady && teamLimit === 0;
    const teamGoalsComplete = resultIsReady && assignedTeamGoals >= teamLimit;

    return teamPlayers
      .map((player) => {
        const goals = activeMatch.scorers?.find((entry) => entry.playerId === player.id)?.goals ?? 0;
        if (!resultIsReady || (teamHasNoGoals && goals === 0) || (teamGoalsComplete && goals === 0)) return null;

        return (
          <div className={`scorer-row ${variant}-row`} key={player.id}>
            <span>
              {player.inactive ? (
                <span className="inline-inactive" title="Ya no está en el grupo" aria-label="Ya no está en el grupo">
                  <UserOffLogo />
                </span>
              ) : null}
              {player.injured ? (
                <span className="inline-injury" title="Jugador lesionado" aria-label="Jugador lesionado">
                  <HospitalLogo />
                </span>
              ) : null}
              {playerDisplayName(player)}
            </span>
            <button type="button" disabled={goals === 0} onClick={() => setPlayerGoals(player.id, goals - 1)}>-</button>
            <b>{goals}</b>
            <button type="button" disabled={!resultIsReady || assignedTeamGoals >= teamLimit} onClick={() => setPlayerGoals(player.id, goals + 1)}>+</button>
          </div>
        );
      })
      .filter(Boolean);
  }

  function finalizeMatch() {
    if (!canUseAdminControls) return;
    if (matchFinalized) return;
    if (!resultIsReady) return;

    const scoreA = Number(scoreAValue);
    const scoreB = Number(scoreBValue);
    const winners = scoreA === scoreB ? [] : scoreA > scoreB ? suggested.teamA.map((player) => player.id) : suggested.teamB.map((player) => player.id);
    const previousGoalsByPlayer = new Map((activeMatch.scorers ?? []).map((entry) => [entry.playerId, entry.goals]));
    const shouldApplyMatchStats = !activeMatch.closed;

    setPlayers((current) =>
      current.map((player) =>
        confirmedIds.includes(player.id)
          ? {
              ...player,
              appearances: shouldApplyMatchStats ? player.appearances + 1 : player.appearances,
              goals: shouldApplyMatchStats ? player.goals + (previousGoalsByPlayer.get(player.id) ?? 0) : player.goals,
              wins: shouldApplyMatchStats && winners.includes(player.id) ? player.wins + 1 : player.wins,
            }
          : player,
      ),
    );

    updateMatch({
      ...activeMatch,
      scoreA,
      scoreB,
      closed: true,
      payerId,
      teamA: suggested.teamA.map((player) => player.id),
      teamB: suggested.teamB.map((player) => player.id),
    });
  }

  function deleteClosedMatch(matchId: string) {
    if (!canUseAdminControls) return;
    const match = matches.find((item) => item.id === matchId);
    if (!match) return;

    const confirmedMatchIds = match.players.filter((entry) => entry.status === "voy").map((entry) => entry.playerId);
    const scoreA = match.scoreA ?? 0;
    const scoreB = match.scoreB ?? 0;
    const winningIds = scoreA === scoreB ? [] : scoreA > scoreB ? match.teamA ?? [] : match.teamB ?? [];
    const goalsByPlayer = new Map((match.scorers ?? []).map((entry) => [entry.playerId, entry.goals]));

    setPlayers((current) =>
      current.map((player) =>
        confirmedMatchIds.includes(player.id)
          ? {
              ...player,
              appearances: Math.max(0, player.appearances - 1),
              goals: Math.max(0, player.goals - (goalsByPlayer.get(player.id) ?? 0)),
              wins: Math.max(0, player.wins - (winningIds.includes(player.id) ? 1 : 0)),
            }
          : player,
      ),
    );

    const remainingMatches = matches.filter((item) => item.id !== matchId);
    const fallbackKind = match.kind ?? "futbol7";
    const fallbackVenue = venues.find((venue) => venue.id === match.venueId) ?? venues[0];
    const replacementMatch: Match = {
      id: id(),
      title: "Nueva pachanga",
      date: nextMatchDate(match.date),
      place: fallbackVenue?.name ?? "Campo por confirmar",
      venueId: fallbackVenue?.id,
      kind: fallbackKind,
      targetPlayers: matchKinds[fallbackKind].targetPlayers,
      fieldCost: match.fieldCost ?? fallbackVenue?.defaultCost ?? 56,
      players: [],
      reservesAttend: match.reservesAttend ?? false,
      reserveLimit: match.reserveLimit ?? 0,
    };
    const nextMatches = remainingMatches.length > 0 ? remainingMatches : [replacementMatch];
    const nextActiveMatchId = activeMatchId === matchId ? nextMatches[0].id : activeMatchId;

    setActiveMatchId(nextActiveMatchId);
    setMatches(nextMatches);
  }

  function deleteMatch(matchId: string) {
    if (!canUseAdminControls) return;
    const match = matches.find((item) => item.id === matchId);
    if (!match) return;
    if (!window.confirm("¿Borrar este partido?")) return;
    if (!window.confirm("Confirmación final: se eliminará definitivamente.")) return;

    if (match.scoreA !== undefined || match.closed) {
      deleteClosedMatch(matchId);
      return;
    }

    const remainingMatches = matches.filter((item) => item.id !== matchId);
    const fallbackKind = match.kind ?? "futbol7";
    const fallbackVenue = venues.find((venue) => venue.id === match.venueId) ?? venues[0];
    const replacementMatch: Match = {
      id: id(),
      title: "Nueva pachanga",
      date: nextMatchDate(match.date),
      place: fallbackVenue?.name ?? "Campo por confirmar",
      venueId: fallbackVenue?.id,
      kind: fallbackKind,
      targetPlayers: matchKinds[fallbackKind].targetPlayers,
      fieldCost: match.fieldCost ?? fallbackVenue?.defaultCost ?? 56,
      players: [],
      reservesAttend: match.reservesAttend ?? false,
      reserveLimit: match.reserveLimit ?? 0,
    };
    const nextMatches = remainingMatches.length > 0 ? remainingMatches : [replacementMatch];
    const nextActiveMatchId = activeMatchId === matchId ? nextMatches[0].id : activeMatchId;

    setActiveMatchId(nextActiveMatchId);
    setMatches(nextMatches);
  }

  const rankedPlayers = [...players].sort((a, b) => scorePlayer(b) - scorePlayer(a));
  const sortedPlayers = [...players].sort((a, b) => {
    const statusOrder: Record<MatchPlayer["status"] | "sin", number> = { voy: 0, duda: 1, no: 2, sin: 3 };
    const statusA = a.injured || a.inactive ? "no" : activeMatch.players.find((entry) => entry.playerId === a.id)?.status ?? "sin";
    const statusB = b.injured || b.inactive ? "no" : activeMatch.players.find((entry) => entry.playerId === b.id)?.status ?? "sin";
    return statusOrder[statusA] - statusOrder[statusB] || a.name.localeCompare(b.name, "es");
  });
  const teamAPlayerIds = new Set(suggested.teamA.map((player) => player.id));
  const teamBPlayerIds = new Set(suggested.teamB.map((player) => player.id));
  const reservePlayerIds = new Set(reserveIds);
  const waitingPlayerIds = new Set(waitingIds);
  const sortedTeamA = sortedLineupPlayers(suggested.teamA);
  const sortedTeamB = sortedLineupPlayers(suggested.teamB);
  const otherPlayers = sortedPlayers.filter((player) => !teamAPlayerIds.has(player.id) && !teamBPlayerIds.has(player.id) && !reservePlayerIds.has(player.id) && !waitingPlayerIds.has(player.id));
  const selectedPlayer = selectedPlayerId ? players.find((player) => player.id === selectedPlayerId) : undefined;
  const currentTeam = remoteTeams.find((team) => team.id === remoteGroupId);
  const isDemoMode = !remoteReady && remoteTeams.length === 0;
  const isRegisteredUser = Boolean(authUser && !isAnonymousAuthUser(authUser));
  const hasRealTeam = remoteReady && Boolean(remoteGroupId);
  const canManageTeam = isRegisteredUser && (currentRole === "owner" || currentRole === "admin");
  const canUseAdminControls = hasRealTeam && canManageTeam;
  const canCreateTeam = Boolean(supabase && isRegisteredUser);
  const ownPlayer = currentUserId ? players.find((player) => player.ownerUserId === currentUserId) : undefined;
  const selectedPlayerIsOwn = Boolean(selectedPlayer?.ownerUserId && selectedPlayer.ownerUserId === currentUserId);
  const canEditSelectedPlayer = Boolean(selectedPlayer && (canUseAdminControls || (hasRealTeam && isRegisteredUser && selectedPlayerIsOwn)));
  const canEditMatchSettings = canUseAdminControls && !matchFinalized;
  const canEditLineup = canUseAdminControls && matchConfigured && !lineupClosed && !matchFinalized;
  const matchCanBeSaved = Boolean(
    canUseAdminControls &&
      !matchFinalized &&
      activeMatch.venueId &&
      activeMatch.date &&
      activeMatch.kind &&
      Number.isFinite(fieldCost) &&
      fieldCost >= 0,
  );
  const ratingVoterId = currentUserId ?? `local:${profileName.trim().toLocaleLowerCase("es-ES") || "jugador"}`;
  const selectedRatingHistory = selectedPlayer ? ratingHistory(selectedPlayer) : [];
  const selectedRatingWindow = selectedPlayer ? ratingWindow(selectedPlayer, ratingVoterId) : null;
  const selectedUserVote = selectedRatingWindow?.ownVote;
  const canRateSelectedPlayer = Boolean(
    selectedRatingWindow?.canRate &&
      selectedPlayer &&
      !selectedPlayerIsOwn &&
      (isDemoMode || (hasRealTeam && isRegisteredUser)),
  );
  const ratingWaitMatches = selectedRatingWindow?.waitMatches ?? 0;
  const draftPeerAverage = selectedPlayer
    ? ratingFacets.reduce((sum, facet) => sum + clampRating(newFacetRatings[facet.key] ?? facetAverage(selectedPlayer, facet.key)), 0) / ratingFacets.length
    : 0;
  const selectedRatingStatusText = selectedPlayer && selectedRatingWindow
    ? selectedPlayer.inactive
      ? "Jugador fuera del grupo: valoración bloqueada."
      : selectedPlayerIsOwn
        ? "No puedes votar tu propia ficha."
        : hasRealTeam && !isRegisteredUser
          ? "Entra con Google para valorar a compañeros."
          : selectedRatingWindow.canRate
        ? "Valoraciones abiertas: puedes votar ahora."
        : selectedUserVote
          ? `Cerradas: se reabren cuando juegue ${ratingWaitMatches} partido${ratingWaitMatches === 1 ? "" : "s"} más.`
          : `Cerradas: se abren al completar 3 partidos. Faltan ${ratingWaitMatches}.`
    : "";
  const selectedRatingButtonText = canRateSelectedPlayer
    ? "Guardar valoración"
    : ratingWaitMatches > 0
      ? `Faltan ${ratingWaitMatches} partido${ratingWaitMatches === 1 ? "" : "s"}`
      : "Valoraciones cerradas";

  useEffect(() => {
    if (!selectedPlayer) return;
    const ownVote = ratingHistory(selectedPlayer).filter((vote) => vote.voterId === ratingVoterId).at(-1);
    const nextFacets = ratingFacets.reduce((next, facet) => {
      next[facet.key] = clampRating(ownVote?.facets[facet.key] ?? facetAverage(selectedPlayer, facet.key));
      return next;
    }, {} as Record<RatingFacet, number>);
    setNewFacetRatings(nextFacets);
  }, [selectedPlayerId, ratingVoterId]);

  function updateMatchSettings(next: Match) {
    if (!canEditMatchSettings) return;
    updateMatch(next);
  }

  function saveMatchConfiguration() {
    if (!matchCanBeSaved) return;
    updateMatch({ ...activeMatch, configured: true });
  }

  function updatePlayer(playerId: string, next: Partial<Player>) {
    const player = players.find((item) => item.id === playerId);
    if (!player) return;
    const canEditPlayer = canUseAdminControls || (hasRealTeam && isRegisteredUser && player.ownerUserId === currentUserId);
    if (!canEditPlayer) return;
    setPlayers((current) => current.map((item) => (item.id === playerId ? { ...item, ...next } : item)));
  }

  function addPeerRating(playerId: string) {
    const player = players.find((item) => item.id === playerId);
    if (!player) return;
    if (player.ownerUserId && player.ownerUserId === currentUserId) return;
    if (hasRealTeam && !isRegisteredUser) return;
    const ratingState = ratingWindow(player, ratingVoterId);
    if (!ratingState.canRate) return;

    const vote: RatingVote = {
      id: id(),
      voterId: ratingVoterId,
      voterName: profileName.trim() ? displayName(profileName) : undefined,
      matchCount: player.appearances,
      createdAt: new Date().toISOString(),
      facets: ratingFacets.reduce((next, facet) => {
        next[facet.key] = clampRating(newFacetRatings[facet.key]);
        return next;
      }, {} as Record<RatingFacet, number>),
    };

    setPlayers((current) =>
      current.map((item) => (item.id === playerId ? { ...item, ratingVotes: [...(item.ratingVotes ?? []), vote] } : item)),
    );
  }

  async function uploadAvatar(file: File | undefined, playerId = selectedPlayer?.id) {
    setAvatarMessage("");
    const player = players.find((item) => item.id === playerId);
    const canEditPlayer = Boolean(player && (canUseAdminControls || (hasRealTeam && isRegisteredUser && player.ownerUserId === currentUserId)));
    if (!canEditPlayer) {
      setAvatarMessage("Solo tú o un admin podéis cambiar esta foto.");
      return;
    }
    if (!file || !playerId) return;

    try {
      setAvatarMessage("Recortando foto...");
      const avatar = await avatarDataUrl(file);
      updatePlayer(playerId, { avatar });
      setAvatarMessage("Foto actualizada");
      window.setTimeout(() => setAvatarMessage(""), 1800);
    } catch {
      setAvatarMessage("No se pudo cargar la foto.");
    }
  }

  function stopCamera() {
    cameraStreamRef.current?.getTracks().forEach((track) => track.stop());
    cameraStreamRef.current = null;
    if (cameraVideoRef.current) cameraVideoRef.current.srcObject = null;
    setCameraPlayerId(null);
    setCameraError("");
  }

  function openCamera(playerId: string) {
    const player = players.find((item) => item.id === playerId);
    const canEditPlayer = Boolean(player && (canUseAdminControls || (hasRealTeam && isRegisteredUser && player.ownerUserId === currentUserId)));
    if (!canEditPlayer) {
      setAvatarMessage("Solo tú o un admin podéis cambiar esta foto.");
      return;
    }
    setCameraError("");
    setCameraPlayerId(playerId);
  }

  async function captureCameraAvatar() {
    const video = cameraVideoRef.current;
    if (!video || !cameraPlayerId || video.videoWidth === 0 || video.videoHeight === 0) {
      setCameraError("La cámara todavía no está lista.");
      return;
    }

    const canvas = document.createElement("canvas");
    canvas.width = video.videoWidth;
    canvas.height = video.videoHeight;
    const context = canvas.getContext("2d");
    if (!context) {
      setCameraError("No se pudo capturar la foto.");
      return;
    }

    context.drawImage(video, 0, 0, canvas.width, canvas.height);
    canvas.toBlob((blob) => {
      if (!blob) {
        setCameraError("No se pudo capturar la foto.");
        return;
      }
      void uploadAvatar(new File([blob], "webcam.jpg", { type: "image/jpeg" }), cameraPlayerId);
      stopCamera();
    }, "image/jpeg", 0.9);
  }

  function changeKind(kind: MatchKind) {
    if (!canEditMatchSettings) return;
    updateMatch({ ...activeMatch, kind, targetPlayers: matchKinds[kind].targetPlayers });
  }

  function selectVenue(venueId: string) {
    if (!canEditMatchSettings) return;
    const venue = venues.find((item) => item.id === venueId);
    if (!venue) return;
    const kind = venue.kind ?? activeKind;

    updateMatch({
      ...activeMatch,
      venueId,
      place: venue.name,
      fieldCost: venue.defaultCost,
      kind,
      targetPlayers: matchKinds[kind].targetPlayers,
    });
  }

  function addVenue(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!canUseAdminControls) return;
    const name = newVenue.name.trim();
    if (!name) return;
    const kind = newVenue.kind;

    const venue: Venue = {
      id: id(),
      name,
      defaultCost: Number(newVenue.cost) || 0,
      kind,
    };

    setVenues((current) => [...current, venue]);
    updateMatch({
      ...activeMatch,
      venueId: venue.id,
      place: venue.name,
      fieldCost: venue.defaultCost,
      kind,
      targetPlayers: matchKinds[kind].targetPlayers,
    });
    setNewVenue({ name: "", cost: String(venue.defaultCost || 56), kind });
    setOpenQuickForm(null);
  }

  async function createTeam(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!supabase) return;

    const client = supabase;
    setSyncStatus("connecting");
    setSyncError("");

    try {
      const user = await getSignedUser(client);
      if (!user || isAnonymousAuthUser(user)) throw new Error("Entra con Google para crear equipos o ser admin.");
      const userId = user.id;
      const teamName = newTeamName.trim() || "Mi equipo pachanguero";
      const initialPayload = emptyTeamPayload(teamName);
      const insertResult = await client
        .from("pachanga_groups")
        .insert({ name: teamName, owner_id: userId, payload: initialPayload })
        .select("id, invite_token, name, payload, team_code")
        .single();

      if (insertResult.error || !insertResult.data) throw new Error(insertResult.error?.message ?? "No se pudo crear el equipo");

      const memberResult = await client.from("pachanga_group_members").insert({
        display_name: profileName.trim() || authDisplayName(user),
        group_id: insertResult.data.id,
        role: "owner",
        user_id: userId,
      });

      if (memberResult.error) throw new Error(memberResult.error.message);

      await loadTeams(client, insertResult.data.id);
      setAdminInviteToken(null);
      setOpenQuickForm(null);
    } catch (error) {
      setSyncStatus("error");
      setSyncError(error instanceof Error ? error.message : "No se pudo crear el equipo");
    }
  }

  async function saveProfileName() {
    const nextName = displayName(profileName || authDisplayName(authUser));
    if (!nextName) return;

    setProfileName(nextName);

    if (ownPlayer) {
      updatePlayer(ownPlayer.id, { name: nextName });
    }

    if (!supabase || !remoteGroupId || !currentUserId) return;

    const result = await supabase.rpc("update_pachanga_member_name", {
      member_name: nextName,
      target_group_id: remoteGroupId,
    });

    if (result.error) {
      setSyncStatus("error");
      setSyncError(result.error.message);
      return;
    }

    await loadTeamMembers(supabase, remoteGroupId);
    setSyncStatus("live");
    setSyncError("");
  }

  function openOwnPlayerProfile() {
    if (ownPlayer) {
      setSelectedPlayerId(ownPlayer.id);
      return;
    }

    if (!hasRealTeam || !isRegisteredUser || !currentUserId) return;

    const name = displayName(profileName || authDisplayName(authUser)) || "Jugador";
    const player: Player = {
      id: id(),
      ownerUserId: currentUserId,
      name,
      phone: "",
      goalkeeperOnly: false,
      injured: false,
      rating: 5,
      ratings: [],
      ratingVotes: [],
      position: defaultPositionForKind(activeKind),
      goals: 0,
      assists: 0,
      appearances: 0,
      wins: 0,
      lateCancels: 0,
    };

    setPlayers((current) => [...current, player]);
    setSelectedPlayerId(player.id);
  }

  function claimSelectedPlayer() {
    if (!selectedPlayer || selectedPlayer.ownerUserId || ownPlayer || !hasRealTeam || !isRegisteredUser || !currentUserId) return;

    const nextName = displayName(profileName || selectedPlayer.name || authDisplayName(authUser));
    setPlayers((current) =>
      current.map((player) =>
        player.id === selectedPlayer.id
          ? { ...player, ownerUserId: currentUserId, name: nextName || player.name }
          : player,
      ),
    );
    if (nextName) setProfileName(nextName);
  }

  async function deleteCurrentTeam() {
    if (!supabase || !remoteGroupId || !canManageTeam) return;
    const teamName = currentTeam?.name ?? "este equipo";
    if (!window.confirm(`¿Eliminar ${teamName}?`)) return;
    if (!window.confirm("Confirmación final: se borrarán el equipo y sus miembros.")) return;

    const client = supabase;
    setSyncStatus("connecting");
    setSyncError("");

    try {
      const deleteResult = await client.from("pachanga_groups").delete().eq("id", remoteGroupId);
      if (deleteResult.error) throw new Error(deleteResult.error.message);

      const nextTeam = remoteTeams.find((team) => team.id !== remoteGroupId);
      await loadTeams(client, nextTeam?.id ?? null);

      const nextParams = new URLSearchParams(window.location.search);
      if (nextTeam) {
        nextParams.set("equipo", nextTeam.teamCode);
        nextParams.set("i", compactUuid(nextTeam.inviteToken));
      } else {
        nextParams.delete("grupo");
        nextParams.delete("invite");
        nextParams.delete("equipo");
        nextParams.delete("i");
      }
      nextParams.delete("admin");
      nextParams.delete("a");
      window.history.replaceState(null, "", nextParams.toString() ? `${window.location.pathname}?${nextParams.toString()}` : window.location.pathname);
    } catch (error) {
      setSyncStatus("error");
      setSyncError(error instanceof Error ? error.message : "No se pudo eliminar el equipo");
    }
  }

  function selectTeam(teamId: string) {
    const selectedTeam = remoteTeams.find((team) => team.id === teamId);
    if (!selectedTeam) return;

    setRemoteGroupId(selectedTeam.id);
    setRemoteInviteToken(selectedTeam.inviteToken);
    setCurrentRole(selectedTeam.role);
    setAdminInviteToken(null);
    applyPayload(selectedTeam.payload);
    setRemoteReady(true);
    setSyncStatus("live");
    setSyncError("");

    const nextParams = prettyTeamParams(selectedTeam);
    window.history.replaceState(null, "", `${window.location.pathname}?${nextParams.toString()}`);

    if (supabase) {
      void loadTeamMembers(supabase, selectedTeam.id).catch((error) => {
        setSyncStatus("error");
        setSyncError(error instanceof Error ? error.message : "No se pudieron cargar miembros");
      });
    }
  }

  async function updateMemberRole(member: RemoteMember, role: MemberRole) {
    if (!supabase || !remoteGroupId || !canManageTeam || member.role === "owner" || member.userId === currentUserId || role === "owner") return;

    const result = await supabase
      .from("pachanga_group_members")
      .update({ role })
      .eq("group_id", remoteGroupId)
      .eq("user_id", member.userId);

    if (result.error) {
      setSyncStatus("error");
      setSyncError(result.error.message);
      return;
    }

    await loadTeamMembers(supabase, remoteGroupId);
  }

  function adminInviteUrl(token: string | null = adminInviteToken) {
    if (!localHydrated || typeof window === "undefined" || !currentTeam || !token) return "";
    const params = new URLSearchParams();
    params.set("equipo", currentTeam.teamCode);
    params.set("a", compactUuid(token));
    return `${window.location.origin}${window.location.pathname}?${params.toString()}`;
  }

  async function createAdminInvite() {
    if (!supabase || !remoteGroupId || !canManageTeam) return;

    setSyncStatus("connecting");
    setSyncError("");

    const result = await supabase.rpc("create_pachanga_admin_invite", {
      target_group_id: remoteGroupId,
    });

    if (result.error || !result.data) {
      setSyncStatus("error");
      setSyncError(result.error?.message ?? "No se pudo crear la invitación de admin");
      return;
    }

    const token = String(result.data);
    setAdminInviteToken(token);
    setSyncStatus("live");
    setSyncError("");
  }

  async function copyAdminInvite() {
    let token = adminInviteToken;
    if (!token) {
      if (!supabase || !remoteGroupId || !canManageTeam) return;
      setSyncStatus("connecting");
      setSyncError("");

      const result = await supabase.rpc("create_pachanga_admin_invite", {
        target_group_id: remoteGroupId,
      });

      if (result.error || !result.data) {
        setSyncStatus("error");
        setSyncError(result.error?.message ?? "No se pudo crear la invitación de admin");
        return;
      }

      token = String(result.data);
      setAdminInviteToken(token);
    }

    const inviteUrl = adminInviteUrl(token);
    if (!inviteUrl || !navigator.clipboard) return;

    try {
      await navigator.clipboard.writeText(inviteUrl);
      setSyncStatus("live");
      setSyncError("");
    } catch {
      setSyncStatus("error");
      setSyncError("No se pudo copiar la invitación de admin");
    }
  }

  async function shareAdminInviteWhatsApp() {
    let token = adminInviteToken;
    if (!token) {
      if (!supabase || !remoteGroupId || !canManageTeam) return;
      setSyncStatus("connecting");
      setSyncError("");

      const result = await supabase.rpc("create_pachanga_admin_invite", {
        target_group_id: remoteGroupId,
      });

      if (result.error || !result.data) {
        setSyncStatus("error");
        setSyncError(result.error?.message ?? "No se pudo crear la invitación de admin");
        return;
      }

      token = String(result.data);
      setAdminInviteToken(token);
    }

    const inviteUrl = adminInviteUrl(token);
    const teamName = currentTeam?.name ?? "mi equipo";
    if (!inviteUrl) return;
    window.open(`https://wa.me/?text=${encodeURIComponent(`Invitación de admin para ${teamName}\n${inviteUrl}`)}`, "_blank", "noopener,noreferrer");
  }

  function matchUrl() {
    if (!localHydrated || typeof window === "undefined" || !matchConfigured) return "";
    const params = currentTeam ? prettyTeamParams(currentTeam) : new URLSearchParams();
    params.set("p", compactUuid(activeMatch.id));
    return `${window.location.origin}${window.location.pathname}?${params.toString()}`;
  }

  function currentTeamInviteUrl() {
    if (!localHydrated || typeof window === "undefined" || !currentTeam) return "";
    const params = prettyTeamParams(currentTeam);
    return `${window.location.origin}${window.location.pathname}?${params.toString()}`;
  }

  async function copyTeamInvite() {
    const inviteUrl = currentTeamInviteUrl();
    if (!inviteUrl || !navigator.clipboard) return;

    try {
      await navigator.clipboard.writeText(inviteUrl);
      setSyncStatus("live");
      setSyncError("");
    } catch {
      setSyncStatus("error");
      setSyncError("No se pudo copiar el enlace");
    }
  }

  function shareTeamInviteWhatsApp() {
    const inviteUrl = currentTeamInviteUrl();
    if (!inviteUrl) return;
    const teamName = currentTeam?.name ?? "mi equipo";
    window.open(`https://wa.me/?text=${encodeURIComponent(`Únete a ${teamName}\n${inviteUrl}`)}`, "_blank", "noopener,noreferrer");
  }

  function shareText() {
    const date = new Date(activeMatch.date).toLocaleString("es-ES", {
      weekday: "long",
      day: "2-digit",
      month: "short",
      hour: "2-digit",
      minute: "2-digit",
    });

    return [
      "Nuevo partido",
      `${date}`,
      `${activeMatch.place}`,
      matchUrl(),
    ]
      .filter(Boolean)
      .join("\n");
  }

  function shareWhatsApp() {
    window.open(`https://wa.me/?text=${encodeURIComponent(shareText())}`, "_blank", "noopener,noreferrer");
  }

  async function copyMatchLink() {
    const url = matchUrl();
    if (!url || !navigator.clipboard) return;

    try {
      await navigator.clipboard.writeText(url);
      setSyncStatus("live");
      setSyncError("");
    } catch {
      setSyncStatus("error");
      setSyncError("No se pudo copiar el partido");
    }
  }

  function renderPlayerCard(player: Player, team?: "A" | "B") {
    const matchEntry = activeMatch.players.find((entry) => entry.playerId === player.id);
    const status = player.injured || player.inactive ? "no" : matchEntry?.status;
    const isReserve = reserveIds.includes(player.id);
    const isWaiting = waitingIds.includes(player.id);
    const joinedLabel = status === "voy" ? joinedAtLabel(matchEntry?.joinedAt) : "";
    const teamClass = team === "A" ? "team-a-card" : team === "B" ? "team-b-card" : "";
    const nextTeam = team === "A" ? "B" : "A";
    const playerRatingWindow = ratingWindow(player, ratingVoterId);
    const canChangeThisPlayerStatus = matchConfigured && (isDemoMode || canUseAdminControls || (hasRealTeam && isRegisteredUser && player.ownerUserId === currentUserId));
    const ratingTitle = player.ownerUserId === currentUserId
      ? "No puedes votarte a ti mismo"
      : playerRatingWindow.canRate
      ? "Valoraciones abiertas"
      : `Valoraciones cerradas: faltan ${playerRatingWindow.waitMatches} partido${playerRatingWindow.waitMatches === 1 ? "" : "s"}`;

    return (
      <article className={`player-card ${status ? `status-${status}` : "status-sin"} ${teamClass} ${isReserve ? "reserve-card" : ""} ${isWaiting ? "waiting-card" : ""} ${player.inactive ? "inactive-card" : ""} ${playerPosition(player) === "Porteria" ? "goalkeeper-card" : ""}`} key={player.id}>
        <div>
          <button className="player-name" onClick={() => openPlayerProfile(player.id)}>
            {player.avatar ? (
              // eslint-disable-next-line @next/next/no-img-element
              <img src={player.avatar} alt="" />
            ) : null}
            <strong>
              {playerDisplayName(player)} <small>({scorePlayer(player).toFixed(1)}) {player.goals} Goles</small>
            </strong>
          </button>
          <span className="player-meta">
            {positionLabel(player)}
            {player.inactive ? <em className="reserve-chip">Ya no está</em> : null}
            {isReserve ? <em className="reserve-chip">Reserva</em> : null}
            {isWaiting ? <em className="reserve-chip">Espera</em> : null}
          </span>
          {joinedLabel ? <small className="joined-at">Voy desde {joinedLabel}</small> : null}
        </div>
        <div className="card-badges">
          {!player.inactive ? (
            <button
              className={playerRatingWindow.canRate ? "rating-badge rating-open" : "rating-badge rating-closed"}
              onClick={() => openPlayerProfile(player.id)}
              title={ratingTitle}
              type="button"
              aria-label={ratingTitle}
            >
              ★
            </button>
          ) : null}
          {player.inactive ? (
            <span className="inactive-badge" title="Ya no está en el grupo" aria-label="Ya no está en el grupo">
              <UserOffLogo />
            </span>
          ) : null}
          {player.injured ? (
            <span className="injury-badge" title="Jugador lesionado" aria-label="Jugador lesionado">
              <HospitalLogo />
            </span>
          ) : null}
          {payerId === player.id ? (
            <span className="payer-badge" title="Le toca pagar el campo" aria-label="Le toca pagar el campo">
              $
            </span>
          ) : null}
        </div>
        <div className="player-actions">
          <div className="status-buttons" aria-label={`Estado de ${playerDisplayName(player)}`}>
            <button className={status === "voy" ? "selected" : ""} disabled={!canChangeThisPlayerStatus || Boolean(player.injured || player.inactive)} onClick={() => setStatus(player.id, "voy")}>Voy</button>
            <button className={status === "duda" ? "selected" : ""} disabled={!canChangeThisPlayerStatus || Boolean(player.inactive)} onClick={() => setStatus(player.id, "duda")}>Duda</button>
            <button className={status === "no" ? "selected danger" : ""} disabled={!canChangeThisPlayerStatus || Boolean(player.inactive)} onClick={() => setStatus(player.id, "no")}>No</button>
          </div>
          {status === "voy" && team && canUseAdminControls ? (
            <button
              className={`team-move ${team === "A" ? "to-b" : "to-a"}`}
              disabled={lineupClosed}
              onClick={() => assignPlayerTeam(player.id, nextTeam)}
              title={team === "A" ? "Mover al equipo 2" : "Mover al equipo 1"}
              type="button"
            >
              {team === "A" ? "→" : "←"}
            </button>
          ) : null}
          {status === "voy" && !isWaiting ? (
            <button
              className={matchEntry?.paid ? "paid-button paid" : "paid-button"}
              onClick={() => togglePaid(player.id)}
              title={matchEntry?.paid ? "Pago recibido" : "Marcar pago recibido"}
              aria-label={matchEntry?.paid ? "Pago recibido" : "Marcar pago recibido"}
            >
              $
            </button>
          ) : null}
        </div>
      </article>
    );
  }

  const teamColorStyle = {
    "--team-a": siteSettings.teamAColor,
    "--team-b": siteSettings.teamBColor,
    "--team-a-soft": `color-mix(in srgb, ${siteSettings.teamAColor} 10%, white)`,
    "--team-b-soft": `color-mix(in srgb, ${siteSettings.teamBColor} 10%, white)`,
    "--team-a-card": `color-mix(in srgb, ${siteSettings.teamAColor} 14%, white)`,
    "--team-b-card": `color-mix(in srgb, ${siteSettings.teamBColor} 14%, white)`,
    "--team-a-muted": `color-mix(in srgb, ${siteSettings.teamAColor} 38%, white)`,
    "--team-b-muted": `color-mix(in srgb, ${siteSettings.teamBColor} 38%, white)`,
  } as CSSProperties;

  return (
    <main className="min-h-screen bg-[#f7f6f0] text-[#1d2521]" style={teamColorStyle}>
      <section className="hero">
        <div>
          <div className="brand-lockup" aria-label={siteSettings.brand}>
            <img src="/icon-192.png" alt="" />
            <span>{siteSettings.brand}</span>
          </div>
          <h1>{siteSettings.title}</h1>
          <p className="hero-copy">{siteSettings.subtitle}</p>
        </div>
        <div className="hero-actions">
          <a className="manual-link-button" href="/manual" title="Manual de usuario" aria-label="Abrir manual de usuario">
            <svg aria-hidden="true" viewBox="0 0 24 24">
              <path d="M6 3h10.5A2.5 2.5 0 0 1 19 5.5V21l-3-1.8L13 21l-3-1.8L7 21l-3-1.8V5A2 2 0 0 1 6 3Zm0 2v12.6l1 .6 3-1.8 3 1.8 3-1.8 1 .6V5.5a.5.5 0 0 0-.5-.5H6Zm2 3h7v2H8V8Zm0 4h7v2H8v-2Z" />
            </svg>
          </a>
          <button className="primary-button" onClick={createMatch} disabled={!canUseAdminControls}>
            + Partido
          </button>
          <button className="secondary-button" onClick={() => setOpenQuickForm(openQuickForm === "player" ? null : "player")} disabled={!canUseAdminControls}>
            + Jugador
          </button>
          <button className="secondary-button" onClick={() => setOpenQuickForm(openQuickForm === "venue" ? null : "venue")} disabled={!canUseAdminControls}>
            + Campo
          </button>
          <button className="secondary-button" onClick={() => setOpenQuickForm(openQuickForm === "team" ? null : "team")}>
            + Equipo
          </button>
          <button className="secondary-button" onClick={() => setShowSettings((current) => !current)} disabled={!canUseAdminControls}>
            Configurar
          </button>
        </div>
      </section>

      <section className="top-panel auth-panel">
        <div>
          <span>Registro</span>
          <strong>{isRegisteredUser ? "Conectado con Google" : "Entra para crear tu equipo"}</strong>
          <p>
            Cada jugador entra con Google para tener su propia ficha. Solo esa persona y los admins pueden editarla.
          </p>
        </div>
        <div className="auth-actions">
          {isRegisteredUser ? (
            <>
              <label className="profile-name-field">
                Nombre en el equipo
                <input
                  value={profileName}
                  onChange={(event) => setProfileName(event.target.value)}
                  onBlur={() => setProfileName(displayName(profileName || authDisplayName(authUser)))}
                  placeholder="Ej. Alberto"
                />
              </label>
              <button className="secondary-button" type="button" onClick={() => void saveProfileName()} disabled={!hasRealTeam}>
                Guardar nombre
              </button>
              <button className="primary-button" type="button" onClick={openOwnPlayerProfile} disabled={!hasRealTeam}>
                {ownPlayer ? "Mi ficha" : "Crear mi ficha"}
              </button>
              <button className="secondary-button" type="button" onClick={() => void signOut()}>
                Salir
              </button>
            </>
          ) : (
            <button className="primary-button" type="button" onClick={() => void signInWithGoogle()} disabled={!supabase || !googleClientId}>
              Entrar con Google
            </button>
          )}
        </div>
      </section>

      {openQuickForm === "team" ? (
        <form className="top-panel team-create-form top-team-form" onSubmit={createTeam}>
          <input value={newTeamName} onChange={(event) => setNewTeamName(event.target.value)} placeholder="Nombre del nuevo equipo" />
          <button type="submit" disabled={!canCreateTeam}>Crear equipo</button>
          {!canCreateTeam ? (
            <button className="ghost-form-button" type="button" onClick={() => void signInWithGoogle()} disabled={!supabase}>
              Entrar con Google
            </button>
          ) : null}
          <button className="ghost-form-button" type="button" onClick={() => setOpenQuickForm(null)}>Cerrar</button>
        </form>
      ) : null}

      <section className="top-panel team-access-panel">
        <div className="team-access-current">
          <span>Equipo pachanguero</span>
          {remoteTeams.length > 0 ? (
            <select value={remoteGroupId ?? ""} onChange={(event) => selectTeam(event.target.value)}>
              {remoteTeams.map((team) => (
                <option key={team.id} value={team.id}>{team.name}</option>
              ))}
            </select>
          ) : (
            <strong>Sin equipo todavía</strong>
          )}
        </div>
        <div className="team-access-meta">
          <span>ID equipo</span>
          <strong>{currentTeam?.teamCode ?? "-"}</strong>
        </div>
        <div className="team-access-meta">
          <span>Rol</span>
          <strong>{currentRole === "owner" || currentRole === "admin" ? "Admin" : currentRole === "player" ? "Jugador" : "-"}</strong>
        </div>
        <div className="team-invite-link">
          <span>Invitar a equipo</span>
          <div className="team-invite-actions">
            <button className="copy-icon-button" type="button" onClick={() => void copyTeamInvite()} disabled={!currentTeamInviteUrl()} title="Copiar invitación" aria-label="Copiar invitación">
              <CopyLogo />
            </button>
            <button className="whatsapp-icon-button" type="button" onClick={shareTeamInviteWhatsApp} disabled={!currentTeamInviteUrl()} title="Enviar por WhatsApp" aria-label="Enviar por WhatsApp">
              <WhatsAppLogo />
            </button>
          </div>
        </div>
        <button
          className="trash-icon-button team-delete-button"
          disabled={!remoteGroupId || !canUseAdminControls}
          onClick={() => void deleteCurrentTeam()}
          title="Eliminar equipo"
          type="button"
          aria-label="Eliminar equipo"
        >
          <TrashLogo />
        </button>
        <small className={`sync-status sync-${syncStatus}`}>
          {syncStatus === "live" ? "Equipo privado sincronizado" : syncStatus === "connecting" ? "Conectando..." : syncStatus === "error" ? `Sin sync: ${syncError}` : "Crea un equipo o entra con invitación"}
        </small>
      </section>

      {isDemoMode ? (
        <section className="top-panel demo-banner">
          <div>
            <span>Demo interactiva</span>
            <strong>Lo que ves son datos de ejemplo.</strong>
            <p>
              Puedes tocar jugadores, cambiar asistencia, revisar reservas, pagos, alineaciones, valoraciones y fichas. Cuando crees tu equipo real, la web empieza limpia.
            </p>
          </div>
          <button className="primary-button" type="button" onClick={() => setOpenQuickForm("team")}>
            Crear mi equipo limpio
          </button>
        </section>
      ) : null}

      {showSettings ? (
        <section className="top-panel settings-panel">
          <label>
            Nombre
            <input value={siteSettings.brand} onChange={(event) => setSiteSettings({ ...siteSettings, brand: event.target.value })} />
          </label>
          <label>
            Título
            <input value={siteSettings.title} onChange={(event) => setSiteSettings({ ...siteSettings, title: event.target.value })} />
          </label>
          <label>
            Subtítulo
            <input value={siteSettings.subtitle} onChange={(event) => setSiteSettings({ ...siteSettings, subtitle: event.target.value })} />
          </label>
          <div className="palette-field">
            <span>Color equipo 1</span>
            <div className="color-select">
              <span style={{ background: siteSettings.teamAColor }} />
              <select value={siteSettings.teamAColor} onChange={(event) => setSiteSettings({ ...siteSettings, teamAColor: event.target.value })}>
                {teamPalette.map((color) => (
                  <option key={`team-a-${color.value}`} value={color.value}>{color.name}</option>
                ))}
              </select>
            </div>
          </div>
          <div className="palette-field">
            <span>Color equipo 2</span>
            <div className="color-select">
              <span style={{ background: siteSettings.teamBColor }} />
              <select value={siteSettings.teamBColor} onChange={(event) => setSiteSettings({ ...siteSettings, teamBColor: event.target.value })}>
                {teamPalette.map((color) => (
                  <option key={`team-b-${color.value}`} value={color.value}>{color.name}</option>
                ))}
              </select>
            </div>
          </div>
          <button className="panel-hide-button" type="button" onClick={() => setShowSettings(false)}>
            Guardar
          </button>
        </section>
      ) : null}

      {openQuickForm === "player" ? (
        <form className="top-panel add-player top-player-form" onSubmit={addPlayer}>
          <input placeholder="Nombre del jugador" value={newPlayer} onChange={(event) => setNewPlayer(event.target.value)} />
          <button type="submit">Guardar jugador</button>
        </form>
      ) : null}

      {openQuickForm === "venue" ? (
        <form className="top-panel venue-form top-venue-form" onSubmit={addVenue}>
          <input
            placeholder="Crear campo: nombre"
            value={newVenue.name}
            onChange={(event) => setNewVenue({ ...newVenue, name: event.target.value })}
          />
          <label className="money-input">
            <input
              type="number"
              min="0"
              placeholder="Precio"
              value={newVenue.cost}
              onChange={(event) => setNewVenue({ ...newVenue, cost: event.target.value })}
            />
            <span>€</span>
          </label>
          <select value={newVenue.kind} onChange={(event) => setNewVenue({ ...newVenue, kind: event.target.value as MatchKind })}>
            {Object.entries(matchKinds).map(([kind, config]) => (
              <option key={kind} value={kind}>{config.label}</option>
            ))}
          </select>
          <button type="submit">Guardar campo</button>
        </form>
      ) : null}

      <section className="app-shell">
        <aside className="panel match-list" aria-label="Partidos">
          {teamMembers.length > 0 ? (
            <details className="team-members">
              <summary>
                <span>Miembros</span>
                <strong>{teamMembers.length}</strong>
              </summary>
              <div>
                {teamMembers.map((member) => (
                  <label key={member.userId}>
                    <strong>
                      {member.displayName}
                      {member.userId === currentUserId ? " (tú)" : ""}
                    </strong>
                    <select
                      value={member.role}
                      disabled={!canManageTeam || member.role === "owner" || member.userId === currentUserId}
                      onChange={(event) => void updateMemberRole(member, event.target.value as MemberRole)}
                    >
                      {member.role === "owner" ? <option value="owner">Admin</option> : null}
                      <option value="admin">Admin</option>
                      <option value="player">Jugador</option>
                    </select>
                  </label>
                ))}
                {canManageTeam ? (
                  <div className="admin-invite-row">
                    <span>Invitar admin</span>
                    <div>
                      <button type="button" onClick={() => void createAdminInvite()} disabled={!remoteGroupId}>
                        Crear link
                      </button>
                      <button className="copy-icon-button" type="button" onClick={() => void copyAdminInvite()} disabled={!remoteGroupId} title="Copiar invitación de admin" aria-label="Copiar invitación de admin">
                        <CopyLogo />
                      </button>
                      <button className="whatsapp-icon-button" type="button" onClick={() => void shareAdminInviteWhatsApp()} disabled={!remoteGroupId} title="Enviar admin por WhatsApp" aria-label="Enviar admin por WhatsApp">
                        <WhatsAppLogo />
                      </button>
                    </div>
                    {adminInviteToken ? <small>Invitación admin lista</small> : null}
                  </div>
                ) : null}
              </div>
            </details>
          ) : null}
          <div className="panel-title">
            <span>Próximos partidos</span>
            <strong>{openMatches.length}</strong>
          </div>
          {openMatches.length === 0 ? <p className="empty-copy">Crea tu primer partido con “+ Partido”.</p> : null}
          {openMatches.map((match) => (
            <div className="match-row" key={match.id}>
              <button
                className={match.id === activeMatch.id ? "match-item active" : "match-item"}
                onClick={() => setActiveMatchId(match.id)}
              >
                <span>{match.title}</span>
                <small>{new Date(match.date).toLocaleString("es-ES", { weekday: "short", hour: "2-digit", minute: "2-digit" })}</small>
              </button>
              <button
                className="trash-icon-button"
                disabled={!canUseAdminControls}
                onClick={() => deleteMatch(match.id)}
                title="Borrar partido"
                type="button"
                aria-label={`Borrar ${match.title}`}
              >
                <TrashLogo />
              </button>
            </div>
          ))}
          <div className="side-history">
            <div className="panel-title compact-title">
              <span>Historial</span>
              <strong>{closedMatches.length}</strong>
            </div>
            <div className="history">
              {closedMatches.map((match, index) => {
                const matchPayer = players.find((player) => player.id === match.payerId);
                const currentMonth = monthLabel(match.date);
                const previousMonth = index > 0 ? monthLabel(closedMatches[index - 1].date) : "";
                const scorersText = match.scorers
                  ?.map((entry) => {
                    const scorer = players.find((player) => player.id === entry.playerId);
                    return `${scorer ? playerDisplayName(scorer) : "Jugador"} ${entry.goals}`;
                  })
                  .join(", ");

                return (
                  <Fragment key={match.id}>
                    {currentMonth !== previousMonth ? <div className="history-month">{currentMonth}</div> : null}
                    <article className="history-item">
                      <div>
                        <strong>{match.title}</strong>
                        <small>{new Date(match.date).toLocaleDateString("es-ES", { day: "2-digit", month: "short" })}</small>
                      </div>
                      <span>{match.scoreA} - {match.scoreB}</span>
                      {canUseAdminControls ? (
                        <button
                          className="history-delete"
                          type="button"
                          onClick={() => {
                            if (window.confirm("¿Borrar este partido y descontar sus estadísticas?")) deleteClosedMatch(match.id);
                          }}
                        >
                          Borrar
                        </button>
                      ) : null}
                      <small>
                        {match.place} · pagó {matchPayer ? playerDisplayName(matchPayer) : "sin asignar"}
                        {scorersText ? ` · goles: ${scorersText}` : ""}
                      </small>
                    </article>
                  </Fragment>
                );
              })}
            </div>
          </div>
        </aside>

        <section className="panel main-panel">
          <div className={canEditMatchSettings ? "match-editor" : "match-editor readonly-editor"}>
            {!canUseAdminControls ? <span className="admin-only-badge">Solo admin</span> : null}
            {canUseAdminControls && matchFinalized ? <span className="admin-only-badge">Partido finalizado</span> : null}
            {canUseAdminControls && !matchConfigured && !matchFinalized ? <span className="admin-only-badge draft-badge">Borrador</span> : null}
            <label>
              Campo
              <select value={activeMatch.venueId ?? ""} onChange={(event) => selectVenue(event.target.value)} disabled={!canEditMatchSettings}>
                <option value="" disabled>Selecciona campo</option>
                {venues.map((venue) => (
                  <option key={venue.id} value={venue.id}>{venue.name}</option>
                ))}
              </select>
            </label>
            <label>
              Fecha
              <input
                type="datetime-local"
                step="600"
                value={activeMatch.date}
                disabled={!canEditMatchSettings}
                onChange={(event) => updateMatchSettings({ ...activeMatch, date: event.target.value })}
              />
            </label>
            <label>
              Modalidad
              <select value={activeKind} onChange={(event) => changeKind(event.target.value as MatchKind)} disabled={!canEditMatchSettings}>
                {Object.entries(matchKinds).map(([kind, config]) => (
                  <option key={kind} value={kind}>{config.label}</option>
                ))}
              </select>
            </label>
            <label>
              Precio
              <input
                type="number"
                min="0"
                value={fieldCost}
                disabled={!canEditMatchSettings}
                onChange={(event) => updateMatchSettings({ ...activeMatch, fieldCost: Number(event.target.value) })}
              />
            </label>
            <label className="reserve-toggle">
              Reservas
              <span className="reserve-toggle-box">
                <input
                  type="checkbox"
                  checked={Boolean(activeMatch.reservesAttend)}
                  disabled={!canEditMatchSettings}
                  onChange={(event) =>
                    updateMatchSettings({
                      ...activeMatch,
                      reservesAttend: event.target.checked,
                      reserveLimit: event.target.checked ? Math.max(1, activeMatch.reserveLimit ?? 2) : 0,
                    })
                  }
                />
                Van y pagan
              </span>
            </label>
            <label>
              Max reservas
              <input
                type="number"
                min="0"
                value={activeMatch.reserveLimit ?? 0}
                disabled={!canEditMatchSettings || !activeMatch.reservesAttend}
                onChange={(event) => updateMatchSettings({ ...activeMatch, reserveLimit: Math.max(0, Math.floor(Number(event.target.value) || 0)) })}
              />
            </label>
            {canUseAdminControls && !matchFinalized ? (
              <button className="save-match-button" type="button" onClick={saveMatchConfiguration} disabled={!matchCanBeSaved || matchConfigured}>
                {matchConfigured ? "Guardado" : "Guardar partido"}
              </button>
            ) : null}
          </div>

          {!matchConfigured && !matchFinalized ? (
            <div className="draft-match-note">
              <span>Partido sin guardar</span>
              <strong>Configura campo, fecha, modalidad y precio. Al guardar se activan confirmaciones, compartir y alineación.</strong>
            </div>
          ) : null}

          <div className="stats-row">
            <div>
              <span>Confirmados</span>
              <strong>{confirmedPlayers.length}/{activeMatch.targetPlayers}</strong>
            </div>
            <div>
              <span>Faltan</span>
              <strong>{missing}</strong>
            </div>
            <div>
              <span>Reservas</span>
              <strong>{activeMatch.reservesAttend ? `${reservePlayers.length}/${reserveLimit}` : "No"}</strong>
            </div>
            <div>
              <span>Espera</span>
              <strong>{waitingPlayers.length}</strong>
            </div>
            <div>
              <span>Duda</span>
              <strong>{doubtfulCount}</strong>
            </div>
            <div>
              <span>Toca</span>
              <strong>{sharePerPlayer.toFixed(2)} €</strong>
            </div>
            <div>
              <span>Campo</span>
              <strong>{fieldCost.toFixed(0)} €</strong>
            </div>
            <div>
              <span>Paga</span>
              <strong>{payer?.name ?? "-"}</strong>
            </div>
            <div>
              <span>Pagados</span>
              <strong>{paidCount}/{payingIds.length}</strong>
            </div>
          </div>

          <div className="payer-note">
            <span>Turno de pago</span>
            <strong>
              {payer
                ? `${playerDisplayName(payer)} adelanta el campo. Bizum: ${payer.phone || "sin telefono"} · ${sharePerPlayer.toFixed(2)} € por persona`
                : "Añade asistentes para calcularlo"}
            </strong>
          </div>

          <div className="share-box">
            <span>Comparte este partido!</span>
            <div className="share-actions">
              <button className="copy-invite-button" type="button" onClick={() => void copyMatchLink()} disabled={!matchUrl()} title="Copiar link del partido" aria-label="Copiar link del partido">
                Copiar link
              </button>
              <button className="whatsapp-icon-button" type="button" onClick={shareWhatsApp} disabled={!matchUrl()} title="Enviar partido por WhatsApp" aria-label="Enviar partido por WhatsApp">
                <WhatsAppLogo />
              </button>
            </div>
            {syncStatus !== "local" ? (
              <small className={`sync-status sync-${syncStatus}`}>
                {!matchConfigured ? "Guarda el partido para compartirlo" : syncStatus === "live" ? "Sincronizado" : syncStatus === "connecting" ? "Conectando..." : `Sin sync: ${syncError}`}
              </small>
            ) : null}
          </div>

          <div className="team-player-grid">
            <div className="team-player-column team-a-column">
              <div className="team-column-title">
                <span>Equipo 1</span>
                <strong>{suggested.teamA.length}</strong>
              </div>
              {sortedTeamA.map((player) => renderPlayerCard(player, "A"))}
            </div>
            <div className="team-player-column team-b-column">
              <div className="team-column-title">
                <span>Equipo 2</span>
                <strong>{suggested.teamB.length}</strong>
              </div>
              {sortedTeamB.map((player) => renderPlayerCard(player, "B"))}
            </div>
          </div>

          {reservePlayers.length > 0 ? (
            <div className="reserve-section">
              <div className="team-column-title">
                <span>Reservas que van</span>
                <strong>{reservePlayers.length}</strong>
              </div>
              <div className="player-grid reserve-player-grid">
                {reservePlayers.map((player) => renderPlayerCard(player))}
              </div>
            </div>
          ) : null}

          {waitingPlayers.length > 0 ? (
            <div className="reserve-section waiting-section">
              <div className="team-column-title">
                <span>Lista de espera</span>
                <strong>{waitingPlayers.length}</strong>
              </div>
              <div className="player-grid reserve-player-grid">
                {waitingPlayers.map((player) => renderPlayerCard(player))}
              </div>
            </div>
          ) : null}

          {otherPlayers.length > 0 ? (
            <div className="player-grid other-player-grid">
              {otherPlayers.map((player) => renderPlayerCard(player))}
            </div>
          ) : null}
        </section>

        <aside className="panel teams-panel">
          <div className="panel-title">
            <span>Equipos sugeridos</span>
            <strong>{matchKinds[activeKind].teamSize}v{matchKinds[activeKind].teamSize}</strong>
          </div>
          <MatchPitch teamA={suggested.teamA} teamB={suggested.teamB} kind={activeKind} />
          <div className={lineupClosed ? "lineup-state closed" : "lineup-state"}>
            {!matchConfigured ? "Alineación pendiente" : lineupClosed ? "Alineación cerrada" : "Alineación abierta"}
          </div>
          <div className="lineup-actions">
            <button type="button" onClick={applyRandomTeams} disabled={!canEditLineup}>Aleatorio</button>
            <button type="button" onClick={applyBalancedTeams} disabled={!canEditLineup}>Equilibrado por stats</button>
          </div>
          <Team title="Equipo 1" players={suggested.teamA} variant="team-a" />
          <Team title="Equipo 2" players={suggested.teamB} variant="team-b" />
          {canUseAdminControls && matchConfigured && !matchFinalized ? (
            <button className="primary-button full" onClick={toggleLineupClosed}>
              {lineupClosed ? "Abrir alineación" : "Cerrar alineación"}
            </button>
          ) : null}
          <div className="result-box">
            <span>Resultado</span>
            <div>
              <input type="number" min="0" value={result.a} disabled={!matchConfigured || matchFinalized} onChange={(event) => setResult({ ...result, a: event.target.value })} inputMode="numeric" />
              <b>-</b>
              <input type="number" min="0" value={result.b} disabled={!matchConfigured || matchFinalized} onChange={(event) => setResult({ ...result, b: event.target.value })} inputMode="numeric" />
            </div>
            <div className="scorers-box">
              <strong>Goles</strong>
              {!matchConfigured ? <small>Guarda primero el partido.</small> : null}
              {matchConfigured && confirmedPlayers.length === 0 ? <small>Marca asistentes para añadir goleadores.</small> : null}
              {confirmedPlayers.length > 0 && !resultIsReady ? <small>Rellena primero el resultado.</small> : null}
              {matchConfigured && confirmedPlayers.length > 0 && resultIsReady ? (
                <div className="scorers-teams">
                  <div className="scorers-team team-a-scorers">
                    <div className="scorers-team-title">
                      <span>Equipo 1</span>
                      <b>{scoreAValue}</b>
                    </div>
                    {scorerRows(suggested.teamA, "team-a")}
                  </div>
                  <div className="scorers-team team-b-scorers">
                    <div className="scorers-team-title">
                      <span>Equipo 2</span>
                      <b>{scoreBValue}</b>
                    </div>
                    {scorerRows(suggested.teamB, "team-b")}
                  </div>
                </div>
              ) : null}
            </div>
            {matchFinalized ? (
              <small className="result-locked-note">Partido finalizado. Puedes corregir goleadores y asistencia.</small>
            ) : (
              <button disabled={!matchConfigured || !resultIsReady || !canUseAdminControls} onClick={finalizeMatch}>Finalizar partido</button>
            )}
          </div>
        </aside>
      </section>

      <section className={selectedPlayer ? "bottom-grid" : "bottom-grid without-profile"}>
        {selectedPlayer ? (
          <div className="panel player-profile" ref={playerProfileRef}>
            <div className="panel-title">
              <span>Ficha jugador</span>
              <div className="profile-title-actions">
                {selectedPlayerIsOwn ? <small className="own-label">Tu ficha</small> : null}
                {selectedPlayer.inactive ? <small className="inactive-label">Ya no está</small> : null}
                {canUseAdminControls && !selectedPlayer.inactive ? (
                  <button
                    className="trash-icon-button profile-delete-button"
                    onClick={() => deactivatePlayer(selectedPlayer.id)}
                    title="Eliminar jugador"
                    type="button"
                    aria-label="Eliminar jugador"
                  >
                    <TrashLogo />
                  </button>
                ) : null}
                <strong>{scorePlayer(selectedPlayer).toFixed(1)}</strong>
              </div>
            </div>
            {!ownPlayer && selectedPlayer && !selectedPlayer.ownerUserId && hasRealTeam && isRegisteredUser ? (
              <div className="profile-claim">
                <span>¿Esta ficha eres tú?</span>
                <button type="button" onClick={claimSelectedPlayer}>Esta es mi ficha</button>
              </div>
            ) : null}
            <>
              <div className="profile-top">
                <div className="fifa-card-shell">
                  <label className={canEditSelectedPlayer ? "fifa-player-card" : "fifa-player-card readonly-card"}>
                    <span className="fifa-score">{Math.round(scorePlayer(selectedPlayer) * 10)}</span>
                    <span className="fifa-position">{positionShort(selectedPlayer)}</span>
                    <span className="fifa-photo">
                      {selectedPlayer.avatar ? (
                        // eslint-disable-next-line @next/next/no-img-element
                        <img src={selectedPlayer.avatar} alt={`Foto de ${playerDisplayName(selectedPlayer)}`} />
                      ) : (
                        <b>+</b>
                      )}
                    </span>
                    <strong>{playerDisplayName(selectedPlayer)}</strong>
                    <span className="fifa-card-meta">{selectedPlayer.goals} Goles · {selectedPlayer.appearances} PJ</span>
                    <div className="fifa-facets">
                      {ratingFacets.map((facet) => (
                        <span key={facet.key}>
                          <b>{Math.round(facetAverage(selectedPlayer, facet.key) * 10)}</b>
                          {facet.label.slice(0, 3).toLocaleUpperCase("es-ES")}
                        </span>
                      ))}
                    </div>
                    <span className="fifa-photo-action">{selectedPlayer.avatar ? "Cambiar foto" : "Añadir foto"}</span>
                    <input
                      type="file"
                      accept="image/*"
                      disabled={!canEditSelectedPlayer}
                      aria-label={selectedPlayer.avatar ? "Cambiar foto del jugador" : "Añadir foto del jugador"}
                      onClick={(event) => {
                        event.currentTarget.value = "";
                      }}
                      onChange={(event) => {
                        void uploadAvatar(event.currentTarget.files?.[0], selectedPlayer.id);
                        event.currentTarget.value = "";
                      }}
                    />
                  </label>
                  <div className="avatar-actions">
                    <label className="avatar-action-button">
                      Foto
                      <input
                        type="file"
                        accept="image/*"
                        disabled={!canEditSelectedPlayer}
                        onChange={(event) => {
                          void uploadAvatar(event.currentTarget.files?.[0], selectedPlayer.id);
                          event.currentTarget.value = "";
                        }}
                      />
                    </label>
                    <label className="avatar-action-button">
                      Cámara
                      <input
                        type="file"
                        accept="image/*"
                        capture="user"
                        disabled={!canEditSelectedPlayer}
                        onChange={(event) => {
                          void uploadAvatar(event.currentTarget.files?.[0], selectedPlayer.id);
                          event.currentTarget.value = "";
                        }}
                      />
                    </label>
                    <button className="avatar-action-button" type="button" onClick={() => openCamera(selectedPlayer.id)} disabled={!canEditSelectedPlayer}>
                      Webcam
                    </button>
                  </div>
                  {avatarMessage ? <small className="avatar-message">{avatarMessage}</small> : null}
                  {cameraPlayerId === selectedPlayer.id ? (
                    <div className="camera-panel">
                      <video ref={cameraVideoRef} autoPlay muted playsInline />
                      <div>
                        <button type="button" onClick={captureCameraAvatar}>Usar foto</button>
                        <button type="button" onClick={stopCamera}>Cerrar</button>
                      </div>
                      {cameraError ? <small>{cameraError}</small> : null}
                    </div>
                  ) : null}
                </div>
                <div>
                  <select value={selectedPlayer.id} onChange={(event) => setSelectedPlayerId(event.target.value)}>
                    {players.map((player) => (
                      <option key={player.id} value={player.id}>{playerDisplayName(player)}</option>
                    ))}
                  </select>
                  <input
                    value={selectedPlayer.name}
                    disabled={!canEditSelectedPlayer}
                    onBlur={() => updatePlayer(selectedPlayer.id, { name: displayName(selectedPlayer.name) })}
                    onChange={(event) => updatePlayer(selectedPlayer.id, { name: event.target.value })}
                  />
                  <input
                    inputMode="tel"
                    placeholder="Teléfono Bizum"
                    value={selectedPlayer.phone ?? ""}
                    disabled={!canEditSelectedPlayer}
                    onChange={(event) => updatePlayer(selectedPlayer.id, { phone: event.target.value })}
                  />
                </div>
              </div>
              <div className="profile-fields">
                <label className="toggle-field">
                  <input
                    type="checkbox"
                    checked={Boolean(selectedPlayer.goalkeeperOnly)}
                    disabled={!canEditSelectedPlayer}
                    onChange={(event) =>
                      updatePlayer(selectedPlayer.id, {
                        goalkeeperOnly: event.target.checked,
                        position: event.target.checked ? "Portero" : selectedPlayer.position,
                      })
                    }
                  />
                  Portero fijo
                </label>
                <label className="toggle-field injured-toggle">
                  <input
                    type="checkbox"
                    checked={Boolean(selectedPlayer.injured)}
                    disabled={!canEditSelectedPlayer}
                    onChange={(event) => setPlayerInjured(selectedPlayer.id, event.target.checked)}
                  />
                  Lesionado
                </label>
                <label>
                  Posición preferida
                  <select
                    value={equivalentPositionForKind(selectedPlayer.position, activeKind)}
                    disabled={!canEditSelectedPlayer}
                    onChange={(event) => updatePlayer(selectedPlayer.id, { position: event.target.value as PlayerPosition })}
                  >
                    {positionOptionsByKind[activeKind].map((option) => (
                      <option key={option.value} value={option.value}>{option.value}</option>
                    ))}
                  </select>
                </label>
                <div className="base-rating-card">
                  <span>Valor base</span>
                  <strong>{scorePlayer(selectedPlayer).toFixed(1)}</strong>
                  <small>Media de facetas</small>
                </div>
                <div className={canRateSelectedPlayer ? "rating-box rating-open-box" : "rating-box rating-locked-box"}>
                  <div className="rating-box-title">
                    <span>Valoraciones</span>
                    <em className={canRateSelectedPlayer ? "rating-state open" : "rating-state closed"}>
                      {canRateSelectedPlayer ? "Abiertas" : "Cerradas"}
                    </em>
                  </div>
                  <strong>{draftPeerAverage.toFixed(1)}</strong>
                  <small>
                    {(selectedPlayer.ratingVotes?.length ?? 0) + (selectedPlayer.ratings?.length ?? 0)} votos de compañeros
                  </small>
                  <p className="rating-help">{selectedRatingStatusText}</p>
                  <div className="facet-grid">
                    {ratingFacets.map((facet) => (
                      <label className="facet-field" key={facet.key}>
                        <span>{facet.label}</span>
                        <input
                          type="range"
                          min="1"
                          max="10"
                          step="0.5"
                          value={newFacetRatings[facet.key]}
                          disabled={!canRateSelectedPlayer}
                          onChange={(event) =>
                            setNewFacetRatings((current) => ({
                              ...current,
                              [facet.key]: Number(event.target.value),
                            }))
                          }
                        />
                        <b>{clampRating(newFacetRatings[facet.key] ?? facetAverage(selectedPlayer, facet.key)).toFixed(1)}</b>
                      </label>
                    ))}
                  </div>
                  <button type="button" onClick={() => addPeerRating(selectedPlayer.id)} disabled={!canRateSelectedPlayer}>
                    {selectedRatingButtonText}
                  </button>
                  <div className="rating-evolution">
                    <span>Evolución</span>
                    {selectedRatingHistory.length > 0 ? (
                      <div>
                        {selectedRatingHistory.slice(-10).map((vote, index, list) => {
                          const average = voteAverage(vote);
                          return (
                            <i
                              key={vote.id}
                              style={{ height: `${24 + average * 7}px` }}
                              title={`Partido ${vote.matchCount}: ${average.toFixed(1)}`}
                            >
                              {index === list.length - 1 ? average.toFixed(1) : ""}
                            </i>
                          );
                        })}
                      </div>
                    ) : (
                      <small>Sin evolución todavía</small>
                    )}
                  </div>
                </div>
                <label>
                  Goles
                  <input
                    type="number"
                    min="0"
                    value={selectedPlayer.goals}
                    disabled={!canEditSelectedPlayer}
                    onChange={(event) => updatePlayer(selectedPlayer.id, { goals: Number(event.target.value) })}
                  />
                </label>
              </div>
            </>
          </div>
        ) : null}

        <div className="panel">
          <div className="panel-title">
            <span>Ranking vivo</span>
            <strong>{rankedPlayers.length}</strong>
          </div>
          <div className="ranking">
            {rankedPlayers.slice(0, 8).map((player, index) => (
              <button
                className="ranking-row"
                key={player.id}
                onClick={() => openPlayerProfile(player.id)}
                type="button"
              >
                <span>{index + 1}</span>
                <strong>
                  {player.inactive ? (
                    <span className="inline-inactive" title="Ya no está en el grupo" aria-label="Ya no está en el grupo">
                      <UserOffLogo />
                    </span>
                  ) : null}
                  {player.injured ? (
                    <span className="inline-injury" title="Jugador lesionado" aria-label="Jugador lesionado">
                      <HospitalLogo />
                    </span>
                  ) : null}
                  {playerDisplayName(player)}
                </strong>
                <b>Media {scorePlayer(player).toFixed(1)}</b>
                <small>{positionLabel(player)} · {player.goals} goles · {player.wins} victorias</small>
              </button>
            ))}
          </div>
        </div>
      </section>
    </main>
  );
}

function Team({ title, players, variant }: { title: string; players: Player[]; variant: "team-a" | "team-b" }) {
  const orderedPlayers = sortedLineupPlayers(players);

  return (
    <div className={`team ${variant}`}>
      <h2>{title}</h2>
      {players.length === 0 ? <p>Marca jugadores como “Voy”.</p> : null}
      {orderedPlayers.map((player) => (
        <div className={playerPosition(player) === "Porteria" ? "goalkeeper-row" : ""} key={player.id}>
          <span>
            {player.inactive ? (
              <span className="inline-inactive" title="Ya no está en el grupo" aria-label="Ya no está en el grupo">
                <UserOffLogo />
              </span>
            ) : null}
            {player.injured ? (
              <span className="inline-injury" title="Jugador lesionado" aria-label="Jugador lesionado">
                <HospitalLogo />
              </span>
            ) : null}
            {playerDisplayName(player)}
            <em>({scorePlayer(player).toFixed(1)}) {player.goals} Goles</em>
          </span>
          <small className="position-pill">{positionLabel(player)}</small>
        </div>
      ))}
    </div>
  );
}

function MatchPitch({ teamA, teamB, kind }: { teamA: Player[]; teamB: Player[]; kind: MatchKind }) {
  const teamATokens = placeTeam(teamA, kind, "bottom");
  const teamBTokens = placeTeam(teamB, kind, "top");
  const emptySlots = [
    ...teamATokens.empty.map((slot) => ({ ...slot, variant: "team-a" as const })),
    ...teamBTokens.empty.map((slot) => ({ ...slot, variant: "team-b" as const })),
  ];
  const tokens = [
    ...teamATokens.players.map((token) => ({ ...token, variant: "team-a" as const })),
    ...teamBTokens.players.map((token) => ({ ...token, variant: "team-b" as const })),
  ];

  return (
    <div className="match-pitch" aria-label="Campo completo con alineaciones">
      <div className="pitch-label top">Equipo 2</div>
      <div className="pitch-label bottom">Equipo 1</div>
      <div className="midline" />
      <div className="center-circle" />
      <div className="goal-box top" />
      <div className="goal-box bottom" />
      {tokens.length === 0 ? <p>Marca jugadores como “Voy”.</p> : null}
      {emptySlots.map((slot, index) => (
        <div
          className={`empty-token ${slot.variant}`}
          key={`${slot.variant}-empty-${index}`}
          style={{ left: `${slot.x}%`, top: `${slot.y}%` }}
          title="Falta jugador"
        >
          <b>Falta</b>
        </div>
      ))}
      {tokens.map(({ player, x, y, variant }) => (
        <button
          className={`player-token ${variant} ${player.injured ? "injured-token" : ""} ${player.inactive ? "inactive-token" : ""}`}
          key={player.id}
          style={{ left: `${x}%`, top: `${y}%` }}
          title={`${playerDisplayName(player)} · ${positionLabel(player)} · ${scorePlayer(player).toFixed(1)}`}
        >
          {player.inactive ? (
            <span className="token-inactive" title="Ya no está en el grupo" aria-label="Ya no está en el grupo">
              <UserOffLogo />
            </span>
          ) : null}
          {player.injured ? (
            <span className="token-injury" title="Jugador lesionado" aria-label="Jugador lesionado">
              <HospitalLogo />
            </span>
          ) : null}
          {player.avatar ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img src={player.avatar} alt="" />
          ) : (
            <span>{playerDisplayName(player).slice(0, 2).toUpperCase()}</span>
          )}
          <b>{playerDisplayName(player).split(" ")[0]}</b>
        </button>
      ))}
    </div>
  );
}

function placeTeam(players: Player[], kind: MatchKind, side: "top" | "bottom") {
  const sorted = [...players].sort((a, b) => {
    const order: Record<PositionLine, number> = { Porteria: 0, Defensa: 1, Medio: 2, Ataque: 3 };
    return order[playerPosition(a)] - order[playerPosition(b)] || scorePlayer(b) - scorePlayer(a);
  });
  const slots = formationSlots(kind, side);

  const placedPlayers = sorted.map((player, index) => {
    const preferred = slots.find((slot) => slot.position === playerPosition(player) && !slot.used);
    const fallback = slots.find((slot) => !slot.used) ?? slots[slots.length - 1];
    const slot = preferred ?? fallback;
    slot.used = true;

    if (index >= slots.length) {
      const extraOffset = index - slots.length + 1;
      return {
        player,
        x: 18 + ((extraOffset * 17) % 64),
        y: side === "top" ? 44 : 56,
      };
    }

    return { player, x: slot.x, y: slot.y };
  });

  return {
    players: placedPlayers,
    empty: slots.filter((slot) => !slot.used).map((slot) => ({ x: slot.x, y: slot.y })),
  };
}

function formationSlots(kind: MatchKind, side: "top" | "bottom") {
  const rows: Record<MatchKind, Array<{ position: PositionLine; count: number; y: number }>> = {
    sala: [
      { position: "Porteria", count: 1, y: 6 },
      { position: "Defensa", count: 1, y: 20 },
      { position: "Medio", count: 2, y: 32 },
      { position: "Ataque", count: 1, y: 43 },
    ],
    futbol7: [
      { position: "Porteria", count: 1, y: 6 },
      { position: "Defensa", count: 2, y: 18 },
      { position: "Medio", count: 3, y: 31 },
      { position: "Ataque", count: 1, y: 43 },
    ],
    futbol11: [
      { position: "Porteria", count: 1, y: 5 },
      { position: "Defensa", count: 4, y: 16 },
      { position: "Medio", count: 4, y: 30 },
      { position: "Ataque", count: 2, y: 43 },
    ],
  };

  return rows[kind].flatMap((row) =>
    spreadX(row.count).map((x) => ({
      position: row.position,
      x,
      y: side === "top" ? row.y : 100 - row.y,
      used: false,
    })),
  );
}

function spreadX(count: number) {
  if (count === 1) return [50];
  if (count === 2) return [32, 68];
  const gap = Math.min(70 / (count - 1), 22);
  const start = 50 - (gap * (count - 1)) / 2;
  return Array.from({ length: count }, (_, index) => start + gap * index);
}
