// Local integration QA: browser UI -> authenticated SQL RPCs in a disposable database.
import assert from 'node:assert/strict';
import {execFileSync, spawn} from 'node:child_process';
const {chromium}=await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
const container=process.env.CLAIMS_TEST_CONTAINER;
const database=process.env.CLAIMS_TEST_DATABASE;
assert.match(database ?? '', /^claims_test_/);
assert.ok(container);
const gid='f9620000-0000-4000-8000-000000000010';
const admin='f9620000-0000-4000-8000-000000000001', player='f9620000-0000-4000-8000-000000000002';
const q=(v)=>"'"+String(v).replaceAll("'","''")+"'";
function sql(query){return execFileSync('docker',['exec','-i',container,'psql','-X','-Atq','-v','ON_ERROR_STOP=1','-U','supabase_admin','-d',database],{input:query,encoding:'utf8'}).trim();}
function asUser(uid,query){return `begin; set local role authenticated; set local "request.jwt.claims"=${q(JSON.stringify({sub:uid,role:'authenticated',is_anonymous:false}))}; ${query}; commit;`;}
const browser=await chromium.launch({headless:true,executablePath:process.env.CHROME_EXECUTABLE || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'});
const errors=[];
async function open(uid){
 const page=await browser.newPage({viewport:{width:1280,height:900}});
 page.on('pageerror',e=>errors.push(e.message));
 const user={id:uid,aud:'authenticated',role:'authenticated',email:'qa@example.invalid',user_metadata:{},app_metadata:{provider:'email'}};
 const home={groupId:gid,name:'Equipo QA',teamCode:'CLQA9601',memberCount:3,role:uid===admin?'owner':'player',modality:'futbol7',revision:1,actions:{canInvitePlayers:uid===admin},activeInvitationCount:0};
 await page.route('https://profile-qa.supabase.co/**',async route=>{
  const path=new URL(route.request().url()).pathname;let data=[];
  const body=route.request().postDataJSON() || {};
  try{
   if(path.includes('/auth/v1/user'))data=user;
   else if(path.endsWith('/get_pachanga_player_claims_v1'))data=JSON.parse(sql(asUser(uid,`select public.get_pachanga_player_claims_v1(${q(body.target_group_id)})`)));
   else if(path.endsWith('/request_pachanga_player_claim_v1'))data=JSON.parse(sql(asUser(uid,`select public.request_pachanga_player_claim_v1(${q(body.target_group_id)},${q(body.target_player_id)})`)));
   else if(path.endsWith('/decide_pachanga_player_claim_v1'))data=JSON.parse(sql(asUser(uid,`select public.decide_pachanga_player_claim_v1(${q(body.target_claim_id)},${q(body.decision)})`)));
   else if(path.endsWith('/get_my_pachanga_social_teams_v1'))data=[home];
   else if(path.endsWith('/get_pachanga_social_team_home_v1'))data=home;
   else if(path.endsWith('/get_pachanga_team_players_v1'))data=[{memberKey:'manual',displayName:'Alberto M',role:'player',preferredModality:'futbol7',primaryPosition:'DEL'}];
   else if(path.endsWith('/get_pachanga_social_team_feature_flags_v1'))data={socialTeamHomeV3fEnabled:true};
   else if(path.endsWith('/get_my_pachanga_social_profile_v1'))data={displayName:'Perfil QA',primaryPosition:'DEL',preferredModality:'futbol7'};
   await route.fulfill({status:200,contentType:'application/json',body:JSON.stringify(data)});
  }catch(e){await route.fulfill({status:400,contentType:'application/json',body:JSON.stringify({message:String(e.stderr || e.message)})});}
 });
 await page.addInitScript(({user})=>{const jwt=btoa(JSON.stringify({alg:'HS256'}))+'.'+btoa(JSON.stringify({sub:user.id,role:'authenticated',exp:Math.floor(Date.now()/1000)+3600}))+'.qa';localStorage.setItem('sb-profile-qa-auth-token',JSON.stringify({access_token:jwt,refresh_token:'qa',expires_in:3600,expires_at:Math.floor(Date.now()/1000)+3600,user,token_type:'bearer'}));},{user});
 await page.goto('http://127.0.0.1:3191/equipo/plantilla?team='+gid);
 await page.locator('[data-social-team-status="ready"]').waitFor();
 return page;
}
try{
 const p=await open(player);
 await p.getByRole('button',{name:'Esta es mi ficha',exact:true}).first().click();
 await p.getByRole('button',{name:'Enviar solicitud',exact:true}).click();
 await p.getByText('Tu solicitud',{exact:true}).waitFor();
 assert.equal(sql(`select count(*) from private.pachanga_player_claims_v1 where requester_id=${q(player)} and state='PENDING'`),'1');
 const a=await open(admin);
 await a.getByRole('button',{name:'Revisar y vincular',exact:true}).click();
 await a.getByText('Coincidir en el nombre no basta.',{exact:false}).waitFor();
 for(const [theme,width] of [['dark',1280],['dark',390],['light',390]]){
  await a.setViewportSize({width,height:844});
  await a.evaluate(theme=>document.documentElement.setAttribute('data-theme',theme),theme);
  await a.getByRole('group',{name:'Confirmar vinculación'}).scrollIntoViewIfNeeded();
  assert.ok(await a.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1));
  await a.screenshot({path:`/tmp/claims-${theme}-${width}.png`});
 }
 await a.getByRole('button',{name:'He comprobado su identidad · Vincular',exact:true}).click();
 await a.getByText('No hay solicitudes pendientes.',{exact:true}).waitFor();
 await p.reload();
 await p.getByText('Tu ficha de',{exact:false}).waitFor();
 assert.equal(sql(`select payload->'players'->0->>'ownerUserId' from public.pachanga_groups where id=${q(gid)}`),player);
 assert.equal(sql(`select rating from public.pachanga_player_profiles where user_id=${q(player)}`),'7');
 assert.deepEqual(errors,[]);
 console.log('PASS: requester sends -> admin explicit confirmation -> persisted link -> requester sees approved; desktop/mobile/light; no runtime errors.');
 // Two concurrent approvals for one unowned player: only one may win.
 const b='f9620000-0000-4000-8000-000000000003',c='f9620000-0000-4000-8000-000000000005';
 sql(`insert into auth.users(id,email) values(${q(c)},'claim-concurrent@example.test'); insert into public.pachanga_group_members(group_id,user_id,role,display_name) values(${q(gid)},${q(c)},'player','Same name');`);
 const ids=[b,c].map(uid=>JSON.parse(sql(asUser(uid,`select public.request_pachanga_player_claim_v1(${q(gid)},'other-manual')`))).requestId);
 const results=await Promise.all(ids.map((id,i)=>new Promise(resolve=>{
  const child=spawn('docker',['exec','-i',container,'psql','-X','-Atq','-v','ON_ERROR_STOP=1','-U','supabase_admin','-d',database]);let stderr='';child.stderr.on('data',d=>stderr+=d);child.on('close',code=>resolve({code,stderr}));
  child.stdin.end(asUser(admin,`select public.decide_pachanga_player_claim_v1(${q(id)},'approve')`).replace('begin;', i===0 ? `begin; select id from public.pachanga_groups where id=${q(gid)} for update; select pg_sleep(0.3);` : 'begin;'));
 })));
 assert.equal(results.filter(r=>r.code===0).length,1);assert.match(results.find(r=>r.code!==0).stderr,/CLAIM_ALREADY_DECIDED/);
 assert.equal(sql(`select count(*) from private.pachanga_player_claims_v1 where group_id=${q(gid)} and player_id='other-manual' and state='APPROVED'`),'1');
 console.log('PASS: simultaneous approvals serialize to exactly one owner; other request superseded.');
}finally{await browser.close();}
