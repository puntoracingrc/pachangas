// Browser regression using synthetic Supabase responses; never modifies real attendance.
const {chromium}=await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
import assert from 'node:assert/strict';
const browser=await chromium.launch({headless:true,executablePath:process.env.CHROME_EXECUTABLE || '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'});
const page=await browser.newPage({viewport:{width:1280,height:900}}),errors=[];page.setDefaultTimeout(10000);page.on('pageerror',e=>errors.push(e.message));
const uid='f9640000-0000-4000-8000-000000000001',gid='f9640000-0000-4000-8000-000000000010';
const user={id:uid,aud:'authenticated',role:'authenticated',email:'qa@example.invalid',user_metadata:{},app_metadata:{provider:'email'}};
const players=['Alberto','Jordi','Vicente','Ranca'].map((name,i)=>({id:'p'+i,name,position:'DEL',rating:50,ratings:{},ownerUserId:i===0?uid:undefined}));
const draft={id:'draft',title:'Borrador de septiembre',configured:false,date:'2099-09-12T10:20',kind:'futbol7',venueId:'venue-qa',place:'Campo QA',targetPlayers:14,fieldCost:56,players:[]};
const published={...draft,id:'published',title:'Partido confirmado',configured:true,date:'2099-09-24T21:00',players:players.map(p=>({playerId:p.id,status:'voy',paid:false}))};
let commands=[];
let group={id:gid,name:'Equipo QA',team_code:'DTQA9601',owner_id:uid,payload_revision:0,payload:{matches:[draft,published],activeMatchId:'draft',players,venues:[{id:'venue-qa',name:'Campo QA',kind:'futbol7',defaultCost:56}],siteSettings:{brand:'Equipo QA'}}};
await page.route('**/api/**',r=>r.request().method()==='POST'?r.fulfill({status:200,json:{ok:true}}):r.continue());
await page.route('**/api/ratings/assessment',r=>r.fulfill({json:{assessments:{initial:{completedAt:'2026-09-06T13:00:00Z'}}}}));
await page.route('https://*.supabase.co/**',async route=>{
 const url=new URL(route.request().url()),p=url.pathname;let data=[];
 if(p.includes('/auth/v1/user'))data=user;
 else if(p.endsWith('/pachanga_group_members'))data=url.searchParams.get('select')?.includes('pachanga_groups')?[{group_id:gid,role:'owner',pachanga_groups:group}]:[{user_id:uid,display_name:'Admin QA',role:'owner'}];
 else if(p.endsWith('/get_my_pachanga_social_profile_v1'))data={displayName:'Admin QA',primaryPosition:'DEL',birthDate:'1990-01-01',preferredModality:'futbol7',generalArea:'Barcelona'};
 else if(p.endsWith('/patch_pachanga_match_player_status_authoritative_v2')){
  const body=route.request().postDataJSON();commands.push(body);
  assert.equal(body.target_match_id,'published');assert.equal(body.target_player_id,'p0');
  group.payload.matches.find(m=>m.id===body.target_match_id).players.find(p=>p.playerId===body.target_player_id).status=body.next_status;
  group.payload_revision++;data={payload:group.payload,confirmedRevision:group.payload_revision};
 }
 else if(p.endsWith('/save_pachanga_payload_authoritative_v2')){const body=route.request().postDataJSON();group.payload=body.next_payload;group.payload_revision++;data={payload:group.payload,confirmedRevision:group.payload_revision};}
 await route.fulfill({json:data});
});
await page.addInitScript(({user})=>{const token=btoa(JSON.stringify({alg:'HS256'}))+'.'+btoa(JSON.stringify({sub:user.id,role:'authenticated',exp:Math.floor(Date.now()/1000)+3600}))+'.qa';localStorage.setItem('sb-profile-qa-auth-token',JSON.stringify({access_token:token,refresh_token:'qa',expires_at:Math.floor(Date.now()/1000)+3600,user,token_type:'bearer'}));localStorage.setItem('sb-qonbngfrnrqgmxbdfbea-auth-token',localStorage.getItem('sb-profile-qa-auth-token'));localStorage.setItem('pachanga-iq-theme','dark');},{user});
try{
 await page.goto((process.env.QA_ORIGIN || 'http://127.0.0.1:3191')+'/?equipo=DTQA9601');
 await page.getByLabel('Navegación principal',{exact:true}).getByRole('button',{name:'Partidos',exact:true}).click();
 await page.locator('[data-match-state="upcoming"]').getByRole('button',{name:/Partido confirmado/}).click();
 const hub=page.locator('[data-official-match-hub="v3b"]');await hub.waitFor();
 await hub.getByRole('button',{name:'Duda',exact:true}).click();
 await Promise.all([page.waitForResponse(r=>r.url().includes('/patch_pachanga_match_player_status_authoritative_v2')), page.getByRole('button',{name:'Pasar a duda',exact:true}).click()]);
 await page.waitForTimeout(500);
 assert.match(await hub.innerText(),/Confirmados\s+3[\s\S]*Duda\s+1[\s\S]*Sin respuesta\s+0/);
 assert.equal(group.payload.activeMatchId,'draft');
 assert.equal(group.payload.matches[1].players[0].status,'duda');
 await hub.getByRole('button',{name:'Voy',exact:true}).click();
 await page.waitForTimeout(600);
 assert.deepEqual(commands.map(c=>c.next_status),['duda','voy']);
 assert.equal(group.payload.matches[1].players[0].status,'voy');
 assert.equal(group.payload.matches[1].players.filter(p=>p.status==='voy').length,4);
 await hub.getByRole('button',{name:'Todos los partidos',exact:true}).click();
 await page.locator('[data-match-state="upcoming"]').getByRole('button',{name:/Partido confirmado/}).click();
 assert.match(await hub.innerText(),/4\/14/);
 await page.screenshot({path:'/tmp/attendance-desktop.png',fullPage:true});
 await page.setViewportSize({width:390,height:844});
 await page.evaluate(()=>document.documentElement.dataset.theme='light');
 await hub.getByRole('button',{name:'Duda',exact:true}).click();
 await page.screenshot({path:'/tmp/attendance-mobile-confirm.png'});
 await page.getByRole('button',{name:'Pasar a duda',exact:true}).click();
 await page.waitForTimeout(600);
 await hub.getByRole('button',{name:'Voy',exact:true}).click();
 await page.waitForTimeout(600);
 assert.deepEqual(commands.map(c=>c.next_status),['duda','voy','duda','voy']);
 assert.equal(group.payload.matches[1].players.filter(p=>p.status==='voy').length,4);
 assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1));
 await page.screenshot({path:'/tmp/attendance-mobile.png',fullPage:true});
 assert.deepEqual(errors,[]);
 console.log('PASS: desktop/mobile Voy -> Duda -> Voy stays in published match despite server active draft; others preserved; calendar reentry works; no runtime errors. Synthetic backend responses.');
}catch(e){console.error(errors);console.error((await page.locator('body').innerText()).slice(-2200));await page.screenshot({path:'/tmp/attendance-failure.png'});throw e;}finally{await browser.close();}
