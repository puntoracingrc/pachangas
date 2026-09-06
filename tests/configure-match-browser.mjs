// Actual home UI -> authenticated SQL command -> persisted reload, in an isolated database.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
const {chromium}=await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
const database=process.env.CONFIGURE_TEST_DATABASE, container=process.env.CONFIGURE_TEST_CONTAINER;
assert.match(database??'',/^create_match_test_/);assert.ok(container);
const gid='f9630000-0000-4000-8000-000000000010',uid='f9630000-0000-4000-8000-000000000001';
const q=v=>"'"+String(v).replaceAll("'","''")+"'";
function sql(s){return execFileSync('docker',['exec','-i',container,'psql','-X','-Atq','-v','ON_ERROR_STOP=1','-U','supabase_admin','-d',database],{input:s,encoding:'utf8'}).trim();}
function asUser(s){return `begin; set local role authenticated; set local "request.jwt.claims"=${q(JSON.stringify({sub:uid,role:'authenticated',is_anonymous:false}))};${s};commit;`;}
function group(){return JSON.parse(sql(`select row_to_json(g) from public.pachanga_groups g where id=${q(gid)}`));}
sql(`update public.pachanga_groups set payload=jsonb_set(payload,'{matches}','[{"id":"draft","configured":false},{"id":"published","configured":true}]') where id=${q(gid)}`);
sql(`update public.pachanga_groups set payload=jsonb_set(payload,'{matches}',(select jsonb_agg('{"title":"Partido QA","date":"2099-09-12T10:20","kind":"futbol7","venueId":"venue","place":"Campo QA","targetPlayers":14,"fieldCost":56,"players":[]}'::jsonb || value) from jsonb_array_elements(payload->'matches'))) where id=${q(gid)}`);
const beforePlayers=sql(`select (payload->'players')::text from public.pachanga_groups where id=${q(gid)}`);
const beforeMatches=sql(`select (payload->'matches')::text from public.pachanga_groups where id=${q(gid)}`);
const browser=await chromium.launch({headless:true,executablePath:process.env.CHROME_EXECUTABLE || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'});
const page=await browser.newPage({viewport:{width:1280,height:900}}),errors=[];page.setDefaultTimeout(10000);page.on('pageerror',e=>errors.push(e.message));
const user={id:uid,aud:'authenticated',role:'authenticated',email:'qa@example.invalid',user_metadata:{},app_metadata:{provider:'email'}};
let failNext=false,commands=0;
await page.route('**/api/**',route=>route.request().method()==='POST'?route.fulfill({json:{ok:true}}):route.continue());
await page.route('**/api/ratings/assessment',route=>route.fulfill({json:{assessments:{initial:{completedAt:'2026-09-06T13:00:00Z'}}}}));
await page.route('https://*.supabase.co/**',async route=>{
 const url=new URL(route.request().url()),p=url.pathname,body=route.request().postDataJSON()||{};let data=[];
 try{
  if(p.includes('/auth/v1/user'))data=user;
  else if(p.endsWith('/pachanga_group_members'))data=url.searchParams.get('select')?.includes('pachanga_groups')?[{group_id:gid,role:'owner',pachanga_groups:group()}]:[{user_id:uid,display_name:'Admin QA',role:'owner'}];
  else if(p.endsWith('/pachanga_groups'))data=group();
  else if(p.endsWith('/get_my_pachanga_social_profile_v1'))data={displayName:'Admin QA',primaryPosition:'DEL',birthDate:'1990-01-01',preferredModality:'futbol7',generalArea:'Barcelona'};
  else if(p.endsWith('/configure_pachanga_match_v1')){
   commands++;if(failNext){failNext=false;throw new Error('Temporary failure');}
   assert.equal('next_payload' in body,false);
   data=JSON.parse(sql(asUser(`select public.configure_pachanga_match_v1(${q(body.target_group_id)},${q(body.target_match_id)},${q(JSON.stringify(body.configuration))}::jsonb,${q(body.operation_id)},${Number(body.expected_revision)},'{}')`)));
  }else if(p.endsWith('/save_pachanga_payload_authoritative_v2')){
   data=JSON.parse(sql(asUser(`select public.save_pachanga_payload_authoritative_v2(${q(gid)},${Number(body.expected_revision)},${q(JSON.stringify(body.next_payload))}::jsonb,${q(body.operation_id)},'{}')`)));
  }
  await route.fulfill({status:200,contentType:'application/json',body:JSON.stringify(data)});
 }catch(e){console.error('RPC',p,String(e.stderr||e.message));await route.fulfill({status:400,contentType:'application/json',body:JSON.stringify({message:String(e.stderr||e.message)})});}
});
await page.addInitScript(({user})=>{const token=btoa(JSON.stringify({alg:'HS256'}))+'.'+btoa(JSON.stringify({sub:user.id,role:'authenticated',exp:Math.floor(Date.now()/1000)+3600}))+'.qa';localStorage.setItem('sb-profile-qa-auth-token',JSON.stringify({access_token:token,refresh_token:'qa',expires_at:Math.floor(Date.now()/1000)+3600,user,token_type:'bearer'}));localStorage.setItem('sb-qonbngfrnrqgmxbdfbea-auth-token',localStorage.getItem('sb-profile-qa-auth-token'));},{user});
const overview=page.locator('[data-view="overview"]');
async function calendar(){await page.getByLabel('Navegación principal',{exact:true}).getByRole('button',{name:'Partidos',exact:true}).click();await overview.waitFor();}
try{
 await page.goto((process.env.QA_ORIGIN||'http://127.0.0.1:3191')+'/?equipo=DRQA9601');await calendar();
 await page.getByRole('button',{name:'Crear partido',exact:true}).first().click();
 const wizard=page.locator('[data-view="wizard"]');await wizard.waitFor();
 await wizard.getByLabel('Fecha',{exact:true}).fill('2099-09-12');
 await wizard.getByLabel('Hora',{exact:true}).fill('10:20');
 await wizard.getByRole('combobox').nth(1).selectOption('venue');
 await wizard.getByRole('button',{name:'Continuar',exact:true}).click();
 await wizard.getByLabel('Coste del campo (€)',{exact:true}).fill('72.5');
 await wizard.getByRole('checkbox',{name:/Reservas presenciales/}).check();
 await wizard.getByLabel('Máximo reservas',{exact:true}).fill('3');
 await wizard.getByRole('button',{name:'Continuar',exact:true}).click();
 failNext=true;await wizard.getByRole('button',{name:'Crear partido',exact:true}).click();
 await wizard.getByText('No se ha podido guardar el partido. Conservamos los datos para que puedas reintentarlo.',{exact:true}).waitFor();
 await wizard.getByRole('button',{name:'Crear partido',exact:true}).click();
 await wizard.waitFor({state:'detached'});
 const stored=group();const created=stored.payload.matches.find(m=>m.id==='draft');
 assert.equal(created.configured,true);assert.equal(created.fieldCost,72.5);assert.equal(created.reserveLimit,3);
 assert.equal(sql(`select (payload->'players')::text from public.pachanga_groups where id=${q(gid)}`),beforePlayers);
 assert.deepEqual(stored.payload.matches.filter(m=>m.id!=='draft'),JSON.parse(beforeMatches).filter(m=>m.id!=='draft'));
 await page.reload();await calendar();assert.equal(group().payload.matches.filter(m=>m.id==='draft').length,1);
 assert.equal(await overview.getByRole('button',{name:'Continuar',exact:true}).count(),0);
 await page.screenshot({path:'/tmp/configure-match-confirmed.png',fullPage:true});
 assert.equal(commands,2);assert.deepEqual(errors,[]);
 console.log('PASS: actual UI failure/retry -> authenticated SQL configuration -> reload; persisted price/reserves; exact rating precision and other matches preserved; no duplicate.');
}catch(e){console.error(errors);await page.screenshot({path:'/tmp/configure-match-failure.png'});throw e;}finally{await browser.close();}
