// Use local dev with the profile-qa.supabase.co fixture URL and a placeholder public key.
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
 await page.goto('http://127.0.0.1:3187/personalizar-carta');
 await page.locator('[data-frame="player.frame.future.navy"]').waitFor();
 await page.getByRole('button',{name:'Restablecer',exact:true}).click();
 const dialog=page.getByRole('dialog');
 await dialog.waitFor();
 await page.screenshot({path:"/tmp/card-reset-confirmation.png"});
 assert.match(await dialog.innerText(),/Tu puntuación no cambia y conservas todos los cosméticos/);
 await dialog.getByRole('button',{name:'Cancelar',exact:true}).click();
 assert.equal(await page.locator('[data-frame="player.frame.future.navy"]').count(),1);
 await page.getByRole('button',{name:'Restablecer',exact:true}).click();
 await dialog.getByRole('button',{name:'Sí, restablecer aspecto',exact:true}).click();
 assert.equal(await page.locator('[data-frame="original"]').count(),1);
 assert.equal(await page.locator('[data-frame="original"]').getAttribute('data-effect'),'none');
 assert.match(await page.locator('[data-frame="original"]').innerText(),/72/);
 assert.equal(await page.getByRole('button',{name:'Deshacer',exact:true}).count(),0);
 console.log(JSON.stringify({passed:true,checks:['confirmation explains cosmetics retained and rating unchanged','cancel preserves loadout','reset clears equipped cosmetics only','no undo button after confirmation']}));
} catch(error) {console.log(await page.locator('body').innerText());throw error;} finally {await browser.close();}
