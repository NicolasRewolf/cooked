-- C3 (09/07/2026) — canonical_path unifié : decode → NFC → strip slash.
-- Aligne SQL sur Edge (_shared/canonical_path.ts) et scripts/gsc_common.py.
-- Contrat : contracts/canonical_path_vectors.json (CI Python + Deno + scripts/canonical_path_contract.sql).

-- Miroir prod (absent du repo jusqu'ici) — requis pour canonical_path(url_decode(...)).
CREATE OR REPLACE FUNCTION public.url_decode(input text)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare
  result        text  := '';
  i             int   := 1;
  len           int   := length(input);
  pending       bytea := ''::bytea;
  hex_pair      text;
begin
  if input is null then
    return null;
  end if;

  while i <= len loop
    if substring(input from i for 1) = '%'
       and i + 2 <= len
       and substring(input from i+1 for 2) ~ '^[0-9A-Fa-f]{2}$'
    then
      hex_pair := substring(input from i+1 for 2);
      pending  := pending || decode(hex_pair, 'hex');
      i := i + 3;
    else
      if length(pending) > 0 then
        result  := result || convert_from(pending, 'UTF8');
        pending := ''::bytea;
      end if;
      result := result || substring(input from i for 1);
      i := i + 1;
    end if;
  end loop;

  if length(pending) > 0 then
    result := result || convert_from(pending, 'UTF8');
  end if;

  return result;
exception
  when others then
    return input;
end;
$function$;

CREATE OR REPLACE FUNCTION public.canonical_path(p text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $function$
  SELECT CASE
    WHEN char_length(n) > 1 AND right(n, 1) = '/' THEN left(n, char_length(n) - 1)
    ELSE COALESCE(NULLIF(n, ''), '/')
  END
  FROM (
    SELECT normalize(public.url_decode(COALESCE(p, '')), NFC) AS n
  ) AS s;
$function$;

COMMENT ON FUNCTION public.canonical_path(text) IS
  'C3 — Jointure Cooked × GSC : url_decode → NFC → strip trailing slash (sauf /). Contrat partagé Edge/Python/SQL.';
