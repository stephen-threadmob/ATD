-- Minimal assertion harness so tests run with plain psql (no pgTAP needed).
create schema if not exists t;

create table if not exists t.results (
  id bigint generated always as identity primary key,
  name text not null,
  passed boolean not null,
  detail text,
  at timestamptz not null default now()
);

create or replace function t.ok(p_name text, p_cond boolean, p_detail text default null)
returns void language plpgsql as $$
begin
  insert into t.results(name, passed, detail) values (p_name, coalesce(p_cond,false), p_detail);
  if not coalesce(p_cond,false) then
    raise warning 'FAIL  %  (%)', p_name, coalesce(p_detail,'');
  else
    raise notice 'ok    %', p_name;
  end if;
end $$;

create or replace function t.eq(p_name text, p_a anyelement, p_b anyelement)
returns void language plpgsql as $$
begin
  perform t.ok(p_name, p_a is not distinct from p_b,
               format('expected %s, got %s', p_b, p_a));
end $$;

-- Assert that a statement raises, optionally with a specific SQLSTATE.
create or replace function t.raises(p_name text, p_sql text, p_sqlstate text default null)
returns void language plpgsql as $$
declare v_state text;
begin
  begin
    execute p_sql;
    perform t.ok(p_name, false, 'expected an exception, none raised');
    return;
  exception when others then
    v_state := sqlstate;
  end;
  perform t.ok(p_name, p_sqlstate is null or v_state = p_sqlstate,
               format('sqlstate %s (wanted %s)', v_state, coalesce(p_sqlstate,'any')));
end $$;

create or replace function t.summary() returns table(total bigint, passed bigint, failed bigint)
language sql as $$
  select count(*), count(*) filter (where passed), count(*) filter (where not passed) from t.results
$$;
