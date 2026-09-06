import assert from "node:assert/strict";
import test from "node:test";
import { pickRarity, createStrip, odds, tileAtPosition } from "../app/laboratorio-ruleta/roulette";
test("roulette buckets cover the advertised odds exactly", () => {
  const counts = [0,0,0,0,0];
  for (let i=0;i<10000;i++) counts[pickRarity((i+.5)/10000)]++;
  assert.deepEqual(counts, odds.map(p=>p*100));
  for (const invalid of [-1,1,NaN]) assert.throws(()=>pickRarity(invalid));
});
test("the landing chest equals the sampled outcome, irrespective of surrounding tiles", () => {
  for (const roll of [.1,.7,.9,.97,.995]) {
    let first=true;
    const result=createStrip(()=>{if(first){first=false;return roll;}return .2;});
    assert.equal(result.winner,pickRarity(roll));
    assert.equal(result.strip[40],result.winner);
    assert.equal(result.strip.length,48);
  }
});
test("random stopping positions remain safely inside the awarded chest", () => {
  const left = createStrip(() => 0);
  const right = createStrip(() => .999999);
  assert.equal(left.landing, .06);
  assert.ok(right.landing > .93 && right.landing < .94);
  for (const width of [132, 170]) {
    for (const draw of [left, right]) {
      const markerWithinTile = width * draw.landing;
      assert.ok(markerWithinTile > 7 && markerWithinTile < width - 7);
      assert.equal(draw.strip[40], draw.winner);
    }
  }
});

test("adjoining cells have a single owner at their shared boundary", () => {
  assert.equal(tileAtPosition(40 - .000001), 39);
  assert.equal(tileAtPosition(40), 40);
  assert.equal(tileAtPosition(40 + .000001), 40);
  assert.equal(tileAtPosition(41), 41);
});
test("server result overrides decorative sampling and uses configured visual weights", () => {
  const result = createStrip(() => .1, 4, [100,0,0,0,0]);
  assert.equal(result.winner, 4);
  assert.equal(result.strip[40], 4);
  assert.ok(result.strip.every((tier, i) => tier === (i === 40 ? 4 : 0)));
});
