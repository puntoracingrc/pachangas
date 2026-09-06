import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import ts from 'typescript';
const source=readFileSync(new URL('../app/page.tsx',import.meta.url),'utf8');
function extract(name:string){
 const tree=ts.createSourceFile('page.tsx',source,ts.ScriptTarget.Latest,true,ts.ScriptKind.TSX);let found='';
 function visit(node:ts.Node){if(ts.isFunctionDeclaration(node)&&node.name?.text===name)found=node.getText(tree);ts.forEachChild(node,visit);}visit(tree);
 assert.ok(found,name);return ts.transpileModule(found,{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.None}}).outputText;
}
test('explicitly empty calendars remain empty after server or cache normalization',()=>{
 const normalize=new Function('defaultPayload','normalizeSiteSettings','normalizeVenue',`${extract('normalizePayload')};return normalizePayload;`)(()=>({matches:[],players:[],venues:[]}),()=>({}),(v:unknown)=>v);
 let payload={matches:[],players:[],venues:[],activeMatchId:'deleted'};
 for(let i=0;i<3;i++){payload=normalize(JSON.parse(JSON.stringify(payload)));assert.deepEqual(payload.matches,[]);assert.equal(payload.activeMatchId,'');}
 assert.match(source,/matches\[0\] \?\? emptyCalendarMatch/);
});
function harness({remote=true,admin=true,confirm=true,result={data:{payload:{matches:[]}}},rpc}:any={}){
 const state={matches:[{id:'draft',configured:false}],active:'draft',error:'',busy:null as string|null,removed:new Set<string>(),calls:0,commits:0,refreshes:0};
 const flight={current:false};const noop=()=>{};
 const context:any={canUseAdminControls:admin,discardDraftInFlightRef:flight,matches:state.matches,activeMatch:{id:'draft'},activeMatchId:'draft',window:{confirm:()=>confirm},setDiscardingDraftId:(v:string|null)=>state.busy=v,setQuickMatchError:(v:string)=>state.error=v,saveTimerRef:{current:null},hasRealTeam:remote,supabase:{rpc:async(...args:any[])=>{state.calls++;assert.equal(args[0],'discard_pachanga_match_draft_v1');assert.equal(args[1].target_match_id,'draft');assert.equal('next_payload' in args[1],false);return rpc?rpc():result;}},remoteGroupId:'group',remoteReady:true,id:()=> 'operation',remotePayloadRevisionRef:{current:7},clientOperationMetadata:()=>({}),isRemoteRevisionConflict:(s:string)=>s.includes('revision'),loadTeams:async()=>{state.refreshes++;},applyRemoteCommit:(data:any)=>{state.matches=data.payload.matches;state.commits++;},setSyncStatus:noop,setSyncError:noop,setMatches:(v:any)=>state.matches=v,setActiveMatchId:(v:string)=>state.active=v,setDiscardedMatchDraftIds:(f:any)=>state.removed=f(state.removed),setQuickMatchDraft:noop,setMatchExperienceView:noop};
 const discard=new Function(...Object.keys(context),`${extract('discardQuickMatchDraft')};return discardQuickMatchDraft;`)(...Object.values(context));
 return {state,discard,flight};
}
test('success removes the server-confirmed draft; local last draft also leaves an empty calendar',async()=>{
 for(const remote of [true,false]){const h=harness({remote});await h.discard('draft');assert.deepEqual(h.state.matches,[]);assert.equal(h.state.busy,null);assert.equal(h.state.error,'');if(!remote)assert.equal(h.state.active,'');}
});
test('failed and malformed responses keep the draft and display an error',async()=>{
 for(const result of [{error:{message:'server unavailable'}},{data:null},{data:{payload:{matches:[{id:'draft'}]}}}]){const h=harness({result});await h.discard('draft');assert.equal(h.state.matches.length,1);assert.equal(h.state.removed.size,0);assert.ok(h.state.error);assert.equal(h.state.busy,null);}
});
test('revision conflicts reload server state and require a new explicit discard',async()=>{
 const h=harness({result:{error:{message:'Server revision is newer'}}});await h.discard('draft');assert.equal(h.state.refreshes,1);assert.equal(h.state.calls,1);assert.match(h.state.error,/equipo ha cambiado/);assert.equal(h.state.removed.size,0);
});
test('double clicks only send one command and keep the draft visible while waiting',async()=>{
 let resolve!:(v:any)=>void;const pending=new Promise(r=>resolve=r);const h=harness({rpc:()=>pending});const first=h.discard('draft');await h.discard('draft');assert.equal(h.state.calls,1);assert.equal(h.state.busy,'draft');assert.equal(h.state.matches.length,1);resolve({data:{payload:{matches:[]}}});await first;assert.equal(h.flight.current,false);
});
test('cancel and non-admin access cannot discard',async()=>{
 for(const options of [{confirm:false},{admin:false}]){const h=harness(options);await h.discard('draft');assert.equal(h.state.calls,0);assert.equal(h.state.matches.length,1);}
});
