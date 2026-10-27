-- =====================================================================
-- FIRE COMMAND - skema database Supabase
-- Jalankan SEKALI di Supabase: SQL Editor > New query > tempel > Run.
-- Aman dijalankan ulang (memakai IF NOT EXISTS / OR REPLACE / DROP POLICY IF EXISTS).
-- =====================================================================

-- ---------- 1. Tabel ----------
create table if not exists public.profil (
  id               uuid primary key references auth.users(id) on delete cascade,
  email            text not null default '',
  nama             text not null default '',
  regu             text not null default '1',
  shift            text not null default 'Pagi (08:00 - 16:00)',
  area             text not null default 'Blok A1 - A3',
  foto             text,
  role             text not null default 'personel' check (role in ('personel','komandan','admin')),
  aktif            boolean not null default false,
  profil_lengkap   boolean not null default false,
  dibuat_pada      timestamptz not null default now(),
  diubah_pada      timestamptz not null default now()
);

-- Daftar email yang disetujui otomatis saat pertama kali login Google.
create table if not exists public.undangan (
  email text primary key check (email = lower(email)),
  role  text not null default 'personel' check (role in ('personel','komandan','admin'))
);

create table if not exists public.laporan (
  id           text primary key check (char_length(id) between 3 and 64),
  tipe         text not null check (tipe in ('patroli','menara','hujan','api','alat','lain')),
  waktu        timestamptz not null,
  penulis_id   uuid not null default auth.uid() references auth.users(id),
  penulis_nama text not null default '',
  data         jsonb not null default '{}'::jsonb check (pg_column_size(data) < 20000),
  foto         text[] not null default '{}' check (coalesce(array_length(foto,1),0) <= 3),
  pembaruan    jsonb not null default '[]'::jsonb check (pg_column_size(pembaruan) < 100000),
  regu         jsonb not null default '[]'::jsonb,
  alat         jsonb not null default '[]'::jsonb,
  dibuat_pada  timestamptz not null default now(),
  diubah_pada  timestamptz not null default clock_timestamp()
);
create index if not exists laporan_diubah_idx on public.laporan (diubah_pada);
create index if not exists laporan_tipe_waktu_idx on public.laporan (tipe, waktu desc);

create table if not exists public.level_kesiagaan (
  id        bigint generated always as identity primary key,
  level     text not null check (level in ('normal','s3','s2','s1')),
  dari      text,
  oleh_id   uuid not null default auth.uid() references auth.users(id),
  oleh_nama text not null default '',
  catatan   text not null default '' check (char_length(catatan) <= 500),
  waktu     timestamptz not null default now()
);

-- ---------- 2. Fungsi bantu ----------
-- SECURITY DEFINER agar bisa membaca tabel profil tanpa memicu rekursi RLS.
create or replace function public.is_aktif() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.profil where id = (select auth.uid()) and aktif)
$$;

create or replace function public.my_role() returns text
language sql stable security definer set search_path = '' as $$
  select role from public.profil where id = (select auth.uid()) and aktif
$$;

-- Profil dibuat otomatis saat akun Google pertama kali login.
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
declare inv public.undangan%rowtype; em text := lower(coalesce(new.email,''));
begin
  select * into inv from public.undangan where email = em;
  insert into public.profil (id, email, nama, aktif, role)
  values (new.id, em,
          coalesce(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name', split_part(em,'@',1)),
          found, coalesce(inv.role,'personel'))
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- Anggota biasa tidak boleh mengubah aktif/role/email sendiri.
create or replace function public.jaga_profil() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  new.diubah_pada := now();
  new.id := old.id;
  -- auth.uid() null = dijalankan dari SQL Editor / service role: diizinkan.
  if (select auth.uid()) is not null and coalesce(public.my_role(),'') <> 'admin' then
    new.aktif := old.aktif; new.role := old.role; new.email := old.email;
  end if;
  return new;
end $$;
drop trigger if exists jaga_profil_trg on public.profil;
create trigger jaga_profil_trg before update on public.profil
  for each row execute function public.jaga_profil();

-- Waktu ubah diisi server (bukan jam HP) dan kolom kunci tidak bisa diganti.
create or replace function public.jaga_laporan() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'UPDATE' then
    new.id := old.id; new.tipe := old.tipe; new.penulis_id := old.penulis_id;
    new.penulis_nama := old.penulis_nama; new.dibuat_pada := old.dibuat_pada;
  else
    -- nama penulis diambil dari profil, bukan dari kiriman HP (tidak bisa dipalsukan)
    new.penulis_nama := coalesce((select nama from public.profil where id = new.penulis_id), '');
    new.dibuat_pada := now();
  end if;
  new.diubah_pada := clock_timestamp();
  return new;
end $$;
drop trigger if exists jaga_laporan_trg on public.laporan;
create trigger jaga_laporan_trg before insert or update on public.laporan
  for each row execute function public.jaga_laporan();

create or replace function public.jaga_level() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  new.oleh_nama := coalesce((select nama from public.profil where id = new.oleh_id), '');
  new.waktu := now();
  return new;
end $$;
drop trigger if exists jaga_level_trg on public.level_kesiagaan;
create trigger jaga_level_trg before insert on public.level_kesiagaan
  for each row execute function public.jaga_level();

-- ---------- 3. Row Level Security ----------
alter table public.profil          enable row level security;
alter table public.undangan        enable row level security;
alter table public.laporan         enable row level security;
alter table public.level_kesiagaan enable row level security;

-- profil
drop policy if exists profil_baca on public.profil;
create policy profil_baca on public.profil for select to authenticated
  using (id = (select auth.uid()) or (select public.my_role()) = 'admin' or ((select public.is_aktif()) and aktif));
drop policy if exists profil_ubah on public.profil;
create policy profil_ubah on public.profil for update to authenticated
  using (id = (select auth.uid()) or (select public.my_role()) = 'admin')
  with check (id = (select auth.uid()) or (select public.my_role()) = 'admin');

-- undangan: hanya admin
drop policy if exists undangan_admin on public.undangan;
create policy undangan_admin on public.undangan for all to authenticated
  using ((select public.my_role()) = 'admin') with check ((select public.my_role()) = 'admin');

-- laporan: semua anggota AKTIF membaca semuanya; menulis hanya atas nama sendiri.
-- Laporan pemadaman (tipe 'api') boleh diperbarui oleh anggota aktif mana pun
-- (supaya rekan bisa menambah perkembangan). Tipe lain hanya oleh penulisnya.
drop policy if exists laporan_baca on public.laporan;
create policy laporan_baca on public.laporan for select to authenticated
  using ((select public.is_aktif()));
drop policy if exists laporan_tambah on public.laporan;
create policy laporan_tambah on public.laporan for insert to authenticated
  with check ((select public.is_aktif()) and penulis_id = (select auth.uid()));
drop policy if exists laporan_ubah on public.laporan;
create policy laporan_ubah on public.laporan for update to authenticated
  using ((select public.is_aktif()) and (penulis_id = (select auth.uid()) or tipe = 'api'))
  with check ((select public.is_aktif()) and (penulis_id = (select auth.uid()) or tipe = 'api'));
drop policy if exists laporan_hapus on public.laporan;
create policy laporan_hapus on public.laporan for delete to authenticated
  using ((select public.my_role()) = 'admin');

-- level kesiagaan: semua anggota aktif membaca; hanya komandan/admin yang mengubah.
-- (Ingin semua anggota boleh mengubah? ganti 'in (...)' di bawah menjadi: (select public.is_aktif()) )
drop policy if exists level_baca on public.level_kesiagaan;
create policy level_baca on public.level_kesiagaan for select to authenticated
  using ((select public.is_aktif()));
drop policy if exists level_tambah on public.level_kesiagaan;
create policy level_tambah on public.level_kesiagaan for insert to authenticated
  with check ((select public.my_role()) in ('komandan','admin') and oleh_id = (select auth.uid()));

-- Anonim (belum login) tidak boleh menyentuh apa pun.
revoke all on public.profil, public.undangan, public.laporan, public.level_kesiagaan from anon;
grant select, update on public.profil to authenticated;
grant select, insert, update, delete on public.undangan to authenticated;
grant select, insert, update, delete on public.laporan to authenticated;
grant select, insert on public.level_kesiagaan to authenticated;
grant usage on sequence public.level_kesiagaan_id_seq to authenticated;

-- ---------- 4. Penyimpanan foto (privat) ----------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('foto', 'foto', false, 2097152, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public = false, file_size_limit = 2097152,
  allowed_mime_types = array['image/jpeg','image/png','image/webp'];

-- Foto disimpan di folder bernama ID penggunanya: <uid>/<id-laporan>/<n>.jpg
drop policy if exists foto_baca on storage.objects;
create policy foto_baca on storage.objects for select to authenticated
  using (bucket_id = 'foto' and (select public.is_aktif()));
drop policy if exists foto_unggah on storage.objects;
create policy foto_unggah on storage.objects for insert to authenticated
  with check (bucket_id = 'foto' and (select public.is_aktif()) and (storage.foldername(name))[1] = (select auth.uid())::text);
drop policy if exists foto_timpa on storage.objects;
create policy foto_timpa on storage.objects for update to authenticated
  using (bucket_id = 'foto' and (select public.is_aktif()) and (storage.foldername(name))[1] = (select auth.uid())::text);

-- ---------- 5. Realtime (laporan & level baru langsung muncul di HP lain) ----------
do $$ begin
  begin alter publication supabase_realtime add table public.laporan; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.level_kesiagaan; exception when duplicate_object then null; end;
end $$;
