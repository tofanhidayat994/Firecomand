# Fire Command (PWA) — login Google, data bersama, bisa offline

Semua personel yang **sudah disetujui admin** melihat laporan satu sama lain.
Tanpa sinyal, laporan disimpan di HP lalu dikirim otomatis saat online.

Kamu perlu 3 akun gratis: **Supabase** (database), **Google Cloud** (tombol login Google), dan **hosting statis** (Netlify / Cloudflare Pages / GitHub Pages). Total sekitar 45–60 menit untuk pertama kali.

> Catatan penting: paket Supabase **Free** menghentikan (pause) proyek yang tidak dipakai 1 minggu. Untuk operasional lapangan, pakai **Pro** (±US$25/bulan, tidak pernah di-pause, ada backup harian). Cek harga terbaru di supabase.com/pricing.

---

## 1. Buat proyek Supabase
1. Daftar di https://supabase.com → **New project**. Pilih region terdekat (Singapore). Simpan password database.
2. Buka **SQL Editor → New query**, tempel seluruh isi `supabase/schema.sql`, klik **Run**. Hasilnya harus "Success". (Aman dijalankan ulang.)
3. Buka **Project Settings → API**. Catat:
   - **Project URL** (`https://xxxx.supabase.co`)
   - kunci **anon / publishable** (BUKAN `service_role` / `secret`).

## 2. Daftarkan admin pertama (SEBELUM login pertama)
Di **SQL Editor** jalankan (ganti emailnya dengan email Google admin):
```sql
insert into public.undangan (email, role) values ('emailadmin@gmail.com', 'admin');
```
Email yang ada di tabel `undangan` otomatis **aktif** saat pertama kali login Google. Email lain masuk status **Menunggu persetujuan**.
Sudah terlanjur login? Jalankan:
```sql
update public.profil set aktif = true, role = 'admin' where email = 'emailadmin@gmail.com';
```

## 3. Aktifkan login Google
1. https://console.cloud.google.com → buat project → **APIs & Services → OAuth consent screen** (User type: External, isi nama aplikasi & email) → Publish app.
2. **Credentials → Create credentials → OAuth client ID → Web application**.
   - **Authorized redirect URIs**: `https://<PROJECT-REF>.supabase.co/auth/v1/callback`
     (alamat persisnya tertera di Supabase: **Authentication → Providers → Google**).
3. Salin **Client ID** dan **Client secret**.
4. Di Supabase: **Authentication → Providers → Google** → Enable → tempel Client ID & Secret → Save.

## 4. Pasang di hosting
1. Isi `config.js` dengan Project URL dan anon key dari langkah 1.
2. Unggah **seluruh isi folder ini** ke hosting statis:
   - **Netlify**: https://app.netlify.com/drop → seret folder ini.
   - **Cloudflare Pages / GitHub Pages**: unggah isi folder apa adanya (tanpa build).
   Wajib **HTTPS** (semua hosting di atas sudah HTTPS).
3. Catat alamat aplikasimu, mis. `https://damkar-lahan.netlify.app/`.

## 5. Beri tahu Supabase alamat aplikasimu
**Authentication → URL Configuration**:
- **Site URL**: alamat aplikasi dari langkah 4.
- **Redirect URLs**: tambahkan alamat yang sama (dengan `/` di akhir), mis. `https://damkar-lahan.netlify.app/`.

## 6. Coba
1. Buka alamat aplikasi di HP → **Masuk dengan Google** (pakai email admin).
2. **Profil → Kelola Anggota** (khusus admin):
   - tambahkan email personel di kotak **Setujui email lebih dulu**, atau
   - tunggu personel login lalu ketuk **Setujui** pada namanya. Di sini admin juga mengatur peran: **Personel / Komandan / Admin**.
3. Di Android Chrome: menu ⋮ → **Install app / Tambahkan ke layar utama**. Di iPhone Safari: Bagikan → **Add to Home Screen**.
4. **Buka sekali dalam keadaan online** agar aplikasi tersimpan untuk offline.

---

## Siapa boleh apa
| | Personel | Komandan | Admin |
|---|---|---|---|
| Lihat semua laporan & foto | ✔ | ✔ | ✔ |
| Buat laporan sendiri | ✔ | ✔ | ✔ |
| Tambah pembaruan pada laporan **pemadaman** milik rekan | ✔ | ✔ | ✔ |
| Ubah laporan non-pemadaman milik orang lain | ✘ | ✘ | ✘ |
| Ubah Level Kesiagaan | ✘ | ✔ | ✔ |
| Setujui / nonaktifkan anggota, ubah peran | ✘ | ✘ | ✔ |

Ingin semua anggota boleh mengubah level? Di `schema.sql`, pada policy `level_tambah`, ganti `(select public.my_role()) in ('komandan','admin')` menjadi `(select public.is_aktif())`, lalu jalankan ulang file tersebut dan ubah kondisi `canLevel()` di `index.html`.

## Cara kerja offline
- Laporan baru masuk antrean di HP (IndexedDB) dan dikirim otomatis saat online. Lihat menu **Sinkron**.
- Data rekan yang terakhir diunduh tetap bisa dibaca offline. Foto **rekan** butuh online untuk tampil (foto sendiri tetap tampil).
- Pembaruan yang dibuat dua orang pada kebakaran yang sama digabung otomatis (riwayat, personel, alat; status memakai pembaruan paling baru).
- Perubahan **Level Kesiagaan** dan **Kelola Anggota** wajib online.
- Login pertama wajib online. Sesudahnya aplikasi bisa dibuka offline selama sesi belum dihapus.

## Batasan yang perlu kamu tahu
- **Tidak ada notifikasi push** saat aplikasi tertutup. Notifikasi muncul di dalam aplikasi ketika dibuka / realtime aktif.
- Data diunduh untuk **400 hari terakhir** per perangkat. Unduh Excel hanya mencakup data yang sudah diunduh.
- Foto: maks. 3 per laporan, dikecilkan ±480 px. Disimpan di bucket **privat** dan hanya terbaca anggota aktif.
- Citra satelit peta tersimpan **per perangkat** (tiap HP memasangnya sendiri).
- Akun Google mana pun bisa mencoba login, tetapi tanpa persetujuan admin ia **tidak bisa membaca apa pun** (dijaga aturan RLS di database, bukan oleh aplikasi).
- Menonaktifkan anggota langsung memutus akses ke server. Data yang **sudah terunduh** di HP-nya tetap ada sampai ia keluar/menghapus data aplikasi.
- Admin dapat menghapus laporan lewat Supabase **Table Editor** (aplikasi tidak menyediakan tombol hapus untuk data yang sudah terkirim).

## Memperbarui aplikasi
Unggah ulang file ke hosting. Jika `index.html` atau file lain berubah, naikkan `VERSI` di `sw.js` (mis. `fc-v2`) agar HP memuat versi baru.

## Isi paket
```
index.html            aplikasi
config.js             URL & anon key Supabase  <- isi ini
manifest.webmanifest  data pemasangan PWA
sw.js                 service worker (offline)
icons/                ikon
vendor/               supabase-js, ExcelJS, font (tanpa CDN, jalan offline)
supabase/schema.sql   tabel, aturan keamanan (RLS), penyimpanan foto, realtime
```
