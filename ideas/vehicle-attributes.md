# Atribut Kendaraan (Mobil & Motor) — Fase 1

> **Status:** Ide, belum masuk backlog · **Tanggal:** 2026-09-28
> **Terkait:** PRD §6.2–6.5, BR-001/011/012/014/016/017/046/057, `03-erd.md` (`resources`, `resource_units`, `owners`, `handovers`)
> **Cakupan:** khusus `business_type = 'vehicle_rental'` (mobil & motor). Equipment
> (kamera, HP), boarding house/apartemen, dan venue punya atributnya sendiri. Tabel
> spek di sini **tidak** dipakai mereka.

## Problem Statement

Bagaimana memberi juragan rental mobil/motor data kendaraan secukupnya, supaya
**penyewa tidak perlu bertanya lewat WA sebelum booking**, tanpa mengubah form
katalog jadi form STNK 30 kolom?

## Recommended Direction

Data dibagi menjadi **atribut generik**, yang dipakai semua vertikal, dan **atribut
kendaraan**, yang hanya dipakai `vehicle_rental`:

| | Generik: kolom di tabel yang sudah ada | Khusus kendaraan: tabel pendamping 1:1 |
|---|---|---|
| **Model** | `resources`: nama, foto, harga, deskripsi, S&K | `vehicle_specs`: jenis, transmisi, kursi, BBM |
| **Unit fisik** | `resource_units`: plat/kode, label, odometer, status | `vehicle_unit_details`: tahun, warna, pajak, STNK |
| **Usaha** | `owners`: WA, alamat, jam operasional | — |

Atribut kendaraan ditaruh di **tabel pendamping**, bukan di `resources` dan bukan di `jsonb`. Alasannya:

- **`resources` tetap generik.** Kamera, kos, atau lapangan tidak mewarisi kolom `transmission` yang selalu kosong. Vertikal berikutnya nanti menambah tabel pendampingnya sendiri (misalnya `equipment_specs`) tanpa menyentuh tabel inti.
- **Aturan ditegakkan database.** Nilai transmisi, rentang kursi, "kopling hanya untuk motor", dan "mobil wajib punya jumlah kursi" semuanya bisa jadi `CHECK`. Semangatnya sama dengan BR-012 (*"ditegakkan database, bukan cuma didaftar di sini"*). Dengan `jsonb`, aturan-aturan ini hanya hidup di aplikasi.
- **Migrasi tetap diperlukan per vertikal, dan itu memang wajar.** Vertikal baru tetap butuh form, placeholder, dan halaman publik baru. Migrasi satu tabel pendamping adalah bagian terkecil dari pekerjaan itu.

**Hanya yang sering dibandingkan penyewa yang dibuat terstruktur**: transmisi, kursi,
dan BBM. Semua isian lainnya berupa teks dengan **placeholder per jenis kendaraan**
yang diawali "Contoh:". Tombol **"Pakai contoh"** menyalin placeholder menjadi isi
sungguhan, jadi juragan tinggal mengganti angkanya.

Preset tetap satu, `vehicle_rental`, dan juragan memilih jenis Mobil/Motor per
resource. Dengan begitu, rental yang menyewakan mobil dan motor sekaligus tetap bisa
memakai satu akun.

Aturan yang menjaga halaman publik tetap jujur: **apa pun yang dihitung sistem tidak
boleh diketik ulang oleh juragan.** "1 hari = 24 jam", batas bayar, denda telat, dan
toleransi no-show ditampilkan sebagai kalimat buatan sistem dari kolom yang sudah
ada. Teks S&K hanya dipakai untuk hal yang tidak dijalankan sistem (refund,
reschedule, ongkir, BBM), dan juragan sendiri yang mengeksekusinya secara manual.

## Daftar Input

Legenda: ✅ kolom sudah ada · ➕ baru · 🔒 dihitung sistem · ⏸ ditunda

### 1. Model — `resources` (generik) + `vehicle_specs` (kendaraan)

| Input | Kolom | Model input | Nilai / validasi | Rekomendasi |
|---|---|---|---|---|
| Jenis kendaraan | ➕ `vehicle_specs.vehicle_type` | Radio | `car` / `motorcycle` | **Wajib**. Menentukan field, placeholder, dan checklist |
| Nama model | ✅ `resources.name` | Teks | "Avanza 1.3 G", tanpa tahun | **Wajib** |
| Foto | ✅ `resources.images` | Upload multi | minimal 1 | **Wajib** |
| Transmisi | ➕ `vehicle_specs.transmission` | Segmented radio | Mobil: `manual`/`automatic` · Motor: + `clutch` (kopling) | **Wajib** |
| Jumlah kursi | ➕ `vehicle_specs.seats` | Stepper | 2–20, hanya mobil | **Wajib** (mobil) |
| BBM | ➕ `vehicle_specs.fuel` | Dropdown | `gasoline`/`diesel`/`hybrid`/`electric`. Motor tanpa `diesel` | **Wajib** |
| Deskripsi (fitur & perlengkapan) | ✅ `resources.description` (dikembalikan) | Textarea + placeholder + "Pakai contoh" | maks. 500 karakter | Opsional |

`resources.category` diisi server dengan nilai yang sama seperti `vehicle_type`, dengan
pola yang sama seperti `pricing_unit` (BR-017 aturan 1). Tujuannya supaya daftar
resource generik tetap bisa dikelompokkan tanpa join. Sumber kebenarannya tetap
`vehicle_type`.

`description` dulu dihapus dengan syarat *"tambahkan kembali ketika ada layar yang
menampilkannya"* (`03-erd.md:754`). Halaman publik akan menampilkannya, jadi syarat
itu sekarang terpenuhi.

### 2. Unit fisik — `resource_units` (generik) + `vehicle_unit_details` (kendaraan)

| Input | Kolom | Model input | Nilai / validasi | Rekomendasi |
|---|---|---|---|---|
| Plat nomor | ✅ `resource_units.code` | Teks, otomatis huruf besar | unik per owner (BR-011) | **Wajib** |
| Nama panggilan | ✅ `resource_units.label` | Teks | "Avanza Putih" | Opsional |
| Odometer | ✅ `resource_units.meter_value` | Angka (km) | ≥ 0 | Opsional |
| Status | ✅ `resource_units.status` | Dropdown | active/maintenance/retired | Default active |
| Catatan kondisi | ✅ `resource_units.condition_notes` | Textarea | — | Opsional |
| Tahun | ➕ `vehicle_unit_details.year` | Dropdown | 1990 s.d. tahun depan | **Wajib** |
| Warna | ➕ `vehicle_unit_details.color` | Dropdown + Lainnya | Putih, Hitam, Silver, … | Opsional |
| Pajak tahunan jatuh tempo | ➕ `vehicle_unit_details.tax_due_on` | Date picker | hanya dilihat juragan | Opsional |
| STNK berlaku s.d. | ➕ `vehicle_unit_details.registration_valid_until` | Date picker | hanya dilihat juragan | Opsional |

### 3. Skema tabel pendamping

```sql
CREATE TABLE vehicle_specs (
  resource_id  uuid PRIMARY KEY,
  owner_id     uuid NOT NULL,
  vehicle_type text NOT NULL CHECK (vehicle_type IN ('car', 'motorcycle')),
  transmission text NOT NULL CHECK (transmission IN ('manual', 'automatic', 'clutch')),
  seats        int  CHECK (seats BETWEEN 2 AND 20),
  fuel         text NOT NULL CHECK (fuel IN ('gasoline', 'diesel', 'hybrid', 'electric')),
  FOREIGN KEY (resource_id, owner_id) REFERENCES resources (id, owner_id) ON DELETE CASCADE,
  CONSTRAINT vehicle_specs_seats_car   CHECK ((vehicle_type = 'car') = (seats IS NOT NULL)),
  CONSTRAINT vehicle_specs_clutch_moto CHECK (transmission <> 'clutch' OR vehicle_type = 'motorcycle'),
  CONSTRAINT vehicle_specs_diesel_car  CHECK (fuel <> 'diesel' OR vehicle_type = 'car')
);

CREATE TABLE vehicle_unit_details (
  resource_unit_id         uuid PRIMARY KEY,
  owner_id                 uuid NOT NULL,
  year                     int  NOT NULL CHECK (year BETWEEN 1990 AND 2100),
  color                    text,
  tax_due_on               date,
  registration_valid_until date,
  FOREIGN KEY (resource_unit_id, owner_id) REFERENCES resource_units (id, owner_id) ON DELETE CASCADE
);

SELECT enable_owner_rls('vehicle_specs');
SELECT enable_owner_rls('vehicle_unit_details');
```

- **Isolasi tenant mengikuti pola yang sudah ada.** Setiap tabel punya `owner_id` dan RLS `owner_isolation` (BR-001), serta FK komposit `(id, owner_id)`, dengan pola yang sama seperti `resource_units_resource_matches_owner`. Konsekuensinya, `resource_units` perlu `UNIQUE (id, owner_id)` kalau belum ada.
- **Kewajiban 1:1 dijaga aplikasi.** Resource `vehicle_rental` wajib punya baris `vehicle_specs`, dan database tidak bisa menegakkan "child wajib ada" dengan murah. Karena itu, service membuat `resources` dan `vehicle_specs` dalam **satu transaksi**. Hal yang sama berlaku untuk unit dan `vehicle_unit_details`.
- **Batas atas `year`** sengaja longgar. "Tahun depan" divalidasi aplikasi, karena `CHECK` tidak boleh memakai `now()`.
- **Pilihan transmisi dan BBM berupa `CHECK`, bukan tabel referensi.** Nilainya jarang berubah dan tidak diisi tenant. Tabel lookup baru layak dibuat kalau juragan boleh menambah nilainya sendiri.

### 4. Harga — `resources` (semua sudah ada)

`base_price` (wajib), `deposit_amount`, `late_fee_per_unit`, `min_duration`/`max_duration`,
`buffer_minutes`, dan `requires_id_verification`. `pricing_unit` 🔒 diisi server (BR-017).

### 5. Syarat & ketentuan — `resources` (generik)

**5a. Durasi & tenggat** 🔒 berupa kalimat otomatis dan tidak bisa diedit:

| Kalimat | Sumber |
|---|---|
| "1 hari = 24 jam" | `pricing_unit` |
| "Bayar paling lambat X jam, atau booking batal otomatis" | `owners.payment_due_hours` (BR-057) |
| "Telat kembali dikenakan Rp X per hari" | `late_fee_per_unit` |
| "Tidak datang lewat X jam dari jadwal = batal" | `owners.no_show_tolerance_hours` |

**5b–5d. Tiga textarea dari juragan.** Semuanya opsional. Bagian yang kosong tidak ditampilkan di halaman publik.

| Bagian | Kolom | Model input | Rekomendasi |
|---|---|---|---|
| Belum termasuk | ➕ `resources.terms_excludes text` | Textarea + placeholder + "Pakai contoh" | Opsional, maks. 500 karakter |
| Syarat sewa | ➕ `resources.terms_requirements text` | Textarea + placeholder + "Pakai contoh" | Opsional, maks. 1000 karakter |
| Pembatalan & perubahan | ➕ `resources.terms_cancellation text` | Textarea + placeholder + "Pakai contoh" | Opsional, maks. 1000 karakter |

S&K dan `description` sengaja tinggal di `resources`. Kos, lapangan, dan kamera juga
punya syarat dan kebijakan pembatalan, dan yang membedakan hanya placeholder-nya.

Form menyediakan tombol **"Salin S&K dari resource lain"**, karena S&K diisi per resource.

### 6. Placeholder per jenis kendaraan

| Field | Mobil | Motor |
|---|---|---|
| Deskripsi | Contoh: AC dingin, charger HP, audio Bluetooth, kartu e-Toll (saldo isi sendiri), air mineral gratis. Ban serep & dongkrak tersedia. | Contoh: 2 helm SNI, 2 jas hujan, holder HP, charger USB, box bagasi. |
| Belum termasuk | Contoh: Harga belum termasuk BBM, tol, dan parkir. BBM dikembalikan sama seperti saat diambil. | Contoh: Harga belum termasuk BBM dan parkir. BBM dikembalikan sama seperti saat diambil. |
| Syarat sewa | Contoh: KTP & SIM A asli penyewa. KTP asli ditinggal sebagai jaminan. Usia minimal 21 tahun. Boleh ke luar kota dengan izin. Antar-jemput dalam kota Rp 50.000. | Contoh: KTP & SIM C asli penyewa. KTP asli ditinggal sebagai jaminan. Hanya dalam kota. Antar-jemput Rp 20.000. |
| Pembatalan & perubahan | Contoh: Batal H-3 refund 100%, H-1 refund 50%, hari-H tanpa refund. Reschedule gratis 1× paling lambat H-1, selama unit tersedia. | (sama) |

Placeholder dan template checklist disimpan sebagai **konstanta di kode per jenis
kendaraan**, bukan data tenant. Semangatnya sama dengan BR-017 aturan 4.

### 7. Template checklist serah-terima — konstanta per jenis kendaraan

| Jenis | Isian default `handovers.checklist` |
|---|---|
| Mobil | BBM, ban serep, dongkrak, STNK |
| Motor | BBM, helm (jumlah), jas hujan (jumlah), STNK |

Operator mengisi jumlah dan kondisinya saat serah-terima. Juragan tidak mengisi apa pun di form resource.

### 8. Profil usaha — `owners` (generik)

| Input | Kolom | Model input | Rekomendasi |
|---|---|---|---|
| Nama usaha | ✅ `name` | Teks | **Wajib** |
| WhatsApp | ➕ `whatsapp` | Telepon, format +62 | **Wajib** |
| Alamat usaha | ➕ `address` | Textarea | **Wajib**. Lokasi ambil default, kecuali ditulis lain di Syarat sewa |
| Jam operasional | ➕ `operating_hours` | Teks | Opsional |

## Key Assumptions to Validate

- [ ] **Placeholder + "Pakai contoh" cukup untuk membuat juragan mengisi S&K.** Uji: persentase resource aktif dengan ketiga S&K terisi. Kalau di bawah 50%, S&K kemungkinan perlu dibuat terstruktur.
- [ ] **S&K cukup di level resource tanpa default dari owner.** Uji: hitung berapa kali "Salin S&K" dipakai. Kalau hampir selalu dipakai, S&K seharusnya punya default di owner.
- [ ] **Sewa lepas kunci selalu 24 jam; paket 12 jam hanya lazim untuk sewa dengan sopir.** Uji: tanyakan pola booking ke 3 pemilik sebelum M2 (PRD:902).
- [ ] **Halaman S&K benar-benar mengurangi chat WA.** Uji: minta juragan menghitung pertanyaan WA pra-booking selama 2 minggu, sebelum dan sesudah halaman aktif.
- [ ] **Denda telat per hari sudah cukup.** Rental Indonesia sering memakai overtime per jam. Uji: wawancara bersama poin 12 jam.

## MVP Scope

**Masuk:**
- Tabel baru `vehicle_specs` dan `vehicle_unit_details` (§3), dengan RLS dan FK komposit.
- `resources`: `description` dikembalikan, serta `terms_excludes`, `terms_requirements`, `terms_cancellation`.
- `owners`: `whatsapp`, `address`, `operating_hours`.
- Service yang membuat resource + `vehicle_specs` (dan unit + `vehicle_unit_details`) dalam satu transaksi.
- Form resource yang field spek dan placeholder-nya mengikuti jenis kendaraan, dengan tombol "Pakai contoh" dan "Salin S&K dari resource lain".
- Halaman publik: kartu spek (transmisi, kursi, BBM, tahun, warna), deskripsi, blok S&K (5a dibuat sistem, 5b–5d dari juragan), dan tombol WA.
- Template `handovers.checklist` per jenis kendaraan sebagai konstanta.
- Test di `03-verify-constraints.sql` untuk ketiga `CHECK` lintas kolom dan isolasi RLS kedua tabel baru.

Per kendaraan hanya ada 9 input wajib (jenis, nama, foto, transmisi, kursi, BBM,
harga, plat, tahun), ditambah 2 di profil usaha (WA, alamat) yang cukup diisi sekali.

## Not Doing (and Why)

- **Kolom kendaraan langsung di `resources`**: vertikal lain akan mewarisi kolom yang selalu kosong. Diganti dengan tabel pendamping.
- **Spek kendaraan di `jsonb`**: aturan seperti "kopling hanya motor" dan "mobil wajib punya kursi" tidak bisa ditegakkan database.
- **Tabel referensi (lookup) untuk transmisi/BBM**: nilainya tetap dan tidak diisi tenant. `CHECK` sudah cukup.
- **Memecah preset jadi Rental Mobil / Rental Motor**: rental yang menyewakan keduanya harus tetap muat di satu akun. Radio jenis kendaraan cukup satu klik.
- **Fitur & perlengkapan terstruktur (chip, `{name, qty}`)**: satu textarea deskripsi dengan placeholder sudah cukup. Jumlah helm/jas hujan dicatat di checklist serah-terima.
- **S&K per butir (dokumen, jaminan, usia, luar kota, antar-jemput, kebijakan BBM)**: terlalu banyak input. Tiga textarea dengan placeholder sudah menjawab pertanyaan WA yang sama.
- **Paket 12 jam / `day_length_hours`**: mengubah `duration_qty`, denda, dan snapshot. Ditunda sampai ada bukti dari wawancara.
- **Refund & reschedule otomatis**: kebijakan refund memang dijadwalkan di fase 2 (PRD:776). Untuk sekarang cukup teks, dan juragan mengeksekusi manual.
- **Ongkir antar masuk tagihan**: belum ada jenis baris invoice untuk ongkir. Teks sudah cukup.
- **cc motor**: dihapus atas keputusan produk.
- **Katalog master model kendaraan**: butuh satu tim sendiri untuk merawat datanya.
- **Pengingat otomatis pajak/STNK dan jadwal servis**: kolom tanggalnya disiapkan, notifikasinya belum.
- **Foto per unit**: foto di level resource sudah cukup untuk fase 1.
- **No. rangka/mesin, merek, tipe bodi, dan bagasi**: tidak dirender di layar mana pun, atau juragan tidak tahu jawabannya.
- **Filter pencarian berdasarkan spek**: Sewain SaaS B2B, bukan marketplace, jadi penyewa datang lewat link satu usaha.

## Open Questions

- Apakah `vehicle_type` boleh diubah setelah resource punya unit/booking? Mengubah motor menjadi mobil akan melanggar `CHECK` kursi. Saran: kunci saja, dan kalau salah jenis, juragan membuat resource baru.
- Apakah `resources.category` perlu tetap diisi untuk kendaraan (disalin dari `vehicle_type`), atau cukup dibiarkan kosong dan UI membaca `vehicle_specs`?
- Pelanggaran kebijakan BBM di teks S&K: apakah potongannya lewat `deposit_deducted` secara manual sudah cukup?
- Apakah placeholder per jenis kendaraan perlu dikirim dari API (supaya satu sumber kebenaran untuk FE dan halaman publik), atau cukup berupa konstanta di FE?
