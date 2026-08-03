-- =============================================================================
-- 0005 Service catalogue, resource requirements, pricing, policies, add-ons
-- -----------------------------------------------------------------------------
-- This is the "no developer required" layer. A service is a template that
-- declares WHAT resources it consumes and HOW it is priced. The scheduling
-- engine reads these rows; it has no knowledge of "birthday party" or
-- "HitTrax lesson" as concepts.
-- =============================================================================
set search_path = atd, public;

create table atd.service_categories (
  id          uuid primary key default gen_random_uuid(),
  location_id uuid references atd.locations(id) on delete cascade,
  key         text not null,
  name        text not null,
  description text,
  color       text not null default '#1f6feb',
  icon        text,
  sort_order  int not null default 0,
  is_public   boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create unique index on atd.service_categories
  (coalesce(location_id,'00000000-0000-0000-0000-000000000000'::uuid), key);

create table atd.services (
  id                  uuid primary key default gen_random_uuid(),
  location_id         uuid not null references atd.locations(id) on delete cascade,
  category_id         uuid not null references atd.service_categories(id) on delete restrict,
  slug                text not null,
  name                text not null,
  short_description   text,
  description         text,
  format              atd.service_format not null,
  image_url           text,
  color               text,

  -- Scheduling shape ------------------------------------------------------
  default_duration_minutes int not null default 60 check (default_duration_minutes > 0),
  min_duration_minutes     int,
  max_duration_minutes     int,
  duration_increment_minutes int not null default 30,
  setup_minutes            int not null default 0 check (setup_minutes >= 0),
  cleanup_minutes          int not null default 0 check (cleanup_minutes >= 0),
  buffer_before_minutes    int not null default 0 check (buffer_before_minutes >= 0),
  buffer_after_minutes     int not null default 0 check (buffer_after_minutes >= 0),
  slot_granularity_minutes int not null default 15,

  -- Capacity + eligibility -------------------------------------------------
  min_participants    int not null default 1 check (min_participants >= 0),
  max_participants    int not null default 1 check (max_participants >= 1),
  min_age             int,
  max_age             int,
  allowed_sports      atd.sport not null default 'both',
  skill_levels        text[] not null default '{}',

  -- Booking rules ----------------------------------------------------------
  is_online_bookable  boolean not null default true,
  is_public           boolean not null default true,
  requires_approval   boolean not null default false,
  allow_guest_checkout boolean not null default true,
  min_lead_minutes    int not null default 60,
  max_horizon_days    int not null default 120,
  max_active_bookings_per_household int,
  cancellation_policy_id uuid,                       -- FK added below
  waiver_template_ids uuid[] not null default '{}',
  requires_deposit    boolean not null default false,
  deposit_cents       bigint not null default 0,
  deposit_percent     numeric(5,2),
  balance_due_days_before int,

  -- Pricing ----------------------------------------------------------------
  pricing_model       atd.pricing_model not null default 'fixed',
  base_price_cents    bigint not null default 0,
  tax_rate_id         uuid,
  is_taxable          boolean not null default false,

  sort_order          int not null default 0,
  is_active           boolean not null default true,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  deleted_at          timestamptz,
  check (max_participants >= min_participants),
  check (max_age is null or min_age is null or max_age >= min_age),
  check (min_duration_minutes is null or min_duration_minutes <= default_duration_minutes),
  check (max_duration_minutes is null or max_duration_minutes >= default_duration_minutes)
);
create unique index on atd.services (location_id, slug) where deleted_at is null;
create index on atd.services (location_id, category_id) where deleted_at is null and is_active;

-- ---------------------------------------------------------------------------
-- Resource requirements. One row per "slot" the service needs filled.
-- A HitTrax lesson has three rows: coach(1), cage(1, attr has_hittrax=true),
-- hittrax_system(1). A birthday party has: party_room(1), cage(2), host(1).
-- ---------------------------------------------------------------------------
create table atd.service_resource_requirements (
  id                 uuid primary key default gen_random_uuid(),
  service_id         uuid not null references atd.services(id) on delete cascade,
  label              text not null,
  resource_type_id   uuid not null references atd.resource_types(id) on delete restrict,
  quantity           int not null default 1 check (quantity >= 1),
  is_optional        boolean not null default false,
  -- Matching: attribute predicate applied to resources.attributes via @>.
  required_attributes jsonb not null default '{}'::jsonb,
  -- Explicit allow / prefer lists override attribute matching when non-empty.
  allowed_resource_ids   uuid[] not null default '{}',
  preferred_resource_ids uuid[] not null default '{}',
  excluded_resource_ids  uuid[] not null default '{}',
  required_qualification_ids uuid[] not null default '{}',   -- coach slots only
  assignment_mode    atd.assignment_mode not null default 'auto',
  -- Per-requirement buffer overrides; fall back to the service values.
  setup_minutes      int,
  cleanup_minutes    int,
  buffer_before_minutes int,
  buffer_after_minutes  int,
  -- Occupy only part of the booking window (e.g. host only for first 30 min).
  offset_start_minutes int not null default 0,
  offset_end_minutes   int not null default 0,
  sort_order         int not null default 0,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);
create index on atd.service_resource_requirements (service_id, sort_order);

-- Add-ons: optional purchasable extras that may themselves pull resources.
create table atd.service_addons (
  id              uuid primary key default gen_random_uuid(),
  location_id     uuid not null references atd.locations(id) on delete cascade,
  key             text not null,
  name            text not null,
  description     text,
  price_cents     bigint not null default 0,
  price_per       text not null default 'booking'
                    check (price_per in ('booking','participant','hour')),
  max_quantity    int not null default 1,
  is_taxable      boolean not null default false,
  -- Requirement template applied when the add-on is selected.
  adds_resource_type_id uuid references atd.resource_types(id) on delete set null,
  adds_resource_quantity int not null default 0,
  adds_required_attributes jsonb not null default '{}'::jsonb,
  adds_minutes    int not null default 0,
  is_active       boolean not null default true,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create unique index on atd.service_addons (location_id, key);

create table atd.service_addon_links (
  service_id uuid not null references atd.services(id) on delete cascade,
  addon_id   uuid not null references atd.service_addons(id) on delete cascade,
  is_default boolean not null default false,
  is_required boolean not null default false,
  sort_order int not null default 0,
  primary key (service_id, addon_id)
);

-- Intake questions rendered during checkout.
create table atd.service_questions (
  id            uuid primary key default gen_random_uuid(),
  service_id    uuid not null references atd.services(id) on delete cascade,
  key           text not null,
  label         text not null,
  help_text     text,
  input_type    text not null default 'text'
                  check (input_type in ('text','textarea','number','select','multiselect','boolean','date','phone','email')),
  options       jsonb not null default '[]'::jsonb,
  is_required   boolean not null default false,
  applies_to    text not null default 'booking'
                  check (applies_to in ('booking','participant')),
  is_sensitive  boolean not null default false,
  sort_order    int not null default 0,
  created_at    timestamptz not null default now()
);
create unique index on atd.service_questions (service_id, key);

-- ---------------------------------------------------------------------------
-- Pricing rules. Evaluated in priority order; the engine collects every
-- matching rule and applies them as an ordered pipeline, so peak + member +
-- promo compose predictably and the breakdown is fully explainable.
-- ---------------------------------------------------------------------------
create table atd.rate_cards (
  id          uuid primary key default gen_random_uuid(),
  location_id uuid not null references atd.locations(id) on delete cascade,
  name        text not null,
  description text,
  is_default  boolean not null default false,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
alter table atd.customer_organizations
  add constraint customer_organizations_rate_card_fk
  foreign key (custom_rate_card_id) references atd.rate_cards(id) on delete set null;

create table atd.pricing_rules (
  id              uuid primary key default gen_random_uuid(),
  location_id     uuid not null references atd.locations(id) on delete cascade,
  rate_card_id    uuid references atd.rate_cards(id) on delete cascade,
  service_id      uuid references atd.services(id) on delete cascade,
  category_id     uuid references atd.service_categories(id) on delete cascade,
  name            text not null,
  scope           atd.rate_scope not null default 'base',
  priority        int not null default 100,       -- ascending application order
  -- Conditions (all NULL-able; null = "don't care")
  coach_id        uuid references atd.coaches(id) on delete cascade,
  resource_id     uuid references atd.resources(id) on delete cascade,
  membership_plan_id uuid,                          -- FK added in 0008
  days_of_week    int[],
  starts_at_time  time,
  ends_at_time    time,
  effective_from  date,
  effective_to    date,
  min_duration_minutes int,
  max_duration_minutes int,
  min_participants int,
  max_participants int,
  min_days_before int,        -- early-bird
  max_days_before int,        -- late registration
  -- Effect
  effect          text not null default 'set'
                    check (effect in ('set','add','multiply','percent_off','amount_off','set_per_minute','set_per_participant')),
  amount_cents    bigint,
  percent         numeric(6,3),
  is_active       boolean not null default true,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index on atd.pricing_rules (location_id, service_id, priority) where is_active;

create table atd.tax_rates (
  id          uuid primary key default gen_random_uuid(),
  location_id uuid not null references atd.locations(id) on delete cascade,
  name        text not null,
  percent     numeric(6,3) not null default 0,
  stripe_tax_rate_id text,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now()
);
alter table atd.services
  add constraint services_tax_rate_fk foreign key (tax_rate_id)
  references atd.tax_rates(id) on delete set null;

-- ---------------------------------------------------------------------------
-- Cancellation / reschedule / no-show policy engine
-- ---------------------------------------------------------------------------
create table atd.policies (
  id          uuid primary key default gen_random_uuid(),
  location_id uuid not null references atd.locations(id) on delete cascade,
  name        text not null,
  description text,
  applies_to  text not null default 'booking'
                check (applies_to in ('booking','registration','membership','party','rental')),
  is_default  boolean not null default false,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
alter table atd.services
  add constraint services_policy_fk foreign key (cancellation_policy_id)
  references atd.policies(id) on delete set null;

-- Ordered tiers: first matching tier (by hours-before descending) wins.
create table atd.policy_tiers (
  id                uuid primary key default gen_random_uuid(),
  policy_id         uuid not null references atd.policies(id) on delete cascade,
  min_hours_before  numeric(8,2) not null default 0,
  action            text not null default 'cancel' check (action in ('cancel','reschedule','no_show')),
  outcome           atd.policy_outcome not null,
  refund_percent    numeric(5,2),
  fee_cents         bigint not null default 0,
  returns_package_credit boolean not null default true,
  requires_approval boolean not null default false,
  note              text,
  sort_order        int not null default 0
);
create index on atd.policy_tiers (policy_id, action, min_hours_before desc);

select atd.attach_touch('atd.service_categories');
select atd.attach_touch('atd.services');
select atd.attach_touch('atd.service_resource_requirements');
select atd.attach_touch('atd.service_addons');
select atd.attach_touch('atd.rate_cards');
select atd.attach_touch('atd.pricing_rules');
select atd.attach_touch('atd.policies');
