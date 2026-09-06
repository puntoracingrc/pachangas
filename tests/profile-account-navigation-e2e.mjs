// Run against local dev with NEXT_PUBLIC_SUPABASE_URL=https://profile-qa.supabase.co
// and a non-secret placeholder NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY. All backend reads are fixtures.
const { chromium } = await import(process.env.PLAYWRIGHT_MODULE ?? 'playwright');
import assert from 'node:assert/strict';
const browser = await chromium.launch({headless:true,...(process.env.CHROME_EXECUTABLE ? {executablePath:process.env.CHROME_EXECUTABLE} : {})});
const page = await browser.newPage({viewport:{width:390,height:844}});
page.setDefaultTimeout(15000);
const uid='10000000-0000-4000-8000-000000000001', pid='20000000-0000-4000-8000-000000000001';
const user={id:uid,aud:'authenticated',role:'authenticated',email:'profile-qa@example.invalid',app_metadata:{provider:'email'},user_metadata:{},created_at:new Date().toISOString()};
let frame='player.frame.future.navy';
let requests=0;
await page.route('https://profile-qa.supabase.co/**',async route=>{
 const path=new URL(route.request().url()).pathname;
 let data=[];
 if(path.includes('/auth/v1/user')) data=user;
 else if(path.includes('/pachanga_player_profiles')) data={id:pid,display_name:'Jugador QA',position:'Medio',current_overall:72,current_facets:{Pace:70,Shot:75,Pass:80},assessment_summary:{initial:{completedAt:'2026-09-01T10:00:00Z'},advanced:{completedAt:'2026-09-02T10:00:00Z'}},profile_version:1,market_enabled:false};
 else if(path.endsWith('/get_pachanga_player_cosmetics_snapshot_v1')) {requests++;data={enabled:true,playerProfileId:pid,revision:2,serverSequence:2,loadout:{frameKey:frame,backgroundKey:'player.background.future.navy',accentKey:null,effectKey:null,titleKey:null,featuredBadgeGrantId:'badge-qa'},owned:[],featuredBadges:[{grantId:'badge-qa',achievementKey:'qa',title:'Logro QA',rarity:'rare'}]};}
 else if(path.endsWith('/get_my_pachanga_social_profile_v1')) data=null;
 await route.fulfill({status:200,contentType:'application/json',body:JSON.stringify(data)});
});
await page.addInitScript(({user})=>{
 const jwt=btoa(JSON.stringify({alg:'HS256',typ:'JWT'}))+'.'+btoa(JSON.stringify({sub:user.id,role:'authenticated',exp:Math.floor(Date.now()/1000)+3600}))+'.qa';
 localStorage.setItem('sb-profile-qa-auth-token',JSON.stringify({access_token:jwt,refresh_token:'qa-refresh',expires_at:Math.floor(Date.now()/1000)+3600,expires_in:3600,token_type:'bearer',user}));
 localStorage.setItem('pachanga-iq-theme','light');
},{user});
try {
 await page.goto('http://127.0.0.1:3187/perfil');
 await page.locator('[data-frame="player.frame.future.navy"]').waitFor();
 assert.match(await page.locator('[title="Logro destacado"]').innerText(),/Logro QA/);
 const edit=page.getByRole('link',{name:'Editar carta',exact:true});
 assert.equal(await edit.getAttribute('href'),'/personalizar-carta');
 assert.deepEqual(await edit.evaluate(e=>[getComputedStyle(e).backgroundColor,getComputedStyle(e).color]),await page.getByRole('link',{name:'Editar perfil',exact:true}).evaluate(e=>[getComputedStyle(e).backgroundColor,getComputedStyle(e).color]));
 assert.equal(await page.getByText('Mercado público',{exact:true}).count(),1);
 const privacy=page.locator('details').filter({has:page.getByText('Lo que no publicamos',{exact:true})});
 assert.equal(await privacy.getAttribute('open'),null);
 await privacy.locator('summary').click();
 assert.equal(await privacy.locator('p').isVisible(),true);
 await privacy.locator('summary').click();
 await page.screenshot({path:'/tmp/my-card-profile-light.png',fullPage:true});
 frame='player.frame.barrio.copper';
 await page.evaluate(()=>window.dispatchEvent(new Event('focus')));
 await page.locator('[data-frame="player.frame.barrio.copper"]').waitFor();
 await page.getByRole('button',{name:'Abrir menú de perfil',exact:true}).click();
 assert.equal(await page.getByRole('link',{name:'Mi perfil',exact:true}).getAttribute('href'),'/perfil');
 assert.equal(await page.getByRole('link',{name:'Mi carta',exact:true}).count(),0);
 await page.keyboard.press('Escape');
 await page.locator('summary[aria-label="Abrir menú general"]:visible').click();
 assert.equal(await page.getByRole('link',{name:'Mi perfil',exact:true}).isVisible(),true);
 assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false);
 console.log(JSON.stringify({passed:true,cosmeticReads:requests,checks:['saved frame and badge','editor button matches profile','refresh on return','avatar and hamburger menu','mobile overflow','market description','privacy collapsed and expandable']}));
} catch(error) {console.log(await page.locator('body').innerText()); console.log('reads',requests); throw error;} finally {await browser.close();}
