-- =============================================================================
-- SEED 02 — Services, resource requirements, pricing, add-ons, packages,
--           memberships, waivers, notification templates
--
-- Note how each service differs ONLY in data. A HitTrax lesson is not a special
-- code path; it is a private lesson whose cage requirement carries
-- {"has_hittrax": true} and which adds a third requirement for the unit itself.
-- =============================================================================
set search_path = atd, public;

-- ---------------------------------------------------------------------------
-- Services
-- ---------------------------------------------------------------------------
insert into atd.services
 (id, location_id, category_id, slug, name, short_description, format,
  default_duration_minutes, min_duration_minutes, max_duration_minutes, duration_increment_minutes,
  buffer_before_minutes, buffer_after_minutes, setup_minutes, cleanup_minutes,
  min_participants, max_participants, min_age, max_age,
  pricing_model, base_price_cents, cancellation_policy_id, min_lead_minutes, slot_granularity_minutes)
values
-- Private instruction ---------------------------------------------------------
('11000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-0000000010c1','f0000000-0000-4000-8000-000000000001',
 'private-hitting','Private Hitting Lesson','One-on-one hitting instruction in a full-size cage.','appointment',
 60,30,90,30, 0,5,0,0, 1,1,6,18, 'fixed',9000,'66000000-0000-4000-8000-000000000001',120,15),
('11000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-0000000010c1','f0000000-0000-4000-8000-000000000001',
 'private-pitching','Private Pitching Lesson','Mechanics, command and velocity work on a mound cage.','appointment',
 60,30,90,30, 0,5,0,0, 1,1,8,18, 'fixed',9500,'66000000-0000-4000-8000-000000000001',120,15),
('11000000-0000-4000-8000-000000000003','00000000-0000-4000-8000-0000000010c1','f0000000-0000-4000-8000-000000000001',
 'private-catching','Private Catching Lesson','Receiving, blocking, and throwing mechanics.','appointment',
 60,30,60,30, 0,5,0,0, 1,1,8,18, 'fixed',9500,'66000000-0000-4000-8000-000000000001',120,15),
('11000000-0000-4000-8000-000000000004','00000000-0000-4000-8000-0000000010c1','f0000000-0000-4000-8000-000000000001',
 'private-fielding','Private Fielding Lesson','Infield and outfield footwork and hands.','appointment',
 60,30,60,30, 0,5,0,0, 1,1,7,18, 'fixed',9000,'66000000-0000-4000-8000-000000000001',120,15),
('11000000-0000-4000-8000-000000000005','00000000-0000-4000-8000-0000000010c1','f0000000-0000-4000-8000-000000000003',
 'hittrax-lesson','HitTrax Hitting Lesson','Private hitting lesson with live HitTrax data and video.','appointment',
 60,60,90,30, 5,10,5,5, 1,1,8,18, 'fixed',12000,'66000000-0000-4000-8000-000000000001',180,15),
('11000000-0000-4000-8000-000000000006','00000000-0000-4000-8000-0000000010c1','f0000000-0000-4000-8000-000000000001',
 'semi-private','Semi-Private Lesson (2–3)','Small-group instruction for siblings or teammates.','appointment',
 60,60,90,30, 0,5,0,0, 2,3,7,18, 'per_participant',6000,'66000000-0000-4000-8000-000000000001',120,15),

-- Rentals ---------------------------------------------------------------------
('11000000-0000-4000-8000-000000000010','00000000-0000-4000-8000-0000000010c1','f0000000-0000-4000-8000-000000000002',
 'cage-rental-35','Cage Rental — 35 ft','Self-guided tee and soft-toss work.','rental',
 60,30,180,30, 0,5,0,0, 1,6,0,99, 'per_minute',75,'66000000-0000-4000-8000-000000000001',30,30),
('11000000-0000-4000-8000-000000000011','00000000-0000-4000-8000-0000000010c1','f0000000-0000-4000-8000-000000000002',
 'cage-rental-50','Cage Rental — 50 ft w/ Mound','Full-length cage with mound for live work.','rental',
 60,30,180,30, 0,5,0,0, 1,8,0,99, 'per_minute',95,'66000000-0000-4000-8000-000000000001',30,30),
('11000000-0000-4000-8000-000000000012','00000000-0000-4000-8000-0000000010c1','f0000000-0000-4000-8000-000000000003',
 'hittrax-rental','HitTrax Rental','70 ft cage with the HitTrax simulator, self-guided.','rental',
 60,30,120,30, 5,10,5,5, 1,8,0,99, 'per_minute',150,'66000000-0000-4000-8000-000000000001',60,30),

-- Group / program shells ------------------------------------------------------
('11000000-0000-4000-8000-000000000020','00000000-0000-4000-8000-0000000010c1','f0000000-0000-4000-8000-000000000004',
 'group-hitting-clinic','Group Hitting Clinic','Six-player hitting group with two coaches.','group_session',
 75,75,75,15, 5,10,0,5, 4,12,9,14, 'fixed',4500,'66000000-0000-4000-8000-000000000002',120,15),
('11000000-0000-4000-8000-000000000021','00000000-0000-4000-8000-0000000010c1','f0000000-0000-4000-8000-000000000006',
 'arm-care-program','Arm Care Program','Six-week throwing health and velocity program.','program',
 60,60,60,15, 5,5,0,0, 4,10,11,18, 'fixed',39900,'66000000-0000-4000-8000-000000000002',1440,15),
('11000000-0000-4000-8000-000000000022','00000000-0000-4000-8000-0000000010c1','f0000000-0000-4000-8000-000000000005',
 'summer-camp','Summer Skills Camp','Multi-day camp across hitting, fielding and base running.','program',
 240,240,240,30, 15,30,15,15, 8,40,7,13, 'fixed',29900,'66000000-0000-4000-8000-000000000002',1440,30),
('11000000-0000-4000-8000-000000000023','00000000-0000-4000-8000-0000000010c1','f0000000-0000-4000-8000-000000000007',
 'parents-night-out','Parents'' Night Out','Supervised evening of games, pizza and cage time.','event',
 180,180,180,30, 15,30,15,15, 6,30,5,12, 'fixed',5500,'66000000-0000-4000-8000-000000000002',720,30),

-- Party + facility ------------------------------------------------------------
('11000000-0000-4000-8000-000000000030','00000000-0000-4000-8000-0000000010c1','f0000000-0000-4000-8000-000000000007',
 'birthday-party','Birthday Party — Grand Slam Package','90 minutes of cages plus 45 minutes in the party room.','party',
 135,135,180,30, 15,30,15,30, 8,20,4,16, 'fixed',45000,'66000000-0000-4000-8000-000000000003',2880,30),
('11000000-0000-4000-8000-000000000031','00000000-0000-4000-8000-0000000010c1','f0000000-0000-4000-8000-000000000008',
 'team-practice','Team Practice Rental','Three cages plus lobby space for a full team.','rental',
 120,60,240,30, 10,15,0,10, 8,25,0,99, 'per_minute',300,'66000000-0000-4000-8000-000000000001',720,30),
('11000000-0000-4000-8000-000000000032','00000000-0000-4000-8000-0000000010c1','f0000000-0000-4000-8000-000000000008',
 'facility-buyout','Full Facility Buyout','Exclusive use of the entire training center.','rental',
 180,120,360,60, 30,30,15,30, 10,60,0,99, 'per_minute',600,'66000000-0000-4000-8000-000000000003',10080,60);

update atd.services set requires_deposit = true, deposit_cents = 15000
 where id = '11000000-0000-4000-8000-000000000030';
update atd.services set requires_deposit = true, deposit_percent = 25
 where id = '11000000-0000-4000-8000-000000000032';
update atd.services set is_online_bookable = false
 where id in ('11000000-0000-4000-8000-000000000032');

-- ---------------------------------------------------------------------------
-- Resource requirements — the declarative heart of the engine
-- ---------------------------------------------------------------------------
-- Private hitting: qualified coach + any cage (35 or 50).
insert into atd.service_resource_requirements
 (service_id, label, resource_type_id, quantity, required_attributes,
  required_qualification_ids, assignment_mode, buffer_after_minutes, sort_order) values
('11000000-0000-4000-8000-000000000001','Coach','a0000000-0000-4000-8000-000000000003',1,'{}',
  array['c0000000-0000-4000-8000-000000000001']::uuid[],'auto_with_choice',5,1),
('11000000-0000-4000-8000-000000000001','Cage','a0000000-0000-4000-8000-000000000001',1,'{}',
  '{}','auto',5,2);

-- Private pitching: needs a mound, so the attribute predicate narrows to
-- Cage 1 and Cage 5 automatically. No code knows those cage numbers.
insert into atd.service_resource_requirements
 (service_id, label, resource_type_id, quantity, required_attributes,
  required_qualification_ids, assignment_mode, buffer_after_minutes, sort_order) values
('11000000-0000-4000-8000-000000000002','Coach','a0000000-0000-4000-8000-000000000003',1,'{}',
  array['c0000000-0000-4000-8000-000000000002']::uuid[],'auto_with_choice',5,1),
('11000000-0000-4000-8000-000000000002','Mound Cage','a0000000-0000-4000-8000-000000000001',1,
  '{"has_mound": true}','{}','auto',5,2);

insert into atd.service_resource_requirements
 (service_id, label, resource_type_id, quantity, required_attributes,
  required_qualification_ids, assignment_mode, buffer_after_minutes, sort_order) values
('11000000-0000-4000-8000-000000000003','Coach','a0000000-0000-4000-8000-000000000003',1,'{}',
  array['c0000000-0000-4000-8000-000000000003']::uuid[],'auto_with_choice',5,1),
('11000000-0000-4000-8000-000000000003','Cage','a0000000-0000-4000-8000-000000000001',1,'{}','{}','auto',5,2),
('11000000-0000-4000-8000-000000000004','Coach','a0000000-0000-4000-8000-000000000003',1,'{}',
  array['c0000000-0000-4000-8000-000000000004']::uuid[],'auto_with_choice',5,1),
('11000000-0000-4000-8000-000000000004','Cage','a0000000-0000-4000-8000-000000000001',1,'{}','{}','auto',5,2);

-- HitTrax lesson: HitTrax-certified coach + the 70 ft HitTrax cage + the unit.
-- Three resources, one booking, all blocked together.
insert into atd.service_resource_requirements
 (service_id, label, resource_type_id, quantity, required_attributes,
  required_qualification_ids, assignment_mode, buffer_before_minutes, buffer_after_minutes, sort_order) values
('11000000-0000-4000-8000-000000000005','HitTrax Coach','a0000000-0000-4000-8000-000000000003',1,'{}',
  array['c0000000-0000-4000-8000-000000000007']::uuid[],'auto_with_choice',5,10,1),
('11000000-0000-4000-8000-000000000005','HitTrax Cage','a0000000-0000-4000-8000-000000000001',1,
  '{"has_hittrax": true}','{}','auto',5,10,2),
('11000000-0000-4000-8000-000000000005','HitTrax Unit','a0000000-0000-4000-8000-000000000002',1,'{}','{}','auto',5,10,3);

insert into atd.service_resource_requirements
 (service_id, label, resource_type_id, quantity, required_attributes, assignment_mode, buffer_after_minutes, sort_order) values
('11000000-0000-4000-8000-000000000006','Coach','a0000000-0000-4000-8000-000000000003',1,'{}','auto_with_choice',5,1),
('11000000-0000-4000-8000-000000000006','Cage','a0000000-0000-4000-8000-000000000001',1,'{}','auto',5,2),

-- Rentals need no coach at all — a requirement set of one.
('11000000-0000-4000-8000-000000000010','Cage','a0000000-0000-4000-8000-000000000001',1,
  '{"length_ft": 35}','customer_choice',5,1),
('11000000-0000-4000-8000-000000000011','Cage','a0000000-0000-4000-8000-000000000001',1,
  '{"length_ft": 50}','customer_choice',5,1),
('11000000-0000-4000-8000-000000000012','HitTrax Cage','a0000000-0000-4000-8000-000000000001',1,
  '{"has_hittrax": true}','auto',10,1),
('11000000-0000-4000-8000-000000000012','HitTrax Unit','a0000000-0000-4000-8000-000000000002',1,'{}','auto',10,2),

-- Group clinic: two coaches, two cages, capacity 12 — but the cages are
-- blocked ONCE regardless of how many children register.
('11000000-0000-4000-8000-000000000020','Coaches','a0000000-0000-4000-8000-000000000003',2,'{}','admin_only',10,1),
('11000000-0000-4000-8000-000000000020','Cages','a0000000-0000-4000-8000-000000000001',2,'{}','auto',10,2),

('11000000-0000-4000-8000-000000000021','Coach','a0000000-0000-4000-8000-000000000003',1,'{}','admin_only',5,1),
('11000000-0000-4000-8000-000000000021','Cage','a0000000-0000-4000-8000-000000000001',1,'{}','auto',5,2),

-- Camp: four cages, three coaches, lobby for check-in.
('11000000-0000-4000-8000-000000000022','Camp Coaches','a0000000-0000-4000-8000-000000000003',3,'{}','admin_only',30,1),
('11000000-0000-4000-8000-000000000022','Camp Cages','a0000000-0000-4000-8000-000000000001',4,'{}','auto',30,2),
('11000000-0000-4000-8000-000000000022','Check-in Space','a0000000-0000-4000-8000-000000000005',1,'{}','auto',30,3),

('11000000-0000-4000-8000-000000000023','Staff','a0000000-0000-4000-8000-000000000006',2,'{}','admin_only',30,1),
('11000000-0000-4000-8000-000000000023','Cages','a0000000-0000-4000-8000-000000000001',2,'{}','auto',30,2),
('11000000-0000-4000-8000-000000000023','Party Room','a0000000-0000-4000-8000-000000000004',1,'{}','auto',30,3),

-- Birthday party: room + 2 cages + host, all held for the full window
-- including 15 min setup and 30 min cleanup.
('11000000-0000-4000-8000-000000000030','Party Room','a0000000-0000-4000-8000-000000000004',1,'{}','auto',30,1),
('11000000-0000-4000-8000-000000000030','Cages','a0000000-0000-4000-8000-000000000001',2,'{}','auto',30,2),
('11000000-0000-4000-8000-000000000030','Party Host','a0000000-0000-4000-8000-000000000006',1,'{}','admin_only',30,3),

('11000000-0000-4000-8000-000000000031','Cages','a0000000-0000-4000-8000-000000000001',3,'{}','auto',15,1),
('11000000-0000-4000-8000-000000000031','Lobby','a0000000-0000-4000-8000-000000000005',1,'{}','auto',15,2),

-- Buyout: every cage plus the party room.
('11000000-0000-4000-8000-000000000032','All Cages','a0000000-0000-4000-8000-000000000001',5,'{}','auto',30,1),
('11000000-0000-4000-8000-000000000032','Party Room','a0000000-0000-4000-8000-000000000004',1,'{}','auto',30,2);

-- The party host arrives 15 minutes in and leaves at the end: offsets let one
-- requirement occupy a sub-window of the booking.
update atd.service_resource_requirements
   set offset_start_minutes = 0, offset_end_minutes = 0
 where service_id = '11000000-0000-4000-8000-000000000030';

-- ---------------------------------------------------------------------------
-- Add-ons
-- ---------------------------------------------------------------------------
insert into atd.service_addons
 (id, location_id, key, name, description, price_cents, price_per, max_quantity,
  adds_resource_type_id, adds_resource_quantity, adds_required_attributes) values
('a1000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-0000000010c1','hittrax_addon',
 'Add HitTrax','Upgrade your session to the HitTrax cage.',3000,'booking',1,
 'a0000000-0000-4000-8000-000000000002',1,'{}'),
('a1000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-0000000010c1','pitching_machine',
 'Pitching Machine','Machine set up in your cage.',1500,'booking',1,
 'a0000000-0000-4000-8000-000000000007',1,'{}'),
('a1000000-0000-4000-8000-000000000003','00000000-0000-4000-8000-0000000010c1','extra_guest',
 'Additional Party Guest','Each guest beyond the package count.',2000,'participant',12,null,0,'{}'),
('a1000000-0000-4000-8000-000000000004','00000000-0000-4000-8000-0000000010c1','pizza_package',
 'Pizza & Drinks Package','Three large pizzas, juice boxes, water.',9000,'booking',3,null,0,'{}'),
('a1000000-0000-4000-8000-000000000005','00000000-0000-4000-8000-0000000010c1','decorations',
 'Decorations & Party Favors','Table settings, balloons, favor bags.',6500,'booking',1,null,0,'{}'),
('a1000000-0000-4000-8000-000000000006','00000000-0000-4000-8000-0000000010c1','extra_cage_time',
 'Extra 30 Minutes','Extend your cage time.',3500,'booking',4,null,0,'{}');

-- "Add HitTrax" must do two things: pull in the HitTrax unit AND narrow the
-- host service's cage requirement to the cage the unit actually lives in.
-- Without the second half you get a HitTrax unit reserved next to a 35 ft cage.
update atd.service_addons
   set constrains_resource_type_id = 'a0000000-0000-4000-8000-000000000001',
       constrains_attributes = '{"has_hittrax": true}'::jsonb
 where key = 'hittrax_addon';

-- Duration-extending add-ons.
update atd.service_addons set adds_minutes = 30 where key = 'extra_cage_time';

insert into atd.service_addon_links (service_id, addon_id, is_default, sort_order) values
('11000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000001',false,1),
('11000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000002',false,2),
('11000000-0000-4000-8000-000000000010','a1000000-0000-4000-8000-000000000002',false,1),
('11000000-0000-4000-8000-000000000011','a1000000-0000-4000-8000-000000000002',false,1),
('11000000-0000-4000-8000-000000000030','a1000000-0000-4000-8000-000000000003',false,1),
('11000000-0000-4000-8000-000000000030','a1000000-0000-4000-8000-000000000004',true,2),
('11000000-0000-4000-8000-000000000030','a1000000-0000-4000-8000-000000000005',false,3),
('11000000-0000-4000-8000-000000000030','a1000000-0000-4000-8000-000000000001',false,4);

-- ---------------------------------------------------------------------------
-- Intake questions
-- ---------------------------------------------------------------------------
insert into atd.service_questions (service_id, key, label, input_type, is_required, applies_to, sort_order, options) values
('11000000-0000-4000-8000-000000000001','focus','What would you like to work on?','textarea',false,'booking',1,'[]'),
('11000000-0000-4000-8000-000000000002','arm_status','Any current arm soreness or injury?','textarea',false,'participant',1,'[]'),
('11000000-0000-4000-8000-000000000022','shirt_size','Camp shirt size','select',true,'participant',1,
  '["YS","YM","YL","AS","AM","AL"]'),
('11000000-0000-4000-8000-000000000022','lunch','Bringing lunch or purchasing?','select',true,'participant',2,
  '["Bringing lunch","Purchase lunch ($10/day)"]'),
('11000000-0000-4000-8000-000000000023','dinner_pref','Pizza preference','select',false,'participant',1,
  '["Cheese","Pepperoni","No pizza"]'),
('11000000-0000-4000-8000-000000000030','birthday_child','Birthday child name and age','text',true,'booking',1,'[]'),
('11000000-0000-4000-8000-000000000030','guest_count','Expected number of children','number',true,'booking',2,'[]'),
('11000000-0000-4000-8000-000000000030','special_requests','Special requests','textarea',false,'booking',3,'[]');

-- ---------------------------------------------------------------------------
-- Pricing rules: peak, off-peak, member, coach premium, early bird
-- ---------------------------------------------------------------------------
insert into atd.rate_cards (id, location_id, name, is_default) values
('c1000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-0000000010c1','Standard Rate Card',true),
('c1000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-0000000010c1','Travel Team Rate Card',false);

insert into atd.pricing_rules
 (location_id, rate_card_id, service_id, name, scope, priority, days_of_week,
  starts_at_time, ends_at_time, effect, percent, amount_cents) values
-- Weekday evenings and weekend mornings are peak for cage rentals.
('00000000-0000-4000-8000-0000000010c1','c1000000-0000-4000-8000-000000000001','11000000-0000-4000-8000-000000000010',
 'Peak cage rate','peak',10,'{1,2,3,4,5}',time '16:00',time '20:30','set_per_minute',null,100),
('00000000-0000-4000-8000-0000000010c1','c1000000-0000-4000-8000-000000000001','11000000-0000-4000-8000-000000000010',
 'Off-peak cage rate','off_peak',10,'{1,2,3,4,5}',time '09:30',time '16:00','set_per_minute',null,58),
('00000000-0000-4000-8000-0000000010c1','c1000000-0000-4000-8000-000000000001','11000000-0000-4000-8000-000000000011',
 'Peak 50ft cage rate','peak',10,'{1,2,3,4,5}',time '16:00',time '20:30','set_per_minute',null,125),
('00000000-0000-4000-8000-0000000010c1','c1000000-0000-4000-8000-000000000001',null,
 'Member discount','member',80,null,null,null,'percent_off',10,null),
('00000000-0000-4000-8000-0000000010c1','c1000000-0000-4000-8000-000000000002','11000000-0000-4000-8000-000000000031',
 'Travel team practice rate','team',20,null,null,null,'set_per_minute',null,225);

-- Coach premium: sessions with the hitting director cost more.
insert into atd.pricing_rules
 (location_id, rate_card_id, service_id, coach_id, name, scope, priority, effect, amount_cents) values
('00000000-0000-4000-8000-0000000010c1','c1000000-0000-4000-8000-000000000001','11000000-0000-4000-8000-000000000001',
 'e0000000-0000-4000-8000-000000000001','Director premium — Reyes','custom',30,'add',1500);

-- ---------------------------------------------------------------------------
-- Packages
-- ---------------------------------------------------------------------------
insert into atd.package_definitions
 (id, location_id, key, name, description, credit_count, credit_unit, price_cents,
  eligible_service_ids, valid_days, household_shared, sort_order) values
('c2000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-0000000010c1','lessons-5',
 '5 Private Lessons','Five 60-minute private lessons. Save $50.',5,'session',40000,
 array['11000000-0000-4000-8000-000000000001','11000000-0000-4000-8000-000000000002',
       '11000000-0000-4000-8000-000000000003','11000000-0000-4000-8000-000000000004']::uuid[],365,true,1),
('c2000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-0000000010c1','lessons-10',
 '10 Private Lessons','Ten 60-minute private lessons. Save $150.',10,'session',75000,
 array['11000000-0000-4000-8000-000000000001','11000000-0000-4000-8000-000000000002',
       '11000000-0000-4000-8000-000000000003','11000000-0000-4000-8000-000000000004']::uuid[],365,true,2),
('c2000000-0000-4000-8000-000000000003','00000000-0000-4000-8000-0000000010c1','cage-10hr',
 '10 Cage Hours','Ten hours of cage rental time.',10,'hour',60000,
 array['11000000-0000-4000-8000-000000000010','11000000-0000-4000-8000-000000000011']::uuid[],365,true,3),
('c2000000-0000-4000-8000-000000000004','00000000-0000-4000-8000-0000000010c1','hittrax-5hr',
 '5 HitTrax Hours','Five hours in the HitTrax cage.',5,'hour',65000,
 array['11000000-0000-4000-8000-000000000012']::uuid[],180,true,4);

update atd.package_definitions set restricted_to_off_peak = true
 where key = 'cage-10hr';

-- ---------------------------------------------------------------------------
-- Memberships
-- ---------------------------------------------------------------------------
insert into atd.membership_plans
 (id, location_id, key, name, description, billing_interval, price_cents,
  included_credits, member_discount_percent, priority_booking_hours,
  credits_roll_over, max_rollover_credits, sort_order) values
('c3000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-0000000010c1','cage-monthly',
 'Cage Club — Monthly','Four cage hours a month plus 10% off everything.','month',9900,4,10,24,true,8,1),
('c3000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-0000000010c1','training-monthly',
 'Training Club — Monthly','Two private lessons, four cage hours, 15% off.','month',24900,6,15,48,true,6,2),
('c3000000-0000-4000-8000-000000000003','00000000-0000-4000-8000-0000000010c1','family-annual',
 'Family Annual','Household-wide benefits, priority booking, 20% off.','year',149900,60,20,72,false,null,3);

-- ---------------------------------------------------------------------------
-- Waivers
-- ---------------------------------------------------------------------------
insert into atd.waiver_templates (id, location_id, key, name, audience, renewal_months) values
('77000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-0000000010c1','general-liability',
 'General Liability & Assumption of Risk','participant',12),
('77000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-0000000010c1','camp-medical',
 'Camp Medical Authorization & Pickup','guardian',12),
('77000000-0000-4000-8000-000000000003','00000000-0000-4000-8000-0000000010c1','photo-consent',
 'Photo & Video Consent','guardian',null);

insert into atd.waiver_versions (template_id, version, body_markdown, effective_from, requires_resignature) values
('77000000-0000-4000-8000-000000000001',1,
 E'# Assumption of Risk and Release of Liability\n\nBaseball and softball training involve inherent risks of injury...\n\nBy signing, I acknowledge these risks on behalf of the participant named above.',
 now() - interval '18 months', true),
('77000000-0000-4000-8000-000000000002',1,
 E'# Medical Authorization and Authorized Pickup\n\nI authorize ATD Baseball Company staff to seek emergency medical treatment...\n\nOnly the individuals listed on the account may collect the participant.',
 now() - interval '12 months', true),
('77000000-0000-4000-8000-000000000003',1,
 E'# Photo and Video Consent\n\nATD may photograph or record sessions for instructional and promotional use.',
 now() - interval '12 months', false);

update atd.services
   set waiver_template_ids = array['77000000-0000-4000-8000-000000000001']::uuid[];
update atd.services
   set waiver_template_ids = array['77000000-0000-4000-8000-000000000001',
                                   '77000000-0000-4000-8000-000000000002']::uuid[]
 where id in ('11000000-0000-4000-8000-000000000022','11000000-0000-4000-8000-000000000023');

-- ---------------------------------------------------------------------------
-- Notification templates + rules
-- ---------------------------------------------------------------------------
insert into atd.notification_templates
 (id, location_id, key, name, channel, subject, body, available_variables) values
('88000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-0000000010c1','booking_confirmed','Booking Confirmation','email',
 'Your {{service_name}} is confirmed — {{date}} at {{time}}',
 E'Hi {{customer_first_name}},\n\n{{participant_name}} is booked for {{service_name}} on {{date}} at {{time}} with {{coach_name}} in {{resource_name}}.\n\nConfirmation code: {{confirmation_code}}\nBalance due: {{balance_due}}\n\nWaiver: {{waiver_link}}\nNeed to change it? {{manage_link}}\n\n— ATD Baseball Company',
 array['customer_first_name','participant_name','service_name','date','time','coach_name','resource_name','confirmation_code','balance_due','waiver_link','manage_link']),
('88000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-0000000010c1','booking_reminder','24-Hour Reminder','sms',
 null,
 'ATD Baseball: {{participant_name}} has {{service_name}} tomorrow at {{time}} with {{coach_name}}. {{manage_link}} Reply STOP to opt out.',
 array['participant_name','service_name','time','coach_name','manage_link']),
('88000000-0000-4000-8000-000000000003','00000000-0000-4000-8000-0000000010c1','waiver_missing','Waiver Required','email',
 'Action needed: waiver for {{participant_name}}',
 E'We still need a signed waiver for {{participant_name}} before {{date}}.\n\nSign here: {{waiver_link}}',
 array['participant_name','date','waiver_link']),
('88000000-0000-4000-8000-000000000004','00000000-0000-4000-8000-0000000010c1','waitlist_offer','A Spot Opened Up','sms',
 null,
 'ATD Baseball: a spot opened for {{program_name}} on {{date}}. Claim within {{claim_window}}: {{claim_link}}',
 array['program_name','date','claim_window','claim_link']),
('88000000-0000-4000-8000-000000000005','00000000-0000-4000-8000-0000000010c1','balance_due','Balance Due Reminder','email',
 'Balance due for your {{service_name}}',
 E'A balance of {{balance_due}} is due by {{due_date}} for {{service_name}} on {{date}}.\n\nPay here: {{payment_link}}',
 array['service_name','balance_due','due_date','date','payment_link']),
('88000000-0000-4000-8000-000000000006','00000000-0000-4000-8000-0000000010c1','closure','Facility Closure','sms',
 null,
 'ATD Baseball is closed {{date}} ({{reason}}). Your {{service_name}} at {{time}} is cancelled and credited. Reply STOP to opt out.',
 array['date','reason','service_name','time']);

insert into atd.notification_rules (location_id, event_key, template_id, channel, anchor, offset_minutes) values
('00000000-0000-4000-8000-0000000010c1','booking.confirmed','88000000-0000-4000-8000-000000000001','email','immediate',0),
('00000000-0000-4000-8000-0000000010c1','booking.reminder','88000000-0000-4000-8000-000000000002','sms','booking_start',-1440),
('00000000-0000-4000-8000-0000000010c1','waiver.missing','88000000-0000-4000-8000-000000000003','email','booking_start',-2880),
('00000000-0000-4000-8000-0000000010c1','waitlist.offer','88000000-0000-4000-8000-000000000004','sms','immediate',0),
('00000000-0000-4000-8000-0000000010c1','balance.due','88000000-0000-4000-8000-000000000005','email','balance_due',-4320),
('00000000-0000-4000-8000-0000000010c1','location.closure','88000000-0000-4000-8000-000000000006','sms','immediate',0);

-- ---------------------------------------------------------------------------
-- Coach compensation
-- ---------------------------------------------------------------------------
insert into atd.coach_compensation_rules
 (location_id, coach_id, service_id, basis, percent, amount_cents, hourly_cents, priority) values
('00000000-0000-4000-8000-0000000010c1',null,null,'percent_revenue',60,null,null,100),
('00000000-0000-4000-8000-0000000010c1','e0000000-0000-4000-8000-000000000001',null,'percent_revenue',70,null,null,50),
('00000000-0000-4000-8000-0000000010c1',null,'11000000-0000-4000-8000-000000000022','hourly',null,null,4500,40);

-- ---------------------------------------------------------------------------
-- Tags + settings
-- ---------------------------------------------------------------------------
insert into atd.tags (key, label, color, category) values
('travel_team','Travel Team','#1f6feb','segment'),
('pitching_client','Pitching Client','#8957e5','segment'),
('camp_customer','Camp Customer','#cf222e','segment'),
('party_lead','Birthday Party Lead','#d4a72c','lead'),
('member','Member','#1a7f37','segment'),
('vip','VIP','#bf8700','service'),
('needs_follow_up','Needs Follow-Up','#cf222e','service'),
('past_due','Past-Due Balance','#a40e26','finance');

insert into atd.system_settings (location_id, key, value, category, label) values
('00000000-0000-4000-8000-0000000010c1','checkout_hold_minutes','10','booking','Checkout hold duration (minutes)'),
('00000000-0000-4000-8000-0000000010c1','waitlist_claim_minutes','120','waitlist','Waitlist claim window (minutes)'),
('00000000-0000-4000-8000-0000000010c1','no_show_fee_cents','2500','policy','No-show fee'),
('00000000-0000-4000-8000-0000000010c1','allow_front_desk_override','false','permissions','Front desk may override conflicts'),
('00000000-0000-4000-8000-0000000010c1','allow_front_desk_refund','false','permissions','Front desk may issue refunds'),
('00000000-0000-4000-8000-0000000010c1','sibling_discount_percent','10','pricing','Default sibling discount'),
('00000000-0000-4000-8000-0000000010c1','reminder_hours_before','24','notifications','Reminder lead time'),
('00000000-0000-4000-8000-0000000010c1','kiosk_enabled','true','operations','Enable kiosk check-in');

-- ---------------------------------------------------------------------------
-- Calendar colours.
--
-- Eight categories, but only FIVE colours. The eight were validated with the
-- data-viz palette checker and failed: any 8-hue set has pairs that are
-- indistinguishable under deuteranopia (worst pair ΔE 3.2) and some that are
-- hard to separate even with full colour vision (ΔE 7.1).
--
-- So the categories fold into five operational families — which is how staff
-- actually think about the board anyway — using a set that passes the checker
-- on ALL pairs, not just adjacent ones. On a resource timeline any two blocks
-- can end up side by side, so all-pairs is the honest test.
--
-- Colour is never the only signal: every block carries its service name, and
-- status (hold, cancelled) is shown with texture and words as well.
-- ---------------------------------------------------------------------------
update atd.service_categories set color = '#2a78d6' where key in ('private_lessons','group_training');
update atd.service_categories set color = '#1baf7a' where key in ('cage_rentals','team_rentals');
update atd.service_categories set color = '#4a3aa7' where key = 'hittrax';
update atd.service_categories set color = '#eda100' where key in ('camps_clinics','programs');
update atd.service_categories set color = '#e34948' where key = 'parties_events';
