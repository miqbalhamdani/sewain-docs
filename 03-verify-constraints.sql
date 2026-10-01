-- Verifikasi 53 constraint sisa di 03-erd.md §3.
-- Anti-bentrok (BR-022) TIDAK di sini — ia punya file sendiri:
--   03-verify-overlap-constraint.sql
--
-- Jalankan di database KOSONG / scratch:
--   createdb sewain_scratch && psql sewain_scratch -f docs/03-verify-constraints.sql
-- Harapan: 57 NOTICE "OK" constraint + 6 NOTICE "OK RLS", tanpa ERROR yang
-- tidak tertangkap.
-- Script diakhiri ROLLBACK, jadi tidak meninggalkan apa pun.
--
-- Tabel di bawah SENGAJA minimal: hanya kolom yang disentuh constraint. Ia bukan
-- skema sebenarnya, ia harness. Kalau constraint di 03-erd.md §3 berubah, ubah juga
-- di sini — CI menjalankan keduanya (S1-069).

BEGIN;

CREATE EXTENSION IF NOT EXISTS btree_gist;

-- ─────────────────────────── tabel harness ───────────────────────────

CREATE TABLE owners (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug                text,                                 -- BR-025: NULL = tanpa halaman
  booking_code_prefix text NOT NULL DEFAULT 'SWN',            -- BR-024
  business_type       text NOT NULL DEFAULT 'vehicle_rental',  -- BR-017
  payment_due_hours       int NOT NULL DEFAULT 24,               -- BR-057
  no_show_tolerance_hours int NOT NULL DEFAULT 3,   -- BR-057
  whatsapp                text                     -- BR-096
);

CREATE TABLE users (
  id       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL REFERENCES owners(id),
  email    text NOT NULL,
  role     text NOT NULL DEFAULT 'operator',
  status   text NOT NULL DEFAULT 'active'
);

-- resource_id SENGAJA nullable di harness ini walau skema sebenarnya NOT NULL:
-- kasus 7-9 cuma menguji keunikan kode dan tidak butuh resource. FK komposit di
-- bawah MATCH SIMPLE, jadi baris ber-resource_id NULL melewatinya -- dan itu yang
-- membuat kasus 46 menguji pasangannya, bukan NOT NULL-nya.
CREATE TABLE resource_units (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id    uuid NOT NULL,
  resource_id uuid,
  code        text NOT NULL,
  status      text NOT NULL DEFAULT 'active',   -- BR-013
  deleted_at  timestamptz
);

-- BR-016: kelima nominal NULLABLE (NULL = aturannya tidak berlaku).
-- buffer_minutes sengaja NOT NULL -- lihat catatan di 03-erd.md §3.
CREATE TABLE resources (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id                 uuid NOT NULL,
  base_price               bigint  NOT NULL DEFAULT 0,
  pricing_unit             text    NOT NULL DEFAULT 'day',   -- BR-012, BR-017
  deposit_amount           bigint,
  late_fee_per_unit        bigint,
  min_duration             int,
  max_duration             int,
  buffer_minutes           int     NOT NULL DEFAULT 0,
  requires_id_verification boolean NOT NULL DEFAULT false,
  status                   text    NOT NULL DEFAULT 'active',  -- BR-010
  description              text,                                -- BR-095
  terms_excludes           text,
  terms_requirements       text,
  terms_cancellation       text
);

CREATE TABLE bookings (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id              uuid NOT NULL,
  code                  text NOT NULL,
  resource_unit_id      uuid NOT NULL,
  start_at              timestamptz NOT NULL,
  end_at                timestamptz NOT NULL,
  buffer_minutes        int  NOT NULL DEFAULT 0,
  end_at_with_buffer    timestamptz NOT NULL,
  status                text NOT NULL,
  deposit_amount        bigint,               -- BR-016: NULL = tanpa deposit
  deposit_deducted      bigint NOT NULL DEFAULT 0,
  deposit_refunded      bigint NOT NULL DEFAULT 0,
  deposit_waived_at     timestamptz,          -- BR-051
  deposit_waived_by     uuid,
  deposit_waiver_reason text,
  deleted_at            timestamptz
);

CREATE TABLE handovers (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id uuid NOT NULL,
  direction  text NOT NULL
);

CREATE TABLE handover_photos (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  handover_id uuid NOT NULL
);

CREATE TABLE subscriptions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid()
);

CREATE TABLE invoices (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id        uuid NOT NULL,
  booking_id      uuid,
  subscription_id uuid,
  status          text NOT NULL DEFAULT 'unpaid'
);

CREATE TABLE invoice_lines (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  invoice_id        uuid NOT NULL,
  kind              text NOT NULL,
  amount            bigint NOT NULL,
  handover_photo_id uuid
);

CREATE TABLE payments (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  invoice_id uuid NOT NULL,
  status     text NOT NULL
);

CREATE TABLE payment_gateway_transactions (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  provider    text NOT NULL,
  external_id text NOT NULL
);

CREATE TABLE notifications (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id     uuid NOT NULL,
  kind           text NOT NULL,
  scheduled_date date NOT NULL,
  attempt_no     int  NOT NULL DEFAULT 1,
  provider_message_id text                                    -- BR-073
);

CREATE TABLE refresh_tokens (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id   uuid NOT NULL REFERENCES owners(id),
  user_id    uuid NOT NULL REFERENCES users(id),
  token_hash text NOT NULL
);

-- ──────────────────── constraint, verbatim dari 03-erd.md §3 ────────────────────

-- BR-021
ALTER TABLE bookings
  ADD CONSTRAINT bookings_range_valid  CHECK (end_at > start_at),
  ADD CONSTRAINT bookings_buffer_valid CHECK (end_at_with_buffer >= end_at);

-- BR-016: NULL = tidak berlaku, 0 DILARANG (satu keadaan, satu cara menulisnya)
ALTER TABLE resources
  ADD CONSTRAINT resources_deposit_positive
    CHECK (deposit_amount    IS NULL OR deposit_amount    > 0),
  ADD CONSTRAINT resources_late_fee_positive
    CHECK (late_fee_per_unit IS NULL OR late_fee_per_unit > 0),
  ADD CONSTRAINT resources_min_duration_positive
    CHECK (min_duration      IS NULL OR min_duration      > 0),
  ADD CONSTRAINT resources_max_duration_positive
    CHECK (max_duration      IS NULL OR max_duration      > 0),
  ADD CONSTRAINT resources_duration_order
    CHECK (min_duration IS NULL OR max_duration IS NULL
           OR max_duration >= min_duration),
  ADD CONSTRAINT resources_buffer_nonneg CHECK (buffer_minutes >= 0);

-- BR-010 + BR-013: status asing tidak bikin error, ia bikin baris hilang diam-diam
-- dari pencarian ketersediaan.
ALTER TABLE resources ADD CONSTRAINT resources_status_valid
  CHECK (status IN ('active', 'inactive'));
ALTER TABLE resources ADD CONSTRAINT resources_base_price_nonneg
  CHECK (base_price >= 0);
ALTER TABLE resource_units ADD CONSTRAINT resource_units_status_valid
  CHECK (status IN ('active', 'maintenance', 'retired'));

-- BR-001: cek FK berjalan sebagai pemilik tabel dan MELEWATI RLS, jadi FK biasa ke
-- resources(id) menerima id pemilik mana pun. Pasangkan kolomnya.
ALTER TABLE resources ADD CONSTRAINT resources_id_owner_uq UNIQUE (id, owner_id);
ALTER TABLE resource_units ADD CONSTRAINT resource_units_resource_matches_owner
  FOREIGN KEY (resource_id, owner_id) REFERENCES resources (id, owner_id);

-- BR-094: tabel pendamping 1:1. Ketiga CHECK lintas kolom di bawah adalah alasan
-- ia bukan jsonb -- tidak satu pun bisa ditulis di sana.
ALTER TABLE resource_units ADD CONSTRAINT resource_units_id_owner_uq
  UNIQUE (id, owner_id);

CREATE TABLE vehicle_specs (
  resource_id  uuid PRIMARY KEY,
  owner_id     uuid NOT NULL,
  vehicle_type text NOT NULL,
  transmission text NOT NULL DEFAULT 'manual',
  seats        int,
  fuel         text NOT NULL DEFAULT 'gasoline',
  CONSTRAINT vehicle_specs_resource_matches_owner
    FOREIGN KEY (resource_id, owner_id) REFERENCES resources (id, owner_id)
    ON DELETE CASCADE
);

ALTER TABLE vehicle_specs
  ADD CONSTRAINT vehicle_specs_type_valid
    CHECK (vehicle_type IN ('car', 'motorcycle')),
  ADD CONSTRAINT vehicle_specs_transmission_valid
    CHECK (transmission IN ('manual', 'automatic', 'clutch')),
  ADD CONSTRAINT vehicle_specs_fuel_valid
    CHECK (fuel IN ('gasoline', 'diesel', 'hybrid', 'electric')),
  ADD CONSTRAINT vehicle_specs_seats_range
    CHECK (seats IS NULL OR seats BETWEEN 2 AND 20),
  ADD CONSTRAINT vehicle_specs_seats_car
    CHECK ((vehicle_type = 'car') = (seats IS NOT NULL)),
  ADD CONSTRAINT vehicle_specs_clutch_moto
    CHECK (transmission <> 'clutch' OR vehicle_type = 'motorcycle'),
  ADD CONSTRAINT vehicle_specs_diesel_car
    CHECK (fuel <> 'diesel' OR vehicle_type = 'car');

CREATE TABLE vehicle_unit_details (
  resource_unit_id        uuid PRIMARY KEY,
  owner_id                uuid NOT NULL,
  year                    int NOT NULL DEFAULT 2020,
  color                   text,
  tax_due_on              date,
  registration_valid_until date,
  CONSTRAINT vehicle_unit_details_unit_matches_owner
    FOREIGN KEY (resource_unit_id, owner_id) REFERENCES resource_units (id, owner_id)
    ON DELETE CASCADE
);

ALTER TABLE vehicle_unit_details
  ADD CONSTRAINT vehicle_unit_details_year_range
    CHECK (year BETWEEN 1990 AND 2100);

-- BR-095: halaman publik merendernya apa adanya.
ALTER TABLE resources
  ADD CONSTRAINT resources_description_length
    CHECK (description IS NULL OR char_length(description) <= 500),
  ADD CONSTRAINT resources_terms_excludes_length
    CHECK (terms_excludes IS NULL OR char_length(terms_excludes) <= 500),
  ADD CONSTRAINT resources_terms_requirements_length
    CHECK (terms_requirements IS NULL OR char_length(terms_requirements) <= 1000),
  ADD CONSTRAINT resources_terms_cancellation_length
    CHECK (terms_cancellation IS NULL OR char_length(terms_cancellation) <= 1000);

-- BR-096: nomor yang dibaca mesin, bukan mata.
ALTER TABLE owners
  ADD CONSTRAINT owners_whatsapp_format
    CHECK (whatsapp IS NULL OR whatsapp ~ '^\+62[0-9]{8,13}$');

-- BR-048 + BR-016. Versi lama (deposit_deducted <= deposit_amount) lolos DIAM-DIAM
-- begitu deposit_amount nullable: CHECK yang bernilai NULL dianggap lolos.
ALTER TABLE bookings
  ADD CONSTRAINT bookings_deposit_nonneg
  CHECK (deposit_deducted >= 0 AND deposit_refunded >= 0
         AND (deposit_amount IS NOT NULL
              OR (deposit_deducted = 0 AND deposit_refunded = 0))
         AND (deposit_amount IS NULL OR deposit_deducted <= deposit_amount));

-- BR-051: pembebasan terisi bertiga atau tidak sama sekali.
ALTER TABLE bookings
  ADD CONSTRAINT bookings_deposit_waiver_complete
  CHECK (num_nonnulls(deposit_waived_at, deposit_waived_by, deposit_waiver_reason)
         IN (0, 3));

-- BR-024
CREATE UNIQUE INDEX bookings_code_per_owner ON bookings (owner_id, code);
ALTER TABLE owners ADD CONSTRAINT owners_booking_code_prefix_format
  CHECK (booking_code_prefix ~ '^[A-Z0-9]{2,6}$');

-- BR-012: satuan harga dipakai di perhitungan uang; nilai asing = tagihan salah.
ALTER TABLE resources ADD CONSTRAINT resources_pricing_unit_valid
  CHECK (pricing_unit IN ('hour', 'day', 'week', 'month'));

-- BR-057: tenggat bayar > 0 (nol = jatuh tempo saat terbit); toleransi no-show
-- boleh 0 (langsung no_show lewat start_at adalah kebijakan yang sah).
ALTER TABLE owners
  ADD CONSTRAINT owners_payment_due_positive     CHECK (payment_due_hours > 0),
  ADD CONSTRAINT owners_no_show_tolerance_nonneg CHECK (no_show_tolerance_hours >= 0);

-- BR-017: preset pasar yang menentukan satuan itu.
ALTER TABLE owners ADD CONSTRAINT owners_business_type_valid
  CHECK (business_type IN ('vehicle_rental', 'equipment_rental',
                           'boarding_house', 'apartment', 'venue', 'clinic'));
CREATE TABLE booking_counters (
  owner_id    uuid PRIMARY KEY REFERENCES owners(id),
  last_number bigint NOT NULL DEFAULT 0
);

-- BR-011
CREATE UNIQUE INDEX resource_units_code_per_owner
  ON resource_units (owner_id, code) WHERE deleted_at IS NULL;

-- BR-004: email unik GLOBAL, bukan per usaha -- itu yang bikin login cukup
-- email+password tanpa parameter usaha.
ALTER TABLE users ADD CONSTRAINT users_email_key UNIQUE (email);

-- BR-004: refresh token tidak bisa menunjuk usaha yang bukan usaha user-nya.
-- users_id_owner_uq cuma ada sebagai target FK di bawah -- id sendiri sudah PK.
ALTER TABLE users ADD CONSTRAINT users_id_owner_uq UNIQUE (id, owner_id);
ALTER TABLE refresh_tokens ADD CONSTRAINT refresh_tokens_user_matches_owner
  FOREIGN KEY (user_id, owner_id) REFERENCES users (id, owner_id);

-- BR-025
-- BUKAN lower(slug) -- lihat 03-erd.md §3. Format sudah menjamin huruf kecil,
-- dan index ekspresi tidak melayani WHERE slug = $1 (jalur Host -> owner).
CREATE UNIQUE INDEX owners_slug_unique ON owners (slug);
ALTER TABLE owners ADD CONSTRAINT owners_slug_format
  CHECK (slug ~ '^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$');
ALTER TABLE owners ADD CONSTRAINT owners_slug_not_punycode
  CHECK (substring(slug, 3, 2) <> '--');
ALTER TABLE owners ADD CONSTRAINT owners_slug_not_reserved
  CHECK (slug NOT IN (
    'app','api','www','admin','auth','login','dashboard','portal','settings',
    'static','assets','cdn','media','img','files','mail','smtp','imap','mx',
    'ns1','ns2','blog','status','help','docs','support','billing','pay',
    'checkout','webhook','webhooks','test','staging','dev','demo','sewain'));

-- BR-060
CREATE UNIQUE INDEX payments_one_success_per_invoice
  ON payments (invoice_id) WHERE status = 'success';

-- BR-063
CREATE UNIQUE INDEX pgt_provider_external_id
  ON payment_gateway_transactions (provider, external_id);

-- BR-047
ALTER TABLE invoice_lines ADD CONSTRAINT invoice_lines_damage_needs_photo
  CHECK (kind <> 'damage' OR handover_photo_id IS NOT NULL);

-- BR-055
ALTER TABLE invoice_lines ADD CONSTRAINT invoice_lines_sign
  CHECK ((kind = 'discount' AND amount < 0) OR (kind <> 'discount' AND amount > 0));

-- BR-035
CREATE UNIQUE INDEX handovers_one_per_direction
  ON handovers (booking_id, direction);

-- BR-071
CREATE UNIQUE INDEX notifications_once_per_day
  ON notifications (booking_id, kind, scheduled_date);
CREATE UNIQUE INDEX notifications_provider_message_id
  ON notifications (provider_message_id) WHERE provider_message_id IS NOT NULL;
ALTER TABLE notifications ADD CONSTRAINT notifications_max_attempts
  CHECK (attempt_no BETWEEN 1 AND 3);

-- BR-082
ALTER TABLE invoices ADD CONSTRAINT invoices_one_subject
  CHECK (num_nonnulls(booking_id, subscription_id) = 1);

-- index kecepatan (PRD §9) — diuji hanya "bisa dibuat"
CREATE INDEX bookings_unit_range ON bookings
  USING gist (resource_unit_id, tstzrange(start_at, end_at_with_buffer, '[)'))
  WHERE status IN ('reserved','picked_up') AND deleted_at IS NULL;
CREATE INDEX bookings_owner_status_start ON bookings (owner_id, status, start_at);
CREATE INDEX resource_units_owner_resource_status
  ON resource_units (owner_id, resource_id, status) WHERE deleted_at IS NULL;

-- ─────────────────────────────── kasus uji ───────────────────────────────

DO $$
DECLARE
  o1 uuid := '11111111-1111-1111-1111-111111111111';
  o2 uuid := '22222222-2222-2222-2222-222222222222';
  u1 uuid := '33333333-3333-3333-3333-333333333333';
  b1 uuid := '44444444-4444-4444-4444-444444444444';
  i1 uuid := '55555555-5555-5555-5555-555555555555';
  ph uuid := '66666666-6666-6666-6666-666666666666';
  us uuid := '77777777-7777-7777-7777-777777777777';
  r_id uuid;
  r_id2 uuid;
  u_id uuid;
  n  int  := 0;
BEGIN
  INSERT INTO owners (id, slug) VALUES (o1, 'rentalbudi'), (o2, 'rentalsari');
  INSERT INTO users (id, owner_id, email) VALUES (u1, o1, 'operator@contoh.id');
  INSERT INTO subscriptions (id) VALUES (i1);
  INSERT INTO handovers (id, booking_id, direction) VALUES (ph, b1, 'return');
  INSERT INTO handover_photos (id, handover_id) VALUES (ph, ph);

  -- 1 · owners_slug_unique: duplikat persis ditolak
  BEGIN
    INSERT INTO owners (slug) VALUES ('rentalbudi');
    RAISE EXCEPTION 'GAGAL: slug duplikat diterima';
  EXCEPTION WHEN unique_violation THEN
    n := n+1; RAISE NOTICE 'OK %/57 - owners_slug_unique tolak duplikat', n;
  END;

  -- 2 · owners_slug_format: hyphen di ujung DAN huruf besar ditolak.
  --     Huruf besar ditolak di sini, bukan di unique index -- itu sebabnya
  --     index-nya tidak perlu lower(). Lihat 03-erd.md §3.
  BEGIN
    INSERT INTO owners (slug) VALUES ('-rental');
    RAISE EXCEPTION 'GAGAL: slug diawali hyphen diterima';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  BEGIN
    INSERT INTO owners (slug) VALUES ('RentalBudi');
    RAISE EXCEPTION 'GAGAL: slug huruf besar diterima';
  EXCEPTION WHEN check_violation THEN
    n := n+1; RAISE NOTICE 'OK %/57 - owners_slug_format tolak hyphen ujung & huruf besar', n;
  END;

  -- 3 · owners_slug_format: 2 karakter ditolak (minimum 3)
  BEGIN
    INSERT INTO owners (slug) VALUES ('ab');
    RAISE EXCEPTION 'GAGAL: slug 2 karakter diterima';
  EXCEPTION WHEN check_violation THEN
    n := n+1; RAISE NOTICE 'OK %/57 - owners_slug_format tolak < 3 karakter', n;
  END;

  -- 4 · owners_slug_not_punycode: xn-- ditolak
  BEGIN
    INSERT INTO owners (slug) VALUES ('xn--80ak6aa92e');
    RAISE EXCEPTION 'GAGAL: slug punycode diterima';
  EXCEPTION WHEN check_violation THEN
    n := n+1; RAISE NOTICE 'OK %/57 - owners_slug_not_punycode tolak xn--', n;
  END;

  -- 5 · owners_slug_not_reserved
  BEGIN
    INSERT INTO owners (slug) VALUES ('api');
    RAISE EXCEPTION 'GAGAL: subdomain terlarang diterima';
  EXCEPTION WHEN check_violation THEN
    n := n+1; RAISE NOTICE 'OK %/57 - owners_slug_not_reserved tolak "api"', n;
  END;

  -- 6 · slug sah tetap diterima (constraint tidak kebablasan)
  INSERT INTO owners (slug) VALUES ('rental-budi-2021');
  n := n+1; RAISE NOTICE 'OK %/57 - slug sah tetap diterima', n;

  -- 7 · resource_units_code_per_owner: kode sama, owner sama → tolak
  INSERT INTO resource_units (owner_id, code) VALUES (o1, 'B 1234 XY');
  BEGIN
    INSERT INTO resource_units (owner_id, code) VALUES (o1, 'B 1234 XY');
    RAISE EXCEPTION 'GAGAL: kode unit ganda pada satu owner diterima';
  EXCEPTION WHEN unique_violation THEN
    n := n+1; RAISE NOTICE 'OK %/57 - kode unit unik per owner', n;
  END;

  -- 8 · owner lain boleh pakai kode yang sama
  INSERT INTO resource_units (owner_id, code) VALUES (o2, 'B 1234 XY');
  n := n+1; RAISE NOTICE 'OK %/57 - owner lain boleh kode sama', n;

  -- 9 · unit terhapus dikecualikan dari unique
  UPDATE resource_units SET deleted_at = now() WHERE owner_id = o2;
  INSERT INTO resource_units (owner_id, code) VALUES (o2, 'B 1234 XY');
  n := n+1; RAISE NOTICE 'OK %/57 - partial index kecualikan deleted_at', n;

  -- 10 · bookings_code_per_owner
  INSERT INTO bookings (id, owner_id, code, resource_unit_id, start_at, end_at,
                        end_at_with_buffer, status)
  VALUES (b1, o1, 'SWN-0001', u1, '2026-09-03 09:00+07', '2026-09-05 09:00+07',
          '2026-09-05 09:00+07', 'reserved');
  BEGIN
    INSERT INTO bookings (owner_id, code, resource_unit_id, start_at, end_at,
                          end_at_with_buffer, status)
    VALUES (o1, 'SWN-0001', u1, '2026-10-03 09:00+07', '2026-10-05 09:00+07',
            '2026-10-05 09:00+07', 'reserved');
    RAISE EXCEPTION 'GAGAL: kode booking ganda pada satu owner diterima';
  EXCEPTION WHEN unique_violation THEN
    n := n+1; RAISE NOTICE 'OK %/57 - kode booking unik per owner', n;
  END;

  -- 11 · bookings_range_valid
  BEGIN
    INSERT INTO bookings (owner_id, code, resource_unit_id, start_at, end_at,
                          end_at_with_buffer, status)
    VALUES (o1, 'SWN-0002', u1, '2026-09-05 09:00+07', '2026-09-03 09:00+07',
            '2026-09-03 09:00+07', 'reserved');
    RAISE EXCEPTION 'GAGAL: end_at sebelum start_at diterima';
  EXCEPTION WHEN check_violation THEN
    n := n+1; RAISE NOTICE 'OK %/57 - bookings_range_valid', n;
  END;

  -- 12 · bookings_buffer_valid
  BEGIN
    INSERT INTO bookings (owner_id, code, resource_unit_id, start_at, end_at,
                          end_at_with_buffer, status)
    VALUES (o1, 'SWN-0003', u1, '2026-09-03 09:00+07', '2026-09-05 09:00+07',
            '2026-09-04 09:00+07', 'reserved');
    RAISE EXCEPTION 'GAGAL: end_at_with_buffer < end_at diterima';
  EXCEPTION WHEN check_violation THEN
    n := n+1; RAISE NOTICE 'OK %/57 - bookings_buffer_valid', n;
  END;

  -- 13 · bookings_deposit_nonneg: potongan > deposit ditolak
  BEGIN
    UPDATE bookings SET deposit_amount = 500000, deposit_deducted = 700000 WHERE id = b1;
    RAISE EXCEPTION 'GAGAL: deposit_deducted melebihi deposit_amount diterima';
  EXCEPTION WHEN check_violation THEN
    n := n+1; RAISE NOTICE 'OK %/57 - deposit tidak bisa dipotong lebih dari nilainya', n;
  END;

  -- 14 · deposit habis persis (= amount) harus DITERIMA
  UPDATE bookings SET deposit_amount = 500000, deposit_deducted = 500000 WHERE id = b1;
  n := n+1; RAISE NOTICE 'OK %/57 - deposit habis persis diterima', n;

  -- 15 · booking_counters FK ke owners
  BEGIN
    INSERT INTO booking_counters (owner_id) VALUES (u1);
    RAISE EXCEPTION 'GAGAL: booking_counters menerima owner_id asing';
  EXCEPTION WHEN foreign_key_violation THEN
    n := n+1; RAISE NOTICE 'OK %/57 - booking_counters FK ke owners', n;
  END;

  -- 16 · handovers_one_per_direction
  BEGIN
    INSERT INTO handovers (booking_id, direction) VALUES (b1, 'return');
    RAISE EXCEPTION 'GAGAL: dua handover arah sama pada satu booking diterima';
  EXCEPTION WHEN unique_violation THEN
    n := n+1; RAISE NOTICE 'OK %/57 - satu handover per arah per booking', n;
  END;

  -- 17 · invoices_one_subject: dua-duanya NULL ditolak
  BEGIN
    INSERT INTO invoices (owner_id) VALUES (o1);
    RAISE EXCEPTION 'GAGAL: invoice tanpa subjek diterima';
  EXCEPTION WHEN check_violation THEN
    n := n+1; RAISE NOTICE 'OK %/57 - invoices_one_subject tolak nol subjek', n;
  END;

  -- 18 · invoices_one_subject: dua-duanya terisi ditolak; lalu satu subjek diterima
  BEGIN
    INSERT INTO invoices (owner_id, booking_id, subscription_id) VALUES (o1, b1, i1);
    RAISE EXCEPTION 'GAGAL: invoice dua subjek diterima';
  EXCEPTION WHEN check_violation THEN
    INSERT INTO invoices (id, owner_id, booking_id) VALUES (i1, o1, b1);
    n := n+1; RAISE NOTICE 'OK %/57 - invoices_one_subject tolak dua subjek', n;
  END;

  -- 19 · invoice_lines_damage_needs_photo + invoice_lines_sign
  BEGIN
    INSERT INTO invoice_lines (invoice_id, kind, amount) VALUES (i1, 'damage', 500000);
    RAISE EXCEPTION 'GAGAL: baris damage tanpa foto diterima';
  EXCEPTION WHEN check_violation THEN
    INSERT INTO invoice_lines (invoice_id, kind, amount, handover_photo_id)
    VALUES (i1, 'damage', 500000, ph);
    n := n+1; RAISE NOTICE 'OK %/57 - baris damage wajib merujuk foto', n;
  END;

  BEGIN
    INSERT INTO invoice_lines (invoice_id, kind, amount) VALUES (i1, 'discount', 50000);
    RAISE EXCEPTION 'GAGAL: discount bernilai positif diterima';
  EXCEPTION WHEN check_violation THEN
    INSERT INTO invoice_lines (invoice_id, kind, amount) VALUES (i1, 'discount', -50000);
    n := n+1; RAISE NOTICE 'OK %/57 - discount wajib negatif, rent wajib positif', n;
  END;

  -- 20 · payments_one_success_per_invoice + notifications
  INSERT INTO payments (invoice_id, status) VALUES (i1, 'success');
  INSERT INTO payments (invoice_id, status) VALUES (i1, 'failed');   -- gagal boleh menumpuk
  BEGIN
    INSERT INTO payments (invoice_id, status) VALUES (i1, 'success');
    RAISE EXCEPTION 'GAGAL: dua pembayaran sukses pada satu invoice diterima';
  EXCEPTION WHEN unique_violation THEN
    n := n+1; RAISE NOTICE 'OK %/57 - satu pembayaran sukses per invoice', n;
  END;

  INSERT INTO notifications (booking_id, kind, scheduled_date, attempt_no)
  VALUES (b1, 'overdue', '2026-09-06', 3);
  BEGIN
    INSERT INTO notifications (booking_id, kind, scheduled_date) VALUES (b1, 'overdue', '2026-09-06');
    RAISE EXCEPTION 'GAGAL: dua pengingat sejenis pada hari sama diterima';
  EXCEPTION WHEN unique_violation THEN
    NULL;
  END;
  BEGIN
    INSERT INTO notifications (booking_id, kind, scheduled_date, attempt_no)
    VALUES (b1, 'overdue', '2026-09-07', 4);
    RAISE EXCEPTION 'GAGAL: attempt_no 4 diterima';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;
  BEGIN
    INSERT INTO payment_gateway_transactions (provider, external_id) VALUES ('midtrans', 'trx-1');
    INSERT INTO payment_gateway_transactions (provider, external_id) VALUES ('midtrans', 'trx-1');
    RAISE EXCEPTION 'GAGAL: external_id ganda per provider diterima';
  EXCEPTION WHEN unique_violation THEN
    NULL;
  END;

  -- 22 · users_email_key: email unik GLOBAL, termasuk lintas usaha.
  --      Kalau per-usaha, POST /auth/login yang cuma membawa email+password tidak
  --      punya apa pun untuk memilih di antara dua baris.
  INSERT INTO users (id, owner_id, email, role) VALUES (us, o1, 'budi@contoh.id', 'owner');
  BEGIN
    INSERT INTO users (owner_id, email) VALUES (o2, 'budi@contoh.id');
    RAISE EXCEPTION 'GAGAL: email yang sama diterima di usaha kedua';
  EXCEPTION WHEN unique_violation THEN
    INSERT INTO users (owner_id, email) VALUES (o2, 'sari@contoh.id');
    n := n+1; RAISE NOTICE 'OK %/57 - email unik global, alamat lain tetap boleh', n;
  END;

  -- 23 · refresh_tokens_user_matches_owner: token tidak bisa menunjuk usaha lain.
  --      refresh_tokens punya owner_id DAN user_id; tanpa FK komposit ini tidak ada
  --      yang memaksa keduanya cocok, dan baris yang tidak cocok menerbitkan access
  --      token untuk usaha yang salah -- senyap, karena tidak ada yang error.
  --      us ada di o1, jadi token ber-owner o2 untuk user itu harus ditolak.
  BEGIN
    INSERT INTO refresh_tokens (owner_id, user_id, token_hash) VALUES (o2, us, 'h1');
    RAISE EXCEPTION 'GAGAL: refresh token ber-owner asing diterima';
  EXCEPTION WHEN foreign_key_violation THEN
    INSERT INTO refresh_tokens (owner_id, user_id, token_hash) VALUES (o1, us, 'h1');
    n := n+1; RAISE NOTICE 'OK %/57 - refresh token wajib usaha yang sama dengan user', n;
  END;

  -- ══ BR-016 · kosong berarti tidak berlaku; NOL dilarang ══
  -- Inti aturannya: satu keadaan tidak boleh punya dua cara menulisnya. Tanpa
  -- larangan 0, "tanpa deposit" bisa ditulis NULL oleh satu jalur dan 0 oleh
  -- jalur lain, dan tidak ada laporan yang bisa membedakannya lagi.

  -- 24 · resources_deposit_positive: 0 ditolak
  BEGIN
    INSERT INTO resources (owner_id, deposit_amount) VALUES (o1, 0);
    RAISE EXCEPTION 'GAGAL: deposit_amount = 0 diterima';
  EXCEPTION WHEN check_violation THEN
    n := n+1; RAISE NOTICE 'OK %/57 - deposit_amount 0 ditolak (pakai NULL)', n;
  END;

  -- 25 · ...tapi NULL DITERIMA -- ini yang membuat "tanpa deposit" bisa ditulis
  INSERT INTO resources (owner_id, deposit_amount, late_fee_per_unit)
  VALUES (o1, NULL, NULL);
  n := n+1; RAISE NOTICE 'OK %/57 - deposit & denda NULL diterima', n;

  -- 26 · resources_late_fee_positive: 0 ditolak
  BEGIN
    INSERT INTO resources (owner_id, late_fee_per_unit) VALUES (o1, 0);
    RAISE EXCEPTION 'GAGAL: late_fee_per_unit = 0 diterima';
  EXCEPTION WHEN check_violation THEN
    n := n+1; RAISE NOTICE 'OK %/57 - late_fee_per_unit 0 ditolak', n;
  END;

  -- 27 · resources_min_duration_positive: 0 ditolak
  BEGIN
    INSERT INTO resources (owner_id, min_duration) VALUES (o1, 0);
    RAISE EXCEPTION 'GAGAL: min_duration = 0 diterima';
  EXCEPTION WHEN check_violation THEN
    n := n+1; RAISE NOTICE 'OK %/57 - min_duration 0 ditolak', n;
  END;

  -- 28 · resources_max_duration_positive: 0 ditolak
  BEGIN
    INSERT INTO resources (owner_id, max_duration) VALUES (o1, 0);
    RAISE EXCEPTION 'GAGAL: max_duration = 0 diterima';
  EXCEPTION WHEN check_violation THEN
    n := n+1; RAISE NOTICE 'OK %/57 - max_duration 0 ditolak', n;
  END;

  -- 29 · resources_duration_order: max < min ditolak; satu sisi kosong diterima
  BEGIN
    INSERT INTO resources (owner_id, min_duration, max_duration) VALUES (o1, 7, 3);
    RAISE EXCEPTION 'GAGAL: max_duration < min_duration diterima';
  EXCEPTION WHEN check_violation THEN
    INSERT INTO resources (owner_id, min_duration, max_duration) VALUES (o1, 7, NULL);
    n := n+1; RAISE NOTICE 'OK %/57 - max < min ditolak, batas sepihak diterima', n;
  END;

  -- 30 · resources_buffer_nonneg: negatif ditolak
  BEGIN
    INSERT INTO resources (owner_id, buffer_minutes) VALUES (o1, -1);
    RAISE EXCEPTION 'GAGAL: buffer_minutes negatif diterima';
  EXCEPTION WHEN check_violation THEN
    n := n+1; RAISE NOTICE 'OK %/57 - buffer_minutes negatif ditolak', n;
  END;

  -- 31 · bookings_deposit_nonneg: booking TANPA deposit tidak boleh punya potongan.
  --      Ini kasus yang versi lama constraint-nya lolos DIAM-DIAM: dengan
  --      deposit_amount NULL, CHECK (deposit_deducted <= deposit_amount) bernilai
  --      NULL, dan CHECK bernilai NULL dianggap lolos. Penyewa dipotong dari
  --      titipan yang tidak pernah ada, tanpa satu pun error.
  BEGIN
    INSERT INTO bookings (owner_id, code, resource_unit_id, start_at, end_at,
                          end_at_with_buffer, status,
                          deposit_amount, deposit_deducted)
    VALUES (o1, 'SWN-0010', u1, '2026-09-03 09:00+07', '2026-09-05 09:00+07',
            '2026-09-05 09:00+07', 'reserved', NULL, 100000);
    RAISE EXCEPTION 'GAGAL: potongan pada booking tanpa deposit diterima';
  EXCEPTION WHEN check_violation THEN
    n := n+1; RAISE NOTICE 'OK %/57 - tanpa deposit, potongan ditolak', n;
  END;

  -- 32 · bookings_deposit_waiver_complete: dibebaskan tanpa alasan ditolak
  BEGIN
    UPDATE bookings SET deposit_waived_at = now(), deposit_waived_by = u1
    WHERE id = b1;
    RAISE EXCEPTION 'GAGAL: pembebasan tanpa alasan diterima';
  EXCEPTION WHEN check_violation THEN
    n := n+1; RAISE NOTICE 'OK %/57 - pembebasan wajib berasalan', n;
  END;

  -- 33 · ...bertiga lengkap DITERIMA
  UPDATE bookings SET deposit_waived_at = now(), deposit_waived_by = u1,
                      deposit_waiver_reason = 'pelanggan lama, disepakati pemilik'
  WHERE id = b1;
  n := n+1; RAISE NOTICE 'OK %/57 - pembebasan lengkap diterima', n;

  -- ══ BR-024 · prefix kode booking milik pemilik ══
  -- Kode ini dibacakan lewat telepon. Format dijaga database supaya tidak ada
  -- pemilik yang menyimpan prefix sepanjang slug-nya lalu heran kodenya tidak
  -- bisa dibacakan.

  -- 34 · owners_booking_code_prefix_format: huruf kecil ditolak
  BEGIN
    INSERT INTO owners (slug, booking_code_prefix) VALUES ('rental-kecil', 'rb');
    RAISE EXCEPTION 'GAGAL: prefix huruf kecil diterima';
  EXCEPTION WHEN check_violation THEN
    n := n+1; RAISE NOTICE 'OK %/57 - prefix huruf kecil ditolak', n;
  END;

  -- 35 · ...lebih dari 6 karakter ditolak; 6 karakter DITERIMA
  BEGIN
    INSERT INTO owners (slug, booking_code_prefix) VALUES ('rental-tujuh', 'ABCDEFG');
    RAISE EXCEPTION 'GAGAL: prefix 7 karakter diterima';
  EXCEPTION WHEN check_violation THEN
    INSERT INTO owners (slug, booking_code_prefix) VALUES ('rental-enam', 'MTR999');
    n := n+1; RAISE NOTICE 'OK %/57 - prefix 7 karakter ditolak, 6 diterima', n;
  END;

  -- ══ BR-012 + BR-017 · satuan harga & preset pasar ══
  -- pricing_unit dipakai di duration_qty DAN rumus denda BR-046. Sampai constraint
  -- ini ada, INSERT yang melewatkannya menghasilkan NULL dan 'bulan' diterima --
  -- dua-duanya menghasilkan tagihan yang salah, bukan sekadar data kotor.

  -- 36 · resources_pricing_unit_valid: nilai asing ditolak
  BEGIN
    INSERT INTO resources (owner_id, pricing_unit) VALUES (o1, 'bulan');
    RAISE EXCEPTION 'GAGAL: pricing_unit asing diterima';
  EXCEPTION WHEN check_violation THEN
    n := n+1; RAISE NOTICE 'OK %/57 - pricing_unit asing ditolak', n;
  END;

  -- 37 · ...dan yang TIDAK dikirim jatuh ke 'day', bukan NULL
  INSERT INTO resources (owner_id) VALUES (o1) RETURNING id INTO r_id;
  IF (SELECT pricing_unit FROM resources WHERE id = r_id) IS DISTINCT FROM 'day' THEN
    RAISE EXCEPTION 'GAGAL: pricing_unit tanpa nilai tidak jatuh ke day';
  END IF;
  n := n+1; RAISE NOTICE 'OK %/57 - pricing_unit default day, bukan NULL', n;

  -- 38 · owners_business_type_valid: preset asing ditolak
  BEGIN
    INSERT INTO owners (slug, business_type) VALUES ('rental-warung', 'warung');
    RAISE EXCEPTION 'GAGAL: business_type asing diterima';
  EXCEPTION WHEN check_violation THEN
    n := n+1; RAISE NOTICE 'OK %/57 - business_type asing ditolak', n;
  END;

  -- 39 · BR-025 · slug NULL diterima, dan BANYAK slug NULL tidak saling tabrakan.
  --      Tier gratis tidak punya halaman publik maupun portal penyewa, jadi kosong
  --      adalah keadaan awal setiap pemilik. Kasus ini menjaga dua hal sekaligus:
  --      keempat CHECK slug lolos saat NULL, dan unique index tidak menganggap dua
  --      NULL sebagai duplikat.
  INSERT INTO owners (slug) VALUES (NULL), (NULL);
  n := n+1; RAISE NOTICE 'OK %/57 - slug NULL diterima, dua NULL tidak tabrakan', n;

  -- ══ BR-057 · tenggat bayar & toleransi no-show ══

  -- 40 · owners_payment_due_positive: 0 jam ditolak
  BEGIN
    INSERT INTO owners (slug, payment_due_hours) VALUES ('rental-noljam', 0);
    RAISE EXCEPTION 'GAGAL: payment_due_hours = 0 diterima';
  EXCEPTION WHEN check_violation THEN
    n := n+1; RAISE NOTICE 'OK %/57 - payment_due_hours 0 ditolak', n;
  END;

  -- 41 · owners_no_show_tolerance_nonneg: negatif ditolak, tapi 0 DITERIMA
  BEGIN
    INSERT INTO owners (slug, no_show_tolerance_hours) VALUES ('rental-negatif', -1);
    RAISE EXCEPTION 'GAGAL: no_show_tolerance_hours negatif diterima';
  EXCEPTION WHEN check_violation THEN
    INSERT INTO owners (slug, no_show_tolerance_hours) VALUES ('rental-ketat', 0);
    n := n+1; RAISE NOTICE 'OK %/57 - toleransi negatif ditolak, 0 diterima', n;
  END;

  -- ══ BR-073 · korelasi webhook WhatsApp ══
  -- wamid adalah satu-satunya jalan menghubungkan status yang masuk ke barisnya.
  -- Kalau dua baris bisa memegang wamid yang sama, satu callback memperbarui baris
  -- yang salah - dan BR-072 berhenti bisa dipercaya.

  -- 42 · notifications_provider_message_id: wamid ganda ditolak
  INSERT INTO notifications (booking_id, kind, scheduled_date, provider_message_id)
  VALUES (b1, 'pickup_reminder', '2026-09-10', 'wamid.HBgN123');
  BEGIN
    INSERT INTO notifications (booking_id, kind, scheduled_date, provider_message_id)
    VALUES (b1, 'return_reminder', '2026-09-10', 'wamid.HBgN123');
    RAISE EXCEPTION 'GAGAL: provider_message_id ganda diterima';
  EXCEPTION WHEN unique_violation THEN
    n := n+1; RAISE NOTICE 'OK %/57 - wamid ganda ditolak', n;
  END;

  -- 43 · ...tapi banyak NULL boleh berdampingan (belum terkirim)
  INSERT INTO notifications (booking_id, kind, scheduled_date)
  VALUES (b1, 'invoice_link', '2026-09-11'), (b1, 'payment_due_reminder', '2026-09-11');
  n := n+1; RAISE NOTICE 'OK %/57 - banyak wamid NULL berdampingan', n;

  -- ══ BR-010 + BR-013 · status katalog, dan siapa pemilik jenis barangnya ══

  -- 44 · resources_status_valid: nilai asing ditolak
  BEGIN
    INSERT INTO resources (owner_id, status) VALUES (o1, 'draft');
    RAISE EXCEPTION 'GAGAL: status resource asing diterima';
  EXCEPTION WHEN check_violation THEN
    n := n+1; RAISE NOTICE 'OK %/57 - status resource asing ditolak', n;
  END;

  -- 45 · resource_units_status_valid: 'rusak' ditolak, ketiga nilai sah diterima.
  --      Sisi kedua penting: constraint yang menolak 'maintenance' akan lolos
  --      kasus pertama dan menghancurkan BR-013 tanpa satu pun test merah.
  BEGIN
    INSERT INTO resource_units (owner_id, code, status) VALUES (o1, 'B 9 RUSAK', 'rusak');
    RAISE EXCEPTION 'GAGAL: status unit asing diterima';
  EXCEPTION WHEN check_violation THEN
    INSERT INTO resource_units (owner_id, code, status)
    VALUES (o1, 'B 1 AKTIF', 'active'), (o1, 'B 2 BENGKEL', 'maintenance'),
           (o1, 'B 3 PENSIUN', 'retired');
    n := n+1; RAISE NOTICE 'OK %/57 - status unit asing ditolak, ketiganya diterima', n;
  END;

  -- 46 · resource_units_resource_matches_owner: unit o2 tidak bisa menunjuk
  --      resource milik o1. r_id dibuat di kasus 37 dan milik o1.
  INSERT INTO resource_units (owner_id, resource_id, code) VALUES (o1, r_id, 'B 4 SAH');
  BEGIN
    INSERT INTO resource_units (owner_id, resource_id, code) VALUES (o2, r_id, 'B 5 CURI');
    RAISE EXCEPTION 'GAGAL: unit menunjuk resource pemilik lain diterima';
  EXCEPTION WHEN foreign_key_violation THEN
    n := n+1; RAISE NOTICE 'OK %/57 - unit tidak bisa menunjuk resource pemilik lain', n;
  END;

  -- 47 · resources_base_price_nonneg: negatif ditolak, NOL diterima.
  --      Sisi kedua yang penting: constraint '> 0' akan lolos kasus pertama dan
  --      diam-diam melarang barang pelengkap gratis.
  BEGIN
    INSERT INTO resources (owner_id, base_price) VALUES (o1, -1);
    RAISE EXCEPTION 'GAGAL: base_price negatif diterima';
  EXCEPTION WHEN check_violation THEN
    INSERT INTO resources (owner_id, base_price) VALUES (o1, 0);
    n := n+1; RAISE NOTICE 'OK %/57 - base_price negatif ditolak, 0 diterima', n;
  END;

  -- Fixture untuk kasus 48-57. r_id dibuat di kasus 37 dan milik o1.
  INSERT INTO resources (owner_id) VALUES (o1) RETURNING id INTO r_id2;
  INSERT INTO resource_units (owner_id, resource_id, code)
  VALUES (o1, r_id, 'B 6 SPEK') RETURNING id INTO u_id;

  -- ══ BR-094 · atribut kendaraan, dan tiga aturan lintas kolom ══
  -- Ketiganya alasan tabel ini bukan jsonb. Tiap satu diuji DUA ARAH: constraint
  -- yang kebablasan (menolak yang sah) sama rusaknya dengan yang bolong.

  -- 48 · vehicle_specs enum: jenis, transmisi, dan BBM asing ditolak
  BEGIN
    INSERT INTO vehicle_specs (resource_id, owner_id, vehicle_type, seats)
    VALUES (r_id, o1, 'truk', 4);
    RAISE EXCEPTION 'GAGAL: vehicle_type asing diterima';
  EXCEPTION WHEN check_violation THEN
    n := n+1; RAISE NOTICE 'OK %/57 - vehicle_type asing ditolak', n;
  END;

  -- 49 · vehicle_specs_seats_car: DUA arah dari satu kesetaraan.
  --      Mobil tanpa kursi ditolak, DAN motor berkursi ditolak. Versi
  --      "mobil wajib punya kursi" saja lolos kasus kedua tanpa test merah.
  BEGIN
    INSERT INTO vehicle_specs (resource_id, owner_id, vehicle_type)
    VALUES (r_id, o1, 'car');
    RAISE EXCEPTION 'GAGAL: mobil tanpa jumlah kursi diterima';
  EXCEPTION WHEN check_violation THEN
    BEGIN
      INSERT INTO vehicle_specs (resource_id, owner_id, vehicle_type, seats)
      VALUES (r_id, o1, 'motorcycle', 2);
      RAISE EXCEPTION 'GAGAL: motor berkursi diterima';
    EXCEPTION WHEN check_violation THEN
      n := n+1; RAISE NOTICE 'OK %/57 - kursi wajib mobil DAN dilarang motor', n;
    END;
  END;

  -- 50 · vehicle_specs_clutch_moto: kopling di mobil ditolak, di motor diterima
  BEGIN
    INSERT INTO vehicle_specs (resource_id, owner_id, vehicle_type, seats, transmission)
    VALUES (r_id, o1, 'car', 7, 'clutch');
    RAISE EXCEPTION 'GAGAL: transmisi kopling pada mobil diterima';
  EXCEPTION WHEN check_violation THEN
    INSERT INTO vehicle_specs (resource_id, owner_id, vehicle_type, transmission)
    VALUES (r_id, o1, 'motorcycle', 'clutch');
    n := n+1; RAISE NOTICE 'OK %/57 - kopling ditolak di mobil, diterima di motor', n;
  END;
  DELETE FROM vehicle_specs WHERE resource_id = r_id;

  -- 51 · vehicle_specs_diesel_car: diesel di motor ditolak, di mobil diterima
  BEGIN
    INSERT INTO vehicle_specs (resource_id, owner_id, vehicle_type, fuel)
    VALUES (r_id, o1, 'motorcycle', 'diesel');
    RAISE EXCEPTION 'GAGAL: motor diesel diterima';
  EXCEPTION WHEN check_violation THEN
    INSERT INTO vehicle_specs (resource_id, owner_id, vehicle_type, seats, fuel)
    VALUES (r_id, o1, 'car', 4, 'diesel');
    n := n+1; RAISE NOTICE 'OK %/57 - diesel ditolak di motor, diterima di mobil', n;
  END;
  -- resource_id adalah PRIMARY KEY, jadi baris yang baru saja berhasil akan
  -- membuat kasus 53 melempar unique_violation, bukan foreign_key_violation --
  -- dan kasus itu akan lulus karena sebab yang salah.
  DELETE FROM vehicle_specs WHERE resource_id = r_id;

  -- 52 · vehicle_specs_seats_range: 1 dan 21 ditolak, 2 dan 20 diterima
  BEGIN
    INSERT INTO vehicle_specs (resource_id, owner_id, vehicle_type, seats)
    VALUES (r_id2, o1, 'car', 21);
    RAISE EXCEPTION 'GAGAL: 21 kursi diterima';
  EXCEPTION WHEN check_violation THEN
    INSERT INTO vehicle_specs (resource_id, owner_id, vehicle_type, seats)
    VALUES (r_id2, o1, 'car', 20);
    n := n+1; RAISE NOTICE 'OK %/57 - kursi di luar 2-20 ditolak, batasnya diterima', n;
  END;

  -- 53 · spek tidak bisa menunjuk resource pemilik lain (FK komposit)
  BEGIN
    INSERT INTO vehicle_specs (resource_id, owner_id, vehicle_type, seats)
    VALUES (r_id, o2, 'car', 4);
    RAISE EXCEPTION 'GAGAL: spek menunjuk resource pemilik lain diterima';
  EXCEPTION WHEN foreign_key_violation THEN
    n := n+1; RAISE NOTICE 'OK %/57 - spek tidak bisa menunjuk resource pemilik lain', n;
  END;

  -- 54 · detail unit tidak bisa menunjuk unit pemilik lain (FK komposit)
  -- Yang salah duluan, supaya PK-nya masih bebas dan yang dilempar benar-benar
  -- foreign_key_violation.
  BEGIN
    INSERT INTO vehicle_unit_details (resource_unit_id, owner_id) VALUES (u_id, o2);
    RAISE EXCEPTION 'GAGAL: detail menunjuk unit pemilik lain diterima';
  EXCEPTION WHEN foreign_key_violation THEN
    INSERT INTO vehicle_unit_details (resource_unit_id, owner_id) VALUES (u_id, o1);
    n := n+1; RAISE NOTICE 'OK %/57 - detail tidak bisa menunjuk unit pemilik lain', n;
  END;

  -- 55 · vehicle_unit_details_year_range: 1989 ditolak, 1990 diterima.
  --      Batas atas 2100 sengaja longgar: "tahun depan" butuh now(), dan CHECK
  --      wajib IMMUTABLE. Aplikasi yang menyempitkannya.
  DELETE FROM vehicle_unit_details WHERE resource_unit_id = u_id;
  BEGIN
    INSERT INTO vehicle_unit_details (resource_unit_id, owner_id, year)
    VALUES (u_id, o1, 1989);
    RAISE EXCEPTION 'GAGAL: tahun 1989 diterima';
  EXCEPTION WHEN check_violation THEN
    INSERT INTO vehicle_unit_details (resource_unit_id, owner_id, year)
    VALUES (u_id, o1, 1990);
    n := n+1; RAISE NOTICE 'OK %/57 - tahun di luar 1990-2100 ditolak', n;
  END;

  -- ══ BR-095 + BR-096 · teks yang dirender halaman publik apa adanya ══

  -- 56 · panjang S&K dibatasi database; teks 501 karakter ditolak
  BEGIN
    INSERT INTO resources (owner_id, terms_excludes)
    VALUES (o1, repeat('x', 501));
    RAISE EXCEPTION 'GAGAL: terms_excludes 501 karakter diterima';
  EXCEPTION WHEN check_violation THEN
    INSERT INTO resources (owner_id, terms_requirements) VALUES (o1, repeat('x', 1000));
    n := n+1; RAISE NOTICE 'OK %/57 - S&K melebihi batas ditolak, batasnya diterima', n;
  END;

  -- 57 · owners_whatsapp_format: nomor lokal ditolak, E.164 diterima, NULL bebas
  BEGIN
    INSERT INTO owners (slug, whatsapp) VALUES ('rental-wa-salah', '08123456789');
    RAISE EXCEPTION 'GAGAL: nomor format lokal diterima';
  EXCEPTION WHEN check_violation THEN
    INSERT INTO owners (slug, whatsapp) VALUES ('rental-wa-benar', '+628123456789');
    n := n+1; RAISE NOTICE 'OK %/57 - whatsapp wajib +62, NULL tetap boleh', n;
  END;

  IF n <> 57 THEN
    RAISE EXCEPTION 'GAGAL: hanya % dari 57 kasus terhitung', n;
  END IF;
  RAISE NOTICE '--- 57/57 kasus, 53 constraint 03-erd.md §3 terverifikasi ---';
END $$;

-- ══════════════════ BR-001 · isolasi pemilik ditegakkan database ══════════════════
-- Bukan constraint, tapi tinggal di 03-erd.md §3 dan mode gagalnya paling senyap:
-- ENABLE tanpa FORCE terlihat sehat sepenuhnya -- semua peran tersaring benar,
-- kecuali pemilik tabel, yang melihat segalanya. Itu peran yang menjalankan migrasi.

CREATE OR REPLACE FUNCTION enable_owner_rls(tbl regclass)
RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_name = tbl::text AND column_name = 'owner_id') THEN
    RAISE EXCEPTION 'enable_owner_rls: % tidak punya kolom owner_id', tbl;
  END IF;
  EXECUTE format('ALTER TABLE %s ENABLE ROW LEVEL SECURITY', tbl);
  EXECUTE format('ALTER TABLE %s FORCE  ROW LEVEL SECURITY', tbl);
  EXECUTE format($p$
    CREATE POLICY owner_isolation ON %s
      USING      (owner_id = NULLIF(current_setting('app.owner_id', true), '')::uuid)
      WITH CHECK (owner_id = NULLIF(current_setting('app.owner_id', true), '')::uuid)
  $p$, tbl);
END $fn$;

CREATE TABLE rls_probe (
  id       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL,
  label    text NOT NULL
);
CREATE TABLE rls_no_owner (id uuid PRIMARY KEY DEFAULT gen_random_uuid());

SELECT enable_owner_rls('rls_probe');

-- Peran non-superuser: superuser MELEWATI RLS sepenuhnya, FORCE sekalipun.
-- Menguji sebagai diri sendiri akan "lulus" secara palsu.
CREATE ROLE rls_probe_role NOLOGIN;
GRANT USAGE ON SCHEMA public TO rls_probe_role;
GRANT SELECT, INSERT ON rls_probe TO rls_probe_role;

-- Model handover_photos (03-erd.md §1): tabel anak yang ditunjuk LANGSUNG lewat id-nya
-- dari tabel lain (invoice_lines.handover_photo_id, BR-047), bukan cuma lewat induknya.
CREATE TABLE rls_child (
  id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id  uuid NOT NULL,
  parent_id uuid NOT NULL
);
SELECT enable_owner_rls('rls_child');
GRANT SELECT, INSERT ON rls_child TO rls_probe_role;

DO $$
DECLARE
  o1  uuid := '11111111-1111-1111-1111-111111111111';
  o2  uuid := '22222222-2222-2222-2222-222222222222';
  ena bool; frc bool; c int; b_child uuid;
BEGIN
  INSERT INTO rls_probe (owner_id, label) VALUES (o1, 'milik A'), (o2, 'milik B');
  INSERT INTO rls_child (owner_id, parent_id) VALUES (o2, gen_random_uuid())
    RETURNING id INTO b_child;

  -- RLS 1/6 · ENABLE *dan* FORCE, bukan salah satunya
  SELECT relrowsecurity, relforcerowsecurity INTO ena, frc
  FROM pg_class WHERE oid = 'rls_probe'::regclass;
  IF NOT ena THEN RAISE EXCEPTION 'GAGAL: RLS tidak menyala'; END IF;
  IF NOT frc THEN RAISE EXCEPTION 'GAGAL: FORCE tidak menyala - bocor ke pemilik tabel'; END IF;
  RAISE NOTICE 'OK RLS 1/6 - enable_owner_rls menyalakan ENABLE DAN FORCE';

  -- RLS 2/6 · menolak tabel tanpa owner_id
  BEGIN
    PERFORM enable_owner_rls('rls_no_owner');
    RAISE EXCEPTION 'GAGAL: tabel tanpa owner_id diterima';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'GAGAL:%' THEN RAISE; END IF;
    RAISE NOTICE 'OK RLS 2/6 - tabel tanpa owner_id ditolak';
  END;

  -- RLS 3/6 · isolasi sungguhan, dari peran non-superuser
  PERFORM set_config('app.owner_id', o1::text, true);
  EXECUTE 'SET LOCAL ROLE rls_probe_role';
  SELECT count(*) INTO c FROM rls_probe;
  EXECUTE 'RESET ROLE';
  IF c <> 1 THEN
    RAISE EXCEPTION 'GAGAL: owner A melihat % baris, seharusnya 1', c;
  END IF;
  RAISE NOTICE 'OK RLS 3/6 - owner A hanya melihat barisnya sendiri';

  -- RLS 4/6 · gagal-tertutup: tanpa owner -> NOL baris, bukan semua baris
  PERFORM set_config('app.owner_id', '', true);
  EXECUTE 'SET LOCAL ROLE rls_probe_role';
  SELECT count(*) INTO c FROM rls_probe;
  EXECUTE 'RESET ROLE';
  IF c <> 0 THEN
    RAISE EXCEPTION 'GAGAL: tanpa owner terlihat % baris, seharusnya 0', c;
  END IF;
  RAISE NOTICE 'OK RLS 4/6 - tanpa owner: nol baris (gagal-tertutup, NULLIF aman)';

  -- RLS 5/6 - WITH CHECK: MENULIS baris pemilik lain juga ditolak.
  --   USING saja TIDAK diterapkan pada INSERT. Tanpa WITH CHECK baris di bawah
  --   masuk tanpa error sedikit pun, lalu lenyap dari pandangan penulisnya karena
  --   USING menyaringnya kembali -- yang terlihat seperti "insert-nya gagal diam-diam"
  --   padahal datanya sudah ada di tabel, di bawah owner_id orang lain.
  PERFORM set_config('app.owner_id', o1::text, true);
  BEGIN
    EXECUTE 'SET LOCAL ROLE rls_probe_role';
    EXECUTE format('INSERT INTO rls_probe (owner_id, label) VALUES (%L, %L)',
                   o2, 'selundupan');
    EXECUTE 'RESET ROLE';
    RAISE EXCEPTION 'GAGAL: menulis baris ber-owner_id asing diterima - WITH CHECK hilang';
  EXCEPTION WHEN insufficient_privilege THEN
    EXECUTE 'RESET ROLE';
    RAISE NOTICE 'OK RLS 5/6 - menulis baris pemilik lain ditolak (WITH CHECK)';
  END;

  -- RLS 6/6 - tabel anak wajib punya owner_id SENDIRI.
  --   handover_photos sempat tidak punya, dengan alasan "ia cuma dijangkau lewat
  --   handovers yang sudah ber-RLS". Itu tidak benar: invoice_lines menunjuk barisnya
  --   LANGSUNG lewat handover_photo_id (BR-047), jadi satu id foto milik pemilik lain
  --   sudah cukup untuk menariknya keluar tanpa induknya pernah ikut ter-JOIN.
  PERFORM set_config('app.owner_id', o1::text, true);
  EXECUTE 'SET LOCAL ROLE rls_probe_role';
  SELECT count(*) INTO c FROM rls_child WHERE id = b_child;
  EXECUTE 'RESET ROLE';
  IF c <> 0 THEN
    RAISE EXCEPTION 'GAGAL: baris anak milik pemilik lain terbaca lewat id-nya (% baris)', c;
  END IF;
  RAISE NOTICE 'OK RLS 6/6 - baris anak milik pemilik lain tidak terbaca lewat id-nya';

  RAISE NOTICE '--- 6/6 isolasi BR-001 terverifikasi ---';
END $$;

ROLLBACK;
