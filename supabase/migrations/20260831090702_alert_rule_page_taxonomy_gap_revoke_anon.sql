-- Correctif advisors 0028/0029 introduits par 20260831090540.
-- `revoke all ... from public` ne retire pas les EXECUTE accordés directement aux rôles
-- anon / authenticated par le default privilege Supabase : la fonction restait appelable
-- via /rest/v1/rpc/. Alignement sur la convention des autres règles d'alerte, dont l'ACL
-- est exactement `postgres=X | service_role=X`.
revoke execute on function public.alert_rule_page_taxonomy_gap() from anon, authenticated;
