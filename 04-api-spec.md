# API Spec — Sewain

> Turunan dari [`02-business-rules.md`](./02-business-rules.md),
> [`01-product-requirements.md`](./01-product-requirements.md), dan [`03-erd.md`](./03-erd.md).
> Konvensi mengikuti `new-commerce-api/CLAUDE.md` (PRD §6.7).

---

## 1. Satu API, empat host

Satu deploy, satu basis kode. Yang memisahkan tenant adalah **host**, bukan segmen
path (BR-025, BR-030):

| Host | Isi | Autentikasi | Sumber `owner_id` |
|---|---|---|---|
| `sewain.id` | promosi — **M7, paling akhir** | — | — |
| `app.sewain.id` | backoffice + API-nya — **M0–M5, fokus utama** | Bearer JWT | Klaim token (BR-001) |
| `<slug>.sewain.id` | katalog penyewa + portal penyewa — **M5, fitur MVP #5** | — | header `Host` (BR-030) |
| `api.sewain.id` | webhook; API eksternal — **M5** | tanda tangan / `X-API-Key` | transaksi tertaut / kunci (BR-031, BR-032) |

```
rentalbudi.sewain.id/                        katalog publik
rentalbudi.sewain.id/api/v1/public/resources listing katalog + ketersediaan
rentalbudi.sewain.id/booking/<token>         portal penyewa
app.sewain.id/api/v1/bookings                backoffice
api.sewain.id/api/v1/webhooks/{provider}     webhook gateway
```

> **`sewain.id` dan `<slug>.sewain.id` sering tertukar.** Yang pertama menjual Sewain ke pemilik
> rental — halaman promosi, ditunda ke paling akhir. Yang kedua adalah produk yang dipakai
> penyewa, fitur MVP #5 dengan target metrik sendiri di PRD §10. Cuma yang pertama boleh ditunda.

**Slug tidak muncul di path sama sekali.** `GET /api/v1/public/resources` di host
`rentalbudi.sewain.id`, bukan `GET /api/v1/public/r/rentalbudi/resources` di apex.
Endpoint yang menerima slug sebagai parameter adalah endpoint yang bisa disuruh
menunjuk pemilik lain.

`owner_id` **tidak pernah** dibaca dari path, body, atau query pada permukaan mana
pun. Body yang memuat `owner_id` ditolak `400`, bukan diabaikan diam-diam —
diabaikan diam-diam berarti pemanggilnya tetap yakin filternya jalan.

**`api.sewain.id` melayani dua hal di fase 1:** webhook WhatsApp Cloud API (BR-072, BR-073)
sejak awal, dan API eksternal untuk situs pemilik (BR-031) mulai M5. Webhook pembayaran
nonaktif bersama jalur gateway (§3.8.1).

Host-nya tetap berdiri sekarang, dan alasannya justru makin kuat: URL webhook didaftarkan di
dashboard penyedia, dan memindahkannya nanti adalah tugas koordinasi dengan mereka. Sekali
sekarang, nol saat gateway dinyalakan.

> **Kenapa `Host` boleh dipercaya padahal BR-001 melarang header:** `Host` bukan
> data aplikasi, ia amplop routing — proxy sudah memilih sertifikat lewat SNI dan
> menolak host yang tidak dikonfigurasi. Konsekuensinya satu kewajiban operasional:
> **API tidak boleh bisa dijangkau tanpa melewati proxy** — termasuk oleh frontend
> sendiri saat merender di server, yang memanggil balik ke host publik alih-alih
> menembus ke `api` internal. Uraiannya di BR-030.

## 2. Konvensi

| Hal | Ketentuan |
|---|---|
| Versi | `/api/v1`; perubahan yang merusak → `/v2`, tidak pernah diam-diam |
| Tenant | Dari klaim token, atau dari header `Host`. **Tidak pernah dari path, query, atau body** |
| Uang | Integer rupiah penuh (`120000`), tidak pernah string atau desimal |
| Waktu | RFC 3339 dengan offset (`2026-09-10T08:00:00+07:00`) |
| Rentang | Awal inklusif, akhir eksklusif `[)` di seluruh API (BR-022) |
| Paginasi | Cursor: `?limit=50&cursor=…` → `{ "data": [...], "next_cursor": "…" }` |
| Error | `application/problem+json` (RFC 9457) |
| Idempotensi | Header `Idempotency-Key` wajib pada `POST` yang menghasilkan uang atau booking. Kunci sama → dijalankan **sekali**, panggilan berikutnya memutar ulang respons pertama. Lihat §2.1 |
| Upload | **Browser `PUT` langsung ke R2** lewat URL bertanda tangan; byte tidak pernah melewati API. Yang dikirim ke API cuma `object_key`-nya. Lihat §2.2 (BR-093) |
| Peran | Endpoint bertanda 🔒 hanya untuk `owner`, bukan `operator` (BR-003) |
| Verifikasi | Seluruh endpoint di luar daftar putih §3.1 dibalas `403 email-not-verified` sampai `users.email_verified_at` terisi (BR-006) |
| Kode booking | `<booking_code_prefix pemilik>-<nomor>`. Contoh di dokumen ini memakai default `SWN`; pemilik yang mengubahnya menghasilkan `RB-0042`, `JAYA-0007`, dst (BR-024) |
| Nonaktif | Endpoint bertanda **[nonaktif]** tidak didaftarkan dan tidak masuk `openapi.yaml` — memanggilnya `404`, bukan `503` |

### 2.1 Idempotensi (BR-090)

Constraint database sudah mencegah kerusakan dari submit ganda — `bookings_no_overlap`,
`payments_one_success_per_invoice`, `handovers_one_per_direction`. Yang **tidak** dicegahnya
adalah pengalaman penggunanya: operator menekan Simpan, jaringan seluler timeout, dia tekan
lagi, lalu menerima `409 booking-conflict` yang menyebut booking**nya sendiri**.

`Idempotency-Key` mengubah itu jadi sukses yang diulang, dan itu yang memberi frontend cara
aman me-retry `POST`. Tanpa ini, satu-satunya pilihan klien di jaringan buruk adalah menyerah
atau menduplikasi.

```
POST /api/v1/bookings
Idempotency-Key: 8f3a1c92-…        ← UUID dibuat klien, satu per niat pengguna
```

| Keadaan kunci | Respons |
|---|---|
| Belum pernah dipakai | Dijalankan; respons disimpan bersama kunci, TTL 24 jam |
| Sudah ada hasilnya | Respons pertama diputar ulang — status & body **identik**, database tidak disentuh |
| Ada tapi masih berjalan | `409 request-in-flight`; klien menunggu, tidak mengirim ulang dengan kunci baru |

Satu kunci mewakili **satu niat pengguna**, bukan satu percobaan jaringan. Klien yang membuat
kunci baru setiap retry sudah membatalkan seluruh gunanya. Wajib pada `POST /bookings`,
`/public/bookings`, `/invoices/{id}/lines`, `/invoices/{id}/payments`, `/bookings/{id}/pickup`,
`/bookings/{id}/return`, `/bookings/{id}/deposit/settle`, dan
`/bookings/{id}/deposit/waive`.

Penyimpanannya Redis, bukan tabel — lihat `03-erd.md` §4.

### 2.2 Unggahan langsung ke R2 (BR-093)

Byte tidak pernah melewati API. Tiga langkah, dan langkah ketiga selalu endpoint domain
yang sudah ada — **tidak ada `/uploads/confirm` generik**, karena baris dan objeknya
harus tercatat dalam satu transaksi (BR-035).

Satu endpoint, dipakai tiga jalur — foto serah-terima (§3.6), foto identitas (§3.4), dan
bukti transfer (§3.8). Ia hidup di sini, bukan di salah satu dari ketiganya:

| Method | Path | Peran | BR |
|---|---|---|---|
| `POST` | `/uploads/presign` | semua | BR-093 |

```http
POST /api/v1/uploads/presign
{ "kind": "handover_photo", "content_type": "image/jpeg", "bytes": 3145728 }
```
```json
{ "object_key": "pending/<owner_id>/9f2c…", 
  "upload_url": "https://…r2.cloudflarestorage.com/…?X-Amz-Signature=…",
  "expires_in": 600 }
```

```http
PUT <upload_url>          ← byte langsung ke R2, API tidak terlibat
```

```http
POST /api/v1/bookings/{id}/pickup
{ "photo_keys": ["pending/<owner_id>/9f2c…"], "meter_value": 45120, … }
```

| Hal | Ketentuan |
|---|---|
| `kind` | `handover_photo` · `identity_photo` · `payment_proof` |
| `object_key` | **Server yang menentukan.** Klien tidak pernah mengusulkannya |
| TTL `upload_url` | **10 menit.** Foto 5 MB di jaringan seluler yang jelek bisa lewat 5 menit, dan presign yang mati di tengah unggahan mengenai persis alur serah-terima di parkiran |
| Batas | `Content-Type` dan `Content-Length` **diikat pada tanda tangan** — ditegakkan R2, bukan cuma divalidasi aplikasi. Maksimum 10 MB per objek |
| Tipe diizinkan | `image/jpeg`, `image/png`, `image/webp`; `payment_proof` juga `application/pdf` |

**Saat commit, server memverifikasi tiap kunci sebelum menulis baris:** `HEAD` ke R2 —
objeknya ada? prefiks `owner_id`-nya cocok? tipe dan ukurannya sesuai? Gagal salah satu
→ `422`. Kunci yang lolos disalin dari `pending/` ke prefiks finalnya (R2→R2, nol egress),
lalu barisnya ditulis dalam transaksi yang sama.

Objek `pending/` yang tidak pernah di-commit **hilang sendiri dalam 24 jam** lewat
lifecycle rule — nol job penyapu, nol query silang ke database.

> Objek yang ada tanpa barisnya bukan barang bukti: tidak ada yang menunjuknya dan tidak
> ada yang bisa membacanya. Yang berbahaya arah sebaliknya — baris yang menunjuk objek
> karangan — dan itu yang ditutup `HEAD` di atas.

### Bentuk error

```json
{
  "type": "https://sewain.id/problems/booking-conflict",
  "title": "Unit sudah dibooking pada rentang itu",
  "status": 409,
  "detail": "Avanza Putih (B 1234 XY) sudah dipakai booking SWN-0042.",
  "conflicts": [
    { "code": "SWN-0042", "start_at": "2026-09-03T09:00:00+07:00",
      "end_at": "2026-09-05T09:00:00+07:00", "status": "reserved" }
  ]
}
```

### Katalog error → aturan bisnis

| `type` | HTTP | Kapan | BR |
|---|---|---|---|
| `unauthenticated` | 401 | Token tidak ada, kedaluwarsa, atau tanda tangannya salah | BR-004 |
| `permission-denied` | 403 | Terautentikasi tapi perannya tidak mengizinkan. `detail` **menyebut izin yang dibutuhkan** | BR-003 |
| `validation-failed` | 422 | Body tidak lolos validasi, termasuk field yang dikelola server dan `null` eksplisit | — |
| `internal` | 500 | Kesalahan di sisi kami. `detail` tetap, tanpa rincian | BR-092 |
| `booking-conflict` | 409 | Unit bentrok, termasuk kalah balapan di constraint | BR-022 |
| `duration-out-of-range` | 422 | Durasi di luar `min_duration`/`max_duration` | BR-021 |
| `customer-blacklisted` | 422 | Penyewa diblokir | BR-028 |
| `unit-not-swappable` | 409 | Tukar unit setelah `picked_up` | BR-029 |
| `handover-photo-required` | 422 | Serah-terima tanpa foto | BR-036 |
| `upload-not-found` | 422 | `object_key` menunjuk objek yang tidak ada di R2, atau bukan milik pemilik ini | BR-093 |
| `upload-type-mismatch` | 422 | Tipe atau ukuran objek tidak cocok dengan yang ditandatangani | BR-093 |
| `meter-value-required` | 422 | Resource bermeter, odometer kosong | BR-036 |
| `payment-required-before-pickup` | 409 | Flag pemilik aktif, invoice belum lunas | BR-038 |
| `physical-conflict-unconfirmed` | 409 | Unit belum balik; butuh `confirm_physical_conflict: true` | BR-042 |
| `deposit-not-settled` | 409 | `returned → completed` sebelum deposit beres | BR-049 |
| `invoice-already-paid` | 409 | Pembayaran kedua atas invoice yang sama | BR-060 |
| `evidence-immutable` | 405 | Percobaan `PATCH`/`DELETE` handover | BR-037 |
| `unit-quota-exceeded` | 403 | *(menganggur)* Tambah unit melebihi kuota paket — langganan ditunda, error ini tidak pernah terbit di fase 1 | BR-081 |
| `request-in-flight` | 409 | `Idempotency-Key` sama masih diproses; tunggu, jangan kirim ulang | BR-090 |
| `rate-limited` | 429 | Batas laju permukaan publik | BR-030 |
| `not-found` | 404 | Host tak dikenal, pemilik nonaktif, data milik pemilik lain | BR-030 |
| `invalid-api-key` | 401 | Kunci tidak dikenal atau sudah dicabut | BR-031 |
| `origin-not-allowed` | 403 | `Origin` tidak ada di `allowed_origins` | BR-031 |
| `quota-exceeded` | 429 | Kuota kunci habis | BR-031 |
| `email-taken` | 422 | Email sudah dipakai di usaha mana pun — unik global | BR-004, BR-005 |
| `slug-taken` | 422 | Slug sudah dipakai pemilik lain | BR-005, BR-025 |
| `slug-invalid` | 422 | Slug tidak lolos format label DNS, atau masuk daftar subdomain terlarang | BR-005, BR-025 |
| `email-not-verified` | 403 | **Seluruh backoffice** sebelum email terverifikasi; hanya login/refresh/logout/verify/resend/`me` yang lolos | BR-006 |
| `verification-token-invalid` | 422 | Tautan verifikasi kedaluwarsa, sudah dipakai, atau tidak dikenal | BR-006 |
| `deposit-already-paid` | 409 | Pembebasan deposit setelah invoice-nya lunas | BR-051 |
| `deposit-not-applicable` | 409 | Pembebasan/penyelesaian deposit pada booking tanpa deposit | BR-016, BR-051 |
| `waiver-reason-required` | 422 | Pembebasan dikirim tanpa alasan | BR-051 |

**404 seragam.** Host tidak dikenal, pemilik `suspended`, dan resource milik
pemilik lain menghasilkan respons yang persis sama. Selisih respons antar kasus
adalah cara katalog pemilik lain bocor.

Empat baris teratas generik dan tidak terikat satu BR — ia yang dipakai setiap endpoint
sebelum sampai ke aturan bisnisnya. Sisanya spesifik, dan tiap baris punya BR yang bisa
dibuka. **`type` memakai hyphen, bukan underscore**, dan sama persis dengan segmen
terakhir URI-nya: `https://sewain.id/problems/booking-conflict`. Tidak ada field `code`
terpisah — kodenya adalah segmen terakhir `type`.

**Data milik usaha lain dijawab `404`, bukan `403`** (BR-001, BR-030).
`permission-denied` dipakai ketika data itu memang milik usahanya tapi perannya
kurang; baris milik usaha lain tidak boleh bisa dibedakan dari baris yang tidak ada.

---

## 3. Backoffice

### 3.1 Auth & akun

| Method | Path | Peran | BR |
|---|---|---|---|
| `POST` | `/auth/register` | — | BR-005, BR-017, BR-025 |
| `POST` | `/auth/login` | — | BR-004 |
| `POST` | `/auth/refresh` | — | BR-004 |
| `POST` | `/auth/logout` | semua | BR-004 |
| `POST` | `/auth/verify-email` | — | BR-006 |
| `POST` | `/auth/verify-email/resend` | semua | BR-006 |
| `POST` | `/auth/accept-invitation` | — | BR-004, BR-006 |
| `GET` `PATCH` | `/me` | semua | BR-003, BR-004 |
| `GET` `PATCH` | `/settings` 🔒 | owner | BR-024, BR-025, BR-027, BR-031, BR-038, BR-057, BR-070 |
| `GET` `POST` | `/users` 🔒 | owner | BR-003, BR-004 |
| `PATCH` `DELETE` | `/users/{id}` 🔒 | owner | BR-003, BR-004 |
| `GET` | `/subscription` 🔒 **[nonaktif]** | owner | BR-080 |
| `GET` `POST` | `/api-keys` 🔒 | owner | BR-031 |
| `DELETE` | `/api-keys/{id}` 🔒 | owner | BR-031 |

`PATCH /settings` adalah satu-satunya tempat knob pemilik hidup — `slug`,
`booking_code_prefix`, `require_payment_before_pickup`, `draft_expiry_hours`,
`payment_due_hours`, `no_show_tolerance_hours`, `allowed_origins`, dan tiga sakelar
pengingat. Tidak ada satu pun yang di-hardcode
(BR-024, BR-025, BR-027, BR-031, BR-038, BR-057, BR-070).

`booking_code_prefix` 2–6 huruf besar/angka, default `SWN`; di luar itu `422`.
Mengubahnya **tidak** menyentuh kode booking yang sudah terbit, dan **tidak** me-reset
pencacahnya (BR-024).

`slug` **kosong saat usaha dibuat** dan diisi belakangan dari sini — ia tidak ditanyakan
saat mendaftar (BR-005). Tiga hal yang sering tertukar:

| | |
|---|---|
| **Kapan halamannya ada** | Sejak **M5** (`S1-051` + `S1-060`). Begitu slug terisi, `<slug>.sewain.id` melayani katalog publik dan portal penyewa. Fiturnya **tidak** ditunda ke fase berikutnya |
| **Siapa yang boleh mengisi** | Aturannya paket `usaha` ke atas (BR-080), tapi **belum ditegakkan di fase 1** — langganan ditunda dan tidak ada kuota apa pun yang ditegakkan. Praktisnya: siapa pun boleh mengisi, dan halamannya langsung jalan |
| **Selama slug masih kosong** | Pemilik itu tidak punya host sama sekali — katalog publik maupun portal penyewa ikut tidak ada, dan `<slug>.sewain.id` apa pun dibalas `404` seperti host tak dikenal (BR-030) |

Gerbang berbayarnya baru menggigit kalau langganan dinyalakan, dan itu menunggu rantai
yang ujungnya di luar kendali tim: `langganan ← jalur pembayaran ← akun merchant`
(BR-061, BR-082).

| Kondisi | Balasan |
|---|---|
| Slug sudah dipakai pemilik lain | `422 slug-taken` |
| Gagal format DNS atau masuk daftar terlarang | `422 slug-invalid` |

#### `/api-keys` — kunci untuk situs pemilik sendiri (BR-031)

| Endpoint | Perilaku |
|---|---|
| `POST /api-keys` | Terbitkan kunci. **Rahasianya dibalas sekali di respons ini dan tidak pernah bisa dilihat lagi** — yang disimpan cuma hash argon2id dan 8 karakter prefix |
| `GET /api-keys` | Daftar kunci: `name`, `key_prefix`, `last_used_at`, `revoked_at`. Tidak pernah rahasianya |
| `DELETE /api-keys/{id}` | **Cabut, bukan hapus** (`revoked_at`). Kunci yang hilang dari tabel membuat log akses lama tidak bisa dijelaskan |

Kunci hanya membuka empat endpoint §4 — lihat §4.1. Ia bukan token backoffice, dan
tidak pernah diterima di `app.sewain.id` maupun `<slug>.sewain.id` (BR-032).

#### `/subscription` **[nonaktif]** — langganan ditunda

Langganan SaaS ditunda dari fase 1 (BR-080–BR-082), jadi endpoint ini tidak
didaftarkan. Konsekuensi yang perlu dipegang saat ngoding:

- **Nol penegakan kuota.** `POST /users` dan `POST /resources/{id}/units` tidak lagi
  memikul BR-081 — setiap pemilik tanpa batas unit maupun pengguna.
- **`unit-quota-exceeded` tetap di katalog error tapi tidak pernah terbit.** Jangan
  menulis test yang menunggunya, sama seperti `gateway_pending` di BR-056.
- **Tabel `subscriptions` tetap ada dan tetap kosong**, beserta `invoices.kind`,
  `invoices.subscription_id`, dan constraint `invoices_one_subject`. Menyalakannya
  kembali berarti mendaftarkan satu endpoint — nol migrasi, nol perubahan katalog error.
- **Pemicu menyalakannya: jalur pembayaran menyala** (BR-061). Harganya sudah diputuskan
  (PRD §13); yang belum ada adalah cara menagihnya, karena BR-082 memakai gateway yang sama.

#### `POST /auth/register` — satu-satunya jalur yang menciptakan usaha (BR-005)

```json
{ "email": "budi@contoh.id", "password": "…",
  "business_name": "Rental Budi", "business_type": "vehicle_rental" }
```

→ `201` beserta sesi yang langsung jadi — pemilik tidak perlu login lagi setelah daftar.

| Kondisi | Balasan |
|---|---|
| Email sudah dipakai di usaha mana pun | `422 email-taken` |
| `business_type` di luar enam preset BR-017 | `422 validation-failed` |

**`slug` tidak ditanyakan di sini.** Ia opsional, butuh paket `usaha` ke atas, dan diisi
belakangan dari `PATCH /settings` (BR-025, BR-080). Tiap field di layar daftar adalah
tempat orang berhenti, dan memilih subdomain adalah keputusan yang belum bisa diambil
sebelum produknya terlihat.

Tiga hal yang mengikat:

- **Satu transaksi.** Baris `owners` dan baris `users` ber-`role = 'owner'` terbit
  bersama; gagal di tengah tidak boleh meninggalkan usaha yang tidak bisa dimasuki
  siapa pun.
- **`business_type` menentukan `pricing_unit` seluruh resource pemilik itu** (BR-017).
  Ia ditanyakan sekali di sini, bukan berulang di tiap form resource.
- **Dibatasi laju per IP** (§7) — endpoint tanpa autentikasi yang setiap suksesnya
  membuat satu usaha baru.

`POST /users` **tidak** menciptakan usaha; ia mengundang operator ke usaha yang sudah
ada (BR-004). Email wajib terverifikasi sebelum pengguna boleh melakukan apa pun — lihat
blok di atas (BR-006).

#### Verifikasi email (BR-006) — gerbang seluruh backoffice

Pendaftaran terbuka untuk publik, dan **email wajib terverifikasi sebelum pengguna boleh
melakukan apa pun.** Penegakannya **satu middleware**, bukan pengecekan per handler:
gerbang yang harus diingat di tiap endpoint adalah gerbang yang akan terlewat di
endpoint ke-31.

**Daftar putih — hanya lima jalur ini yang jalan saat `email_verified_at IS NULL`:**

```
POST /auth/login            POST /auth/verify-email
POST /auth/refresh          POST /auth/verify-email/resend
POST /auth/logout           GET  /me
```

Selain itu — **tanpa kecuali** — dibalas `403 email-not-verified`. Termasuk `/resources`,
`/bookings`, `/handovers`, `/invoices`, `/settings`, `/users`, `/api-keys`, dan `/reports`.

| Endpoint | Perilaku |
|---|---|
| `POST /auth/verify-email` | Body `{ "token": "…" }`. Sekali pakai, umur 24 jam; kedaluwarsa/terpakai → `422 verification-token-invalid`. Sukses mengisi `users.email_verified_at` |
| `POST /auth/verify-email/resend` | Kirim ulang ke alamat terdaftar. 3 req/jam per pengguna (§7). **Selalu tersedia** — kedaluwarsa tidak boleh jadi jalan buntu |
| `GET /me` | Membawa `email_verified_at`, supaya frontend merender dinding verifikasi alih-alih menebak dari `403` |

`POST /auth/register` tetap membalas `201` beserta sesi yang langsung jadi — tapi
pemiliknya mendarat di **dinding verifikasi**, bukan dashboard. Sesinya diterbitkan
justru supaya ia bisa memanggil `resend` tanpa login ulang.

**Operator undangan tidak lewat jalur ini.** Undangan hanya bisa diterima lewat tautan
di emailnya (BR-004), jadi menerimanya sudah bukti kendali atas alamat itu:
`email_verified_at` terisi saat undangan diterima, dan tidak ada surel verifikasi kedua.

Konsekuensi yang perlu diketahui frontend: **`403 email-not-verified` bisa muncul di
endpoint mana pun**, jadi ia ditangani di lapisan klien HTTP sebagai pengalihan ke
layar verifikasi — bukan sebagai toast di tiap layar.

#### `POST /auth/accept-invitation` — jalur yang menghidupkan akun undangan

`POST /users` menerbitkan baris ber-`status = 'invited'` tanpa password (§3.1 `/users`).
Endpoint inilah yang membuatnya bisa dipakai. Body `{ "token": "…", "password": "…" }`,
dan ia melakukan tiga hal sekaligus:

| Yang disetel | Kenapa |
|---|---|
| `password_hash` | Undangan sengaja tidak pernah membawa password; yang diundang yang memilihnya |
| `status = 'active'` | Dari `invited`. Tidak ada jalur lain yang keluar dari status itu |
| `email_verified_at` | **Nol surel kedua** — lihat di bawah |

Yang ketiga bukan jalan pintas. Undangan hanya bisa diterima lewat tautan di emailnya,
jadi menerimanya **sudah** bukti kendali atas alamat itu — bukti yang sama persis yang
dikejar surel verifikasi. Mengirimnya lagi sesudah surel undangan adalah meminta bukti
yang sama dua kali, dan BR-006 menolaknya secara eksplisit.

Balasannya `200` beserta sesi yang langsung jadi, dan operator ini **mendarat di
dashboard** — bukan di dinding verifikasi, karena ia sudah melewatinya. Itu satu-satunya
tempat perilakunya berbeda dari `POST /auth/register`.

| Kondisi | Balasan |
|---|---|
| Token tidak dikenal, sudah dipakai, atau kedaluwarsa | `422 verification-token-invalid` |
| Password di bawah 8 karakter | `422 validation-failed` |

Tokennya hidup di Redis, bukan tabel — alasan yang sama dengan `Idempotency-Key`, lihat
`03-erd.md` §4.

#### Sesi & usaha (BR-004)

Satu user milik tepat satu usaha. `owner_id` dan `role` diambil dari baris `users`
saat login dan **tidak pernah** dari request — tidak ada parameter usaha di mana pun
pada permukaan ini.

| Endpoint | Perilaku |
|---|---|
| `POST /auth/login` | Verifikasi email+password → terbitkan access token membawa `owner_id` dan `role` milik baris `users` itu. Refresh token diset sebagai cookie httpOnly, tidak pernah di body |
| `POST /auth/refresh` | Rotasi refresh token, terbitkan access token baru. Token yang sudah dirotasi lalu dipakai lagi = pencurian: seluruh rantai dicabut dan semua sesi user itu berakhir |
| `GET /me` | Usaha, peran, dan izin yang diturunkan dari peran itu |
| `PATCH /me` | Ubah nama dan telepon sendiri. `owner_id`, `role`, dan `email` **tidak** bisa diubah dari sini |

**Email unik global** yang membuat login cukup email+password: satu alamat menunjuk
tepat satu baris `users`, jadi tepat satu usaha. Harganya satu alamat email = satu
usaha — orang yang menjalankan dua rental butuh dua akun (BR-004).

Data milik usaha lain → **`404`, bukan `403`**. Selisih respons antar kasus
membocorkan usaha mana yang ada, sama seperti BR-030 di permukaan publik.

#### `/users` mengelola akun di usaha ini

| Endpoint | Arti |
|---|---|
| `POST /users` | Undang `operator` ke **usaha ini**. Email yang sudah dipakai di usaha mana pun ditolak `422` — unik global (BR-004) |
| `PATCH /users/{id}` | Ubah `role` atau `status`. `email` dan `owner_id` tidak bisa diubah |
| `DELETE /users/{id}` | `users.status = 'disabled'` — **nonaktifkan, bukan hapus baris.** `created_by` di tabel lain harus tetap bisa dijelaskan |

Nol endpoint di sini yang menghapus baris `users`. Menonaktifkan akun membunuh
sesinya dalam ≤ 15 menit — batasnya TTL access token, bukan sesuatu yang dipaksakan
seketika (BR-004).

### 3.2 Katalog

| Method | Path | Peran | BR |
|---|---|---|---|
| `GET` `POST` | `/resources` | POST 🔒 | BR-010, BR-012, BR-015 |
| `GET` `PATCH` `DELETE` | `/resources/{id}` | GET semua; PATCH/DELETE 🔒 | BR-003, BR-014 |
| `GET` `POST` | `/resources/{id}/units` | POST 🔒 | BR-010, BR-011 |
| `PATCH` `DELETE` | `/units/{id}` | 🔒 | BR-013 |

Mengubah harga resource **tidak** menyentuh booking mana pun (BR-014); respons
`PATCH /resources/{id}` menyebutkan jumlah booking berjalan yang tetap memakai
harga lama, supaya pemilik tidak menebak.

**Operator membaca katalog, tidak menulisnya.** Matriks BR-003 di
`sewain-api/internal/auth/roles.go` — satu-satunya definisinya — memberi operator
`resources:read` dan `units:read`, tidak lebih. Jadi `POST`, `PATCH`, dan `DELETE`
di tabel ini seluruhnya 🔒, dan baris `/resources/{id}` yang dulu berbunyi "🔒 untuk
harga & deposit" menyiratkan sesuatu yang tidak pernah benar di kode.

Yang tetap dicek terpisah: field `base_price`, `deposit_amount`, dan
`late_fee_per_unit` butuh **`pricing:write`** di atas `resources:write`. Hari ini
kedua izin itu sama-sama milik owner saja, jadi cek kedua belum pernah jadi
satu-satunya yang menolak. Ia ada karena BR-003 menyebut **nominalnya**, bukan
endpoint-nya — kalau matriks perannya berubah, cek inilah yang masih benar. Di
layar, ketiga field itu **tidak dirender** untuk operator (`S1-018`).

**`pricing_unit` tidak dikirim klien.** Server mengisinya dari `owners.business_type`
saat resource dibuat (BR-012, BR-017) — seperti `unit_price` dan `deposit_amount` pada
booking. Mengirimnya → `422`. Juragan rental tidak pernah ditanya satuan harga, karena
presetnya cuma punya satu; pemilih baru dirender untuk preset bersatuan-banyak
(`apartment`, fase 2).

**Empat field boleh `null`, dan `null` berarti aturannya tidak berlaku** (BR-016):
`deposit_amount`, `late_fee_per_unit`, `min_duration`, dan `max_duration`.

`requires_id_verification` **tidak** ikut, walau BR-016 mendaftarnya di tabel yang
sama: ia `NOT NULL DEFAULT false` di `03-erd.md` §3, dan "tidak wajib" sudah persis
sama dengan `false`. Alasannya sejenis dengan `buffer_minutes` — sebuah boolean
bernilai `NULL` menambah keadaan ketiga yang tidak ada artinya bagi siapa pun.

```json
{ "name": "Tenda Dome 4 Orang", "base_price": 75000,
  "deposit_amount": null, "late_fee_per_unit": null,
  "min_duration": null, "max_duration": null, "buffer_minutes": 60 }
```

Dua hal yang gampang salah di sini:

- **`0` ditolak database, bukan diterima lalu diperlakukan seperti `null`**
  (`422 validation-failed`). Satu keadaan, satu cara menulisnya — kalau `0` dan
  `null` sama-sama berarti "tanpa deposit", tidak ada laporan yang bisa
  membedakannya lagi.
- **`null` eksplisit di sini bukan pelanggaran konvensi.** Aturan umum "`null`
  eksplisit adalah `422`" berlaku untuk field yang dikelola server; untuk kelima
  field ini `null` adalah nilai yang sah dan bermakna. Menghilangkan key-nya pada
  `POST` memberi hasil yang sama; pada `PATCH`, mengirim `null` adalah **satu-satunya
  cara mencabut** nilai yang sudah ada.

`buffer_minutes` tidak ikut — ia `NOT NULL`, default `0` (BR-015).

`PATCH /units/{id}` yang mengubah status ke `maintenance`/`retired` mengembalikan
`200` beserta peringatan — bukan menolak, bukan membatalkan (BR-013):

```json
{ "id": "…", "status": "maintenance",
  "warning": { "affected_bookings": [ { "code": "SWN-0043", "start_at": "…" } ] } }
```

### 3.3 Ketersediaan

| Method | Path | Peran | BR |
|---|---|---|---|
| `GET` | `/availability` | semua | BR-020, BR-013, BR-015 |
| `GET` | `/calendar` | semua | BR-033, BR-041 |

```http
GET /api/v1/availability?start_at=2026-09-03T09:00:00%2B07:00
                        &end_at=2026-09-05T09:00:00%2B07:00
                        &resource_id=…
```

```json
{ "data": [ {
    "resource": { "id": "…", "name": "Avanza 2021", "base_price": 350000,
                  "pricing_unit": "day", "deposit_amount": 500000,
                  "buffer_minutes": 120 },
    "available_units": [ { "id": "…", "code": "B 1234 XY", "label": "Avanza Putih" } ],
    "duration_qty": 2, "subtotal": 700000
} ] }
```

Unit `maintenance`/`retired` tidak pernah muncul (BR-013). Buffer ikut dihitung:
booking selesai 10:00 dengan `buffer_minutes = 120` membuat unit baru muncul
sebagai tersedia mulai 12:00 (BR-015).

`GET /calendar?from=&to=` mengembalikan **lajur per unit** untuk layar kalender.
Tiap segmen membawa satu field `state` — salah satu dari delapan keadaan BR-033,
dihitung server:

```json
{ "data": [ {
    "unit": { "id": "…", "code": "B 1234 XY", "label": "Avanza Putih" },
    "segments": [
      { "from": "2026-09-01T00:00:00+07:00", "to": "2026-09-03T09:00:00+07:00",
        "state": "available" },
      { "from": "2026-09-03T09:00:00+07:00", "to": "2026-09-05T09:00:00+07:00",
        "state": "reserved_unpaid",
        "booking": { "id": "…", "code": "SWN-0042", "customer_name": "Budi" } },
      { "from": "2026-09-05T09:00:00+07:00", "to": "2026-09-05T11:00:00+07:00",
        "state": "buffer" }
    ]
} ] }
```

Empat hal yang mengikat bentuk ini:

- **`state` dihitung server, tidak pernah disusun klien** dari gabungan
  `bookings.status` + `invoices.status` + status unit. Begitu klien menyusunnya
  sendiri, backoffice dan halaman publik mulai menyimpang (BR-033, semangat BR-025).
- **`is_overdue` tidak lagi ada sebagai field terpisah** — ia salah satu nilai
  `state`. Dua sumber kebenaran untuk satu kondisi adalah dua yang bisa berbeda.
- **`draft` tidak pernah muncul di sini.** Ia tidak mengunci unit (BR-023, BR-026)
  dan hidup di `GET /bookings?status=draft`. `returned` tampil `available`.
- Unit berstatus `retired` tidak punya lajur sama sekali; unit `maintenance` punya
  lajur dengan satu segmen `maintenance` sepanjang rentangnya (BR-013).

### 3.4 Penyewa

| Method | Path | Peran | BR |
|---|---|---|---|
| `GET` `POST` | `/customers` | semua | BR-003 |
| `GET` `PATCH` | `/customers/{id}` | semua | — |
| `POST` `DELETE` | `/customers/{id}/blacklist` 🔒 | owner | BR-028 |
| `POST` | `/customers/{id}/identity` | semua | BR-085 |
| `GET` | `/customers/{id}/identity` | semua, **tercatat di audit log** | BR-085 |

`POST …/identity` menerima `{ "object_key": "pending/…", "id_type": "ktp" }` — foto
diunggah lebih dulu langsung ke R2 (§2.2), dan server mem-`HEAD` kuncinya sebelum
menyimpan (BR-093).

`GET …/identity` mengembalikan URL bertanda tangan berumur **5 menit** dan menulis satu
baris `audit_logs` setiap kali dipanggil. Tanpa baris itu, endpoint ini melanggar
BR-085 — jadi keduanya satu transaksi. Fotonya dilindungi enkripsi at-rest R2, bukan
enkripsi aplikasi: URL bertanda tangan harus bisa dirender langsung oleh browser.

### 3.5 Booking

| Method | Path | Peran | BR |
|---|---|---|---|
| `GET` | `/bookings` | semua | BR-041 |
| `POST` | `/bookings` | semua | BR-021, BR-022, BR-024, BR-028 |
| `GET` | `/bookings/{id}` | semua | — |
| `PATCH` | `/bookings/{id}` | semua | BR-021, BR-022, BR-029 |
| `POST` | `/bookings/{id}/confirm` | semua | BR-026, BR-022 |
| `POST` | `/bookings/{id}/cancel` | semua | BR-023 |

`GET /bookings` menerima `?status=`, `?from=`, `?to=`, `?unit_id=`, dan
`?overdue=true` (kondisi turunan, bukan status — BR-041).

`POST /bookings` (staff → langsung `reserved`):

```json
{ "customer_id": "…", "resource_unit_id": "…",
  "start_at": "2026-09-03T09:00:00+07:00",
  "end_at":   "2026-09-05T09:00:00+07:00" }
```

Server yang mengisi `code` dan seluruh kolom snapshot harga — termasuk `buffer_minutes`
(BR-014, BR-015, BR-024). **`end_at_with_buffer` diisi database lewat trigger**, bukan
oleh aplikasi: satu jalur insert yang lupa menghitungnya menghasilkan buffer `0` yang gagal
senyap. Nilai yang dikirim klien untuk kolom itu **ditimpa**, bukan ditolak. Lihat `03-erd.md` §3. Harga yang dikirim klien diabaikan; kalau dikirim,
`400`. Cek bentrok dijalankan lebih dulu supaya pesannya enak dibaca, tapi
pelanggaran `bookings_no_overlap` tetap diterjemahkan ke `booking-conflict` yang
sama — dua operator yang menekan Simpan pada detik yang sama menghasilkan tepat
satu keberhasilan (BR-022).

`PATCH /bookings/{id}` dengan `resource_unit_id` berbeda = tukar unit: hanya saat
`reserved`, hanya ke unit dari resource yang sama, dan unit tujuan wajib lolos
cek bentrok. Setelah `picked_up` → `unit-not-swappable` (BR-029).

`POST /bookings/{id}/confirm` menjalankan **ulang** cek bentrok saat itu juga —
draft tidak pernah menahan unit, jadi konfirmasi bisa gagal dan itu benar (BR-026).

### 3.6 Serah-terima

| Method | Path | Peran | BR |
|---|---|---|---|
| `POST` | `/bookings/{id}/pickup` | semua | BR-035, BR-036, BR-038, BR-042 |
| `GET` | `/bookings/{id}/return-preview` | semua | BR-046 |
| `POST` | `/bookings/{id}/return` | semua | BR-035, BR-040, BR-046, BR-047 |
| `GET` | `/bookings/{id}/handovers` | semua | BR-037 |
| `PATCH` `DELETE` | `/handovers/{id}` | **tidak ada** → `405 evidence-immutable` | BR-037 |

`POST …/pickup` — JSON: `photo_keys[]` (≥ 1, wajib), `meter_value` (wajib bila resource
bermeter), `checklist`, `condition_notes`, `confirm_physical_conflict` (bool). Kuncinya
didapat lebih dulu dari `/uploads/presign` (§2.2); byte-nya tidak pernah lewat sini.
Tanpa kunci → `422`, dan **kunci yang `HEAD`-nya gagal juga `422`** — syarat foto
ditegakkan atas objeknya, bukan atas klaimnya (BR-036, BR-093). Bila unit sebelumnya masih `picked_up` melewati `end_at`, panggilan
pertama dijawab `409 physical-conflict-unconfirmed` dan baru lolos setelah
operator mengirim ulang dengan `confirm_physical_conflict: true` (BR-042).

`GET …/return-preview` — dihitung, tidak menyimpan apa pun:

```json
{ "actual_return_at": "2026-09-06T14:30:00+07:00",
  "end_at": "2026-09-05T09:00:00+07:00",
  "overdue_units": 2, "pricing_unit": "day",
  "late_fee_per_unit": 100000, "late_fee_total": 200000,
  "deposit_amount": 500000,
  "proposed_lines": [
    { "kind": "late_fee", "amount": 200000, "description": "Telat 2 hari" }
  ] }
```

`proposed_lines` adalah **usulan, bukan keputusan** (BR-051). Baris yang tidak
dikonfirmasi tidak pernah terbit — bukan terbit lalu dinolkan.
`late_fee_per_unit: null` berarti resource-nya memang tanpa denda (BR-016), jadi
tidak ada baris `late_fee` yang diusulkan; `overdue_units` **tetap dihitung**,
karena kondisi terlambatnya tetap berlaku (BR-041).

`POST …/return` menerima hasil keputusan operator, bukan sekadar menyalin preview:
`photo_keys[]` (≥ 1, lewat §2.2), `meter_value`, `confirmed_lines[]`, `late_fee_waived` (bigint),
`waiver_reason` (wajib bila ada pembebasan), dan `damages[]` — tiap elemen
`{ amount, description, handover_photo_id }`. `actual_return_at` diisi jam server,
bukan dari body (BR-040).

| Aturan | Akibat |
|---|---|
| Baris `late_fee` yang tidak ada di `confirmed_lines[]` | tidak terbit |
| Pembebasan tanpa `waiver_reason` | `422 waiver-reason-required` |
| `damages[]` tanpa `handover_photo_id` | `422` — ditolak database juga (BR-047) |
| `Idempotency-Key` | **wajib** — `damages[]` satu-satunya jalur uang tanpa constraint (BR-090) |

Denda yang tidak bisa dibebaskan membuat operator berhenti mencatat waktu kembali
dengan jujur, jadi jalur pembebasannya adalah bagian dari desain, bukan celah
(BR-046, BR-051).

### 3.7 Deposit

| Method | Path | Peran | BR |
|---|---|---|---|
| `GET` | `/bookings/{id}/deposit` | semua | BR-048 |
| `POST` | `/bookings/{id}/deposit/waive` | semua | BR-051 |
| `POST` | `/bookings/{id}/deposit/settle` | semua | BR-048, BR-049 |
| `POST` | `/bookings/{id}/complete` | semua | BR-049 |

Ketiganya duduk di titik yang berbeda di umur satu booking. Yang membedakan `waive`
dari `settle` cuma satu hal: **apakah uangnya sudah masuk.**

```
booking dibuat → invoice terbit: rent 700k + deposit 500k = 1.200k
      │
      ├─ waive ──────► deposit DIBATALKAN, penyewa tidak pernah membayarnya
      │                invoice jadi 700k
      ▼
   penyewa bayar  ←──── setelah ini waive MATI PERMANEN (409)
      │
   pickup → dipakai → return
      │
      ├─ settle ─────► uangnya sudah di tangan pemilik:
      │                berapa dikembalikan, berapa dipotong
      ▼
   complete ────────► booking selesai
```

**`complete` dipakai oleh setiap booking, `settle` tidak.** Booking yang depositnya
dibebaskan atau yang memang tanpa deposit (BR-016) tidak pernah memanggil `settle` —
tapi tetap harus bisa selesai. Itu sebabnya keduanya endpoint terpisah: `settle`
mengurus uang dan hanya ada untuk booking berdeposit; `complete` mengurus status dan
ada untuk semua.

`GET …/deposit` adalah **pratinjau — ia tidak menyimpan apa pun.** Angka di bawah
dihitung saat diminta dari potongan yang sudah dicentang operator (BR-051), bukan
dibaca dari kolom hasil:

```json
{ "deposit_amount": 500000, "deductions": 700000,
  "refund_amount": 0, "deducted_amount": 500000,
  "new_invoice_amount": 200000 }
```

Sisa negatif tidak pernah menjadi deposit minus: selisihnya terbit sebagai invoice
baru (BR-048). `POST …/complete` sebelum penyelesaian → `409 deposit-not-settled`
(BR-049).

**Booking tanpa deposit** (`deposit_amount: null`, BR-016) membalas
`{ "deposit_amount": null }` tanpa angka lain, dan `POST …/complete` **tidak**
diblokir — tidak ada yang perlu diselesaikan.

`POST …/deposit/waive` membebaskan deposit untuk booking ini (BR-051). Body:
`{ "reason": "…" }` — wajib, dan `Idempotency-Key` wajib (BR-090). Baris `deposit`
**dicabut** dari invoice, bukan diimbangi baris `discount`: `discount` terhitung
sebagai pemasukan (BR-076), jadi mengimbanginya akan mengurangi angka pemasukan
sebesar nilai deposit — persis yang BR-050 ada untuk mencegah.

| Kondisi | Balasan |
|---|---|
| Invoice yang memuat baris `deposit` sudah lunas | `409 deposit-already-paid` |
| `reason` kosong | `422 waiver-reason-required` |
| Booking memang tanpa deposit | `409 deposit-not-applicable` |

Sesudah lunas tidak ada jalur pembebasan sama sekali — yang ada pengembalian lewat
`settle` (BR-048). Itu yang menjaga satu hal tetap benar: **tidak ada invoice lunas
yang pernah diubah.**

### 3.8 Invoice & pembayaran

| Method | Path | Peran | BR |
|---|---|---|---|
| `GET` | `/invoices` | 🔒 daftar penuh; operator hanya per booking | BR-003 |
| `GET` | `/invoices/{id}` | semua | BR-055 |
| `POST` | `/invoices/{id}/lines` | 🔒 untuk `discount` | BR-047, BR-055 |
| `POST` | `/invoices/{id}/payment-link` | — | **[nonaktif]** → §3.8.1 |
| `POST` | `/invoices/{id}/payments` | semua | BR-060, BR-061 |
| `POST` | `/invoices/{id}/proofs` | semua | BR-062 |
| `POST` | `/proofs/{id}/approve` | semua | BR-062 |

`total` selalu hasil penjumlahan `lines` pada saat dibaca — tidak ada kolom total
(BR-055). `POST …/payments` kedua atas invoice yang sama → `409
invoice-already-paid` (BR-060).

**`due_at` diisi server saat invoice terbit** (BR-057), tidak pernah dari klien:
`min(created_at + owners.payment_due_hours, booking.start_at)`. Lewat tempo dan belum
lunas → status `overdue`, dan **apa yang terjadi pada booking-nya bergantung
`require_payment_before_pickup`** (BR-038):

| Sakelar | Lewat `due_at`, belum lunas |
|---|---|
| `true` | Booking → `cancelled` alasan `payment_expired`, unit bebas |
| `false` (default) | Invoice `overdue` saja; booking dibatasi `no_show` lewat `start_at + no_show_tolerance_hours` |

`payment_due_reminder` dikirim mendahului keduanya (BR-070) — pembatalan tanpa
peringatan tidak sah.

`POST …/proofs` menerima `{ "object_key": "pending/…" }` — bukti diunggah lebih dulu
langsung ke R2 (§2.2), server mem-`HEAD` kuncinya, lalu mengembalikan `202` dengan
`match_status: "pending"`; pembacaan AI berjalan asinkron dan hasilnya **hanya
rekomendasi** — invoice baru lunas setelah `POST /proofs/{id}/approve` oleh
manusia (BR-062).

### 3.8.1 Jalur pembayaran fase 1: manual saja

**Jalur payment gateway dimatikan di fase 1.** Penanda `**[nonaktif]**` di dokumen ini berarti
endpoint itu tidak didaftarkan dan tidak masuk `openapi.yaml`.

Penyewa membayar dengan **transfer manual berbukti**, dan itu jalur yang lengkap:

```
Invoice terbit  ──▶  link dikirim via WhatsApp
                       │
       penyewa transfer sendiri ke rekening pemilik
                       │
       POST /invoices/{id}/proofs        unggah bukti → 202
                       │
       worker baca nominal & tanggal pakai AI → rekomendasi (BR-062)
                       │
       POST /proofs/{id}/approve         operator setujui → LUNAS
```

Ditambah `POST /invoices/{id}/payments` untuk transfer yang sudah dicek operator sendiri dan
untuk pembayaran tunai di konter. Pelunasan **selalu** lewat persetujuan manusia — tidak ada
jalur otomatis apa pun di fase 1.

Tujuh hal yang perlu dipegang:

1. **BR-061 sudah mendesain sakelarnya.** "Pemilik boleh menonaktifkan salah satunya" — fase 1
   memakai mekanisme yang sama di tingkat sistem, bukan menciptakan konsep baru.
2. **Endpoint tidak terdaftar → `404`, bukan `503`.** Endpoint yang ada tapi selalu gagal tetap
   ikut ke `openapi.yaml`, digenerate jadi method di klien, lalu dipanggil orang. Yang tidak
   terdaftar tidak bisa dipanggil.
3. **Tidak ada tipe error baru.** Sengaja: `gateway-disabled` berarti menambah kontrak yang
   harus dicabut lagi nanti.
4. **Dua nilai enum jadi tidak terjangkau:** `invoices.status = 'gateway_pending'` (BR-056) dan
   `payments.method = 'gateway'`. **Enum-nya tetap ada** supaya menyalakan kembali tidak butuh
   migrasi. Ini yang paling penting bagi yang menulis test — jangan menulis test yang menunggu
   status itu muncul.
5. **`payment_gateway_transactions` tetap ada di skema dan tetap kosong.** Ia bukan tabel mati;
   ia tabel yang belum kebagian baris.
6. **BR-064 menganggur, bukan batal.** "Redirect bukan bukti" tidak relevan di fase 1 karena
   tidak ada halaman gateway yang dituju sama sekali. BR-063 (webhook idempoten) sama.
7. **Menyalakan kembali = daftarkan tiga endpoint bertanda `[nonaktif]`.** Nol perubahan skema,
   nol perubahan katalog error, nol migrasi. Kontraknya sengaja ditinggal utuh, bukan dihapus.

> **Pemicu menyalakan kembali: akun merchant aktif.** Begitu aggregator pembayaran menyetujui
> akun, tiga endpoint bertanda `[nonaktif]` didaftarkan. Nol perubahan skema, nol migrasi, nol
> perubahan katalog error.
>
> Risiko yang perlu dijaga: **pemicu ini di luar kendali tim.** Kalau pengajuan akunnya tidak
> pernah dimulai, "sementara" jadi permanen tanpa ada yang pernah memutuskannya. Karena itu
> statusnya juga tercatat sebagai pertanyaan terbuka di PRD §12 #2 — di sini ia syarat teknis, di
> sana ia tugas yang harus dijalankan seseorang.

### 3.9 Notifikasi & laporan

| Method | Path | Peran | BR |
|---|---|---|---|
| `GET` | `/notifications` | semua | BR-072 |
| `POST` | `/notifications/{id}/retry` | semua | BR-071, BR-072 |
| `GET` | `/dashboard` | operator: tanpa angka uang | BR-003, BR-041 |
| `GET` | `/reports/revenue` 🔒 | owner | BR-050, BR-075, BR-076 |
| `GET` | `/reports/utilization` 🔒 | owner | BR-075 |
| `GET` | `/reports/idle-units` 🔒 | owner | BR-075 |
| `POST` | `/reports/export` 🔒 | owner | BR-077 |
| `GET` | `/jobs/{id}` | semua | BR-091 |

`GET /reports/revenue?from=&to=` memisahkan deposit dari pendapatan — bukan
sebagai catatan kaki, tapi sebagai dua angka berbeda di respons (BR-050, BR-076):

```json
{ "revenue": { "rent": 12500000, "late_fee": 300000,
               "damage": 150000, "discount": -200000, "total": 12750000 },
  "deposit_held": { "in": 4000000, "returned": 3500000, "balance": 500000 } }
```

`POST /reports/export` menerima `{ "report": "revenue|utilization|idle_units|bookings",
"from": "…", "to": "…", "format": "csv|xlsx" }` dan mengembalikan `202` berisi `job_id`.
Berkasnya dirakit **di luar request** oleh job runner (BR-091) — 12 bulan × 500 unit tidak selesai dalam
satu siklus HTTP, dan memaksakannya berarti timeout yang menyalahkan pengguna.

`GET /jobs/{id}` adalah kontrak umum untuk semua pekerjaan asinkron, bukan cuma ekspor:

```json
{ "id": "…", "status": "queued|running|done|failed",
  "download_url": "https://…", "expires_at": "…", "error": null }
```

Tautan unduh berumur **15 menit** dan dibuat ulang dengan mengulang permintaan ekspor. Laporan
memuat data penyewa; tautan yang tidak kedaluwarsa akan hidup selamanya di riwayat WhatsApp.

Ekspor tetap memisahkan deposit dari pemasukan sebagai kolom berbeda (BR-077) —
pemisahan itu tidak boleh hilang cuma karena formatnya berubah jadi CSV.

---

## 4. Permukaan publik — `<slug>.sewain.id` (BR-025, BR-030)

Tanpa autentikasi. Hanya-baca kecuali satu endpoint pengajuan. Tenant diturunkan
dari `Host`, jadi path-nya tidak punya segmen slug.

| Method | Path | BR |
|---|---|---|
| `GET` | `/public/owner` | BR-025 |
| `GET` | `/public/resources` | BR-010, BR-013, BR-020, BR-025 |
| `GET` | `/public/resources/{id}` | BR-025 |
| `POST` | `/public/bookings` | BR-026, BR-027, BR-030 |

```http
GET https://rentalbudi.sewain.id/api/v1/public/resources?start_at=…&end_at=…
```

```json
{ "owner": { "name": "Rental Budi", "whatsapp": "+62…" },
  "data": [ { "id": "…", "name": "Avanza 2021", "images": ["…"],
              "base_price": 350000, "pricing_unit": "day",
              "deposit_amount": 500000,
              "available": true, "available_count": 2,
              "min_duration": 1, "max_duration": 30 } ] }
```

Yang **tidak pernah** ada di respons publik: `resource_units.code`, id unit, nama
penyewa lain, harga khusus, dan `owner_id` (BR-025). Ketersediaan dilaporkan di
level resource; penunjukan unit fisik terjadi di server saat pengajuan dibuat.

`POST /public/bookings`:

```json
{ "resource_id": "…", "start_at": "…", "end_at": "…",
  "customer": { "name": "Sari", "phone": "+62…" } }
```

→ `201` dengan `{ "code": "SWN-0051", "status": "draft", "expires_at": "…",
"track_url": "https://rentalbudi.sewain.id/booking/<token>" }`.

Empat hal yang membuat endpoint ini aman untuk dibuka ke internet:

1. `status = 'draft'`, `source = 'public_page'` — **tidak mengunci unit**, jadi
   spam pengajuan tidak bisa memblokir penjualan sungguhan (BR-023, BR-026).
2. Draft kedaluwarsa sesuai `owners.draft_expiry_hours` (BR-027).
3. Rate limit per IP **dan** per pemilik; keduanya, karena satu IP menyerang
   banyak pemilik dan banyak IP menyerang satu pemilik adalah dua serangan
   berbeda (BR-030).
4. `owner_id` diturunkan dari `Host`, tidak dari parameter apa pun; `resource_id`
   milik pemilik lain → `404` yang sama dengan host asing (BR-030).

Pengajuan tetap dicek terhadap BR-021 (durasi) dan blacklist (BR-028) — tapi
penyewa terblokir menerima pesan netral "pengajuan tidak dapat diproses, silakan
hubungi pemilik", bukan alasan blokirnya.

### 4.1 API eksternal — `api.sewain.id` (BR-031, BR-032)

Skema kedua: pemilik meng-host situsnya sendiri (`rentalbudi.com`) dan menarik
katalog dari sewain. Path dan bentuk respons **identik** dengan §4 — yang beda cuma
host dan cara menurunkan tenant.

| | Same-origin — `<slug>.sewain.id` | Eksternal — `api.sewain.id` |
|---|---|---|
| Tenant dari | `Host` | `X-API-Key` |
| CORS | tidak perlu, same-origin | wajib, `owners.allowed_origins` |
| Kuota | rate limit per IP & pemilik | + kuota per kunci |
| Yang merender | sewain | pemilik |

**Dua jalur, tanpa penyeberangan (BR-032).** `api.sewain.id` tidak pernah membaca
`Host` sebagai sumber `owner_id`, dan `<slug>.sewain.id` tidak pernah membaca
`X-API-Key`. Header yang salah alamat diabaikan — bukan error, cuma tidak menaikkan
hak apa pun. Kalau `api.sewain.id` ikut mempercayai `Host`, satu kunci yang sah
digabung `Host` palsu jadi jalan menunjuk pemilik lain, dan asumsi topologi yang
menopang BR-030 tidak berlaku untuk host yang memang dirancang menerima panggilan
dari luar browser.

**Kunci hanya membuka empat endpoint §4.** Katalog, ketersediaan, dan pengajuan
`draft` — itu saja. Bukan pintu ke backoffice, bukan jalan ke data penyewa. Batasan
isi respons BR-025 berlaku utuh: kode unit, id unit, dan nama penyewa tidak pernah
keluar, siapa pun pemanggilnya. Ketersediaan tetap di level resource, dan keadaan
kalender tetap hanya `available`/tidak (BR-033).

```http
GET /api/v1/public/resources?start_at=…&end_at=…
Host: api.sewain.id
X-API-Key: swn_live_a1b2c3d4…
Origin: https://rentalbudi.com
```

| Kondisi | Balasan |
|---|---|
| Kunci tidak dikenal atau `revoked_at` terisi | `401 invalid-api-key` |
| `Origin` ada tapi tidak di `allowed_origins` | `403 origin-not-allowed` |
| Kuota per kunci habis | `429 quota-exceeded` |
| Endpoint di luar keempatnya | `404 not-found` — sama seperti host tak dikenal |

**Preflight.** `OPTIONS` dibalas tanpa `X-API-Key` (browser tidak mengirimkannya di
preflight), dengan `Access-Control-Allow-Origin` diisi dari `allowed_origins`
pemilik yang ditunjuk `Origin` — dan `Vary: Origin` supaya cache tidak menyajikan
izin satu pemilik ke pemilik lain.

> **Origin allowlist bukan kontrol keamanan, ia kontrol browser.** Siapa pun tetap
> bisa memanggil dengan `curl`. Yang benar-benar menjaga adalah kuota per kunci,
> rate limit, dan kenyataan bahwa keempat endpoint ini memang dirancang untuk
> dilihat publik. Jangan pernah pakai kunci ini untuk apa pun di luar §4 — di situ
> asumsinya berhenti berlaku.

---

## 5. Portal penyewa — `<slug>.sewain.id/booking/<token>` (BR-002)

Akses lewat token di link WhatsApp, tanpa akun. Tinggal di **host pemilik**, bukan
di `app.sewain.id`: semua yang dilihat penyewa hidup di satu host, dan brandingnya
jadi benar tanpa usaha tambahan.

**Kenapa awalan `/booking/` ada, dan kenapa dieja penuh.** Host pemilik melayani dua
permukaan yang sangat berbeda — katalog publik yang boleh dilihat siapa saja di `/`, dan
halaman satu booking yang isinya milik satu penyewa. Awalan itu yang memisahkan keduanya,
sekaligus menjaga sisa namespace tetap bebas untuk katalog (`/resources/<id>`).

Ia dieja penuh, bukan disingkat `/b/`, karena tautan ini **dibaca manusia di WhatsApp** —
penyewa yang melihat `rentalbudi.sewain.id/booking/…` tahu itu miliknya sebelum membukanya.
"booking" juga kosakata yang sudah dipakai di seluruh produk ini (BR-024 kode booking,
`GET /bookings`), jadi ia bukan istilah asing yang ditempel di URL.

| Method | Path | BR |
|---|---|---|
| `GET` | `/portal/bookings/{token}` | BR-002 |
| `POST` | `/portal/bookings/{token}/payment-link` | **[nonaktif]** → §3.8.1 |
| `POST` | `/portal/bookings/{token}/proofs` | BR-062 |

Unggah bukti dari portal memakai jalur yang sama dengan backoffice (§2.2): penyewa
meminta presign, `PUT` langsung ke R2, lalu mengirim `object_key`-nya. Token booking yang
membatasi presign-nya — satu token hanya bisa menandatangani unggahan untuk booking itu.

Respons memuat jadwal, rincian invoice, foto kondisi milik booking itu, dan status
deposit. Tidak memuat data booking lain, katalog, maupun laporan (BR-002).

**Di fase 1 portal ini jalur satu arah untuk pembayaran** (§3.8.1): penyewa bisa melihat
tagihannya dan **mengunggah bukti transfer**, tidak bisa membayar di tempat. Salinan layarnya
harus jujur soal itu — instruksi transfer beserta nomor rekening pemilik, lalu unggah bukti.
Tombol "Bayar sekarang" yang membuka halaman gateway tidak ada, jadi jangan dirender.

---

## 6. Webhook (BR-063, BR-064)

Dilayani di `api.sewain.id` — host mesin, bukan host pemilik dan bukan backoffice.

| Method | Path | BR |
|---|---|---|
| `POST` | `api.sewain.id/api/v1/webhooks/payments/{provider}` | **[nonaktif]** → §3.8.1 |
| `GET` | `api.sewain.id/api/v1/webhooks/whatsapp` | BR-073 — verifikasi langganan |
| `POST` | `api.sewain.id/api/v1/webhooks/whatsapp` | BR-072, BR-073 |

Webhook pembayaran ikut nonaktif bersama jalur gateway (§3.8.1), dan itu bukan sekadar
kebersihan: tanpa link yang pernah diterbitkan tidak ada transaksi tertaut, dan tanpa akun
merchant tidak ada signing secret — jadi webhook apa pun gagal verifikasi tanda tangan (`401`)
sebelum menyentuh apa-apa. Mematikannya menghapus satu endpoint `POST` tanpa auth yang tidak
mungkin dipakai secara sah.

Urutan di bawah tetap kontrak yang berlaku begitu gateway dinyalakan kembali. Ia ditulis
sekarang justru supaya tidak dirancang ulang nanti dengan tergesa.

Urutan yang wajib, dan urutannya bukan selera:

1. Verifikasi tanda tangan. Gagal → `401`, tidak diproses.
2. Simpan payload mentah ke `payment_gateway_transactions` (`provider`,
   `external_id` unik).
3. `external_id` sudah ada → `200 OK` tanpa efek apa pun. Webhook yang sama
   diproses dua kali tidak boleh melahirkan dua pembayaran (BR-063).
4. Buat `payments` + ubah `invoices.status` **dalam satu transaksi**.

Pengalihan balik dari halaman gateway tidak punya endpoint sama sekali — hanya
halaman terima kasih. Redirect bukan bukti; hanya webhook terverifikasi yang bisa
menandai lunas (BR-064).

### 6.1 `/webhooks/whatsapp` — satu-satunya webhook aktif di fase 1

Ia tinggal di host mesin **tanpa `Host` pemilik dan tanpa token**, jadi tenant-nya tidak
bisa diturunkan seperti di permukaan lain (BR-030, BR-032) — ia ditemukan dari isi
payload lewat `wamid`.

**`GET` — verifikasi langganan.** Meta memanggilnya sekali saat webhook didaftarkan:

```http
GET /api/v1/webhooks/whatsapp?hub.mode=subscribe
                             &hub.verify_token=<token kita>
                             &hub.challenge=1158201444
```

Token cocok → balas `200` berisi **`hub.challenge` apa adanya**, sebagai teks biasa.
Tidak cocok → `403`. Tanpa endpoint ini webhook-nya **tidak bisa didaftarkan sama
sekali**; ia bukan kerapian.

**`POST` — status pengiriman.** Urutannya:

1. **Verifikasi `X-Hub-Signature-256`.** Gagal → `401`, tidak diproses. Ini `POST`
   tanpa autentikasi di host publik; tanpa verifikasi siapa pun bisa menandai pengingat
   sebagai terkirim padahal tidak pernah sampai.
2. **Temukan barisnya lewat `notifications.provider_message_id`** (`wamid` yang
   disimpan saat pesan dikirim). Tidak ketemu → `200` tanpa efek, bukan `404` — Meta
   me-retry apa pun yang bukan `2xx`.
3. **Perbarui `status`** (`sent` / `failed`) dan `failure_reason` kalau gagal (BR-072).
   Pembaruan ini idempoten: callback yang sama dua kali menghasilkan baris yang sama.

**Pesan masuk dibuang, dan itu keputusan.** Penyewa yang membalas pengingat dikirim
Meta ke URL yang sama. Fase 1 membalas `200` lalu membuangnya — tidak ada kotak masuk,
tidak ada balasan otomatis (BR-073). Tetap balas `2xx`: apa pun selain itu membuat Meta
me-retry pesan yang memang tidak kita pakai.

Webhook pembayaran ikut nonaktif; urutan wajibnya di atas tetap kontrak untuk saat
gateway dinyalakan.

---

## 7. Batas laju

| Permukaan | Batas |
|---|---|
| Publik — `GET` | 60 req/menit per IP, 600 req/menit per pemilik |
| Publik — `POST /bookings` | 5 req/jam per IP, 30 req/jam per pemilik |
| `POST /auth/register` | 5 req/jam per IP — tanpa autentikasi, dan tiap panggilan sukses membuat satu usaha (BR-005) |
| `POST /auth/verify-email/resend` | 3 req/jam per pengguna — pengirim surel, bukan endpoint data (BR-006) |
| `POST /uploads/presign` | 60 req/menit per pengguna — satu serah-terima bisa memuat belasan foto (BR-093) |
| API eksternal — `api.sewain.id` | `api_keys.rate_limit_per_min`, default 60/menit per kunci |
| Portal penyewa | 120 req/menit per token |
| Backoffice | 600 req/menit per pengguna |
| Webhook | tanpa batas, tapi wajib idempoten (BR-063). Fase 1: hanya WhatsApp yang aktif (§3.8.1) |

Angka-angka ini konfigurasi, bukan konstanta di kode.

---

## 8. Yang sengaja tidak ada endpoint-nya

| Tidak ada | Alasan |
|---|---|
| `PATCH`/`DELETE` handover & fotonya | Bukti yang bisa diedit bukan bukti (BR-037) |
| `DELETE` apa pun untuk peran operator | BR-003 |
| Ubah status booking langsung (`PATCH {status}`) | Semua transisi lewat endpoint aksi yang punya syaratnya sendiri (PRD §8) |
| Endpoint konfirmasi redirect gateway | Redirect bukan bukti (BR-064) |
| Endpoint kalkulasi ulang harga booking lama | Snapshot itu tidak boleh bergerak (BR-014) |
| `POST /public/.../availability` | Permukaan publik hanya-baca kecuali satu endpoint pengajuan (BR-030) |
| Endpoint publik apa pun yang menerima `slug` atau `owner_id` sebagai parameter | Tenant datang dari `Host`. Parameter bisa dipalsukan, host tidak — selama API tidak bisa dijangkau tanpa proxy (BR-030) |
| `POST /invoices/{id}/payment-link` | **[nonaktif]** fase 1 — pembayaran manual saja (§3.8.1) |
| `POST /portal/bookings/{token}/payment-link` | **[nonaktif]** fase 1 — penyewa mengunggah bukti, tidak membayar di tempat (§3.8.1) |
| `POST /webhooks/payments/{provider}` | **[nonaktif]** fase 1 — tanpa link terbit tidak ada transaksi tertaut, dan tanpa signing secret verifikasi selalu gagal (§3.8.1) |
