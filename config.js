/* Supabase settings for the shared message wall and leaderboard.
 *
 * Both values are PUBLIC by design and safe to commit:
 *   url            - Project URL, e.g. https://abcdefghijklmnop.supabase.co
 *   publishableKey - the "Publishable key" (sb_publishable_...) from Project Settings -> API Keys,
 *                    or the legacy "anon public" key if your project only has that.
 * They are only safe because supabase/schema.sql limits the public role to reading and adding rows.
 *
 * NEVER put the secret key (sb_secret_...), the legacy service_role key, or the database
 * password here. Anything in this file is visible to every visitor.
 */
window.SUPABASE_CONFIG = {
  url: "https://opxktqhuywumwximmohe.supabase.co",
  publishableKey: "sb_publishable_kBjvCErC4AWE1dGBYOv6jg_gG0LPpZT"
};
