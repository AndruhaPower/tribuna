-- Русские названия включённых турниров (D16). Строки турниров созданы в 20261119120000_football.sql.
update competitions set name_ru = 'АПЛ' where code = 'PL';
update competitions set name_ru = 'Ла Лига' where code = 'PD';
update competitions set name_ru = 'Бундеслига' where code = 'BL1';
update competitions set name_ru = 'Серия А' where code = 'SA';
update competitions set name_ru = 'Лига 1' where code = 'FL1';
update competitions set name_ru = 'Лига чемпионов' where code = 'CL';
