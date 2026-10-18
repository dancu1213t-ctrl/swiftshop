begin;
insert into public.merchant_storefronts(category,latitude,longitude) values
('Brew',18.095301428406426,-88.56395246250682),
('Aroma',18.081252196733367,-88.56688290267675),
('Dumpling',18.067995805951213,-88.56307905042725),
('Leo Meatpies',18.074378416952662,-88.56807829803518),
('Salsas',18.088118318415674,-88.5677573146454),
('TFC',18.082628485605387,-88.5622431184445),
('Guerrero',18.09252315891488,-88.56110020087203),
('Urban',18.06826937898531,-88.57071217399431),
('Better Life Pharmacy',18.08322088265203,-88.5600940507101),
('HomeSweetBakes',18.070522945782205,-88.55808732836645),
('Maria',18.083880977603187,-88.56199213802994),
('Shaken',18.08170052940821,-88.56504133563116),
('AddToCart',18.079295476139862,-88.56424639397503)
on conflict(category) do update set latitude=excluded.latitude,longitude=excluded.longitude;
commit;
select category,latitude,longitude from public.merchant_storefronts where category in ('Brew','Aroma','Dumpling','Leo Meatpies','Salsas','TFC','Guerrero','Urban','Better Life Pharmacy','HomeSweetBakes','Maria','Shaken','AddToCart') order by category;