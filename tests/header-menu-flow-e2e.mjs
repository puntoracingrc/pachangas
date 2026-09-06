// Run against local dev with NEXT_PUBLIC_SUPABASE_URL=https://profile-qa.supabase.co
// and a non-secret placeholder NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY. All backend reads are fixtures.
const { chromium } = await import(process.env.PLAYWRIGHT_MODULE ?? 'playwright');
import assert from 'node:assert/strict';
const browser = await chromium.launch({headless:true,...(process.env.CHROME_EXECUTABLE ? {executablePath:process.env.CHROME_EXECUTABLE} : {})});
const page = await browser.newPage({hasTouch:true,viewport:{width:390,height:844}});
page.setDefaultTimeout(15000);
const uid='10000000-0000-4000-8000-000000000001', pid='20000000-0000-4000-8000-000000000001';
const user={id:uid,aud:'authenticated',role:'authenticated',email:'profile-qa@example.invalid',app_metadata:{provider:'email'},user_metadata:{},created_at:new Date().toISOString()};
let frame='player.frame.future.navy';
let balance=114;
let pointsFail=false;
await page.route('https://profile-qa.supabase.co/**',async route=>{
 const path=new URL(route.request().url()).pathname;
 let data=[];
 if(path.includes('/auth/v1/user')) data=user;
 else if(path.includes('/pachanga_player_point_accounts')) {
  if(pointsFail) return route.fulfill({status:503,contentType:'application/json',body:JSON.stringify({message:'Unavailable'})});
  data={balance};
 }
 else if(path.includes('/pachanga_player_profiles')) data={id:pid,display_name:'Jugador QA',position:'Medio',current_overall:72,current_facets:{Pace:70,Shot:75,Pass:80},assessment_summary:{initial:{completedAt:'2026-09-01T10:00:00Z'},advanced:{completedAt:'2026-09-02T10:00:00Z'}},profile_version:1,market_enabled:false};
 else if(path.endsWith('/get_pachanga_player_cosmetics_snapshot_v1')) {data={enabled:true,playerProfileId:pid,revision:2,serverSequence:2,loadout:{frameKey:frame,backgroundKey:'player.background.future.navy',accentKey:null,effectKey:null,titleKey:null,featuredBadgeGrantId:'badge-qa'},owned:[],featuredBadges:[{grantId:'badge-qa',achievementKey:'qa',title:'Logro QA',rarity:'rare'}]};}
 else if(path.endsWith('/get_my_pachanga_social_profile_v1')) data=null;
 await route.fulfill({status:200,contentType:'application/json',body:JSON.stringify(data)});
});
await page.addInitScript(({user})=>{
 const jwt=btoa(JSON.stringify({alg:'HS256',typ:'JWT'}))+'.'+btoa(JSON.stringify({sub:user.id,role:'authenticated',exp:Math.floor(Date.now()/1000)+3600}))+'.qa';
 localStorage.setItem('sb-profile-qa-auth-token',JSON.stringify({access_token:jwt,refresh_token:'qa-refresh',expires_at:Math.floor(Date.now()/1000)+3600,expires_in:3600,token_type:'bearer',user}));
 localStorage.setItem('pachanga-iq-theme','light');
},{user});
try {
 for (const viewport of [{width:390,height:844},{width:1440,height:960}]) {
  await page.setViewportSize(viewport);
  await page.goto('http://127.0.0.1:3187/perfil');
  await page.getByRole('link',{name:'Editar perfil',exact:true}).waitFor();
  const team=page.locator('summary[aria-label="Abrir selector de equipo"]:visible');
  const account=page.locator('summary[aria-label="Abrir menú general"]:visible');
  const openMenus=page.locator('header details[open]:visible');
  await team.click();
  assert.equal(await openMenus.count(),1);
  const box=await account.boundingBox();
  await page.mouse.move(box.x+box.width/2,box.y+box.height/2);
  await page.mouse.down();
  await page.waitForTimeout(100);
  assert.equal(await page.getByRole('link',{name:'Crear equipo',exact:true}).isVisible(),true,'Pressing another trigger must not expose the page before release');
  await page.mouse.up();
  assert.equal(await openMenus.count(),1);
  assert.equal(await page.getByRole('link',{name:'PERFIL/CARTA',exact:true}).isVisible(),true);
  for(let i=0;i<3;i++) {
   await team.click();
   assert.equal(await openMenus.count(),1);
   await account.click();
   assert.equal(await openMenus.count(),1);
  }
  await account.click(); assert.equal(await openMenus.count(),0);
  if(viewport.width===390) {
   await team.tap(); await account.tap();
   assert.equal(await openMenus.count(),1);
   assert.equal(await page.getByRole('link',{name:'PERFIL/CARTA',exact:true}).isVisible(),true);
   await account.tap(); assert.equal(await openMenus.count(),0);
  }
  await team.focus(); await page.keyboard.press('Enter');
  await account.focus(); await page.keyboard.press('Space');
  assert.equal(await openMenus.count(),1);
  assert.equal(await page.getByRole('link',{name:'PERFIL/CARTA',exact:true}).isVisible(),true);
  await page.keyboard.press('Escape'); assert.equal(await openMenus.count(),0);
  assert.equal(await account.evaluate(e=>e===document.activeElement),true);
  await team.click();
  await page.mouse.click(2,viewport.height/2);
  assert.equal(await openMenus.count(),0);
  await account.click();
  await page.getByRole('link',{name:'Abrir perfil y carta',exact:true}).click();
  assert.equal(await openMenus.count(),0);
  assert.equal(new URL(page.url()).pathname,'/perfil');
  console.log(JSON.stringify({passed:true,viewport}));
 }
} finally {await browser.close();}
