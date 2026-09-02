import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import {
  marketQueryPhase,
  marketRequestPresentation,
  visibleMarketResultCount,
  type MarketDataSource,
  type MarketRequestVisualStatus,
} from "../app/mercado/marketplace-ui-state";

const source = (path: string) => readFile(new URL(`../${path}`, import.meta.url), "utf8");

test("SOCIAL-RC-004 distinguishes every Market query phase before showing a count", () => {
  const cases: Array<[MarketDataSource, number, boolean, ReturnType<typeof marketQueryPhase>, number | null]> = [
    ["IDLE", 0, true, "IDLE", null],
    ["LOADING", 0, true, "LOADING", null],
    ["UNAVAILABLE", 0, true, "UNAVAILABLE", null],
    ["UNAVAILABLE", 0, false, "OFFLINE_NO_CACHE", null],
    ["LIVE", 0, true, "READY_EMPTY", 0],
    ["LIVE", 12, true, "READY_WITH_RESULTS", 12],
    ["CACHED", 4, false, "CACHED", 4],
  ];

  for (const [dataSource, count, online, phase, visibleCount] of cases) {
    const actualPhase = marketQueryPhase(dataSource, count, online);
    assert.equal(actualPhase, phase);
    assert.equal(visibleMarketResultCount(actualPhase, count), visibleCount);
  }
});

test("SOCIAL-RC-004 unauthenticated Market starts unqueried and never renders a provisional zero", async () => {
  const market = await source("app/mercado/marketplace-client.tsx");
  assert.match(market, /setMatchSource\("IDLE"\)/);
  assert.match(market, /confirmedResultCount !== null \? \(/);
  assert.match(market, /matchSource === "IDLE"/);
  assert.match(market, /Inicia sesión para buscar partidos abiertos/);
  assert.match(market, /marketQueryPhase\(activeSource, resultCount, online\)/);
  assert.match(market, /visibleMarketResultCount\(resultPhase, resultCount \?\? 0\)/);
});

test("SOCIAL-RC-010 exposes one consistent presentation for all request states", () => {
  const expected: Record<MarketRequestVisualStatus, [string, string | null]> = {
    accepted: ["Ver partido", "Plaza confirmada"],
    cancelled: ["Solicitar de nuevo", "Solicitud cancelada"],
    idle: ["Solicitar plaza", null],
    pending: ["Solicitud enviada", "Solicitud enviada"],
    rejected: ["Solicitar de nuevo", "Solicitud no aceptada"],
    sending: ["Enviando...", "Enviando solicitud"],
  };

  for (const [status, [actionLabel, statusLabel]] of Object.entries(expected) as Array<[MarketRequestVisualStatus, [string, string | null]]>) {
    const presentation = marketRequestPresentation(status);
    assert.equal(presentation.actionLabel, actionLabel);
    assert.equal(presentation.statusLabel, statusLabel);
    if (status !== "idle") assert.match(presentation.detail ?? "", /Remote writes = 0/);
  }
});

test("SOCIAL-RC-010 Demo request is single-submit and visible in card and open detail", async () => {
  const demo = await source("app/demo-world/demo-world-app.tsx");
  assert.match(demo, /setDemoSpotRequest\("sending"\)/);
  assert.match(demo, /requestAnimationFrame\(\(\) => \{[\s\S]*setDemoSpotRequest\(\(current\) => current === "sending" \? "pending" : current\)/);
  assert.match(demo, /demoSpotRequestFrame\.current !== null \|\| \(demoSpotMatchId === matchId && demoSpotRequest !== "idle"\)/);
  assert.match(demo, /selectedMatchRequestPresentation\.statusLabel/);
  assert.match(demo, /selectedMatchRequestPresentation\.detail/);
  assert.match(demo, /marketRequestPresentation\(requestForMatch\)\.statusLabel/);
  assert.match(demo, /disabled=\{offline \|\| requestForMatch !== "idle"\}/);
  assert.match(demo, /Necesitas conexión para solicitar una plaza\./);
});

test("SOCIAL-RC-006 attendance notice opens its exact match and resolves locally for a team actor", async () => {
  const demo = await source("app/demo-world/demo-world-app.tsx");
  assert.match(demo, /const canRespondAttendance = currentTeamInMatch && \(perspective\.role === "admin" \|\| perspective\.role === "player"\)/);
  assert.match(demo, /itemId === DEMO_SOCIAL_ATTENDANCE_ID && socialAttendanceMatch[\s\S]*openMatch\(socialAttendanceMatch\.id\);[\s\S]*return;/);
  assert.match(demo, /onBack=\{closeMatchDetail\}/);
  assert.match(demo, /attendanceByMatch: \{ \.\.\.current\.attendanceByMatch, \[demoAttendanceKey\(currentPlayer\.id, selectedMatch\.id\)\]: status \}/);
  assert.match(demo, /Remote writes: 0/);
});

test("SOCIAL-RC-006 returning to Avisos recomputes the badge and removes the duplicate Home action", async () => {
  const demo = await source("app/demo-world/demo-world-app.tsx");
  assert.match(demo, /const socialAttendanceStatus = socialAttendanceMatch \? session\.attendanceByMatch/);
  assert.match(demo, /resolved: socialAttendanceStatus !== null/);
  assert.match(demo, /const socialPendingCount = socialInboxActions\.filter\(\(action\) => !action\.resolved\)\.length/);
  assert.match(demo, /const primaryPendingAction = pendingActions\.find\(\(action\) => !action\.resolved\) \?\? null/);
  assert.match(demo, /params\.get\("matchView"\) === "detail"[\s\S]*window\.history\.back\(\)/);
});

test("SOCIAL-RC-008 Market detail has modal semantics, focus containment and safe cleanup", async () => {
  const detail = await source("app/mercado/market-detail-sheet.tsx");
  assert.match(detail, /<div ref=\{dialogRef\}[^>]*role="dialog"[^>]*aria-modal="true"/);
  assert.doesNotMatch(detail, /<aside[^>]*role="dialog"/);
  assert.match(detail, /closeRef\.current\?\.focus\(\{ preventScroll: true \}\)/);
  assert.match(detail, /event\.key === "Escape"/);
  assert.match(detail, /event\.key !== "Tab"/);
  assert.match(detail, /event\.shiftKey/);
  assert.match(detail, /sibling\.inert = true/);
  assert.match(detail, /document\.body\.style\.overflow = "hidden"/);
  assert.match(detail, /restoreBackground\(\)/);
  assert.match(detail, /opener\?\.isConnected/);
});

test("SOCIAL-RC-001 Demo navigation writes real entries and restores Back and Forward via popstate", async () => {
  const demo = await source("app/demo-world/demo-world-app.tsx");
  assert.match(demo, /window\.history\.pushState\(demoHistoryState\(entry\)/);
  assert.match(demo, /window\.addEventListener\("popstate", restoreDemoRoute\)/);
  assert.match(demo, /window\.removeEventListener\("popstate", restoreDemoRoute\)/);
  assert.match(demo, /writeDemoRoute\(params, "route", activeTab === tab \? "replace" : "push"\)/);
  assert.match(demo, /params\.set\("matchView", "detail"\)/);
  assert.match(demo, /onOpen=\{openMatch\}/);
});

test("SOCIAL-RC-001 direct Demo deep links receive one safe internal fallback", async () => {
  const demo = await source("app/demo-world/demo-world-app.tsx");
  assert.match(demo, /const hasDeepContext = initialTab !== "inicio"/);
  assert.match(demo, /fallbackParams\.set\("tab", "inicio"\)/);
  assert.match(demo, /window\.history\.replaceState\(demoHistoryState\("fallback"\)/);
  assert.match(demo, /window\.history\.pushState\(demoHistoryState\("route"\), "", originalUrl\)/);
});

test("cross-flow history preserves Market detail and Match return context without a parallel authority", async () => {
  const demo = await source("app/demo-world/demo-world-app.tsx");
  assert.match(demo, /writeMarketHistory\("market-detail", pane, nextDetailId\)/);
  assert.match(demo, /window\.history\.state\.demoEntry === "market-detail"[\s\S]*window\.history\.back\(\)/);
  assert.match(demo, /onMatch=\{openMatch\}/);
  assert.match(demo, /onPendingAction=\{\(action\) => openSocialInboxItem\(action\.targetTab, action\.id\)\}/);
  assert.doesNotMatch(demo, /localHistoryStack|demoHistoryStack/);
});
