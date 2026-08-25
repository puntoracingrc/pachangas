# Demo World V2 Production Release

## Checkpoint

- Fecha de cierre: 2026-08-25 18:44 CEST.
- Base inicial: `cc171293e3839b54fe9e0079b480ee78eca2b100`.
- Commit de implementacion: `b31bd6aaca4ccf48c246caa138275bb73ab8ac13`.
- PR: [#189](https://github.com/puntoracingrc/pachangas/pull/189).
- Merge squash en `main`: `f346bb41212925cb0d47ab7d4ed6cef812cbf486`.
- Deployment productivo: `dpl_AencMGPuHicX626q8RSKJq7rvDUZ`.
- Artefacto Vercel: `pachangas-9i71bj560-persianas-almar-web-s-projects.vercel.app`.
- Dominio comprobado: [pachangasiq.com/demo](https://pachangasiq.com/demo).
- Supabase remoto: no modificado.

## Evidencia canonica

| Evidencia | Valor productivo |
| --- | --- |
| Seed | `pachangas-iq-demo-world-v2-2026-27` |
| Hash del snapshot | `f6603605183f1446371ef55b97e7020909fcc91f81533e51e7860f869ca81b3b` |
| Hash de autoridad PostgreSQL | `9b91cedf18c725086da0fe37abf7c38c9ef8ae690179650b76414b5b69c769c1` |
| Migraciones de Simulation World | 141 |
| Recibos Scheduling | 5 |
| Recibos Match Operations | 266 |
| Recibos Operational Exceptions | 13 |
| Escrituras remotas | 0 |

La simulacion se ejecuto en una base PostgreSQL local temporal. La verificacion
recreo el mundo en otra base, obtuvo los mismos hashes y destruyo la base al
terminar. Produccion recibe solo el snapshot estatico sanitizado.

## Gates tecnicos

- `npm run demo-world:v2:verify`: PASS, snapshot identico.
- `npm run test:demo-world:v2`: 10/10.
- `npm test`: 471/471, sin skipped, todo ni cancelled.
- `npm run typecheck`: PASS.
- Lint focal: 0 errores y 0 avisos.
- `npm run build`: PASS, 49 paginas estaticas.
- `git diff --check`: PASS.
- Lint global: deuda heredada sin cambios, 22 errores y 18 avisos fuera del
  diff Demo World V2.
- Vercel Preview del SHA de implementacion: READY y QA superada.
- Checks del PR: Vercel PASS y Vercel Preview Comments PASS.

## QA de produccion

Se comprobo directamente el deployment de `main` y el dominio canonico:

- `/demo` carga Demo World V2 con `data-demo-world="ready"`.
- Liga, Clasificacion, Jornadas, Club y Arbitros abren la seccion correcta.
- 390x844 y 844x390: cero overflow raiz, imagenes rotas u overlay de Next.
- El bloque de incidencias muestra cinco historias: aplazamiento, llegada
  tardia resuelta, cambio de sede, incomparecencia y suspension/reanudacion.
- La llegada tardia abre el read model productivo del CanonicalMatch correcto.
- El manifest productivo responde 200 con el hash V2 exacto.
- El Service Worker responde sin cache, version
  `2.0.0+sw.f346bb412129`, precachea el manifest V2 y reconoce chunks
  `/demo-world/vN/` inmutables.
- Vercel Runtime Errors para `/demo`: ninguno en la ventana posterior al
  release.
- Logs 5xx del deployment productivo: ninguno en la misma ventana.

Android fisico, iPhone fisico y PWA instalada en dispositivo fisico no se
presentan como PASS porque no formaron parte de esta comprobacion automatizada.

## Autoridad y aislamiento

- El navegador solo descarga recursos `GET` del snapshot.
- No hay RPC, mutaciones Supabase, Auth real, PII, tokens ni `service_role` en
  el bundle Demo.
- StandingSnapshot y resultados se calculan durante la simulacion
  autoritativa, no en cada lectura del navegador.
- Demo World V1 permanece versionada en `/demo-world/v1/` como evidencia
  historica.
- Referee Assignments permanece desactivado.
- Rating V2, rewards, Conduct, billing, ranking, Player Cosmetics y Team
  Cosmetics no fueron modificados por la release.

## Resultado

Demo World V2 League Private Beta parity queda fusionada y publicada en
produccion. No quedan migraciones ni cambios de Supabase asociados a esta fase.

## Evolucion V2.1 publicada

Demo World V2.1 mantiene este mundo y le incorpora Competition Discipline V1
con los renderers productivos de Liga, partido y disciplina. El snapshot final
se genera sobre las `147` migraciones, conserva `0` escrituras remotas y
obtiene estos hashes deterministas:

- autoridad PostgreSQL:
  `f833b84f08aa859b14e31a4c11b676b996f8c80ae0813727467f2ae23d6849f9`;
- snapshot publico:
  `0eae1613e2d84fdd5f0821cfc2f7ad77b7bc4193a6c50ee3d58c0431ee493a51`.

La publicacion final usa los PR #192, #193 y #194. El runtime productivo de
codigo queda en `0401a127ebd910ccad799b466ad3327782067b37`, deployment
`dpl_DEugDYDWVWYAnkKehr3syFHmqEnx`, con Service Worker
`2.0.0+sw.0401a127ebd9`. El smoke de V2.1 se registra en
`DEMO_WORLD_V2_1_DISCIPLINE_PARITY_REPORT.md`.
