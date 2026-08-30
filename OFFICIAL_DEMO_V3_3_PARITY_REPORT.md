# Official / Demo V3.3 Parity Report

## Authority boundary

Demo World V3.3 is a presentation layer over the immutable V3.2 Synthetic
Operations Season. It adds no competition, result, Rating, reward, discipline,
billing, or operational authority.

- V3.2 authority hash:
  `763c8c70cafde739c308a91668f5ca8b9ed6d6b2036935aa4ac1c65e49a8bab1`
- Hash before/after: identical.
- V3.3 remote writes: 0.
- PII: false.
- Auth IDs: false.
- Real entities: 0.

Versions V2.1 through V2.9 and V3.0 through V3.2 remain available and
unchanged. V3.3 references `/demo-world/v3-2/manifest.json` as its authority.

## Presentation parity

| Contract | Official product | Demo V3.3 |
| --- | --- | --- |
| Primary IA | Inicio, Partido, Competir, Mercado, Equipo, Perfil | Same product vocabulary |
| Role context | Server-authoritative capabilities | Synthetic perspective only |
| Context selector | Real team/Club/competition/read model | Synthetic perspective/checkpoint/competition |
| Product states | Canonical state and feedback components | Explanatory read-only examples |
| Competition surfaces | Official read models and commands | Existing production renderers with sanitized preview data |
| Writes | RPC/API with operation and revision contracts | None |
| Offline | Confirmed cache; no sporting write success | Fully navigable immutable snapshots and local tour progress |

## Legitimate differences

- Demo may switch perspective and checkpoint without authentication.
- Demo progress is stored locally and is not a product event.
- Official permission, entitlement, privacy, and mutation responses remain
  server-owned.
- Demo does not create cosmetic ownership, billing objects, notifications, or
  sporting evidence.

## Verification

- Manifest contract and proof hash regression: pass.
- Serialized privacy scan inherited from V3.2: pass.
- Nine-checkpoint eager fetch removed; current plus adjacent only.
- Official renderers remain reused for league scheduling, match operations,
  discipline, referee assignment, Club profile, competition directory, and
  competition hub.
- Service Worker precaches the V3.3 manifest and refuses APIs, private services,
  Stripe, Supabase, Auth, and every non-GET request.
