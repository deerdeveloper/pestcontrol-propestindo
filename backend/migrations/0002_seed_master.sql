-- Data master awal dari template Excel Propestindo, ejaan sudah dirapikan.

INSERT INTO building_types (name, default_areas) VALUES
('Pabrik',        ARRAY['Area Produksi','Area Packing','Area Mixing','Gudang','Loading Dock','Pantry','Toilet','Ruang Loker','Perimeter Luar','Parkiran','Genset','Panel Listrik']),
('Kantor',        ARRAY['Lobi Utama','Pintu Masuk','Ruang Meeting','Pantry','Toilet','Koridor','Plafon','Parkiran','Basement','Tangga Darurat','Perimeter Luar']),
('Hotel',         ARRAY['Lobi Utama','Ballroom','Ruang Meeting','Dapur','Kamar Tamu','Koridor','Taman','Basement','Tangga Darurat','Area Sampah']),
('Rumah Tinggal', ARRAY['Kamar','Ruang Tamu','Ruang Keluarga','Dapur','Kamar Mandi','Taman','Plafon','Gudang']),
('Gudang',        ARRAY['Area Penyimpanan','Loading Dock','Kantor Gudang','Toilet','Perimeter Luar']);

INSERT INTO pest_types (name_id, name_en, pest_group, icon) VALUES
('Kecoa',  'Cockroach', 'Serangga merayap', 'cockroach'),
('Semut',  'Ant',       'Serangga merayap', 'ant'),
('Lalat',  'Fly',       'Serangga terbang', 'fly'),
('Nyamuk', 'Mosquito',  'Serangga terbang', 'mosquito'),
('Tikus',  'Rodent',    'Rodensia',         'rat'),
('Rayap',  'Termite',   'Rayap',            'termite'),
('Tawon',  'Wasp',      'Serangga terbang', 'wasp'),
('Kucing', 'Cat',       'Hewan pengganggu', 'cat'),
('Ular',   'Snake',     'Hewan pengganggu', 'snake'),
('Hama Lainnya', 'Other Pest', 'Lainnya', NULL);

INSERT INTO treatment_methods (name_id, name_en) VALUES
('Penyemprotan Residual',          'Residual Spraying'),
('Gel Baiting & Dusting',          'Gel Baiting & Dusting'),
('Stasiun Umpan Tikus & Perangkap','Rodent Bait Stations & Traps'),
('ULV Misting / Cold Fogging',     'ULV Misting / Cold Fogging'),
('Thermal Fogging',                'Thermal Fogging'),
('Perangkap',                      'Trapping'),
('Injeksi Tanah',                  'Soil Injection System'),
('Sistem Umpan',                   'Baiting System');

INSERT INTO chemicals (trade_name, active_ingredient, chemical_class, unit) VALUES
('Cypermethrin',       'Cypermethrin',       'Piretroid',        'ml'),
('Deltamethrin',       'Deltamethrin',       'Piretroid',        'ml'),
('Lambda-cyhalothrin', 'Lambda-cyhalothrin', 'Piretroid',        'ml'),
('Permethrin',         'Permethrin',         'Piretroid',        'ml'),
('Profenofos',         'Profenofos',         'Organofosfat',     'ml'),
('Fipronil',           'Fipronil',           'Fenilpirazol',     'ml'),
('Imidacloprid',       'Imidacloprid',       'Neonikotinoid',    'gr'),
('Thiamethoxam',       'Thiamethoxam',       'Neonikotinoid',    'gr'),
('Brodifacoum',        'Brodifacoum',        'Rodentisida',      'blok'),
('Bromadiolone',       'Bromadiolone',       'Rodentisida',      'blok'),
('Flocoumafen',        'Flocoumafen',        'Rodentisida',      'blok');

INSERT INTO chemical_doses (chemical_id, method_id, dose_text)
SELECT c.id, m.id, d.dose FROM (VALUES
  ('Cypermethrin', 'Residual Spraying',          '10 ml per 1 liter air'),
  ('Deltamethrin', 'Residual Spraying',          '10 ml per 1 liter air'),
  ('Cypermethrin', 'Thermal Fogging',            '25 ml per 1 liter solar'),
  ('Fipronil',     'Gel Baiting & Dusting',      '10 gr'),
  ('Imidacloprid', 'Gel Baiting & Dusting',      '10 gr'),
  ('Brodifacoum',  'Rodent Bait Stations & Traps','3 blok per stasiun'),
  ('Bromadiolone', 'Rodent Bait Stations & Traps','3 blok per stasiun'),
  ('Fipronil',     'Soil Injection System',      '200 gr')
) AS d(chem, method, dose)
JOIN chemicals c ON c.trade_name = d.chem
JOIN treatment_methods m ON m.name_en = d.method;

INSERT INTO equipment_types (name, code_prefix) VALUES
('Rat Bait Station',   'BS'),
('Insect Light Trap',  'ILT'),
('Glue Trap',          'GT'),
('Live Trap',          'LT');
