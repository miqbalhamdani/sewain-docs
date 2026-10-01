# Business Rules — Sewain

> Rujukan waktu ngoding. Format mengikuti `boarding-house-api/docs/business-rules.md`
> supaya konsisten dengan codebase yang sudah ada.
>
> Aturan bertanda **[warisan]** dipakai apa adanya dari codebase kos — jangan
> ditulis ulang. Bertanda **[baru]** khas rental.
>
> Turunannya: [`03-erd.md`](./03-erd.md) (skema & constraint) dan
> [`04-api-spec.md`](./04-api-spec.md) (kontrak endpoint).

---

## 1. Multi-tenant

### BR-001 Isolasi pemilik **[warisan]**
Setiap pemilik hanya bisa mengakses data dengan `owner_id` sama dengan pemilik
terautentikasi. Berlaku untuk **setiap tabel yang punya `owner_id`** — `users`,
`refresh_tokens`, `api_keys`, `booking_counters`, `resources`, `resource_units`,
`customers`, `bookings`, `handovers`, `handover_photos`, `invoices`, `invoice_lines`,
`payments`, `payment_gateway_transactions`, `payment_proofs`, `subscriptions`,
`notifications`, `audit_logs`.

Tepat satu tabel sengaja di luar daftar ini: `owners`. Ia **adalah** tenant-nya, jadi
`owner_id` tidak punya arti di sana (`03-erd.md` §2).

`owner_id` **selalu** diturunkan dari token, **tidak pernah** diterima dari
request body.

**Penegakannya di database, bukan di query.** Setiap tabel bertenant menyalakan
`ENABLE ROW LEVEL SECURITY` **dan** `FORCE ROW LEVEL SECURITY`, dengan policy yang
membandingkan `owner_id` terhadap `current_setting('app.owner_id')`. Aplikasi
tersambung sebagai peran yang tidak memiliki tabel apa pun.

Ini naik satu tingkat dari `boarding-house-api`, yang menegakkan aturan ini lewat
filter di setiap query. Filter di query benar sampai ada satu query yang lupa — dan
yang lupa **tidak gagal**, ia mengembalikan data pemilik lain. RLS mengubah mode
gagalnya jadi baris kosong.

**`FORCE` yang menentukan, bukan `ENABLE`.** Tanpa `FORCE`, pemilik tabel melewati
policy-nya sendiri — dan peran itulah yang menjalankan migrasi. Konfigurasi yang
salah ini **terlihat sehat sepenuhnya**: semua orang lain tersaring benar, cuma satu
peran yang melihat segalanya. Karena itu ia punya guard sendiri (`S1-006`) dan kasus
uji sendiri di `03-verify-constraints.sql`, bukan diserahkan ke review kode.

Owner di-set per **transaksi** (`set_config(..., true)`), tidak pernah per koneksi:
pool koneksi membuat `SET` yang bocor ikut ke request pemilik berikutnya.

### BR-002 Akses penyewa **[warisan]**
Penyewa hanya bisa melihat booking, invoice, dan bukti kondisi miliknya sendiri.
Penyewa tidak bisa mengakses dashboard pemilik, katalog, maupun laporan.

### BR-004 Satu user, satu usaha **[baru]**
Setiap user milik tepat satu usaha. `users.owner_id` menyatakan usaha mana, dan
`users.role` menyatakan perannya di situ. Tidak ada keanggotaan ganda, tidak ada
pengalih usaha, dan tidak ada usaha "aktif" yang bisa berubah di tengah sesi.

**Email unik secara global**, bukan per usaha — dan itulah yang membuat aturan ini
bekerja. `POST /auth/login` cuma membawa email dan password; kalau satu alamat bisa
ada di dua usaha, tidak ada apa pun di request itu yang bisa memilih di antara
keduanya. Baris `users` yang menyatakan usahanya, jadi satu alamat harus menunjuk
tepat satu baris.

**Harganya dibayar di muka, dan perlu diketahui sebelum ada yang mengeluh:** satu
alamat email = satu usaha. Orang yang menjalankan dua rental butuh dua akun dengan
dua email berbeda, begitu juga operator yang bekerja di dua rental. Itu batasan
yang disengaja, bukan keterbatasan yang menunggu diperbaiki — menukarnya berarti
login butuh parameter usaha, dan parameter itu datang dari request.

**Access token membawa `owner_id` dan `role`**, dua-duanya diambil dari baris
`users` saat login dan tidak pernah dari request. Refresh token juga terikat ke
satu usaha, karena user-nya memang cuma punya satu; tidak ada yang hilang dengan
mengikatnya.

**Batas paparan adalah TTL access token.** Peran yang diturunkan atau akun yang
dinonaktifkan tetap berlaku sampai token yang sudah terbit kedaluwarsa. Itu yang
membuat TTL pendek bukan sekadar kebiasaan.

Data milik usaha lain dijawab `404`, bukan `403` — selisih respons antar kasus
membocorkan usaha mana yang ada (BR-001, setara BR-030).

Usaha baru lahir lewat `POST /auth/register` (BR-005), bukan lewat `POST /users` —
yang terakhir cuma mengundang operator ke usaha yang sudah ada.

### BR-005 Pendaftaran mandiri **[baru]**
`POST /auth/register` adalah **satu-satunya jalur yang menciptakan usaha baru**. Ia
membuat baris `owners` **dan** baris `users` ber-`role = 'owner'` dalam satu transaksi.
`POST /users` tidak pernah menciptakan usaha — ia cuma mengundang operator ke usaha
yang sudah ada (BR-004).

Isian pendaftaran: email, password, nama usaha, dan **preset pasar** (BR-017).
**`slug` tidak ditanyakan di sini** — ia opsional, berbayar, dan diisi belakangan dari
`PATCH /settings` (BR-025). Memilih subdomain adalah keputusan yang belum bisa diambil
juragan sebelum melihat produknya, dan tiap field di layar daftar adalah tempat orang
berhenti.

| Aturan | Kenapa |
|---|---|
| Email unik global, kalau sudah dipakai → `422` | BR-004; itu yang membuat login cukup email+password |
| Satu transaksi — `owners` tanpa `users` tidak boleh pernah ada | Usaha tanpa pemilik adalah baris yatim yang tidak bisa dimasuki siapa pun |
| Dibatasi laju per IP | Endpoint tanpa autentikasi, semangat yang sama dengan BR-030 |
| `owners.status` mulai `active` | Gerbangnya di level pengguna, bukan usaha — `users.email_verified_at` (BR-006) |

**Endpointnya milik M0, halaman daftarnya milik M7.** Tanpa aturan ini
`POST /auth/login` tidak punya baris untuk diverifikasi — seluruh rantai dependensi
proyek ini bermuara ke skema `owners`/`users` lalu mengasumsikan barisnya sudah ada.
Halaman promosi `sewain.id` nanti cuma menautkan ke alur yang sudah berdiri sejak
minggu pertama.

### BR-006 Verifikasi email **[baru]**
Pendaftaran terbuka untuk publik sejak hari pertama (BR-005), dan **email wajib
terverifikasi sebelum pengguna boleh melakukan apa pun di backoffice.** Tersimpan
sebagai `users.email_verified_at` — satu kolom nullable, bukan status baru.

Alasannya bukan menyaring akun sampah, itu cuma efek samping. **Email adalah
satu-satunya identitas pemilik yang punya bukti** — tidak ada verifikasi usaha, tidak
ada KYC (BR-005). Kalau backoffice bisa dipakai tanpanya, juragan bisa mengisi 50 unit,
ratusan booking, dan seluruh riwayat serah-terima ke dalam akun yang **tidak punya
jalur pemulihan sama sekali**: lupa password satu kali, dan semuanya hilang tanpa cara
mengembalikannya. Verifikasi wajib melindungi data pemiliknya sendiri.

Sebelum terverifikasi, pengguna **cuma boleh melakukan empat hal**:

| Diizinkan | Kenapa |
|---|---|
| Login & refresh sesi | Tanpanya ia tidak bisa sampai ke layar verifikasi |
| Membaca `/me` | Frontend perlu tahu keadaannya untuk merender dindingnya |
| Verifikasi & kirim ulang | Justru jalan keluarnya |
| Logout | Selalu boleh |

**Semua permintaan lain dibalas `403 email-not-verified`**, tanpa kecuali — termasuk
katalog, booking, serah-terima, dan invoice. Penegakannya di middleware, satu tempat,
bukan dicek per handler: gerbang yang harus diingat di tiap endpoint adalah gerbang yang
akan terlewat di endpoint ke-31.

**Operator undangan tidak perlu verifikasi terpisah.** Undangan dikirim ke emailnya dan
hanya bisa diterima lewat tautan di email itu (BR-004) — menerimanya **sudah** bukti
kendali atas alamatnya, jadi `email_verified_at` terisi saat undangan diterima. Mengirim
surel verifikasi kedua setelah surel undangan adalah meminta bukti yang sama dua kali.

Tautan verifikasi **sekali pakai, umur 24 jam**. Kedaluwarsa bukan jalan buntu: kirim
ulang selalu tersedia, karena satu-satunya hal yang bisa dilakukan akun belum
terverifikasi adalah memverifikasi dirinya.

**Harga yang dibayar aturan ini, supaya tercatat:** juragan tidak melihat satu pun
layar produk sebelum membuka emailnya, dan surel yang nyangkut di spam menghabisi
percobaan pertama. Itu diterima sebagai imbalan atas akun yang selalu bisa dipulihkan.
Kalau angka aktivasi nanti menunjukkan orang berhenti di dinding ini, yang ditinjau
ulang adalah **aturan ini**, bukan pengiriman surelnya.

**Squatting slug bukan risiko pendaftaran.** Slug tidak diambil saat daftar
(BR-005, BR-025) — ia dipilih belakangan, sengaja, oleh pemilik berbayar. Pendaftar
yang cuma mencoba lalu menghilang tidak pernah menahan nama siapa pun.

### BR-003 Peran operator **[baru]**
Peran yang diizinkan: `owner`, `operator`. Tersimpan di `users.role` — satu peran
per orang, karena satu orang cuma punya satu usaha (BR-004).

Operator **tidak boleh**: melihat laporan keuangan, mengubah harga atau deposit,
menghapus data apa pun, mengelola pengguna, mengubah pengaturan langganan.

Operator **boleh**: membuat & mengubah booking, memproses serah-terima, mencatat
pembayaran, mengelola data penyewa.

---

## 2. Katalog

### BR-010 Resource dan unit **[baru]**
`resources` adalah jenis barang; `resource_units` adalah barang fisiknya.
Booking selalu menunjuk satu `resource_unit`, tidak pernah hanya `resource`.

Resource tanpa unit aktif tidak boleh muncul di pencarian ketersediaan.

### BR-011 Kode unit unik **[baru]**
`resource_units.code` unik per `owner_id`. Ini yang dipakai operator
mengidentifikasi barang secara fisik (plat nomor, nomor seri).

### BR-012 Satuan harga **[baru]**
Satuan yang diizinkan: `hour`, `day`, `week`, `month` — **ditegakkan database**, bukan
cuma didaftar di sini. `resources.pricing_unit` `NOT NULL DEFAULT 'day'`, dan nilai di
luar keempatnya ditolak. Satuan tersimpan di level resource dan **ikut disalin ke
booking sebagai snapshot** (BR-014).

Ia dipakai dua kali di perhitungan uang: `duration_qty` dan rumus denda telat
`ceil(kelebihan / pricing_unit)` (BR-046). Itu yang membuat nilai kosong atau nilai
asing bukan sekadar kotor — ia menghasilkan tagihan yang salah.

**Yang memilihnya bukan juragan, tapi preset pasarnya** (BR-017). Server mengisi
`pricing_unit` saat resource dibuat; klien tidak pernah mengirimnya.

### BR-013 Status unit **[baru]**
Status yang diizinkan: `active`, `maintenance`, `retired`.

Hanya unit `active` yang muncul di pencarian ketersediaan. Mengubah unit menjadi
`maintenance` atau `retired` **tidak** menghapus atau membatalkan booking yang
sudah ada untuk unit itu — sistem menampilkan peringatan berisi daftar booking
terdampak dan pemilik yang memutuskan.

### BR-014 Snapshot harga **[warisan, diperluas]**
`bookings` menyimpan `unit_price`, `pricing_unit`, `deposit_amount`, dan
`late_fee_per_unit` sebagai salinan pada saat booking dibuat.

Nilai-nilai ini **tidak boleh** berubah otomatis ketika data di `resources`
diubah kemudian. Setara BR-012 pada codebase kos.

**Kosong ikut di-snapshot sebagai kosong.** `deposit_amount` dan
`late_fee_per_unit` yang `NULL` di resource tersalin sebagai `NULL` di booking
(BR-016) — bukan sebagai `0`. Booking yang dibuat waktu resource-nya belum pakai
deposit tetap tidak berdeposit selamanya, walau pemiliknya mengisi deposit besok.

### BR-015 Jeda antar sewa **[baru]**
`resources.buffer_minutes` adalah jeda wajib setelah `end_at` sebelum unit yang
sama bisa disewa lagi. Nilainya disalin ke booking dan ikut diperhitungkan dalam
cek bentrok (§BR-022).

Default 0. Nilainya wajib bisa diatur per resource — **jangan di-hardcode**.

**Ini satu-satunya field opsional yang tidak boleh kosong** (BR-016). `buffer_minutes`
`NOT NULL DEFAULT 0`, karena `end_at + NULL` menghasilkan NULL, dan
`tstzrange(start_at, NULL)` adalah rentang tak berbatas ke atas — unit itu akan
bentrok dengan seluruh booking masa depannya. "Tidak ada jeda" sudah persis sama
dengan `0`, jadi tidak ada yang perlu dibedakan.

### BR-016 Nilai kosong berarti tidak berlaku **[baru]**
Lima field di `resources` boleh kosong, dan kosong berarti **aturannya tidak
berlaku** untuk resource itu:

| Field | Kosong berarti |
|---|---|
| `deposit_amount` | tidak ada deposit (BR-045 tidak menerbitkan baris; BR-048/049 tidak berlaku) |
| `late_fee_per_unit` | tidak ada denda telat (BR-046 tidak menerbitkan baris) |
| `min_duration` | tidak ada durasi minimum (BR-021) |
| `max_duration` | tidak ada durasi maksimum (BR-021) |
| `requires_id_verification` | default `false` — BR-085 tidak wajib |

**`NULL` dan `0` adalah dua keadaan yang berbeda, dan keduanya tidak boleh
tertukar.** `NULL` berarti "aturan ini tidak berlaku"; `0` berarti "berlaku,
besarnya nol". Karena tidak ada satu pun kasus rental yang butuh deposit sebesar
nol rupiah atau denda nol rupiah, `0` **dilarang database** — satu keadaan, satu
cara menulisnya. Tanpa larangan itu, dua jalur insert yang berbeda menghasilkan
dua nilai untuk maksud yang sama, dan laporan tidak bisa membedakannya.

Ini juga menutup lubang yang sudah lama tercatat: hari ini tidak ada cara
membedakan buffer `0` yang dipilih pemilik dari buffer `0` karena satu jalur
insert lupa mengisinya. Larangan `0` menghapus kelas bug itu dari empat field
sisanya sekaligus.

**Satu akibat penting: kondisi terlambat tidak ikut mati.** Resource tanpa
`late_fee_per_unit` tetap memunculkan peringatan terlambat di dashboard dan tetap
mengirim pengingat (BR-041, BR-070). Yang hilang cuma tagihannya — juragan tetap
perlu tahu barangnya belum balik.

### BR-017 Preset pasar **[baru]**
Pemilik memilih **satu preset pasar** saat mendaftar (BR-005), tersimpan di
`owners.business_type`. Preset itulah yang menentukan satuan harga seluruh
resource-nya — bukan juragan mengisi satuan di tiap barang.

| Preset | Contoh usaha | Satuan yang berlaku | Default | Fase |
|---|---|---|---|---|
| `vehicle_rental` | mobil, motor | `day` | `day` | 1 |
| `equipment_rental` | kamera, HP, sound, tenda | `day` | `day` | 1 |
| `boarding_house` | kos | `month` | `month` | 2 |
| `apartment` | apartemen | `day`, `week`, `month` | `month` | 2 |
| `venue` | lapangan | `hour` | `hour` | 3 |
| `clinic` | praktisi | *(belum diputuskan)* | — | 4 |

> `clinic` sengaja dikosongkan: PRD §1 menulis satuannya "30 menit", nilai yang tidak ada
> di enum BR-012. Diputuskan di fase 4, bukan ditebak sekarang.

Empat aturan yang menempel:

1. **Server yang mengisi `pricing_unit` dari preset saat resource dibuat.** Klien tidak
   pernah mengirimnya, sama seperti `unit_price` dan `deposit_amount` (BR-014).
2. **Preset dengan satu satuan tidak pernah menampilkan pilihan apa pun.** Seluruh preset
   fase 1 masuk kategori itu, jadi **juragan rental tidak pernah melihat field satuan
   harga.** Menanyakannya berarti meminta dia menjawab pertanyaan yang cuma ada demi
   vertikal yang belum dibuka — dan PRD §3.1 sudah menyatakan juragan tidak akan mengisi
   data master sebelum bisa memakai produknya. Pemilih baru dirender ketika presetnya
   memang punya lebih dari satu satuan (`apartment`).
3. **Mengganti preset tidak mengubah resource yang sudah ada**, dan tidak menyentuh
   snapshot di booking. Preset menentukan nilai **saat pembuatan**, bukan nilai hidup —
   semangat yang sama dengan BR-014 dan BR-024.
4. **Pemetaan preset → satuan adalah konfigurasi produk, bukan data tenant.** Ia hidup
   sebagai tabel di aturan ini dan konstanta di kode; tidak disalin ke tiap baris
   `owners`. Enam preset harus punya satu sumber kebenaran, bukan satu per pemilik.

### BR-094 Atribut kendaraan **[baru]**
Preset `vehicle_rental` punya atribut yang tidak dimiliki vertikal lain: jenis,
transmisi, jumlah kursi, bahan bakar, tahun, warna, pajak, STNK. Ia disimpan di
**tabel pendamping 1:1** — `vehicle_specs` untuk jenis barangnya,
`vehicle_unit_details` untuk unit fisiknya — bukan sebagai kolom di `resources`
dan bukan sebagai `jsonb`.

Tiga alasan, dan ketiganya menolak satu alternatif masing-masing:

1. **`resources` tetap generik.** Kamera, kos, dan lapangan tidak mewarisi kolom
   `transmission` yang selamanya kosong. Ini persis mode gagal yang dipakai
   BR-017 aturan 2 untuk menolak pemilih satuan harga: field yang ada demi
   vertikal yang belum dibuka.
2. **Aturannya ditegakkan database.** "Kursi hanya untuk mobil", "kopling hanya
   untuk motor", dan "diesel hanya untuk mobil" semuanya `CHECK` lintas kolom.
   Dengan `jsonb` ketiganya cuma hidup di aplikasi — semangat yang sama dengan
   BR-012, yang menolak mendaftar satuan harga tanpa menegakkannya.
3. **Migrasi per vertikal memang wajar.** Vertikal baru tetap butuh form,
   placeholder, dan halaman publiknya sendiri. Satu tabel pendamping adalah
   bagian terkecil dari pekerjaan itu.

Dua aturan yang menempel:

- **`vehicle_type` dikunci sesudah resource dibuat.** Alasannya mekanis, bukan
  selera: `CHECK ((vehicle_type = 'car') = (seats IS NOT NULL))` membuat
  motor→mobil melanggar constraint kecuali kursinya ikut diisi di transaksi yang
  sama. Juragan yang salah pilih jenis membuat resource baru, dan itu lebih murah
  daripada jalur migrasi nilai yang dipakai sekali seumur hidup.
- **`resources.category` diturunkan dari `vehicle_type`, diisi server.** Klien
  tidak pernah mengirimnya, sama seperti `pricing_unit` (BR-017 aturan 1).
  Tujuannya supaya daftar resource generik tetap bisa dikelompokkan tanpa join;
  sumber kebenarannya tetap `vehicle_type`. Preset yang belum punya tabel
  pendamping membiarkan `category` kosong — bukan mengisinya dengan tebakan.

Preset tetap **satu**, `vehicle_rental`, dan jenis dipilih per resource. Rental
yang menyewakan mobil dan motor sekaligus harus muat di satu akun; memecah preset
jadi dua akan memaksanya punya dua.

### BR-095 Syarat & ketentuan resource **[baru]**
Tiga teks opsional per resource — **belum termasuk**, **syarat sewa**, dan
**pembatalan & perubahan** — plus `description` untuk fitur dan perlengkapan.
Bagian yang kosong tidak ditampilkan di halaman publik.

Satu aturan menjaga halaman itu tetap jujur, dan ia lebih penting daripada
ketiga kolomnya: **apa pun yang dihitung sistem tidak boleh diketik ulang
juragan.**

| Kalimat di halaman publik | Sumbernya |
|---|---|
| "1 hari = 24 jam" | `resources.pricing_unit` (BR-012) |
| "Bayar paling lambat X jam, atau booking batal otomatis" | `owners.payment_due_hours` (BR-057) |
| "Telat kembali dikenakan Rp X per hari" | `resources.late_fee_per_unit` (BR-016) |
| "Tidak datang lewat X jam dari jadwal = batal" | `owners.no_show_tolerance_hours` (BR-057) |

Keempatnya dirakit sistem dan **tidak bisa diedit**. Juragan yang mengetik ulang
"bayar maksimal 24 jam" ke dalam textarea akan salah pada detik ia mengubah
knob-nya, dan halaman publiknya berbohong tanpa ada yang tahu — persis kelas bug
yang dihapus BR-024 dari prefix kode booking dan BR-014 dari harga booking.

Teks dari juragan karena itu hanya untuk hal yang **tidak dijalankan sistem**:
refund, reschedule, ongkos antar, kebijakan BBM. Semuanya dieksekusi manual oleh
juragan sendiri, dan fase 1 memang tidak menjanjikan lebih.

**Keempatnya menerima markdown minimal** — tebal, miring, dan daftar berbutir.
Tidak lebih: tanpa tautan, tanpa gambar, tanpa tabel, tanpa heading. Kolomnya
tetap `text` polos dan batas `char_length` **ikut menghitung penandanya**, jadi
`**AC dingin**` memakan 15 dari jatah 500, bukan 9.

Yang dipilih di sini adalah markdown, **bukan HTML**, dan alasannya sama dengan
alasan batas panjangnya ada: halaman publik merender teks ini dan teks yang
dirender apa adanya adalah permukaan serangan kalau ia markup. Markdown gagal
dengan jinak — pembaca yang renderernya belum terpasang melihat `**AC dingin**`,
bukan skrip orang lain yang berjalan di peramban penyewa.

`S1-060` merendernya lewat **satu** renderer, dan renderer itu satu-satunya
tempat markdown berubah jadi elemen. Bagian yang tidak dikenalinya ditampilkan
sebagai teks biasa, tidak dibuang: syarat sewa yang hilang separuh lebih buruk
daripada syarat sewa yang tampil jelek.

---

## 3. Ketersediaan & booking

### BR-020 Definisi tersedia **[baru]**
Sebuah unit tersedia pada rentang `[T1, T2)` jika:
1. `resource_units.status = 'active'`, **dan**
2. tidak ada booking berstatus `reserved` atau `picked_up` pada unit itu yang
   rentang `[start_at, end_at + buffer)`-nya beririsan dengan `[T1, T2)`.

### BR-021 Batas durasi **[baru]**
`end_at` harus setelah `start_at`. Durasi harus berada di antara `min_duration`
dan `max_duration` milik resource, bila diisi.

"Bila diisi" berarti bukan-`NULL` (BR-016). Keduanya independen: `min_duration`
terisi sementara `max_duration` kosong berarti ada batas bawah tanpa batas atas.
Dua-duanya kosong berarti durasi apa pun boleh, sepanjang `end_at > start_at`.

### BR-022 Tanpa bentrok — dijamin database **[baru]**
Bentrok dicegah oleh *exclusion constraint* pada `bookings`:

```sql
CREATE EXTENSION IF NOT EXISTS btree_gist;

ALTER TABLE bookings
  ADD CONSTRAINT bookings_no_overlap
  EXCLUDE USING gist (
    resource_unit_id WITH =,
    tstzrange(start_at, end_at_with_buffer, '[)') WITH &&
  )
  WHERE (status IN ('reserved', 'picked_up') AND deleted_at IS NULL);
```

Aplikasi **tetap** mengecek lebih dulu agar pesan error enak dibaca dan bisa
menyebut booking yang bentrok — tetapi kebenarannya dijaga database, bukan
aplikasi. Pelanggaran constraint diterjemahkan menjadi error domain, mengikuti
pola `mapAssignmentUnique` di
`boarding-house-api/internal/repository/onboarding_repository.go:263-278`.

Batas rentang bersifat **awal inklusif, akhir eksklusif** (`[)`): booking yang
berakhir jam 10:00 dan booking yang mulai jam 10:00 **tidak** bentrok.

`end_at_with_buffer` **diisi trigger database**, bukan aplikasi — uraiannya di
`03-erd.md` §3. Dan aturan ini punya **bukti yang bisa dijalankan**:
`03-verify-overlap-constraint.sql`, di database scratch, tanpa satu baris kode
aplikasi. Jalankan sebelum menulis migrasinya — versi kolom generated sudah
gagal di sana, dan itulah gunanya.

### BR-023 Status yang mengunci **[baru]**
Hanya `reserved` dan `picked_up` yang mengunci unit. `draft`, `cancelled`,
`no_show`, `returned`, dan `completed` tidak.

Konsekuensi yang disengaja: pengajuan dari halaman publik (`draft`) **tidak**
memblokir penjualan sungguhan.

### BR-024 Kode booking **[baru]**
Setiap booking punya kode pendek yang enak dibacakan lewat telepon:

```
<owners.booking_code_prefix>-<angka urut per pemilik>
        RB-0042        JAYA-0007        SWN-0001
```

Unik per pemilik. Tidak pernah dipakai ulang — nomornya dari `booking_counters`
yang hanya naik, bukan dari `MAX(code)+1` yang salah begitu ada booking terhapus.

**Prefiksnya milik pemilik, bukan sistem.** `owners.booking_code_prefix` diatur di
`PATCH /settings` seperti knob pemilik lainnya, default `SWN`. Formatnya ditegakkan
database: **2–6 karakter, huruf besar atau angka**. Batas itu bukan selera — kode ini
dibacakan lewat telepon, dan prefix panjang membuat seluruh gunanya hilang.

Tiga hal yang mengikat:

1. **Mengganti prefix tidak mengubah kode yang sudah terbit.** `RB-0041`, `RB-0042`,
   lalu `BUDI-0043`. Semangat yang sama dengan BR-014: kode yang sudah dibacakan ke
   penyewa lewat telepon tidak boleh bergeser di belakang punggungnya.
2. **Nomornya tidak ikut reset.** Pencacah milik pemilik, bukan milik prefix.
3. **Tidak unik secara global.** Dua pemilik boleh sama-sama memakai `RB`. Kode tidak
   pernah keluar dari konteks satu pemilik — portal penyewa memakai token (BR-002),
   dan halaman publik tidak pernah menampilkan kode booking (BR-025). Yang dijaga
   database tetap keunikan per pemilik.

Nomornya empat digit ber-nol depan (`0042`) dan tumbuh sendiri setelah `9999` —
tidak ada batas atas yang dipasang.

### BR-025 Halaman publik per pemilik **[baru]**
**Satu backoffice, satu API, banyak halaman pemilik.** Halaman publik bukan
aplikasi terpisah dan bukan salinan data — ia hanya tampilan dari data yang sama
yang diisi pemilik di backoffice.

Pemilik **berbayar** punya satu halaman sendiri di **`<slug>.sewain.id`** —
`rentalbudi.sewain.id`, bukan `sewain.id/r/rentalbudi`. `owners.slug` **adalah**
label subdomain-nya, jadi ia tunduk pada aturan label DNS: 3–63 karakter, huruf
kecil/angka/hyphen, tidak diawali maupun diakhiri hyphen, dan tanpa hyphen di
posisi 3–4 (`xx--…` adalah ruang punycode; membiarkannya terbuka mengundang
pendaftaran yang menyerupai domain lain).

**`owners.slug` boleh kosong, dan kosong adalah keadaan awal setiap pemilik.**
Ia tidak ditanyakan saat mendaftar (BR-005) — diisi belakangan dari `PATCH /settings`,
dan butuh paket `usaha` ke atas (BR-080).

**Jangan tertukar: yang berbayar adalah aksesnya, bukan kapan fiturnya dibangun.**
`<slug>.sewain.id` hidup sejak fase 1 (M5). Yang menunggu langganan cuma gerbang
berbayarnya — dan selama itu belum menyala, siapa pun boleh mengisi slug dan halamannya
langsung jalan.

Tiga akibat yang perlu dipegang:

| Akibat | Rincian |
|---|---|
| Pemilik tanpa slug tidak punya host sama sekali | Halaman publik **dan** portal penyewa (BR-002) sama-sama hidup di `<slug>.sewain.id`, jadi keduanya ikut tidak ada |
| Penyewa di paket gratis tidak punya tautan apa pun | Tagihan, jadwal, dan foto kondisi disampaikan operator secara manual. Ini **harga yang dibayar tier gratis**, dan ia disengaja: halaman sendiri adalah pemicu naik paket yang paling terbaca |
| Slug baru dipesan saat seseorang benar-benar memilihnya | Bukan efek samping pendaftaran. Pendaftar yang cuma mencoba tidak pernah menahan nama yang tidak dipakainya |

**Di fase 1 gerbang ini tidak ditegakkan**, sama seperti seluruh kuota lain
(BR-080–082 ditunda): siapa pun boleh mengisi slug. Yang sudah diputuskan adalah
bentuknya, supaya menyalakannya nanti tidak butuh migrasi.

Slug unik secara global dan **tidak pernah dipakai ulang** oleh pemilik lain
setelah diganti — link yang sudah tersebar di WhatsApp tidak boleh mendarat di
rental orang lain.

**Daftar subdomain terlarang wajib ada.** Memindahkan pemisahan dari path ke host
tidak menghapus masalah tabrakan nama, ia memindahkannya: yang dulu bertabrakan
dengan route aplikasi (`/login`, `/dashboard`) sekarang bertabrakan dengan
subdomain infrastruktur (`app`, `api`, `mail`, `ns1`). Daftarnya ditegakkan
database, bukan validasi aplikasi — lihat `03-erd.md` §3.

**Backoffice tinggal di `app.sewain.id`, bukan di apex.** Begitu `*.sewain.id`
jadi milik pemilik, cookie sesi backoffice **tidak boleh** ber-`Domain=.sewain.id`:
ia akan terkirim ke setiap halaman publik yang bisa dibuka siapa saja. Host
terpisah membuat cookie itu host-only secara alami, tanpa mengandalkan seseorang
mengingat aturannya.

Yang tampil di halaman: katalog dan ketersediaan **asli**, dihitung memakai aturan
yang sama persis dengan BR-020. Tidak ada cache atau tabel salinan untuk halaman
publik; kalau backoffice dan halaman publik bisa berbeda, keduanya salah.

Sebuah resource muncul bila punya minimal satu unit `active` (BR-010, BR-013).
Ketersediaan ditampilkan di level **resource** — "ada / tidak ada unit yang bebas"
— bukan per unit. Penunjukan unit fisik tetap terjadi di server saat pengajuan
dibuat.

Halaman publik **tidak pernah** menampilkan data penyewa lain, nama penyewa,
harga khusus, maupun `resource_units.code`.

### BR-026 Draft tidak mengunci **[baru]**
Membuat draft tidak mengunci unit. Cek bentrok dijalankan ulang pada saat
konfirmasi (`draft → reserved`) — bukan pada saat draft dibuat.

### BR-027 Draft kedaluwarsa **[baru]**
Draft yang tidak dikonfirmasi dalam 24 jam otomatis menjadi `cancelled` dengan
alasan `expired`. Ambang waktunya bisa diatur per pemilik.

### BR-028 Penyewa terblokir **[baru]**
Penyewa yang ditandai `blacklisted` tidak bisa dibuatkan booking baru. Operator
melihat peringatan berisi alasannya. Hanya pemilik yang bisa memblokir atau
membuka blokir.

### BR-029 Tukar unit **[baru]**
Operator boleh menukar `resource_unit_id` pada booking `reserved` ke unit lain
dari resource yang sama, sepanjang unit tujuan lolos BR-022.

Setelah `picked_up`, unit **tidak bisa** ditukar — barangnya sudah di tangan
penyewa dan riwayatnya harus tetap jujur.

### BR-030 Resolusi tenant di jalur tanpa token **[baru]**
Endpoint publik dilayani API yang sama dengan backoffice. Ada **dua** jalur
menurunkan `owner_id` tanpa token, dan tidak akan pernah ada yang ketiga:

| Jalur | Sumber `owner_id` | Fase |
|---|---|---|
| Same-origin — `<slug>.sewain.id` | header `Host` | 1 |
| Eksternal — `api.sewain.id` | API key (BR-031) | 1 |

Tiga batasan yang berlaku di dua-duanya:

1. **Hanya-baca kecuali satu endpoint pengajuan.** Selebihnya `GET`.
2. **`owner_id` tidak pernah dari path, query, maupun body.** Slug **tidak lagi
   muncul di path sama sekali** — `GET /api/v1/public/resources`, bukan
   `/public/r/rentalbudi/resources`. Endpoint yang menerima slug sebagai parameter
   adalah endpoint yang bisa disuruh menunjuk pemilik lain.
3. **Tanpa autentikasi, jadi wajib dibatasi laju per IP dan per pemilik.**
   Pencarian ketersediaan dan pembuatan pengajuan sama-sama dibatasi.

Pengajuan dari halaman ini dibuat dengan `status = 'draft'` dan
`source = 'public_page'` (BR-026, BR-027).

Host yang tidak dikenal, pemilik nonaktif, atau resource milik pemilik lain
menghasilkan `404` yang sama — bukan `403` dan bukan pesan berbeda. Selisih
respons antar kasus adalah cara katalog pemilik lain bocor.

#### Kenapa `Host` boleh dipercaya padahal BR-001 melarang header

BR-001 melarang menurunkan `owner_id` dari header, dan `Host` adalah header. Yang
membedakan: **`Host` bukan data aplikasi, ia amplop routing.** Reverse proxy sudah
memilih sertifikat berdasarkan SNI dan menolak meneruskan host yang tidak
dikonfigurasi, jadi `Host` yang sampai ke aplikasi sudah tersaring sebelum menjadi
input.

Yang membuat ini benar bukan header-nya, tapi topologinya. Karena itu ada satu
kewajiban operasional yang tidak bisa ditawar: **API tidak boleh bisa dijangkau
tanpa melewati proxy.** Kalau port-nya terbuka, `curl -H "Host: rentalbudi.sewain.id"`
langsung ke aplikasi memilih pemilik mana pun yang diinginkan penyerang, dan
seluruh isolasi jalur publik runtuh — bukan bocor sedikit, runtuh.

Jangan "memperbaiki" aturan ini dengan menerima slug dari query sebagai jalan
aman. Itu justru menukar satu asumsi topologi yang bisa diuji dengan satu
parameter yang bisa dipalsukan siapa saja.

**Render sisi server ikut aturan yang sama — tanpa pengecualian.** Halaman publik
dirender di server (`S1-028`, `S1-060`), jadi Next.js memanggil API dari dalam server,
bukan dari browser. Panggilan itu **kembali lewat proxy** ke host publik yang sama:

```
browser ──→ Caddy ──→ web (SSR) ──→ Caddy ──→ api
                                 https://<host asli>/api/v1/…
```

Host-nya diambil dari permintaan yang sedang dilayani, **bukan dari konstanta** — jadi
tiap tenant terbawa sendirinya, dan tidak ada tempat untuk salah menuliskannya.

Alternatifnya — `web` memanggil `api` langsung di jaringan internal sambil memalsukan
`Host` — akan bekerja dan lebih cepat, tapi menggeser batas kepercayaan: `web` ikut jadi
bagian dari penjaga isolasi, dan kalimat "`Host` sudah tersaring proxy" berhenti berlaku
harfiah. **Itu ditolak.** Satu pintu, satu asumsi, satu test — `api` hanya bisa dicapai
lewat proxy, dari mana pun asal panggilannya.

### BR-031 API eksternal untuk situs pemilik **[baru]**
Pemilik yang punya situsnya sendiri (`rentalbudi.com`) boleh menarik katalog dan
ketersediaan dari sewain lewat `api.sewain.id`, memakai `X-API-Key` yang dimiliki
tepat satu pemilik.

**Aturan yang paling penting: kunci hanya membuka endpoint publik yang sama.**
Katalog, ketersediaan, dan pengajuan `draft` — itu saja. Bukan pintu ke
backoffice, bukan jalan ke data penyewa, bukan pintasan ke laporan. Batasan isi
respons di BR-025 tetap berlaku utuh: kode unit, id unit, dan nama penyewa tidak
pernah keluar, siapa pun pemanggilnya.

Origin yang diizinkan disimpan per pemilik (`owners.allowed_origins`) dan dibalas
sebagai header CORS. Perlu dinyatakan terang-terangan supaya tidak dipercayai
berlebihan: **origin allowlist bukan kontrol keamanan, ia kontrol browser.**
Siapa pun tetap bisa memanggil dengan `curl`. Yang benar-benar menjaga adalah
kuota per kunci, rate limit, dan kenyataan bahwa endpoint ini memang sudah
dirancang untuk dilihat publik.

Membuka jalur ini **tidak menambah permukaan kebocoran data** — yang bertambah
hanya permukaan penyalahgunaan kuota. Itu yang membuat keputusannya murah, dan
juga yang membuat kunci tidak boleh pernah dipakai untuk apa pun selain ini.

Rahasia kuncinya tidak pernah disimpan, hanya hash dan 8 karakter prefix untuk
ditampilkan; kunci **dicabut, tidak dihapus**, karena kunci yang hilang dari tabel
membuat log akses lama tidak bisa dijelaskan.

### BR-032 Dua jalur tanpa token tidak boleh menyeberang **[baru]**
BR-030 punya dua jalur, dan keduanya kini hidup berbarengan. Masing-masing hanya
mengenal caranya sendiri:

| Host | Menerima | **Menolak** |
|---|---|---|
| `<slug>.sewain.id` | tenant dari `Host` | `X-API-Key` — diabaikan, tidak pernah mengubah tenant |
| `api.sewain.id` | tenant dari `X-API-Key` | `Host` — tidak pernah jadi sumber `owner_id` |

Kalau `api.sewain.id` ikut membaca `Host`, satu kunci yang sah digabung `Host`
palsu jadi jalan menunjuk pemilik lain — dan asumsi yang menopang BR-030 (proxy
menyaring `Host` sebelum ia jadi input) tidak berlaku untuk host yang memang
dirancang menerima panggilan dari luar browser. Gabungan dua mekanisme yang
masing-masing aman menghasilkan satu yang tidak.

Kunci yang sah tapi dikirim ke `<slug>.sewain.id`, dan `Host` pemilik yang dikirim
ke `api.sewain.id`, sama-sama **tidak menaikkan hak apa pun**. Bukan error — cuma
diabaikan, lalu jalur host itu memutuskan tenant dengan caranya sendiri seperti
biasa.

### BR-033 Keadaan kalender **[baru]**
Kalender ketersediaan adalah layar yang paling sering dibuka juragan, dan tiap sel
di dalamnya punya **keadaan** — bukan status. Ketiganya beda asal: `maintenance`
datang dari status unit, "belum dibayar" dari status booking **dan** status invoice,
dan "tersedia" sama sekali tidak punya baris. Jadi kalender butuh kosakatanya
sendiri, diturunkan seperti `overdue` (BR-041) dan `rented` yang sudah lebih dulu
begitu.

Daftar tertutup, delapan keadaan. Tidak satu pun jadi kolom baru:

| Keadaan | Diturunkan dari | Warna acuan |
|---|---|---|
| `available` | unit `active`, tidak ada booking mengunci, di luar buffer | hijau |
| `reserved_unpaid` | `reserved` + invoice sewa belum lunas | biru |
| `reserved_paid` | `reserved` + invoice sewa lunas | biru tua |
| `picked_up` | `picked_up`, `end_at >= now()` | oranye |
| `overdue` | `picked_up`, `end_at < now()` (BR-041) | merah |
| `buffer` | jeda setelah `end_at` (BR-015) | arsir abu |
| `maintenance` | unit `maintenance` (BR-013) | hitam |
| `retired` | unit `retired` — **tidak dirender sama sekali** | — |

`draft` **tidak muncul di kalender.** Ia tidak mengunci unit (BR-023, BR-026), dan
blok yang terlihat sepadat `reserved` akan membuat operator menolak penjualan yang
sebenarnya boleh jalan. Draft hidup di daftar booking, bukan di kalender.
`returned` tampil `available` — barangnya memang sudah bebas disewakan lagi.

Empat aturan yang menempel:

1. **Keadaan dihitung server**, dikirim `GET /calendar` sebagai satu field `state`.
   Satu definisi untuk semua layar; kalau backoffice dan halaman publik bisa
   berbeda, keduanya salah (semangat BR-025). Klien tidak pernah menyusun keadaan
   sendiri dari gabungan status — di situlah dua layar mulai menyimpang.
2. **Warna tidak pernah jadi satu-satunya pembeda.** Tiap blok wajib punya label
   teks, dan keadaan selain `available` wajib punya pola atau border yang berbeda.
   Legenda wajib tampil di layar, bukan jadi hafalan. Operator memakai HP di bawah
   matahari, dan sebagian orang tidak bisa membedakan merah dari hijau — kalender
   yang hanya bisa dibaca lewat warna tidak bisa dibaca sebagian penggunanya.
3. **Halaman publik hanya mengenal dua keadaan: `available` dan tidak.** Tujuh
   sisanya membocorkan keadaan usaha pemilik — siapa belum bayar, unit mana masuk
   bengkel. BR-025 sudah melarang kode unit dan nama penyewa keluar; ini larangan
   yang sama untuk informasi yang bentuknya warna.
4. **Yang tidak masuk kalender wajib punya tempat lain.** Booking `returned` yang
   depositnya belum diselesaikan (BR-049) tidak terlihat di sini karena selnya sudah
   hijau. Ia muncul di dashboard sebagai daftar tersendiri, sebaris dengan peringatan
   terlambat. Tanpa itu, BR-049 cuma ketahuan kalau ada yang membuka booking-nya satu
   per satu.

### BR-096 Profil usaha yang dilihat penyewa **[baru]**
`owners` menyimpan tiga hal yang bukan knob melainkan identitas: **`whatsapp`**,
**`address`**, dan **`operating_hours`**. Ketiganya diatur dari `PATCH /settings`
seperti knob lain, dan ketiganya dibaca halaman publik (BR-025).

**Aturan ini menambal lubang, bukan membuka fitur.** `04-api-spec.md` §4 sudah
menjanjikan `{ "owner": { "name": …, "whatsapp": "+62…" } }` di respons katalog
publik sejak sebelum ada kolomnya, dan acceptance `S1-068` menuntut "penyewa yang
mendarat di katalog kosong harus tahu harus menghubungi siapa". Dua janji, nol
kolom di baliknya.

- **`whatsapp` satu-satunya yang dibaca mesin**, bukan mata: halaman publik
  menjadikannya tautan `wa.me`, jadi formatnya ditegakkan database (`+62`,
  8–13 digit). Nomor berformat bebas menghasilkan tautan mati, dan tautan mati di
  halaman yang seluruh gunanya menghubungi pemilik lebih buruk daripada tidak ada
  tombol sama sekali.
- **`address` adalah lokasi ambil default**, kecuali juragan menulis lain di
  syarat sewa (BR-095).
- **`operating_hours` teks bebas** dan sengaja tidak terstruktur. Jam buka rental
  Indonesia penuh pengecualian — "24 jam lewat WA", "Minggu janjian dulu" — dan
  memaksanya jadi tujuh baris buka/tutup membuat juragan mengisi data yang salah
  atau tidak mengisi sama sekali.

**Ketiganya nullable, dan kosong bukan kasus pinggir.** Ia keadaan awal setiap
usaha yang baru mendaftar, persis seperti `slug` (BR-025, BR-005) — pendaftaran
cuma menanyakan empat hal. Yang berlaku: **halaman publik tidak hidup sebelum
`slug`, `whatsapp`, dan `address` ketiganya terisi**, dan layar pengaturan wajib
mengatakan itu, bukan membiarkan juragan menebak kenapa halamannya kosong.

---

## 4. Serah-terima

### BR-035 Serah-terima wajib **[baru]**
Transisi `reserved → picked_up` dan `picked_up → returned` masing-masing wajib
membuat satu baris `handovers`.

### BR-036 Foto wajib **[baru]**
Setiap `handover` wajib memuat minimal 1 foto. Untuk resource dengan
`meter_value`, odometer/jam pakai juga wajib diisi.

Ini disengaja tidak bisa dilewati: satu-satunya alasan sengketa deposit (§2.2 PRD)
bisa diselesaikan adalah karena datanya selalu ada.

**"Minimal 1 foto" ditegakkan atas objek, bukan atas klaim.** Byte-nya diunggah langsung
ke R2 (BR-093), jadi yang sampai ke API cuma kuncinya — dan server memverifikasi tiap
kunci lewat `HEAD` sebelum menulis baris. Tanpa langkah itu, syarat ini bisa dipenuhi
dengan kunci karangan.

### BR-037 Bukti bersifat append-only **[baru]**
Baris `handovers` dan fotonya **tidak bisa diubah atau dihapus oleh siapa pun**,
termasuk pemilik. Koreksi dilakukan dengan menambah baris catatan baru, bukan
mengubah yang lama.

Aturan ini punya prasyarat yang tidak bisa dipenuhi aplikasi: **fotonya harus
tinggal di luar mesin aplikasi.** "Tidak bisa dihapus siapa pun" jadi bohong kalau
satu VPS mati membawanya, dan tidak ada tempat lain untuk memulihkannya. Karena itu
object storage-nya Cloudflare R2, bukan disk mesin yang sama — PRD §9 durabilitas.

### BR-038 Bayar sebelum ambil **[baru]**
Bila pemilik mengaktifkan `require_payment_before_pickup`, transisi
`reserved → picked_up` diblokir sampai invoice sewa lunas.

Default: nonaktif. Banyak rental menerima pembayaran saat pengambilan, dan
memaksakan sebaliknya bikin produk ini nggak kepakai.

Sakelar ini juga menentukan **apa yang terjadi saat tenggat bayar lewat** (BR-057):
menyala → booking yang belum lunas dibatalkan; mati → cuma invoicenya yang ditandai
`overdue`, dan batasnya pindah ke `no_show`.

### BR-040 Waktu kembali sebenarnya **[baru]**
`actual_return_at` diisi waktu server saat serah-terima kembali diproses,
bukan diketik operator. Nilai inilah dasar perhitungan denda telat.

### BR-041 Terlambat sebagai kondisi turunan **[baru]**
Terlambat **bukan** status. Kondisinya: `status = 'picked_up' AND end_at < now()`.

Booking dalam kondisi ini muncul di dashboard sebagai peringatan dan memicu
notifikasi (BR-071). Tidak ada job yang mengubah status karenanya.

### BR-042 Bentrok fisik **[baru]**
Bila unit punya booking berikutnya sementara booking saat ini masih `picked_up`
melewati `end_at`, sistem memperingatkan operator saat akan memproses
pengambilan berikutnya dan meminta konfirmasi eksplisit.

Secara jadwal tidak bentrok — secara fisik barangnya belum ada. Constraint
database tidak bisa menangkap ini; hanya peringatan yang bisa.

---

## 5. Deposit & denda

### BR-045 Deposit ditagih di muka **[baru]**
Deposit muncul sebagai baris `deposit` pada invoice pertama, bersama baris `rent`.

Ini **default, bukan keharusan**: resource tanpa `deposit_amount` tidak pernah
menerbitkan baris itu (BR-016), dan deposit yang terbit masih bisa dibebaskan per
booking selama invoice-nya belum lunas (BR-051).

### BR-046 Denda telat **[baru]**
Bila `actual_return_at > end_at`, denda = `ceil(kelebihan / pricing_unit) ×
late_fee_per_unit`, memakai nilai snapshot di booking.

Resource tanpa `late_fee_per_unit` tidak pernah menghasilkan baris ini (BR-016) —
tapi kondisi terlambatnya tetap berlaku utuh (BR-041).

Hasilnya **ditampilkan lebih dulu ke operator sebelum dikonfirmasi**, dan boleh
dibebaskan sebagian atau seluruhnya. Polanya di BR-051. Denda otomatis yang tidak
bisa dibatalkan akan bikin operator berhenti mencatat waktu kembali dengan jujur.

### BR-047 Biaya kerusakan **[baru]**
Operator boleh menambah baris `damage` dengan nominal dan keterangan. Wajib
merujuk ke minimal satu foto dari `handover` pengembalian.

Baris ini juga tunduk BR-051: ia diusulkan dan dicentang, tidak pernah terbit
sendiri.

### BR-048 Perhitungan sisa deposit **[baru]**
```
potongan   = denda_telat + biaya_kerusakan
sisa       = deposit_amount − potongan
```
- `sisa ≥ 0` → dikembalikan ke penyewa, tercatat di `deposit_refunded`.
- `sisa < 0` → deposit habis (`deposit_deducted = deposit_amount`) dan
  **selisihnya terbit sebagai tagihan baru**. Deposit tidak pernah bernilai negatif.

Potongan yang dipakai adalah yang **sudah dicentang operator** (BR-051), bukan
hasil hitungan mentah. Angka ini dihitung ulang tiap kali centangnya berubah.

**Tanpa deposit, aturan ini tidak berlaku sama sekali.** Booking yang
`deposit_amount`-nya kosong atau dibebaskan tidak boleh punya `deposit_deducted`
maupun `deposit_refunded` — bukan nol karena kebetulan, tapi tidak ada sama sekali,
dan database yang menolaknya. Denda telat dan biaya kerusakan pada booking seperti
itu tetap terbit seperti biasa; yang tidak ada cuma titipan untuk menutupinya.

### BR-049 Penyelesaian deposit wajib **[baru]**
Transisi `returned → completed` diblokir sampai deposit diselesaikan: dikembalikan,
dipotong, atau keduanya — dengan catatan alasan bila ada potongan.

**Booking tanpa deposit tidak diblokir.** Tidak ada yang perlu diselesaikan, jadi
`returned → completed` jalan begitu serah-terima kembali terisi (BR-016).

### BR-050 Deposit bukan pendapatan **[baru]**
Laporan pemasukan **wajib** memisahkan `deposit` dari `rent`, `late_fee`, dan
`damage`. Deposit adalah titipan, bukan penghasilan.

### BR-051 Pembebasan tagihan **[baru]**
Nilai di resource menentukan **default, bukan keharusan**. Deposit, denda telat,
dan biaya kerusakan sama-sama bisa dibebaskan per booking. Tidak semua penyewa
membayar deposit, dan tidak semua keterlambatan ditagih — itu keputusan usaha,
dan sistem yang memaksakan sebaliknya akan dikalahkan oleh operator yang berhenti
mencatat dengan jujur.

**Aturan yang menyatukan ketiganya: pembebasan hanya mungkin sebelum uangnya
masuk.** Sesudah dibayar, jalurnya pengembalian (BR-048), bukan pembebasan. Ini
yang menjaga satu hal tetap benar: **tidak ada invoice lunas yang pernah diubah.**

| Yang dibebaskan | Kapan masih bisa | Siapa |
|---|---|---|
| Deposit | selama invoice yang memuat barisnya belum lunas | operator & pemilik |
| Denda telat | saat pengembalian diproses, sebelum barisnya terbit | operator & pemilik |
| Biaya kerusakan | saat pengembalian diproses, sebelum barisnya terbit | operator & pemilik |

**Ini bukan pengecualian terhadap BR-003, karena bukan hal yang sama.** BR-003
melarang operator mengubah **nilai** deposit — angka di `resources` dan salinannya
di booking. Membebaskan penagihan pada satu booking tidak menyentuh angka itu:
`bookings.deposit_amount` tetap utuh apa adanya, yang berubah cuma apakah barisnya
ditagih. Nilainya urusan pemilik; penagihan satu transaksi urusan orang yang sedang
melayani penyewa di konter.

Yang membuatnya aman bukan pembatasan peran, tapi **jejaknya**: tiap pembebasan
menulis siapa, kapan, dan alasannya, dan ketiganya wajib terisi bersama
(`bookings_deposit_waiver_complete`). Pemilik menelusurinya belakangan; operator
tidak perlu menahan penyewa menunggu persetujuan yang tidak akan datang dalam
3 menit.

Empat kewajiban:

1. **Tidak ada baris yang terbit tanpa dicentang.** Sistem menghitung dan
   **mengusulkan**; operator melihat daftar centang berisi tiap baris dan
   nominalnya. Yang tidak dicentang tidak terbit — bukan terbit lalu dinolkan.
2. **Tiap pembebasan wajib punya alasan tercatat**, beserta siapa dan kapan.
   Pembebasan tanpa alasan ditolak, dan alasannya ikut ke laporan.
3. **Deposit yang dibebaskan menghapus barisnya dari invoice** — bukan diimbangi
   baris `discount`. `discount` terhitung sebagai pemasukan (BR-076), jadi
   mengimbangi deposit dengannya akan **mengurangi angka pemasukan sebesar nilai
   deposit**, persis kesalahan yang BR-050 ada untuk mencegah. Invoice yang belum
   lunas belum jadi kewajiban; ia masih boleh berubah.
4. **Konfirmasinya `POST` yang menghasilkan uang**, jadi tunduk `Idempotency-Key`
   (BR-090). BR-090 sudah menandai baris `damage` sebagai satu-satunya jalur tanpa
   constraint: submit ganda di situ menagih penyewa dua kali untuk satu lecet.

---

## 6. Invoice & pembayaran

### BR-055 Invoice berbaris **[baru]**
Satu invoice memuat satu atau lebih `invoice_lines`. Jenis yang diizinkan:
`rent`, `deposit`, `late_fee`, `damage`, `discount` (bernilai negatif).

Total invoice = jumlah seluruh barisnya. Total tidak pernah disimpan terpisah
sebagai sumber kebenaran.

### BR-056 Status invoice **[warisan]**
`unpaid`, `gateway_pending`, `paid`, `overdue`, `cancelled`.

`overdue` terbit saat `now() > due_at` dan invoice belum lunas (BR-057). Ia **status
kolom**, berbeda dari `overdue` pada booking yang merupakan kondisi turunan (BR-041) —
satu soal tagihan lewat tempo, satu soal barang belum balik.

**`gateway_pending` tidak terjangkau di fase 1** karena jalur gateway nonaktif (BR-061,
`04-api-spec.md` §3.8.1). Nilainya tetap ada di enum supaya menyalakannya kembali tidak butuh
migrasi — tapi jangan menulis test yang menunggu status itu muncul.

### BR-057 Tenggat pembayaran **[baru]**
Setiap invoice sewa punya `due_at`, diisi **saat invoice terbit** — bukan diketik
operator, bukan dibiarkan kosong:

```
due_at = min( created_at + owners.payment_due_hours , bookings.start_at )
```

`payment_due_hours` default **24**, bisa diatur per pemilik — jangan di-hardcode.

**Tenggat ini baru mulai berdetak saat booking jadi `reserved`**, karena di situlah
invoice terbit. Draft belum punya invoice, jadi belum punya `due_at` — ia dibatasi
`draft_expiry_hours` (BR-027) yang terpisah. Dua jam, tidak pernah bersamaan:
`draft → (BR-027) → hangus`, atau `draft → konfirmasi operator → reserved →
(BR-057) → due_at`. Contoh lengkapnya di PRD §7.5.
Rumus `min(…)` menutup dua kasus sekaligus tanpa ada yang perlu memilih:

| Booking dibuat | Ambil | `due_at` | Yang menentukan |
|---|---|---|---|
| Sen 10:00 | Sel 09:00 | Sel 09:00 | `start_at` lebih dulu |
| Sen 10:00 | dua minggu lagi | Sel 10:00 | 24 jam lebih dulu |

**Apa yang terjadi sesudah `due_at` bergantung BR-038**, dan itu yang membuat
sakelarnya tetap berarti:

| `require_payment_before_pickup` | Lewat `due_at`, belum lunas |
|---|---|
| **`true`** | Invoice → `overdue`, **booking → `cancelled`** dengan alasan `payment_expired`, unit langsung bebas |
| **`false`** (default) | Invoice → `overdue` dan tampil di dashboard. Booking **tidak** dibatalkan — pemilik ini memang menerima pembayaran saat pengambilan |

Pembatalan otomatis aman di jalur pertama justru karena **belum ada uang yang masuk**:
pemilik yang mewajibkan bayar di muka tidak pernah menyerahkan barang sebelum lunas,
jadi pertanyaan refund — yang PRD §8 masih menunda ke fase 2 — tidak pernah muncul.

**Booking yang tidak dibatalkan tetap punya batas**, lewat jalur lain: `reserved →
no_show` saat `now() > start_at + owners.no_show_tolerance_hours` (**default 3**). Tanpa
angka itu, pemilik yang membiarkan bayar-saat-ambil punya booking yang mengunci unit
tanpa batas waktu — persis lubang yang aturan ini ada untuk menutup.

**Kenapa 3 jam, bukan 0 dan bukan 24.** Ia satu-satunya rentang yang memenuhi dua hal
sekaligus:

| Nilai | Unit bebas | Masalahnya |
|---|---|---|
| `0` | tepat di `start_at` | **Setiap pengambilan normal berlomba dengan job ini** — penyewa datang *pada* `start_at`, dan serah-terima butuh menit |
| **`3`** | hari itu juga (09:00 → 12:00) | Penyewa yang telat lebih dari 3 jam kehilangan booking — dan itu memang niatnya |
| `24` | keesokan harinya | Untuk `pricing_unit = day`, satu periode sewa penuh hilang di luar hari yang sudah hangus |

Tiga jam memberi kelonggaran macet dan terlambat bangun, tapi tetap mengembalikan unit
ke pasar pada hari yang sama.

> **Dua kewajiban yang tetap berlaku berapa pun angkanya**, karena pemilik boleh
> menurunkannya sampai `0`:
>
> 1. **Job tidak pernah menyentuh booking yang serah-terimanya sudah dimulai.** Begitu
>    baris `handovers` terbit, booking itu di luar jangkauannya — bukan cuma saat
>    statusnya sudah `picked_up`.
> 2. **`POST …/pickup` atas booking `no_show` tidak boleh langsung ditolak.** Operator
>    yang memulai tepat waktu harus bisa menyelesaikannya; kalau tidak, pemilik akan
>    menaikkan toleransinya cuma untuk menghindari kekalahan balapan, dan angka itu
>    berhenti berarti.

**Pengingat wajib mendahului pembatalan.** Membatalkan booking tanpa peringatan adalah
cara tercepat kehilangan pelanggan, jadi `payment_due_reminder` dikirim sebelum `due_at`
(BR-070). Aturan ini tidak sah tanpa pengingatnya.

> **`overdue` di sini bukan `overdue` BR-041.** Yang ini status kolom pada `invoices` —
> tagihan lewat tempo. Yang itu kondisi turunan pada booking — barang belum balik.
> Keduanya bisa terjadi bersamaan pada booking yang sama dan artinya tetap berbeda.

### BR-060 Bayar penuh **[warisan]**
Satu invoice dibayar penuh. Pembayaran sebagian tidak didukung. Satu invoice
hanya boleh punya satu pembayaran berhasil.

### BR-061 Dua jalur pembayaran **[warisan]**
Gateway pembayaran dan transfer manual berbukti, keduanya tersedia. Pemilik boleh
menonaktifkan salah satunya.

**Fase 1 mematikan jalur gateway di tingkat sistem.** Pembayaran dilakukan manual:
transfer berbukti, dibaca AI sebagai rekomendasi, dilunaskan operator (BR-062).
Ini memakai mekanisme yang sudah ada di aturan ini — sakelar per-pemilik tidak
berubah, cuma dipasang satu tingkat di atasnya. Kontrak endpoint-nya ditinggal
utuh, bukan dihapus, supaya menyalakannya kembali tidak butuh migrasi maupun
perubahan katalog error. Uraiannya di `04-api-spec.md` §3.8.1.

**Pemicu menyalakannya kembali: akun merchant aktif.** Bukan jumlah tenant, bukan
jadwal fase — begitu aggregator menyetujui akun, tiga endpoint yang ditandai
nonaktif didaftarkan. Pemicu ini di luar kendali tim, jadi pengajuan akunnya
sendiri tercatat sebagai pertanyaan terbuka di PRD §12 #2.

Konsekuensinya: **BR-063 dan BR-064 menganggur di fase 1, bukan batal.** Keduanya
kontrak yang berlaku begitu gateway kembali, dan ditulis sekarang justru supaya
tidak dirancang ulang nanti dengan tergesa.

### BR-062 Bukti transfer dibaca otomatis **[warisan]**
Bukti transfer yang diunggah diproses secara asinkron untuk mengekstrak nominal
dan tanggal, lalu ditandai cocok/tidak terhadap invoice.

Hasil AI adalah **rekomendasi, bukan keputusan.** Pelunasan tetap butuh
persetujuan manusia. Lihat `boarding-house-api/migrations/000013_create_payment_proofs.up.sql`.

### BR-063 Webhook idempoten **[warisan]**
Tanda tangan webhook wajib diverifikasi. Payload mentah disimpan. Webhook yang
sama diproses berulang tidak boleh menghasilkan pembayaran ganda. Pembuatan
pembayaran dan pembaruan invoice terjadi dalam satu transaksi database.

### BR-064 Redirect bukan bukti **[warisan]**
Pengalihan balik dari halaman gateway **tidak pernah** menjadi dasar pelunasan.
Hanya webhook terverifikasi berstatus sukses yang bisa menandai invoice lunas.

---

## 7. Notifikasi

### BR-070 Pengingat terjadwal **[baru]**
Lima jenis pesan WhatsApp otomatis:

| `notifications.kind` | Kapan | Bisa dimatikan pemilik? |
|---|---|---|
| `invoice_link` | Saat invoice terbit — membawa instruksi transfer dan tautan portal | **Tidak.** Tanpanya penyewa tidak tahu harus bayar ke mana |
| `payment_due_reminder` | Sebelum `due_at` (BR-057) | **Tidak.** Pembatalan otomatis tanpa peringatan tidak sah |
| `pickup_reminder` | H-1 sebelum `start_at` | ya |
| `return_reminder` | H-1 sebelum `end_at` | ya |
| `overdue` | Saat kondisi terlambat terpenuhi (BR-041) | ya |

Tiga yang terakhir adalah **pengingat** — pemilik boleh mematikannya satu per satu.
Dua yang pertama **bukan pengingat, melainkan bagian dari transaksinya**: satu membawa
tagihan, satu mendahului pembatalan. Mematikannya berarti menagih atau membatalkan
diam-diam.

### BR-071 Pengingat telat berhenti sendiri **[baru]**
Pengingat terlambat dikirim maksimal sekali per hari, maksimal 3 kali, lalu
berhenti dan dieskalasi menjadi tugas untuk operator. Sistem yang mengirim
pesan tanpa henti akan diblokir oleh penerima, bukan dibayar.

### BR-072 Kegagalan kirim harus terlihat **[baru]**
Pengiriman yang gagal dicatat beserta alasannya dan tampil di dashboard.
Notifikasi tidak boleh gagal diam-diam.

### BR-073 WhatsApp lewat API resmi **[baru]**
Integrasi WhatsApp memakai **WhatsApp Cloud API resmi Meta**. Pemasangan nomor
pribadi pemilik lewat *Perangkat Tertaut* **dilarang** — pola itu menitipkan
risiko pemblokiran akun ke pelanggan (lihat catatan RoomKost di
`boarding-house-app-recon/market.yaml`). Pola integrasi tersedia di
`agent-posyandu/wa_cloud.py`.

**Satu integrasi untuk semua pemilik, bukan satu per pemilik.** Konsekuensinya
webhook-nya tinggal di `api.sewain.id` — host mesin, tanpa `Host` pemilik dan tanpa
token. Tenant-nya **tidak bisa** diturunkan seperti di permukaan lain (BR-030, BR-032);
ia ditemukan dari isi payload. Empat kewajiban yang lahir dari itu:

1. **Simpan `provider_message_id`.** Meta membalas `wamid` saat pesan terkirim, dan
   webhook status merujuk id itu. `notifications.provider_message_id` unik — tanpanya
   status yang masuk tidak punya cara menemukan baris mana yang diperbarui, dan BR-072
   tidak bisa ditepati.
2. **Verifikasi `X-Hub-Signature-256`, gagal → `401` sebelum menyentuh apa pun.**
   Ini endpoint `POST` tanpa autentikasi di host publik; tanpa verifikasi, siapa pun
   bisa mengirim status palsu dan menandai pengingat sebagai terkirim padahal tidak.
3. **Sediakan jalur verifikasi langganan.** Meta mewajibkan `GET` ber-`hub.challenge`
   saat webhook didaftarkan. Tanpa itu webhook-nya **tidak bisa didaftarkan sama
   sekali** — bukan sekadar kurang rapi.
4. **Pesan masuk diabaikan, dan itu keputusan.** Penyewa yang membalas pengingat
   dikirim Meta ke URL yang sama. Fase 1 membalasnya `200` lalu membuangnya: tidak ada
   kotak masuk, tidak ada balasan otomatis, dan penyewa yang butuh sesuatu menghubungi
   pemiliknya langsung. Yang dilarang adalah membuangnya **diam-diam tanpa tercatat**
   di dokumen ini, bukan membuangnya.

---

## 8. Laporan

### BR-075 Ruang lingkup laporan **[baru]**
Laporan minimum: pemasukan per periode (dipecah per jenis baris), tingkat
pemakaian per unit, daftar unit menganggur > 30 hari, daftar booking terlambat.

### BR-076 Pemasukan tidak termasuk deposit **[baru]**
Angka pemasukan hanya menjumlahkan baris `rent`, `late_fee`, `damage`, dan
`discount`. Deposit dilaporkan terpisah sebagai saldo titipan. Setara BR-050.

### BR-077 Ekspor laporan **[baru]**
Setiap laporan di BR-075 bisa diekspor sebagai CSV dan XLSX.

**Pemisahan deposit dari pemasukan ikut ke berkas ekspor** sebagai kolom berbeda
(BR-050, BR-076). Pemisahan itu tidak boleh hilang hanya karena formatnya berubah
— justru di Excel-lah angka itu dijumlahkan orang lain.

Berkas dirakit di luar request (BR-091); tautan unduhnya **kedaluwarsa 15 menit**
dan bisa dibuat ulang. Laporan memuat data penyewa, dan tautan tanpa kedaluwarsa
akan hidup selamanya di riwayat WhatsApp — tersebar ke orang yang tidak pernah
dimaksudkan melihatnya, lama setelah laporannya tidak relevan.

Alasannya sederhana: juragan yang ingin tahu "untung berapa" akan memindahkan
angkanya ke Excel apa pun yang kita sediakan. Laporan yang cuma bisa dilihat di
layar akan disalin ulang dengan tangan, dan angka yang disalin tangan salah.

---

## 9. Langganan SaaS

> **Seluruh bagian ini ditunda dari fase 1.** Tidak ada paket, tidak ada kuota, dan
> tidak ada tagihan langganan yang dibangun sekarang — **setiap pemilik tanpa batas
> unit maupun pengguna.** Ketiga aturan di bawah tetap ditulis sebagai kontrak,
> mengikuti pola jalur gateway di `04-api-spec.md` §3.8.1: kontraknya ditinggal utuh,
> jalurnya dimatikan, jadi menyalakannya kembali tidak butuh migrasi maupun perubahan
> katalog error.
>
> **Pemicu menyalakannya: jalur pembayaran menyala.** Harga paket **sudah diputuskan**
> (PRD §13: gratis / Rp 99.000 / Rp 249.000), jadi yang tersisa bukan keputusan harga.
> BR-082 menagih langganan lewat `invoices` + gateway yang sama dengan yang dipakai
> pemilik menagih penyewanya — dan jalur itu mati di fase 1 (BR-061). Rantainya:
>
> ```
> langganan menyala  ←  jalur pembayaran menyala  ←  akun merchant aktif
>    (BR-080–082)            (BR-061)            (PRD §12 #2, belum dimulai)
> ```
>
> Selama rantai itu putus, tidak ada yang bisa ditagih — jadi tidak ada gunanya
> menegakkan kuota.
>
> Yang **tetap dibangun**: tabel `subscriptions` ada di skema dan tetap kosong, dan
> `invoices.kind`/`subscription_id` beserta constraint `invoices_one_subject` tetap
> jalan. Ia bukan tabel mati; ia tabel yang belum kebagian baris.

### BR-080 Paket & kuota **[ditunda]**
Tiga paket, dengan harga dan kuota yang **sudah diputuskan** — alasan angkanya di
PRD §13:

| `plan` | Nama jual | Harga | `unit_quota` | `user_quota` |
|---|---|---|---|---|
| `trial` | Coba | gratis | 5 | 1 |
| `usaha` | Usaha | Rp 99.000/bln | 50 | 3 |
| `bisnis` | Bisnis | Rp 249.000/bln | tanpa batas | tanpa batas |

**Harga flat, bukan per unit.** Juragan yang menambah unit ke-12 tidak membayar lebih;
itu pembeda langsung dari kompetitor yang menagih per kamar. Tier gratis dibatasi
**jumlah unit, bukan waktu** — rental kecil boleh jalan di situ selamanya.

**Batas 50 unit menutup seluruh persona** (PRD §3.1: 5–50 unit). Itu disengaja: juragan
naik ke `bisnis` karena **bentuk usahanya berubah** — buka cabang kedua, punya situs
sendiri, tim lebih dari tiga — bukan karena beli satu motor lagi. Tebing harga yang jatuh
di tengah target adalah dosa yang sama dengan menagih per unit, cuma bentuknya tangga.

**Pembedanya bukan cuma kuota.** Tiga gerbang fitur:

| Gerbang | Mulai dari | Kenapa di situ |
|---|---|---|
| `owners.slug` + halaman publik + portal penyewa | `usaha` | Pemicu naik paket yang paling terbaca — lihat BR-025 |
| Pengingat WhatsApp (BR-070–073) | `usaha` | Cloud API menagih per percakapan; ia punya biaya marginal nyata per tenant |
| API eksternal (BR-031) | `bisnis` | Untuk pemilik yang punya situsnya sendiri |

Ketiganya **belum punya kolomnya** di `subscriptions`; ditambahkan saat bagian ini
dinyalakan, bukan sekarang.

`user_quota` dihitung dari baris `users` **berstatus `active` dengan `owner_id`
pemilik itu** (BR-004). Akun `invited` yang belum menerima undangan belum memakai
kuota; akun `disabled` melepaskannya kembali.

### BR-081 Kuota habis **[ditunda]**
Ketika kuota unit terlampaui, pemilik **tidak bisa menambah unit baru** tetapi
tetap bisa mengoperasikan seluruh unit yang sudah ada.

Data pemilik tidak pernah dikunci atau disembunyikan karena langganan berakhir —
menyandera data pelanggan adalah cara tercepat kehilangan mereka selamanya.
Yang dibatasi adalah pertumbuhan, bukan operasional.

Konsekuensi penundaan: `unit-quota-exceeded` tetap ada di katalog error tapi
**tidak pernah terbit di fase 1** — setara `gateway_pending` di BR-056. Jangan
menulis test yang menunggu error itu muncul.

### BR-082 Langganan lewat jalur pembayaran yang sama **[ditunda]**
Tagihan langganan memakai `invoices` + gateway yang sama dengan yang dipakai
pemilik menagih penyewanya. Tanpa integrasi pembayaran kedua.

---

## 10. Data pribadi

### BR-085 Identitas penyewa **[baru]**
Foto KTP/SIM disimpan terenkripsi. Akses tercatat dalam audit log. Hanya pemilik
dan operator dari `owner_id` yang bersangkutan yang bisa membukanya. Tautan bacanya
berumur **5 menit** — dibuka sekali, lalu mati.

**"Terenkripsi" di sini berarti enkripsi at-rest object storage, bukan enkripsi tingkat
aplikasi** — dan itu memang yang bisa berlaku: jalur bacanya adalah URL bertanda tangan
yang dirender langsung oleh browser, jadi objek yang dienkripsi aplikasi akan kembali
sebagai ciphertext yang tidak bisa ditampilkan. Yang menjaganya bertiga: enkripsi
at-rest, tautan 5 menit, dan baris audit per pembukaan.

Bedakan dari `customers.id_number_enc` — itu **nomor**-nya, `bytea`, dan ia memang
terenkripsi di tingkat aplikasi karena tidak pernah perlu dirender browser.

**Lokasi penyimpanannya: Cloudflare R2, sampai September 2027.** R2 tidak punya
region Indonesia, dan apakah data identitas boleh keluar dari Indonesia adalah
pertanyaan UU PDP — pertanyaan hukum, bukan teknis. Keputusan itu **ditinjau ulang
bersama pembentukan PT**, dan sampai saat itu R2 dipakai apa adanya. Tercatat di
PRD §12 #3 sebagai pertanyaan terbuka dengan tanggalnya.

Yang membuat keputusan ini murah dibalik nanti: kalau jawabannya "harus di dalam
negeri", yang berubah cuma **satu bucket** — adapter-nya sama-sama S3-compatible,
dan foto serah-terima maupun berkas ekspor tidak terkena aturan itu.

### BR-086 Retensi **[ditunda]**
Foto identitas terhapus otomatis 90 hari setelah booking terakhir penyewa
tersebut `completed` atau `cancelled`. Data ini kewajiban hukum, bukan aset —
menyimpannya lebih lama menambah risiko tanpa menambah nilai.

> **Dinonaktifkan di fase 1.** Tidak ada job yang menghapus foto identitas, jadi
> foto itu **menumpuk tanpa batas waktu**. Kolom `customers.id_purge_after` tetap ada
> di skema dan tetap tidak dibaca siapa pun — menyalakannya kembali berarti menulis
> satu job, nol migrasi.
>
> **Pemicu menyalakannya: keputusan UU PDP setelah PT berdiri** — sama dengan
> peninjauan lokasi penyimpanan di BR-085, dan tercatat di baris yang sama di
> PRD §12 #3.

---

## 11. Platform

Tiga aturan yang tidak dimiliki satu fitur pun, tapi menopang belasan.

### BR-090 Tulis aman diulang **[baru]**
Setiap `POST` yang menghasilkan uang atau booking menerima header `Idempotency-Key`.
Daftar endpointnya di `04-api-spec.md` §2.1.

| Keadaan kunci | Yang dilakukan server |
|---|---|
| Belum pernah dipakai | Jalankan; simpan respons bersama kunci, **TTL 24 jam** |
| Sudah ada hasilnya | Putar ulang respons pertama — status dan body **identik**, database tidak disentuh |
| Ada, masih berjalan | `409 request-in-flight`; klien menunggu, tidak mengirim ulang |

**Satu kunci mewakili satu niat pengguna, bukan satu percobaan jaringan.** Klien yang
membuat kunci baru tiap retry sudah membatalkan seluruh gunanya.

> Yang diperbaiki aturan ini bukan integritas data — itu sudah dijaga constraint
> (BR-022, BR-035, BR-060) — tapi responsnya: timeout setelah `COMMIT` tidak boleh
> kembali sebagai error bentrok yang menyebut booking milik operator itu sendiri.
> Tanpa ini frontend tidak punya cara aman me-retry `POST` di jaringan seluler.

### BR-091 Pekerjaan latar **[baru]**
Pekerjaan berjadwal dan pekerjaan yang terlalu lama untuk satu request jalan di luar
proses API, lewat **dua penjalan terpisah**:

| Penjalan | Isinya | Kenapa terpisah |
|---|---|---|
| Konsumer | Bukti transfer dibaca AI (BR-062), ekspor laporan (BR-077) | Rakus memori, bursty, bergantung layanan luar |
| Penjadwal | Draft kedaluwarsa (BR-027), pengingat (BR-070) | Nyaris nol sumber daya |

Batas sumber daya per layanan tidak bisa dipasang ke satu biner yang memuat dua
profil seekstrem itu, dan satu ekspor yang kehabisan memori tidak boleh ikut
menjatuhkan pengingat.

Empat kewajiban:

1. **Setiap handler wajib idempoten.** Pengirimannya at-least-once — satu pekerjaan
   bisa jalan dua kali kalau penjalannya mati di tengah. Ini sifat desain, bukan
   lewat header; beda mekanisme dari BR-090.
2. **Gagal → retry dengan backoff → dead-letter yang terlihat di dashboard** (BR-072).
   Tidak hilang diam-diam, tidak retry selamanya.
3. **Penjadwal memakai kunci lease** — tidak pernah jalan dobel walau ada beberapa
   replika, termasuk saat rolling deploy.
4. **Ada endpoint untuk menanyakan status** pekerjaan yang hasilnya ditunggu pengguna.

> Timer di dalam proses API dilarang: ia jalan sekali **per replika** — dua replika
> berarti dua pengingat WhatsApp ke penyewa yang sama, persis yang BR-071 cegah — ia
> mati saat deploy, dan kegagalannya cuma sampai ke log padahal BR-072 mewajibkannya
> terlihat.

### BR-092 Jejak yang bisa ditelusuri **[baru]**
`trace_id` pada setiap respons error **diambil dari konteks tracing**, bukan dibuat
di tempat sebagai UUID acak, dan harus benar-benar bisa dibuka di backend tracing.

Span-nya memuat `owner_id`, route, dan durasi query.

> Frontend menyuruh pengguna menyalin `trace_id` ke tiket support. `trace_id` yang
> tidak menunjuk ke apa pun mengubah janji itu jadi bohong, sekaligus membuat tim
> mengira punya observability yang sebenarnya tidak ada.

### BR-093 Unggahan langsung ke object storage **[baru]**
Byte unggahan **tidak pernah melewati API.** Browser `PUT` langsung ke R2 memakai URL
bertanda tangan; yang lewat API cuma permintaan tanda tangannya dan penyerahan kuncinya.

```
1. POST /uploads/presign        → { object_key: "pending/<owner_id>/<uuid>", upload_url }
2. PUT  <upload_url>            → byte langsung ke R2
3. POST endpoint domainnya      → { photo_keys: [...] }
     HEAD tiap kunci → salin pending/ → prefix final → tulis baris, satu transaksi
```

Lima kewajiban:

1. **Server yang menentukan kunci, selalu.** Klien mengirim jenis dan ukuran, lalu
   menerima kuncinya. Kunci berprefiks `owner_id`, jadi satu kunci yang bocor tidak
   membuka jalan menebak objek pemilik lain.
2. **`Content-Type` dan `Content-Length` diikat pada tanda tangan**, sehingga
   ditegakkan R2 sendiri — bukan cuma divalidasi aplikasi yang bisa dilewati.
3. **Baris baru ditulis setelah `HEAD` berhasil.** Kunci yang objeknya tidak ada, bukan
   milik pemilik itu, atau tipenya tidak cocok → `422`. Ini yang menjaga BR-036 tetap
   punya arti.
4. **Unggahan mendarat di `pending/`, bukan langsung di prefix bukti.** Ia dipindahkan
   saat commit; yang tidak pernah di-commit hilang sendiri lewat lifecycle 24 jam. Prefix
   bukti **hanya** berisi bukti sungguhan — foto yang belum dikonfirmasi tidak pernah
   bisa disangka barang bukti.
5. **Yang disimpan kunci, bukan URL.** URL memuat endpoint, region, dan tanda tangan;
   semuanya berubah, dan BR-085 menjanjikan pemindahan bucket yang cuma menyentuh satu
   tempat. Kunci tidak berubah. URL dibuat saat dibaca.

**Kenapa ini aman padahal presign membuka jendela.** Objek yang ada tanpa barisnya
**bukan** barang bukti: tidak ada yang menunjuknya, dan tidak ada yang bisa membacanya
tanpa URL bertanda tangan. Ia sampah, dan lifecycle yang mengurusnya.

Yang berbahaya justru arah sebaliknya — **baris yang menunjuk objek pilihan klien atau
objek yang tidak pernah ada.** Di situ "minimal 1 foto" berubah jadi klaim kosong dan
sengketa deposit (§2.2 PRD) kehilangan dasarnya. Kewajiban 1 dan 3 menutupnya, dan
BR-037 tidak bergeser sedikit pun: sesudah barisnya ditulis, objek dan barisnya tetap
tidak bisa diubah maupun dihapus siapa pun.

Tiga jalur memakai mekanisme yang sama: foto serah-terima (BR-036), foto identitas
(BR-085), dan bukti transfer (BR-062).

---

## Lampiran — matriks ketertelusuran

Tiap acceptance criteria di PRD nempel ke satu BR, dan tiap BR punya minimal
satu AC atau satu test.

| BR | Story PRD | Bentuk verifikasi |
|---|---|---|
| BR-001, BR-002 | §9 non-fungsional | Test akses lintas-owner (sudah ada di kos) |
| BR-003 | §3.2 persona | Test matriks izin per peran |
| BR-004 | §9 non-fungsional | Test: email yang sama ditolak di usaha kedua (unik global); `owner_id` dan `role` di token berasal dari baris `users`, bukan dari request |
| BR-006 | A0 | Test verifikasi: **setiap** endpoint backoffice → `403 email-not-verified` sebelum terverifikasi, dan empat jalur yang diizinkan tetap jalan; sesudah verifikasi semuanya terbuka; tautan sekali pakai & mati 24 jam; kirim ulang selalu tersedia; **operator undangan terverifikasi otomatis saat menerima undangan** |
| BR-005 | A0 | Test pendaftaran: `owners` + `users` terbit bersama dalam satu transaksi — gagal di tengah tidak meninggalkan usaha yatim; email terpakai → `422`; slug terlarang & format DNS ditolak database; batas laju per IP |
| BR-010, BR-011 | A1 | Test integrasi katalog |
| BR-012, BR-014 | A1 | Test snapshot: ubah harga resource, booking lama tidak berubah |
| BR-012 | A1 | Test satuan: `INSERT` tanpa `pricing_unit` menghasilkan `day` **bukan `NULL`**; nilai asing (`'bulan'`) **ditolak database** |
| BR-017 | A0, A1 | Test preset: `business_type` asing ditolak database; `pricing_unit` resource baru terisi dari preset pemiliknya, **bukan dari request body**; ganti preset tidak menyentuh resource maupun booking lama; form fase 1 tidak merender pemilih satuan |
| BR-013 | A1 | Test: unit `maintenance` hilang dari pencarian, booking tetap ada |
| BR-094 | A1 | Test spek kendaraan: mobil tanpa kursi & motor **dengan** kursi sama-sama ditolak database; `clutch` di mobil dan `diesel` di motor ditolak; `vehicle_type` tidak ada di skema `PATCH`; `category` terisi dari `vehicle_type` **bukan dari request body**; spek yang menunjuk resource pemilik lain ditolak FK komposit |
| BR-095 | A1 | Test S&K: tiga teks opsional tersimpan dan boleh kosong; **nol textarea untuk hal yang dihitung sistem** — tenggat bayar, denda telat, dan toleransi no-show dirender dari kolomnya, tidak bisa diketik |
| BR-096 | A0, B6 | Test profil: `whatsapp` berformat salah ditolak database; ketiganya boleh kosong pada usaha baru; halaman publik tidak hidup sebelum `slug` + `whatsapp` + `address` terisi |
| BR-015 | A2 | Test buffer: booking selesai 10:00 + buffer 120 → tersedia 12:00 |
| BR-016 | A1, C2 | Test field opsional: `NULL` diterima & `0` **ditolak database** untuk keempat nominal; resource tanpa deposit tidak menerbitkan baris `deposit` dan tidak memblokir `completed`; resource tanpa `late_fee_per_unit` **tetap** memunculkan peringatan terlambat |
| BR-020, BR-021 | B1 | Test pencarian ketersediaan; test durasi: di luar `min`/`max` ditolak, dan **kosong berarti tanpa batas** |
| BR-022 | B2 | **Test konkuren** — dua insert bersamaan, tepat satu berhasil |
| BR-023 | B2, B3 | Test: draft tidak memblokir booking `reserved` |
| BR-024 | B2 | Test kode: format `<prefix>-<nomor>`, unik per pemilik, nomor tidak pernah dipakai ulang; **ganti prefix tidak mengubah kode lama**; prefix huruf kecil & > 6 karakter **ditolak database** |
| BR-025 | B3 | Test halaman publik: host asing → 404, unit `maintenance` hilang; slug terlarang & format DNS ditolak database |
| BR-026, BR-030 | B3 | Test API publik: scope dari `Host`, rate limit, draft `public_page`; **test `Host` palsu tanpa proxy** |
| BR-031 | B6 | Test kunci API: scope terbatas ke empat endpoint publik, kunci dicabut → `401`, CORS allowlist, kuota per kunci |
| BR-032 | B6 | **Test silang jalur:** `X-API-Key` yang sah dikirim ke `<slug>.sewain.id` tidak mengubah tenant; `Host` pemilik dikirim ke `api.sewain.id` tidak mengubah tenant |
| BR-033 | B1 | Test keadaan kalender: delapan nilai, `draft` tidak muncul, `returned` tampil `available`, unit `retired` tidak dirender; respons publik hanya `available`/tidak |
| BR-027 | B3 | Test kedaluwarsa 24 jam |
| BR-028 | B4 | Test blacklist: booking ditolak, aksi blokir hanya untuk owner, pesan publik netral |
| BR-029 | B5 | Test tukar unit: lolos cek bentrok saat `reserved`, ditolak setelah `picked_up` |
| BR-035, BR-036 | C1 | Test: pengambilan tanpa foto ditolak |
| BR-037 | C1 | Test: percobaan ubah/hapus handover ditolak |
| BR-038 | C1 | Test: pengambilan diblokir saat belum lunas & flag aktif |
| BR-040, BR-046 | C2 | Test hitung denda |
| BR-041, BR-042 | C3 | Test kondisi terlambat & peringatan bentrok fisik |
| BR-045, BR-047, BR-048 | C2 | Test penyelesaian deposit, termasuk kasus sisa negatif; test booking tanpa deposit: potongan & pengembalian **ditolak database** |
| BR-049 | D3 | Test: `completed` diblokir sebelum deposit selesai — dan **tidak** diblokir kalau booking-nya tanpa deposit |
| BR-051 | C2 | Test pembebasan: baris tak dicentang tidak terbit; pembebasan tanpa alasan → `422`; **operator boleh membebaskan deposit** selama invoice belum lunas, dan jejaknya terisi bertiga; pembebasan setelah invoice lunas ditolak; dua `POST` berkunci sama → satu hasil |
| BR-050, BR-076 | F1 | Test: deposit tidak masuk angka pemasukan |
| BR-055, BR-056 | D1 | Test invoice berbaris; `overdue` terbit saat lewat `due_at`, dan **tidak** tertukar dengan `overdue` booking (BR-041) |
| BR-057 | D2, §7.5 | Test tenggat: `due_at` = `min(created_at + payment_due_hours, start_at)`; **sakelar menyala** → booking belum lunas jadi `cancelled (payment_expired)` dan unit bebas; **sakelar mati** → booking tetap, batasnya `no_show` lewat `start_at + no_show_tolerance_hours`; `payment_due_reminder` terkirim **sebelum** pembatalan |
| BR-060, BR-061, BR-062 | D2 | Test pembayaran manual: satu pembayaran sukses per invoice, bukti dibaca AI sebagai rekomendasi |
| BR-063, BR-064 | D2-fase2 | *(menganggur di fase 1)* Test webhook idempoten & redirect-bukan-bukti — berlaku begitu gateway dinyalakan (BR-061) |
| BR-070–BR-072 | E1 | Test penjadwalan & pencatatan kegagalan |
| BR-073 | E1 | Test webhook: `GET` membalas `hub.challenge`, token salah → `403`; tanda tangan salah → `401` tanpa efek; `wamid` ganda **ditolak database**; `wamid` tak dikenal → `200` tanpa efek; pesan masuk dibuang tapi tetap `2xx` |
| BR-075 | F1 | Test laporan |
| BR-077 | F1 | Test ekspor: deposit tetap kolom terpisah; tautan kedaluwarsa 15 menit |
| BR-080–BR-082 | §12 | *(ditunda)* Test penegakan kuota — berlaku begitu jalur pembayaran menyala (BR-061). Di fase 1 justru sebaliknya: **test bahwa tidak ada batas** unit maupun pengguna |
| BR-085 | §9 non-fungsional | Test enkripsi identitas & baris audit per pembukaan; tautan mati setelah 5 menit |
| BR-086 | — | *(ditunda)* Test job retensi — berlaku begitu keputusan UU PDP turun. Fase 1 tidak punya job penghapus |
| BR-090 | §9 non-fungsional | Test: dua `POST` berkunci sama → satu baris, respons identik; kunci masih jalan → `409` |
| BR-091 | E1, §9 non-fungsional | Test: pekerjaan gagal masuk dead-letter; penjadwal 2 replika tidak mengirim dobel |
| BR-092 | §9 non-fungsional | Test: `trace_id` pada error benar-benar menunjuk ke span |
| BR-093 | C1, D2 | Test unggah: kunci karangan → `422`; kunci milik pemilik lain → `422`; objek yang tidak pernah di-PUT → `422`; presign kedaluwarsa ditolak R2; **byte tidak pernah melewati API**; objek `pending/` yang tidak di-commit hilang lewat lifecycle |

