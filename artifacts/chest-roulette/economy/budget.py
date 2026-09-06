"""Finite 100-point budget, opening every prize and reinvesting; no free spins."""
import json
import random
from pathlib import Path
from study import KEYS, RARITIES, ODDS, draw, percentile

rows = []
for initial in ['empty', 'full']:
    for price in [10, 15, 20]:
        values = []
        for seed in range(2000):
            rng = random.Random(99300 + seed)
            owned = set(KEYS if initial == 'full' else [])
            balance, count = 100, 0
            while balance >= price:
                balance -= price
                balance += draw(rng, rng.choices(RARITIES, weights=ODDS)[0], owned)[0]
                count += 1
                assert count < 10000
            values.append(count)
        rows.append(dict(initial=initial, price=price, mean=round(sum(values)/len(values), 2),
                         p50=percentile(values, .5), p95=percentile(values, .95)))
Path(__file__).with_name('budget-100.json').write_text(json.dumps(rows, indent=2)+'\n')
print(json.dumps(rows, indent=2))
