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
const frame='player.frame.future.navy';
await page.route('https://profile-qa.supabase.co/**',async route=>{
 const path=new URL(route.request().url()).pathname;
 let data=[];
 if(path.includes('/auth/v1/user')) data=user;
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
 await page.goto(`${process.env.BASE_URL ?? 'http://127.0.0.1:3187'}/perfil`);
 const link=page.getByRole('link',{name:'Configurar mercado público',exact:true});
 await link.waitFor();
 await link.click();
 const market=page.locator('#market-profile');
 await market.waitFor();
 assert.equal(await page.getByRole('checkbox',{name:'Mostrarme en mercado de fichajes'}).isVisible(),true);
 await page.waitForTimeout(1600);
 assert.equal(await page.locator('main[data-mobile-tab]').getAttribute('data-mobile-tab'),'perfil');
 const y=await market.evaluate(e=>e.getBoundingClientRect().top);
 assert.ok(y>=-2&&y<250,`Market controls not at viewport start: ${y}`);
 assert.ok(new URL(page.url()).searchParams.get('market')==='1');
 await page.reload();
 await market.waitFor();
 await page.waitForTimeout(1600);
 assert.equal(await page.locator('main[data-mobile-tab]').getAttribute('data-mobile-tab'),'perfil');
 assert.ok(new URL(page.url()).searchParams.get('market')==='1');
 console.log(JSON.stringify({passed:true,url:page.url(),marketTop:y,reload:true}));
} catch(error) {console.log(await page.locator('body').innerText());throw error;} finally {await browser.close();}
