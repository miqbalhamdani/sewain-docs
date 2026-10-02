-- Verifikasi 94 constraint sisa di 03-erd.md §3.
-- Anti-bentrok (BR-022) TIDAK di sini — ia punya file sendiri:
--   03-verify-overlap-constraint.sql
--
-- Jalankan di database KOSONG / scratch:
--   createdb sewain_scratch && psql sewain_scratch -f docs/03-verify-constraints.sql
-- Harapan: 92 NOTICE "OK" constraint + 6 NOTICE "OK RLS", tanpa ERROR yang
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
  deposit_settled_at    timestamptz,         -- M4, BR-049
  deleted_at            timestamptz,
  -- M2. resource_id & customer_id nullable di harness dengan alasan yang sama
  -- dengan resource_units.resource_id di atas: kasus 10-15 tidak butuh keduanya,
  -- dan FK komposit MATCH SIMPLE melewati baris ber-NULL.
  resource_id           uuid,
  customer_id           uuid,
  source                text   NOT NULL DEFAULT 'staff',
  cancelled_reason      text,
  unit_price            bigint NOT NULL DEFAULT 0,
  duration_qty          int    NOT NULL DEFAULT 1,
  subtotal              bigint NOT NULL DEFAULT 0,
  late_fee_per_unit     bigint
);

-- owner_id nullable di harness: kasus 16-19 tidak butuh, dan FK komposit
-- MATCH SIMPLE melewati baris ber-NULL -- kasus M3 di bawah yang mengisinya.
CREATE TABLE handovers (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id        uuid,
  booking_id      uuid NOT NULL,
  direction       text NOT NULL,
  performed_by    uuid,
  late_fee_waived bigint,
  waiver_reason   text
);

CREATE TABLE handover_photos (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id    uuid,
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
  customer_id     uuid,
  kind            text NOT NULL DEFAULT 'booking',
  number          text,
  status          text NOT NULL DEFAULT 'unpaid'
);

CREATE TABLE invoice_lines (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id          uuid,
  invoice_id        uuid NOT NULL,
  kind              text NOT NULL,
  amount            bigint NOT NULL,
  handover_photo_id uuid
);

CREATE TABLE payments (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id    uuid,
  invoice_id  uuid NOT NULL,
  method      text NOT NULL DEFAULT 'cash',
  amount      bigint NOT NULL DEFAULT 1,
  approved_by uuid,
  status      text NOT NULL
);

CREATE TABLE payment_proofs (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id      uuid,
  invoice_id    uuid NOT NULL,
  match_status  text,
  review_status text NOT NULL DEFAULT 'pending',
  reviewed_by   uuid,
  reviewed_at   timestamptz,
  reject_reason text,
  payment_id    uuid
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

CREATE TABLE customers (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id         uuid NOT NULL REFERENCES owners(id),
  name             text NOT NULL DEFAULT 'Penyewa',
  id_type          text,
  is_blacklisted   boolean NOT NULL DEFAULT false,
  blacklist_reason text
);

CREATE TABLE audit_logs (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id      uuid NOT NULL,
  actor_user_id uuid NOT NULL,
  action        text NOT NULL
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

-- M2 · BR-022/023/027: status asing = booking yang tidak mengunci unit.
ALTER TABLE bookings
  ADD CONSTRAINT bookings_status_valid
    CHECK (status IN ('draft', 'reserved', 'picked_up', 'returned',
                      'completed', 'cancelled', 'no_show')),
  ADD CONSTRAINT bookings_source_valid
    CHECK (source IN ('staff', 'public_page')),
  ADD CONSTRAINT bookings_cancelled_reason_valid
    CHECK ((status = 'cancelled') = (cancelled_reason IS NOT NULL)
           AND (cancelled_reason IS NULL
                OR cancelled_reason IN ('manual', 'expired', 'payment_expired')));

-- BR-014 + BR-016: snapshot mewarisi aturan sumbernya.
ALTER TABLE bookings
  ADD CONSTRAINT bookings_snapshot_valid
    CHECK (unit_price >= 0 AND duration_qty > 0 AND subtotal >= 0
           AND (deposit_amount    IS NULL OR deposit_amount    > 0)
           AND (late_fee_per_unit IS NULL OR late_fee_per_unit > 0));

-- BR-001 + BR-029: satu FK tiga kolom -- unit milik pemilik DAN milik resource-nya.
ALTER TABLE resource_units ADD CONSTRAINT resource_units_id_resource_owner_uq
  UNIQUE (id, resource_id, owner_id);
ALTER TABLE bookings ADD CONSTRAINT bookings_unit_matches_resource
  FOREIGN KEY (resource_unit_id, resource_id, owner_id)
  REFERENCES resource_units (id, resource_id, owner_id);

-- BR-001: penyewa pemilik lain tidak bisa ditunjuk.
ALTER TABLE customers ADD CONSTRAINT customers_id_owner_uq UNIQUE (id, owner_id);
ALTER TABLE bookings ADD CONSTRAINT bookings_customer_matches_owner
  FOREIGN KEY (customer_id, owner_id) REFERENCES customers (id, owner_id);

-- BR-028 + BR-085
ALTER TABLE customers
  ADD CONSTRAINT customers_id_type_valid
    CHECK (id_type IS NULL OR id_type IN ('ktp', 'sim', 'passport')),
  ADD CONSTRAINT customers_blacklist_has_reason
    CHECK (is_blacklisted = (blacklist_reason IS NOT NULL));

-- BR-085. REVOKE di 03-erd.md §3 TIDAK disalin: harness tidak punya app_user,
-- dan yang dibuktikan di sini constraint, bukan grant. Test Go yang membuktikannya.
ALTER TABLE audit_logs ADD CONSTRAINT audit_logs_actor_matches_owner
  FOREIGN KEY (actor_user_id, owner_id) REFERENCES users (id, owner_id);

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

-- M3 · BR-035/037/051/055/056/001 -- REVOKE di 03-erd.md tidak disalin (harness
-- tidak punya app_user); test Go yang membuktikannya.
ALTER TABLE handovers ADD CONSTRAINT handovers_direction_valid
  CHECK (direction IN ('pickup', 'return'));
ALTER TABLE bookings  ADD CONSTRAINT bookings_id_owner_uq  UNIQUE (id, owner_id);
ALTER TABLE handovers ADD CONSTRAINT handovers_id_owner_uq UNIQUE (id, owner_id);
ALTER TABLE handovers ADD CONSTRAINT handovers_booking_matches_owner
  FOREIGN KEY (booking_id, owner_id) REFERENCES bookings (id, owner_id);
ALTER TABLE handover_photos ADD CONSTRAINT handover_photos_id_owner_uq UNIQUE (id, owner_id);
ALTER TABLE handover_photos ADD CONSTRAINT handover_photos_handover_matches_owner
  FOREIGN KEY (handover_id, owner_id) REFERENCES handovers (id, owner_id);
ALTER TABLE handovers ADD CONSTRAINT handovers_waiver_complete
  CHECK (num_nonnulls(late_fee_waived, waiver_reason) IN (0, 2)
         AND (late_fee_waived IS NULL OR (direction = 'return' AND late_fee_waived >= 0)));
ALTER TABLE invoices ADD CONSTRAINT invoices_status_valid
  CHECK (status IN ('unpaid', 'gateway_pending', 'paid', 'overdue', 'cancelled'));
ALTER TABLE invoice_lines ADD CONSTRAINT invoice_lines_kind_valid
  CHECK (kind IN ('rent', 'deposit', 'late_fee', 'damage', 'discount'));
CREATE UNIQUE INDEX invoices_number_per_owner ON invoices (owner_id, number);
ALTER TABLE handovers ADD CONSTRAINT handovers_performer_matches_owner
  FOREIGN KEY (performed_by, owner_id) REFERENCES users (id, owner_id);
ALTER TABLE invoices ADD CONSTRAINT invoices_kind_valid
  CHECK (kind IN ('booking', 'subscription'));
ALTER TABLE invoices ADD CONSTRAINT invoices_customer_matches_owner
  FOREIGN KEY (customer_id, owner_id) REFERENCES customers (id, owner_id);
ALTER TABLE invoices ADD CONSTRAINT invoices_id_owner_uq UNIQUE (id, owner_id);
ALTER TABLE invoices ADD CONSTRAINT invoices_booking_matches_owner
  FOREIGN KEY (booking_id, owner_id) REFERENCES bookings (id, owner_id);
ALTER TABLE invoice_lines ADD CONSTRAINT invoice_lines_invoice_matches_owner
  FOREIGN KEY (invoice_id, owner_id) REFERENCES invoices (id, owner_id);
ALTER TABLE invoice_lines ADD CONSTRAINT invoice_lines_photo_matches_owner
  FOREIGN KEY (handover_photo_id, owner_id) REFERENCES handover_photos (id, owner_id);

-- M4 · BR-048/049/051/060/062
ALTER TABLE bookings
  ADD CONSTRAINT bookings_deposit_settlement
    CHECK (deposit_settled_at IS NULL
           OR (deposit_amount IS NOT NULL AND deposit_waived_at IS NULL
               AND deposit_deducted + deposit_refunded = deposit_amount)),
  ADD CONSTRAINT bookings_deposit_waived_untouched
    CHECK (deposit_waived_at IS NULL OR (deposit_deducted = 0 AND deposit_refunded = 0));
ALTER TABLE payments
  ADD CONSTRAINT payments_method_valid CHECK (method IN ('gateway', 'manual_transfer', 'cash')),
  ADD CONSTRAINT payments_status_valid CHECK (status IN ('success', 'failed')),
  ADD CONSTRAINT payments_amount_positive CHECK (amount > 0),
  ADD CONSTRAINT payments_invoice_matches_owner
    FOREIGN KEY (invoice_id, owner_id) REFERENCES invoices (id, owner_id),
  ADD CONSTRAINT payments_approver_matches_owner
    FOREIGN KEY (approved_by, owner_id) REFERENCES users (id, owner_id);
ALTER TABLE payment_proofs
  ADD CONSTRAINT payment_proofs_review_valid
    CHECK (review_status IN ('pending', 'approved', 'rejected')),
  ADD CONSTRAINT payment_proofs_match_valid
    CHECK (match_status IS NULL OR match_status IN ('match', 'mismatch', 'unreadable')),
  ADD CONSTRAINT payment_proofs_reviewed_complete
    CHECK ((review_status = 'pending') = (reviewed_at IS NULL)
           AND num_nonnulls(reviewed_by, reviewed_at) IN (0, 2)),
  ADD CONSTRAINT payment_proofs_reject_reason
    CHECK ((review_status = 'rejected') = (reject_reason IS NOT NULL)),
  ADD CONSTRAINT payment_proofs_approved_has_payment
    CHECK ((review_status = 'approved') = (payment_id IS NOT NULL)),
  ADD CONSTRAINT payment_proofs_invoice_matches_owner
    FOREIGN KEY (invoice_id, owner_id) REFERENCES invoices (id, owner_id);

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
  c_id uuid;
  h_id   uuid := gen_random_uuid();
  hp_id  uuid := gen_random_uuid();
  inv_id uuid := gen_random_uuid();
  inv2_id uuid := gen_random_uuid();
  b77    uuid := gen_random_uuid();
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
    n := n+1; RAISE NOTICE 'OK %/92 - owners_slug_unique tolak duplikat', n;
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
    n := n+1; RAISE NOTICE 'OK %/92 - owners_slug_format tolak hyphen ujung & huruf besar', n;
  END;

  -- 3 · owners_slug_format: 2 karakter ditolak (minimum 3)
  BEGIN
    INSERT INTO owners (slug) VALUES ('ab');
    RAISE EXCEPTION 'GAGAL: slug 2 karakter diterima';
  EXCEPTION WHEN check_violation THEN
    n := n+1; RAISE NOTICE 'OK %/92 - owners_slug_format tolak < 3 karakter', n;
  END;

  -- 4 · owners_slug_not_punycode: xn-- ditolak
  BEGIN
    INSERT INTO owners (slug) VALUES ('xn--80ak6aa92e');
    RAISE EXCEPTION 'GAGAL: slug punycode diterima';
  EXCEPTION WHEN check_violation THEN
    n := n+1; RAISE NOTICE 'OK %/92 - owners_slug_not_punycode tolak xn--', n;
  END;

  -- 5 · owners_slug_not_reserved
  BEGIN
    INSERT INTO owners (slug) VALUES ('api');
    RAISE EXCEPTION 'GAGAL: subdomain terlarang diterima';
  EXCEPTION WHEN check_violation THEN
    n := n+1; RAISE NOTICE 'OK %/92 - owners_slug_not_reserved tolak "api"', n;
  END;

  -- 6 · slug sah tetap diterima (constraint tidak kebablasan)
  INSERT INTO owners (slug) VALUES ('rental-budi-2021');
  n := n+1; RAISE NOTICE 'OK %/92 - slug sah tetap diterima', n;

  -- 7 · resource_units_code_per_owner: kode sama, owner sama → tolak
  INSERT INTO resource_units (owner_id, code) VALUES (o1, 'B 1234 XY');
  BEGIN
    INSERT INTO resource_units (owner_id, code) VALUES (o1, 'B 1234 XY');
    RAISE EXCEPTION 'GAGAL: kode unit ganda pada satu owner diterima';
  EXCEPTION WHEN unique_violation THEN
    n := n+1; RAISE NOTICE 'OK %/92 - kode unit unik per owner', n;
  END;

  -- 8 · owner lain boleh pakai kode yang sama
  INSERT INTO resource_units (owner_id, code) VALUES (o2, 'B 1234 XY');
  n := n+1; RAISE NOTICE 'OK %/92 - owner lain boleh kode sama', n;

  -- 9 · unit terhapus dikecualikan dari unique
  UPDATE resource_units SET deleted_at = now() WHERE owner_id = o2;
  INSERT INTO resource_units (owner_id, code) VALUES (o2, 'B 1234 XY');
  n := n+1; RAISE NOTICE 'OK %/92 - partial index kecualikan deleted_at', n;

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
    n := n+1; RAISE NOTICE 'OK %/92 - kode booking unik per owner', n;
  END;

  -- 11 · bookings_range_valid
  BEGIN
    INSERT INTO bookings (owner_id, code, resource_unit_id, start_at, end_at,
                          end_at_with_buffer, status)
    VALUES (o1, 'SWN-0002', u1, '2026-09-05 09:00+07', '2026-09-03 09:00+07',
            '2026-09-03 09:00+07', 'reserved');
    RAISE EXCEPTION 'GAGAL: end_at sebelum start_at diterima';
  EXCEPTION WHEN check_violation THEN
    n := n+1; RAISE NOTICE 'OK %/92 - bookings_range_valid', n;
  END;

  -- 12 · bookings_buffer_valid
  BEGIN
    INSERT INTO bookings (owner_id, code, resource_unit_id, start_at, end_at,
                          end_at_with_buffer, status)
    VALUES (o1, 'SWN-0003', u1, '2026-09-03 09:00+07', '2026-09-05 09:00+07',
            '2026-09-04 09:00+07', 'reserved');
    RAISE EXCEPTION 'GAGAL: end_at_with_buffer < end_at diterima';
  EXCEPTION WHEN check_violation THEN
    n := n+1; RAISE NOTICE 'OK %/92 - bookings_buffer_valid', n;
  END;

  -- 13 · bookings_deposit_nonneg: potongan > deposit ditolak
  BEGIN
    UPDATE bookings SET deposit_amount = 500000, deposit_deducted = 700000 WHERE id = b1;
    RAISE EXCEPTION 'GAGAL: deposit_deducted melebihi deposit_amount diterima';
  EXCEPTION WHEN check_violation THEN
    n := n+1; RAISE NOTICE 'OK %/92 - deposit tidak bisa dipotong lebih dari nilainya', n;
  END;

  -- 14 · deposit habis persis (= amount) harus DITERIMA
  UPDATE bookings SET deposit_amount = 500000, deposit_deducted = 500000 WHERE id = b1;
  n := n+1; RAISE NOTICE 'OK %/92 - deposit habis persis diterima', n;

  -- 15 · booking_counters FK ke owners
  BEGIN
    INSERT INTO booking_counters (owner_id) VALUES (u1);
    RAISE EXCEPTION 'GAGAL: booking_counters menerima owner_id asing';
  EXCEPTION WHEN foreign_key_violation THEN
    n := n+1; RAISE NOTICE 'OK %/92 - booking_counters FK ke owners', n;
  END;

  -- 16 · handovers_one_per_direction
  BEGIN
    INSERT INTO handovers (booking_id, direction) VALUES (b1, 'return');
    RAISE EXCEPTION 'GAGAL: dua handover arah sama pada satu booking diterima';
  EXCEPTION WHEN unique_violation THEN
    n := n+1; RAISE NOTICE 'OK %/92 - satu handover per arah per booking', n;
  END;

  -- 17 · invoices_one_subject: dua-duanya NULL ditolak
  BEGIN
    INSERT INTO invoices (owner_id) VALUES (o1);
    RAISE EXCEPTION 'GAGAL: invoice tanpa subjek diterima';
  EXCEPTION WHEN check_violation THEN
    n := n+1; RAISE NOTICE 'OK %/92 - invoices_one_subject tolak nol subjek', n;
  END;

  -- 18 · invoices_one_subject: dua-duanya terisi ditolak; lalu satu subjek diterima
  BEGIN
    INSERT INTO invoices (owner_id, booking_id, subscription_id) VALUES (o1, b1, i1);
    RAISE EXCEPTION 'GAGAL: invoice dua subjek diterima';
  EXCEPTION WHEN check_violation THEN
    INSERT INTO invoices (id, owner_id, booking_id) VALUES (i1, o1, b1);
    n := n+1; RAISE NOTICE 'OK %/92 - invoices_one_subject tolak dua subjek', n;
  END;

  -- 19 · invoice_lines_damage_needs_photo + invoice_lines_sign
  BEGIN
    INSERT INTO invoice_lines (invoice_id, kind, amount) VALUES (i1, 'damage', 500000);
    RAISE EXCEPTION 'GAGAL: baris damage tanpa foto diterima';
  EXCEPTION WHEN check_violation THEN
    INSERT INTO invoice_lines (invoice_id, kind, amount, handover_photo_id)
    VALUES (i1, 'damage', 500000, ph);
    n := n+1; RAISE NOTICE 'OK %/92 - baris damage wajib merujuk foto', n;
  END;

  BEGIN
    INSERT INTO invoice_lines (invoice_id, kind, amount) VALUES (i1, 'discount', 50000);
    RAISE EXCEPTION 'GAGAL: discount bernilai positif diterima';
  EXCEPTION WHEN check_violation THEN
    INSERT INTO invoice_lines (invoice_id, kind, amount) VALUES (i1, 'discount', -50000);
    n := n+1; RAISE NOTICE 'OK %/92 - discount wajib negatif, rent wajib positif', n;
  END;

  -- 20 · payments_one_success_per_invoice + notifications
  INSERT INTO payments (invoice_id, status) VALUES (i1, 'success');
  INSERT INTO payments (invoice_id, status) VALUES (i1, 'failed');   -- gagal boleh menumpuk
  BEGIN
    INSERT INTO payments (invoice_id, status) VALUES (i1, 'success');
    RAISE EXCEPTION 'GAGAL: dua pembayaran sukses pada satu invoice diterima';
  EXCEPTION WHEN unique_violation THEN
    n := n+1; RAISE NOTICE 'OK %/92 - satu pembayaran sukses per invoice', n;
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
    n := n+1; RAISE NOTICE 'OK %/92 - email unik global, alamat lain tetap boleh', n;
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
    n := n+1; RAISE NOTICE 'OK %/92 - refresh token wajib usaha yang sama dengan user', n;
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
    n := n+1; RAISE NOTICE 'OK %/92 - deposit_amount 0 ditolak (pakai NULL)', n;
  END;

  -- 25 · ...tapi NULL DITERIMA -- ini yang membuat "tanpa deposit" bisa ditulis
  INSERT INTO resources (owner_id, deposit_amount, late_fee_per_unit)
  VALUES (o1, NULL, NULL);
  n := n+1; RAISE NOTICE 'OK %/92 - deposit & denda NULL diterima', n;

  -- 26 · resources_late_fee_positive: 0 ditolak
  BEGIN
    INSERT INTO resources (owner_id, late_fee_per_unit) VALUES (o1, 0);
    RAISE EXCEPTION 'GAGAL: late_fee_per_unit = 0 diterima';
  EXCEPTION WHEN check_violation THEN
    n := n+1; RAISE NOTICE 'OK %/92 - late_fee_per_unit 0 ditolak', n;
  END;

  -- 27 · resources_min_duration_positive: 0 ditolak
  BEGIN
    INSERT INTO resources (owner_id, min_duration) VALUES (o1, 0);
    RAISE EXCEPTION 'GAGAL: min_duration = 0 diterima';
  EXCEPTION WHEN check_violation THEN
    n := n+1; RAISE NOTICE 'OK %/92 - min_duration 0 ditolak', n;
  END;

  -- 28 · resources_max_duration_positive: 0 ditolak
  BEGIN
    INSERT INTO resources (owner_id, max_duration) VALUES (o1, 0);
    RAISE EXCEPTION 'GAGAL: max_duration = 0 diterima';
  EXCEPTION WHEN check_violation THEN
    n := n+1; RAISE NOTICE 'OK %/92 - max_duration 0 ditolak', n;
  END;

  -- 29 · resources_duration_order: max < min ditolak; satu sisi kosong diterima
  BEGIN
    INSERT INTO resources (owner_id, min_duration, max_duration) VALUES (o1, 7, 3);
    RAISE EXCEPTION 'GAGAL: max_duration < min_duration diterima';
  EXCEPTION WHEN check_violation THEN
    INSERT INTO resources (owner_id, min_duration, max_duration) VALUES (o1, 7, NULL);
    n := n+1; RAISE NOTICE 'OK %/92 - max < min ditolak, batas sepihak diterima', n;
  END;

  -- 30 · resources_buffer_nonneg: negatif ditolak
  BEGIN
    INSERT INTO resources (owner_id, buffer_minutes) VALUES (o1, -1);
    RAISE EXCEPTION 'GAGAL: buffer_minutes negatif diterima';
  EXCEPTION WHEN check_violation THEN
    n := n+1; RAISE NOTICE 'OK %/92 - buffer_minutes negatif ditolak', n;
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
    n := n+1; RAISE NOTICE 'OK %/92 - tanpa deposit, potongan ditolak', n;
  END;

  -- 32 · bookings_deposit_waiver_complete: dibebaskan tanpa alasan ditolak
  BEGIN
    UPDATE bookings SET deposit_waived_at = now(), deposit_waived_by = u1
    WHERE id = b1;
    RAISE EXCEPTION 'GAGAL: pembebasan tanpa alasan diterima';
  EXCEPTION WHEN check_violation THEN
    n := n+1; RAISE NOTICE 'OK %/92 - pembebasan wajib berasalan', n;
  END;

  -- 33 · ...bertiga lengkap DITERIMA
  UPDATE bookings SET deposit_waived_at = now(), deposit_waived_by = u1,
                      deposit_waiver_reason = 'pelanggan lama, disepakati pemilik'
  WHERE id = b1;
  n := n+1; RAISE NOTICE 'OK %/92 - pembebasan lengkap diterima', n;

  -- ══ BR-024 · prefix kode booking milik pemilik ══
  -- Kode ini dibacakan lewat telepon. Format dijaga database supaya tidak ada
  -- pemilik yang menyimpan prefix sepanjang slug-nya lalu heran kodenya tidak
  -- bisa dibacakan.

  -- 34 · owners_booking_code_prefix_format: huruf kecil ditolak
  BEGIN
    INSERT INTO owners (slug, booking_code_prefix) VALUES ('rental-kecil', 'rb');
    RAISE EXCEPTION 'GAGAL: prefix huruf kecil diterima';
  EXCEPTION WHEN check_violation THEN
    n := n+1; RAISE NOTICE 'OK %/92 - prefix huruf kecil ditolak', n;
  END;

  -- 35 · ...lebih dari 6 karakter ditolak; 6 karakter DITERIMA
  BEGIN
    INSERT INTO owners (slug, booking_code_prefix) VALUES ('rental-tujuh', 'ABCDEFG');
    RAISE EXCEPTION 'GAGAL: prefix 7 karakter diterima';
  EXCEPTION WHEN check_violation THEN
    INSERT INTO owners (slug, booking_code_prefix) VALUES ('rental-enam', 'MTR999');
    n := n+1; RAISE NOTICE 'OK %/92 - prefix 7 karakter ditolak, 6 diterima', n;
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
    n := n+1; RAISE NOTICE 'OK %/92 - pricing_unit asing ditolak', n;
  END;

  -- 37 · ...dan yang TIDAK dikirim jatuh ke 'day', bukan NULL
  INSERT INTO resources (owner_id) VALUES (o1) RETURNING id INTO r_id;
  IF (SELECT pricing_unit FROM resources WHERE id = r_id) IS DISTINCT FROM 'day' THEN
    RAISE EXCEPTION 'GAGAL: pricing_unit tanpa nilai tidak jatuh ke day';
  END IF;
  n := n+1; RAISE NOTICE 'OK %/92 - pricing_unit default day, bukan NULL', n;

  -- 38 · owners_business_type_valid: preset asing ditolak
  BEGIN
    INSERT INTO owners (slug, business_type) VALUES ('rental-warung', 'warung');
    RAISE EXCEPTION 'GAGAL: business_type asing diterima';
  EXCEPTION WHEN check_violation THEN
    n := n+1; RAISE NOTICE 'OK %/92 - business_type asing ditolak', n;
  END;

  -- 39 · BR-025 · slug NULL diterima, dan BANYAK slug NULL tidak saling tabrakan.
  --      Tier gratis tidak punya halaman publik maupun portal penyewa, jadi kosong
  --      adalah keadaan awal setiap pemilik. Kasus ini menjaga dua hal sekaligus:
  --      keempat CHECK slug lolos saat NULL, dan unique index tidak menganggap dua
  --      NULL sebagai duplikat.
  INSERT INTO owners (slug) VALUES (NULL), (NULL);
  n := n+1; RAISE NOTICE 'OK %/92 - slug NULL diterima, dua NULL tidak tabrakan', n;

  -- ══ BR-057 · tenggat bayar & toleransi no-show ══

  -- 40 · owners_payment_due_positive: 0 jam ditolak
  BEGIN
    INSERT INTO owners (slug, payment_due_hours) VALUES ('rental-noljam', 0);
    RAISE EXCEPTION 'GAGAL: payment_due_hours = 0 diterima';
  EXCEPTION WHEN check_violation THEN
    n := n+1; RAISE NOTICE 'OK %/92 - payment_due_hours 0 ditolak', n;
  END;

  -- 41 · owners_no_show_tolerance_nonneg: negatif ditolak, tapi 0 DITERIMA
  BEGIN
    INSERT INTO owners (slug, no_show_tolerance_hours) VALUES ('rental-negatif', -1);
    RAISE EXCEPTION 'GAGAL: no_show_tolerance_hours negatif diterima';
  EXCEPTION WHEN check_violation THEN
    INSERT INTO owners (slug, no_show_tolerance_hours) VALUES ('rental-ketat', 0);
    n := n+1; RAISE NOTICE 'OK %/92 - toleransi negatif ditolak, 0 diterima', n;
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
    n := n+1; RAISE NOTICE 'OK %/92 - wamid ganda ditolak', n;
  END;

  -- 43 · ...tapi banyak NULL boleh berdampingan (belum terkirim)
  INSERT INTO notifications (booking_id, kind, scheduled_date)
  VALUES (b1, 'invoice_link', '2026-09-11'), (b1, 'payment_due_reminder', '2026-09-11');
  n := n+1; RAISE NOTICE 'OK %/92 - banyak wamid NULL berdampingan', n;

  -- ══ BR-010 + BR-013 · status katalog, dan siapa pemilik jenis barangnya ══

  -- 44 · resources_status_valid: nilai asing ditolak
  BEGIN
    INSERT INTO resources (owner_id, status) VALUES (o1, 'draft');
    RAISE EXCEPTION 'GAGAL: status resource asing diterima';
  EXCEPTION WHEN check_violation THEN
    n := n+1; RAISE NOTICE 'OK %/92 - status resource asing ditolak', n;
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
    n := n+1; RAISE NOTICE 'OK %/92 - status unit asing ditolak, ketiganya diterima', n;
  END;

  -- 46 · resource_units_resource_matches_owner: unit o2 tidak bisa menunjuk
  --      resource milik o1. r_id dibuat di kasus 37 dan milik o1.
  INSERT INTO resource_units (owner_id, resource_id, code) VALUES (o1, r_id, 'B 4 SAH');
  BEGIN
    INSERT INTO resource_units (owner_id, resource_id, code) VALUES (o2, r_id, 'B 5 CURI');
    RAISE EXCEPTION 'GAGAL: unit menunjuk resource pemilik lain diterima';
  EXCEPTION WHEN foreign_key_violation THEN
    n := n+1; RAISE NOTICE 'OK %/92 - unit tidak bisa menunjuk resource pemilik lain', n;
  END;

  -- 47 · resources_base_price_nonneg: negatif ditolak, NOL diterima.
  --      Sisi kedua yang penting: constraint '> 0' akan lolos kasus pertama dan
  --      diam-diam melarang barang pelengkap gratis.
  BEGIN
    INSERT INTO resources (owner_id, base_price) VALUES (o1, -1);
    RAISE EXCEPTION 'GAGAL: base_price negatif diterima';
  EXCEPTION WHEN check_violation THEN
    INSERT INTO resources (owner_id, base_price) VALUES (o1, 0);
    n := n+1; RAISE NOTICE 'OK %/92 - base_price negatif ditolak, 0 diterima', n;
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
    n := n+1; RAISE NOTICE 'OK %/92 - vehicle_type asing ditolak', n;
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
      n := n+1; RAISE NOTICE 'OK %/92 - kursi wajib mobil DAN dilarang motor', n;
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
    n := n+1; RAISE NOTICE 'OK %/92 - kopling ditolak di mobil, diterima di motor', n;
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
    n := n+1; RAISE NOTICE 'OK %/92 - diesel ditolak di motor, diterima di mobil', n;
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
    n := n+1; RAISE NOTICE 'OK %/92 - kursi di luar 2-20 ditolak, batasnya diterima', n;
  END;

  -- 53 · spek tidak bisa menunjuk resource pemilik lain (FK komposit)
  BEGIN
    INSERT INTO vehicle_specs (resource_id, owner_id, vehicle_type, seats)
    VALUES (r_id, o2, 'car', 4);
    RAISE EXCEPTION 'GAGAL: spek menunjuk resource pemilik lain diterima';
  EXCEPTION WHEN foreign_key_violation THEN
    n := n+1; RAISE NOTICE 'OK %/92 - spek tidak bisa menunjuk resource pemilik lain', n;
  END;

  -- 54 · detail unit tidak bisa menunjuk unit pemilik lain (FK komposit)
  -- Yang salah duluan, supaya PK-nya masih bebas dan yang dilempar benar-benar
  -- foreign_key_violation.
  BEGIN
    INSERT INTO vehicle_unit_details (resource_unit_id, owner_id) VALUES (u_id, o2);
    RAISE EXCEPTION 'GAGAL: detail menunjuk unit pemilik lain diterima';
  EXCEPTION WHEN foreign_key_violation THEN
    INSERT INTO vehicle_unit_details (resource_unit_id, owner_id) VALUES (u_id, o1);
    n := n+1; RAISE NOTICE 'OK %/92 - detail tidak bisa menunjuk unit pemilik lain', n;
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
    n := n+1; RAISE NOTICE 'OK %/92 - tahun di luar 1990-2100 ditolak', n;
  END;

  -- ══ BR-095 + BR-096 · teks yang dirender halaman publik apa adanya ══

  -- 56 · panjang S&K dibatasi database; teks 501 karakter ditolak
  BEGIN
    INSERT INTO resources (owner_id, terms_excludes)
    VALUES (o1, repeat('x', 501));
    RAISE EXCEPTION 'GAGAL: terms_excludes 501 karakter diterima';
  EXCEPTION WHEN check_violation THEN
    INSERT INTO resources (owner_id, terms_requirements) VALUES (o1, repeat('x', 1000));
    n := n+1; RAISE NOTICE 'OK %/92 - S&K melebihi batas ditolak, batasnya diterima', n;
  END;

  -- 57 · owners_whatsapp_format: nomor lokal ditolak, E.164 diterima, NULL bebas
  BEGIN
    INSERT INTO owners (slug, whatsapp) VALUES ('rental-wa-salah', '08123456789');
    RAISE EXCEPTION 'GAGAL: nomor format lokal diterima';
  EXCEPTION WHEN check_violation THEN
    INSERT INTO owners (slug, whatsapp) VALUES ('rental-wa-benar', '+628123456789');
    n := n+1; RAISE NOTICE 'OK %/92 - whatsapp wajib +62, NULL tetap boleh', n;
  END;

  -- ══ M2 · BR-022/023/027/028/029/085 · booking, penyewa, audit ══

  -- 58 · bookings_status_valid
  BEGIN
    INSERT INTO bookings (owner_id, code, resource_unit_id, start_at, end_at,
                          end_at_with_buffer, status)
    VALUES (o1, 'SWN-0058', u1, '2026-11-01 09:00+07', '2026-11-02 09:00+07',
            '2026-11-02 09:00+07', 'confirmed');
    RAISE EXCEPTION 'GAGAL: status booking asing diterima';
  EXCEPTION WHEN check_violation THEN
    n := n+1; RAISE NOTICE 'OK %/92 - status booking asing ditolak', n;
  END;

  -- 59 · bookings_source_valid
  BEGIN
    INSERT INTO bookings (owner_id, code, resource_unit_id, start_at, end_at,
                          end_at_with_buffer, status, source)
    VALUES (o1, 'SWN-0059', u1, '2026-11-01 09:00+07', '2026-11-02 09:00+07',
            '2026-11-02 09:00+07', 'reserved', 'whatsapp');
    RAISE EXCEPTION 'GAGAL: source booking asing diterima';
  EXCEPTION WHEN check_violation THEN
    n := n+1; RAISE NOTICE 'OK %/92 - source booking asing ditolak', n;
  END;

  -- 60 · bookings_cancelled_reason_valid: DUA arah, lalu yang sah diterima.
  --      Batal tanpa alasan ditolak, DAN reserved beralasan batal ditolak.
  BEGIN
    UPDATE bookings SET status = 'cancelled' WHERE id = b1;
    RAISE EXCEPTION 'GAGAL: booking batal tanpa alasan diterima';
  EXCEPTION WHEN check_violation THEN
    BEGIN
      UPDATE bookings SET cancelled_reason = 'manual' WHERE id = b1;
      RAISE EXCEPTION 'GAGAL: booking reserved beralasan batal diterima';
    EXCEPTION WHEN check_violation THEN
      UPDATE bookings SET status = 'cancelled', cancelled_reason = 'manual' WHERE id = b1;
      UPDATE bookings SET status = 'reserved', cancelled_reason = NULL WHERE id = b1;
      n := n+1; RAISE NOTICE 'OK %/92 - alasan batal terisi tepat saat cancelled', n;
    END;
  END;

  -- 61 · bookings_snapshot_valid: snapshot deposit 0 ditolak, NULL diterima
  BEGIN
    INSERT INTO bookings (owner_id, code, resource_unit_id, start_at, end_at,
                          end_at_with_buffer, status, late_fee_per_unit)
    VALUES (o1, 'SWN-0061', u1, '2026-11-01 09:00+07', '2026-11-02 09:00+07',
            '2026-11-02 09:00+07', 'draft', 0);
    RAISE EXCEPTION 'GAGAL: snapshot denda 0 diterima';
  EXCEPTION WHEN check_violation THEN
    INSERT INTO bookings (owner_id, code, resource_unit_id, start_at, end_at,
                          end_at_with_buffer, status, late_fee_per_unit)
    VALUES (o1, 'SWN-0061', u1, '2026-11-01 09:00+07', '2026-11-02 09:00+07',
            '2026-11-02 09:00+07', 'draft', NULL);
    n := n+1; RAISE NOTICE 'OK %/92 - snapshot nominal 0 ditolak, NULL diterima', n;
  END;

  -- 62 · bookings_unit_matches_resource (BR-029): unit u_id milik r_id; booking
  --      yang menulis r_id2 dengan unit itu ditolak, dengan r_id diterima.
  BEGIN
    INSERT INTO bookings (owner_id, code, resource_id, resource_unit_id, start_at,
                          end_at, end_at_with_buffer, status)
    VALUES (o1, 'SWN-0062', r_id2, u_id, '2026-11-01 09:00+07', '2026-11-02 09:00+07',
            '2026-11-02 09:00+07', 'draft');
    RAISE EXCEPTION 'GAGAL: unit dari resource lain diterima';
  EXCEPTION WHEN foreign_key_violation THEN
    INSERT INTO bookings (owner_id, code, resource_id, resource_unit_id, start_at,
                          end_at, end_at_with_buffer, status)
    VALUES (o1, 'SWN-0062', r_id, u_id, '2026-11-01 09:00+07', '2026-11-02 09:00+07',
            '2026-11-02 09:00+07', 'draft');
    n := n+1; RAISE NOTICE 'OK %/92 - unit wajib milik resource booking-nya', n;
  END;

  -- 63 · bookings_customer_matches_owner: penyewa o2 tidak bisa ditunjuk booking o1
  INSERT INTO customers (owner_id) VALUES (o2) RETURNING id INTO c_id;
  BEGIN
    INSERT INTO bookings (owner_id, code, customer_id, resource_unit_id, start_at,
                          end_at, end_at_with_buffer, status)
    VALUES (o1, 'SWN-0063', c_id, u1, '2026-11-01 09:00+07', '2026-11-02 09:00+07',
            '2026-11-02 09:00+07', 'draft');
    RAISE EXCEPTION 'GAGAL: booking menunjuk penyewa pemilik lain diterima';
  EXCEPTION WHEN foreign_key_violation THEN
    n := n+1; RAISE NOTICE 'OK %/92 - penyewa pemilik lain tidak bisa ditunjuk', n;
  END;

  -- 64 · customers_id_type_valid
  BEGIN
    INSERT INTO customers (owner_id, id_type) VALUES (o1, 'npwp');
    RAISE EXCEPTION 'GAGAL: jenis identitas asing diterima';
  EXCEPTION WHEN check_violation THEN
    n := n+1; RAISE NOTICE 'OK %/92 - jenis identitas asing ditolak', n;
  END;

  -- 65 · customers_blacklist_has_reason: DUA arah dari satu kesetaraan
  BEGIN
    INSERT INTO customers (owner_id, is_blacklisted) VALUES (o1, true);
    RAISE EXCEPTION 'GAGAL: blokir tanpa alasan diterima';
  EXCEPTION WHEN check_violation THEN
    BEGIN
      INSERT INTO customers (owner_id, blacklist_reason) VALUES (o1, 'sisa alasan');
      RAISE EXCEPTION 'GAGAL: alasan blokir tanpa blokir diterima';
    EXCEPTION WHEN check_violation THEN
      INSERT INTO customers (owner_id, is_blacklisted, blacklist_reason)
      VALUES (o1, true, 'tidak mengembalikan unit');
      n := n+1; RAISE NOTICE 'OK %/92 - blokir dan alasannya terisi bersama', n;
    END;
  END;

  -- 66 · audit_logs_actor_matches_owner: pelaku dari usaha lain ditolak
  BEGIN
    INSERT INTO audit_logs (owner_id, actor_user_id, action)
    VALUES (o2, u1, 'customer.identity.viewed');
    RAISE EXCEPTION 'GAGAL: audit dengan pelaku usaha lain diterima';
  EXCEPTION WHEN foreign_key_violation THEN
    INSERT INTO audit_logs (owner_id, actor_user_id, action)
    VALUES (o1, u1, 'customer.identity.viewed');
    n := n+1; RAISE NOTICE 'OK %/92 - pelaku audit wajib dari usaha yang sama', n;
  END;

  -- ══ M3 · serah-terima dan invoice ══
  -- b1 milik o1 (kasus 10). Fixture: satu handover + foto ber-owner_id.

  -- 67 · handovers_direction_valid
  BEGIN
    INSERT INTO handovers (owner_id, booking_id, direction) VALUES (o1, b1, 'ambil');
    RAISE EXCEPTION 'GAGAL: arah handover asing diterima';
  EXCEPTION WHEN check_violation THEN
    n := n+1; RAISE NOTICE 'OK %/92 - arah handover asing ditolak', n;
  END;

  -- 68 · handovers_booking_matches_owner: handover o2 atas booking o1 ditolak
  BEGIN
    INSERT INTO handovers (owner_id, booking_id, direction) VALUES (o2, b1, 'pickup');
    RAISE EXCEPTION 'GAGAL: handover menunjuk booking pemilik lain diterima';
  EXCEPTION WHEN foreign_key_violation THEN
    INSERT INTO handovers (id, owner_id, booking_id, direction) VALUES (h_id, o1, b1, 'pickup');
    n := n+1; RAISE NOTICE 'OK %/92 - handover wajib milik pemilik booking-nya', n;
  END;

  -- 69 · handover_photos_handover_matches_owner
  BEGIN
    INSERT INTO handover_photos (owner_id, handover_id) VALUES (o2, h_id);
    RAISE EXCEPTION 'GAGAL: foto menunjuk handover pemilik lain diterima';
  EXCEPTION WHEN foreign_key_violation THEN
    INSERT INTO handover_photos (id, owner_id, handover_id) VALUES (hp_id, o1, h_id);
    n := n+1; RAISE NOTICE 'OK %/92 - foto wajib milik pemilik handover-nya', n;
  END;

  -- 70 · handovers_waiver_complete: DUA arah -- jumlah tanpa alasan ditolak, dan
  --      pembebasan di handover AMBIL ditolak (denda hanya ada saat kembali).
  BEGIN
    INSERT INTO handovers (booking_id, direction, late_fee_waived) VALUES (gen_random_uuid(), 'return', 100000);
    RAISE EXCEPTION 'GAGAL: pembebasan tanpa alasan diterima';
  EXCEPTION WHEN check_violation THEN
    BEGIN
      INSERT INTO handovers (booking_id, direction, late_fee_waived, waiver_reason)
      VALUES (gen_random_uuid(), 'pickup', 1, 'x');
      RAISE EXCEPTION 'GAGAL: pembebasan di handover ambil diterima';
    EXCEPTION WHEN check_violation THEN
      n := n+1; RAISE NOTICE 'OK %/92 - pembebasan berpasangan alasan, hanya saat kembali', n;
    END;
  END;

  -- 71 · invoices_status_valid
  BEGIN
    INSERT INTO invoices (owner_id, booking_id, status) VALUES (o1, b1, 'lunas');
    RAISE EXCEPTION 'GAGAL: status invoice asing diterima';
  EXCEPTION WHEN check_violation THEN
    n := n+1; RAISE NOTICE 'OK %/92 - status invoice asing ditolak', n;
  END;

  -- 72 · invoice_lines_kind_valid
  BEGIN
    INSERT INTO invoice_lines (invoice_id, kind, amount) VALUES (i1, 'tip', 1);
    RAISE EXCEPTION 'GAGAL: jenis baris asing diterima';
  EXCEPTION WHEN check_violation THEN
    n := n+1; RAISE NOTICE 'OK %/92 - jenis baris invoice asing ditolak', n;
  END;

  -- 73 · invoices_number_per_owner: ganda di satu pemilik ditolak, pemilik lain boleh
  INSERT INTO invoices (owner_id, booking_id, number) VALUES (o1, b1, 'SWN-0001/1');
  BEGIN
    INSERT INTO invoices (owner_id, booking_id, number) VALUES (o1, b1, 'SWN-0001/1');
    RAISE EXCEPTION 'GAGAL: nomor invoice ganda diterima';
  EXCEPTION WHEN unique_violation THEN
    INSERT INTO invoices (owner_id, subscription_id, number) VALUES (o2, i1, 'SWN-0001/1');
    n := n+1; RAISE NOTICE 'OK %/92 - nomor invoice unik per pemilik', n;
  END;

  -- 74 · invoices_booking_matches_owner
  BEGIN
    INSERT INTO invoices (owner_id, booking_id) VALUES (o2, b1);
    RAISE EXCEPTION 'GAGAL: invoice menunjuk booking pemilik lain diterima';
  EXCEPTION WHEN foreign_key_violation THEN
    INSERT INTO invoices (id, owner_id, booking_id) VALUES (inv_id, o1, b1);
    n := n+1; RAISE NOTICE 'OK %/92 - invoice wajib milik pemilik booking-nya', n;
  END;

  -- 75 · invoice_lines_invoice_matches_owner
  BEGIN
    INSERT INTO invoice_lines (owner_id, invoice_id, kind, amount) VALUES (o2, inv_id, 'rent', 1);
    RAISE EXCEPTION 'GAGAL: baris menunjuk invoice pemilik lain diterima';
  EXCEPTION WHEN foreign_key_violation THEN
    n := n+1; RAISE NOTICE 'OK %/92 - baris wajib milik pemilik invoice-nya', n;
  END;

  -- 76 · invoice_lines_photo_matches_owner: damage o1 yang menunjuk foto lewat
  --      owner_id lain ditolak; dengan pemiliknya sendiri diterima.
  BEGIN
    INSERT INTO invoices (id, owner_id, subscription_id) VALUES (inv2_id, o2, i1);
    INSERT INTO invoice_lines (owner_id, invoice_id, kind, amount, handover_photo_id)
    VALUES (o2, inv2_id, 'damage', 1, hp_id);
    RAISE EXCEPTION 'GAGAL: damage menunjuk foto pemilik lain diterima';
  EXCEPTION WHEN foreign_key_violation THEN
    INSERT INTO invoice_lines (owner_id, invoice_id, kind, amount, handover_photo_id)
    VALUES (o1, inv_id, 'damage', 1, hp_id);
    n := n+1; RAISE NOTICE 'OK %/92 - damage hanya menunjuk foto pemilik sendiri', n;
  END;

  -- 77 · handovers_performer_matches_owner: petugas usaha lain ditolak.
  --      Booking sendiri: b1 sudah punya handover dua arah, dan unique index
  --      one_per_direction akan menolak lebih dulu -- membuktikan hal yang salah.
  INSERT INTO bookings (id, owner_id, code, resource_unit_id, start_at, end_at,
                        end_at_with_buffer, status)
  VALUES (b77, o1, 'SWN-0077', u1, '2026-12-01 09:00+07', '2026-12-02 09:00+07',
          '2026-12-02 09:00+07', 'draft');
  BEGIN
    INSERT INTO handovers (owner_id, booking_id, direction, performed_by) VALUES (o1, b77, 'pickup', gen_random_uuid());
    RAISE EXCEPTION 'GAGAL: handover dengan petugas asing diterima';
  EXCEPTION WHEN foreign_key_violation THEN
    n := n+1; RAISE NOTICE 'OK %/92 - petugas serah-terima wajib dari usaha yang sama', n;
  END;

  -- 78 · invoices_kind_valid
  BEGIN
    INSERT INTO invoices (owner_id, booking_id, kind) VALUES (o1, b1, 'sewa');
    RAISE EXCEPTION 'GAGAL: jenis invoice asing diterima';
  EXCEPTION WHEN check_violation THEN
    n := n+1; RAISE NOTICE 'OK %/92 - jenis invoice asing ditolak', n;
  END;

  -- 79 · invoices_customer_matches_owner: c_id milik o2 (kasus 63)
  BEGIN
    INSERT INTO invoices (owner_id, booking_id, customer_id) VALUES (o1, b1, c_id);
    RAISE EXCEPTION 'GAGAL: invoice menunjuk penyewa pemilik lain diterima';
  EXCEPTION WHEN foreign_key_violation THEN
    n := n+1; RAISE NOTICE 'OK %/92 - penyewa invoice wajib dari usaha yang sama', n;
  END;

  -- ══ M4 · deposit, pembayaran, bukti transfer ══
  -- b1 milik o1: deposit_amount 500000, deducted 500000 (kasus 14). inv_id milik o1 (kasus 74).

  -- 80 · bookings_deposit_settlement: diselesaikan wajib potong + kembali = deposit
  BEGIN
    UPDATE bookings SET deposit_settled_at = now(), deposit_refunded = 100 WHERE id = b1;
    RAISE EXCEPTION 'GAGAL: penyelesaian yang tidak genap diterima';
  EXCEPTION WHEN check_violation THEN
    UPDATE bookings SET deposit_settled_at = now() WHERE id = b1;
    UPDATE bookings SET deposit_settled_at = NULL WHERE id = b1;
    n := n+1; RAISE NOTICE 'OK %/92 - penyelesaian deposit wajib genap', n;
  END;

  -- 81 · bookings_deposit_waived_untouched: deposit dibebaskan tidak bisa dikembalikan
  UPDATE bookings SET deposit_deducted = 0 WHERE id = b1;
  BEGIN
    UPDATE bookings SET deposit_waived_at = now(), deposit_waived_by = u1,
           deposit_waiver_reason = 'pelanggan tetap', deposit_refunded = 1 WHERE id = b1;
    RAISE EXCEPTION 'GAGAL: deposit dibebaskan sekaligus dikembalikan diterima';
  EXCEPTION WHEN check_violation THEN
    n := n+1; RAISE NOTICE 'OK %/92 - deposit dibebaskan tidak punya potongan/pengembalian', n;
  END;

  -- 82 · payments_method_valid
  BEGIN
    INSERT INTO payments (invoice_id, status, method) VALUES (i1, 'failed', 'qris');
    RAISE EXCEPTION 'GAGAL: metode bayar asing diterima';
  EXCEPTION WHEN check_violation THEN
    n := n+1; RAISE NOTICE 'OK %/92 - metode bayar asing ditolak', n;
  END;

  -- 83 · payments_status_valid
  BEGIN
    INSERT INTO payments (invoice_id, status) VALUES (i1, 'pending');
    RAISE EXCEPTION 'GAGAL: status bayar asing diterima';
  EXCEPTION WHEN check_violation THEN
    n := n+1; RAISE NOTICE 'OK %/92 - status bayar asing ditolak', n;
  END;

  -- 84 · payments_amount_positive
  BEGIN
    INSERT INTO payments (invoice_id, status, amount) VALUES (i1, 'failed', 0);
    RAISE EXCEPTION 'GAGAL: pembayaran nol diterima';
  EXCEPTION WHEN check_violation THEN
    n := n+1; RAISE NOTICE 'OK %/92 - pembayaran wajib positif', n;
  END;

  -- 85 · payments_invoice_matches_owner
  BEGIN
    INSERT INTO payments (owner_id, invoice_id, status) VALUES (o2, inv_id, 'failed');
    RAISE EXCEPTION 'GAGAL: pembayaran atas invoice pemilik lain diterima';
  EXCEPTION WHEN foreign_key_violation THEN
    n := n+1; RAISE NOTICE 'OK %/92 - pembayaran wajib milik pemilik invoice-nya', n;
  END;

  -- 86 · payments_approver_matches_owner: u1 milik o1, invoice o1 -- pemberi
  --      persetujuan pemilik lain ditolak lewat pasangan (approved_by, owner_id)
  BEGIN
    INSERT INTO payments (owner_id, invoice_id, status, approved_by)
    VALUES (o1, inv_id, 'failed', gen_random_uuid());
    RAISE EXCEPTION 'GAGAL: penyetuju asing diterima';
  EXCEPTION WHEN foreign_key_violation THEN
    n := n+1; RAISE NOTICE 'OK %/92 - penyetuju wajib dari usaha yang sama', n;
  END;

  -- 87 · payment_proofs_review_valid
  BEGIN
    INSERT INTO payment_proofs (invoice_id, review_status) VALUES (inv_id, 'lunas');
    RAISE EXCEPTION 'GAGAL: status review asing diterima';
  EXCEPTION WHEN check_violation THEN
    n := n+1; RAISE NOTICE 'OK %/92 - status review asing ditolak', n;
  END;

  -- 88 · payment_proofs_match_valid: asing ditolak, NULL (belum dibaca) diterima
  BEGIN
    INSERT INTO payment_proofs (invoice_id, match_status) VALUES (inv_id, 'cocok');
    RAISE EXCEPTION 'GAGAL: hasil baca asing diterima';
  EXCEPTION WHEN check_violation THEN
    INSERT INTO payment_proofs (invoice_id) VALUES (inv_id);
    n := n+1; RAISE NOTICE 'OK %/92 - hasil baca asing ditolak, belum dibaca boleh', n;
  END;

  -- 89 · payment_proofs_reviewed_complete: direview tanpa siapa/kapan ditolak
  BEGIN
    INSERT INTO payment_proofs (invoice_id, review_status, reject_reason) VALUES (inv_id, 'rejected', 'buram');
    RAISE EXCEPTION 'GAGAL: review tanpa pelaku diterima';
  EXCEPTION WHEN check_violation THEN
    n := n+1; RAISE NOTICE 'OK %/92 - review wajib punya pelaku dan waktu', n;
  END;

  -- 90 · payment_proofs_reject_reason: DUA arah
  BEGIN
    INSERT INTO payment_proofs (invoice_id, review_status, reviewed_by, reviewed_at)
    VALUES (inv_id, 'rejected', u1, now());
    RAISE EXCEPTION 'GAGAL: penolakan tanpa alasan diterima';
  EXCEPTION WHEN check_violation THEN
    BEGIN
      INSERT INTO payment_proofs (invoice_id, reject_reason) VALUES (inv_id, 'sisa');
      RAISE EXCEPTION 'GAGAL: alasan tolak pada bukti pending diterima';
    EXCEPTION WHEN check_violation THEN
      n := n+1; RAISE NOTICE 'OK %/92 - alasan tolak tepat saat ditolak', n;
    END;
  END;

  -- 91 · payment_proofs_approved_has_payment: disetujui wajib punya pembayarannya
  BEGIN
    INSERT INTO payment_proofs (invoice_id, review_status, reviewed_by, reviewed_at)
    VALUES (inv_id, 'approved', u1, now());
    RAISE EXCEPTION 'GAGAL: bukti disetujui tanpa pembayaran diterima';
  EXCEPTION WHEN check_violation THEN
    n := n+1; RAISE NOTICE 'OK %/92 - bukti disetujui wajib menunjuk pembayaran', n;
  END;

  -- 92 · payment_proofs_invoice_matches_owner
  BEGIN
    INSERT INTO payment_proofs (owner_id, invoice_id) VALUES (o2, inv_id);
    RAISE EXCEPTION 'GAGAL: bukti atas invoice pemilik lain diterima';
  EXCEPTION WHEN foreign_key_violation THEN
    n := n+1; RAISE NOTICE 'OK %/92 - bukti wajib milik pemilik invoice-nya', n;
  END;

  IF n <> 92 THEN
    RAISE EXCEPTION 'GAGAL: hanya % dari 92 kasus terhitung', n;
  END IF;
  RAISE NOTICE '--- 92/92 kasus, 94 constraint 03-erd.md §3 terverifikasi ---';
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
