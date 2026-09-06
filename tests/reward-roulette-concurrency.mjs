// Run only against the task's isolated local database; never a production URL.
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
const exec = promisify(execFile);
async function sql(query) {
  const { stdout } = await exec('docker', ['exec', 'supabase_db_pachangas-synthetic-world-v1', 'psql', '-U', 'supabase_admin', '-d', 'pachangas_roulette_v1', '-XAt', '-v', 'ON_ERROR_STOP=1', '-c', query]);
  return stdout.trim();
}
const user='b1000000-0000-0000-0000-000000000001';
const profile='b2000000-0000-0000-0000-000000000001';
await sql(`insert into auth.users(id,email) values('${user}','roulette-concurrency@example.test'); insert into public.pachanga_player_profiles(id,user_id,display_name) values('${profile}','${user}','Roulette concurrency'); select private.pachanga_apply_player_points_v1('${profile}','${user}',15,'admin_adjustment',gen_random_uuid(),null,null,null,'roulette-concurrency-seed');`);
const call = id => sql(`begin; set local role authenticated; select set_config('request.jwt.claim.sub','${user}',true); select public.pachanga_roulette_v1('spin','${id}'); commit;`);
const attempts=await Promise.allSettled([call('b3000000-0000-0000-0000-000000000001'),call('b3000000-0000-0000-0000-000000000002')]);
assert.equal(attempts.filter(r=>r.status==='fulfilled').length,1);
assert.equal(attempts.filter(r=>r.status==='rejected').length,1);
assert.equal(await sql(`select balance from public.pachanga_player_point_accounts where user_id='${user}'`),'0');
assert.equal(await sql(`select count(*) from private.pachanga_roulette_boxes where user_id='${user}'`),'1');
const winning=attempts[0].status==='fulfilled'?'b3000000-0000-0000-0000-000000000001':'b3000000-0000-0000-0000-000000000002';
await Promise.all([call(winning),call(winning)]);
assert.equal(await sql(`select count(*) from private.pachanga_roulette_boxes where user_id='${user}'`),'1');
console.log('PASS: concurrent spending and concurrent replay preserve one debit and one chest');
