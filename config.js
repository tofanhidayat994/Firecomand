// Isi dua nilai ini dari Supabase: Project Settings > API.
// Kunci "anon / publishable" memang boleh tampil di sini (keamanan dijaga oleh aturan RLS di database).
// JANGAN PERNAH menaruh kunci "service_role" / "secret" di file ini.
window.FC_CONFIG = {
  SUPABASE_URL: 'ISI_URL_PROYEK_SUPABASE',        // contoh: https://abcdxyz.supabase.co
  SUPABASE_ANON_KEY: 'ISI_ANON_PUBLIC_KEY'        // contoh: eyJhbGciOi... atau sb_publishable_...
};
