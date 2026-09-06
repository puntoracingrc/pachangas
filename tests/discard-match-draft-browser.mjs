// Actual home UI -> authenticated SQL command -> persisted reload, in an isolated database.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
const {chromium}=await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
const database=process.env.DISCARD_TEST_DATABASE, container=process.env.DISCARD_TEST_CONTAINER;
assert.match(database??'',/^discard_test_/);assert.ok(container);
const gid='f9630000-0000-4000-8000-000000000010',uid='f9630000-0000-4000-8000-000000000001';
const q=v=>"'"+String(v).replaceAll("'","''")+"'";
function sql(s){return execFileSync('docker',['exec','-i',container,'psql','-X','-Atq','-v','ON_ERROR_STOP=1','-U','supabase_admin','-d',database],{input:s,encoding:'utf8'}).trim();}
function asUser(s){return `begin; set local role authenticated; set local "request.jwt.claims"=${q(JSON.stringify({sub:uid,role:'authenticated',is_anonymous:false}))};${s};commit;`;}
const match=(id,configured)=>({id,title:configured?'Partido confirmado':'Borrador QA',configured,date:'2099-09-12T21:00',season:'2099-2100',place:'Campo QA',kind:'futbol7',targetPlayers:14,fieldCost:0,players:[],reserveLimit:0});
function seed(matches){sql(`update public.pachanga_groups set payload=jsonb_build_object('matches',${q(JSON.stringify(matches))}::jsonb,'activeMatchId',${q(matches[0]?.id??'')},'players','[]'::jsonb,'venues','[]'::jsonb,'siteSettings','{"brand":"Equipo QA"}'::jsonb) where id=${q(gid)}`);}
function group(){return JSON.parse(sql(`select row_to_json(g) from public.pachanga_groups g where id=${q(gid)}`));}
seed([match('draft',false),match('published',true)]);
const browser=await chromium.launch({headless:true,executablePath:process.env.CHROME_EXECUTABLE || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'});
const page=await browser.newPage({viewport:{width:1280,height:900}}),errors=[];page.on('pageerror',e=>errors.push(e.message));
const user={id:uid,aud:'authenticated',role:'authenticated',email:'qa@example.invalid',user_metadata:{},app_metadata:{provider:'email'}};
let failNext=false,commands=0;
await page.route('**/api/ratings/assessment',route=>route.fulfill({json:{assessments:{initial:{completedAt:'2026-09-06T13:00:00Z'}}}}));
await page.route('https://profile-qa.supabase.co/**',async route=>{
 const url=new URL(route.request().url()),p=url.pathname,body=route.request().postDataJSON()||{};let data=[];
 try{
  if(p.includes('/auth/v1/user'))data=user;
  else if(p.endsWith('/pachanga_group_members'))data=url.searchParams.get('select')?.includes('pachanga_groups')?[{group_id:gid,role:'owner',pachanga_groups:group()}]:[{user_id:uid,display_name:'Admin QA',role:'owner'}];
  else if(p.endsWith('/pachanga_groups'))data=group();
  else if(p.endsWith('/get_my_pachanga_social_profile_v1'))data={displayName:'Admin QA',primaryPosition:'DEL',birthDate:'1990-01-01',preferredModality:'futbol7',generalArea:'Barcelona'};
  else if(p.endsWith('/discard_pachanga_match_draft_v1')){
   commands++;if(failNext){failNext=false;throw new Error('Temporary failure');}
   assert.equal('next_payload' in body,false);
   data=JSON.parse(sql(asUser(`select public.discard_pachanga_match_draft_v1(${q(body.target_group_id)},${q(body.target_match_id)},${q(body.operation_id)},${Number(body.expected_revision)},'{}')`)));
  }else if(p.endsWith('/save_pachanga_payload_authoritative_v2')){
   data=JSON.parse(sql(asUser(`select public.save_pachanga_payload_authoritative_v2(${q(gid)},${Number(body.expected_revision)},${q(JSON.stringify(body.next_payload))}::jsonb,${q(body.operation_id)},'{}')`)));
  }
  await route.fulfill({status:200,contentType:'application/json',body:JSON.stringify(data)});
 }catch(e){await route.fulfill({status:400,contentType:'application/json',body:JSON.stringify({message:String(e.stderr||e.message)})});}
});
await page.addInitScript(({user})=>{const token=btoa(JSON.stringify({alg:'HS256'}))+'.'+btoa(JSON.stringify({sub:user.id,role:'authenticated',exp:Math.floor(Date.now()/1000)+3600}))+'.qa';localStorage.setItem('sb-profile-qa-auth-token',JSON.stringify({access_token:token,refresh_token:'qa',expires_at:Math.floor(Date.now()/1000)+3600,user,token_type:'bearer'}));},{user});
const overview=page.locator('[data-official-match-experience="v3b"][data-view="overview"]');
async function calendar(){await page.getByLabel('Navegación principal',{exact:true}).getByRole('button',{name:'Partidos',exact:true}).click();await overview.waitFor();}
async function discard(){page.once('dialog',d=>d.accept());await overview.getByRole('button',{name:'Descartar',exact:true}).click();}
try{
 await page.goto('http://127.0.0.1:3191/?equipo=DRQA9601');await calendar();
 // Error stays visible, draft stays available, action menu isn't optimistically lost.
 failNext=true;await discard();await overview.getByRole('alert').waitFor();assert.equal(await overview.getByRole('button',{name:'Descartar',exact:true}).count(),1);
 for(const width of [390,1280]){await page.setViewportSize({width,height:900});assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1));await overview.screenshot({path:`/tmp/discard-error-${width}.png`});}
 await discard();await overview.getByRole('button',{name:'Descartar',exact:true}).waitFor({state:'detached'});
 assert.deepEqual(group().payload.matches.map(m=>m.id),['published']);await page.reload();await calendar();assert.equal(await overview.getByRole('button',{name:'Descartar',exact:true}).count(),0);await overview.getByRole('button',{name:/Partido confirmado/}).waitFor();
 seed([match('last',false)]);await page.reload();await calendar();await discard();await overview.getByRole('button',{name:'Descartar',exact:true}).waitFor({state:'detached'});assert.deepEqual(group().payload.matches,[]);
 await page.reload();await calendar();await overview.getByText('No hay partidos programados',{exact:true}).waitFor();assert.equal(await overview.getByRole('button',{name:'Descartar',exact:true}).count(),0);
 await overview.screenshot({path:'/tmp/discard-empty-calendar.png'});
 // An empty calendar still supports creating a deliberate new draft.
 await overview.getByRole('button',{name:'Crear partido',exact:true}).first().click();await page.getByText('Cuándo y dónde',{exact:true}).waitFor();
 assert.equal(commands,3);assert.deepEqual(errors,[]);console.log('PASS: visible failure -> retry -> SQL discard -> reload preserves other match; last draft -> empty reload -> new wizard; mobile/desktop; no runtime errors.');
}catch(e){await page.screenshot({path:'/tmp/discard-browser-failure.png'});console.error((await page.locator('body').innerText()).slice(0,5000));throw e;}
finally{await browser.close();}
