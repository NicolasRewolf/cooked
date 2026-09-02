-- E1 — mesurer l'exposition zero-clic des SERP qui portent notre trafic.
--
-- Constat du 27/07/2026 : GSC annonce une position dans le BLOC ORGANIQUE et
-- ignore tout ce qui le precede (AI Overview, People Also Ask, Knowledge
-- Graph, Local Pack).
--
-- PERIMETRE — la traine des requetes est trop longue pour une mesure
-- exhaustive : le top 100 ne couvre que 48 % des impressions non brandees,
-- le top 20 seulement 28,6 %. On ne cherche donc pas la couverture mais la
-- TENDANCE : un panel fixe, remesure periodiquement, dit si le plancher
-- zero-clic descend. Changer le panel casse la comparabilite.
--
-- Une ligne = une requete x un jour de mesure. Le releve se fait via
-- DataForSEO SERP Google Organic Live Advanced (device mobile, France) :
-- l'appel coute des credits, d'ou une table plutot qu'un calcul a la volee.
--
-- Premier releve du 28/07/2026, 4 requetes. Le resultat le plus fort n'est
-- PAS celui attendu : sur « surveillance electronique » — plus grosse requete
-- du site avec 10 394 impressions pour 5 clics — GSC annonce position 7
-- organique, le visiteur nous voit en position absolue 19, sous un Knowledge
-- Graph, un PAA, 3 organiques, un carrousel d'annuaires et SIX entrees de
-- Local Pack qui sont des magasins de cameras de videosurveillance. Ce n'est
-- pas du zero-clic : c'est une requete dont l'intention dominante n'a rien a
-- voir avec le droit penal.

CREATE TABLE IF NOT EXISTS public.serp_features (
  day                      date        NOT NULL DEFAULT public.paris_today(),
  query                    text        NOT NULL,
  device                   text        NOT NULL DEFAULT 'mobile',
  location_name            text        NOT NULL DEFAULT 'France',

  has_ai_overview          boolean     NOT NULL DEFAULT false,
  has_people_also_ask      boolean     NOT NULL DEFAULT false,
  has_local_pack           boolean     NOT NULL DEFAULT false,
  has_knowledge_graph      boolean     NOT NULL DEFAULT false,

  first_organic_absolute   integer,
  our_rank_absolute        integer,
  our_rank_organic         integer,

  gsc_impressions_28j      integer,
  gsc_clicks_28j           integer,

  measured_at              timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (day, query, device, location_name)
);

COMMENT ON TABLE public.serp_features IS
  'Exposition zero-clic : ce qui s intercale entre le visiteur et notre '
  'resultat organique. Panel FIXE de requetes remesure periodiquement — on '
  'cherche la tendance, pas la couverture (le top 100 des requetes ne pese '
  'que 48 % des impressions). Renseigne par releve DataForSEO SERP Live '
  'Advanced, device mobile / France. Changer le panel casse la comparabilite.';

COMMENT ON COLUMN public.serp_features.our_rank_absolute IS
  'Rang tel que le visiteur le voit, AI Overview et PAA compris. A comparer a '
  'our_rank_organic (ce que GSC rapporte) : l ecart est la mesure du biais.';

COMMENT ON COLUMN public.serp_features.first_organic_absolute IS
  'Position absolue du premier resultat organique, tous domaines confondus. '
  '1 = SERP saine ; 3 ou plus = le bloc organique est repousse sous un AI '
  'Overview, un PAA ou un Local Pack.';
