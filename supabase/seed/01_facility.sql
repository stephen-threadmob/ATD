-- =============================================================================
-- SEED 01 — ATD Baseball Company facility, staff, service catalogue
-- Every value here is admin-editable at runtime; nothing is hard-coded in app
-- logic. This file just gives the platform a realistic day-one configuration.
-- =============================================================================
set search_path = atd, public;

-- ---------------------------------------------------------------------------
-- Organisation + location
-- ---------------------------------------------------------------------------
insert into atd.organizations (id, name, legal_name, support_email, support_phone, branding) values
('00000000-0000-4000-8000-00000000ff01', 'ATD Baseball Company', 'ATD Baseball Company LLC',
 'info@atdbaseball.com', '+15555550100',
 jsonb_build_object('primary','#0B2545','accent','#C8102E','neutral','#F5F6F8',
                    'font_display','Barlow Condensed','font_body','Inter'));

insert into atd.locations (id, organization_id, slug, name, timezone,
  address_line1, city, region, postal_code, phone, email) values
('00000000-0000-4000-8000-0000000010c1', '00000000-0000-4000-8000-00000000ff01',
 'atd-main', 'ATD Baseball — Training Center', 'America/New_York',
 '1200 Diamond Way', 'Wallingford', 'CT', '06492', '+15555550100', 'info@atdbaseball.com');

-- Operating hours 9:30 AM – 8:30 PM, seven days, fully editable.
insert into atd.operating_hour_sets (id, location_id, name, is_default, priority) values
('00000000-0000-4000-8000-00000000a001', '00000000-0000-4000-8000-0000000010c1',
 'Standard Hours', true, 0);

insert into atd.operating_hours (hour_set_id, day_of_week, opens_at, closes_at)
select '00000000-0000-4000-8000-00000000a001', d, time '09:30', time '20:30'
from generate_series(0,6) d;

insert into atd.date_overrides (location_id, on_date, is_closed, label) values
('00000000-0000-4000-8000-0000000010c1', date '2026-12-25', true, 'Christmas Day'),
('00000000-0000-4000-8000-0000000010c1', date '2026-11-26', true, 'Thanksgiving');

-- ---------------------------------------------------------------------------
-- Resource types
-- ---------------------------------------------------------------------------
insert into atd.resource_types (id, location_id, key, name, kind, allocation, color, sort_order) values
('a0000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-0000000010c1','cage','Batting Cage','cage','exclusive','#1f6feb',1),
('a0000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-0000000010c1','hittrax','HitTrax System','hittrax_system','exclusive','#8957e5',2),
('a0000000-0000-4000-8000-000000000003','00000000-0000-4000-8000-0000000010c1','coach','Coach','staff','exclusive','#1a7f37',3),
('a0000000-0000-4000-8000-000000000004','00000000-0000-4000-8000-0000000010c1','party_room','Party / Event Space','party_room','exclusive','#bf8700',4),
('a0000000-0000-4000-8000-000000000005','00000000-0000-4000-8000-0000000010c1','lobby','Lobby','lobby','shared','#57606a',5),
('a0000000-0000-4000-8000-000000000006','00000000-0000-4000-8000-0000000010c1','event_host','Event Host','event_host','exclusive','#cf222e',6),
('a0000000-0000-4000-8000-000000000007','00000000-0000-4000-8000-0000000010c1','machine','Pitching Machine','machine','exclusive','#6e7781',7),
('a0000000-0000-4000-8000-000000000008','00000000-0000-4000-8000-0000000010c1','facility','Whole Facility','facility','exclusive','#24292f',8);

-- ---------------------------------------------------------------------------
-- Physical resources: 1×50ft, 3×35ft, 1×70ft w/ HitTrax, plus spaces
-- ---------------------------------------------------------------------------
insert into atd.resources (id, location_id, resource_type_id, code, name, capacity, attributes, sort_order) values
('b0000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-0000000010c1','a0000000-0000-4000-8000-000000000001','CAGE-1','Cage 1 — 50 ft',1,
  '{"length_ft":50,"has_hittrax":false,"has_mound":true,"turf":"pro","supports_pitching":true}',1),
('b0000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-0000000010c1','a0000000-0000-4000-8000-000000000001','CAGE-2','Cage 2 — 35 ft',1,
  '{"length_ft":35,"has_hittrax":false,"has_mound":false,"turf":"standard","supports_pitching":false}',2),
('b0000000-0000-4000-8000-000000000003','00000000-0000-4000-8000-0000000010c1','a0000000-0000-4000-8000-000000000001','CAGE-3','Cage 3 — 35 ft',1,
  '{"length_ft":35,"has_hittrax":false,"has_mound":false,"turf":"standard","supports_pitching":false}',3),
('b0000000-0000-4000-8000-000000000004','00000000-0000-4000-8000-0000000010c1','a0000000-0000-4000-8000-000000000001','CAGE-4','Cage 4 — 35 ft',1,
  '{"length_ft":35,"has_hittrax":false,"has_mound":false,"turf":"standard","supports_pitching":false}',4),
('b0000000-0000-4000-8000-000000000005','00000000-0000-4000-8000-0000000010c1','a0000000-0000-4000-8000-000000000001','CAGE-5','Cage 5 — 70 ft (HitTrax)',1,
  '{"length_ft":70,"has_hittrax":true,"has_mound":true,"turf":"pro","supports_pitching":true}',5),
('b0000000-0000-4000-8000-000000000010','00000000-0000-4000-8000-0000000010c1','a0000000-0000-4000-8000-000000000002','HITTRAX-1','HitTrax Unit',1,
  '{"model":"HitTrax Pro"}',10),
('b0000000-0000-4000-8000-000000000020','00000000-0000-4000-8000-0000000010c1','a0000000-0000-4000-8000-000000000004','PARTY-1','Party Room',1,
  '{"seats":24,"has_tv":true}',20),
('b0000000-0000-4000-8000-000000000021','00000000-0000-4000-8000-0000000010c1','a0000000-0000-4000-8000-000000000005','LOBBY','Lobby & Waiting Area',3,
  '{}',21),
('b0000000-0000-4000-8000-000000000030','00000000-0000-4000-8000-0000000010c1','a0000000-0000-4000-8000-000000000007','MACHINE-1','Iron Mike Pitching Machine',1,
  '{"type":"arm"}',30),
('b0000000-0000-4000-8000-000000000031','00000000-0000-4000-8000-0000000010c1','a0000000-0000-4000-8000-000000000007','MACHINE-2','Hack Attack Wheel Machine',1,
  '{"type":"wheel"}',31),
('b0000000-0000-4000-8000-000000000040','00000000-0000-4000-8000-0000000010c1','a0000000-0000-4000-8000-000000000006','HOST-1','Event Host A',1,'{}',40),
('b0000000-0000-4000-8000-000000000041','00000000-0000-4000-8000-0000000010c1','a0000000-0000-4000-8000-000000000006','HOST-2','Event Host B',1,'{}',41);

-- HitTrax lives in Cage 5. Reserving the cage for a HitTrax service also pulls
-- the unit through an explicit requirement, and the parent link keeps the
-- physical relationship visible in the admin UI.
update atd.resources set parent_resource_id = 'b0000000-0000-4000-8000-000000000005'
 where id = 'b0000000-0000-4000-8000-000000000010';

-- ---------------------------------------------------------------------------
-- Qualifications
-- ---------------------------------------------------------------------------
insert into atd.qualifications (id, key, name, category) values
('c0000000-0000-4000-8000-000000000001','hitting','Hitting Instruction','skill'),
('c0000000-0000-4000-8000-000000000002','pitching','Pitching Instruction','skill'),
('c0000000-0000-4000-8000-000000000003','catching','Catching Instruction','skill'),
('c0000000-0000-4000-8000-000000000004','fielding','Infield / Outfield','skill'),
('c0000000-0000-4000-8000-000000000005','arm_care','Arm Care Program','program'),
('c0000000-0000-4000-8000-000000000006','strength','Strength & Conditioning','program'),
('c0000000-0000-4000-8000-000000000007','hittrax','HitTrax Certified','equipment'),
('c0000000-0000-4000-8000-000000000008','softball','Softball Specialist','skill'),
('c0000000-0000-4000-8000-000000000009','camp_lead','Camp Lead Instructor','program');

-- ---------------------------------------------------------------------------
-- Staff users
-- ---------------------------------------------------------------------------
insert into atd.users (id, email, phone, first_name, last_name, status) values
('d0000000-0000-4000-8000-000000000001','owner@atdbaseball.com','+15555550101','Anthony','Delgado','active'),
('d0000000-0000-4000-8000-000000000002','manager@atdbaseball.com','+15555550102','Renee','Okafor','active'),
('d0000000-0000-4000-8000-000000000003','frontdesk@atdbaseball.com','+15555550103','Jamie','Whitfield','active'),
('d0000000-0000-4000-8000-000000000011','mreyes@atdbaseball.com','+15555550111','Marcus','Reyes','active'),
('d0000000-0000-4000-8000-000000000012','tcallahan@atdbaseball.com','+15555550112','Tyler','Callahan','active'),
('d0000000-0000-4000-8000-000000000013','dnakamura@atdbaseball.com','+15555550113','Dana','Nakamura','active'),
('d0000000-0000-4000-8000-000000000014','jbrennan@atdbaseball.com','+15555550114','Joe','Brennan','active'),
('d0000000-0000-4000-8000-000000000015','svargas@atdbaseball.com','+15555550115','Sofia','Vargas','active');

insert into atd.user_roles (user_id, role_id, location_id)
select u.id, r.id, case when r.key = 'super_admin' then null
                        else '00000000-0000-4000-8000-0000000010c1'::uuid end
from (values
  ('d0000000-0000-4000-8000-000000000001'::uuid,'super_admin'::atd.role_key),
  ('d0000000-0000-4000-8000-000000000002','location_admin'),
  ('d0000000-0000-4000-8000-000000000003','front_desk'),
  ('d0000000-0000-4000-8000-000000000011','coach'),
  ('d0000000-0000-4000-8000-000000000012','coach'),
  ('d0000000-0000-4000-8000-000000000013','coach'),
  ('d0000000-0000-4000-8000-000000000014','coach'),
  ('d0000000-0000-4000-8000-000000000015','coach')
) as u(id, rk)
join atd.roles r on r.key = u.rk;

-- Coaches are also resources, so one exclusion constraint covers them.
insert into atd.resources (id, location_id, resource_type_id, code, name, capacity, is_bookable_directly, sort_order) values
('b0000000-0000-4000-8000-0000000000c1','00000000-0000-4000-8000-0000000010c1','a0000000-0000-4000-8000-000000000003','COACH-MR','Marcus Reyes',1,false,101),
('b0000000-0000-4000-8000-0000000000c2','00000000-0000-4000-8000-0000000010c1','a0000000-0000-4000-8000-000000000003','COACH-TC','Tyler Callahan',1,false,102),
('b0000000-0000-4000-8000-0000000000c3','00000000-0000-4000-8000-0000000010c1','a0000000-0000-4000-8000-000000000003','COACH-DN','Dana Nakamura',1,false,103),
('b0000000-0000-4000-8000-0000000000c4','00000000-0000-4000-8000-0000000010c1','a0000000-0000-4000-8000-000000000003','COACH-JB','Joe Brennan',1,false,104),
('b0000000-0000-4000-8000-0000000000c5','00000000-0000-4000-8000-0000000010c1','a0000000-0000-4000-8000-000000000003','COACH-SV','Sofia Vargas',1,false,105);

insert into atd.coaches (id, user_id, resource_id, display_name, headline, bio, sports,
                         employment_type, assignment_priority, max_sessions_per_day, min_lead_time_minutes) values
('e0000000-0000-4000-8000-000000000001','d0000000-0000-4000-8000-000000000011','b0000000-0000-4000-8000-0000000000c1',
 'Marcus Reyes','Hitting Director — former Double-A outfielder',
 'Marcus leads ATD''s hitting program and specialises in swing mechanics and HitTrax-driven development.','both','employee',10,8,120),
('e0000000-0000-4000-8000-000000000002','d0000000-0000-4000-8000-000000000012','b0000000-0000-4000-8000-0000000000c2',
 'Tyler Callahan','Pitching Coordinator',
 'Ten years of arm-care and velocity development with high school and travel arms.','baseball','employee',20,7,120),
('e0000000-0000-4000-8000-000000000003','d0000000-0000-4000-8000-000000000013','b0000000-0000-4000-8000-0000000000c3',
 'Dana Nakamura','Softball Hitting & Fielding',
 'Former D1 middle infielder focused on softball hitting and defensive footwork.','softball','contractor',30,6,180),
('e0000000-0000-4000-8000-000000000004','d0000000-0000-4000-8000-000000000014','b0000000-0000-4000-8000-0000000000c4',
 'Joe Brennan','Catching & Infield',
 'Catching specialist — receiving, blocking, throwing and game calling.','baseball','contractor',40,6,180),
('e0000000-0000-4000-8000-000000000005','d0000000-0000-4000-8000-000000000015','b0000000-0000-4000-8000-0000000000c5',
 'Sofia Vargas','Strength & Arm Care',
 'CSCS-certified; runs ATD''s arm-care and youth strength programming.','both','contractor',50,5,180);

insert into atd.coach_locations (coach_id, location_id)
select id, '00000000-0000-4000-8000-0000000010c1' from atd.coaches;

insert into atd.coach_qualifications (coach_id, qualification_id) values
('e0000000-0000-4000-8000-000000000001','c0000000-0000-4000-8000-000000000001'),
('e0000000-0000-4000-8000-000000000001','c0000000-0000-4000-8000-000000000007'),
('e0000000-0000-4000-8000-000000000001','c0000000-0000-4000-8000-000000000009'),
('e0000000-0000-4000-8000-000000000002','c0000000-0000-4000-8000-000000000002'),
('e0000000-0000-4000-8000-000000000002','c0000000-0000-4000-8000-000000000005'),
('e0000000-0000-4000-8000-000000000002','c0000000-0000-4000-8000-000000000009'),
('e0000000-0000-4000-8000-000000000003','c0000000-0000-4000-8000-000000000001'),
('e0000000-0000-4000-8000-000000000003','c0000000-0000-4000-8000-000000000004'),
('e0000000-0000-4000-8000-000000000003','c0000000-0000-4000-8000-000000000008'),
('e0000000-0000-4000-8000-000000000003','c0000000-0000-4000-8000-000000000007'),
('e0000000-0000-4000-8000-000000000004','c0000000-0000-4000-8000-000000000003'),
('e0000000-0000-4000-8000-000000000004','c0000000-0000-4000-8000-000000000004'),
('e0000000-0000-4000-8000-000000000004','c0000000-0000-4000-8000-000000000001'),
('e0000000-0000-4000-8000-000000000005','c0000000-0000-4000-8000-000000000005'),
('e0000000-0000-4000-8000-000000000005','c0000000-0000-4000-8000-000000000006');

-- Weekly availability: weekdays 3:00–8:30 PM, weekends 9:30 AM–4:00 PM.
insert into atd.coach_availability_rules (coach_id, day_of_week, starts_at, ends_at)
select c.id, d, time '15:00', time '20:30'
from atd.coaches c cross join generate_series(1,5) d;
insert into atd.coach_availability_rules (coach_id, day_of_week, starts_at, ends_at)
select c.id, d, time '09:30', time '16:00'
from atd.coaches c cross join (values (0),(6)) as g(d);

-- Marcus also works weekday mornings.
insert into atd.coach_availability_rules (coach_id, day_of_week, starts_at, ends_at)
select 'e0000000-0000-4000-8000-000000000001', d, time '09:30', time '13:00'
from generate_series(1,5) d;

-- ---------------------------------------------------------------------------
-- Policies
-- ---------------------------------------------------------------------------
insert into atd.policies (id, location_id, name, description, applies_to, is_default) values
('66000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-0000000010c1',
 'Standard Lesson Policy','24-hour cancellation window for private instruction.','booking',true),
('66000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-0000000010c1',
 'Program & Camp Policy','Tiered refunds up to 14 days before start.','registration',false),
('66000000-0000-4000-8000-000000000003','00000000-0000-4000-8000-0000000010c1',
 'Party Policy','Deposit non-refundable inside 14 days.','party',false);

insert into atd.policy_tiers (policy_id, min_hours_before, action, outcome, refund_percent, fee_cents, returns_package_credit) values
('66000000-0000-4000-8000-000000000001', 24, 'cancel','full_refund',100,0,true),
('66000000-0000-4000-8000-000000000001', 12, 'cancel','partial_refund',50,0,true),
('66000000-0000-4000-8000-000000000001',  0, 'cancel','credit_forfeited',0,0,false),
('66000000-0000-4000-8000-000000000001', 24, 'reschedule','reschedule_free',null,0,true),
('66000000-0000-4000-8000-000000000001',  2, 'reschedule','reschedule_fee',null,1500,true),
('66000000-0000-4000-8000-000000000001',  0, 'no_show','credit_forfeited',0,0,false),
('66000000-0000-4000-8000-000000000002', 336,'cancel','full_refund',100,0,true),
('66000000-0000-4000-8000-000000000002', 168,'cancel','partial_refund',75,0,true),
('66000000-0000-4000-8000-000000000002', 48, 'cancel','account_credit',100,0,true),
('66000000-0000-4000-8000-000000000002', 0,  'cancel','no_refund',0,0,false),
('66000000-0000-4000-8000-000000000003', 336,'cancel','partial_refund',100,0,false),
('66000000-0000-4000-8000-000000000003', 0,  'cancel','no_refund',0,0,false);

-- ---------------------------------------------------------------------------
-- Tax + service categories
-- ---------------------------------------------------------------------------
insert into atd.tax_rates (id, location_id, name, percent) values
('66000000-0000-4000-8000-0000000000e1', '00000000-0000-4000-8000-0000000010c1', 'CT Sales Tax', 6.350);

insert into atd.service_categories (id, location_id, key, name, description, color, sort_order) values
('f0000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-0000000010c1','private_lessons','Private Lessons','One-on-one instruction with an ATD coach.','#1a7f37',1),
('f0000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-0000000010c1','cage_rentals','Cage Rentals','Rent a cage by the half hour or hour.','#1f6feb',2),
('f0000000-0000-4000-8000-000000000003','00000000-0000-4000-8000-0000000010c1','hittrax','HitTrax','Simulator sessions, lessons and games.','#8957e5',3),
('f0000000-0000-4000-8000-000000000004','00000000-0000-4000-8000-0000000010c1','group_training','Group Training','Semi-private and group instruction.','#bf8700',4),
('f0000000-0000-4000-8000-000000000005','00000000-0000-4000-8000-0000000010c1','camps_clinics','Camps & Clinics','School-break camps and skill clinics.','#cf222e',5),
('f0000000-0000-4000-8000-000000000006','00000000-0000-4000-8000-0000000010c1','programs','Programs','Multi-week arm care and strength programs.','#0969da',6),
('f0000000-0000-4000-8000-000000000007','00000000-0000-4000-8000-0000000010c1','parties_events','Parties & Events','Birthday parties and Parents'' Night Out.','#d4a72c',7),
('f0000000-0000-4000-8000-000000000008','00000000-0000-4000-8000-0000000010c1','team_rentals','Team & Facility Rentals','Team practices and full facility buyouts.','#57606a',8);
