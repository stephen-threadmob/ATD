-- =============================================================================
-- 0011 Permission catalogue, role bundles, auth helpers, row-level security
-- -----------------------------------------------------------------------------
-- RLS is the LAST line of defence, not the only one: the app always goes
-- through server-side authorisation too. But because Supabase exposes PostgREST
-- directly, every customer-reachable table gets a policy so a leaked anon key
-- cannot enumerate other families' children.
-- =============================================================================
set search_path = atd, public;

-- ---------------------------------------------------------------------------
-- Permission catalogue
-- ---------------------------------------------------------------------------
insert into atd.permissions (key, category, description) values
  ('booking.read',              'booking',  'View bookings'),
  ('booking.create',            'booking',  'Create bookings'),
  ('booking.update',            'booking',  'Move, resize, or edit bookings'),
  ('booking.cancel',            'booking',  'Cancel bookings'),
  ('booking.cancel_paid',       'booking',  'Cancel bookings that have payments'),
  ('booking.override_conflict', 'booking',  'Override a scheduling conflict'),
  ('booking.reassign_resource', 'booking',  'Reassign cages, coaches or equipment'),
  ('booking.walk_in',           'booking',  'Create walk-in bookings'),
  ('booking.extend',            'booking',  'Extend an in-progress rental'),
  ('customer.read',             'customer', 'View customer accounts'),
  ('customer.write',            'customer', 'Edit customer accounts'),
  ('customer.delete',           'customer', 'Delete or anonymise customer data'),
  ('customer.export',           'customer', 'Export customer data'),
  ('participant.read_medical',  'customer', 'View allergies and medical notes'),
  ('payment.collect',           'money',    'Collect payments'),
  ('payment.refund',            'money',    'Issue refunds'),
  ('payment.discount',          'money',    'Apply discounts'),
  ('payment.price_override',    'money',    'Override prices'),
  ('payment.credit',            'money',    'Grant account credit'),
  ('payment.comp',              'money',    'Create complimentary bookings'),
  ('finance.reports',           'money',    'View financial reports'),
  ('package.sell',              'money',    'Sell packages and memberships'),
  ('package.adjust',            'money',    'Adjust package credits'),
  ('waiver.send',               'ops',      'Send and resend waivers'),
  ('waiver.override',           'ops',      'Allow participation without a waiver'),
  ('checkin.manage',            'ops',      'Check customers in and out'),
  ('waitlist.manage',           'ops',      'Manage waitlists and offers'),
  ('schedule.block',            'ops',      'Create maintenance blocks and closures'),
  ('resource.manage',           'config',   'Create and edit resources'),
  ('service.manage',            'config',   'Create and edit services and pricing'),
  ('program.manage',            'config',   'Create and edit programs, camps, events'),
  ('coach.manage',              'config',   'Manage coach profiles and qualifications'),
  ('coach.availability_self',   'config',   'Edit own availability'),
  ('coach.approve_time_off',    'config',   'Approve coach time off'),
  ('comp.read_self',            'money',    'View own compensation'),
  ('comp.manage',               'money',    'Manage compensation rules and payroll'),
  ('staff.manage',              'admin',    'Manage staff and permissions'),
  ('location.manage',           'admin',    'Manage locations and operating hours'),
  ('settings.manage',           'admin',    'Manage system settings and integrations'),
  ('audit.read',                'admin',    'View audit logs'),
  ('report.operational',        'admin',    'View operational reports')
on conflict (key) do nothing;

insert into atd.roles (key, name, description) values
  ('super_admin',    'Super Administrator', 'Full control across all locations'),
  ('location_admin', 'Location Administrator', 'Full control of an assigned location'),
  ('front_desk',     'Front Desk', 'Day-to-day counter operations'),
  ('coach',          'Coach / Instructor', 'Teaching, availability, own earnings'),
  ('customer',       'Customer', 'Household self-service')
on conflict (key) do nothing;

-- super_admin: everything
insert into atd.role_permissions (role_id, permission_key)
select r.id, p.key from atd.roles r cross join atd.permissions p
 where r.key = 'super_admin'
on conflict do nothing;

-- location_admin: everything except cross-location administration
insert into atd.role_permissions (role_id, permission_key)
select r.id, p.key from atd.roles r cross join atd.permissions p
 where r.key = 'location_admin'
   and p.key not in ('location.manage','settings.manage','customer.delete')
on conflict do nothing;

insert into atd.role_permissions (role_id, permission_key)
select r.id, k from atd.roles r,
  unnest(array[
    'booking.read','booking.create','booking.update','booking.cancel','booking.walk_in',
    'booking.reassign_resource','booking.extend',
    'customer.read','customer.write','payment.collect','payment.discount','package.sell',
    'waiver.send','checkin.manage','waitlist.manage','report.operational'
  ]) as k
 where r.key = 'front_desk'
on conflict do nothing;

insert into atd.role_permissions (role_id, permission_key)
select r.id, k from atd.roles r,
  unnest(array[
    'booking.read','customer.read','checkin.manage',
    'coach.availability_self','comp.read_self'
  ]) as k
 where r.key = 'coach'
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- Auth helpers. app_user_id() reads the Supabase JWT subject; service-role
-- connections bypass RLS entirely and are used only by trusted server code.
-- ---------------------------------------------------------------------------
create or replace function atd.app_user_id() returns uuid
language plpgsql stable as $$
declare v uuid;
begin
  begin
    v := nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
  exception when others then v := null;
  end;
  if v is null then
    begin
      v := nullif(current_setting('app.user_id', true), '')::uuid;
    exception when others then v := null;
    end;
  end if;
  return (select u.id from atd.users u where u.auth_user_id = v or u.id = v limit 1);
end $$;

create or replace function atd.has_permission(p_key text, p_location uuid default null)
returns boolean language sql stable as $$
  with me as (select atd.app_user_id() as uid)
  select
    -- explicit deny wins
    not exists (
      select 1 from atd.user_permission_overrides o, me
       where o.user_id = me.uid and o.permission_key = p_key and o.effect = 'deny'
         and (o.location_id is null or o.location_id = p_location))
    and (
      exists (
        select 1 from atd.user_roles ur
          join atd.role_permissions rp on rp.role_id = ur.role_id, me
         where ur.user_id = me.uid and ur.revoked_at is null
           and rp.permission_key = p_key
           and (ur.location_id is null or p_location is null or ur.location_id = p_location))
      or exists (
        select 1 from atd.user_permission_overrides o, me
         where o.user_id = me.uid and o.permission_key = p_key and o.effect = 'allow'
           and (o.location_id is null or o.location_id = p_location))
    )
$$;

create or replace function atd.is_staff(p_location uuid default null)
returns boolean language sql stable as $$
  select exists (
    select 1 from atd.user_roles ur join atd.roles r on r.id = ur.role_id
     where ur.user_id = atd.app_user_id() and ur.revoked_at is null
       and r.key in ('super_admin','location_admin','front_desk','coach')
       and (ur.location_id is null or p_location is null or ur.location_id = p_location))
$$;

create or replace function atd.my_household_ids() returns setof uuid
language sql stable as $$
  select hm.household_id from atd.household_members hm
   where hm.user_id = atd.app_user_id()
$$;

create or replace function atd.my_coach_id() returns uuid
language sql stable as $$
  select c.id from atd.coaches c where c.user_id = atd.app_user_id() and c.deleted_at is null
$$;

-- ---------------------------------------------------------------------------
-- Row-level security
-- ---------------------------------------------------------------------------
alter table atd.households        enable row level security;
alter table atd.household_members enable row level security;
alter table atd.participants      enable row level security;
alter table atd.bookings          enable row level security;
alter table atd.booking_participants enable row level security;
alter table atd.registrations     enable row level security;
alter table atd.orders            enable row level security;
alter table atd.payments          enable row level security;
alter table atd.package_purchases enable row level security;
alter table atd.memberships       enable row level security;
alter table atd.signed_waivers    enable row level security;
alter table atd.waitlist_entries  enable row level security;
alter table atd.lesson_notes      enable row level security;
alter table atd.staff_notes       enable row level security;
alter table atd.emergency_contacts enable row level security;
alter table atd.notifications     enable row level security;
alter table atd.resource_reservations enable row level security;

create policy households_self on atd.households for select
  using (id in (select atd.my_household_ids()) or atd.is_staff(location_id));
create policy households_update on atd.households for update
  using (id in (select atd.my_household_ids()) or atd.has_permission('customer.write', location_id));

create policy household_members_self on atd.household_members for select
  using (household_id in (select atd.my_household_ids()) or atd.is_staff(null));

create policy participants_self on atd.participants for select
  using (household_id in (select atd.my_household_ids()) or atd.is_staff(null));
create policy participants_write on atd.participants for all
  using (household_id in (select atd.my_household_ids())
         or atd.has_permission('customer.write', null))
  with check (household_id in (select atd.my_household_ids())
         or atd.has_permission('customer.write', null));

create policy bookings_self on atd.bookings for select
  using (household_id in (select atd.my_household_ids())
         or atd.is_staff(location_id)
         -- a coach sees bookings they are reserved on
         or exists (select 1 from atd.resource_reservations rr
                      join atd.coaches c on c.resource_id = rr.resource_id
                     where rr.booking_id = bookings.id and c.id = atd.my_coach_id()));
create policy bookings_staff_write on atd.bookings for all
  using (atd.has_permission('booking.update', location_id))
  with check (atd.has_permission('booking.create', location_id));

create policy booking_participants_self on atd.booking_participants for select
  using (exists (select 1 from atd.bookings b where b.id = booking_id
                   and (b.household_id in (select atd.my_household_ids())
                        or atd.is_staff(b.location_id))));

create policy registrations_self on atd.registrations for select
  using (household_id in (select atd.my_household_ids()) or atd.is_staff(null));

create policy orders_self on atd.orders for select
  using (household_id in (select atd.my_household_ids()) or atd.is_staff(location_id));

create policy payments_self on atd.payments for select
  using (household_id in (select atd.my_household_ids())
         or atd.has_permission('finance.reports', location_id)
         or atd.has_permission('payment.collect', location_id));

create policy packages_self on atd.package_purchases for select
  using (household_id in (select atd.my_household_ids()) or atd.is_staff(null));

create policy memberships_self on atd.memberships for select
  using (household_id in (select atd.my_household_ids()) or atd.is_staff(null));

create policy waivers_self on atd.signed_waivers for select
  using (household_id in (select atd.my_household_ids()) or atd.is_staff(null));

create policy waitlist_self on atd.waitlist_entries for select
  using (household_id in (select atd.my_household_ids()) or atd.is_staff(location_id));

-- Lesson notes: coaches see their own; parents see only what was shared.
create policy lesson_notes_read on atd.lesson_notes for select
  using (coach_id = atd.my_coach_id()
         or atd.has_permission('customer.read', null)
         or (shared_with_customer and exists (
               select 1 from atd.participants p
                where p.id = participant_id
                  and p.household_id in (select atd.my_household_ids()))));

-- Staff notes are never customer-visible.
create policy staff_notes_staff_only on atd.staff_notes for select
  using (case when visibility = 'admin_only'
              then atd.has_permission('staff.manage', location_id)
              when visibility = 'coach'
              then atd.is_staff(location_id)
              else atd.has_permission('customer.read', location_id) end);

create policy emergency_contacts_read on atd.emergency_contacts for select
  using (household_id in (select atd.my_household_ids()) or atd.is_staff(null));

create policy notifications_self on atd.notifications for select
  using (household_id in (select atd.my_household_ids())
         or to_user_id = atd.app_user_id()
         or atd.is_staff(location_id));

-- Reservations are readable by staff; customers see only their own bookings'.
create policy reservations_read on atd.resource_reservations for select
  using (atd.is_staff(location_id)
         or exists (select 1 from atd.bookings b where b.id = booking_id
                      and b.household_id in (select atd.my_household_ids())));

-- ---------------------------------------------------------------------------
-- Sensitive-column protection: a view that redacts medical data unless the
-- caller holds participant.read_medical. The app reads this, never the table,
-- for staff-facing lists.
-- ---------------------------------------------------------------------------
create or replace view atd.participants_safe
with (security_invoker = true) as
select p.id, p.household_id, p.first_name, p.last_name, p.preferred_name,
       p.date_of_birth, p.sport, p.school, p.team_name, p.skill_level,
       p.positions, p.bats, p.throws, p.shirt_size, p.is_active,
       case when atd.has_permission('participant.read_medical')
                 or p.household_id in (select atd.my_household_ids())
            then p.allergies else null end as allergies,
       case when atd.has_permission('participant.read_medical')
                 or p.household_id in (select atd.my_household_ids())
            then p.medical_notes else null end as medical_notes,
       atd.age_on(p.date_of_birth, current_date) as age
  from atd.participants p
 where p.deleted_at is null;

revoke update, delete on audit.entries from public;
