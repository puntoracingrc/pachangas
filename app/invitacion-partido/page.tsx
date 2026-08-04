"use client";

import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { Suspense, useCallback, useEffect, useState } from "react";
import type { User } from "@supabase/supabase-js";
import { supabase } from "../supabaseClient";

const googleClientId = process.env.NEXT_PUBLIC_GOOGLE_CLIENT_ID;
const googleAuthNonceKey = "pachanga-google-auth-nonce";
const googleAuthReturnKey = "pachanga-google-auth-return";
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

type InvitationPreview = {
  groupName: string;
  invitation: {
    expiresAt?: string;
    revision: number;
    serverSequence: number;
    status: "accepted" | "cancelled" | "expired" | "pending" | "rejected";
  };
  match: {
    confirmedCount: number;
    date?: string;
    finalized: boolean;
    id: string;
    kind?: string;
    lineupClosed: boolean;
    place?: unknown;
    targetPlayers: number;
    title: string;
  };
  matchRevision: number;
};

function createGoogleRawNonce() {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return btoa(String.fromCharCode(...bytes));
}

function expandCompactToken(value: string) {
  if (!value || uuidPattern.test(value)) return value;
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

async function sha256Hex(value: string) {
  const encoded = new TextEncoder().encode(value);
  const buffer = await crypto.subtle.digest("SHA-256", encoded);
  return Array.from(new Uint8Array(buffer), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

function normalizePreview(value: unknown): InvitationPreview | null {
  if (!value || typeof value !== "object") return null;
  const row = value as Record<string, unknown>;
  const invitation = row.invitation as Record<string, unknown> | undefined;
  const match = row.match as Record<string, unknown> | undefined;
  if (!invitation || !match || typeof match.id !== "string") return null;
  const rawStatus = invitation.status;
  const status = rawStatus === "accepted" || rawStatus === "cancelled" || rawStatus === "expired" || rawStatus === "rejected"
    ? rawStatus
    : "pending";
  return {
    groupName: typeof row.groupName === "string" ? row.groupName : "Grupo de pachangas",
    invitation: {
      expiresAt: typeof invitation.expiresAt === "string" ? invitation.expiresAt : undefined,
      revision: Math.max(1, Math.floor(Number(invitation.revision) || 1)),
      serverSequence: Math.max(0, Math.floor(Number(invitation.serverSequence) || 0)),
      status,
    },
    match: {
      confirmedCount: Math.max(0, Math.floor(Number(match.confirmedCount) || 0)),
      date: typeof match.date === "string" ? match.date : undefined,
      finalized: Boolean(match.finalized),
      id: match.id,
      kind: typeof match.kind === "string" ? match.kind : undefined,
      lineupClosed: Boolean(match.lineupClosed),
      place: match.place,
      targetPlayers: Math.max(0, Math.floor(Number(match.targetPlayers) || 0)),
      title: typeof match.title === "string" ? match.title : "Partido",
    },
    matchRevision: Math.max(0, Math.floor(Number(row.matchRevision) || 0)),
  };
}

function displayDate(value?: string) {
  if (!value) return "Fecha por confirmar";
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) return value;
  return new Intl.DateTimeFormat("es-ES", { dateStyle: "full", timeStyle: "short" }).format(parsed);
}

function displayPlace(value: unknown) {
  if (typeof value === "string") return value;
  if (!value || typeof value !== "object") return "Campo por confirmar";
  const place = value as Record<string, unknown>;
  return [place.name, place.address, place.city].find((item): item is string => typeof item === "string" && item.trim().length > 0)
    ?? "Campo por confirmar";
}

function operationMetadata() {
  return {
    orientation: window.matchMedia("(orientation: landscape)").matches ? "landscape" : "portrait",
    surface: window.matchMedia("(display-mode: standalone)").matches ? "pwa-match-invitation" : "web-match-invitation",
  };
}

export function MatchInvitationContent({ invitationToken }: { invitationToken?: string } = {}) {
  const searchParams = useSearchParams();
  const token = expandCompactToken(invitationToken ?? searchParams.get("t") ?? "");
  const [preview, setPreview] = useState<InvitationPreview | null>(null);
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);
  const [responding, setResponding] = useState(false);
  const [message, setMessage] = useState("");

  const load = useCallback(async () => {
    if (!supabase || !token) {
      setLoading(false);
      return;
    }
    const [session, invitation] = await Promise.all([
      supabase.auth.getSession(),
      supabase.rpc("get_pachanga_match_link_invitation_v1", { invitation_token: token }),
    ]);
    setUser(session.data.session?.user ?? null);
    if (invitation.error) {
      setMessage(invitation.error.message);
      setPreview(null);
    } else {
      setPreview(normalizePreview(invitation.data));
      setMessage("");
    }
    setLoading(false);
  }, [token]);

  useEffect(() => {
    const timeout = window.setTimeout(() => void load(), 0);
    return () => window.clearTimeout(timeout);
  }, [load]);

  async function signInWithGoogle() {
    if (!googleClientId) {
      setMessage("Falta configurar el acceso con Google.");
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

  async function respond(nextStatus: "accepted" | "rejected") {
    if (!supabase || !preview || !user || preview.invitation.status !== "pending") return;
    setResponding(true);
    setMessage("");
    const result = await supabase.rpc("respond_pachanga_match_link_invitation_v1", {
      client_metadata: operationMetadata(),
      expected_invitation_revision: preview.invitation.revision,
      expected_match_revision: preview.matchRevision,
      invitation_token: token,
      next_status: nextStatus,
      operation_id: crypto.randomUUID(),
    });
    if (result.error) {
      setMessage(result.error.message);
      await load();
      setResponding(false);
      return;
    }
    const response = result.data as { accessId?: string } | null;
    if (nextStatus === "accepted" && response?.accessId) {
      window.location.replace(`/partido-invitado?acceso=${encodeURIComponent(response.accessId)}`);
      return;
    }
    setMessage("Has rechazado la invitación. No se ha concedido acceso al grupo ni al partido.");
    await load();
    setResponding(false);
  }

  if (!token || !supabase) {
    return <main className="match-invitation-page"><section><h1>Invitación no disponible</h1><p>{token ? "Supabase no está configurado." : "Falta el token de invitación."}</p><Link href="/">Volver</Link></section></main>;
  }
  if (loading) return <main className="match-invitation-page"><section><p>Cargando invitación segura...</p></section></main>;
  if (!preview) return <main className="match-invitation-page"><section><h1>No podemos abrir esta invitación</h1><p>{message || "El enlace no es válido."}</p><Link href="/">Volver</Link></section></main>;

  const active = preview.invitation.status === "pending" && !preview.match.finalized && !preview.match.lineupClosed;
  return (
    <main className="match-invitation-page">
      <section className="match-invitation-card">
        <header>
          <span>Invitación únicamente a este partido</span>
          <h1>{preview.match.title}</h1>
          <p>{preview.groupName}</p>
        </header>
        <div className="match-invitation-facts">
          <div><span>Fecha</span><strong>{displayDate(preview.match.date)}</strong></div>
          <div><span>Campo</span><strong>{displayPlace(preview.match.place)}</strong></div>
          <div><span>Modalidad</span><strong>{preview.match.kind || "Fútbol"}</strong></div>
          <div><span>Confirmados</span><strong>{preview.match.confirmedCount}/{preview.match.targetPlayers}</strong></div>
        </div>
        <p className="match-invitation-privacy">Aceptar permite ver este partido y su alineación en tiempo real. No te hace miembro, admin ni owner del grupo, y no muestra teléfonos, pagos ni configuración privada.</p>
        {message ? <p className="match-invitation-message">{message}</p> : null}
        {active && !user ? (
          <button className="match-invitation-google" type="button" onClick={() => void signInWithGoogle()} disabled={!googleClientId}>Continuar con Google</button>
        ) : null}
        {active && user ? (
          <div className="match-invitation-actions">
            <button type="button" onClick={() => void respond("accepted")} disabled={responding}>Aceptar invitación</button>
            <button className="secondary" type="button" onClick={() => void respond("rejected")} disabled={responding}>Rechazar</button>
          </div>
        ) : null}
        {!active ? <p className="match-invitation-closed">Esta invitación está {preview.invitation.status === "expired" ? "caducada" : preview.invitation.status === "rejected" ? "rechazada" : preview.invitation.status === "accepted" ? "aceptada" : "cerrada"}.</p> : null}
        <Link href="/">Volver a Pachangas IQ</Link>
      </section>
    </main>
  );
}

export default function MatchInvitationPage() {
  return <Suspense fallback={<main className="match-invitation-page"><section><p>Cargando invitación segura...</p></section></main>}><MatchInvitationContent /></Suspense>;
}
