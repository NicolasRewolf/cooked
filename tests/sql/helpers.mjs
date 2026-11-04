import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

export const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');

// Synthetic catalogue only: no connection string, external data or network.
export async function createDatabase() {
  const {PGlite} = await import(process.env.PGLITE_MODULE ?? '@electric-sql/pglite');
  const db = new PGlite();
  try {
    await db.exec(`CREATE ROLE anon; CREATE ROLE authenticated;
      CREATE ROLE service_role BYPASSRLS; CREATE ROLE cooked_ci_ro;
      SET check_function_bodies=false;`);
    const relations = JSON.parse(fs.readFileSync(root + '/tests/sql/fixtures/catalog-20261020.json', 'utf8'));
    const eventViews = ['events_human', 'events_main', 'events_no_bots', 'events_human_outremer', 'events_outremer'];
    for (const relation of relations.filter(r => !eventViews.includes(r.name))) {
      await db.exec(`CREATE TABLE public.${relation.name} (${relation.columns});`);
    }
    await db.exec(`ALTER TABLE events ALTER id SET DEFAULT gen_random_uuid();
      ALTER TABLE cooked_config ADD PRIMARY KEY(key);
      ALTER TABLE noise_sessions ADD PRIMARY KEY(session_id);
      ALTER TABLE bot_fingerprints ADD PRIMARY KEY(anonymous_id);
      ALTER TABLE identity_stitch ADD PRIMARY KEY(kind,key);
      ALTER TABLE page_taxonomy ADD PRIMARY KEY(path);
      ALTER TABLE cpi_daily ADD PRIMARY KEY(day,path);
      ALTER TABLE dashboard_assisted_quarter_snapshot ADD PRIMARY KEY(quarter);
      CREATE VIEW events_main AS SELECT * FROM events;
      CREATE VIEW events_outremer AS SELECT * FROM events WHERE false;
      CREATE VIEW events_human AS SELECT * FROM events e
        WHERE NOT EXISTS(SELECT 1 FROM noise_sessions n WHERE n.session_id=e.session_id)
          AND NOT EXISTS(SELECT 1 FROM bot_fingerprints b WHERE b.anonymous_id=e.anonymous_id);
      CREATE VIEW events_no_bots AS SELECT * FROM events;
      CREATE VIEW events_human_outremer AS SELECT * FROM events WHERE false;
      INSERT INTO cooked_config(key,value) VALUES('cpi_definition_version','2.2.5');`);
    // Le préambule crée seulement la table des lots. Rejouer toute l’ancienne
    // migration après le miroir écraserait les définitions courantes.
    const batchMigration = fs.readdirSync(root + '/supabase/migrations')
      .find(name => name.endsWith('_audit_data_integrity_and_ingest_completion.sql'));
    const batchSchema = fs.readFileSync(root + '/supabase/migrations/' + batchMigration, 'utf8')
      .split('CREATE OR REPLACE FUNCTION')[0].replace(/\bBEGIN;/, '');
    await db.exec(batchSchema);
    const source = fs.readFileSync(process.env.SQL_RPC_MIRROR ?? root + '/supabase/rpcs.sql', 'utf8');
    for (const chunk of source.split(/\n-- ═══ /).slice(1)) {
      const start = chunk.indexOf('CREATE OR REPLACE');
      if (start < 0) continue;
      const ddl = chunk.slice(start).trim();
      if (/FUNCTION public.unaccent/.test(ddl)) continue;
      await db.exec(ddl + ';');
    }
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
