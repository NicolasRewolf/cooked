import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

export const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');

// Synthetic catalogue only: no connection string, external data or network.
export async function createDatabase({rpcMirror = process.env.SQL_RPC_MIRROR} = {}) {
  const {PGlite} = await import(process.env.PGLITE_MODULE ?? '@electric-sql/pglite');
  const db = new PGlite();
  try {
    await db.exec(`CREATE ROLE anon; CREATE ROLE authenticated;
      CREATE ROLE service_role BYPASSRLS; CREATE ROLE cooked_ci_ro;
      SET check_function_bodies=false;`);
    const fixture = JSON.parse(fs.readFileSync(root + '/tests/sql/fixtures/catalog-20261104-core.json', 'utf8'));
    for (const relation of fixture.tables) {
      await db.exec(`CREATE TABLE public.${relation.name} (${relation.columns});`);
      for (const constraint of relation.constraints) {
        await db.exec(`ALTER TABLE public.${relation.name} ADD CONSTRAINT ${constraint.name} ${constraint.definition};`);
      }
      if (relation.rls) await db.exec(`ALTER TABLE public.${relation.name} ENABLE ROW LEVEL SECURITY;`);
      if (relation.rls_force) await db.exec(`ALTER TABLE public.${relation.name} FORCE ROW LEVEL SECURITY;`);
    }
    const source = fs.readFileSync(rpcMirror ?? root + '/supabase/rpcs.sql', 'utf8');
    for (const chunk of source.split(/\n-- ═══ /).slice(1)) {
      const start = chunk.indexOf('CREATE OR REPLACE');
      if (start < 0) continue;
      const ddl = chunk.slice(start).trim();
      if (/FUNCTION public.unaccent/.test(ddl)) continue;
      await db.exec(ddl + ';');
    }
    for (const view of fixture.views) await db.exec(view.ddl);
    // Reproduce effective client/service grants from the metadata snapshot.
    // No production role, secret, extension or connection is used here.
    await db.exec('REVOKE ALL ON ALL ROUTINES IN SCHEMA public FROM PUBLIC,anon,authenticated,service_role;');
    for (const routine of fixture.routine_acl) {
      if (!(await db.query("SELECT 1 FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname=$1", [routine.name])).rows.length) continue;
      const roles = [['anon', routine.anon_exec], ['authenticated', routine.auth_exec], ['service_role', routine.service_exec]]
        .filter(([, allowed]) => allowed).map(([role]) => role);
      if (roles.length) await db.exec(`GRANT EXECUTE ON ROUTINE public.${routine.name}(${routine.args}) TO ${roles.join(',')};`);
    }
    await db.exec('GRANT ALL ON ALL TABLES IN SCHEMA public TO service_role;');
    return db;
  } catch (error) {
    await db.close();
    throw error;
  }
}

export async function applyMigration(db, suffix) {
  const directory = root + '/supabase/migrations';
  const names = fs.readdirSync(directory).filter(name => name.endsWith(suffix));
  if (names.length !== 1) throw new Error(`Expected one migration ending ${suffix}, found ${names.length}`);
  await db.exec(fs.readFileSync(path.join(directory, names[0]), 'utf8'));
}
