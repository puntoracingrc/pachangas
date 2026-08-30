# Synthetic Season Timeline V1

La temporada usa nueve checkpoints inmutables. `capturedAt`, rutas locales e
IDs temporales no participan en los hashes semanticos.

| Checkpoint | Semana | Estado | Public snapshot hash |
| ---: | ---: | --- | --- |
| 0 | 0 | Pretemporada: solicitudes, Clubs, Teams y drafts | `d8f5363168af3927c5fa79b99b758bf13236a079c371f3ce11d4f8ff20f1fd1b` |
| 1 | 1 | Inscripciones: aceptacion, rechazo, retirada, waitlist y rosters | `fc644e97fc2088baf18228834ffdd47920baea6f158cc1c6031a38cd33fe8870` |
| 2 | 3 | Planificacion: RuleRevision, sorteo, calendario y arbitros | `ac2b43990be08146bdda5588963f5695314db941dc2ee3a9625f6f922188f146` |
| 3 | 4 | Inicio: asistencia, resultados y primera clasificacion | `4a0f6fce0edbfbc05ff3372998a269afea8897b8a07abd119ae5e12335168ad6` |
| 4 | 8 | Mitad: sanciones, aplazamiento, owner transfer y SOCIAL_ONLY | `5cdedf59b5f0ccee670dff22bb36a1fb9d2f94acaf6f955722cf2f08d4db0a53` |
| 5 | 12 | Recta final: incidencias, correcciones y sanciones pendientes | `c472cd5405b40686f19817ccb8f20b6993dc37cdd7442ad2c3aab59386655766` |
| 6 | 13 | Clasificacion: grupos, QualificationSnapshot y cuadro | `474e729ea2276e8a339990e1761d912348a48ccd02abb84507b0e0313268d6df` |
| 7 | 15 | Finales: eliminatorias, prorroga, penaltis y campeones | `4c549d5d9f57a892e9eb589d3217387d232610f5f43511e7b973b4305b85c3d9` |
| 8 | 16 | Postemporada: standings finales, sanciones cumplidas e historia | `0c425488be8541ce7a4ad326d5d32f867f7e33da4582783f9e5172a05aa3b799` |

`synthetic-season:checkpoint -- --week=8` selecciona inequivocamente el
checkpoint 4. El replay completo reproduce los nueve hashes, el authority hash
`763c8c70cafde739c308a91668f5ca8b9ed6d6b2036935aa4ac1c65e49a8bab1`
y el public snapshot hash
`48b9bb09baa2e536708ec7c13109a716f81b128ba838a1ba29412d22b252358b`.
