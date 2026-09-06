import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import ts from 'typescript';

const source = readFileSync(new URL('../app/page.tsx', import.meta.url), 'utf8');
function extractFunction(name: string) {
  const tree = ts.createSourceFile('page.tsx', source, ts.ScriptTarget.Latest, true, ts.ScriptKind.TSX);
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
  const state = { id: null as string | null, name: '', members: [] as unknown[] };
  const ref = { current: null as string | null };
  const noop = () => {};
  const names = ['authUserIdRef','setAuthUser','setCurrentUserId','setProfileName','setCanonicalSocialProfile','setSocialProfileResolved','setPlayerCardOnboardingMessage','setPlayerCardOnboardingStatus','isAnonymousAuthUser','authDisplayName','setTeamMembers','displayName'];
  const args = [ref,noop,(id: string | null) => {state.id=id;},(name: string) => {state.name=name;},noop,noop,noop,noop,(u: {is_anonymous?:boolean})=>u.is_anonymous,(u:{name:string})=>u.name,(members:unknown[])=>{state.members=members;},(s:string)=>s];
  const functions = new Function(...names, `${extractFunction('updateAuthState')}\n${extractFunction('loadTeamMembers')}\nreturn {updateAuthState,loadTeamMembers};`)(...args);
  return {state,functions};
}

test('switching accounts resets the name and signing out clears it', () => {
  const {state,functions} = harness();
  functions.updateAuthState({id:'account-a',name:'A'});state.name='Edited A';
  functions.updateAuthState({id:'account-a',name:'A'});assert.equal(state.name,'Edited A');
  functions.updateAuthState({id:'account-b',name:'B'});assert.equal(state.name,'B');
  functions.updateAuthState(null);assert.equal(state.name,'');
  assert.doesNotMatch(source,/pachanga-iq-profile-name|profileNameKey/,'the unscoped browser cache is never reused');
});

test('a delayed membership response from the previous account cannot overwrite the new identity', async () => {
  const {state,functions} = harness();
  let resolve!: (value: unknown) => void;
  const pending = new Promise(r=>{resolve=r;});
  const client = {from:()=>({select:()=>({eq:()=>({order:()=>pending})})})};
  functions.updateAuthState({id:'account-a',name:'A'});
  const request = functions.loadTeamMembers(client,'team-a');
  functions.updateAuthState({id:'account-b',name:'B'});
  resolve({data:[{user_id:'account-a',display_name:'Saved A',role:'owner'}],error:null});
  await request;
  assert.equal(state.name,'B');assert.deepEqual(state.members,[]);
});
