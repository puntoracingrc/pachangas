"""User-approved free-spin sensitivity: active weekly, both tests completed once."""
import json
from pathlib import Path
from study import season, percentile

rows = []
for initial in ['empty', 'full']:
    for weekly in [1, 2, 4]:
        for win in [.5, .7, .85]:
            runs = [season(15, weekly, win, initial, 51000+i, weekly_free=True, test_free=2)
                    for i in range(400)]
            weeks = [w for run in runs for w in run['weekly']]
            assert all(r['free_spins'] == 54 for r in runs)
            rows.append(dict(initial=initial, matches_per_week=weekly, win_rate=win,
                price=15, free_spins_year=54,
                total_spins_week=round(sum(r['spins'] for r in runs)/400/52,2),
                paid_spins_week=round(sum(r['spins']-r['free_spins'] for r in runs)/400/52,2),
                p50_week=percentile(weeks,.5), p95_week=percentile(weeks,.95)))
Path(__file__).with_name('weekly-results.json').write_text(json.dumps(rows,indent=2)+'\n')
print(json.dumps(rows,indent=2))
