-- =====================================================================
--  PREVESA · Inspección de Mixers — esquema para Supabase
--  Pegar completo en: Supabase → SQL Editor → New query → Run
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------- Tablas ----------
create table if not exists public.vehiculos (
  id         uuid primary key default gen_random_uuid(),
  placa      text not null unique,
  interno    text,
  conductor  text,
  activo     boolean not null default true,
  creado     timestamptz not null default now()
);

create table if not exists public.inspecciones (
  id           uuid primary key default gen_random_uuid(),
  vehiculo_id  uuid not null references public.vehiculos(id) on delete restrict,
  placa        text not null,
  interno      text,
  seccion      text not null check (seccion in ('extintor','botiquin','cintas','kit')),
  fecha        date not null,
  km           text,
  extra        jsonb not null default '{}'::jsonb,
  items        jsonb not null,            -- [{t: texto, r: 'C'|'NC'|'NA', obs: texto}]
  obs          text,
  nc           int  not null default 0,   -- número de ítems no conformes
  inspector    text not null,
  cedula       text not null,
  cargo        text,
  firma        text not null,             -- imagen PNG en base64 (data URL)
  creado       timestamptz not null default now()
);
create index if not exists inspecciones_veh_sec_fecha on public.inspecciones (vehiculo_id, seccion, fecha);
create index if not exists inspecciones_creado on public.inspecciones (creado desc);

create table if not exists public.seguimiento (
  inspeccion_id uuid primary key references public.inspecciones(id) on delete cascade,
  accion        text,
  responsable   text,
  compromiso    date,
  estado        text not null default 'abierto' check (estado in ('abierto','proceso','cerrado')),
  cierre        date,
  actualizado   timestamptz not null default now()
);

-- Usuarios con acceso al módulo de administración
create table if not exists public.admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email   text
);

-- Configuración (PIN de inspectores)
create table if not exists public.config (
  clave text primary key,
  valor text not null
);
insert into public.config (clave, valor) values ('pin_inspectores', '2026')
on conflict (clave) do nothing;

-- ---------- Funciones auxiliares ----------
create or replace function public.es_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.admins where user_id = auth.uid());
$$;

create or replace function public._pin_ok(p_pin text)
returns void language plpgsql stable security definer set search_path = public as $$
begin
  if p_pin is null or p_pin <> (select valor from public.config where clave = 'pin_inspectores') then
    raise exception 'pin_invalido' using errcode = '28000';
  end if;
end $$;

-- ---------- Seguridad (RLS) ----------
alter table public.vehiculos    enable row level security;
alter table public.inspecciones enable row level security;
alter table public.seguimiento  enable row level security;
alter table public.admins       enable row level security;
alter table public.config       enable row level security;

drop policy if exists admin_all on public.vehiculos;
create policy admin_all on public.vehiculos    for all to authenticated using (public.es_admin()) with check (public.es_admin());
drop policy if exists admin_all on public.inspecciones;
create policy admin_all on public.inspecciones for all to authenticated using (public.es_admin()) with check (public.es_admin());
drop policy if exists admin_all on public.seguimiento;
create policy admin_all on public.seguimiento  for all to authenticated using (public.es_admin()) with check (public.es_admin());
drop policy if exists admin_all on public.config;
create policy admin_all on public.config       for all to authenticated using (public.es_admin()) with check (public.es_admin());
drop policy if exists admin_self on public.admins;
create policy admin_self on public.admins      for select to authenticated using (user_id = auth.uid());

-- Los inspectores (sin cuenta) NO tienen acceso directo a ninguna tabla.
-- Solo pueden usar estas tres funciones, y todas exigen el PIN.

-- 1) Vehículos activos
create or replace function public.inspector_vehiculos(p_pin text)
returns table (id uuid, placa text, interno text, conductor text)
language plpgsql stable security definer set search_path = public as $$
begin
  perform public._pin_ok(p_pin);
  return query select v.id, v.placa, v.interno, v.conductor
               from public.vehiculos v where v.activo order by v.placa;
end $$;

-- 2) Estado del mes por sección para un vehículo
create or replace function public.inspector_estado(p_pin text, p_vehiculo uuid, p_mes text)
returns table (seccion text, fecha date, nc int, cerrado boolean)
language plpgsql stable security definer set search_path = public as $$
declare d0 date := to_date(p_mes || '-01', 'YYYY-MM-DD');
begin
  perform public._pin_ok(p_pin);
  return query
    select distinct on (i.seccion) i.seccion, i.fecha, i.nc, coalesce(s.estado = 'cerrado', false)
    from public.inspecciones i
    left join public.seguimiento s on s.inspeccion_id = i.id
    where i.vehiculo_id = p_vehiculo and i.fecha >= d0 and i.fecha < (d0 + interval '1 month')
    order by i.seccion, i.creado desc;
end $$;

-- 3) Registrar una inspección firmada
create or replace function public.registrar_inspeccion(p_pin text, p jsonb)
returns uuid language plpgsql volatile security definer set search_path = public as $$
declare v public.vehiculos; nuevo uuid; n_nc int;
begin
  perform public._pin_ok(p_pin);
  select * into v from public.vehiculos where id = (p->>'vehiculo_id')::uuid and activo;
  if not found then raise exception 'vehiculo_invalido'; end if;
  if coalesce(p->>'inspector','') = '' or coalesce(p->>'cedula','') = '' then raise exception 'faltan_datos'; end if;
  if jsonb_typeof(p->'items') <> 'array' then raise exception 'items_invalidos'; end if;
  if left(coalesce(p->>'firma',''), 22) <> 'data:image/png;base64,' or length(p->>'firma') > 400000 then
    raise exception 'firma_invalida';
  end if;
  select count(*) into n_nc from jsonb_array_elements(p->'items') e where e->>'r' = 'NC';
  insert into public.inspecciones (vehiculo_id, placa, interno, seccion, fecha, km, extra, items, obs, nc,
                                   inspector, cedula, cargo, firma)
  values (v.id, v.placa, v.interno, p->>'seccion', (p->>'fecha')::date, p->>'km',
          coalesce(p->'extra','{}'::jsonb), p->'items', p->>'obs', n_nc,
          p->>'inspector', p->>'cedula', p->>'cargo', p->>'firma')
  returning id into nuevo;
  return nuevo;
end $$;

revoke all on function public._pin_ok(text) from public, anon, authenticated;
grant execute on function public.inspector_vehiculos(text)             to anon, authenticated;
grant execute on function public.inspector_estado(text, uuid, text)    to anon, authenticated;
grant execute on function public.registrar_inspeccion(text, jsonb)     to anon, authenticated;
grant execute on function public.es_admin()                            to authenticated;

-- ---------- Tiempo real para el panel de administración ----------
do $$ begin
  alter publication supabase_realtime add table public.inspecciones, public.seguimiento, public.vehiculos;
exception when others then null; end $$;

-- =====================================================================
--  DESPUÉS de crear tu usuario administrador en Authentication → Users,
--  ejecuta esta línea cambiando el correo:
--
--  insert into public.admins (user_id, email)
--  select id, email from auth.users where email = 'TU_CORREO@empresa.com';
-- =====================================================================
