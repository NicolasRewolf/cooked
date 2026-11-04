# Cooked — vocabulaire du socle éditorial

Référence du **04/11/2026**. Le produit mesure l’audience et les contacts observés des pages du site. Les choix de sujets et d’actions éditoriales restent ceux de Nicolas. Les anciennes notions CPI, CRM et snapshots sont documentées dans les archives, pas dans le contrat courant.

## Pages et sources

**Page publiée** : URL présente dans le dernier inventaire Wix complet. `page_taxonomy.is_published` porte ce statut ; `publication_checked_at` date sa vérification, pas sa publication initiale. Le référentiel inclut les articles, pages statiques et catégories, indépendamment du trafic. Une URL absente de l’inventaire reste connue avec un statut non publié.

**Chemin canonique** : chemin partagé entre Wix, GSC et Cooked, décodé, normalisé Unicode NFC et sans slash final sauf `/`. Un changement de cette règle doit rester identique en SQL, Edge et Python.

**Événement observable** : action reçue par Cooked. L’absence d’événement ne prouve pas l’absence d’activité réelle. `events_human` applique les filtres communs du site principal ; `events` brut sert au diagnostic explicite du système.

## Visites et entrées

**Visite observée** : activité d’un même navigateur rapprochée par `identity_stitch`, coupée lorsqu’un écart dépasse 30 minutes. `web_vitals` ne prolonge pas cette activité. La couture est reconstruite sur l’historique conservé, jusqu’à convergence, sans utiliser les identifiants serveur de repli 32-hex pour rapprocher des navigateurs. Une identité technique ne prouve pas une personne unique.

**Entrée** : première page vue de cette visite. Elle peut précéder la période d’extraction d’un contact. Une page postérieure au contact ne fait jamais partie de son amont. Le comptage commun vient de `cooked_visit_events(début, fin)`.

**Visite d’une page** : visite ayant au moins une page vue sur cette page dans la fenêtre. Plusieurs consultations dans une visite comptent une fois. Les visites distinctes par page ne s’additionnent pas en visiteurs uniques du site.

**Cohorte d’entrée** : visites dont l’entrée appartient à la période. `page_visits(début, fin)` compte leurs contacts observés avant la clôture de cette période. Les visites commencées avant ne grossissent pas son dénominateur.

## Contacts

**Contact observé** : clic téléphone (`cta_phone_click`) ou formulaire éligible (`form_submit`, `counts_as_macro`). Un clic ne prouve pas un appel abouti ; une soumission ne prouve pas un prospect unique, un rendez-vous ou un dossier signé.

**Candidature** : formulaire dont l’objet relève de « nous rejoindre », exclu des contacts métier. La règle partagée est testée par `recruitment_objet_vectors.json`.

**Intention** : clic de prise de rendez-vous (`cta_booking_click`). Ce n’est pas un contact. Les signaux de lecture, scroll et performance ne sont pas non plus des contacts.

**Visite ayant contacté** : visite de la cohorte ayant produit au moins une action éligible. `phone_visits`, `form_visits` et `contact_visits` sont respectivement le téléphone, le formulaire et leur union. Une visite ayant fait les deux ne compte qu’une fois dans l’union. Le taux est l’union divisée par les entrées, en pourcentage ; sans entrée, il est inconnu (`NULL`). Présenter aussi les deux nombres et leurs dénominateurs.

**Contact sur une page** et **contact attribué à une entrée** : le premier décrit le lieu de l’action, le second la première page de la visite. Ils ne s’additionnent pas et ne portent jamais un libellé ambigu commun.

**Contact non attribué** : événement éligible sans visite certaine. Un formulaire doit porter des identifiants explicites pour être rapproché ; la proximité temporelle seule ne suffit pas. Ces contacts restent conservés et comptés dans le total des événements du site. Ils ne sont pas forcés dans le taux d’une page.

## Périodes, zéros et Google

**Période Cooked** : jours Paris clos, bornes inclusives dans les fonctions à dates. La comparaison envisagée est de 90 jours aux 90 précédents, modifiable. Une période partielle doit être affichée comme telle ; pas de delta de performance présenté comme complet.

**Couverture** : disponibilité des données nécessaires au calcul. La ligne `coverage` de `page_visits` donne les jours avec au moins une page vue et les événements téléphone/formulaire non attribués. Elle ne prouve pas la disponibilité à chaque minute. La couverture des identifiants de formulaires a évolué dans l’historique.

**Zéro visite** : absence de visite mesurée pour une page publiée dans une fenêtre dont la couverture a été examinée. Une panne, un import incomplet ou une absence de source donnent un résultat inconnu ou partiel, pas un zéro certain.

**Total Google par page** : `gsc_path_daily`, incluant les clics dont la requête est masquée. **Requêtes révélées d’une page** : `gsc_query_page_daily`. Ces grains ne sont pas interchangeables. Les dates GSC restent celles de Google ; le dernier jour disponible peut différer de celui du tracker.

**Position moyenne** : moyenne pondérée par les impressions, jamais moyenne simple des positions quotidiennes. Une requête absente peut être masquée ou sans observation. Les clics GSC ne sont pas des visites Cooked et ne se relient pas individuellement aux formulaires.

## Santé et limites

**Fraîcheur** : âge de la dernière donnée source. **Complétude d’un lot** : les deux grains attendus par l’import GSC ont réussi ; `gsc_ingest_batches` distingue les lots complets, en cours ou échoués. Un lot complet ne restitue pas les requêtes masquées par Google.

**Alerte** : résultat d’un contrôle à une date donnée. Un acquittement signifie « examiné » et ne démontre pas la réparation. La santé doit être lue avec les dates et la source affectée, sans acquittement global.

Toute recommandation s’appuie sur des chiffres contre-vérifiés et leurs limites. Les faibles volumes rendent les taux instables. Une corrélation, une baisse de clics ou une position moyenne ne suffisent pas à expliquer seuls la performance éditoriale.

Les événements de lecture et Web Vitals restent dans la collecte. La profondeur vient de `page_exit.max_scroll`. Les Web Vitals sont au grain document : les révisions d’un même document et d’une même métrique ne sont pas des mesures indépendantes. Aucun agrégat Web Vitals n’est actif ; ces événements n’alimentent plus un score CPI.

[Guide d’analyse](docs/PLAYBOOK-analyse-seo.md) · [Exploitation](docs/OPERATIONS.md) · [Règles agent](CLAUDE.md) · [Archives](docs/README.md)
