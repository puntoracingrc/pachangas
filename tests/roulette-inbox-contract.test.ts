import assert from 'node:assert/strict';
import test from 'node:test';
import { normalizeSocialInboxSnapshot, safeSocialInboxDeepLink } from '../app/social-inbox-contract';

test('reward notifications survive normalization and link to the real roulette', () => {
  const result = normalizeSocialInboxSnapshot({view:'pending',filters:['MATCH','REWARD'],pendingCount:1,items:[{
    id:'notice',sourceDomain:'REWARD',title:'Tienes un giro gratis en la ruleta',deepLink:'/ruleta',
    attentionState:'ACTION_REQUIRED',readState:'READ',ctaLabel:'Ir a la ruleta',
  }]});
  assert.equal(result?.items.length,1);
  assert.equal(result?.items[0].deepLink,'/ruleta');
  assert.equal(result?.items[0].readState,'READ');
  assert.equal(result?.items[0].attentionState,'ACTION_REQUIRED');
  assert.deepEqual(result?.filters,['MATCH','REWARD']);
  assert.equal(safeSocialInboxDeepLink('/ruleta/../../admin'),undefined);
});
