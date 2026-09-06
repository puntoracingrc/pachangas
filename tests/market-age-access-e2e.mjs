// Use local dev with NEXT_PUBLIC_SUPABASE_URL=https://profile-qa.supabase.co
// and a placeholder publishable key. Backend responses use synthetic fixtures.
const { chromium } = await import(process.env.PLAYWRIGHT_MODULE ?? 'playwright');
import assert from 'node:assert/strict';
const browser = await chromium.launch({headless:true,...(process.env.CHROME_EXECUTABLE ? {executablePath:process.env.CHROME_EXECUTABLE} : {})});
const page = await browser.newPage({viewport:{width:390,height:844}});
page.setDefaultTimeout(15000);
const uid='10000000-0000-4000-8000-000000000001', pid='20000000-0000-4000-8000-000000000001';
const user={id:uid,aud:'authenticated',role:'authenticated',email:'profile-qa@example.invalid',app_metadata:{provider:'email'},user_metadata:{},created_at:new Date().toISOString()};
const gid='30000000-0000-4000-8000-000000000001';
let ageAccess='minor';
let protectedReads=0;
const frame='player.frame.future.navy';
await page.route('https://profile-qa.supabase.co/**',async route=>{
 const path=new URL(route.request().url()).pathname;
 let data=[];
 if(path.endsWith('/get_my_pachanga_market_age_access_v1')) data={access:ageAccess};
 else if(path.includes('/pachanga_market_profiles') || path.endsWith('/search_pachanga_open_matches_v1')) {protectedReads++;data=[];}
 else if(path.includes('/auth/v1/user')) data=user;
 else if(path.includes('/pachanga_player_profiles')) data={id:pid,display_name:'Jugador QA',position:'Medio',current_overall:72,current_facets:{Pace:70,Shot:75,Pass:80},assessment_summary:{initial:{completedAt:'2026-09-01T10:00:00Z'},advanced:{completedAt:'2026-09-02T10:00:00Z'}},profile_version:1,market_enabled:false};
 else if(path.endsWith('/get_pachanga_player_cosmetics_snapshot_v1')) {data={enabled:true,playerProfileId:pid,revision:2,serverSequence:2,loadout:{frameKey:frame,backgroundKey:'player.background.future.navy',accentKey:null,effectKey:null,titleKey:null,featuredBadgeGrantId:'badge-qa'},owned:[],featuredBadges:[{grantId:'badge-qa',achievementKey:'qa',title:'Logro QA',rarity:'rare'}]};}
 else if(path.endsWith('/get_my_pachanga_social_profile_v1')) data={displayName:'Jugador QA',primaryPosition:'CM',preferredModality:'football7',generalArea:'Madrid',usualDays:['monday'],approximateTime:'Tarde'};
 else if(path.endsWith('/get_my_pachanga_social_teams_v1')) data=[{groupId:gid,name:'Equipo QA',teamCode:'QA123',role:'player'}];
 else if(path.includes('/pachanga_group_members')) {
  data=route.request().url().includes('pachanga_groups') ? [{group_id:gid,role:'player',pachanga_groups:{id:gid,name:'Equipo QA',owner_id:'40000000-0000-4000-8000-000000000001',team_code:'QA123',payload_revision:1,billing_status:'active',payload:{players:[{id:'player-qa',ownerUserId:uid,globalPlayerProfileId:pid,name:'Jugador QA',position:'Medio',rating:7,goals:0,assists:0,appearances:0,wins:0,assessmentSummary:{initial:{completedAt:'2026-09-01T10:00:00Z'}}}],matches:[],venues:[],siteSettings:{title:'Equipo QA'}}}}] : [{user_id:uid,role:'player',display_name:'Jugador QA'}];
 }
 await route.fulfill({status:200,contentType:'application/json',body:JSON.stringify(data)});
});
await page.addInitScript(({user})=>{
 const jwt=btoa(JSON.stringify({alg:'HS256',typ:'JWT'}))+'.'+btoa(JSON.stringify({sub:user.id,role:'authenticated',exp:Math.floor(Date.now()/1000)+3600}))+'.qa';
 localStorage.setItem('sb-profile-qa-auth-token',JSON.stringify({access_token:jwt,refresh_token:'qa-refresh',expires_at:Math.floor(Date.now()/1000)+3600,expires_in:3600,token_type:'bearer',user}));
 localStorage.setItem('pachanga-iq-theme','light');
},{user});
await page.route('**/api/ratings/assessment',route=>route.fulfill({status:200,contentType:'application/json',body:JSON.stringify({assessments:{initial:{completedAt:'2026-09-01T10:00:00Z'}}})}));
try {
 for(const route of ['/mercado','/retos']) {
  await page.goto(`http://127.0.0.1:3187${route}`);
  await page.getByRole('heading',{name:'Mercado y retos, a partir de los 18 años'}).waitFor();
  assert.equal(protectedReads,0);
  assert.equal(await page.getByText('Unirme a un equipo',{exact:true}).isVisible().catch(()=>false),false);
 }
 ageAccess='missing';
 await page.goto('http://127.0.0.1:3187/mercado');
 await page.getByRole('heading',{name:'Completa tu fecha de nacimiento'}).waitFor();
 assert.equal(protectedReads,0);
 await page.getByRole('link',{name:'Completar mi perfil',exact:true}).click();
 const birthday=page.getByLabel('Fecha de nacimiento',{exact:false});
 await birthday.waitFor();
 const next=page.getByRole('button',{name:'Continuar',exact:true});
 assert.equal(await next.isEnabled(),false);
 await birthday.fill('2099-01-01'); assert.equal(await next.isEnabled(),false);
 await birthday.fill('2012-01-01'); assert.equal(await next.isEnabled(),true);
 assert.equal(await page.getByText('Puedes jugar con tu equipo y crear uno para partidos internos.',{exact:false}).isVisible(),true);
 await page.screenshot({path:'/tmp/age-registration-mobile.png',fullPage:true});
 await next.click();
 await page.getByRole('heading',{name:'Dónde y cuándo prefieres jugar'}).waitFor();
 ageAccess='adult';
 await page.goto('http://127.0.0.1:3187/mercado');
 await page.waitForResponse(response=>response.url().includes('/search_pachanga_open_matches_v1')).catch(()=>{});
 assert.ok(protectedReads>0,'Adult reaches normal market data loading');
 console.log(JSON.stringify({passed:true,checks:['minor gate','missing date gate','no protected reads before adulthood','registration requires valid date','minor can continue registration','adult market access']}));
} catch(error) {console.log((await page.locator('body').innerText()).slice(0,5000));throw error;} finally {await browser.close();}
