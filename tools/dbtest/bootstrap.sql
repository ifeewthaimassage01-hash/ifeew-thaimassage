-- จำลองส่วนของ Supabase ที่ migration ใช้ (เฉพาะสำหรับตรวจใน PGlite)
create role anon nologin;
create role authenticated nologin;
create role service_role nologin bypassrls;
grant anon, authenticated, service_role to postgres;

create schema extensions;
grant usage on schema extensions to anon, authenticated, service_role;
create schema auth;
grant usage on schema auth to anon, authenticated, service_role;
grant usage on schema public to anon, authenticated, service_role;

create table auth.users (
  instance_id uuid, id uuid primary key, aud text, role text, email text,
  encrypted_password text, email_confirmed_at timestamptz,
  raw_app_meta_data jsonb, raw_user_meta_data jsonb,
  created_at timestamptz, updated_at timestamptz,
  confirmation_token text, recovery_token text, email_change_token_new text, email_change text
);
create table auth.identities (
  id uuid primary key, user_id uuid references auth.users(id), provider_id text, provider text,
  identity_data jsonb, last_sign_in_at timestamptz, created_at timestamptz, updated_at timestamptz
);

create function auth.uid() returns uuid language sql stable as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  )::uuid
$$;
create function auth.jwt() returns jsonb language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb
$$;
grant execute on function auth.uid(), auth.jwt() to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- pgTAP shim (เฉพาะ subset ที่ test ใช้)
-- ---------------------------------------------------------------------------
create table extensions.__tap (n serial, ok boolean, descr text, diag text);
grant all on extensions.__tap to public;
grant all on sequence extensions.__tap_n_seq to public;

create function extensions.plan(int) returns text language sql as $$ select '1..' || $1 $$;
create function extensions.ok(boolean, text) returns text language plpgsql as $$
begin
  insert into extensions.__tap(ok, descr) values (coalesce($1, false), $2);
  return case when coalesce($1,false) then 'ok' else 'not ok' end || ' - ' || $2;
end $$;
create function extensions.is(anyelement, anyelement, text) returns text language plpgsql as $$
begin
  insert into extensions.__tap(ok, descr, diag)
  values ($1 is not distinct from $2, $3, format('have: %s want: %s', $1, $2));
  return $3;
end $$;
create function extensions.throws_ok(text, char(5), text, text) returns text language plpgsql as $$
begin
  begin
    execute $1;
    insert into extensions.__tap(ok, descr, diag) values (false, $4, 'no error raised');
  exception when others then
    insert into extensions.__tap(ok, descr, diag)
    values (($2 is null or sqlstate = $2) and ($3 is null or sqlerrm = $3), $4,
            format('got %s: %s', sqlstate, sqlerrm));
  end;
  return $4;
end $$;
create function extensions.lives_ok(text, text) returns text language plpgsql as $$
begin
  begin
    execute $1;
    insert into extensions.__tap(ok, descr) values (true, $2);
  exception when others then
    insert into extensions.__tap(ok, descr, diag) values (false, $2, format('%s: %s', sqlstate, sqlerrm));
  end;
  return $2;
end $$;
create function extensions.finish() returns setof text language sql as $$ select 'done' $$;
grant execute on all functions in schema extensions to public;
alter role postgres set search_path = "$user", public, extensions;

-- storage stub
create schema storage;
grant usage on schema storage to anon, authenticated, service_role;
create table storage.buckets (id text primary key, name text, public boolean, file_size_limit bigint, allowed_mime_types text[]);
create table storage.objects (id uuid primary key default gen_random_uuid(), bucket_id text references storage.buckets(id), name text, owner uuid);
alter table storage.objects enable row level security;
grant all on storage.objects to anon, authenticated, service_role;
