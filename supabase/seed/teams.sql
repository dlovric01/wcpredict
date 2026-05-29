-- Teams seed (temporary IDs 1-48)
-- These IDs are placeholders and will be replaced by BALLDONTLIE team IDs
-- once poll_fixtures runs and resolves the real API identifiers.
-- WC2026 group assignments are based on the 2024 FIFA draw (some TBD slots remain).
INSERT INTO public.teams (id, name, code, flag_url, group_letter) VALUES
  -- Group A
  (1,  'USA',         'USA', 'https://flagcdn.com/48x36/us.png',  'A'),
  (2,  'Panama',      'PAN', 'https://flagcdn.com/48x36/pa.png',  'A'),
  (3,  'Ecuador',     'ECU', 'https://flagcdn.com/48x36/ec.png',  'A'),
  (4,  'TBD-A4',      'TBD', '/flags/tbd.png',                    'A'),

  -- Group B
  (5,  'Mexico',      'MEX', 'https://flagcdn.com/48x36/mx.png',  'B'),
  (6,  'Jamaica',     'JAM', 'https://flagcdn.com/48x36/jm.png',  'B'),
  (7,  'Venezuela',   'VEN', 'https://flagcdn.com/48x36/ve.png',  'B'),
  (8,  'TBD-B4',      'TBD', '/flags/tbd.png',                    'B'),

  -- Group C
  (9,  'Canada',      'CAN', 'https://flagcdn.com/48x36/ca.png',  'C'),
  (10, 'Colombia',    'COL', 'https://flagcdn.com/48x36/co.png',  'C'),
  (11, 'Honduras',    'HND', 'https://flagcdn.com/48x36/hn.png',  'C'),
  (12, 'TBD-C4',      'TBD', '/flags/tbd.png',                    'C'),

  -- Group D
  (13, 'Argentina',   'ARG', 'https://flagcdn.com/48x36/ar.png',  'D'),
  (14, 'Peru',        'PER', 'https://flagcdn.com/48x36/pe.png',  'D'),
  (15, 'Chile',       'CHI', 'https://flagcdn.com/48x36/cl.png',  'D'),
  (16, 'TBD-D4',      'TBD', '/flags/tbd.png',                    'D'),

  -- Group E
  (17, 'Brazil',      'BRA', 'https://flagcdn.com/48x36/br.png',  'E'),
  (18, 'Paraguay',    'PAR', 'https://flagcdn.com/48x36/py.png',  'E'),
  (19, 'Bolivia',     'BOL', 'https://flagcdn.com/48x36/bo.png',  'E'),
  (20, 'TBD-E4',      'TBD', '/flags/tbd.png',                    'E'),

  -- Group F
  (21, 'Germany',     'GER', 'https://flagcdn.com/48x36/de.png',  'F'),
  (22, 'Portugal',    'POR', 'https://flagcdn.com/48x36/pt.png',  'F'),
  (23, 'Turkey',      'TUR', 'https://flagcdn.com/48x36/tr.png',  'F'),
  (24, 'TBD-F4',      'TBD', '/flags/tbd.png',                    'F'),

  -- Group G
  (25, 'Spain',       'ESP', 'https://flagcdn.com/48x36/es.png',  'G'),
  (26, 'France',      'FRA', 'https://flagcdn.com/48x36/fr.png',  'G'),
  (27, 'Belgium',     'BEL', 'https://flagcdn.com/48x36/be.png',  'G'),
  (28, 'TBD-G4',      'TBD', '/flags/tbd.png',                    'G'),

  -- Group H
  (29, 'England',     'ENG', 'https://flagcdn.com/48x36/gb-eng.png', 'H'),
  (30, 'Netherlands', 'NED', 'https://flagcdn.com/48x36/nl.png',  'H'),
  (31, 'Switzerland', 'SUI', 'https://flagcdn.com/48x36/ch.png',  'H'),
  (32, 'TBD-H4',      'TBD', '/flags/tbd.png',                    'H'),

  -- Group I
  (33, 'Uruguay',     'URU', 'https://flagcdn.com/48x36/uy.png',  'I'),
  (34, 'Saudi Arabia','KSA', 'https://flagcdn.com/48x36/sa.png',  'I'),
  (35, 'TBD-I3',      'TBD', '/flags/tbd.png',                    'I'),
  (36, 'TBD-I4',      'TBD', '/flags/tbd.png',                    'I'),

  -- Group J
  (37, 'Japan',       'JPN', 'https://flagcdn.com/48x36/jp.png',  'J'),
  (38, 'Australia',   'AUS', 'https://flagcdn.com/48x36/au.png',  'J'),
  (39, 'TBD-J3',      'TBD', '/flags/tbd.png',                    'J'),
  (40, 'TBD-J4',      'TBD', '/flags/tbd.png',                    'J'),

  -- Group K
  (41, 'Morocco',     'MAR', 'https://flagcdn.com/48x36/ma.png',  'K'),
  (42, 'Cameroon',    'CMR', 'https://flagcdn.com/48x36/cm.png',  'K'),
  (43, 'TBD-K3',      'TBD', '/flags/tbd.png',                    'K'),
  (44, 'TBD-K4',      'TBD', '/flags/tbd.png',                    'K'),

  -- Group L
  (45, 'South Korea', 'KOR', 'https://flagcdn.com/48x36/kr.png',  'L'),
  (46, 'Iran',        'IRN', 'https://flagcdn.com/48x36/ir.png',  'L'),
  (47, 'TBD-L3',      'TBD', '/flags/tbd.png',                    'L'),
  (48, 'TBD-L4',      'TBD', '/flags/tbd.png',                    'L')
ON CONFLICT (id) DO UPDATE SET
  name         = EXCLUDED.name,
  code         = EXCLUDED.code,
  flag_url     = EXCLUDED.flag_url,
  group_letter = EXCLUDED.group_letter;
