-- T-08 (mission 02/09/2026, #109) — invariant I10 : restatement = annotation.
INSERT INTO public.annotations (day, kind, label, paths)
VALUES (
  DATE '2026-09-03',
  'autre',
  'Restatement T-08 (03/09/2026) : les formulaires sans identifiant sont désormais comptés à part. assisted_contacts_by_entry_path excluait les form_submit sans cooked_sid/cooked_aid et jetait tout contact sans visite appariée (JOIN LATERAL interne). Mesure 03/09, fenêtre 06/08→02/09 : 179 assistés vs 191 totaux site ; après : 191 = 191, dont 12 sur la ligne (non attribuable). Le total site ne change pas. Ces 12 n''entrent pas dans le compteur « Contacts nourris par les articles » (ressources seulement, snapshot T3 2026 = 94 du 01/07 au 02/09). dashboard_assisted_quarter lit un snapshot nocturne (3 ms) au lieu de recalculer le trimestre à l''affichage (timeout 30 s, ligne masquée). Pas d''objectif trimestriel (décision Nicolas 03/09). Correction de mesure, pas un changement de trafic.',
  NULL
);
