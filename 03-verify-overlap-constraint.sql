-- Verifikasi constraint anti-bentrok (BR-022).
-- Jalankan di database KOSONG / scratch:
--   createdb sewain_scratch && psql sewain_scratch -f 03-verify-overlap-constraint.sql
-- Harapan: 6 baris NOTICE "OK", tanpa ERROR yang tidak tertangkap.
-- Script diakhiri ROLLBACK, jadi tidak meninggalkan apa pun.

BEGIN;

CREATE EXTENSION IF NOT EXISTS btree_gist;

CREATE TABLE bookings (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  resource_unit_id    uuid NOT NULL,
  start_at            timestamptz NOT NULL,
  end_at              timestamptz NOT NULL,
  buffer_minutes      int NOT NULL DEFAULT 0,
  end_at_with_buffer  timestamptz NOT NULL,   -- diisi trigger, bukan aplikasi
  status              text NOT NULL,
  deleted_at          timestamptz,
  CHECK (end_at > start_at),
  CHECK (end_at_with_buffer >= end_at)
);

-- KENAPA TRIGGER, BUKAN KOLOM GENERATED — jangan "optimasi" balik.
-- GENERATED ALWAYS AS (end_at + make_interval(...)) STORED DITOLAK PostgreSQL:
--   ERROR: generation expression is not immutable
-- Operator timestamptz + interval ditandai STABLE, bukan IMMUTABLE, karena
-- menambah interval berhari/berbulan ke timestamptz hasilnya tergantung TimeZone
-- sesi saat melewati batas DST. Volatilitas ditandai per-fungsi, jadi tidak
-- menolong bahwa make_interval(mins => ...) kita selalu bebas-DST.
-- Terverifikasi pada PostgreSQL sungguhan, 2026-09-10.
CREATE OR REPLACE FUNCTION bookings_fill_end_at_with_buffer()
RETURNS trigger LANGUAGE plpgsql AS $fn$
BEGIN
  NEW.end_at_with_buffer := NEW.end_at + make_interval(mins => NEW.buffer_minutes);
  RETURN NEW;
END $fn$;

-- Tanpa daftar kolom, dan BEFORE UPDATE juga: trigger SELALU menimpa, jadi
-- aplikasi tidak bisa menyetel nilainya sendiri walau mengirimnya.
CREATE TRIGGER bookings_end_at_with_buffer
  BEFORE INSERT OR UPDATE ON bookings
  FOR EACH ROW EXECUTE FUNCTION bookings_fill_end_at_with_buffer();

ALTER TABLE bookings
  ADD CONSTRAINT bookings_no_overlap
  EXCLUDE USING gist (
    resource_unit_id WITH =,
    tstzrange(start_at, end_at_with_buffer, '[)') WITH &&
  )
  WHERE (status IN ('reserved', 'picked_up') AND deleted_at IS NULL);

DO $$
DECLARE
  unit_a uuid := '11111111-1111-1111-1111-111111111111';
  unit_b uuid := '22222222-2222-2222-2222-222222222222';
BEGIN
  -- Dasar: booking 3-5 Sep pada unit A
  INSERT INTO bookings (resource_unit_id, start_at, end_at, status)
  VALUES (unit_a, '2026-09-03 09:00+07', '2026-09-05 09:00+07', 'reserved');

  -- 1. Bentrok harus DITOLAK: 4-6 Sep beririsan dengan 3-5 Sep
  BEGIN
    INSERT INTO bookings (resource_unit_id, start_at, end_at, status)
    VALUES (unit_a, '2026-09-04 09:00+07', '2026-09-06 09:00+07', 'reserved');
    RAISE EXCEPTION 'GAGAL: booking bentrok diterima, seharusnya ditolak';
  EXCEPTION WHEN exclusion_violation THEN
    RAISE NOTICE 'OK 1/6 - booking bentrok ditolak';
  END;

  -- 2. Batas [) : mulai persis saat yang lain selesai harus DITERIMA
  INSERT INTO bookings (resource_unit_id, start_at, end_at, status)
  VALUES (unit_a, '2026-09-05 09:00+07', '2026-09-07 09:00+07', 'reserved');
  RAISE NOTICE 'OK 2/6 - batas awal-inklusif/akhir-eksklusif tidak dianggap bentrok';

  -- 3. Status yang tidak mengunci (draft) boleh menumpuk
  INSERT INTO bookings (resource_unit_id, start_at, end_at, status)
  VALUES (unit_a, '2026-09-03 09:00+07', '2026-09-05 09:00+07', 'draft');
  RAISE NOTICE 'OK 3/6 - draft tidak mengunci unit';

  -- 4. Buffer benar-benar memblokir: unit B selesai 10:00 + buffer 120m -> 12:00
  INSERT INTO bookings (resource_unit_id, start_at, end_at, buffer_minutes, status)
  VALUES (unit_b, '2026-09-10 08:00+07', '2026-09-10 10:00+07', 120, 'reserved');
  BEGIN
    INSERT INTO bookings (resource_unit_id, start_at, end_at, status)
    VALUES (unit_b, '2026-09-10 11:00+07', '2026-09-10 13:00+07', 'reserved');
    RAISE EXCEPTION 'GAGAL: booking di dalam jeda buffer diterima';
  EXCEPTION WHEN exclusion_violation THEN
    RAISE NOTICE 'OK 4/6 - buffer memblokir booking jam 11:00';
  END;

  -- 5. Setelah buffer lewat (12:00) harus diterima
  INSERT INTO bookings (resource_unit_id, start_at, end_at, status)
  VALUES (unit_b, '2026-09-10 12:00+07', '2026-09-10 14:00+07', 'reserved');
  RAISE NOTICE 'OK 5/6 - booking setelah buffer berakhir diterima';

  -- 6. Aplikasi TIDAK BISA menyetel end_at_with_buffer sendiri: trigger menimpa.
  --    Ini yang dulu dijamin kolom generated; sekarang dijamin trigger.
  INSERT INTO bookings (resource_unit_id, start_at, end_at, buffer_minutes,
                        end_at_with_buffer, status)
  VALUES (unit_b, '2026-09-20 08:00+07', '2026-09-20 10:00+07', 120,
          '2000-01-01 00:00+07',            -- nilai ngawur dari "aplikasi"
          'reserved');
  IF (SELECT end_at_with_buffer FROM bookings
      WHERE start_at = '2026-09-20 08:00+07')
     <> '2026-09-20 12:00+07'::timestamptz THEN
    RAISE EXCEPTION 'GAGAL: nilai kiriman aplikasi tidak ditimpa trigger';
  END IF;
  RAISE NOTICE 'OK 6/6 - nilai kiriman aplikasi ditimpa trigger';
END $$;

ROLLBACK;
