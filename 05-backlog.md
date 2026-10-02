# Backlog Fase 1 — Rental & sewa

**Satu backlog untuk dua repo.** `sewain-api/` dan `sewain-web/` mengerjakan item dari file ini;
tidak ada backlog lain di mana pun. Kontraknya ada di folder yang sama:
[`02-business-rules.md`](./02-business-rules.md) · [`03-erd.md`](./03-erd.md) ·
[`04-api-spec.md`](./04-api-spec.md) · [`01-product-requirements.md`](./01-product-requirements.md).

**Berurut menurut posisi, bukan menurut nomor.** Item ditulis dalam urutan pengerjaannya dan
tidak ada yang bergantung pada sesuatu di bawahnya. **Nomor adalah urutan alokasi** — sekali
diberikan ia tidak pernah digeser dan tidak pernah dipakai ulang, karena `S1-028`, `S1-051`,
dan belasan lainnya dikutip dari dokumen dan `CLAUDE.md` di dua repo. Item yang datang belakangan
karena itu bisa bernomor besar tapi duduk di milestone awal. Kalau bingung mau ngerjain apa,
ambil item `todo` **teratas** yang dependensinya sudah `done`.

**Status** `todo` · `wip` · `review` · `done` · `blocked` · `dropped`
**Repo** `BE` backend · `FE` frontend · `CT` kontrak (`docs/`) · `OPS` infrastruktur

---

## Urutan bangun — API dulu atau web dulu?

**API dulu per kapabilitas. Bukan API tuntas dulu.**

- **Di dalam satu milestone, item BE mendahului layar FE-nya.** Backend menyediakan endpoint,
  layar memakainya. Yang tidak berlaku adalah versi besarnya: seluruh backend **tidak** mendahului
  seluruh frontend.
- **Milestone selesai ketika item FE-nya ikut selesai**, bukan saat item BE terakhir merge.
  Milestone yang berhenti di backend tidak menghasilkan apa pun yang bisa ditunjukkan ke siapa pun.
- **`S1-002` (`openapi.yaml`) yang membuat aturan ini longgar.** Begitu kontraknya ada, layar boleh
  mulai ditulis di atas klien yang digenerate kapan saja. Kolom `Depends` menandai kapan sebuah
  layar bisa **diverifikasi**, bukan kapan boleh mulai ditulis.
- **Satu pengecualian permanen: `S1-023`.** Test konkurensi tidak menunggu apa pun dan tidak pernah
  `done` sekali lalu ditinggal — ia hidup di `make check` selamanya.

**Kenapa bukan API tuntas dulu, baru web.** Uji lapangan bareng design partner ada di `S1-076`,
minggu 16–17. Backend yang selesai sendirian di minggu 12 tidak bisa diuji siapa pun, dan pertanyaan
terbuka nomor satu di PRD §12 justru soal apakah pemilik rental mau memakai ini — pertanyaan yang
cuma bisa dijawab dengan layar yang bisa dibuka, sedini mungkin.

**Kenapa bukan FE dulu di atas mock.** Risiko teknis terbesar proyek ini adalah `S1-022`/`S1-023`,
dan menundanya berarti baru tahu di minggu 11 kalau modelnya salah.

### Backoffice dulu, lalu deployment, promosi terakhir

M0–M5 membangun yang dipakai juragan dan operator setiap hari di `app.sewain.id`, plus katalog
penyewa di `<slug>.sewain.id` yang jadi fitur MVP #5. M6 membuatnya bisa diakses dari internet.
M7 baru menjualnya.

Halaman promosi yang jadi sebelum produknya terbukti dipakai adalah halaman yang menjanjikan
sesuatu yang belum ada — dan design partner pertama datang dari percakapan langsung, bukan dari
pencarian Google.

### Kenapa 19 minggu, bukan 10

Kepadatan 4,3 item/minggu bukan angka nyaman, itu angka terukur. **M0 di bawah isinya nyaris
identik dengan M0 `new-commerce`** — layanan lokal, `openapi.yaml`, runner migrasi, RLS, suite
isolasi, skema auth, auth, envelope error, app shell — dan di sana pekerjaan itu **selesai dalam
3 minggu**, ditandai `done`, bukan diestimasi. Sewain sempat menjadwalkannya 1 minggu.

Memadatkannya kembali berarti mengabaikan satu-satunya data yang kita punya. Kalau jadwalnya harus
dipendekkan, yang dipotong adalah **item**, bukan minggu — dan itu keputusan yang ditulis di PR,
bukan diam-diam.

**M0 dapat 3 minggu karena presedennya 3 minggu.** M0 `new-commerce` isinya 11 item dan selesai
dalam 3 minggu. Versi 2 minggu membuatnya 6,50/mgg — milestone yang *seluruh* proyek bergantung
padanya, dipadatkan paling ketat.

**M0 sekarang 16 item, dan itu puncak baru: 5,33/mgg.** Tiga di antaranya (`S1-082` registrasi,
`S1-083` layar daftar, `S1-084` verifikasi email) bukan tambahan fitur — sebelum ketiganya ada,
**tidak ada cara membuat pemilik sama sekali**: `S1-007` membuat tabelnya dan `S1-008`
memverifikasi password terhadap baris yang diasumsikan sudah ada. Rantai dependensi proyek ini
tidak punya titik masuk, dan pendaftaran yang langsung dibuka ke publik membuat verifikasi ikut
wajib sejak hari pertama (BR-006).

Angka 5,33 ditulis di sini supaya kelihatan, bukan diserap diam-diam — ia **1,2× M2**, milestone
paling berisiko, dan 1,23× kepadatan rata-rata. Kalau M0 mau dikembalikan ke ±4,3, tambah satu
minggu di sana dan seluruh jadwal bergeser jadi 20 minggu. Itu keputusan yang ditulis di PR,
bukan efek samping.

**Dan milestone paling berisiko dapat kelonggaran, bukan kompresi.** M2 memuat exclusion
constraint dan test konkurensinya — kalau ia salah, tidak ada bagian lain yang layak dibangun.
Versi 14 minggu justru menjadikannya milestone **terpadat** (6,50/mgg), yang terbalik. Sekarang
4,67, dan puncaknya ada di M5 — milestone dengan risiko teknis paling rendah.

**M5 dapat minggu ke-4 karena isinya nambah, bukan karena longgar.** API eksternal (`S1-079`–`S1-081`,
BR-031) pindah dari fase 2 ke sini. Menahannya di 3 minggu membuatnya 7,0/mgg — 1,6× preseden
terukur, di milestone yang sudah memuat halaman publik, notifikasi, dan laporan sekaligus.

**Minggu itu tidak ditarik kembali walau M5 lalu kehilangan dua item.** Langganan (`S1-058`) dan
job retensi (`S1-059`) ditunda, jadi M5 turun ke 19 item efektif dalam 4 minggu = **4,75/mgg**.
Mengembalikannya ke 3 minggu membuatnya 6,33 — di atas ambang yang bagian ini sendiri sudah tolak
dua paragraf di atas. Kalau jadwalnya memang mau dipendekkan, itu keputusan yang ditulis terpisah,
bukan efek samping dari dua item yang kebetulan gugur.

Angkanya ditulis di sini supaya tetap bisa ditagih: **88 baris, 84 item efektif / 19 minggu =
4,42.** Empat yang `dropped` sengaja tetap berbaris — kontraknya masih berlaku, cuma jalurnya
dimatikan. Kalau ada yang mau memendekkan jadwalnya lagi, yang dipotong item, dan daftarnya
ditulis di PR.

---

## Aturan

- **Satu item, satu PR, satu branch** bernama `s1-<id>-<slug>` (mis. `s1-022-exclusion-constraint`).
- **Klaim dengan menyetel `wip` dan menulis namamu di Owner**, lewat commit ke file ini, sebelum
  menulis kode. Dua orang di satu item adalah kegagalan yang bikin file ini ada.
- **Item `done` hanya kalau kolom Acceptance-nya terbukti benar** — bukan saat kodenya merge.
  Kalau acceptance butuh test, test itu bagian dari item.
- **Item `BE` dan padanan `FE`-nya adalah item terpisah** dan rilis mandiri.
- **`blocked` wajib punya alasan** di Notes. Blocked tanpa alasan sama dengan `todo`.
- Jangan mengurutkan ulang demi kenyamanan. Kalau urutannya salah, tulis kenapa di PR.

---

## M0 · Fondasi (minggu 1–3)

Tidak ada yang terlihat pengguna di sini kecuali layar login. Semua setelahnya bergantung pada
seluruh isinya.

Infrastruktur produksi — VPS, Caddy, TLS, backup, CI — ada di `M6` di akhir fase, bukan di sini.
Belum ada mesin dan belum ada domain. Yang benar-benar dibutuhkan backend cuma PostgreSQL 18 yang
bisa dihubungi, dan `S1-001` menyediakannya dari mesin developer sendiri.

| ID | Item | Repo | Depends | Acceptance | Status | Owner |
|---|---|---|---|---|---|---|
| S1-001 | Layanan lokal **di host, bukan container**: PostgreSQL 18 + `btree_gist`, Redis 8, MinIO | OPS | — | Ketiganya **terpasang di mesin developer** — bukan docker, bukan compose; `make dev` cuma butuh connection string. `GET /healthz` melaporkan ketiganya; `CREATE EXTENSION btree_gist` berhasil. MinIO jalan sebagai biner tunggal. **MinIO hanya untuk lokal** — produksi memakai R2, dan karena dua-duanya S3-compatible kodenya identik (`S1-033`) | done | |
| S1-002 | `openapi.yaml` diturunkan dari `04-api-spec.md` + generator dua repo | CT/BE/FE | 001 | `make generate` no-op di tree bersih, di dua repo | done | |
| S1-003 | Runner migrasi, peran `app_user` non-owner, helper `enable_owner_rls()` | BE | 001 | `app_user` tidak memiliki apa pun; `FORCE RLS` aktif di setiap tabel ber-owner — **dibuktikan `docs/03-verify-constraints.sql` bagian RLS** (6 kasus, dari peran non-superuser) | done | |
| S1-004 | `InOwnerTx`, konteks owner, gagal-tertutup | BE | 003 | Tanpa owner → `ErrNoOwnerContext`, tidak pernah hasil kosong | done | |
| S1-005 | **Suite isolasi owner atas seluruh route terdaftar** | BE | 004 | Dua owner ter-seed; token A mengembalikan nol baris milik B di setiap route (BR-001). **Plus `users` dan `refresh_tokens` sendiri**, yang ikut ber-RLS (BR-004) — token A tidak boleh bisa membaca akun maupun sesi milik B. Suite menolak route terdaftar yang tidak punya entri kasus | done | |
| S1-006 | Guard policy RLS | BE | 003 | `make lint-rls` keluar non-zero untuk tabel ber-`owner_id` tanpa policy, **dan untuk `ENABLE` tanpa `FORCE`** — mode gagal yang terlihat sehat sepenuhnya (BR-001) | done | |
| S1-007 | Skema `owners` (+`slug`), `users` (+`owner_id`, `role`), `refresh_tokens` | BE | 003 | Sesuai `03-erd.md` §1; **`slug` NULLABLE** — kosong adalah keadaan awal, dan dua pemilik tanpa slug tidak saling tabrakan di unique index; kalau diisi: unik global, lolos format label DNS, **dan ditolak database bila masuk daftar subdomain terlarang** (`app`, `api`, `mail`, …) (BR-025); **email unik GLOBAL** — alamat yang sama ditolak di usaha kedua, dan itu yang membuat login cukup email+password; **`refresh_tokens` ber-`owner_id` yang tidak cocok `users.owner_id` ditolak database** — FK komposit, bukan validasi aplikasi (BR-004) | done | |
| S1-008 | Auth: login, rotasi refresh, logout, argon2id, matriks peran | BE | 007 | `403` menyebut izin yang dibutuhkan di `detail`; `operator` ditolak di route khusus owner (BR-003). **`owner_id` dan `role` di access token berasal dari baris `users`**, tidak pernah dari request (BR-004); refresh token yang sudah dirotasi lalu dipakai lagi mencabut seluruh sesi user itu, bukan menolak satu request; data usaha lain → `404` bukan `403` | done | |
| S1-082 | **`POST /auth/register`**: usaha + pemilik dalam satu transaksi | BE | 007, 008 | **Ini titik masuk sistem** — tanpanya `login` tidak punya baris untuk diverifikasi. `owners` + `users` ber-`role='owner'` terbit bersama; gagal di tengah **tidak** meninggalkan usaha yatim; email terpakai → `422 email-taken`; **`slug` tidak diminta di sini** — opsional & berbayar, diisi dari `/settings` (BR-025); `business_type` di luar enam preset → `422`; batas laju 5/jam per IP; balasan `201` langsung membawa sesi (BR-005, BR-017) | done | |
| S1-083 | Layar daftar: email, usaha, **pilih jenis usaha** | FE | 013, 082 | Jenis usaha dipilih dengan bahasa juragan ("rental mobil & motor", "rental alat"), bukan nama enum; sukses **langsung masuk tanpa login ulang**, lalu mendarat di **dinding verifikasi**, bukan dashboard — sesinya diterbitkan justru supaya ia bisa memanggil `resend` (`04-api-spec.md` §3.1, BR-005, BR-006, BR-017) | done | |
| S1-084 | **Gerbang verifikasi email**: middleware + token + kirim ulang | BE | 082 | **Satu middleware, bukan cek per handler** — seluruh endpoint di luar daftar putih (`login`/`refresh`/`logout`/`verify-email`/`resend`/`GET /me`) dibalas `403 email-not-verified` selama `users.email_verified_at` kosong; token sekali pakai, mati 24 jam, kedaluwarsa → `422`; kirim ulang 3/jam per pengguna dan **selalu tersedia**; **operator undangan terverifikasi otomatis saat menerima undangan** — nol surel kedua (BR-004, BR-006) | done | |
| S1-009 | **`/settings` API**: knob pemilik | BE | 008 | `GET`/`PATCH` 🔒 owner. Semua knob bisa diubah **dan terbaca konsumennya**, bukan cuma tersimpan: `slug` **opsional dan mulai kosong** — diisi dari sini, bukan saat daftar; lolos format label DNS + daftar terlarang, butuh paket `usaha` ke atas yang **belum ditegakkan di fase 1** (BR-025, BR-080), **`booking_code_prefix`** (BR-024, 2–6 huruf besar/angka, default `SWN`), `draft_expiry_hours` (BR-027), **`payment_due_hours`** dan **`no_show_tolerance_hours`** (BR-057; `payment_due_hours` 0 ditolak database, toleransi 0 diterima), `require_payment_before_pickup` (BR-038), tiga sakelar pengingat (BR-070). **Tidak satu pun konsumen boleh menyimpan default-nya sendiri** — itu inti keempat BR itu. **Pengecualian yang disengaja: `slug` belum punya konsumen sampai M5** (`S1-051`/`S1-060`) — ia tersimpan dan tervalidasi di sini, tapi baru ada yang membacanya 12 minggu kemudian. Layar pengaturan wajib jujur soal itu, bukan menyiratkan halamannya sudah hidup. `operator` yang memanggil `PATCH` → `403` yang menyebut izinnya (BR-003) | done | |
| S1-010 | **`/users` API**: undang, ubah peran, nonaktifkan akun | BE | 008 | Pemilik bisa mengundang `operator` — tanpa ini peran itu ada di matriks tapi tidak ada cara memakainya. **Email yang sudah dipakai di usaha mana pun ditolak `422`** — unik global (BR-004); `DELETE` menyetel `users.status='disabled'`, **tidak** menghapus baris — `created_by` di tabel lain harus tetap bisa dijelaskan; nonaktif → sesi mati **≤ 15 menit**; `operator` tidak bisa memanggil endpoint ini sama sekali (BR-003) | done | |
| S1-011 | Envelope error RFC 9457, `trace_id`, **wiring OpenTelemetry** | BE | 004 | Setiap error membawa `trace_id` yang **bisa ditelusuri ke span-nya** — bukan string acak; span memuat `owner_id`, route, dan durasi query; katalog `type` cocok dengan `04-api-spec.md` §2 (BR-092) | done | |
| S1-012 | **`Idempotency-Key`**: middleware + penyimpanan hasil di Redis | BE | 001, 011 | `POST` yang sama dengan kunci sama dijalankan **sekali** (BR-090), panggilan kedua memutar ulang respons pertama (status + body identik) tanpa menyentuh database; kunci tanpa hasil tersimpan & masih berjalan → `409 request-in-flight`; TTL 24 jam | done | |
| S1-013 | App shell, routing, layar login, sesi, guard peran | FE | 002, 008, 082, 084 | **Dinding verifikasi**: `403 email-not-verified` ditangani di lapisan klien HTTP sebagai pengalihan ke layar verifikasi, bukan toast di tiap layar (BR-006). Layar login bisa benar-benar dicoba karena ada jalur membuat akunnya (`S1-082`) — bukan diuji dengan baris yang di-seed tangan. Access token di memori, refresh di cookie httpOnly **host-only di `app.sewain.id` — tanpa atribut `Domain`** (BR-025); reload tetap masuk; `operator` tidak melihat navigasi Laporan sama sekali (BR-003). Nama usaha terlihat di header, dibaca dari `/me` — bukan dari token yang di-decode di klien (BR-004) | done | |

> **M0 tuntas. Enam belas dari enam belas `done`**, dan semuanya dijalankan, bukan dibaca
> — `make check` exit 0 di `sewain-api`, `npm run generate:check` + `lint` + `typecheck`
> + `build` hijau di `sewain-web`, terhadap PostgreSQL 18.4, Redis 8.4.0, MinIO dan
> Mailpit yang benar-benar berjalan di host.
>
> **Alur penuhnya sudah dijalankan di browser**, bukan cuma di test: daftar → mendarat di
> dinding verifikasi → tautan diambil dari Mailpit → dashboard → undang operator →
> terima undangan → login sebagai operator → **navigasi Laporan hilang sama sekali**.
>
> **`S1-012` dikerjakan terakhir, dan tanpa satu pun pemakainya.** `Idempotency-Key`
> wajib di delapan endpoint (`04-api-spec.md` §2.1) dan tidak satu pun sudah ada — yang
> pertama `POST /bookings` di `S1-026`. Middleware-nya karena itu diuji langsung, bukan
> lewat route: sembilan kasus yang mencakup replay, `409` saat masih berjalan, scoping
> per pemilik, dan dua yang paling gampang salah dirancang (di bawah). Delapan route-nya
> **sudah terdaftar sebagai komentar** di `routeAccessTable`, jadi item yang membawanya
> tinggal menyalakan satu kolom.
>
> **Dua keputusan di `S1-012` yang tidak tertulis di acceptance-nya:**
>
> - **`5xx` tidak disimpan, `4xx` disimpan.** Kontrak menyuruh klien me-retry dengan
>   kunci **yang sama**; kalau `500` ikut disimpan, instruksi itu memutar ulang kegagalan
>   selama 24 jam dan handler-nya tidak pernah jalan lagi — gangguan sesaat jadi permanen
>   justru oleh mekanisme yang ada supaya retry aman. `422` sebaliknya: ia keputusan,
>   bukan gangguan, dan menanyakan hal yang sama tidak mengubah jawabannya.
> - **Gagal-terbuka kalau Redis mati.** Yang mencegah booking ganda itu exclusion
>   constraint (BR-022), bukan middleware ini — `CLAUDE.md` sendiri menulis "yang
>   diperbaiki middleware ini adalah responsnya". Menolak setiap tulis karena cache mati
>   mengubah dependensi yang pincang jadi outage di endpoint yang justru menghasilkan uang.
>
> **Yang belum dijalankan sama sekali: dua skrip bukti SQL** (`03-verify-constraints.sql`,
> `03-verify-overlap-constraint.sql`; cara menjalankannya di `03-erd.md` §3). Sejak
> `docs` di-realign, M0 menambah **empat** migrasi dengan constraint baru — `000004`
> knob pemilik, `000005` `business_type`, `000006` `email_verified_at` — dan §3 ERD
> mewajibkan skripnya ikut bertambah. Itu utang yang masih terbuka dan satu-satunya
> yang menahan M0 disebut benar-benar tuntas.
>
> ---
>
> **Enam lubang kontrak yang baru kelihatan saat dikerjakan**, dan tidak satu pun
> kelihatan saat dibaca:
>
> 1. **`S1-007` melanggar acceptance-nya sendiri** — `slug text NOT NULL` melawan
>    `03-erd.md` §1. Kompilator yang menemukannya, lewat `make generate`.
> 2. **`S1-008` punya dependensi melingkar** — acceptance-nya menuntut route khusus owner
>    yang baru ada di `S1-009`, yang `Depends`-nya justru `008`. Dan `/settings` saja
>    tidak cukup: kasus `404` butuh `{id}`, jadi `S1-010` ikut ditarik.
> 3. **Nol item membangun pengirim surel**, padahal `S1-084` menuntutnya. `S1-054` itu
>    WhatsApp di M5. Diselesaikan dengan Mailpit di balik interface `Mailer`; provider
>    produksi tetap keputusan M6.
> 4. **Nol endpoint untuk menerima undangan**, padahal tiga tempat menyebut "undangan
>    diterima". Tanpa `POST /auth/accept-invitation`, baris `invited` dari `S1-010` tidak
>    bisa dipakai sama sekali.
> 5. **`S1-083` bertentangan dengan `04-api-spec.md`** soal ke mana pendaftar mendarat.
>    Backlognya yang salah; acceptance-nya sudah diperbaiki.
> 6. **Batas laju tidak punya pemiliknya sendiri** — §7 menuntutnya di lima permukaan,
>    dan `S1-082` yang akhirnya membangun `internal/platform/ratelimit`.
>
> **Dan satu bug yang cuma bisa ditemukan dengan menjalankan, bukan membaca:** halaman
> verifikasi memanggil `/auth/refresh` sementara `SessionProvider` sedang mem-boot
> refresh-nya sendiri. Dua rotasi atas satu cookie dibaca server sebagai pencurian, dan
> deteksi pakai-ulang `S1-008` mencabut seluruh sesi penggunanya — **persis seperti yang
> seharusnya**. Klien sekarang single-flight.
>
> **Sisa sapuan yang belum dikerjakan:** komentar ber-ID `P1-xxx` di `sewain-api`,
> `internal/http/isolation_test.go` yang menyebut *brands/categories/products*, dan
> kutipan ke `tdd.md`/`flows.md` yang tidak ada di `docs/`.

> Batas route berdiri di `S1-013` dan tidak boleh kabur setelahnya: subtree backoffice
> (`app.sewain.id`) dan subtree publik (`<slug>.sewain.id` — katalog + `booking/[token]`). Subtree
> publik tidak mengimpor apa pun dari backoffice, dan tidak pernah menyetel cookie di scope
> `.sewain.id`.

---

## M1 · Katalog (minggu 4–5)

| ID | Item | Repo | Depends | Acceptance | Status | Owner |
|---|---|---|---|---|---|---|
| S1-014 | Skema `resources` | BE | 007 | Sesuai `03-erd.md`; jenis barang terpisah dari unit fisiknya (BR-010); `pricing_unit` `NOT NULL DEFAULT 'day'` **dengan CHECK enum** — `INSERT` tanpa nilai jatuh ke `day` bukan `NULL`, dan `'bulan'` **ditolak database**; ikut di-snapshot ke booking (BR-012, BR-017); `buffer_minutes` default 0 dan bisa diubah — tidak di-hardcode (BR-015) **Keempat nominal nullable dan `0` ditolak database** — `deposit_amount`, `late_fee_per_unit`, `min_duration`, `max_duration` (BR-016); `buffer_minutes` `NOT NULL DEFAULT 0`; `requires_id_verification` `NOT NULL DEFAULT false`; `max < min` ditolak | done | |
| S1-015 | Skema `resource_units` + unique `code` per owner | BE | 014 | Dua unit dengan kode sama pada satu owner ditolak; owner lain boleh pakai kode itu (BR-011) | done | |
| S1-016 | Resources CRUD | BE | 014 | Ubah `base_price` tidak menyentuh booking mana pun; respons menyebut jumlah booking berjalan (BR-014) ; `pricing_unit` **diisi server dari `owners.business_type`** — dikirim klien → `422` (BR-017); resource tanpa deposit/denda/batas durasi bisa disimpan, dan `PATCH` dengan `null` **mencabut** nilai yang sudah ada (BR-016) | done | |
| S1-017 | Units CRUD + peringatan booking terdampak | BE | 015 | Set `maintenance` mengembalikan `200` + daftar booking terdampak, tidak menghapus & tidak membatalkan (BR-013) | done | |
| S1-018 | Layar resource: daftar, editor, harga & deposit | FE | 016 | **Tidak ada pemilih satuan harga di form** — preset fase 1 cuma punya satu satuan (BR-017); field harga, deposit, dan denda tidak dirender untuk `operator` (BR-003); prompt saat meninggalkan perubahan belum tersimpan | done | |
| S1-019 | Layar unit: daftar per resource, ubah status | FE | 017 | Mengubah unit ke `maintenance` menampilkan daftar booking terdampak dan meminta konfirmasi — bukan menolak, bukan membatalkan (BR-013) | done | |
| S1-085 | **Skema atribut kendaraan** + deskripsi & S&K resource | BE | 016, 017 | `vehicle_specs` & `vehicle_unit_details` sebagai tabel pendamping 1:1, keduanya ber-RLS dan ber-FK komposit `(id, owner_id)` — spek yang menunjuk resource pemilik lain **ditolak database**, bukan aplikasi (BR-001, BR-094); tiga CHECK lintas kolom hidup: **kursi wajib pada mobil DAN dilarang pada motor**, `clutch` hanya motor, `diesel` hanya mobil; `vehicle_type` **tidak ada di skema `PATCH`** — dikunci sesudah dibuat; `category` diisi server dari `vehicle_type`, dikirim klien → `422` (BR-094); preset `vehicle_rental` tanpa `vehicle` → `422` **dan** preset lain dengan `vehicle` → `422`; `resources.description` + tiga `terms_*` dengan batas panjang ditegakkan database (BR-095) | done | |
| S1-086 | Profil usaha: `whatsapp`, `address`, `operating_hours` | BE | 009 | Ketiganya lewat `GET`/`PATCH /settings` 🔒 owner; `whatsapp` berformat `+62` + 8–13 digit **ditolak database** kalau lain (BR-096); ketiganya nullable karena itu keadaan awal tiap usaha baru (BR-005); `SessionOwner.business_type` ikut terbit supaya frontend bisa bercabang. **Menambal janji yang sudah ada:** `04-api-spec.md` §4 mengirim `owner.whatsapp` sejak sebelum kolomnya ada, dan acceptance `S1-068` bergantung padanya | done | |
| S1-087 | Layar resource: spek kendaraan, deskripsi, S&K | FE | 085, 086 | Kartu Kendaraan **hanya dirender untuk preset `vehicle_rental`** — juragan `equipment_rental` tidak melihatnya sama sekali (BR-094); **tetap nol pemilih satuan harga** (BR-017); kursi hilang dari layar begitu jenisnya Motor; tombol **"Pakai contoh"** menyalin placeholder jadi isi sungguhan, placeholder-nya konstanta di kode (BR-017 aturan 4); **kalimat tenggat bayar/denda/no-show dirender sistem dan tidak bisa diketik** (BR-095); "Salin S&K dari resource lain" | done | |
| S1-088 | Layar unit: tahun, warna, pajak, STNK | FE | 085 | Tahun wajib, warna opsional, dua tanggal opsional; **dua tanggal itu tidak pernah dirender di permukaan publik** (BR-094); field-nya hilang untuk preset non-kendaraan | done | |

> **M1 tuntas, enam dari enam** — dan `docs/03-verify-constraints.sql` ternyata sudah memuat
> harness beserta 12 kasus uji untuk kedua tabel ini jauh sebelum item-nya dikerjakan. `S1-014`
> dan `S1-015` karena itu menyalin DDL yang sudah tertulis, bukan mendesainnya.
>
> **Empat cacat kontrak yang ketemu saat menelusuri, semuanya diperbaiki di sini:**
>
> | Cacat | Perbaikan |
> |---|---|
> | `04-api-spec.md` §3.2 menulis `/resources/{id}` "🔒 untuk harga & deposit", menyiratkan operator boleh mengubah nama barang. `internal/auth/roles.go` — satu-satunya definisi matriks BR-003 — tidak pernah memberinya `resources:write` | Kolom Peran jadi "GET semua; PATCH/DELETE 🔒", plus paragraf yang menjelaskan cek `pricing:write` yang menumpang di atasnya |
> | §3.2 menghitung `requires_id_verification` sebagai "field kelima yang boleh `null`", padahal ERD dan skrip bukti sama-sama `NOT NULL DEFAULT false` | Jadi **empat**, dengan alasannya ditulis |
> | `03-verify-constraints.sql` membuat `resource_units_owner_resource_status` sebagai `(owner_id, code)` — kolom identik dengan unique index di atasnya, jadi membuktikan nol. ERD menulis `(owner_id, resource_id, status)` | Harness ikut ERD |
> | `03-verify-with-check.sql` masih menulis "kasus RLS 5/5" sejak sebelum M0 | 5/6 |
>
> **Tiga constraint ditambahkan di luar yang tertulis di ERD §3,** dan skrip bukti tumbuh
> **43 → 47** karenanya: dua CHECK enum status (`resources_status_valid`,
> `resource_units_status_valid`), FK komposit `resource_units_resource_matches_owner`, dan
> `resources_base_price_nonneg`. Yang ketiga paling perlu dibaca ulang kalau tidak setuju —
> **cek FK berjalan sebagai pemilik tabel dan melewati RLS**, jadi FK biasa ke `resources(id)`
> menerima id pemilik mana pun; unit itu akan terbaca oleh A sementara jenis barangnya milik B,
> dan booking yang lahir darinya men-snapshot harga B (BR-001, BR-014). Polanya disalin dari
> `refresh_tokens_user_matches_owner`.
>
> **Dua field terbit kosong sampai M2, dan itu disengaja.** `active_bookings` pada
> `PATCH /resources/{id}` dan `warning.affected_bookings` pada `PATCH /units/{id}` keduanya
> `0`/`[]` sampai `S1-022` membuat tabel `bookings`. Bentuk responsnya mendarat sekarang supaya
> layar `S1-018`/`S1-019` ditulis sekali; yang menyusul cuma isi query-nya, bukan pemanggilnya.
>
> **Dua bug yang cuma ketemu dengan menjalankan, bukan membaca:** CHECK enum status ditulis
> inline di `CREATE TABLE`, jadi PostgreSQL menamainya sendiri (`resources_status_check`) dan
> `translate()` yang mencocokkan nama meleset — `500` di tempat kontrak menjanjikan `422`. Dan
> pesan `Problem.detail` dari `internal/catalog` berbahasa Inggris seperti seluruh
> `platform/errors`, lalu dirender apa adanya ke form yang seluruhnya Indonesia; kata-katanya
> sekarang milik layar, pola yang sama dengan `email-taken` di `(auth)/register`.
>
> **Celah kontrak yang sengaja TIDAK diputuskan di sini.** `04-api-spec.md` §3.6 mewajibkan
> odometer saat pengambilan "bila resource bermeter", tapi tidak ada penanda `is_metered` di
> mana pun — `meter_value` justru kolom di `resource_units`, yang baru terisi sesudah
> serah-terima pertama. `S1-015` memang momen termurah memutuskannya, dan menebaknya berarti
> menambah kolom yang mungkin salah ke tabel yang seluruh M2 sudah telanjur menunjuknya.
> **Milik `S1-035`.**

> **M1 dibuka lagi: `S1-085`–`S1-088`.** `docs/ideas/vehicle-attributes.md` menjawab
> pertanyaan yang katalog generik tidak bisa jawab — penyewa yang harus bertanya lewat WA
> sebelum booking. Atributnya masuk lewat **tabel pendamping 1:1**, bukan kolom di
> `resources` dan bukan `jsonb`: `equipment_rental` sama-sama dibuka di fase 1 dan tidak
> boleh mewarisi kolom `transmission` yang selamanya kosong, dan tiga aturan lintas kolom
> yang jadi seluruh alasannya tidak bisa ditulis di `jsonb` (BR-094).
>
> **Kepadatan M1 jadi 10 item / 2 minggu = 5,0/mgg**, naik dari 3,0. Itu **di atas M2
> (4,33)**, milestone paling berisiko di proyek ini, dan di atas rata-rata 4,21. Angkanya
> ditulis di sini supaya bisa ditagih, bukan diserap diam-diam — kalau M1 mau dikembalikan
> ke ±4 ia butuh minggu ketiga dan seluruh jadwal bergeser jadi 20 minggu. Itu keputusan
> yang diambil sadar, bukan efek samping.
>
> **Tiga item lain acceptance-nya ikut berubah, bukan diam-diam dilewati:** `S1-066` (layar
> pengaturan wajib memuat tiga knob profil), `S1-060`/`S1-051` (halaman publik merender
> spek, deskripsi, blok S&K, dan tombol WA), `S1-068` (empty state publik akhirnya punya
> kontak untuk ditunjuk — sebelumnya acceptance-nya **tidak bisa dipenuhi siapa pun**).
>
> **Yang tetap di luar:** halaman publik sendiri (`S1-051`/`S1-060`, M5), layar pengaturan
> (`S1-066`, M5), dan template checklist serah-terima — `handovers.checklist` memang sudah
> ada di ERD, tapi `S1-034` yang memilikinya dan rantai `022 → 033 → 034` belum dimulai.


---

## M2 · Ketersediaan & booking (minggu 6–8)

**Risiko terbesar di seluruh proyek, dikerjakan lebih awal.** Kalau bagian ini tidak benar, tidak
ada satu pun bagian lain yang layak dibangun.

| ID | Item | Repo | Depends | Acceptance | Status | Owner |
|---|---|---|---|---|---|---|
| S1-020 | Skema `customers` + blacklist | BE | 007 | Hanya `owner` yang bisa memblokir/membuka (BR-028) | done | Claude |
| S1-021 | Identitas terenkripsi + `audit_logs` | BE | 020 | Membaca foto identitas menulis satu baris audit dalam transaksi yang sama (BR-085) | done | Claude |
| S1-022 | **Skema `bookings` + `end_at_with_buffer` + `bookings_no_overlap`** | BE | 015, 020 | Booking 3–5 Sep menolak booking 4–6 Sep untuk unit sama; berakhir 10:00 vs mulai 10:00 **tidak** bentrok; `end_at_with_buffer` diisi **trigger**, bukan aplikasi — nilai kiriman klien ditimpa; klausa `WHERE` constraint hanya memuat `reserved` & `picked_up`, jadi `draft` tidak mengunci (BR-023). **Jalankan `docs/03-verify-overlap-constraint.sql` dulu** — ia membuktikan semuanya di database scratch tanpa kode (BR-015, BR-022, BR-023) | done | Claude |
| S1-023 | **Test konkurensi** — dua insert bersamaan | BE | 022 | `make test-race`: tepat satu berhasil, satunya `booking-conflict`. Masuk `make check` selamanya | done | Claude |
| S1-024 | `booking_counters` + kode `<prefix>-nnnn` | BE | 022 | Unik per owner; menghapus booking tidak pernah mendaur ulang nomor; prefix dibaca dari `owners.booking_code_prefix` **saat kode dibuat** — mengubahnya tidak menyentuh kode lama dan tidak me-reset pencacah (BR-024) | done | Claude |
| S1-025 | Pencarian ketersediaan | BE | 022 | p95 < 1 detik untuk 500 unit × 12 bulan; unit `maintenance` hilang; buffer 120 menit menggeser tersedia dari 10:00 ke 12:00 (BR-013, BR-015, BR-020) | done | Claude |
| S1-026 | Bookings API: create, confirm, cancel | BE | 012, 024, 025 | Snapshot harga & buffer terisi server; durasi di luar `min`/`max` → `422`; penyewa blacklist → `422`; `confirm` menjalankan **ulang** cek bentrok (BR-014, BR-021, BR-026, BR-028) ; `min`/`max` kosong berarti **tanpa batas**, bukan nol; snapshot `deposit_amount`/`late_fee_per_unit` yang `NULL` tersalin sebagai `NULL` (BR-016) | done | Claude |
| S1-027 | Tukar unit pada booking `reserved` | BE | 026 | Unit tujuan lolos cek bentrok; setelah `picked_up` → `409 unit-not-swappable` (BR-029) | done | Claude |
| S1-078 | `GET /calendar` + `state` delapan keadaan | BE | 025, 041 | Satu field `state` per segmen, **dihitung server** — klien tidak pernah menyusunnya dari gabungan status booking + status invoice + status unit; `is_overdue` **tidak lagi** field terpisah, ia salah satu nilai `state`; `draft` tidak pernah muncul; respons publik hanya `available`/tidak (BR-033, BR-025) | done | Claude |
| S1-028 | **Kalender ketersediaan** | FE | 025, 078 | Satu lajur per unit, **semua unit**, dengan windowing — hanya sel dalam viewport yang dirender. **50 unit × 30 hari: first byte p95 < 1 detik** (sama anggaran dengan `S1-025`); pan & scroll dalam rentang yang sudah termuat **tanpa fetch ulang**; **200 unit × 12 bulan tetap responsif** — tidak membeku, tidak merender 182.500 sel; render awal dari server, bukan air terjun fetch di klien **Legenda delapan keadaan tampil di layar**, tiap blok berlabel teks + pola — bukan cuma warna; `draft` tidak dirender, `returned` tampil `available`, unit `retired` tidak punya lajur (BR-033) | done | Claude |
| S1-029 | Form booking | FE | 026 | Operator berpengalaman selesai **< 60 detik**; `409 booking-conflict` menampilkan booking yang bentrok + aksi pilih tanggal/unit lain, tidak pernah retry otomatis | done | Claude |
| S1-030 | Daftar booking + filter | FE | 026 | Filter `overdue` bekerja sebagai kondisi turunan, bukan status di dropdown (BR-041) | done | Claude |
| S1-031 | Layar penyewa + blacklist | FE | 020 | Aksi blokir/buka hanya dirender untuk `owner`; peringatan blacklist muncul saat membuat booking (BR-028) | done | Claude |
| S1-032 | Tukar unit dari layar booking | FE | 027 | Aksi hilang begitu status `picked_up` — bukan muncul lalu gagal (BR-029) | done | Claude |

> **S1-023 adalah item yang membuktikan klaim utama produk ini.** Ia bukan test sekali jalan — ia
> hidup di `make check` supaya tetap gagal kalau nanti ada yang "mengoptimasi" constraint jadi cek
> di aplikasi.

> **M2 tuntas kecuali `S1-021`** (foto identitas menunggu `S1-033`). Tiga belas item, dua commit
> kode — bukan satu per item: `make generate` menambahkan semua route M2 ke `ServerInterface`
> sekaligus, jadi commit seukuran item tidak bisa dikompilasi.
>
> **S1-023 dua test, bukan satu** (`internal/booking/race_test.go`). Acceptance-nya — dua create
> serentak, tepat satu menang — bisa lulus tanpa constraint kalau scheduler kebetulan
> menyerialkan goroutine-nya dan pre-check yang menangkap. Test kedua menulis baris kedua saat
> yang pertama belum commit, melewati pre-check mana pun: drop `bookings_no_overlap` dan ia merah
> setiap kali.
>
> **Ketemu dengan menjalankan, bukan membaca:** di bawah RLS, PostgreSQL tidak memakai qual yang
> tidak *leakproof* sebagai kondisi index — dan `&&` range serta `tstzrange()` tidak leakproof.
> Ketersediaan 500 unit × 12 bulan makan **1,6 detik**. Semua pembacaan kini menulis irisan
> sebagai dua perbandingan `timestamptz` terhadap btree `bookings_unit_start`; p95 **14 ms**,
> kalender 500 × 12 bulan **98 ms**. Constraint-nya sendiri tidak terdampak (dicek sebagai pemilik
> tabel). Test perf wajib `ANALYZE` sesudah seeding, atau planner menebak satu baris.
>
> **Tiga penyimpangan yang ditulis, bukan diserap:**
>
> | Yang tertulis | Yang terjadi | Kenapa |
> |---|---|---|
> | `S1-028` "render awal dari server" | Render klien, **satu** fetch per jendela 3 bulan, tanpa air terjun | Access token hanya ada di memori browser; server component tidak punya apa pun untuk memanggil API. Item tersendiri |
> | `reserved_paid` di kalender | Belum pernah terbit — setiap `reserved` adalah `reserved_unpaid` | Tabel `invoices` baru ada di `S1-041`; "belum dibayar" memang keadaan yang benar sampai itu |
> | `routeAccessTable` per route | Hanya `POST /bookings` yang idempoten | `accessFor` mencocokkan path literal; `S1-035` (`/bookings/{id}/pickup`) wajib mengajarinya pola dulu |
>
> **Satu bug lintas repo yang cuma ketemu di browser:** form booking memakai ulang
> `Idempotency-Key` sesudah `409`, dan server memutar ulang `409` yang tersimpan untuk submit yang
> sudah dikoreksi. Kunci kini hidup sampai server *menjawab*; gagal jaringan dan
> `request-in-flight` tetap memakai kunci yang sama.

---

## M3 · Serah-terima (minggu 9–10)

Alur yang dipakai sambil berdiri di parkiran. PRD §10: **< 3 menit**.

| ID | Item | Repo | Depends | Acceptance | Status | Owner |
|---|---|---|---|---|---|---|
| S1-033 | Adapter object storage S3-compatible | BE | 001 | **Diuji seluruhnya terhadap MinIO lokal — nol akun luar dibutuhkan.** **Presign PUT (10 menit, `Content-Type` + `Content-Length` diikat pada tanda tangan) dan `HEAD` untuk verifikasi sebelum commit** (BR-093) — bukan cuma presign GET; **CORS MinIO lokal dikonfigurasi** supaya `PUT` dari browser benar-benar bisa diuji, bukan ditemukan rusak saat deploy; objek tidak bisa dibaca tanpa URL bertanda tangan; TTL: **foto serah-terima 1 jam, berkas ekspor 15 menit (BR-077), foto identitas 5 menit (BR-085)**; kunci berprefiks `owner_id` sehingga satu kunci bocor tidak membuka milik pemilik lain; adapter yang sama dipakai R2 di produksi (`S1-074`) | done | Claude |
| S1-034 | `handovers` + `handover_photos`, append-only | BE | 022, 033 | Satu baris per arah per booking, dan transisi `reserved→picked_up` / `picked_up→returned` wajib membuatnya (BR-035); tidak ada query `UPDATE`/`DELETE` di `db/queries/`; `PATCH`/`DELETE` → `405 evidence-immutable` (BR-037) | done | Claude |
| S1-035 | `POST /bookings/{id}/pickup` | BE | 012, 034 | Menerima `photo_keys[]`, **bukan** `multipart` — tiap kunci di-`HEAD` dan disalin dari `pending/` ke prefiks final dalam transaksi yang sama (BR-093); kunci karangan atau milik pemilik lain → `422 upload-not-found`; tanpa kunci → `422`; resource bermeter tanpa odometer → `422`; flag bayar-dulu aktif & belum lunas → `409`; unit belum balik → `409` sampai `confirm_physical_conflict` (BR-036, BR-038, BR-042) | done | Claude |
| S1-036 | `return-preview` + `POST /return` | BE | 012, 035 | `photo_keys[]` diverifikasi `HEAD` seperti `S1-035` (BR-093); `actual_return_at` dari jam server, bukan body; denda = `ceil(kelebihan / pricing_unit) × late_fee_per_unit` dari snapshot; pembebasan tercatat beserta alasan (BR-040, BR-046) ; `proposed_lines` adalah **usulan** — baris yang tidak ada di `confirmed_lines[]` tidak terbit sama sekali; resource tanpa tarif denda tidak mengusulkan `late_fee` tapi `overdue_units` tetap dihitung; `Idempotency-Key` wajib (BR-016, BR-051, BR-090) | done | Claude |
| S1-037 | Alur serah-terima ambil & kembali, mobile-first | FE | 035, 036 | Bisa diselesaikan satu tangan di HP; kamera terbuka langsung dari alur; **unggah langsung ke R2** lewat presign, byte tidak lewat API (BR-093); foto 5MB menampilkan progres nyata dari `PUT`-nya dan **tidak pernah** memblokir form; syarat foto minimal 1 terlihat sejak awal (BR-036) | done | Claude |
| S1-038 | Pratinjau denda telat + jalur pembebasan | FE | 036 | Denda tampil sebelum dikonfirmasi; tombol bebaskan sebagian/seluruhnya terlihat, dengan field alasan wajib (BR-046) ; daftar centang memuat denda **dan** kerusakan, sisa deposit dihitung ulang tiap centang berubah; menghapus centang tanpa alasan → form ditolak (BR-051) | done | Claude |
| S1-039 | Galeri bukti kondisi, hanya-baca | FE | 034 | Tidak ada tombol hapus atau ganti pada foto handover, termasuk untuk `owner` (BR-037) | done | Claude |

> **M3 tuntas — dan `S1-021` ikut tertutup.** Dua item ditarik maju dari M4, keduanya sadar:
> **`S1-041`** (invoice + baris) supaya `return` menerbitkan baris sungguhan dan bayar-dulu
> (BR-038) membaca status invoice sungguhan, bukan bendera palsu; **`S1-043`** ikut karena M3
> sudah menerbitkan baris `damage`, dan constraint fotonya tidak boleh menyusul belakangan.
> M4 karena itu tinggal pembayaran, deposit, dan ekspor.
>
> **Empat celah kontrak yang diputuskan:**
>
> | Celah | Keputusan |
> |---|---|
> | "Bermeter" tidak didefinisikan di mana pun (catatan M1 menyerahkannya ke `S1-035`) | Resource punya spek kendaraan (BR-094). Tanpa kolom baru |
> | `damages[].handover_photo_id` menunjuk foto yang baru lahir di request yang sama | `photo_key`, salah satu `photo_keys` request itu; server yang menerjemahkan |
> | Pembebasan **penuh** tidak punya baris invoice untuk menampung alasannya | Jumlah + alasan di baris handover kembali (`handovers_waiver_complete`) |
> | Baris dari return masuk invoice yang mana | Satu invoice baru per return, `<kode>/<n>` |
>
> **Penegakan oleh database, bukan disiplin:** `handovers`/`handover_photos` kehilangan
> `UPDATE`/`DELETE` untuk `app_user`, seperti `audit_logs`. `PATCH`/`DELETE /handovers/{id}`
> terdaftar justru supaya jawabannya `405 evidence-immutable`, bukan `404`. Harness tumbuh
> **66 → 79 kasus**.
>
> **Object storage diuji terhadap MinIO sungguhan, termasuk dari browser:** tanda tangan
> presign menolak `Content-Type` atau `Content-Length` lain di tingkat storage; dua foto di-`PUT`
> langsung dari browser (390×844) saat uji ambil/kembali — CORS lokal terbukti, bukan diasumsikan.
> `/healthz` kini `HeadBucket` bertanda tangan, jalan juga di R2. **CORS R2 masuk daftar `S1-074`.**
>
> **Yang belum diukur:** target < 3 menit di HP mid-range jaringan seluler (PRD §10) adalah
> `S1-072`, bukan emulator.

---

## M4 · Uang (minggu 11–12)

Dibuka oleh `S1-040`: dua milestone sesudahnya (M4 dan M5) menaruh pekerjaan di antrean, dan
tanpa runner-nya masing-masing akan menumbuhkan `time.Ticker` sendiri.

| ID | Item | Repo | Depends | Acceptance | Status | Owner |
|---|---|---|---|---|---|---|
| S1-040 | **Job runner**: `cmd/worker` (Redis Streams) + `cmd/scheduler` | BE | 001, 004 | Satu pekerjaan gagal di-retry dengan backoff lalu masuk dead-letter, bukan hilang; job berjadwal tidak pernah jalan dobel walau ada 2 replika; **dipakai apa adanya oleh S1-046, S1-052, S1-054, S1-057** tanpa diubah (BR-091) | wip | Claude |
| S1-041 | `invoices` + `invoice_lines` | BE | 012, 026 | `total` selalu `SUM(lines)`, tidak ada kolom total; `discount` negatif, sisanya positif (BR-055); status salah satu dari lima nilai BR-056 — `gateway_pending` tak terjangkau di fase 1; invoice pertama memuat baris `rent` **dan** `deposit` (BR-045); **`due_at` diisi server saat terbit** = `min(created_at + payment_due_hours, booking.start_at)` — tidak pernah dari klien, tidak pernah kosong (BR-057) | done | Claude |
| S1-042 | Penyelesaian deposit | BE | 012, 036, 041 | Sisa < 0 menerbitkan invoice baru sebesar selisih; deposit tidak pernah negatif; `completed` diblokir sebelum diselesaikan (BR-048, BR-049) ; `POST /bookings/{id}/deposit/waive` 🔒 owner mencabut baris `deposit` selama invoice belum lunas, sesudah lunas → `409 deposit-already-paid`; booking tanpa deposit **tidak** memblokir `completed` (BR-016, BR-051) | wip | Claude |
| S1-043 | Baris `damage` merujuk foto pengembalian | BE | 034, 042 | Baris `damage` tanpa `handover_photo_id` ditolak database, bukan hanya aplikasi (BR-047) | done | Claude |
| S1-044 | Pembayaran manual & tunai | BE | 012, 041 | Pembayaran sukses kedua atas satu invoice → `409 invoice-already-paid` (BR-060) | wip | Claude |
| S1-045 | ~~Gateway + webhook idempoten~~ → fase 2 | BE | 044 | **Jalur gateway nonaktif di fase 1** — pembayaran manual saja (`04-api-spec.md` §3.8.1, BR-061). Kontrak BR-063/BR-064 ditinggal utuh untuk fase 2 | dropped | |
| S1-046 | Bukti transfer + pembacaan AI asinkron | BE | 033, 040, 044 | Bukti diunggah langsung ke R2, API menerima `object_key` lalu `HEAD` (BR-093) → `202`; hasil AI hanya rekomendasi; lunas butuh persetujuan manusia (BR-062) | wip | Claude |
| S1-047 | Layar invoice berbaris | FE | 041 | `total` dihitung dari baris yang dikirim server; `350000` tampil sebagai **Rp 350.000** — rupiah penuh, bukan minor unit | wip | Claude |
| S1-048 | Layar penyelesaian deposit | FE | 042 | Kasus sisa negatif menampilkan invoice baru yang terbit, bukan deposit minus (BR-048); `completed` tidak bisa ditekan sebelum diselesaikan (BR-049) ; aksi bebaskan deposit **tidak dirender** untuk `operator` (BR-003, BR-051); booking tanpa deposit tidak menampilkan layar ini sama sekali (BR-016) | wip | Claude |
| S1-049 | Unggah bukti transfer + persetujuan | FE | 046 | Hasil AI ditampilkan sebagai **rekomendasi** dengan aksi setujui/tolak, tidak pernah sebagai status lunas (BR-062) | wip | Claude |
| S1-050 | ~~Alur bayar gateway~~ → fase 2 | FE | 045 | Ikut `S1-045`. Portal penyewa fase 1 hanya mengunggah bukti, tidak membayar di tempat (`04-api-spec.md` §3.8.1) | dropped | |

---

## M5 · Halaman publik, API eksternal, notifikasi, laporan (minggu 13–16)

| ID | Item | Repo | Depends | Acceptance | Status | Owner |
|---|---|---|---|---|---|---|
| S1-051 | API publik: resolusi tenant dari `Host` + rate limit | BE | 012, 025, 026 | `owner_id` dari header `Host`, **tanpa slug di path**; host asing, owner `suspended`, dan resource owner lain → `404` **identik**; respons tidak memuat kode unit / id unit / nama penyewa; rate limit per IP **dan** per pemilik; **`Host` palsu yang dikirim langsung ke aplikasi tanpa proxy ditolak** — termasuk dari dalam jaringan compose, karena `web` pun wajib lewat proxy; kasus isolasinya masuk `make test-iso` (BR-025, BR-030) ; respons memuat **spek kendaraan, `description`, dan blok S&K** (BR-094, BR-095) plus profil usaha di `GET /public/owner` (BR-096); **`vehicle_unit_details` tidak pernah ikut** — `code` adalah plat nomor dan BR-025 sudah melarangnya keluar; empat kalimat tenggat/denda/no-show **dirakit server**, tidak pernah dari teks juragan | todo | |
| S1-052 | Job kedaluwarsa: draft **dan** tenggat bayar | BE | 026, 040, 041 | **Tiga transisi, satu job.** Draft lewat `draft_expiry_hours` → `cancelled` alasan `expired` (BR-027); `reserved` belum lunas lewat `due_at` **dan** `require_payment_before_pickup` menyala → `cancelled` alasan `payment_expired`, invoice `overdue` (BR-057, BR-038); `reserved` lewat `start_at + no_show_tolerance_hours` (**default 3**) → `no_show`. **Job tidak pernah menyentuh booking yang sudah punya baris `handovers`**, dan `pickup` atas booking `no_show` tidak langsung ditolak — dua kewajiban itu berlaku berapa pun toleransinya, karena pemilik boleh menurunkannya sampai `0` (BR-057). Sakelar **mati** → booking **tidak** dibatalkan, invoice tetap ditandai `overdue`; ambangnya per pemilik, tidak di-hardcode (BR-027) | todo | |
| S1-053 | Token portal penyewa | BE | 026 | Token hanya membuka satu booking; tidak bisa menjangkau booking, katalog, atau laporan lain (BR-002) | todo | |
| S1-054 | WhatsApp Cloud API + penjadwalan pengingat | BE | 026, 040 | **Lima jenis** (BR-070): `invoice_link` saat invoice terbit, `payment_due_reminder` sebelum `due_at` (BR-057), H-1 ambil, H-1 balik, dan saat kondisi telat terpenuhi. **Dua yang pertama tidak bisa dimatikan** — satu membawa tagihan, satu mendahului pembatalan; tiga sisanya bisa dimatikan pemilik satu per satu; **tanpa** pairing nomor pribadi (BR-070, BR-073) | todo | |
| S1-055 | Webhook WhatsApp + pengingat telat berhenti sendiri | BE | 054 | **`GET` verifikasi langganan** membalas `hub.challenge` apa adanya — tanpanya webhook tidak bisa didaftarkan (BR-073); **`X-Hub-Signature-256` diverifikasi, gagal → `401` sebelum menyentuh apa pun**; status dikorelasikan lewat `notifications.provider_message_id`, `wamid` tak dikenal → `200` tanpa efek **bukan `404`** (Meta me-retry apa pun selain `2xx`); pesan masuk dibalas `200` lalu dibuang; pengingat telat maksimal 1×/hari, maksimal 3×, lalu eskalasi jadi tugas operator; kegagalan tercatat beserta alasan (BR-071, BR-072, BR-073) | todo | |
| S1-056 | Laporan | BE | 041 | Empat laporan minimum BR-075 tersedia: pemasukan per periode per jenis baris, tingkat pemakaian per unit, unit menganggur > 30 hari, booking terlambat. Pemasukan menjumlahkan `rent` + `late_fee` + `damage` + `discount` saja; deposit terpisah sebagai saldo titipan (BR-050, BR-076) | todo | |
| S1-057 | Ekspor laporan (CSV + XLSX) | BE | 040, 056 | Ekspor lewat job runner, bukan di request (BR-077, BR-091); tautan unduh kedaluwarsa 15 menit dan bisa dibuat ulang; **deposit tetap kolom terpisah dari pemasukan** (BR-050, BR-076); 12 bulan × 500 unit < 60 detik | todo | |
| S1-058 | ~~`subscriptions` + penegakan kuota~~ → ditunda | BE | 015, 041 | **Langganan ditunda dari fase 1** (BR-080–BR-082). Tabel `subscriptions` tetap dibuat oleh `S1-041` dan tetap kosong; `invoices.kind`/`subscription_id` dan `invoices_one_subject` tetap jalan, jadi menyalakannya nol migrasi. **Fase 1 tanpa batas unit & pengguna.** Harga sudah diputuskan (PRD §13); pemicunya sekarang **jalur pembayaran menyala** (BR-061), karena BR-082 menagih lewat gateway yang sama | dropped | |
| S1-059 | ~~Job retensi identitas~~ → ditunda | BE | 021, 040 | **Retensi dinonaktifkan di fase 1** (BR-086). Tidak ada job penghapus, jadi foto identitas menumpuk tanpa batas waktu; `customers.id_purge_after` tetap ada dan tetap tidak dibaca. Pemicu: keputusan UU PDP setelah PT berdiri (PRD §12 #3) | dropped | |
| S1-060 | **Halaman publik `<slug>.sewain.id`** | FE | 051 | `middleware.ts` memetakan `Host` → slug dan me-rewrite ke subtree publik; **slug tidak pernah muncul di URL**; ketersediaan `force-dynamic`, tanpa ISR; **panggilan SSR ke API memakai origin yang sedang dilayani** (dibaca dari `headers()`, bukan konstanta) dan **balik lewat proxy** — memanggil `api:8080` langsung membuat tenant hilang dan semua halaman publik `404` (BR-030); **Caddy lokal wajib** supaya ini bisa diuji sebelum deploy; tidak merender kode unit / id unit / nama penyewa; host asing → `notFound()` tanpa membedakan diri dari owner nonaktif (BR-025, BR-030) ; merender kartu spek, deskripsi, blok S&K, dan **tombol WA dari `owners.whatsapp`**; halaman **tidak hidup** sebelum `slug` + `whatsapp` + `address` terisi (BR-094, BR-095, BR-096) | todo | |
| S1-061 | Form pengajuan di halaman publik | FE | 051 | Sukses berbunyi "menunggu konfirmasi pemilik", **bukan** "booking berhasil" (BR-026); penyewa blacklist menerima pesan netral tanpa alasan blokir (BR-028) | todo | |
| S1-062 | Portal penyewa `/booking/[token]` | FE | 053 | Memuat jadwal, tagihan, foto kondisi, status deposit — tidak ada booking lain, katalog, atau laporan (BR-002); token tidak pernah masuk `localStorage` atau analytics; **menampilkan instruksi transfer + nomor rekening pemilik dan tombol unggah bukti, tanpa tombol bayar gateway** (`04-api-spec.md` §3.8.1, §5) | todo | |
| S1-063 | Dashboard | FE | 026, 056 | Booking telat muncul sebagai peringatan (BR-041); `operator` tidak melihat satu pun angka pemasukan (BR-003) ; **daftar "deposit belum diselesaikan"** sebaris dengan peringatan telat — tanpa itu BR-049 cuma ketahuan kalau ada yang membuka booking satu per satu (BR-033 memilih tidak menampilkannya di kalender) | todo | |
| S1-064 | Layar laporan + tombol ekspor | FE | 056, 057 | Deposit tampil sebagai saldo titipan **terpisah** dari pemasukan, bukan catatan kaki (BR-050, BR-076); ekspor **poll `GET /jobs/{id}`**, tidak memblokir layar, dan menyebutkan tautannya berumur 15 menit (BR-077); owner saja | todo | |
| S1-065 | Layar notifikasi + kegagalan kirim | FE | 055 | Kegagalan kirim terlihat beserta alasannya, bisa dicoba ulang (BR-072) | todo | |
| S1-066 | Onboarding: langkah tersisa + pengaturan pemilik | FE | 009, 083, 086 | Slug, **`booking_code_prefix`** (BR-024), `require_payment_before_pickup`, ambang draft, dan tiga sakelar pengingat semuanya bisa diatur; mengubah prefix menampilkan peringatan bahwa kode yang sudah terbit tidak ikut berubah. **Daftar langkah di dashboard** (barang → unit → booking pertama) **dihitung dari data, bukan kolom progres**; bisa dilewati, tidak pernah memblokir, hilang sendiri saat selesai (BR-005) ; **profil usaha `whatsapp`/`address`/`operating_hours` diatur di sini** (BR-096, `S1-086`), dan layar wajib menyebut bahwa halaman publik belum hidup sampai `slug` + `whatsapp` + `address` ketiganya terisi — bukan membiarkan juragan menebak kenapa halamannya kosong | todo | |
| S1-067 | Layar Tim & peran | FE | 010 | Undang operator, ubah peran, **nonaktifkan akun**; status undangan terkirim/pending terlihat. Salinannya menyebut "nonaktifkan", bukan "hapus" — barisnya tetap ada supaya `created_by` bisa dijelaskan (BR-004). `operator` **tidak melihat navigasinya sama sekali** — bukan melihat lalu ditolak (BR-003) | todo | |
| S1-068 | Empty state yang jujur | FE | 028, 060 | **Ada di tujuh layar bernama**: katalog resource (`S1-018`), unit (`S1-019`), kalender (`S1-028`), daftar booking (`S1-030`), penyewa (`S1-031`), laporan (`S1-064`), dan **halaman publik** (`S1-060`). Tiap satu punya **tepat satu aksi utama** yang menunjuk langkah berikutnya, bukan "tidak ada data". Yang publik paling penting: penyewa yang mendarat di katalog kosong harus tahu harus menghubungi siapa — **dan sejak `S1-086` ada kolomnya**; sebelum itu acceptance ini tidak bisa dipenuhi siapa pun (BR-096) | todo | |
| S1-079 | `api_keys` + `owners.allowed_origins` + CRUD kunci | BE | 051 | Rahasia kunci **dibalas sekali saja** lalu hanya hash argon2id + 8 char prefix yang disimpan; `DELETE` **mencabut** (`revoked_at`), tidak menghapus baris — log akses lama harus tetap bisa dijelaskan (BR-031) | todo | |
| S1-080 | Middleware `X-API-Key` + CORS + kuota per kunci | BE | 079 | Kunci **hanya** membuka empat endpoint §4; endpoint backoffice → `404`; kunci dicabut → `401`; `Origin` di luar allowlist → `403`, dengan `Vary: Origin` supaya cache tidak menyajikan izin satu pemilik ke pemilik lain; kuota habis → `429`. **Test silang jalur wajib:** kunci sah di `<slug>.sewain.id` dan `Host` pemilik di `api.sewain.id` sama-sama tidak mengubah tenant (BR-031, BR-032) | todo | |
| S1-081 | Layar kelola kunci API di pengaturan | FE | 066, 080 | Rahasia ditampilkan **sekali** dengan peringatan jelas bahwa ia tidak bisa dilihat lagi; daftar kunci menampilkan prefix, `last_used_at`, dan status cabut; `allowed_origins` bisa diatur di layar yang sama; `operator` tidak melihat navigasinya (BR-003, BR-031) | todo | |

---

## M6 · Kesiapan produksi & pilot (minggu 17–18)

Sengaja diturunkan dari `M0`. Tidak satu pun bisa didemokan hari ini — belum ada mesin dan belum
ada domain — dan tidak ada di `M0`–`M5` yang membutuhkannya, karena backend dikembangkan di atas
layanan host dari `S1-001`.

Tidak bisa turun lebih jauh dari sini. `S1-076` menaruh katalog rental sungguhan di mesin itu, dan
itu tidak boleh terjadi di atas storage yang belum pernah dipulihkan.

| ID | Item | Repo | Depends | Acceptance | Status | Owner |
|---|---|---|---|---|---|---|
| S1-069 | CI: lint, test, test-iso, test-race, migrasi di snapshot, drift kontrak | BE | 002 | PR yang merusak salah satunya berwarna merah. **`services: postgres:18` GitHub Actions, bukan docker-in-docker** — sama seperti lokal, test bicara ke PostgreSQL biasa lewat connection string. **`docs/03-verify-overlap-constraint.sql` dan `docs/03-verify-constraints.sql` ikut dijalankan di CI** — constraint yang di-drop seseorang nanti bikin PR merah, bukan ketahuan di produksi | todo | |
| S1-070 | Playwright: booking → serah-terima → deposit selesai | FE | 048 | Satu siklus penuh lewat di CI | todo | |
| S1-071 | Playwright: halaman publik → draft → konfirmasi operator | FE | 061 | Termasuk kasus subdomain asing dan draft kedaluwarsa | todo | |
| S1-072 | Uji perangkat sungguhan untuk alur serah-terima | FE | 037 | Android kelas menengah, jaringan seluler, satu tangan, **< 3 menit** | todo | |
| S1-073 | VPS, Docker Compose, Caddy, TLS wildcard | OPS | — | `docker compose up` melayani HTTPS di `sewain.id`, `app.`, `api.`, **dan `*.sewain.id`**; wildcard **wajib** lewat DNS-01 token Cloudflare — ACME HTTP-01 tidak bisa menerbitkannya; `/api/*` dirutekan ke service `api`, sisanya ke `web`, **`Host` diteruskan utuh**; **hairpin jalan** — `web` bisa memanggil `https://<slug>.sewain.id/api/…` dari dalam dan sampai balik ke Caddy (BR-030 render sisi server); port `web` dan `api` **tidak** terbuka ke publik — nol `ports:` di kedua service, hanya Caddy yang punya `80:80`/`443:443` (BR-030) | todo | |
| S1-074 | PostgreSQL 18 + Redis tuned **+ provisioning R2** | OPS | 073 | `shared_buffers` ≈ 25% RAM; `cpus`/`mem_limit` per layanan terisi. **Bucket R2 sungguhan berdiri**: prefix per owner; **CORS bucket mengizinkan `PUT` dari `<slug>.sewain.id` dan `app.sewain.id`** — tanpa ini unggahan browser mati total (BR-093); **lifecycle menghapus `pending/` setelah 24 jam**; kredensial terpisah dari kredensial lokal. **Tidak ada object storage di mesin ini** — objek tinggal di R2, supaya kehilangan mesin tidak berarti kehilangan foto bukti | todo | |
| S1-075 | **Backup PostgreSQL ke R2 + latihan restore** | OPS | 074 | `pgBackRest` ke **R2, bukan ke disk mesin yang sama** — base backup harian + WAL berkelanjutan. **Restore dari R2 ke mesin bersih berhasil**, dan objeknya masih terbaca karena tidak pernah tinggal di mesin itu. Memblokir semua data pelanggan | todo | |
| S1-076 | Onboarding design partner: katalog asli masuk | OPS | semua | Satu rental sungguhan menjalankan seminggu penuh di sistem ini | todo | |

> **S1-075 adalah gerbang pilot.** `S1-076` tidak mulai sebelum latihan restore lulus.
>
> Backup ke mesin yang sama bukan backup. Itu sebabnya `S1-075` bergantung pada `S1-033`: R2 harus
> sudah berdiri sebelum ada yang bisa dicadangkan ke sana, dan object storage sengaja **tidak**
> ikut di `S1-074`. Foto serah-terima adalah satu-satunya bukti sengketa deposit (BR-037) —
> kehilangannya tidak bisa dipulihkan dari mana pun.

> **CI di minggu 16 bukan kelalaian.** Aturan "satu item, satu PR, `make check` hijau" adalah
> jaring pengaman minggu 1–15; `S1-069` menjadikannya otomatis, bukan menciptakannya. Ia juga
> tidak bergantung pada VPS — jalan di runner dengan `services: postgres`.
>
> **Rantai infra (`S1-073`–`S1-075`) sengaja di ekor.** CI (`S1-069`) **tidak** bergantung
> padanya — ia jalan di runner, bukan di mesin produksi; prasyaratnya `S1-002`, karena cek drift
> kontrak butuh `openapi.yaml`. Versi sebelumnya menulis `CI → VPS`, warisan keliru dari
> `P1-004` new-commerce, dan itu menyandera CI pada mesin yang belum ada.
>
> **Domain produksi cukup diputuskan sebelum M6**, bukan sebelum proyeknya mulai. Syaratnya satu:
> **apex domain wajib konfigurasi, bukan konstanta** — `middleware.ts` (pemetaan `Host`→slug) dan
> Caddy membacanya dari env, sehingga M0–M5 tidak tersandera nama yang belum dibeli.

> **`S1-072` tidak bisa diganti emulator.** Angka 3 menit itu diukur di lapangan bareng design
> partner, bukan di DevTools dengan throttling.

---

## M7 · Promosi (minggu 19)

Sesudah kriteria selesai fase 1 (`S1-076`), bukan bagian darinya. Produk dulu terbukti dipakai,
baru dijual.

| ID | Item | Repo | Depends | Acceptance | Status | Owner |
|---|---|---|---|---|---|---|
| S1-077 | Halaman promosi `sewain.id` | FE | 073 | Fitur dan jalur daftar. **Tabel harga dirender dari PRD §13** (gratis / Rp 99.000 / Rp 249.000) — harganya sudah diputuskan meski penagihannya belum menyala. **Nol data pemilik atau penyewa dirender** — ia halaman statis, bukan bagian aplikasi; tidak mengimpor apa pun dari `(app)/` maupun `(public)/` | todo | |

> **`sewain.id` bukan `<slug>.sewain.id`.** Yang di sini menjual Sewain ke pemilik rental. Yang
> di M5 adalah katalog yang dipakai penyewa — fitur MVP #5, dan target metrik PRD §10 "booking
> dari halaman publik ≥ 20%". Cuma yang pertama boleh ditunda.

---

## Definisi Selesai

Sebuah item `done` kalau **semuanya** benar. Bukan tujuh dari delapan.

1. Kolom Acceptance terbukti benar, dengan test bila test memungkinkan.
2. Cocok dengan kontrak di `docs/`. Kalau tidak bisa, kontraknya berubah dulu, di PR sendiri.
3. Error memakai envelope RFC 9457 beserta `trace_id`.
4. Tidak ada field yang dikelola server diterima dari klien.
5. `make generate` / `npm run generate` no-op di tree yang bersih, di dua repo.
6. **BE:** isolasi owner tetap utuh — route baru tercakup suite `S1-005`.
7. **FE:** layar tidak merender aksi yang perannya tidak punya. Tombol nonaktif yang tetap `403`
   bukan pemenuhan BR-003, ia pelanggarannya dengan langkah tambahan.
8. Ditinjau orang yang tidak menulisnya.

---

## Di luar ruang lingkup fase 1

Dicatat di sini karena akan diusulkan, berkali-kali, dan jawabannya sebaiknya satu tautan.

| Permintaan | Fase |
|---|---|
| Tagihan bulanan berulang, kontrak kos | 2 |
| Kalender per jam, jadwal berulang mingguan | 3 |
| Resource berupa orang, catatan kunjungan | 4 |
| Direktori/marketplace publik lintas pemilik | 5 |
| Multi-cabang | 2 (jualan naik paket, setelah langganan dinyalakan) |
| Akuntansi lengkap (jurnal, neraca) | — tidak direncanakan |
| Tanda tangan digital kontrak | — foto + timestamp sudah cukup |
| GPS tracking kendaraan | — butuh hardware, bisnis yang beda |
| Integrasi asuransi | — butuh partner |
| Dynamic pricing | — belum diminta, butuh data historis |
| Bayar online lewat payment gateway | 2 — nonaktif di fase 1; dinyalakan begitu **akun merchant aktif**, kontraknya utuh di `04-api-spec.md` §3.8.1 |
| Custom domain yang dilayani sewain (`rentalbudi.com` → CNAME) | — tidak direncanakan; pemilik pakai API key fase 1 (`S1-079`–`S1-081`, BR-031) |
| Sinkronisasi offline | — **tidak akan pernah**, lihat PRD §9 |
| Unit fungible tanpa penugasan di muka | — hanya kalau ada tenant yang terbukti kehilangan penjualan karenanya |
