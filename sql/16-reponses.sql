-- ============================================================
-- Migration 16 — pouvoir effacer sa propre réponse
-- À coller et Run SEUL dans le SQL Editor.
--
-- Les réponses ne pouvaient qu'être écrites, jamais retirées : quelqu'un
-- qui poste une bêtise n'avait aucun moyen de revenir dessus, et il
-- fallait passer par la base pour le faire à sa place.
--
-- On reste volontairement sur un seul niveau de réponse. Imbriquer des
-- réponses de réponses devient illisible sur un téléphone, et à l'échelle
-- d'un groupe d'amis ça n'apporte rien : on s'adresse à quelqu'un en le
-- nommant, pas en creusant un niveau de plus.
-- ============================================================

drop policy if exists y_delete on replies;
create policy y_delete on replies for delete to authenticated
  using (user_id = auth.uid());

-- l'auteur d'un avis peut aussi retirer une réponse sous son propre avis,
-- comme il peut supprimer l'avis entier
drop policy if exists y_delete_hote on replies;
create policy y_delete_hote on replies for delete to authenticated
  using (review_id in (select id from reviews where user_id = auth.uid()));

-- tri chronologique : c'est l'ordre dans lequel on lit une conversation
create index if not exists replies_ordre_idx on replies (review_id, created_at);
