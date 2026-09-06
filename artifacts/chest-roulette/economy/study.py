"""Reproducible design study; no application/database writes. Python stdlib only."""
import json
import math
import random
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
RARITIES = ['common', 'uncommon', 'rare', 'epic', 'legendary']
ODDS = [.60, .25, .10, .04, .01]
sql = (ROOT / 'supabase/migrations/20260808175354_reward_economy_v1.sql').read_text()
mapping_sql = (ROOT / 'supabase/migrations/20260810040115_player_cosmetics_v1.sql').read_text()
mapping = {(r, e): key for r, e, key in re.findall(
    r"\('pool.collective.(\w+)', '([^']+)', '([^']+)'\)", mapping_sql)}
POOLS = {r: [] for r in RARITIES}
for r, entry, kind, weight, low, high, key, duplicate in re.findall(
    r"\(1, 'pool.collective.(\w+)', '([^']+)', '([^']+)', (\d+), (\d+), (\d+), (null|'[^']+'), (\d+),", sql):
    POOLS[r].append(dict(entry=entry, kind=kind, weight=int(weight), low=int(low),
                         high=int(high), key=mapping.get((r, entry)) if key != 'null' else None,
                         duplicate=int(duplicate)))
assert all(sum(e['weight'] for e in pool) == 100 for pool in POOLS.values())
assert all(e['key'] for pool in POOLS.values() for e in pool if e['kind'] != 'points')
KEYS = sorted({e['key'] for p in POOLS.values() for e in p if e['key']})

def draw(rng, rarity, owned):
    entry = rng.choices(POOLS[rarity], weights=[e['weight'] for e in POOLS[rarity]])[0]
    points = rng.randint(entry['low'], entry['high'])
    new = duplicate = 0
    if entry['key']:
        if entry['key'] in owned:
            points += entry['duplicate']
            duplicate = 1
        else:
            owned.add(entry['key'])
            new = 1
    return points, new, duplicate

def poisson(rng, mean):
    product, count = 1, 0
    while product > math.exp(-mean):
        product *= rng.random()
        count += 1
    return count - 1

def components(goals):
    out = []
    while goals > 10:
        if goals % 10 == 1:
            out += [2, 1, 1]
            goals -= 11
        else:
            out += [2, 2]
            goals -= 10
    return out + {2:[0], 3:[1], 4:[1], 5:[2], 6:[1,1], 7:[2,0],
                  8:[1,1], 9:[1,1,1], 10:[2,2]}.get(goals, [])

def season(price, weekly, win_rate, initial, seed, weekly_free=False, test_free=0):
    # Separate match/reward/roulette streams keep match schedules identical across prices.
    matches_rng, box_rng, spin_rng = [random.Random(seed + n) for n in (0, 1000000, 2000000)]
    owned = set(KEYS if initial == 'full' else [])
    if initial == 'half':
        owned.update(random.Random(seed + 3000000).sample(KEYS, len(KEYS)//2))
    # Full collection models an established player; other scenarios start a new team history.
    seen = set(['win','clean','big','close','dominance','trajectory'] +
               [f'goals.{n}' for n in range(2, 50)]) if initial == 'full' else set()
    balance = spins = earned = returned = boxes = new = duplicates = free_spins = 0
    weekly_spins = []
    milestones = {1:0, 5:1, 10:1, 25:2, 50:2, 100:3, 250:3, 500:4}
    for week in range(52):
        before = spins
        for day in range(weekly):
            match = week * weekly + day + 1
            won = matches_rng.random() < win_rate
            drawn = not won and matches_rng.random() < .28
            gf = poisson(matches_rng, 1.75 + (win_rate-.5)*1.7)
            ga = poisson(matches_rng, 1.45 - (win_rate-.5)*.65)
            if won and gf <= ga: gf = ga + 1
            if drawn: gf = ga
            if not won and not drawn and gf >= ga: ga = gf + 1
            rewards = []
            if won: rewards.append((0, 'win'))
            rewards += [(r, f'goals.{gf}') for r in components(gf)]
            if ga == 0: rewards.append((0, 'clean'))
            if won and gf-ga >= 4: rewards.append((1, 'big'))
            if won and gf-ga == 1: rewards.append((0, 'close'))
            if won and gf-ga >= 4 and ga == 0: rewards.append((2, 'dominance'))
            if match in milestones: rewards.append((milestones[match], 'trajectory'))
            for rarity, family in rewards:
                if family not in seen: rarity = min(4, rarity + 1)
                seen.add(family)
                points, _, _ = draw(box_rng, RARITIES[rarity], owned)
                balance += points
                earned += points
                boxes += 1
        # Every scenario plays weekly: eligible for the activity-based weekly free spin.
        # Both assessments are completed in week one only in the bonus sensitivity run.
        for _ in range(int(weekly_free) + (test_free if week == 0 else 0)):
            rarity = spin_rng.choices(RARITIES, weights=ODDS)[0]
            points, fresh, repeated = draw(spin_rng, rarity, owned)
            balance += points
            returned += points
            new += fresh
            duplicates += repeated
            spins += 1
            free_spins += 1
        # Deliberately aggressive policy: open immediately and reinvest all available points.
        while balance >= price:
            balance -= price
            rarity = spin_rng.choices(RARITIES, weights=ODDS)[0]
            points, fresh, repeated = draw(spin_rng, rarity, owned)
            balance += points
            returned += points
            new += fresh
            duplicates += repeated
            spins += 1
            assert spins < 100000, 'Unexpected near-unbounded reinvestment'
        weekly_spins.append(spins-before)
    assert balance == earned + returned - (spins-free_spins)*price
    return dict(spins=spins, earned=earned, returned=returned, boxes=boxes,
                new=new, duplicates=duplicates, weekly=weekly_spins, balance=balance,
                free_spins=free_spins)

def percentile(values, q):
    return sorted(values)[max(0, math.ceil(len(values)*q)-1)]

def main():
    rows = []
    iterations = 400
    for initial in ['empty', 'half', 'full']:
        for weekly in [1,2,4]:
            for win in [.5,.7,.85]:
                for price in [10,15,20]:
                    runs = [season(price, weekly, win, initial, 51000+i) for i in range(iterations)]
                    weeks = [w for run in runs for w in run['weekly']]
                    rows.append(dict(initial=initial, matches_per_week=weekly, win_rate=win, price=price,
                        mean_spins_week=round(sum(r['spins'] for r in runs)/iterations/52, 2),
                        p50_week=percentile(weeks,.5), p95_week=percentile(weeks,.95),
                        zero_spin_weeks_pct=round(100*weeks.count(0)/len(weeks), 1),
                        match_points_week=round(sum(r['earned'] for r in runs)/iterations/52,2),
                        new_roulette_cosmetics_year=round(sum(r['new'] for r in runs)/iterations,2)))
    exact = []
    for initial in ['empty','full']:
        expectation = sum(p * sum(e['weight']/100 * ((e['low']+e['high'])/2 +
            (e['duplicate'] if initial == 'full' and e['key'] else 0)) for e in POOLS[r])
            for p,r in zip(ODDS,RARITIES))
        exact.append(dict(initial=initial, return_points=expectation,
                         net_cost={str(c):c-expectation for c in [10,15,20]}))
    # Independent single-draw Monte Carlo validation of the analytical expectation.
    checks = []
    for initial in ['empty','full']:
        rng = random.Random(91523)
        total = 0
        for _ in range(200000):
            rarity = rng.choices(RARITIES, weights=ODDS)[0]
            total += draw(rng, rarity, set(KEYS if initial == 'full' else []))[0]
        mean = total/200000
        expected = next(e['return_points'] for e in exact if e['initial']==initial)
        assert abs(mean-expected) < .08
        checks.append(dict(initial=initial, simulated=mean, analytical=expected))
    output = dict(iterations_per_scenario=iterations, seasons=len(rows)*iterations,
                  cosmetic_count=len(KEYS), pools=POOLS, exact=exact, checks=checks, scenarios=rows)
    Path(__file__).with_name('results.json').write_text(json.dumps(output, indent=2)+'\n')
    print(json.dumps(dict(exact=exact, checks=checks, representative=[r for r in rows
          if r['win_rate']==.5 and r['matches_per_week']==1]), indent=2))

if __name__ == '__main__':
    main()
