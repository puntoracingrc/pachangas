import assert from 'node:assert/strict';
import test from 'node:test';
import { isAdultBirthDate, validBirthDate } from '../app/market-age-contract.ts';
import { normalizeSocialOnboardingDraft, socialFirstTimeProfileReady } from '../app/social-onboarding-contract.ts';

test('birth date validation and adulthood boundary',()=>{
 assert.equal(validBirthDate('', '2026-09-06'),false);
 assert.equal(validBirthDate('2026-09-07','2026-09-06'),false);
 assert.equal(validBirthDate('2008-02-30','2026-09-06'),false);
 assert.equal(isAdultBirthDate('2008-09-07','2026-09-06'),false);
 assert.equal(isAdultBirthDate('2008-09-06','2026-09-06'),true);
 assert.equal(isAdultBirthDate('2008-02-29','2026-02-28'),false);
 assert.equal(isAdultBirthDate('2008-02-29','2026-03-01'),true);
});
test('initial profile requires date and preserves it as a private draft field',()=>{
 const profile={displayName:'Jugador',generalArea:'Barcelona',primaryPosition:'Portero',preferredModality:'futbol7'};
 assert.equal(socialFirstTimeProfileReady(profile),false);
 assert.equal(socialFirstTimeProfileReady({...profile,birthDate:'2012-01-01'}),true);
 assert.equal(normalizeSocialOnboardingDraft({birthDate:'2012-01-01'}).birthDate,'2012-01-01');
});
