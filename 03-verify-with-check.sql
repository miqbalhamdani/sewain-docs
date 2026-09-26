-- Bukti sekali-jalan bahwa WITH CHECK di enable_owner_rls (03-erd.md §3) menutup
-- lubang yang nyata, bukan menambah baris yang kebetulan lulus.
--
-- Dua paruh, kebalikan satu sama lain:
--   A. policy USING saja      -> menulis baris pemilik lain BERHASIL  (lubangnya)
--   B. policy USING + CHECK   -> menulis baris pemilik lain DITOLAK   (tambalannya)
--
-- Kalau paruh A ikut menolak, berarti kasus RLS 5/5 di 03-verify-constraints.sql
-- lulus karena sebab lain dan tidak membuktikan apa pun.
--
-- Jalankan di database scratch; diakhiri ROLLBACK.

BEGIN;

CREATE TABLE probe_a (id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
                      owner_id uuid NOT NULL, label text NOT NULL);
CREATE TABLE probe_b (LIKE probe_a INCLUDING ALL);

-- A: persis policy LAMA -- USING saja
ALTER TABLE probe_a ENABLE ROW LEVEL SECURITY;
ALTER TABLE probe_a FORCE  ROW LEVEL SECURITY;
CREATE POLICY owner_isolation ON probe_a
  USING (owner_id = NULLIF(current_setting('app.owner_id', true), '')::uuid);

-- B: policy BARU -- USING + WITH CHECK
ALTER TABLE probe_b ENABLE ROW LEVEL SECURITY;
ALTER TABLE probe_b FORCE  ROW LEVEL SECURITY;
CREATE POLICY owner_isolation ON probe_b
  USING      (owner_id = NULLIF(current_setting('app.owner_id', true), '')::uuid)
  WITH CHECK (owner_id = NULLIF(current_setting('app.owner_id', true), '')::uuid);

CREATE ROLE wc_probe_role NOLOGIN;
GRANT USAGE ON SCHEMA public TO wc_probe_role;
GRANT SELECT, INSERT ON probe_a, probe_b TO wc_probe_role;

DO $$
DECLARE
  o1 uuid := '11111111-1111-1111-1111-111111111111';
  o2 uuid := '22222222-2222-2222-2222-222222222222';
  bocor bool := false;
  c int;
BEGIN
  PERFORM set_config('app.owner_id', o1::text, true);

  -- A -- diharapkan LOLOS, karena USING tidak diterapkan pada INSERT
  BEGIN
    EXECUTE 'SET LOCAL ROLE wc_probe_role';
    EXECUTE format('INSERT INTO probe_a (owner_id, label) VALUES (%L, %L)', o2, 'selundupan');
    EXECUTE 'RESET ROLE';
    bocor := true;
  EXCEPTION WHEN insufficient_privilege THEN
    EXECUTE 'RESET ROLE';
    bocor := false;
  END;

  IF NOT bocor THEN
    RAISE EXCEPTION
      'TIDAK KONKLUSIF: USING-saja ikut menolak INSERT. Kasus RLS 5/5 lulus karena sebab lain.';
  END IF;

  SELECT count(*) INTO c FROM probe_a WHERE owner_id = o2;
  RAISE NOTICE 'A - USING saja: INSERT owner asing BERHASIL, % baris tertanam. Ini lubangnya.', c;

  -- ...dan si penulis tidak bisa melihat apa yang baru saja ia tulis
  EXECUTE 'SET LOCAL ROLE wc_probe_role';
  SELECT count(*) INTO c FROM probe_a;
  EXECUTE 'RESET ROLE';
  RAISE NOTICE 'A - penulisnya sendiri melihat % baris. Datanya ada; yang hilang cuma errornya.', c;

  -- B -- diharapkan DITOLAK
  BEGIN
    EXECUTE 'SET LOCAL ROLE wc_probe_role';
    EXECUTE format('INSERT INTO probe_b (owner_id, label) VALUES (%L, %L)', o2, 'selundupan');
    EXECUTE 'RESET ROLE';
    RAISE EXCEPTION 'GAGAL: WITH CHECK terpasang tapi INSERT owner asing tetap diterima';
  EXCEPTION WHEN insufficient_privilege THEN
    EXECUTE 'RESET ROLE';
    RAISE NOTICE 'B - USING + WITH CHECK: INSERT owner asing DITOLAK. Tambalannya bekerja.';
  END;

  RAISE NOTICE '--- WITH CHECK terbukti memikul beban: A bocor, B tidak ---';
END $$;

ROLLBACK;
