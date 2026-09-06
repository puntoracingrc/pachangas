// Browser -> RPC transport adapter -> actual isolated PostgreSQL functions.
// Authentication is a synthetic local session; no production request is forwarded.
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { mkdir } from 'node:fs/promises';
const { chromium } = await import(process.env.PLAYWRIGHT_MODULE);
const exec = promisify(execFile);
const uid=randomUUID();
const pid=randomUUID();
async function sql(query) {
 const { stdout } = await exec('docker',['exec','supabase_db_pachangas-synthetic-world-v1','psql','-U','supabase_admin','-d','pachangas_roulette_v1','-XAt','-v','ON_ERROR_STOP=1','-c',query]); return stdout;
}
await sql(`insert into auth.users(id,email) values('${uid}','roulette-browser-${uid}@example.test'); insert into public.pachanga_player_profiles(id,user_id,display_name) values('${pid}','${uid}','Roulette Browser'); insert into private.pachanga_roulette_credits(user_id,origin,granted_at) values('${uid}','assessment:initial',now()),('${uid}','assessment:advanced',now()); select private.pachanga_apply_player_points_v1('${pid}','${uid}',30,'admin_adjustment',gen_random_uuid(),null,null,null,'roulette-browser-seed-${uid}');`);
const browser=await chromium.launch({executablePath:'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',headless:true});
const context=await browser.newContext({viewport:{width:390,height:844},reducedMotion:'reduce'});
const page=await context.newPage(); const errors=[]; page.on('pageerror',e=>errors.push(e.message));
const payload={sub:uid,role:'authenticated',aud:'authenticated',exp:Math.floor(Date.now()/1000)+7200};
const token=Buffer.from(JSON.stringify({alg:'HS256',typ:'JWT'})).toString('base64url')+'.'+Buffer.from(JSON.stringify(payload)).toString('base64url')+'.synthetic';
await context.addInitScript(({token,uid})=>localStorage.setItem('sb-qonbngfrnrqgmxbdfbea-auth-token',JSON.stringify({access_token:token,refresh_token:'synthetic',expires_at:Math.floor(Date.now()/1000)+7200,expires_in:7200,token_type:'bearer',user:{id:uid,aud:'authenticated',role:'authenticated',email:'roulette-browser@example.test',app_metadata:{},user_metadata:{},created_at:new Date().toISOString()}})),{token,uid});
await page.route('https://*.supabase.co/**',async route=>{
 if (!route.request().url().includes('/rpc/pachanga_roulette_v1')) return route.fulfill({status:200,contentType:'application/json',body:'{}'});
 const body=route.request().postDataJSON();
 assert.ok(['snapshot','spin','open','open_all'].includes(body.p_action));
 const quoteUuid=v=>{assert.match(v,/^[a-f0-9-]{36}$/i);return `'${v}'::uuid`;};
 const op=body.p_operation_id?quoteUuid(body.p_operation_id):'null';
 const ids=body.p_box_ids?`array[${body.p_box_ids.map(quoteUuid).join(',')}]`:'null';
 try {
 const output=await sql(`begin; select set_config('request.jwt.claim.sub','${uid}',true); set local role authenticated; select public.pachanga_roulette_v1('${body.p_action}',${op},${ids}); commit;`);
 const result=output.split('\n').find(line=>line.startsWith('{'));
 await route.fulfill({status:200,contentType:'application/json',body:result});
 } catch(e) { await route.fulfill({status:409,contentType:'application/json',body:JSON.stringify({code:'PT409',message:e.stderr})}); }
});
try {
 await page.goto('http://127.0.0.1:3187/ruleta');
 await page.getByRole('button',{name:'Girar gratis',exact:true}).waitFor();
 await page.getByRole('button',{name:'Girar gratis',exact:true}).click();
 await page.getByRole('button',{name:'Abrir este cofre →',exact:true}).waitFor();
 await page.getByRole('button',{name:'Abrir después · girar gratis',exact:true}).click();
 await page.getByRole('button',{name:'Abrir después · girar por 15 puntos',exact:true}).waitFor();
 await page.getByRole('button',{name:'Abrir después · girar por 15 puntos',exact:true}).click();
 await page.getByRole('button',{name:'Abrir este cofre →',exact:true}).waitFor();
 await page.getByLabel('15 puntos',{exact:true}).waitFor();
 assert.match(await sql(`select balance from public.pachanga_player_point_accounts where user_id='${uid}'`),/^15\s*$/);
 await page.reload();
 await page.getByRole('button',{name:'Abrir cofres acumulados (3) →',exact:true}).waitFor();
 // Deterministic real SQL rewards, so the browser assertion is repeatable.
 await sql(`update private.pachanga_roulette_boxes set sealed=jsonb_build_object('key',null,'points',4,'duplicatePoints',0) where user_id='${uid}'`);
 await page.getByRole('button',{name:'Abrir todo',exact:true}).click();
 await page.getByRole('heading',{name:'3 cofres abiertos'}).waitFor();
 await mkdir('artifacts/chest-roulette/release',{recursive:true});
 await page.screenshot({path:'artifacts/chest-roulette/release/mobile-summary.png'});
 await page.getByRole('button',{name:'Aceptar y volver a la ruleta'}).click();
 await page.getByLabel('27 puntos',{exact:true}).waitFor();
 assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true);
 await page.screenshot({path:'artifacts/chest-roulette/release/mobile-roulette.png'});
 await page.setViewportSize({width:1440,height:1000});
 await page.screenshot({path:'artifacts/chest-roulette/release/desktop-roulette.png'});
 assert.deepEqual(errors,[]);
 console.log('PASS: free precedence, immediate next spin, canonical debit, reload persistence, bulk reveal, delayed visible balance, mobile width');
} finally { await browser.close(); }
