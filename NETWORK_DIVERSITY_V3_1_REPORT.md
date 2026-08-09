# Season Score V3.1 - Recalibración de diversidad de red

## Trazabilidad

- Fuente: Synthetic World V1 `3df9494d-3b8c-4447-96e8-d5244892af78`, revisión 313, secuencia 69458.
- Hash SHA-256 antes/después: `23b6b9d6367fa684f65bd45fbfe9d587382513d153281bb5ba4b8455ff84d0e3` / `23b6b9d6367fa684f65bd45fbfe9d587382513d153281bb5ba4b8455ff84d0e3`.
- V1 original y V1.1: preservados. Clones V3 A-E: preservados. Clones M0-M5: model_0_v3=`f0c5caa8-485c-4b6b-8794-8beedf5fcf6c`, model_1_absolute=`ff92f18b-e62e-4319-89c9-641e1d10aaf6`, model_2_relative=`739e23fa-e21f-48cd-9cb4-b843c5a45757`, model_3_relative_floor=`a11d8116-81f8-468a-8799-7725c71c4ead`, model_4_composite_integrity=`2c8bce99-f654-48fb-8825-e849980d7b7d`, model_5_opportunity_adjusted=`3d8bb21f-394b-4b30-9ada-64b31cc90520`.
- Rating V2, GRL, facetas y assessments: solo lectura, sin cambios.
- Conducta/reportes/no-show: pausados; permanecen 37 posibles no-shows y 79 escenarios de reportes.
- Producto V3 activo: sin sustituir. V3.1 sigue siendo investigación; ningún candidato se acepta sin superar también los objetivos en V1.

## Definición exacta actual

`competitionNetworkDiversity = clamp((structuralDiversity * 0.72 + externalNetworkRatio * 0.28) * (1 - outcomeAnomaly * (1 - externalNetworkRatio) * 0.35), 0, 1)`.

- `structuralDiversity`: suma de la mejor independencia por rival lógico dividida por rivales técnicos.
- `externalNetworkRatio`: para cada rival técnico, proporción de sus vecinos que no están ni en los equipos propios ni en el conjunto de rivales del jugador; después se promedia.
- `outcomeAnomaly`: ventaja positiva media sobre el resultado esperado.

La hipótesis queda **confirmada**: una red local sana y conectada reduce `externalNetworkRatio` porque los rivales también juegan entre sí. La señal absoluta mezcla conectividad deportiva normal con cierre sospechoso. En 10 equipos sanos la mediana actual es 0.5862; en 1.000 equipos es 0.7176.

## Componentes instrumentados

El laboratorio expone `logical_opponent_count`, `pair_independence`, `opponent_cluster_diversity`, `external_exposure`, `reciprocity`, `closed_network_ratio`, `opponent_entropy`, `ecosystem_opportunity`, `territorial_network_density` y `available_competitive_opportunity`. La reciprocidad del grafo V3 es 1 por construcción porque sus aristas son no dirigidas; se conserva como diagnóstico, pero no discrimina abuso y no entra en el modelo de referencia.

## Tamaño de ecosistema, 30 seeds

| Equipos | Diversity p50 | Candidatos 25/10 | V3 certificables | V3.1 certificables | FPR V3 | FPR V3.1 |
| --- | --- | --- | --- | --- | --- | --- |
| 10 | 0.5862 | 0 | 0 | 0 | 0 | 0 |
| 20 | 0.6827 | 20 | 11 | 20 | 0.45 | 0 |
| 30 | 0.6996 | 30 | 26.97 | 30 | 0.1011 | 0 |
| 50 | 0.7078 | 50 | 47.77 | 50 | 0.0447 | 0 |
| 75 | 0.7111 | 75 | 73.47 | 75 | 0.0204 | 0 |
| 100 | 0.713 | 100 | 97.97 | 100 | 0.0203 | 0 |
| 200 | 0.7154 | 200 | 196.57 | 200 | 0.0172 | 0 |
| 500 | 0.7171 | 500 | 493.03 | 500 | 0.0139 | 0 |
| 1000 | 0.7176 | 1000 | 986.4 | 1000 | 0.0136 | 0 |

Los 10 equipos no producen candidatos 25/10 porque solo existen 9 rivales posibles; la respuesta correcta es ranking visible y trofeo no preparado, no rebajar 25/10.

## Modelos 0-5

| Modelo | FPR sano | Cert. legítima | Recall abuso | Precision abuso | Top10 cert. | Top20 cert. | Top50 cert. |
| --- | --- | --- | --- | --- | --- | --- | --- |
| model_0_v3 | 0.0212 | 0.98 | 1 | 0.4944 | 0 | 0 | 0 |
| model_2_relative | 0 | 1 | 0.1064 | 0.3386 | 0 | 0 | 0 |
| model_3_relative_floor | 0 | 1 | 0.1064 | 0.3386 | 0 | 0 | 0 |
| model_4_composite_integrity | 0 | 1 | 0.1064 | 0.3386 | 0 | 0 | 0 |
| model_5_opportunity_adjusted | 0 | 1 | 0.1064 | 0.3386 | 0 | 0 | 0 |

| Umbral absoluto | FPR sano | Recall abuso | Contam. certificada |
| --- | --- | --- | --- |
| 0.4 | 0 | 0 | 0.2 |
| 0.45 | 0 | 0 | 0.2 |
| 0.5 | 0 | 0 | 0.2 |
| 0.55 | 0 | 0.0638 | 0.1 |
| 0.6 | 0 | 1 | 0 |
| 0.65 | 0.0004 | 1 | 0 |
| 0.68 | 0.0212 | 1 | 0 |

El control absoluto muestra que elegir un único número puede mejorar una muestra, pero no resuelve la dependencia del tamaño ni explica abuso.

## Mundo sano, club y mundo manipulado

- Sano: relaciones cruzadas naturales y revancha moderada.
- Club local: diez equipos juegan mucho entre sí, con conexiones externas reales; V3.1 no lo trata automáticamente como fraude.
- Manipulado: ring coordinado, cinco equipos falsos con owner/admin/plantilla compartidos, farming y beneficiarios con resultados anómalos.
- Estabilidad: añadir 100 equipos desconectados deja la decisión del jugador núcleo estable: **true**.

### Un mismo territorio creciendo

| Etapa | Equipos | Candidatos 25/10 | V3 cert. | V3.1 cert. | Abs núcleo | Oportunidad núcleo | Núcleo V3.1 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| mes 1 | 10 | 0 | 0 | 0 | 0.5804 | 9 | HOLD |
| mes 3 | 20 | 20 | 0 | 10 | 0.6091 | 19 | HOLD |
| mes 6 | 35 | 35 | 19 | 35 | 0.6638 | 34 | RELEASE |
| mes 9 | 50 | 50 | 49 | 50 | 0.703 | 49 | RELEASE |
| año 2 | 80 | 80 | 80 | 80 | 0.7581 | 79 | RELEASE |
| año 3 | 150 | 150 | 150 | 150 | 0.801 | 149 | RELEASE |

Los Team IDs son acumulativos: cada etapa conserva íntegramente los equipos de la anterior. La decisión puede cambiar cuando el jugador realmente añade rivales; la regresión separada confirma que añadir cien equipos desconectados con los que no juega no altera su oportunidad ni su certificación contextual.

## Synthetic World V1

| Modelo | Certificables | FPR | Recall | Top10 | Top10 cert. |
| --- | --- | --- | --- | --- | --- |
| model_0_v3 | 1 | 0.9412 | 0 | 0.0175 | 0 |
| model_1_absolute @ 0.4 | 17 | 0 | 0 | 0.0175 | 0 |
| model_1_absolute @ 0.45 | 17 | 0 | 0 | 0.0175 | 0 |
| model_1_absolute @ 0.5 | 16 | 0.0588 | 0 | 0.0175 | 0 |
| model_1_absolute @ 0.55 | 13 | 0.2353 | 0 | 0.0175 | 0 |
| model_1_absolute @ 0.6 | 5 | 0.7059 | 0 | 0.0175 | 0 |
| model_1_absolute @ 0.65 | 1 | 0.9412 | 0 | 0.0175 | 0 |
| model_1_absolute @ 0.68 | 1 | 0.9412 | 0 | 0.0175 | 0 |
| model_2_relative | 16 | 0.0588 | 0 | 0.0175 | 0 |
| model_3_relative_floor | 16 | 0.0588 | 0 | 0.0175 | 0 |
| model_4_composite_integrity | 17 | 0 | 0 | 0.0175 | 0 |
| model_5_opportunity_adjusted | 16 | 0.0588 | 0 | 0.0175 | 0 |

### Superficies Top10, Top20 y Top50

| Modelo | Top10 | Top10 cert. | Top20 | Top20 cert. | Top50 | Top50 cert. |
| --- | --- | --- | --- | --- | --- | --- |
| model_0_v3 | 0.0175 | 0 | 0.0127 | 0 | 0.015 | 0 |
| model_1_absolute @ 0.4 | 0.0175 | 0 | 0.0127 | 0 | 0.015 | 0 |
| model_1_absolute @ 0.45 | 0.0175 | 0 | 0.0127 | 0 | 0.015 | 0 |
| model_1_absolute @ 0.5 | 0.0175 | 0 | 0.0127 | 0 | 0.015 | 0 |
| model_1_absolute @ 0.55 | 0.0175 | 0 | 0.0127 | 0 | 0.015 | 0 |
| model_1_absolute @ 0.6 | 0.0175 | 0 | 0.0127 | 0 | 0.015 | 0 |
| model_1_absolute @ 0.65 | 0.0175 | 0 | 0.0127 | 0 | 0.015 | 0 |
| model_1_absolute @ 0.68 | 0.0175 | 0 | 0.0127 | 0 | 0.015 | 0 |
| model_2_relative | 0.0175 | 0 | 0.0127 | 0 | 0.015 | 0 |
| model_3_relative_floor | 0.0175 | 0 | 0.0127 | 0 | 0.015 | 0 |
| model_4_composite_integrity | 0.0175 | 0 | 0.0127 | 0 | 0.015 | 0 |
| model_5_opportunity_adjusted | 0.0175 | 0 | 0.0127 | 0 | 0.015 | 0 |

- Atacantes etiquetados: 44.
- Atacantes con abuso observable ejecutado: 10.
- Legítimos HOLD actuales auditados: 50.
- Con el Modelo 3 como referencia de investigación: ranking 135, candidatos 25/10 17, elegibles 16, pending 1, holds legítimos 1, holds de abuso ejecutado 0, contaminación Top10 territorial 0.0175.

### 50 legítimos actualmente HOLD, uno por uno

| Jugador | Abs | Rel | Lógicos | Técnicos | Team IDs reales | Confianza | Indep. | Closed | Oportunidad | V3.1 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| SIM · Alma M. 002 | 0.5339 | 0.5096 | 19 | 22 | team-34, team-36 | 0.7208 | 0.6617 | 0.8934890722676764 | 6 | RELEASE |
| SIM · Alex D. 003 | 0.5714 | 0.5602 | 19 | 21 | team-09 | 0.8058 | 0.7642 | 0.8326229424505005 | 8 | RELEASE |
| SIM · Leo S. 049 | 0.5853 | 0.4888 | 14 | 16 | team-30 | 0.7711 | 0.6979 | 0.6892541109253065 | 8 | RELEASE |
| SIM · Lina N. 061 | 0.5998 | 0.4856 | 14 | 17 | team-23, team-26 | 0.7955 | 0.6463 | 0.5849376461844493 | 10 | RELEASE |
| SIM · Paula P. 065 | 0.5816 | 0.5569 | 15 | 17 | team-25 | 0.7794 | 0.6609 | 0.7177381128690188 | 7 | RELEASE |
| SIM · Hugo M. 069 | 0.5867 | 0.6281 | 13 | 15 | team-25 | 0.8023 | 0.7477 | 0.6546986324549254 | 7 | RELEASE |
| SIM · Lina G. 086 | 0.6001 | 0.541 | 12 | 14 | team-30 | 0.7345 | 0.7407 | 0.591323459149546 | 8 | RELEASE |
| SIM · Nico F. 108 | 0.4228 | 0.5616 | 10 | 13 | team-31 | 0.7259 | 0.5893 | 1 | 2 | RELEASE |
| SIM · Nico C. 112 | 0.5571 | 0.4846 | 12 | 15 | team-36 | 0.7611 | 0.6083 | 0.6561227902532251 | 7 | RELEASE |
| SIM · Nico C. 123 | 0.6223 | 0.5621 | 17 | 18 | team-09 | 0.8405 | 0.7712 | 0.728284000762071 | 8 | RELEASE |
| SIM · Bruno B. 127 | 0.578 | 0.3404 | 14 | 16 | team-14, team-17 | 0.8228 | 0.7194 | 0.6893096475336893 | 0 | HOLD |
| SIM · Uri A. 142 | 0.4763 | 0.581 | 10 | 12 | team-08 | 0.8016 | 0.6279 | 0.9169256669256669 | 2 | RELEASE |
| SIM · Leo R. 143 | 0.4504 | 0.6006 | 13 | 17 | team-29, team-40 | 0.763 | 0.7455 | 0.9189291101055806 | 3 | RELEASE |
| SIM · Irene S. 154 | 0.5923 | 0.5806 | 16 | 18 | team-15 | 0.8046 | 0.7486 | 0.7119608383042784 | 7 | RELEASE |
| SIM · Marta S. 156 | 0.4244 | 0.5743 | 10 | 13 | team-31, team-40 | 0.7454 | 0.6331 | 1 | 2 | RELEASE |
| SIM · Vera C. 159 | 0.5829 | 0.4945 | 15 | 17 | team-01 | 0.7332 | 0.6066 | 0.6782672482241738 | 1 | RELEASE |
| SIM · Joel N. 188 | 0.629 | 0.5825 | 16 | 17 | team-25 | 0.8195 | 0.7262 | 0.6766605149684972 | 7 | RELEASE |
| SIM · Vera S. 192 | 0.5285 | 0.5207 | 20 | 23 | team-01 | 0.7647 | 0.7208 | 0.8896732388263082 | 1 | RELEASE |
| SIM · Noa P. 194 | 0.4227 | 0.3398 | 10 | 13 | team-23 | 0.7671 | 0.6069 | 1 | 3 | HOLD |
| SIM · Rai M. 222 | 0.5422 | 0.509 | 18 | 21 | team-01 | 0.7461 | 0.6809 | 0.8212526595061737 | 1 | RELEASE |
| SIM · Dani D. 286 | 0.5755 | 0.3214 | 20 | 22 | team-14, team-17 | 0.7566 | 0.7025 | 0.8441989964015135 | 0 | HOLD |
| SIM · Dani A. 300 | 0.5503 | 0.5135 | 18 | 21 | team-25 | 0.7303 | 0.7064 | 0.8132677475926904 | 7 | RELEASE |
| SIM · Marc S. 317 | 0.467 | 0.4902 | 10 | 12 | team-12 | 0.722 | 0.6425 | 0.9256507381507382 | 3 | HOLD |
| SIM · Eva M. 319 | 0.5965 | 0.5008 | 13 | 15 | team-27 | 0.7607 | 0.7089 | 0.6633097980924068 | 8 | RELEASE |
| SIM · Nico V. 337 | 0.5476 | 0.4729 | 17 | 20 | team-36 | 0.7977 | 0.6709 | 0.8208773021092814 | 7 | RELEASE |
| SIM · Sofía G. 371 | 0.5675 | 0.521 | 18 | 20 | team-09 | 0.7411 | 0.7547 | 0.8029671448561608 | 8 | RELEASE |
| SIM · Sara L. 373 | 0.5522 | 0.4971 | 16 | 19 | team-36 | 0.7465 | 0.628 | 0.7421564643153226 | 7 | RELEASE |
| SIM · Noa C. 378 | 0.6229 | 0.6402 | 19 | 20 | team-09, team-39 | 0.7918 | 0.7855 | 0.7696973926467634 | 7 | RELEASE |
| SIM · Víctor B. 384 | 0.5754 | 0.2796 | 19 | 21 | team-01, team-04 | 0.8249 | 0.7502 | 0.8004281803276573 | 0 | HOLD |
| SIM · Víctor S. 413 | 0.5374 | 0.5169 | 18 | 21 | team-15 | 0.7821 | 0.7178 | 0.8512969329412612 | 7 | RELEASE |
| SIM · Marta D. 420 | 0.6677 | 0.5354 | 13 | 15 | team-26, team-37 | 0.8324 | 0.7096 | 0.43760423634336665 | 10 | RELEASE |
| SIM · Rai V. 421 | 0.5741 | 0.5565 | 14 | 16 | team-25 | 0.7414 | 0.6762 | 0.7136690444535124 | 7 | RELEASE |
| SIM · Hugo G. 430 | 0.5392 | 0.604 | 20 | 24 | team-13, team-50 | 0.7309 | 0.7545 | 0.7875976249045471 | 9 | RELEASE |
| SIM · Hugo V. 445 | 0.5412 | 0.4998 | 10 | 11 | team-23 | 0.7456 | 0.6804 | 0.8416684325775234 | 3 | RELEASE |
| SIM · Marta B. 448 | 0.4231 | 0.5861 | 10 | 13 | team-08, team-31 | 0.7283 | 0.6732 | 1 | 1 | RELEASE |
| SIM · Joel F. 460 | 0.5447 | 0.5375 | 18 | 21 | team-20, team-30 | 0.7404 | 0.7168 | 0.8473617738369291 | 7 | RELEASE |
| SIM · Uri T. 481 | 0.6291 | 0.5794 | 16 | 17 | team-09 | 0.7328 | 0.7793 | 0.6889625441637826 | 8 | RELEASE |
| SIM · Marta M. 503 | 0.4234 | 0.3854 | 10 | 13 | team-23 | 0.8141 | 0.6892 | 1 | 3 | RELEASE |
| SIM · Sofía F. 514 | 0.5383 | 0.5381 | 18 | 21 | team-36 | 0.7305 | 0.6813 | 0.8447318480376669 | 7 | RELEASE |
| SIM · Bruno F. 527 | 0.5754 | 0.5877 | 17 | 19 | team-15 | 0.7934 | 0.7789 | 0.7823359030199931 | 7 | RELEASE |
| SIM · Pablo G. 530 | 0.423 | 0.4571 | 10 | 13 | team-12 | 0.7445 | 0.6757 | 1 | 3 | RELEASE |
| SIM · Vera P. 545 | 0.5336 | 0.5104 | 18 | 21 | team-09, team-30 | 0.7659 | 0.6981 | 0.8408341459371207 | 7 | RELEASE |
| SIM · Marta V. 569 | 0.5693 | 0.5108 | 15 | 18 | team-15 | 0.7717 | 0.6922 | 0.6938690295212036 | 7 | RELEASE |
| SIM · Irene B. 586 | 0.4814 | 0.479 | 28 | 35 | team-01, team-40 | 0.7985 | 0.6779 | 0.9277015091080145 | 1 | RELEASE |
| SIM · Pablo P. 588 | 0.5411 | 0.5 | 14 | 17 | team-30 | 0.8029 | 0.6925 | 0.7251471134719216 | 8 | RELEASE |
| SIM · Vera D. 596 | 0.5309 | 0.4967 | 15 | 18 | team-39 | 0.7965 | 0.7434 | 0.7693806895847323 | 8 | RELEASE |
| SIM · Joel A. 604 | 0.5477 | 0.559 | 16 | 19 | team-34, team-36 | 0.8232 | 0.6959 | 0.7765276079120473 | 6 | RELEASE |
| SIM · Alex F. 609 | 0.5254 | 0.47 | 19 | 25 | team-10, team-39 | 0.7573 | 0.6434 | 0.6937958321109351 | 10 | RELEASE |
| SIM · Lina L. 612 | 0.5662 | 0.5526 | 19 | 21 | team-01, team-02 | 0.7862 | 0.7675 | 0.8357069124076315 | 3 | RELEASE |
| SIM · Noa F. 635 | 0.4812 | 0.5863 | 10 | 12 | team-08 | 0.79 | 0.6366 | 0.9169256669256669 | 2 | RELEASE |

### 44 atacantes etiquetados

| Jugador | Perfil | Abuso ejecutado | Abs | Rel | Lógicos | Técnicos | Team IDs reales | Confianza | Riesgo abs. | V3.1 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| SIM · Lina L. 009 | sybil_operator | false | 0.6588 | 0.5215 | 9 | 10 | team-26 | 0.7037 | 0.0724 | NO HOLD |
| SIM · Marc F. 020 | team_hopper | false | 0.6594 | 0.5965 | 7 | 8 | team-04 | 0.727 | 0.083 | NO HOLD |
| SIM · Eric N. 026 | rating_manipulator | false | 0.6223 | 0.4698 | 11 | 13 | team-16 | 0.6808 | 0.1025 | NO HOLD |
| SIM · Noa A. 034 | sybil_operator | false | 0 | 0.102 | 0 | 0 |  | 0 | 0.82 | HOLD |
| SIM · Bruno B. 077 | colluder | false | 0.435 | 0.5228 | 4 | 5 | team-29 | 0.6786 | 0.12 | NO HOLD |
| SIM · Pablo G. 083 | team_hopper | false | 0.7175 | 0.557 | 11 | 11 | team-27 | 0.8502 | 0.0289 | NO HOLD |
| SIM · Irene F. 099 | opponent_farmer | true | 0.4321 | 0.3437 | 7 | 10 | team-18 | 0.6505 | 0.1596 | HOLD |
| SIM · Carla L. 100 | opponent_farmer | false | 0.742 | 0.5298 | 6 | 6 | team-39 | 0.7479 | 0.0082 | NO HOLD |
| SIM · Joel R. 104 | fake_team_operator | false | 0.6691 | 1 | 6 | 6 | team-40 | 0.6862 | 0.062 | NO HOLD |
| SIM · Noa A. 110 | opponent_farmer | false | 0.6592 | 0.6016 | 8 | 9 | team-02, team-17 | 0.7083 | 0.0823 | NO HOLD |
| SIM · Sara N. 130 | team_hopper | true | 0.475 | 0.531 | 37 | 46 | team-05, team-41, team-42, team-43, team-44, team-45, team-46, team-47, team-48, team-49, team-50 | 0.6409 | 0.3276 | NO HOLD |
| SIM · Leo B. 139 | rating_manipulator | false | 0.613 | 0.4044 | 2 | 2 | team-02 | 0.6292 | 0.76 | HOLD |
| SIM · Alma L. 168 | rating_manipulator | false | 0 | 0.2998 | 0 | 0 |  | 0 | 0.82 | HOLD |
| SIM · Bruno V. 176 | rating_manipulator | true | 0.4332 | 0.3715 | 7 | 10 | team-12 | 0.6834 | 0.1394 | HOLD |
| SIM · Leo M. 204 | ghost_participant | true | 0.6032 | 0.5794 | 15 | 17 | team-20 | 0.5059 | 0.1752 | NO HOLD |
| SIM · Marc R. 205 | opponent_farmer | false | 0.5647 | 0.595 | 20 | 22 | team-09, team-39 | 0.8289 | 0.1158 | NO HOLD |
| SIM · Carla R. 216 | rating_manipulator | false | 0.4953 | 0.3773 | 8 | 10 | team-03 | 0.7292 | 0.082 | HOLD |
| SIM · Pablo B. 228 | territory_gamer | false | 0.6129 | 0.4487 | 10 | 12 | team-07 | 0.6262 | 0.76 | HOLD |
| SIM · Noa C. 229 | colluder | false | 0.6769 | 0.5209 | 7 | 8 | team-07 | 0.5742 | 0.1095 | NO HOLD |
| SIM · Joel L. 231 | colluder | false | 0.6019 | 0.5092 | 9 | 11 | team-22 | 0.7202 | 0.1203 | NO HOLD |
| SIM · Leo B. 250 | territory_gamer | false | 0.5261 | 0.5992 | 20 | 23 | team-15 | 0.7376 | 0.088 | NO HOLD |
| SIM · Vera M. 257 | team_hopper | true | 0.5925 | 0.51 | 12 | 14 | team-20 | 0.6104 | 0.1585 | NO HOLD |
| SIM · Lina L. 267 | rating_manipulator | false | 0.5767 | 0.5 | 16 | 19 | team-28, team-35 | 0.6625 | 0.143 | NO HOLD |
| SIM · Hugo S. 291 | sybil_operator | false | 0 | 0.2757 | 0 | 0 | team-33 | 0 | 0.82 | HOLD |
| SIM · Sofía B. 297 | team_hopper | false | 0.612 | 0.4523 | 9 | 11 | team-24 | 0.7386 | 0.1236 | NO HOLD |
| SIM · Noa R. 334 | ghost_participant | true | 0.4108 | 0.5556 | 5 | 6 | team-05 | 0.5665 | 0.2352 | NO HOLD |
| SIM · Pablo G. 338 | rating_manipulator | true | 0.4691 | 0.4444 | 13 | 18 | team-23, team-26 | 0.7304 | 0.1343 | NO HOLD |
| SIM · Lina G. 360 | rating_manipulator | false | 0.6084 | 1 | 14 | 16 | team-35 | 0.7165 | 0.1091 | NO HOLD |
| SIM · Paula B. 367 | sybil_operator | false | 0.5201 | 0.4985 | 21 | 24 | team-25, team-34 | 0.666 | 0.1332 | NO HOLD |
| SIM · Leo N. 390 | team_hopper | false | 0.7446 | 0.7656 | 8 | 8 | team-25 | 0.7479 | 0.0193 | NO HOLD |
| SIM · Hugo P. 398 | territory_gamer | true | 0.4238 | 0.5423 | 4 | 5 | team-05 | 0.613 | 0.2129 | NO HOLD |
| SIM · Paula A. 425 | opponent_farmer | false | 0 | 0.2566 | 0 | 0 |  | 0 | 0.82 | HOLD |
| SIM · Hugo R. 437 | ghost_participant | true | 0.5565 | 0.5181 | 16 | 20 | team-21, team-38 | 0.5245 | 0.2124 | NO HOLD |
| SIM · Marc C. 457 | opponent_farmer | false | 0.5552 | 0.5688 | 12 | 15 | team-22 | 0.6567 | 0.0975 | NO HOLD |
| SIM · Pablo G. 462 | opponent_farmer | false | 0 | 0.2998 | 0 | 0 |  | 0 | 0.82 | HOLD |
| SIM · Eva R. 463 | colluder | false | 0.7172 | 0.6382 | 4 | 4 | team-14 | 0.7462 | 0.0097 | NO HOLD |
| SIM · Pablo F. 480 | fake_team_operator | false | 0.5469 | 0.439 | 14 | 17 | team-30 | 0.7434 | 0.0965 | NO HOLD |
| SIM · Sara N. 499 | colluder | false | 0.5698 | 0.5456 | 4 | 4 | team-29 | 0.8364 | 0.1295 | NO HOLD |
| SIM · Sergio T. 510 | team_hopper | false | 0.5965 | 0.585 | 13 | 15 | team-14 | 0.7373 | 0.0717 | NO HOLD |
| SIM · Uri F. 512 | team_hopper | true | 0.4263 | 0.3901 | 4 | 5 | team-38 | 0.5487 | 0.1948 | NO HOLD |
| SIM · Sara A. 523 | colluder | false | 0 | 0.2566 | 0 | 0 | team-37 | 0 | 0.82 | HOLD |
| SIM · Víctor S. 538 | rating_manipulator | false | 0.6701 | 0.5228 | 7 | 8 | team-27 | 0.6704 | 0.0415 | NO HOLD |
| SIM · Eva R. 591 | fake_team_operator | false | 0.6585 | 0.5045 | 6 | 7 | team-26 | 0.7837 | 0.0782 | NO HOLD |
| SIM · Alma G. 611 | opponent_farmer | false | 0.5446 | 0.4973 | 12 | 15 | team-01 | 0.63 | 0.1017 | NO HOLD |

La decisión usa comportamiento observable. Una etiqueta `attacker` sin acción relevante no obliga a HOLD.

## Top20 Barcelona, revisión manual

| # | Jugador | Score | V3.1 | Hechos |
| --- | --- | --- | --- | --- |
| 1 | SIM · Alex F. 609 | 749.05 | NO CANDIDATO | 19 rivales lógicos; 16 Team IDs con conexiones externas; 13/41 evidencias en el rival dominante; oportunidad 100%. |
| 2 | SIM · Pablo G. 029 | 744.63 | NO CANDIDATO | 10 rivales lógicos; 12 Team IDs con conexiones externas; 3/12 evidencias en el rival dominante; oportunidad 100%. |
| 3 | SIM · Paula N. 416 | 743.1 | NO CANDIDATO | 14 rivales lógicos; 13 Team IDs con conexiones externas; 3/20 evidencias en el rival dominante; oportunidad 100%. |
| 4 | SIM · Sofía F. 054 | 736.56 | NO CANDIDATO | 9 rivales lógicos; 0 Team IDs con conexiones externas; 9/27 evidencias en el rival dominante; oportunidad 100%. |
| 5 | SIM · Lina R. 173 | 725.23 | NO CANDIDATO | 12 rivales lógicos; 14 Team IDs con conexiones externas; 5/23 evidencias en el rival dominante; oportunidad 0%. |
| 6 | SIM · Hugo V. 445 | 715.82 | NO CANDIDATO | 10 rivales lógicos; 0 Team IDs con conexiones externas; 10/37 evidencias en el rival dominante; oportunidad 100%. |
| 7 | SIM · Lina N. 061 | 712.18 | NO CANDIDATO | 14 rivales lógicos; 11 Team IDs con conexiones externas; 11/35 evidencias en el rival dominante; oportunidad 100%. |
| 8 | SIM · Paula M. 280 | 708.95 | NO CANDIDATO | 16 rivales lógicos; 9 Team IDs con conexiones externas; 7/29 evidencias en el rival dominante; oportunidad 100%. |
| 9 | SIM · Marc R. 205 | 703.89 | CERTIFICABLE | 20 rivales lógicos; 1 Team IDs con conexiones externas; 8/56 evidencias en el rival dominante; oportunidad 100%. |
| 10 | SIM · Marc G. 226 | 703.86 | NO CANDIDATO | 5 rivales lógicos; 6 Team IDs con conexiones externas; 4/9 evidencias en el rival dominante; oportunidad 100%. |
| 11 | SIM · Marta M. 503 | 703.23 | NO CANDIDATO | 10 rivales lógicos; 0 Team IDs con conexiones externas; 7/27 evidencias en el rival dominante; oportunidad 100%. |
| 12 | SIM · Bruno N. 513 | 698.12 | NO CANDIDATO | 18 rivales lógicos; 8 Team IDs con conexiones externas; 7/34 evidencias en el rival dominante; oportunidad 100%. |
| 13 | SIM · Leo C. 382 | 697.69 | NO CANDIDATO | 5 rivales lógicos; 6 Team IDs con conexiones externas; 5/13 evidencias en el rival dominante; oportunidad 63%. |
| 14 | SIM · Eva D. 351 | 696.42 | NO CANDIDATO | 8 rivales lógicos; 8 Team IDs con conexiones externas; 2/9 evidencias en el rival dominante; oportunidad 0%. |
| 15 | SIM · Eva S. 281 | 692.98 | NO CANDIDATO | 0 rivales lógicos; 0 Team IDs con conexiones externas; 0/0 evidencias en el rival dominante; oportunidad 0%. |
| 16 | SIM · Sara T. 476 | 682.76 | NO CANDIDATO | 4 rivales lógicos; 4 Team IDs con conexiones externas; 1/4 evidencias en el rival dominante; oportunidad 100%. |
| 17 | SIM · Joel A. 349 | 681.28 | NO CANDIDATO | 9 rivales lógicos; 11 Team IDs con conexiones externas; 5/18 evidencias en el rival dominante; oportunidad 100%. |
| 18 | SIM · Nico S. 092 | 679.15 | NO CANDIDATO | 8 rivales lógicos; 8 Team IDs con conexiones externas; 2/11 evidencias en el rival dominante; oportunidad 100%. |
| 19 | SIM · Víctor F. 534 | 678.96 | NO CANDIDATO | 3 rivales lógicos; 3 Team IDs con conexiones externas; 1/3 evidencias en el rival dominante; oportunidad 38%. |
| 20 | SIM · Lina B. 158 | 677.17 | NO CANDIDATO | 6 rivales lógicos; 7 Team IDs con conexiones externas; 3/10 evidencias en el rival dominante; oportunidad 75%. |

La lectura es razonable cuando el HOLD se explica por abuso absoluto, colapso lógico, concentración anómala o posición contextual extrema; la mera conectividad local deja de ser motivo suficiente.

## Red team

| Ataque | Riesgo V3 | Score riesgo | HOLD V3.1 | Motivos |
| --- | --- | --- | --- | --- |
| collusion | clean | 8.57 | true | absolute_diversity_floor, absolute_abuse_signal |
| fake_matches | clean | 21.53 | true | absolute_abuse_signal |
| fake_participation | clean | 13.47 | true | absolute_abuse_signal |
| ghost_teams | watch | 38.5 | true | absolute_diversity_floor, absolute_abuse_signal |
| impossible_volume | clean | 18 | true | absolute_abuse_signal |
| opponent_boost | clean | 11.38 | true | absolute_diversity_floor, absolute_abuse_signal |
| rating_boost | clean | 8.14 | false |  |
| repeated_opponent | watch | 33.72 | true | absolute_diversity_floor, absolute_abuse_signal |
| sacrifice_accounts | suspicious | 51.41 | true | absolute_diversity_floor, absolute_abuse_signal |
| simultaneous_matches | watch | 25.66 | true | absolute_abuse_signal |
| smurf | clean | 5 | true | absolute_abuse_signal |
| sybil | suspicious | 54.15 | true | absolute_diversity_floor, absolute_abuse_signal |
| team_hopping | clean | 6.57 | true | absolute_abuse_signal |
| territory_gaming | clean | 11.5 | true | absolute_abuse_signal |

Se repitieron sybil, ghost/fake teams, collusion, win trading/fake matches, repeated opponent, fake participation, rating/opponent boosting, team hopping, territory gaming y sacrifice accounts mediante el catálogo V3. Cuando un ataque no supera 25/10 o elegibilidad, no puede contaminar trofeo aunque su HOLD de red sea falso.

## Comparación 10k

- V3: 4635 certificables; FPR 0.
- V3.1: 4613 certificables; FPR 0.0047.
- Season Score y orden territorial no cambian; solo se compara certificación.

## Territory award readiness

| Provincia | Equipos activos | Rankeados | Certificables | Estado |
| --- | --- | --- | --- | --- |
| 17 | 4 | 7 | 1 | ranking_active |
| 28 | 15 | 52 | 5 | trophy_not_ready |
| 08 | 15 | 44 | 8 | trophy_not_ready |
| 46 | 15 | 11 | 0 | trophy_not_ready |
| 50 | 3 | 1 | 0 | ranking_active |
| 15 | 3 | 7 | 1 | ranking_active |
| 41 | 15 | 11 | 1 | trophy_not_ready |
| 30 | 4 | 2 | 0 | ranking_active |

Se recomienda añadir `territory_award_readiness` como estado separado: `ranking_active`, `trophy_not_ready`, `trophy_ready`. No se fija todavía un número global de equipos; la condición decisiva es disponer de al menos diez candidatos legítimos certificables y suficientes conexiones independientes observadas.

## Decisión

| Contrato | Decisión | Motivo |
| --- | --- | --- |
| Season Score formula | KEEP | 55/30/15 y recent_30 no intervienen en el defecto. |
| Ranking eligibility | KEEP | 15 evidencias, 6 rivales, reliability 0,45 y actividad siguen separando acceso al ranking. |
| 25/10 | KEEP | Rebajar a 20/8 no resolvió el cuello y 10 equipos no ofrecen diez rivales posibles. |
| Match confidence | KEEP | Sigue siendo una protección absoluta útil. |
| Logical opponents | KEEP | El colapso owner/admin/plantilla detecta fake teams. |
| Network diversity | KEEP EN PRODUCTO, CHANGE EN INVESTIGACIÓN | El 0,68 es defectuoso en redes pequeñas, pero ningún modelo demuestra aún una sustitución segura en V1. |
| Certification hold | KEEP EN PRODUCTO, CHANGE EN INVESTIGACIÓN | El laboratorio no alcanza todavía el objetivo de falso positivo en V1. |
| Territory award readiness | ADD | Permite ranking provisional sin degradar antifraude para entregar premio. |

## Decisión V3.1

**Candidato aceptado: ninguno.** El Modelo 3 queda solo como referencia de investigación: contextualiza oportunidad y mantiene señales absolutas, pero V1 todavía supera el 2% de falso positivo y no ofrece suficientes abusos ejecutados que pasen los demás gates para demostrar recall >=90%. No se propone cambio de producto ni se reduce el umbral absoluto por ajuste al resultado.

## Incidencias y pruebas

- `SW-0068` a `SW-0074`: registradas antes de cada corrección; el cierre final conserva regresiones específicas.
- Multi-seed: 30 semillas por tamaño y escenario.
- Clones: M0-M5 sobre V1; original no guardado.
- Dashboard: Network Health admin/laboratorio, no público.
- Resultados completos: `simulation/synthetic-world/exports/network-diversity-v3.1-full.json`.
