// Live UI with read-only SQL RPCs in an isolated fixture database.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
const {chromium}=await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
const database=process.env.TEAM_HOME_TEST_DATABASE;
assert.match(database??'',/^team_home_test_/);
const uid='f9650000-0000-4000-8000-000000000001',gid='f9650000-0000-4000-8000-000000000010';
function sql(query){return execFileSync('docker',['exec','-i','supabase_db_pachangas-synthetic-world-v1','psql','-X','-Atq','-v','ON_ERROR_STOP=1','-U','supabase_admin','-d',database],{input:query,encoding:'utf8'}).trim();}
function rpc(name,args=''){assert.match(name,/^get_[a-z_0-9]+$/);return JSON.parse(sql(`begin;set local role authenticated;set local "request.jwt.claims"='{"sub":"${uid}","role":"authenticated","is_anonymous":false}';select public.${name}(${args});rollback;`));}
const group=JSON.parse(sql(`select row_to_json(g) from public.pachanga_groups g where id='${gid}'`));
const user={id:uid,aud:'authenticated',role:'authenticated',email:'qa@example.invalid',user_metadata:{},app_metadata:{provider:'email'}};
const browser=await chromium.launch({headless:true,executablePath:process.env.CHROME_EXECUTABLE || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'});
const page=await browser.newPage({viewport:{width:1280,height:900}}),errors=[];page.setDefaultTimeout(12000);page.on('pageerror',e=>errors.push(e.message));
await page.route('**/api/**',r=>r.request().method()==='POST'?r.fulfill({json:{ok:true}}):r.continue());
await page.route('**/api/ratings/assessment',r=>r.fulfill({json:{assessments:{initial:{completedAt:'2026-09-06T13:00:00Z'}}}}));
await page.route('https://*.supabase.co/**',async route=>{
 const u=new URL(route.request().url()),p=u.pathname;let data=[];
 if(p.includes('/auth/v1/user'))data=user;
 else if(p.endsWith('/pachanga_group_members'))data=u.searchParams.get('select')?.includes('pachanga_groups')?[{group_id:gid,role:'owner',pachanga_groups:group}]:[{user_id:uid,display_name:'QA',role:'owner'}];
 else if(p.endsWith('/get_pachanga_social_team_feature_flags_v1'))data=rpc('get_pachanga_social_team_feature_flags_v1');
 else if(p.endsWith('/get_my_pachanga_social_teams_v1'))data=rpc('get_my_pachanga_social_teams_v1');
 else if(p.endsWith('/get_pachanga_social_team_home_v1'))data=rpc('get_pachanga_social_team_home_v1',`'${gid}'`);
 else if(p.endsWith('/get_pachanga_player_claims_v1'))data={canReview:false,hasTeamPlayer:true,candidates:[],requests:[]};
 else if(p.endsWith('/get_my_pachanga_social_profile_v1'))data={displayName:'QA',primaryPosition:'DEL',birthDate:'1990-01-01',preferredModality:'futbol7',generalArea:'Barcelona'};
 await route.fulfill({json:data});
});
await page.addInitScript(({user})=>{const token=btoa(JSON.stringify({alg:'HS256'}))+'.'+btoa(JSON.stringify({sub:user.id,role:'authenticated',exp:Math.floor(Date.now()/1000)+3600}))+'.qa';const auth=JSON.stringify({access_token:token,refresh_token:'qa',expires_at:Math.floor(Date.now()/1000)+3600,user,token_type:'bearer'});for(const key of ['sb-profile-qa-auth-token','sb-qonbngfrnrqgmxbdfbea-auth-token'])localStorage.setItem(key,auth);localStorage.setItem('pachanga-iq-theme','dark');},{user});
const origin=process.env.QA_ORIGIN || 'http://127.0.0.1:3192';
try{
 await page.goto(origin+'/?equipo=THQA9601');
 const home=page.locator('[data-official-upcoming-rail]');await home.getByText('Pending match',{exact:true}).waitFor();
 assert.match(await home.innerText(),/24 ago/);
 await home.getByRole('button',{name:/Pending match/}).click();
 const context=page.getByLabel('Contexto del partido activo');await context.getByText('Pending match',{exact:true}).waitFor();
 await page.getByRole('button',{name:'Todos los partidos',exact:true}).click();
 const card=page.locator('[data-match-state="upcoming"]').getByRole('button',{name:/Pending match/});await card.waitFor();assert.match(await card.innerText(),/24 ago/i);
 await page.goto(origin+`/equipo?team=${gid}&tab=portada`);
 await page.getByRole('heading',{name:'Pending match',exact:true}).waitFor();
 const link=page.getByRole('link',{name:'Ver partido',exact:true});assert.match(await link.getAttribute('href'),/p=past/);
 assert.equal(await page.getByText('Aún no hay partido',{exact:true}).count(),0);
 await page.screenshot({path:'/tmp/team-home-consistency.png',fullPage:true});
 await link.click();await context.getByText('Pending match',{exact:true}).waitFor();
 await page.goto(origin+`/equipo?team=${gid}`);
 await page.getByText('Top provincial',{exact:true}).waitFor();
 const nav=page.getByRole('navigation',{name:'Secciones del equipo',exact:true});
 assert.deepEqual(await nav.getByRole('link').allTextContents(),['Ranking','Plantilla','Logros','Escudo','Portada','Invitaciones']);
 await nav.getByRole('link',{name:'Portada',exact:true}).click();
 await page.getByRole('heading',{name:'Pending match',exact:true}).waitFor();
 await page.setViewportSize({width:390,height:844});
 await page.evaluate(()=>document.documentElement.dataset.theme='light');
 assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1));
 await page.screenshot({path:'/tmp/team-home-mobile.png',fullPage:true});
 assert.deepEqual(errors,[]);console.log('PASS: Inicio, Partidos and Equipo agree on past open match and date; Equipo reads authenticated SQL and links to same match.');
}catch(e){console.error(errors);console.error((await page.locator('body').innerText()).slice(-2200));await page.screenshot({path:'/tmp/team-home-failure.png'});throw e;}finally{await browser.close();}
