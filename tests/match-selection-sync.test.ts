import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import ts from 'typescript';

const source = readFileSync(new URL('../app/page.tsx', import.meta.url), 'utf8');
const tree = ts.createSourceFile('page.tsx', source, ts.ScriptTarget.Latest, true, ts.ScriptKind.TSX);
function extract(name: string) {
  let found = '';
  function visit(node: ts.Node) {
    if (ts.isFunctionDeclaration(node) && node.name?.text === name) found = node.getText(tree);
    ts.forEachChild(node, visit);
  }
  visit(tree);
  assert.ok(found, name);
  return ts.transpileModule(found, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.None } }).outputText;
}
function harness() {
  const state = { active: 'published', matches: [] as any[], revision: 0 };
  const noop = () => {};
  const context = {
    applyingRemoteRef: { current: false }, lastCommittedPayloadJsonRef: { current: '' },
    serializePayload: JSON.stringify, setPlayers: noop, setVenues: noop, setSiteSettings: noop,
    setMatches: (matches: any[]) => state.matches = matches,
    setActiveMatchId: (next: any) => state.active = typeof next === 'function' ? next(state.active) : next,
    setRemoteRevision: (revision: number) => state.revision = revision,
    window: { setTimeout: noop }, normalizePayload: (payload: any) => payload,
    applyBillingFromCommit: noop, remoteGroupId: null, setSyncStatus: noop, setSyncError: noop,
  };
  const api = new Function(...Object.keys(context), `${extract('applyPayload')}\n${extract('applyRemoteCommit')}\nreturn {applyPayload,applyRemoteCommit};`)(...Object.values(context));
  return { state, ...api };
}
const payload = (status: string) => ({ activeMatchId: 'draft', players: [], venues: [], siteSettings: {}, matches: [
  { id: 'draft', configured: false, players: [] },
  { id: 'published', configured: true, players: [{ playerId: 'self', status }, { playerId: 'other', status: 'voy' }] },
] });

test('Voy → Duda → Voy applies authoritative attendance without jumping to the shared draft', () => {
  const h = harness();
  for (const [i, status] of ['voy', 'duda', 'voy'].entries()) {
    h.applyRemoteCommit({ payload: payload(status), confirmedRevision: i + 1 });
    assert.equal(h.state.active, 'published');
    assert.equal(h.state.matches.find((m: any) => m.id === h.state.active).players[0].status, status);
    assert.equal(h.state.matches[1].players[1].status, 'voy');
    assert.equal(h.state.revision, i + 1);
  }
});
test('a late response respects a newer local selection; removed matches fall back to the server selection', () => {
  const h = harness();
  h.state.active = 'draft';
  h.applyRemoteCommit({ payload: { ...payload('duda'), activeMatchId: 'published' } });
  assert.equal(h.state.active, 'draft');
  h.applyRemoteCommit({ payload: { ...payload('duda'), activeMatchId: 'published', matches: [payload('duda').matches[1]] } });
  assert.equal(h.state.active, 'published');
  h.applyRemoteCommit({ payload: { ...payload('duda'), activeMatchId: '', matches: [] } });
  assert.equal(h.state.active, '');
});
test('initial loading and switching teams use the incoming selection even with overlapping match ids', () => {
  const h = harness();
  h.applyPayload(payload('voy'), 8);
  assert.equal(h.state.active, 'draft');
});
test('realtime and same-team reloads preserve navigation; a confirmation cannot affect a different match', () => {
  assert.match(source, /applyPayload\(normalizePayload\(data.payload as Partial<AppPayload>\), confirmedRevision, true\)/);
  assert.match(source, /applyPayload\(selectedTeam.payload, selectedTeam.payloadRevision, refreshingCurrentTeam\)/);
  const calls: unknown[] = [];
  const confirm = new Function('statusConfirmation', 'activeMatch', 'setStatusConfirmation', 'setStatus', `${extract('confirmStatusChange')};return confirmStatusChange;`);
  for (const activeId of ['published', 'draft']) {
    calls.length = 0;
    confirm({ matchId: 'published', playerId: 'self', nextStatus: 'duda' }, { id: activeId }, () => {}, (...args: unknown[]) => calls.push(args))();
    assert.equal(calls.length, activeId === 'published' ? 1 : 0);
  }
});
