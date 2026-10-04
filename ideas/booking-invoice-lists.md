# Lengkapi daftar Booking & Tagihan

> **Status:** Disetujui & dibangun · **Tanggal:** 2026-10-03
> **Terkait:** BR-003, BR-033, BR-041, BR-055, BR-056, BR-057, BR-060 · S1-041, S1-047, S1-052, S1-063

## Problem Statement

Bagaimana juragan bisa menjawab *"booking ini sudah dibayar belum?"* dari daftar Booking, dan
*"tagihan ini punya siapa?"* dari daftar Tagihan, tanpa membuka detail satu per satu?

## Kenapa booking dan tagihan tetap dua hal

| | Booking (`bookings`) | Tagihan (`invoices` + `invoice_lines`) |
|---|---|---|
| Menjawab | unit mana, untuk siapa, kapan | berapa yang harus dibayar, sudah dibayar belum |
| Status | `draft → reserved → picked_up → returned → completed` (+ `cancelled`, `no_show`) | `unpaid → paid` / `overdue` / `cancelled` |
| Yang dijaga | tidak ada double-booking (`bookings_no_overlap`) | satu invoice dibayar penuh, satu kali (BR-060) |

Satu booking bisa punya beberapa tagihan, dan masing-masing terbit di waktu yang berbeda:

| Invoice | Terbit saat | Isi | Kode |
|---|---|---|---|
| `SWN-0042/1` | booking dibuat | sewa + deposit | `sewain-api/internal/booking/service.go:225` |
| `SWN-0042/2` | barang kembali | denda telat + kerusakan | `handover.go:233` |
| `SWN-0042/3` | deposit diselesaikan | selisih yang tidak tertutup deposit (`/2` dibatalkan, diserap deposit) | `deposit.go:171` |

Menggabungkan keduanya berarti harus mengubah invoice yang sudah lunas atau mengizinkan bayar
sebagian, dan keduanya dilarang BR-060. Status keduanya juga bergerak sendiri-sendiri.
Booking bisa `picked_up` sementara tagihannya lewat tenggat, kalau pemilik menerima bayar saat
ambil (BR-038). Booking bisa `completed` sementara tagihan selisihnya belum dibayar. Selain
itu, invoice langganan SaaS nanti tidak punya booking sama sekali (BR-082).

Masalahnya bukan pemisahannya, tapi **masing-masing daftar hanya punya separuh jawaban.**

## Daftar yang diubah

### 1. Daftar Booking (`/bookings`)

Saat ini kolomnya: Kode · Penyewa · Unit · Jadwal · Status (`sewain-web/src/app/(app)/bookings/page.tsx:233`).
Belum ada status bayar.

| Tambahan | Isi | Sumber |
|---|---|---|
| Kolom **Bayar** (antara Status dan Aksi) | badge **lunas** / **belum bayar** / **lewat tenggat**, atau `—`. Di bawahnya sisa tagihan, misalnya "Sisa Rp 50.000", kalau ada | field baru `booking.payment` |
| Badge yang sama di header `BookingDialog` | supaya status bayar terlihat sebelum menggulir ke `InvoiceSummary` | field yang sama |

Label dan warna memakai `INVOICE_STATUS` dari `sewain-web/src/components/invoice/status.ts`,
supaya kata yang dipakai daftar Booking sama persis dengan daftar Tagihan.

### 2. Daftar Tagihan (`/invoices`)

Saat ini kolomnya: Nomor · Status · Tenggat/lunas · Total (`sewain-web/src/app/(app)/invoices/page.tsx`).
Belum ada nama penyewa.

| Tambahan | Isi | Sumber |
|---|---|---|
| Kolom **Penyewa** (setelah Nomor) | nama, dengan nomor telepon kecil di bawahnya | field baru `invoice.customer` |
| Kolom **Untuk** | "Sewa + deposit", "Denda telat + kerusakan", "Selisih deposit" | **dihitung di FE dari `lines[].kind`**, yang sudah ada di respons (`OwnerInvoices` memanggil `attachLines`). Tidak perlu ubah kontrak |

Pemetaan `kind` ke label: `rent` → Sewa, `deposit` → Deposit, `late_fee` → Denda telat,
`damage` → Kerusakan. `discount` tidak disebut. Label unik digabung dengan " + ".

## Perubahan kontrak (`docs/openapi.yaml`)

### `Booking.payment` (baru, wajib, di `GET /bookings` dan `GET /bookings/{id}`)

```yaml
BookingPayment:
  type: object
  required: [status, outstanding]
  properties:
    status:
      type: string
      enum: [none, unpaid, overdue, paid]
    outstanding:
      type: integer
      format: int64
      description: SUM(lines) dari invoice berstatus unpaid/overdue. 0 kalau tidak ada.
```

**Dihitung server saat dibaca, tidak disimpan**, sama seperti `booking.overdue` (BR-041) dan
total invoice (BR-055). Satu definisi untuk semua layar, mengikuti semangat BR-033.

Aturannya, invoice `cancelled` diabaikan:

1. Booking `draft`, `cancelled`, atau `no_show` → `none`
2. Tidak ada invoice aktif → `none`
3. Ada yang `overdue` → `overdue`
4. Ada yang `unpaid` → `unpaid`
5. Selain itu → `paid`

Ditaruh di objek `payment`, bukan field datar `payment_status`. Alasannya, `Booking` sudah
punya `overdue: boolean` yang artinya *barang belum kembali*. Kalau ada dua "overdue" di
level yang sama, maknanya akan tertukar (lihat catatan di BR-056).

### `Invoice.customer` (baru, wajib, boleh `null`)

Memakai ulang skema `BookingCustomer` (`id, name, phone, is_blacklisted`). Nilainya `null`
hanya untuk invoice langganan (BR-082), yang belum ada di fase 1.

## Catatan implementasi (untuk nanti, bukan sekarang)

- **`db/queries/bookings.sql`** (`ListBookings`, `GetBooking`): tambah `LEFT JOIN LATERAL`
  yang meringkas invoice milik booking (`bool_or` per status, `sum` baris yang belum lunas).
  Index `invoices_owner_booking (owner_id, booking_id)` sudah ada.
- **`db/queries/invoices.sql`** (`GetInvoice`, `ListBookingInvoices`) dan
  **`db/queries/payments.sql`** (`ListOwnerInvoices`): ketiganya ditambah
  `LEFT JOIN customers c ON c.id = i.customer_id`. Ketiganya harus berubah bersamaan, karena
  `invoiceOf(sqlcgen.GetInvoiceRow(r))` di `internal/booking` mengonversi baris dari ketiga
  query itu dan mengandalkan bentuknya identik.
- **Tidak menyentuh `rent_paid` di kalender** (`bookings.sql:178`). Pertanyaannya berbeda:
  kalender bertanya "sewanya sudah dibayar?", daftar Booking bertanya "masih ada uang yang
  belum masuk?".
- **Tidak ada route baru**, jadi tidak ada kasus isolasi baru. `make generate` dan
  `npm run generate` wajib dijalankan.
- **Test:** unit test untuk aturan 1–5 sebagai fungsi murni. Integrasi: booking dengan `/1`
  lunas dan `/3` belum lunas → `unpaid` dengan `outstanding` = total `/3`; booking batal →
  `none`.

## Key Assumptions to Validate

- [ ] **Satu badge per booking sudah cukup**, walaupun ada beberapa invoice di baliknya.
  Uji: tanyakan ke juragan apakah "belum bayar · Sisa Rp 50.000" cukup, atau mereka perlu
  tahu tagihan yang mana.
- [ ] **Nama + telepon cukup untuk menagih dari daftar Tagihan.** Uji: lihat apakah juragan
  tetap membuka booking-nya sebelum menghubungi penyewa lewat WA.
- [ ] **Agregasi per baris tidak memperlambat daftar Booking.** Uji: tambah ke test perf
  booking yang sudah ada, dengan `ANALYZE` (pelajaran dari index range di bawah RLS).

## MVP Scope

**Masuk:** `Booking.payment`, `Invoice.customer`, kolom Bayar di daftar Booking, badge di
`BookingDialog`, kolom Penyewa dan Untuk di daftar Tagihan.

## Not Doing (and Why)

- **Menggabungkan tabel booking dan tagihan**: melanggar BR-060, dan invoice langganan tidak punya booking.
- **Menyimpan status bayar sebagai kolom di `bookings`**: status ini turunan, sama seperti `overdue` dan total invoice. Kolom tersimpan hanya menunggu jadi basi.
- **Filter "belum bayar" di daftar Booking**: daftar Tagihan sudah menjadi tempat menagih. Tambahkan kalau juragan ternyata tidak pernah membuka menu Tagihan.
- **Kolom tagihan terbuka di daftar Penyewa**: belum ada yang bertanya "penyewa mana yang punya utang". Tambahkan setelah ada yang memintanya.
- **Kartu "tagihan lewat tenggat" di dashboard**: itu milik S1-063.
- **Menghapus menu Tagihan**: hanya dari menu itu tagihan selisih milik booking `completed` masih terlihat.

## Open Questions

1. **Diputuskan (3 Okt): ikut batal.** `Cancel` (manual & otomatis) membatalkan invoice
   yang belum dibayar lewat `CancelBookingInvoices`; BR-057 dan S1-052 sudah direvisi.
   Teks asli: `Cancel` (`sewain-api/internal/booking/service.go:306`)
   tidak membatalkan invoice-nya. Selain itu, S1-052 sengaja menandai invoice `overdue` saat
   booking batal karena `payment_expired` (BR-057). Akibatnya daftar Tagihan akan memuat
   "lewat tenggat" yang tidak akan pernah ditagih, karena barangnya tidak pernah diserahkan.
   Rekomendasi: invoice yang belum dibayar ikut `cancelled` saat booking dibatalkan. Ini perlu
   revisi BR-057 dan S1-052, dan **sebaiknya diputuskan sebelum ide ini dibangun**.
2. **"lewat tenggat" belum bisa muncul sampai S1-052 selesai**, karena saat ini tidak ada kode
   yang mengubah invoice menjadi `overdue`. Sebelum itu, badge hanya bisa `unpaid` / `paid` /
   `none`.
3. **Diputuskan (3 Okt): semua peran.** Sisa tagihan adalah alat menagih, bukan angka
   pemasukan BR-003; operator memang sudah punya `invoices:read`. Teks asli: Operator sudah bisa membaca invoice lewat
   booking (`invoices:read`), jadi seharusnya boleh. Tapi perlu dipastikan ini bukan "angka
   pemasukan" yang dilarang BR-003.
