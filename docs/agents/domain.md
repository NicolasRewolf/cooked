# Documentation de domaine

Avant d’explorer Cooked, lire [CONTEXT.md](../../CONTEXT.md) pour le vocabulaire et [SIMPLIFICATION.md](../SIMPLIFICATION.md) pour le périmètre du 04/11/2026. [CLAUDE.md](../../CLAUDE.md) porte l’autonomie, les règles d’analyse et les invariants techniques.

Les concepts actifs sont : page publiée, événement, visite observée, entrée, cohorte d’entrée, clic téléphone, formulaire éligible, visite ayant contacté, contact non attribué et couverture. Ne pas les remplacer par « prospect », « client » ou « session » brute sans preuve correspondante.

Le téléphone et le formulaire se recouvrent au grain des visites ; leur union n’est pas leur somme. Un clic de rendez-vous est une intention. Google par page et Google par requête × page sont deux grains distincts ; aucune attribution individuelle requête → formulaire n’est établie.

Les anciens termes CPI, CRM, modèles mathématiques et snapshots appartiennent aux archives. Leur existence historique ne justifie pas de réintroduire le module ou de créer un nouveau score dans le socle.

Lire les [ADR](../adr/) pertinents avant de changer une règle commune. Signaler une contradiction avec une décision existante et sa conséquence concrète. Une lacune de vocabulaire ne justifie pas, à elle seule, l’ajout d’un document, d’un processus ou d’une couche logicielle.
