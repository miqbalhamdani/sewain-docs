# Product Requirements Document — Sewain

> **Status:** Draft 2 · **Tanggal:** 2026-09-09 · **Nama produk:** *Sewain* (nama kerja, gampang diganti)
> **Dokumen pendamping:** [`02-business-rules.md`](./02-business-rules.md) — aturan bisnis bernomor (BR-xxx) yang jadi rujukan waktu ngoding ·
> [`03-erd.md`](./03-erd.md) — skema &amp; constraint · [`04-api-spec.md`](./04-api-spec.md) — kontrak endpoint ·
> [`05-backlog.md`](./05-backlog.md) — 80 item efektif, satu backlog untuk dua repo.

---

## 1. Ringkasan

**Sewain adalah aplikasi SaaS B2B untuk pemilik usaha persewaan di Indonesia** —
rental mobil, motor, kamera, tenda &amp; alat camping, sound system, alat berat,
kostum, perlengkapan pesta. Pemilik dapat akun sendiri buat ngatur unit, jadwal,
serah-terima barang, deposit, dan tagihan; penyewa cukup buka link, tanpa install
apa-apa.

### Tesis produk: satu mesin, empat pasar

Empat jenis usaha yang kelihatannya beda ternyata satu model data yang sama —
**resource × rentang waktu × cek bentrok × harga × tagihan**:


| Vertikal                       | `business_type`                      | Resource    | Satuan waktu | Tambahan khusus                    |
| ------------------------------ | ------------------------------------ | ----------- | ------------ | ---------------------------------- |
| **Rental &amp; sewa** ← fase 1 | `vehicle_rental`, `equipment_rental` | unit barang | hari         | serah-terima, deposit, denda telat |
| Kos &amp; properti             | `boarding_house`, `apartment`        | kamar       | bulan        | tagihan berulang, kontrak          |
| Lapangan &amp; jadwal          | `venue`                              | lapangan    | jam          | slot berulang mingguan             |
| Klinik &amp; perawatan         | `clinic`                             | praktisi    | 30 menit**   | catatan kunjungan                  |


 `30 menit` belum ada di enum BR-012; satuan `clinic` diputuskan di fase 4, bukan
ditebak sekarang. Apartemen bisa `hari`/`minggu`/`bulan` — daftar lengkapnya di BR-017.

Preset itu **nyata, bukan kiasan**: pemilik memilih `business_type` sekali saat
mendaftar (BR-005), dan pilihan itu yang menentukan satuan harga seluruh barangnya
(BR-017). Juragan rental tidak pernah ditanya "per jam atau per hari?" — pertanyaan itu
cuma ada demi vertikal yang belum dibuka.

Bedanya adalah **konfigurasi, bukan kode**. Sekali engine-nya jadi, tiga pasar
berikutnya dibuka dengan menambah preset — bukan menulis aplikasi baru.

### Kenapa rental yang duluan

Bukan karena pasarnya paling besar, tapi karena **jaraknya paling pendek dari kode
yang sudah ada ke pasar yang belum digarap**:

1. Codebase `boarding-house-api` di repo ini sudah punya sewa berdurasi
`room_assignments` dengan `start_date`/`end_date`), multi-tenancy, payment
ateway, dan upload bukti bayar. Rental = ganti satuan bulan → hari,
ambah cek bentrok.
2. Rental adalah vertikal yang **memaksa engine-nya jadi generik**. Kalau mulai
ari kos, gampang terjebak bikin aplikasi kos. Kalau mulai dari rental,
os dan lapangan tinggal dinyalakan.
3. Pasar rental di Indonesia hampir kosong dari software khusus — mayoritas masih
xcel dan grup WhatsApp. Kompetitor yang ada semuanya main di kos.

---

## 2. Masalah

Pemilik rental hari ini menjalankan usahanya dengan buku tulis, spreadsheet, dan
grup WhatsApp. Empat rasa sakit berikut yang bikin orang mau bayar:

### 2.1 Double-booking

Unit dijanjikan ke dua penyewa untuk tanggal yang beririsan. Ketahuannya pas hari-H,
salah satu harus dibatalkan. Ini bukan cuma kehilangan satu transaksi — reputasi
di pasar yang jalan dari mulut ke mulut rusak jauh lebih mahal dari nilai sewanya.

> Kalau produk ini cuma menyelesaikan satu masalah, ini masalahnya. Semua keputusan
> teknis di dokumen ini tunduk pada satu syarat: **double-booking harus mustahil
> secara struktural, bukan sekadar dicegah lewat validasi aplikasi.**

### 2.2 Sengketa deposit

Barang balik lecet/penyok/kurang. Pemilik bilang rusak pas dipakai, penyewa bilang
sudah begitu dari awal. Nggak ada bukti kondisi sebelum-sesudah, jadi ujungnya
adu ngotot. Pemilik biasanya ngalah — dan diam-diam nambahin harga sewa buat
nutup kerugian, yang bikin dia kalah saing.

### 2.3 Telat balik nggak ketahuan

Nggak ada yang ngingetin penyewa, nggak ada yang tahu unit belum balik sampai
penyewa berikutnya datang. Denda telat sudah ditulis di aturan tapi jarang ditagih
karena canggung dan nggak ada catatannya.

### 2.4 Nggak tahu untung berapa

Uang sewa masuk ke rekening pribadi, campur sama uang belanja. Akhir bulan nggak
ada yang tahu unit mana yang balik modal dan mana yang cuma numpang parkir.

---

## 3. Persona

### 3.1 Juragan — pemilik usaha *(user utama, yang bayar)*

1–3 lokasi, 5–50 unit. Umur 28–50. Melek HP, nggak melek software. Sudah pernah
coba Excel dan nyerah karena nggak bisa diakses pas lagi di luar. Keputusan
beli ditentukan satu hal: **apakah ini bikin saya berhenti ketakutan salah jadwal.**

- Butuh: lihat jadwal semua unit dalam satu layar, tahu uang masuk berapa, tahu
unit mana yang paling laku.
- Nggak akan pernah: baca manual, ikut training, isi data master selama 2 jam
sebelum bisa pakai.

### 3.2 Kasir / operator — *yang paling sering buka aplikasi*

Karyawan yang jaga toko. Yang sebenarnya ngetik data tiap hari, sering sambil
berdiri, sering pakai HP. Kecepatan input lebih penting dari kelengkapan data.

- Butuh: bikin booking dalam &lt; 60 detik, serah-terima dalam &lt; 3 menit.
- Nggak boleh bisa: lihat laporan keuangan, hapus data, ubah harga.

### 3.3 Penyewa — *tamu, bukan user*

Nggak install apa-apa, nggak bikin akun. Semua akses lewat link yang dikirim via
WhatsApp: lihat detail sewa, bayar, lihat bukti kondisi barang.

- Butuh: jelas kapan ambil, kapan balik, bayar berapa, deposit balik berapa.

---

## 4. Scope MVP

### 4.1 Masuk MVP


| #      | Fitur                                                              | Kenapa masuk                                                                                                                             |
| ------ | ------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------- |
| 1      | Auth pemilik + peran operator                                      | Operator adalah user harian; tanpa peran terbatas, pemilik nggak berani kasih akses                                                      |
| 2      | Katalog *resource* &amp; *unit*                                    | Fondasi semua data                                                                                                                       |
| 3      | Kalender ketersediaan                                              | Layar yang paling sering dibuka juragan                                                                                                  |
| 4      | Buat booking + **cek bentrok wajib**                               | Inti produk (§2.1)                                                                                                                       |
| 5      | Halaman booking publik per tenant (subdomain)                      | Penyewa bisa lihat ketersediaan sendiri; ngurangi bolak-balik WA. **Paket Usaha ke atas** (BR-025)                                       |
| 6      | Serah-terima ambil &amp; kembali + foto kondisi                    | Menyelesaikan §2.2                                                                                                                       |
| 7      | Deposit: tahan / potong / kembalikan                               | Menyelesaikan §2.2                                                                                                                       |
| 8      | Denda telat otomatis terhitung                                     | Menyelesaikan §2.3                                                                                                                       |
| 9      | Invoice multi-baris + bayar **transfer manual berbukti + AI scan** | Menyelesaikan §2.4. Gateway ditunda ke fase 2 — `04-api-spec.md` §3.8.1                                                                  |
| 10     | Pesan WhatsApp otomatis: tagihan, tenggat bayar, H-1 ambil, H-1 balik, telat | Menyelesaikan §2.3. Lima jenis; dua di antaranya **tidak bisa dimatikan** karena bagian dari transaksinya (`BR-070`)                   |
| 11     | Dashboard + laporan dasar **+ ekspor CSV/XLSX**                    | Menyelesaikan §2.4. Juragan yang butuh "untung berapa" hampir pasti mau angkanya masuk Excel                                             |
| 12     | Portal penyewa (link, tanpa akun)                                  | Ngurangi beban operator. Hidup di host yang sama dengan #5, jadi **ikut paket Usaha ke atas**                                            |
| ~~13~~ | ~~Langganan SaaS: paket, kuota unit, tagihan sendiri~~ **ditunda** | Disetup belakangan. Harga sudah diputuskan (§13); penagihannya menunggu jalur pembayaran menyala. Fase 1 tanpa batas unit &amp; pengguna |
| 14     | **API eksternal untuk situs pemilik sendiri** (`api.sewain.id`)    | Pemilik yang sudah punya situs menarik katalog dari sana — `BR-031`, `BR-032`                                                            |


### 4.2 Nggak masuk MVP *(dengan alasan — non-goal tanpa alasan bakal balik lagi minggu depan)*


| Nggak masuk                           | Alasan                                                                          |
| ------------------------------------- | ------------------------------------------------------------------------------- |
| Multi-cabang                          | Target awal 1 lokasi. Jadi bahan jualan naik paket begitu langganan dinyalakan. |
| Akuntansi lengkap (jurnal, neraca)    | Juragan butuh "untung berapa", bukan laporan akuntan.                           |
| Tanda tangan digital kontrak          | Foto + timestamp sudah cukup jadi bukti untuk sengketa deposit.                 |
| GPS tracking kendaraan                | Butuh hardware. Bisnis yang beda.                                               |
| Integrasi asuransi                    | Butuh partner. Nggak ada di jalur validasi awal.                                |
| App mobile native                     | Web responsif dulu. Bikin native sebelum tahu produknya benar = buang 2 bulan.  |
| Marketplace / direktori publik        | Cold-start dua sisi. Baru masuk akal setelah punya banyak tenant (fase 5).      |
| *Dynamic pricing*                     | Juragan belum minta. Butuh data historis yang belum ada.                        |
| Langganan berulang otomatis           | Itu model kos — sudah ada di `boarding-house-api`, dinyalakan di fase 2.        |
| Unit fungible tanpa penugasan di muka | Lihat §6.4 — penyederhanaan disengaja, ada jalur upgrade-nya.                   |


---

## 5. User story &amp; acceptance criteria

Format: `Sebagai … saya ingin … supaya …`, diikuti kriteria terima yang bisa diuji.
Kolom **BR** merujuk ke aturan di [`02-business-rules.md`](./02-business-rules.md).

### Epic A — Katalog

**A0.** Sebagai juragan baru, saya ingin daftar sendiri dan langsung bisa dipakai,
supaya nggak perlu nunggu siapa pun membuatkan akun saya. `BR-005, BR-017`

- Given saya isi email, password, nama usaha, dan **jenis usaha saya**, Then akun dan
usaha saya jadi sekaligus, dan saya **langsung masuk** — nggak perlu login lagi.
- Given saya belum diminta memilih alamat halaman apa pun waktu daftar, Then memang
belum perlu: halaman sendiri baru ada di paket berbayar, dan saya mengisinya nanti dari
pengaturan kalau memang mau. `BR-025`
- Given saya pilih "rental mobil" atau "rental alat", Then seluruh barang saya otomatis
dihitung **per hari**, dan saya **nggak pernah ditanya satuan harga** di form mana pun.
`BR-012, BR-017`
- Given email saya sudah dipakai di usaha lain, Then ditolak — satu email satu usaha.
`BR-004`
- Given saya baru masuk pertama kali, Then dashboard menunjukkan **langkah yang tersisa**
(tambah barang → tambah unit → booking pertama), bisa saya lewati, dan hilang sendiri
begitu selesai.
- Given saya belum klik tautan verifikasi di email, Then **belum ada satu pun layar
produk yang bisa saya buka** — cuma layar "cek email Anda" dengan tombol kirim ulang.
`BR-006`
- Given saya klik tautan verifikasinya, Then seluruh backoffice langsung terbuka.
Tautannya sekali pakai dan mati setelah 24 jam; kalau telat, kirim ulang selalu ada.
`BR-006`
- Given saya diundang sebagai operator, Then saya **tidak** diminta verifikasi lagi —
menerima undangan lewat tautan di email saya sudah jadi buktinya. `BR-004, BR-006`

**A1.** Sebagai juragan, saya ingin mendaftarkan jenis barang beserta unit fisiknya,
supaya sistem tahu persis ada berapa yang bisa disewakan. `BR-010, BR-011`

- Given saya punya 3 Avanza, When saya buat resource "Avanza 2021" lalu tambah 3 unit
dengan plat berbeda, Then kalender menampilkan 3 baris terpisah.
- Given saya isi harga sewa harian dan deposit di level resource, When saya bikin
booking, Then harga &amp; deposit ikut nilai itu tapi **disimpan sebagai snapshot** di
booking — naikin harga besok nggak ngubah booking yang sudah jadi. `BR-014`
- Given satu unit masuk bengkel, When saya set statusnya `maintenance`, Then unit itu
hilang dari hasil pencarian ketersediaan tapi booking yang sudah ada nggak terhapus. `BR-013`
- Given saya **nggak** isi deposit, denda telat, dan batas durasi, When saya simpan,
Then resource itu berjalan tanpa deposit, tanpa denda, dan tanpa batas durasi — bukan
dengan nilai nol. `BR-016`
- Given saya isi deposit `0`, Then sistem **menolak** dan menyuruh saya mengosongkannya
saja: nol dan kosong nggak boleh jadi dua cara menulis hal yang sama. `BR-016`
- Given saya buka form barang baru, Then **nggak ada pilihan satuan harga di layar** —
sudah ditentukan jenis usaha yang saya pilih waktu daftar. `BR-017`
- Given resource saya tanpa denda telat, When penyewa telat balik, Then peringatan
telatnya **tetap muncul** di dashboard dan pengingatnya tetap terkirim — yang nggak ada
cuma tagihannya. `BR-016, BR-041`

**A2.** Sebagai juragan, saya ingin menetapkan jeda bersih-bersih antar sewa,
supaya nggak ada penyewa yang datang pas unit belum sempat dicuci. `BR-015`

- Given `buffer_minutes = 120` pada resource, When ada booking selesai jam 10:00,
Then unit itu baru tampil tersedia mulai jam 12:00.

### Epic B — Ketersediaan &amp; booking *(inti produk)*

**B1.** Sebagai operator, saya ingin melihat unit mana yang kosong di rentang tanggal
tertentu, supaya bisa langsung jawab calon penyewa di telepon. `BR-020`

- Given tanggal 3–5 Sep dipilih, When saya cari, Then hanya unit tanpa booking yang
beririsan (termasuk buffer) yang muncul, dalam &lt; 1 detik.
- Given saya buka kalender, Then tiap blok berwarna menurut keadaannya — tersedia,
dipesan belum bayar, dipesan lunas, sedang disewa, telat, jeda bersih-bersih, atau
unit di bengkel — dan **legendanya tampil di layar**. `BR-033`
- Given saya tidak bisa membedakan merah dari hijau, Then kalendernya tetap terbaca:
tiap blok punya label teks dan pola, bukan cuma warna. `BR-033`
- Given ada pengajuan `draft`, Then ia **tidak** muncul di kalender — ia tidak mengunci
unit, dan blok yang terlihat padat bikin saya menolak penjualan yang boleh jalan.
`BR-023, BR-033`

**B2.** Sebagai operator, saya ingin membuat booking, supaya unit terkunci atas nama
penyewa. `BR-021, BR-022, BR-023`

- Given unit A sudah dibooking 3–5 Sep, When saya coba booking unit A 4–6 Sep,
Then sistem menolak dengan pesan yang menyebut booking yang bentrok.
- Given dua operator menekan Simpan pada **detik yang sama** untuk unit dan tanggal
yang sama, Then tepat satu yang berhasil dan satunya dapat error bentrok —
dijamin oleh constraint database, bukan oleh pengecekan di aplikasi. `BR-022`
- Given booking berhasil, Then sistem membuat kode booking yang bisa dibacakan
lewat telepon, memakai prefix milik saya (`RB-0042`; default `SWN` kalau belum
saya atur). `BR-024`
- Given saya ganti prefix jadi `BUDI`, Then kode yang **sudah terbit tidak berubah**
dan nomornya **tidak** balik ke 1 — `RB-0042` lalu `BUDI-0043`. `BR-024`
- Given saya isi prefix `rb` atau `TERLALUPANJANG`, Then ditolak: 2–6 huruf besar
atau angka, karena kode ini dibacakan lewat telepon. `BR-024`

**B3.** Sebagai penyewa, saya ingin mengajukan sewa lewat link tanpa bikin akun,
supaya nggak perlu chat bolak-balik. `BR-025`

- Given saya buka `rentalbudi.sewain.id`, Then saya lihat katalog + ketersediaan asli.
- Given saya ajukan tanggal, Then booking dibuat berstatus `draft` dan **belum**
mengunci unit; operator harus konfirmasi dulu. `BR-026`
- Given operator diam lebih dari `owners.draft_expiry_hours` (default 24 jam), Then draft
kedaluwarsa otomatis. `BR-027`
- Given saya buka subdomain yang tidak ada atau milik pemilik nonaktif, Then saya
dapat `404` yang sama persis — bukan pesan yang membocorkan pemilik mana yang
ada. `BR-030`
- Given pemilik mengubah katalog atau menonaktifkan unit di backoffice, Then halaman
publiknya langsung ikut berubah tanpa langkah publikasi terpisah. `BR-025`

**B4.** Sebagai juragan, saya ingin memblokir penyewa yang bermasalah, supaya operator saya nggak
bisa kebobolan orang yang sama dua kali. `BR-028`

- Given saya tandai seorang penyewa `blacklisted` beserta alasannya, When operator mencoba membuat
booking untuk dia, Then sistem menolak dan menampilkan alasan blokirnya ke operator.
- Given saya bukan pemilik (peran `operator`), Then aksi blokir &amp; buka blokir **tidak dirender**
sama sekali — bukan tampil lalu ditolak.
- Given penyewa terblokir mengajukan lewat halaman publik, Then dia menerima pesan netral
"pengajuan tidak dapat diproses, silakan hubungi pemilik" — **tanpa** alasan blokirnya.
`BR-025, BR-028`

**B5.** Sebagai operator, saya ingin menukar unit pada booking yang sudah jadi, supaya kalau satu
mobil masuk bengkel saya nggak perlu membatalkan sewanya. `BR-029`

- Given booking berstatus `reserved`, When saya tukar ke unit lain dari resource yang sama,
Then berhasil sepanjang unit tujuan lolos cek bentrok — termasuk buffer. `BR-022`
- Given booking sudah `picked_up`, Then aksi tukar unit **hilang dari layar**; barangnya sudah di
tangan penyewa dan riwayatnya harus tetap jujur.

**B6.** Sebagai juragan yang sudah punya situs sendiri, saya ingin menarik katalog dan
ketersediaan dari sewain ke `rentalbudi.com`, supaya nggak perlu mengurus dua katalog yang
isinya beda. `BR-031, BR-032`

- Given saya terbitkan API key di pengaturan, Then rahasianya **ditampilkan sekali saja** dan
sesudah itu nggak bisa dilihat lagi oleh siapa pun — termasuk saya.
- Given saya cabut sebuah kunci, Then panggilan berikutnya dapat `401`, tapi barisnya tetap ada
supaya log akses lama masih bisa dijelaskan.
- Given kunci saya dipakai untuk memanggil endpoint backoffice, Then dia dapat `404` — kunci
cuma membuka katalog, ketersediaan, dan pengajuan `draft`. `BR-031`
- Given seseorang mengirim kunci saya ke `api.sewain.id` bersama `Host` rental orang lain,
Then yang menentukan tetap kuncinya; `Host` **tidak pernah** menunjuk pemilik di host itu.
`BR-032`
- Given situs saya memanggil dari origin yang belum saya daftarkan, Then browsernya diblokir
`403` — sambil saya sadar bahwa allowlist ini kontrol browser, bukan kontrol keamanan.

### Epic C — Serah-terima

**C1.** Sebagai operator, saya ingin mencatat kondisi barang saat keluar,
supaya ada bukti kalau nanti ada sengketa. `BR-035, BR-036`

- Given booking berstatus `reserved`, When saya proses pengambilan, Then saya wajib
unggah minimal 1 foto dan (untuk kendaraan) mengisi odometer &amp; level BBM.
- Given serah-terima selesai, Then foto &amp; waktunya **tidak bisa diubah atau dihapus**
oleh siapa pun, termasuk pemilik. `BR-037`
- Given pembayaran sewa belum lunas dan pemilik mewajibkan bayar di muka,
Then pengambilan diblokir. `BR-038`

**C2.** Sebagai operator, saya ingin mencatat pengembalian dan **diusulkan** potongan
depositnya, supaya nggak perlu ngitung manual sambil dilihatin penyewa — tapi tetap saya
yang memutuskan. `BR-040, BR-045, BR-051`

- Given unit balik lewat dari `end_at`, Then denda telat terhitung dari tarif yang
disimpan di booking dan **ditampilkan sebagai usulan bercentang**, belum jadi tagihan.
`BR-046, BR-051`
- Given saya hapus centang pada denda telat, Then barisnya **nggak terbit sama sekali** —
bukan terbit lalu dinolkan — dan saya wajib mengisi alasannya. `BR-051`
- Given saya tandai ada kerusakan dan isi nominalnya, Then baris `damage` diusulkan
bersama foto rujukannya, dan sisa deposit terhitung ulang tiap centang berubah.
`BR-047, BR-048`
- Given potongan melebihi deposit, Then selisihnya jadi tagihan baru, bukan
deposit minus. `BR-048`
- Given booking ini tanpa deposit, Then nggak ada layar penyelesaian deposit sama sekali
dan `completed` nggak diblokir. `BR-016, BR-049`
- Given saya tekan Simpan dua kali karena sinyal jelek, Then penyewa **nggak** ditagih dua
kali untuk satu lecet. `BR-090`

**C2b.** Sebagai pemilik, saya ingin membebaskan deposit untuk penyewa tertentu, supaya
pelanggan lama nggak perlu menaruh jaminan. `BR-051` *(M4: hanya pemilik — versi lama
menulis "operator"; lihat catatan di BR-051.)*

- Given invoice yang memuat baris `deposit` belum lunas, When saya bebaskan depositnya,
Then barisnya dicabut, total invoice turun, dan alasan saya tercatat.
- Given depositnya sudah dibayar, Then tombol bebaskan **nggak ada** — jalurnya jadi
pengembalian saat penyelesaian, karena invoice lunas nggak pernah diubah. `BR-048`
- Given saya bebaskan depositnya, Then nama saya, waktunya, dan alasan saya tercatat —
ketiganya wajib, dan juragan bisa menelusurinya belakangan. `BR-051`
- Given juragan mengecek, Then `deposit_amount` di booking itu **nggak berubah** — yang
berubah cuma apakah barisnya ditagih. Nilainya tetap urusan juragan (`BR-003`).

**C3.** Sebagai juragan, saya ingin tahu unit yang belum balik padahal sudah lewat
waktu, supaya bisa nelpon sebelum penyewa berikutnya datang. `BR-041`

- Given ada booking `picked_up` yang `end_at`-nya sudah lewat, Then dia muncul di
dashboard sebagai peringatan.
- Given unit belum balik, When operator coba proses pengambilan booking berikutnya
untuk unit yang sama, Then sistem memperingatkan dan minta konfirmasi
eksplisit — karena secara jadwal nggak bentrok, tapi secara fisik barangnya
belum ada. `BR-042`

### Epic D — Uang

**D1.** Sebagai juragan, saya ingin satu tagihan memuat sewa, deposit, denda, dan
kerusakan, supaya penyewa lihat rincian utuh. `BR-055, BR-056`

**D2.** Sebagai penyewa, saya ingin membayar dengan transfer dan mengunggah buktinya,
supaya nggak perlu ketemu orang buat melunasi. `BR-060, BR-061`

- Given saya transfer manual dan unggah bukti, Then sistem membaca nominal &amp;
tanggalnya otomatis dan menandai apakah cocok dengan tagihan — operator tinggal
menyetujui, bukan mengetik ulang. `BR-062`
- Given saya buka portal, Then saya lihat instruksi transfer + nomor rekening pemilik dan tombol
unggah bukti — **tidak** ada tombol bayar online di fase 1. `BR-061`

**D2-fase2.** Sebagai penyewa, saya ingin bayar online lewat gateway. *(Ditunda — `04-api-spec.md`
§3.8.1. Kontraknya sudah utuh di BR-063/BR-064, ACnya di bawah berlaku begitu gateway dinyalakan.)*

- Given webhook gateway masuk dua kali untuk transaksi yang sama, Then hanya satu
pembayaran tercatat. `BR-063`
- Given penyewa diarahkan balik dari halaman gateway dengan status "sukses",
Then sistem **tidak** menandai lunas sebelum webhook terverifikasi masuk. `BR-064`

**D3.** Sebagai juragan, saya ingin deposit dikembalikan dan tercatat,
supaya nggak ada uang penyewa yang nyangkut tanpa jejak. `BR-049`

### Epic E — Notifikasi

**E1.** Sebagai penyewa, saya ingin diingatkan sebelum jadwal ambil dan balik.
`BR-070, BR-071`

- Tiga **pengingat** yang boleh dimatikan pemilik satu per satu: H-1 sebelum ambil ·
H-1 sebelum balik · hari-H saat lewat waktu.
- Dua sisanya **tidak bisa dimatikan** karena bukan pengingat melainkan bagian dari
transaksinya: `invoice_link` saat invoice terbit, dan `payment_due_reminder` sebelum
tenggat bayar — menagih atau membatalkan diam-diam tidak sah. `BR-057, BR-070`
- Given nomor WhatsApp tidak valid, Then kegagalan tercatat dan terlihat oleh
operator — bukan gagal diam-diam. `BR-072`

### Epic F — Laporan

**F1.** Sebagai juragan, saya ingin tahu pemasukan dan unit mana yang paling laku.
`BR-075`

- Pemasukan per periode (sewa, denda, kerusakan — dipisah dari deposit, karena
deposit bukan pendapatan). `BR-076`
- Tingkat pemakaian per unit: berapa persen hari dalam periode unit itu tersewa.
- Daftar unit yang nganggur &gt; 30 hari.
- Given saya pilih periode dan tekan Ekspor, Then berkas CSV/XLSX terbit lewat job berjadwal
(bukan bikin request-nya timeout) dan tautan unduhnya kedaluwarsa 15 menit — laporan memuat
data penyewa, jadi tautannya tidak boleh hidup selamanya di riwayat WhatsApp. `BR-077`

---

## 6. Data model

Ditulis sebagai **delta dari skema `boarding-house-api`** yang sudah jalan.
Kolom "Asal" menunjukkan apakah tabel dipakai apa adanya, diganti nama, atau baru.


| Tabel                                      | Asal                                | Catatan                                         |
| ------------------------------------------ | ----------------------------------- | ----------------------------------------------- |
| `owners`                                   | dipakai apa adanya                  | Akar tenancy. `migrations/000002`               |
| `users`                                    | dipakai, tambah `owner_id` + `role` | `owner`                                         |
| `resources`                                | **baru**                            | Jenis barang; pemegang harga, deposit, buffer   |
| `resource_units`                           | **baru**                            | Unit fisik; ini yang dibooking                  |
| `customers`                                | ganti nama dari `tenants`           | Tambah identitas (KTP/SIM) &amp; blacklist      |
| `bookings`                                 | ganti nama dari `room_assignments`  | Tambah `tstzrange`, deposit, denda, kode        |
| `handovers`                                | **baru**                            | Bukti kondisi ambil &amp; kembali               |
| `invoices`                                 | ganti nama dari `bills`             | Tambah baris rincian                            |
| `invoice_lines`                            | **baru**                            | Kos cuma butuh satu nilai; rental butuh rincian |
| `payments`, `payment_gateway_transactions` | dipakai apa adanya                  | `migrations/000009`, `000010`                   |
| `payment_proofs`                           | dipakai apa adanya                  | Termasuk hasil AI scan. `migrations/000013`     |
| `subscriptions`                            | **baru**                            | Langganan SaaS-nya sendiri                      |


### 6.1 Aturan anti-bentrok — bagian terpenting di dokumen ini

Skema kos memakai *partial unique index* "satu assignment aktif per kamar"
(`migrations/000007`). Aturan itu tidak bisa menjawab pertanyaan inti rental:
*"mobil ini kosong nggak tanggal 3–5?"* — karena tidak memahami rentang tanggal.

Gantinya, bentrok dijamin oleh **exclusion constraint** di database:

```sql
CREATE EXTENSION IF NOT EXISTS btree_gist;  -- wajib: dibutuhkan agar uuid bisa dipakai dengan '='

ALTER TABLE bookings
  ADD CONSTRAINT bookings_no_overlap
  EXCLUDE USING gist (
    resource_unit_id WITH =,
    tstzrange(start_at, end_at_with_buffer, '[)') WITH &&
  )
  WHERE (status IN ('reserved', 'picked_up') AND deleted_at IS NULL);
```

Tiga hal yang perlu dipahami dari constraint ini:

1. `**[)` — awal inklusif, akhir eksklusif.** Booking yang selesai jam 10:00 dan
ooking yang mulai jam 10:00 tidak dianggap bentrok. Ini yang benar.
2. **Statusnya yang mengunci hanya `reserved` dan `picked_up`.** `draft`,
cancelled`,` no_show`,` returned`, dan` completed` tidak mengunci unit —
adi pengajuan dari halaman publik tidak memblokir penjualan sungguhan.
3. **Ini jaminan struktural, bukan validasi.** Dua request bersamaan tetap aman
anpa kunci di level aplikasi. Aplikasi tetap harus mengecek lebih dulu supaya
esan errornya enak dibaca, tapi *kebenarannya* dijaga database.

`end_at_with_buffer` **diisi trigger database** — `end_at + buffer_minutes`, bukan dihitung
aplikasi. (Kolom generated sudah dicoba dan ditolak PostgreSQL: `timestamptz + interval` tidak
immutable. Uraiannya di `03-erd.md` §3.) Yang disalin dari resource saat booking dibuat adalah `buffer_minutes`-nya,
bukan hasil penjumlahannya. Bedanya penting: kalau aplikasi yang menjumlahkan, satu jalur insert
yang lupa menghasilkan buffer `0` — constraint tetap lolos, tidak bentrok, tapi tanpa jeda
bersih-bersih. Lihat `03-erd.md` §3.

Buffer disimpan per resource dan bisa diubah — **jangan di-hardcode**; waktu bersih-bersih mobil
dan waktu bersih-bersih tenda tidak sama, dan hanya juragan yang tahu angka aslinya.

### 6.2 `resources` — jenis barang

```
id, owner_id, name, category, description, images[]
pricing_unit      -- NOT NULL default 'day'; diisi SERVER dari owners.business_type (BR-017)
base_price        -- bigint, rupiah penuh (bukan desimal)
deposit_amount    -- bigint, NULL = tanpa deposit        ← 0 dilarang (BR-016)
late_fee_per_unit -- bigint, NULL = tanpa denda telat    ← 0 dilarang
buffer_minutes    -- int NOT NULL default 0, jeda bersih-bersih (BR-015)
min_duration, max_duration  -- int, NULL = tanpa batas
requires_id_verification    -- bool NOT NULL default false
status            -- 'active' | 'inactive'
```

`pricing_unit` adalah satu-satunya field yang perlu berubah untuk membuka kos
(`month`) dan lapangan (`hour`) nanti. Itu inti dari tesis "satu mesin, empat pasar".

### 6.3 `resource_units` — unit fisik

```
id, owner_id, resource_id
code              -- plat nomor / nomor seri; unik per owner
label             -- nama panggilan ("Avanza Putih")
status            -- 'active' | 'maintenance' | 'retired'
meter_value       -- odometer / jam pakai terakhir
condition_notes
```

### 6.4 `bookings`

```
id, owner_id, code, customer_id, resource_id, resource_unit_id
start_at, end_at              -- timestamptz
end_at_with_buffer            -- tersimpan; dipakai constraint
status                        -- lihat §8
source                        -- 'staff' | 'public_page'
-- snapshot harga (jangan pernah baca ulang dari resources):
unit_price, pricing_unit, duration_qty, subtotal
deposit_amount, late_fee_per_unit   -- NULL ikut tersalin sebagai NULL (BR-016)
-- pembebasan deposit (BR-051), ketiganya terisi bersama atau kosong bersama:
deposit_waived_at, deposit_waived_by, deposit_waiver_reason
-- penyelesaian:
actual_return_at
deposit_deducted, deposit_refunded, deposit_note
cancelled_reason
```

> **Penyederhanaan yang disengaja:** unit fisik ditentukan **saat booking dibuat**,
> bukan saat pengambilan. Artinya untuk 10 tenda identik, sistem langsung menunjuk
> tenda nomor berapa. Ini membuat exclusion constraint mengerjakan seluruh pekerjaan
> berat — tidak perlu penghitungan kapasitas sama sekali.
>
> Harganya: pemakaian unit sedikit kurang optimal (bisa ada celah yang sebetulnya
> muat kalau unitnya ditukar). Operator boleh menukar unit kapan saja sebelum
> pengambilan, dan itu menutup hampir semua kasus nyata.
>
> *Naikkan ke penghitungan kapasitas hanya kalau ada tenant yang benar-benar
> kehilangan penjualan karena ini — dan buktikan dulu dengan datanya.*

### 6.5 `handovers` — bukti kondisi

```
id, owner_id, booking_id
direction         -- 'pickup' | 'return'
performed_by, performed_at
photos[]          -- kunci objek R2 (bukan URL), minimal 1
meter_value, checklist (jsonb)   -- BBM, kelengkapan, dsb — beda per kategori barang
condition_notes
```

`checklist` sengaja `jsonb`: isian untuk mobil (BBM, ban serep, STNK) dan untuk
sound system (jumlah kabel, speaker) tidak akan pernah sama, dan bikin tabel
per kategori adalah jalan tercepat menuju penyesalan.

Baris `handovers` bersifat **append-only**. Nilainya sebagai bukti sengketa
hilang total begitu bisa diedit belakangan.

### 6.6 `invoice_lines`

```
id, owner_id, invoice_id
kind        -- 'rent' | 'deposit' | 'late_fee' | 'damage' | 'discount'
description, amount   -- bigint; discount bernilai negatif
```

Baris `deposit` **bukan pendapatan**. Laporan wajib memisahkannya, kalau tidak
juragan akan mengira dirinya lebih untung dari kenyataan — persis kesalahan yang
sedang dia coba hindari (§2.4).

### 6.7 Konvensi yang diwarisi

Diambil dari `new-commerce-api/CLAUDE.md`, dokumen konvensi paling matang di repo:

- Uang sebagai **bigint rupiah penuh** — `120000` berarti Rp 120.000. Tidak pernah float,
tidak pernah `numeric`, dan **bukan sen**.
  > Ini titik di mana konvensi new-commerce **tidak** diadopsi. `new-commerce` memakai minor unit
  > (`19900000` = Rp 199.000); menyalin helper uangnya bulat-bulat ke sini menghasilkan tagihan
  > 100× — dan tagihan itu benar-benar terkirim ke penyewa. Lihat `04-api-spec.md` §2.
- Primary key UUID.
- Error `application/problem+json` (RFC 9457).
- Paginasi berbasis cursor.
- `owner_id` **selalu** diturunkan dari token, **tidak pernah** dari request body
(`boarding-house-api/CLAUDE.md`). Pada jalur publik tanpa token, `owner_id`
diturunkan dari header `Host` — tetap tidak pernah dari path, query, atau body
(`BR-030`).

Field baru di `owners`. Satu identitas publik, sisanya knob yang diatur dari
`PATCH /settings` dan **tidak boleh di-hardcode** di konsumen mana pun:

```
slug                          -- label subdomain, unik global; halaman publik <slug>.sewain.id
                                 NULL = belum punya halaman sama sekali (BR-025)
business_type                 -- preset pasar, dipilih saat daftar; menentukan pricing_unit (BR-017)
booking_code_prefix           -- 2-6 huruf besar/angka, default 'SWN' (BR-024)
require_payment_before_pickup -- bool, default false (BR-038)
draft_expiry_hours            -- default 24 (BR-027)
payment_due_hours             -- default 24 (BR-057)
no_show_tolerance_hours       -- default 3 (BR-057)
notify_pickup_reminder        -- bool (BR-070)
notify_return_reminder        -- bool (BR-070)
notify_overdue_reminder       -- bool (BR-070)
allowed_origins               -- text[], default kosong; CORS API eksternal (BR-031)
```

Tipe lengkapnya di `03-erd.md` §1.

Empat host, dan pemisahan tenant terjadi di sini — bukan di segmen path:

```
app.sewain.id            backoffice          M0–M5  ← fokus utama, cookie host-only
rentalbudi.sewain.id     katalog penyewa     M5     ← fitur MVP #5, bukan promosi
api.sewain.id            webhook + API kunci M5     ← BR-031, BR-032
sewain.id                promosi             M7     ← paling akhir
```

---

## 7. Alur utama

### 7.1 Booking sampai bayar

```
Penyewa/operator pilih tanggal
   └─> Sistem cari unit kosong (constraint + buffer)
        └─> Booking dibuat: status `reserved`, unit terkunci
             └─> Invoice terbit: baris `rent` (+ `deposit`, kalau resource-nya pakai)
                  └─> Instruksi transfer dikirim via WhatsApp
                       └─ Transfer manual ─> unggah bukti ─> AI baca nominal
                                             ─> operator setujui ──> lunas

                       ┄ Bayar gateway ──> webhook terverifikasi ──> lunas
                         (FASE 2 — nonaktif, 04-api-spec.md §3.8.1)
```

### 7.2 Pengambilan

```
Operator buka booking `reserved`
   └─> Cek: sudah lunas? (kalau pemilik mewajibkan bayar di muka)
        └─> Foto kondisi + odometer + checklist  [WAJIB]
             └─> status `picked_up`; unit_status `rented`
```

### 7.3 Pengembalian &amp; penyelesaian deposit

```
Operator buka booking `picked_up`
   └─> Foto kondisi + odometer
        └─> Sistem MENGUSULKAN — belum menagih apa pun:
             telat? ──> usul baris `late_fee`   (nihil kalau tanpa tarif denda)
             rusak? ──> usul baris `damage`     (nominal diisi operator)
             └─> Operator mencentang / membebaskan   [alasan WAJIB]   BR-051
                  └─> Yang dicentang terbit. Yang tidak: tidak ada barisnya.
                       └─> Sisa deposit = deposit − potongan terkonfirmasi
                            ├─ tanpa deposit ─> langsung `completed`
                            ├─ sisa ≥ 0 ──> dikembalikan, tercatat
                            └─ sisa < 0 ──> terbit tagihan baru sebesar selisihnya
                                 └─> status `completed`; unit_status `active`
```

### 7.4 Telat

```
end_at lewat, status masih `picked_up`
   └─> Muncul di dashboard sebagai peringatan
   └─> Pengingat WhatsApp otomatis ke penyewa
   └─> Booking berikutnya untuk unit yang sama: operator diperingatkan saat
       akan menyerahkan barang — bentroknya fisik, bukan jadwal
```

---

### 7.5 Tenggat bayar & booking yang tidak jadi

Dua jam berdetak di umur satu booking, dan **tidak pernah bersamaan** — draft belum
punya invoice, jadi belum punya tenggat bayar:

```
draft ──(draft_expiry_hours, BR-027)──► hangus
  │
  └─ operator konfirmasi ──► reserved ──► invoice terbit ──► due_at berdetak (BR-057)
```

Booking dari staf langsung `reserved`, jadi tidak pernah lewat tahap draft. Seluruh
kasus di bawah terjadi **sesudah** konfirmasi operator.

`due_at = min(created_at + payment_due_hours, start_at)`. Contoh memakai default
`payment_due_hours = 24` dan `no_show_tolerance_hours = 3`.

#### Pemilik mewajibkan bayar di muka (`require_payment_before_pickup = true`)

```
① Booking jauh hari, dibayar
   Sen 10:00  booking 20 Sep, invoice terbit → invoice_link terkirim
              due_at = min(Sel 10:00, 20 Sep 09:00) = Sel 10:00
   Sen 18:00  payment_due_reminder
   Sen 20:00  lunas  →  20 Sep pickup ✅

② Booking jauh hari, TIDAK dibayar          ← ini nilai utamanya
   Sel 10:00  belum lunas
              invoice → overdue
              booking → cancelled (payment_expired)
              unit    → BEBAS, 18 hari sebelum tanggal sewanya

③ Booking mendadak — start_at yang jadi tenggat, bukan 24 jam
   Sen 10:00  booking untuk BESOK Sel 09:00
              due_at = min(Sel 10:00, Sel 09:00) = Sel 09:00   ← start_at menang
   Sel 09:00  belum lunas → cancelled
```

Tanpa ②, unit terkunci sampai tanggal sewanya oleh orang yang tidak pernah bayar — dan
tanggal paling laku justru paling lama tersandera. Di ③, tenggat 24 jam akan jatuh
**setelah** mobilnya seharusnya keluar; `min(…)` yang mencegahnya.

#### Pemilik menerima bayar saat ambil (default, sakelar mati)

```
④ Bayar di konter
   Sel 09:00  penyewa DATANG, belum bayar
              invoice → overdue          (penanda saja)
              booking → TETAP reserved   (tidak dibatalkan)
              operator terima uang → lunas → pickup ✅

⑤ Penyewa tidak muncul
   Sel 09:00  start_at lewat, tidak diambil, tidak dibayar
              invoice → overdue, booking tetap reserved
   Sel 12:00  start_at + 3 jam
              booking → no_show
              unit    → BEBAS, hari itu juga
```

④ adalah alasan akibat `due_at` **harus** bergantung sakelarnya: kalau pembatalan
otomatis berlaku untuk semua, booking ini hangus tepat saat penyewanya berdiri di
konter memegang uang. ⑤ yang menutup lubang untuk konfigurasi **default** — dan default
adalah mayoritas pemilik.

> **Unit bebas hari itu juga.** Default `no_show_tolerance_hours = 3` memberi
> kelonggaran macet tanpa membuang satu hari sewa — `0` akan membuat setiap pengambilan
> normal berlomba dengan job-nya, `24` membuang satu periode sewa penuh. Uraian
> perbandingannya di BR-057.
>
> Job **tidak pernah menyentuh booking yang serah-terimanya sudah dimulai**, dan
> `POST …/pickup` atas booking `no_show` tidak langsung ditolak — dua kewajiban itu
> berlaku berapa pun angkanya, karena pemilik boleh menurunkannya sampai `0`.

#### Yang sengaja tidak disentuh

Job kedaluwarsa hanya menyentuh booking `reserved`. Begitu barang keluar
(`picked_up`), tidak ada yang otomatis membatalkan apa pun — invoice yang belum
tercatat menggantung di dashboard sampai ada manusia yang menutupnya. Mobil sudah di
jalan; membatalkan bookingnya tidak menariknya pulang.

| | Sakelar menyala | Sakelar mati |
|---|---|---|
| Lewat `due_at` | booking **hangus** | invoice ditandai, booking hidup |
| Lewat `start_at` + toleransi | sudah hangus duluan | booking → `no_show` |
| Sudah `picked_up` | tidak disentuh | tidak disentuh |

**Tidak ada satu pun booking yang bisa mengunci unit tanpa batas waktu** — yang
sebelumnya bisa terjadi di kedua konfigurasi.

---

## 8. State machine booking

```
                  ┌─────────── cancelled ◄──────────┐
                  │                                 │
draft ──konfirmasi──> reserved ──ambil──> picked_up ──kembali──> returned ──> completed
  │                     │                                            
  └─ kedaluwarsa*       └── no_show (lewat start_at, nggak diambil)
```


| Transisi               | Siapa                 | Syarat                                                           |
| ---------------------- | --------------------- | ---------------------------------------------------------------- |
| `draft → reserved`     | operator/pemilik      | Unit lolos cek bentrok saat itu juga — bukan saat draft dibuat   |
| `draft → cancelled`    | siapa saja / otomatis | Kedaluwarsa `owners.draft_expiry_hours`, default 24 jam (BR-027) |
| `reserved → picked_up` | operator/pemilik      | Serah-terima terisi; lunas kalau pemilik mewajibkan              |
| `reserved → cancelled` | operator/pemilik      | Kebijakan refund menyusul (fase 2)                               |
| `reserved → no_show`   | otomatis              | Lewat `start_at` + toleransi, belum diambil                      |
| `picked_up → returned` | operator/pemilik      | Serah-terima kembali terisi                                      |
| `returned → completed` | operator/pemilik      | Deposit sudah diselesaikan — **atau tanpa deposit** (BR-016)     |


`**overdue` sengaja bukan status.** Itu kondisi turunan
(`status = picked_up AND end_at < now()`). Menjadikannya status berarti butuh cron
yang mengubah baris data, dan cron yang mengubah data adalah sumber bug yang tidak
sebanding dengan manfaatnya. Sebagai bonus, unit tetap terkunci selama masih
`picked_up` — perilaku yang benar, gratis.

---

## 9. Kebutuhan non-fungsional


| Aspek               | Ketentuan                                                                                                                                                                                                                                                                                                                                                               |
| ------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Isolasi tenant      | Setiap query wajib difilter `owner_id`; ada test lintas-owner (`BR-001`)                                                                                                                                                                                                                                                                                                |
| Anti double-booking | Dijamin constraint database, bukan aplikasi (`BR-022`)                                                                                                                                                                                                                                                                                                                  |
| Uang                | Integer **rupiah penuh** (`120000` = Rp 120.000); tidak pernah float, tidak pernah sen                                                                                                                                                                                                                                                                                  |
| Webhook             | Tanda tangan diverifikasi, payload mentah disimpan, pemrosesan idempoten                                                                                                                                                                                                                                                                                                |
| Bukti kondisi       | Append-only; tidak bisa diubah/dihapus siapa pun (`BR-037`)                                                                                                                                                                                                                                                                                                             |
| Data pribadi        | Foto KTP/SIM terenkripsi saat disimpan, akses tercatat audit log, tautan baca 5 menit (`BR-085`). **Retensi otomatis ditunda** — fase 1 tidak menghapus foto identitas, dan keputusan UU PDP diambil setelah PT berdiri (`BR-086`, §12 #3)                                                                                                                                 |
| Audit               | `created_at`/`updated_at`/`created_by` di semua tabel utama                                                                                                                                                                                                                                                                                                             |
| Durabilitas         | **Object storage dan backup database wajib di luar mesin aplikasi.** Foto serah-terima adalah satu-satunya alasan sengketa deposit (§2.2) bisa diselesaikan, dan BR-037 melarang siapa pun menghapusnya — kalau ia hilang bersama mesinnya, jaminan itu bohong. Object storage: **Cloudflare R2**. Backup PostgreSQL: `pgBackRest` ke R2, bukan ke disk mesin yang sama |
| Tulis aman diulang  | Setiap `POST` yang menghasilkan uang atau booking menerima `Idempotency-Key`; kunci sama dijalankan sekali. Tanpa ini frontend tidak punya cara aman me-retry di jaringan seluler (`BR-090`)                                                                                                                                                                            |
| Pekerjaan latar     | Pekerjaan berjadwal dan yang terlalu lama untuk satu request jalan di luar proses API, dengan retry, dead-letter yang terlihat, dan penjadwal yang tidak jalan dobel (`BR-091`)                                                                                                                                                                                         |
| Observability       | `trace_id` di setiap error **bisa ditelusuri ke span-nya**, bukan UUID acak — pengguna disuruh menyalinnya ke tiket support (`BR-092`)                                                                                                                                                                                                                                  |
| Kecepatan           | Pencarian ketersediaan &lt; 1 detik untuk 500 unit × 12 bulan                                                                                                                                                                                                                                                                                                           |
| Perangkat           | Web responsif; alur serah-terima wajib enak dipakai satu tangan di HP                                                                                                                                                                                                                                                                                                   |
| Offline             | **Tidak didukung.** Sinyal jelek di lokasi rental itu nyata, tapi sinkronisasi offline pada data yang justru butuh cek bentrok real-time adalah cara paling cepat menciptakan double-booking yang mau dihindari.                                                                                                                                                        |


---

## 10. Metrik sukses

Empat angka, semuanya diukur di lapangan dan bukan di DevTools. Tiap satu punya item backlog
yang memilikinya, supaya tidak ada target yang cuma jadi kalimat di dokumen.


| Metrik                      | Target                          | Yang mengukur                                                     | Kenapa ini yang diukur                                                                                                                                       |
| --------------------------- | ------------------------------- | ----------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Lama serah-terima           | **&lt; 3 menit**                | `S1-072` — Android kelas menengah, jaringan seluler, satu tangan  | Alur ini dipakai sambil berdiri di parkiran dengan penyewa menunggu. Lewat dari itu operator berhenti memakainya, dan bukti kondisi (§2.2) hilang bersamanya |
| Lama membuat booking        | **&lt; 60 detik**               | `S1-029` — operator berpengalaman                                 | Kasir mengetik sambil menjawab telepon (§3.2). Kalau lebih lama dari mencatat di buku, buku yang menang                                                      |
| Booking dari halaman publik | **≥ 20%** dari seluruh booking  | `bookings.source = 'public_page'`, dibaca laporan `S1-056`        | Ini yang membuktikan fitur MVP #5 mengurangi bolak-balik WhatsApp, bukan sekadar menambah satu halaman                                                       |
| Design partner bertahan     | **5 rental**, 1 bulan penuh     | `S1-076`                                                          | Syarat masuk fase 2 (§12). Ditulis sebagai angka supaya tidak pelan-pelan berubah jadi harapan                                                               |


**Yang sengaja bukan metrik:** jumlah pendaftar, jumlah unit terdaftar, dan jumlah halaman
publik yang dibuat. Ketiganya bisa naik tanpa satu pun juragan berhenti ketakutan salah
jadwal (§3.1) — itu angka yang enak dilaporkan dan tidak memberi tahu apa pun.

Kecepatan pencarian ketersediaan (&lt; 1 detik) tinggal di §9: ia anggaran teknis yang wajib
dipenuhi tiap rilis, bukan metrik adopsi yang diukur sekali.

---

## 11. Roadmap

### Fase 1 — Rental &amp; sewa *(MVP, ~19 minggu)*

Isi dokumen ini. Target: 5 design partner rental mobil/motor di satu kota.

**Urutan bangun** (per modul, satu-satu, sesuai aturan di `boarding-house-api/CLAUDE.md`):


| Minggu | Milestone backlog | Modul                                                                                                                    |
| ------ | ----------------- | ------------------------------------------------------------------------------------------------------------------------ |
| 1–3    | `M0`              | Fondasi: `owners`, auth, **pengaturan pemilik, kelola pengguna**, RLS, idempotensi                                       |
| 4–5    | `M1`              | Katalog: `resources` + `resource_units`                                                                                  |
| 6–8    | `M2`              | **Ketersediaan &amp; booking + exclusion constraint** ← risiko terbesar, dapat 3 minggu                                  |
| 9–10   | `M3`              | Serah-terima + upload foto (object storage R2)                                                                           |
| 11–12  | `M4`              | Job runner · invoice multi-baris · deposit · denda · bukti manual + AI scan                                              |
| 13–16  | `M5`              | Halaman publik · **API eksternal** · portal penyewa · notifikasi WA · dashboard · laporan &amp; ekspor · tim &amp; peran |
| 17–18  | `M6`              | Produksi, latihan restore, dan uji lapangan bareng design partner                                                        |
| 19     | `M7`              | Halaman promosi `sewain.id` — di luar kriteria selesai fase 1                                                            |


### Fase 2 — Kos &amp; properti *(~3 minggu)*

Nyalakan lagi tagihan bulanan berulang dari `boarding-house-api` di atas engine
yang sama. **Nyaris tanpa kode baru** — sebagian besar pekerjaannya menggabungkan
apa yang sudah ada, plus `pricing_unit = 'month'` dan kontrak berulang.

> **API eksternal sudah pindah ke fase 1** (`BR-031`, M5). Alasannya berdiri sendiri:
> skemanya sudah dirancang lengkap, dan ia tidak menambah permukaan kebocoran data —
> cuma permukaan penyalahgunaan kuota. Ia **tidak** menunggu rilis paket apa pun;
> langganan sendiri justru ditunda.

Fase ini juga jadi **uji apakah tesis "satu mesin" benar-benar berlaku.** Kalau
menyatukan kos ternyata sulit, berarti engine-nya kurang generik dan lebih baik
ketahuan di sini — sebelum dua vertikal lagi ditumpuk di atasnya.

### Fase 3 — Lapangan &amp; jadwal *(~4 minggu)*

`pricing_unit = 'hour'`, kalender grid per jam, dan satu-satunya hal yang benar-benar
baru: **jadwal berulang mingguan** (member yang sewa tiap Selasa jam 20:00).

### Fase 4 — Klinik &amp; perawatan *(~4 minggu)*

Resource = orang, bukan barang. Jam praktik per praktisi, catatan per kunjungan.
**Berhenti dan tinjau ulang soal data sensitif sebelum mulai** — data kesehatan
punya kewajiban hukum sendiri, dan itu keputusan bisnis, bukan keputusan teknis.

### Fase 5 — Direktori publik *(opsional)*

Setelah punya cukup tenant, buka direktori yang menarik dari katalog tenant yang
sudah ada. **Marketplace sebagai panen, bukan sebagai taruhan awal** — supply-nya
sudah ada duluan, jadi tidak ada masalah cold-start dua sisi.

---

## 12. Risiko &amp; pertanyaan terbuka

### Risiko


| Risiko                                                      | Dampak                                                 | Mitigasi                                                                                                                                                                                                                                                                                                                                                 |
| ----------------------------------------------------------- | ------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Nomor WhatsApp kena blokir**                              | Fitur andalan mati, pelanggan marah                    | Pakai **Cloud API resmi Meta** sejak awal — integrasinya sudah ada di `agent-posyandu/wa_cloud.py`. Jangan pernah tiru pola pairing nomor pribadi ala RoomKost.                                                                                                                                                                                          |
| **Pasar rental belum terbiasa bayar software**              | Konversi rendah                                        | Validasi ke 5 design partner **sebelum** minggu ke-15. Kalau nggak ada yang mau bayar Rp 99k, masalahnya di premis, bukan di fitur.                                                                                                                                                                                                                      |
| **Fokus pecah karena kepengin buru-buru multi-vertikal**    | Nggak ada satu pun vertikal yang selesai               | Fase 2 baru boleh mulai setelah 5 tenant rental bertahan 1 bulan penuh. Tulis angka ini sebagai syarat, bukan harapan.                                                                                                                                                                                                                                   |
| **Operator maunya app mobile**                              | Adopsi seret di lapangan                               | Web responsif dulu, ukur keluhan sungguhan. PWA sebagai jalan tengah yang murah.                                                                                                                                                                                                                                                                         |
| **Model bentrok tidak menutup pola sewa nyata**             | Masalah inti tidak selesai                             | Beda dari baris di atas: constraint-nya terbukti jalan, yang belum terbukti adalah **modelnya** — setengah hari, perpanjangan di tengah sewa, balik-dan-keluar di hari yang sama. Ini pertanyaan *requirement*, jawabannya cuma ada di pemilik rental sungguhan. Butuh **pola booking dari 3 pemilik sebelum M2 (minggu 6)** — wawancara, bukan kontrak. |
| `**Host` dipercaya padahal API bisa dijangkau tanpa proxy** | Isolasi jalur publik runtuh total, bukan bocor sedikit | Port aplikasi tidak pernah terbuka ke publik; ada test yang mengirim `Host` palsu langsung ke aplikasi dan harus ditolak (`BR-030`).                                                                                                                                                                                                                     |


### Pertanyaan terbuka

Bernomor karena dirujuk dari dokumen lain. Tiap satu jawabannya ada di luar tim teknis —
itu yang membuatnya pertanyaan, bukan tugas.

**#1 — Apakah pemilik rental mau membayar software?**
Satu-satunya yang bisa membatalkan seluruh premis. Jawabannya cuma ada di 5 design partner
(`S1-076`) dan harus keluar **sebelum minggu ke-15**, seperti baris kedua tabel risiko di
atas. Kalau tidak ada yang mau bayar Rp 99.000, yang salah premisnya, bukan fiturnya.

**#2 — Kapan akun merchant aggregator aktif?**
Pengajuannya **belum dimulai**, dan tidak ada yang bisa memulainya selain manusia yang
memegang dokumen PT. Ia ujung rantai yang mengunci dua bagian sekaligus:

```
langganan menyala  ←  jalur pembayaran menyala  ←  akun merchant aktif
   (BR-080–082)            (BR-061)                  ← #2, belum dimulai
```

Risikonya bukan teknis: **pemicunya di luar kendali tim**, jadi "sementara" bisa menjadi
permanen tanpa pernah ada yang memutuskannya. Ditulis di sini supaya ada yang menagihnya.

**#3 — Boleh tidak data identitas keluar dari Indonesia?**
Pertanyaan UU PDP, bukan pertanyaan teknis. Cloudflare R2 tidak punya region Indonesia, dan
fase 1 memakainya apa adanya (`BR-085`). Dua hal menunggu jawabannya: lokasi bucket, dan job
retensi yang sengaja dinonaktifkan (`BR-086`, `S1-059`) sehingga foto identitas menumpuk
tanpa batas waktu.

**Ditinjau ulang bersama pembentukan PT.** Murah dibalik: kalau jawabannya "harus di dalam
negeri", yang berubah cuma satu bucket — adapter-nya sama-sama S3-compatible.


---

## 13. Kompetitor &amp; paket harga

> **Umur data:** riset kompetitor di bawah berasal dari catatan repo ini sendiri
> (Juli 2026). Berkas aslinya, `boarding-house-app-recon/market.yaml`, **tidak ada di
> workspace ini** meski masih dirujuk BR-073 — jadi angkanya belum diverifikasi ulang.
> Cek lagi sebelum dipakai di halaman promosi.

### Paket


|                                             | **Coba**    | **Usaha**         | **Bisnis**         |
| ------------------------------------------- | ----------- | ----------------- | ------------------ |
| `subscriptions.plan`                        | `trial`     | `usaha`           | `bisnis`           |
| Harga                                       | **Gratis**  | **Rp 99.000**/bln | **Rp 249.000**/bln |
| `unit_quota`                                | 5           | **50**            | tanpa batas        |
| `user_quota`                                | 1           | **3**             | tanpa batas        |
| Booking, kalender, cek bentrok              | ✅           | ✅                 | ✅                  |
| Serah-terima + foto, deposit, denda         | ✅           | ✅                 | ✅                  |
| Halaman publik `<slug>.sewain.id`           | —           | ✅                 | ✅                  |
| Portal penyewa `<slug>.sewain.id/booking/<token>` | —           | ✅                 | ✅                  |
| Invoice + bukti transfer + AI scan          | ✅           | ✅                 | ✅                  |
| Laporan                                     | dasar       | lengkap + ekspor  | lengkap + ekspor   |
| Pengingat WhatsApp                          | —           | ✅                 | ✅                  |
| API eksternal untuk situs sendiri           | —           | —                 | ✅                  |
| Bayar online (gateway)                      | —           | ✅ *fase 2*        | ✅ *fase 2*         |
| Multi-cabang                                | —           | —                 | ✅ *fase 2*         |


### Kenapa angkanya begitu

1. **Flat, bukan per unit.** Ini serangan langsung ke model RoomKost. Juragan yang
 menambah mobil ke-12 tidak membayar lebih, dan itu kalimat penjualan yang bisa
 diucapkan dalam satu napas.
2. **Rp 99k duduk di antara dua kompetitor** — di atas Kamaru (Rp 49k, tapi mobile-only
 dan tidak punya web), jauh di bawah RoomKost (Rp 149k + per kamar). Cukup murah untuk
 dicoba tanpa rapat, cukup mahal untuk tidak dianggap mainan.
3. **Batas Usaha 50 unit menutup seluruh persona** (§3.1: 5–50 unit). Tebing harga
 sengaja diletakkan **di luar** target: juragan naik ke Bisnis karena bentuk usahanya
 berubah — cabang kedua, situs sendiri, tim di atas tiga — bukan karena beli satu motor
 lagi. Tebing yang jatuh di tengah persona adalah dosa yang sama dengan menagih per
 unit, cuma bentuknya tangga.
4. **Tier gratis dibatasi unit, bukan waktu**, dan **tidak punya host sendiri.** Yang
 hilang di situ bukan cuma katalog publik: portal penyewa hidup di host yang sama, jadi
 penyewa di tier gratis tidak punya tautan untuk melihat tagihan, jadwal, maupun foto
 kondisinya — semuanya balik ke operator lewat WhatsApp manual (BR-025). Itu harga yang
 dibayar tier gratis, dan sekaligus pemicu naik paket yang paling terbaca yang kita
 punya: "mau punya halaman sendiri?".
5. **Pengingat WhatsApp mulai dari Usaha, dan itu bukan sekadar gerbang jualan.**
 WhatsApp Cloud API menagih per percakapan (BR-073), jadi fitur ini punya biaya
 marginal nyata per tenant. Menggratiskannya berarti tier gratis punya biaya yang
 tumbuh seiring pemakaian.
6. **API eksternal jadi pembeda Bisnis**, dan ia sudah ada di fase 1 (BR-031) — bukan
 janji. Multi-cabang menyusul di fase 2.

### Yang belum bisa ditagih

**Harga sudah diputuskan, penagihannya belum bisa jalan.** BR-082 menetapkan tagihan
langganan lewat `invoices` + gateway yang sama dengan yang dipakai pemilik menagih
penyewanya — dan jalur gateway itu mati di fase 1 (BR-061). Jadi:

```
langganan menyala  ←  jalur pembayaran menyala  ←  akun merchant aktif
   (BR-080–082)            (BR-061)                  (§12 #2, belum dimulai)
```

Sampai rantai itu tersambung, setiap pemilik berjalan tanpa batas unit maupun pengguna.
Angka di tabel atas adalah **keputusan harga**, bukan penagihan yang sudah berdiri.