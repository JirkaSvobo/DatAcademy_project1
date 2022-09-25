-- ------------------------------------------------------------------------
--  tabulka pro platy a ceny
-- ------------------------------------------------------------------------

CREATE TABLE t_Jiri_Svoboda_projekt_SQL_prim (
	Rok_mzdy int(8), 
	Odvetvi varchar(128),
	Prum_mzdaKc double,
	Rok_ceny int(8),
	Potravina varchar(128),
    Prum_cenaKc double, 
	Mnozstvi double,
	Jednotka varchar(4)
);


INSERT INTO t_Jiri_Svoboda_projekt_SQL_prim (Rok_mzdy, Odvetvi, Prum_mzdaKc, Rok_ceny, Potravina, Prum_cenaKc, Mnozstvi, Jednotka)
SELECT 
		cp.payroll_year AS Rok_mzdy, cpib.name  AS Odvetvi,
		ROUND(AVG(cp.value),0) AS Prum_mzdaKc,
		pr.rok AS Rok_ceny, pr.potravina AS Potravina, pr.prumCena AS Prum_cenaKc, 
		pr.cenaMnozstvi AS Mnozstvi, pr.cenaJednotka AS Jednotka
	FROM czechia_payroll cp 
	JOIN czechia_payroll_industry_branch cpib 
	 	ON cp.industry_branch_code = cpib.code 
	JOIN czechia_payroll_calculation cpc 
	 	ON cp.calculation_code = cpc.code 
	JOIN czechia_payroll_value_type cpvt 
	 	ON cp.value_type_code = cpvt.code
	JOIN (
		SELECT ROUND(AVG(cp.value),2) as prumCena, YEAR(cp.date_from) AS rok, cpc.name AS potravina, 
			cpc.price_value AS cenaMnozstvi, cpc.price_unit AS cenaJednotka 
		FROM czechia_price cp
		JOIN czechia_price_category cpc 
			ON cpc.code = cp.category_code
		WHERE cp.region_code IS NOT NULL AND YEAR(cp.date_from) -- IN (2006,2018) AND  cpc.name IN ('Mléko polotučné pasterované', 'Chléb konzumní kmínový')
		GROUP BY YEAR(cp.date_from), cpc.name -- takhle je to prumer pres roky a regiony AND  cpc.name IN ('Mléko polotučné pasterované', 'Chléb konzumní kmínový')
		ORDER BY cpc.name) AS pr
		ON cp.payroll_year = pr.rok
	WHERE cp.payroll_year IN (
		SELECT DISTINCT cp.payroll_year 
		FROM czechia_payroll cp2
		) AND cpvt.name = 'Průměrná hrubá mzda na zaměstnance' AND cpc.name = 'fyzický' AND cp.industry_branch_code IS NOT NULL 
	GROUP BY cp.industry_branch_code, cp.payroll_year, pr.potravina
	ORDER BY cpib.name,cp.payroll_year;

SELECT *
FROM t_Jiri_Svoboda_projekt_SQL_prim


-- ------------------------------------------------------------------------
--  tabulka pro dodatečná data o evropských státech (jmeno, populace, HDP ...)
-- ------------------------------------------------------------------------
CREATE TABLE t_Jiri_Svoboda_projekt_SQL_sec (
	Zeme_Evropy varchar(128),
	Rok int(8),
	Populace double,
    HDP double, 
	IndexGINI double,
	Daně double
);

INSERT INTO t_Jiri_Svoboda_projekt_SQL_sec (Zeme_Evropy, Rok, Populace, HDP, IndexGINI, Daně)
SELECT 
	e.country, e.`year`, e.population, e.GDP, e.gini, e.taxes 
	FROM economies e 
	WHERE e.country IN (
		SELECT c.country
		FROM countries c 
		WHERE continent = 'Europe'
		)
	ORDER BY e.country, e.`year`; 

SELECT *
FROM t_Jiri_Svoboda_projekt_SQL_sec


-- ------------------------------------------------------------------------
-- 1. Rostou v průběhu let mzdy ve všech odvětvích, nebo v některých klesají?
-- ------------------------------------------------------------------------

WITH
	sqr (Rok1, Odvetvi1, prum_Mzda_Kc1, rono) AS (
	WITH
		sq (Rok, Odvetvi, prum_Mzda_Kc) AS (
		SELECT DISTINCT Rok_mzdy, Odvetvi, Prum_mzdaKc
		FROM t_Jiri_Svoboda_projekt_SQL_prim
		)
	SELECT sq1.Rok, sq1.Odvetvi, sq1.prum_Mzda_Kc, row_number() over (partition by sq1.Odvetvi order by  sq1.Rok) AS rn1 
	FROM   sq sq1
    )
SELECT sqr1.Odvetvi1 AS Odvetvi, sqr1.Rok1 AS Rok, sqr1.prum_Mzda_Kc1 AS prum_Mzda_Kc, sqr2.Rok1 AS Rok_pred, 
	sqr2.prum_Mzda_Kc1 AS prum_Mzda_Kc_pred, ROUND((sqr1.prum_Mzda_Kc1-sqr2.prum_Mzda_Kc1)/sqr2.prum_Mzda_Kc1*100,1) AS proc_narust
FROM sqr sqr1
JOIN sqr sqr2
	ON sqr1.rono = sqr2.rono+1 AND sqr1.Odvetvi1 = sqr2.Odvetvi1
WHERE(ROUND((sqr1.prum_Mzda_Kc1-sqr2.prum_Mzda_Kc1)/sqr2.prum_Mzda_Kc1*100,1)) < 0  -- tohle je pro ziskani mezirocniho poklesu mzdy
ORDER BY sqr1.Rok1;


-- ------------------------------------------------------------------------
-- 2. Kolik je možné si koupit litrů mléka a kilogramů chleba za první a poslední srovnatelné období v dostupných datech cen a mezd?
-- ------------------------------------------------------------------------

SELECT 
	Rok_mzdy AS Rok, ROUND(AVG(Prum_mzdaKc),0) as prum_mzda_Kc, Potravina, Prum_cenaKc,
	ROUND((ROUND(AVG(Prum_mzdaKc),0)/Prum_cenaKc),0) AS mnozstviZaMzdu
FROM t_Jiri_Svoboda_projekt_SQL_prim
WHERE Rok_mzdy IN ((SELECT MIN(Rok_mzdy) FROM t_Jiri_Svoboda_projekt_SQL_prim),(SELECT MAX(Rok_mzdy) FROM t_Jiri_Svoboda_projekt_SQL_prim))
	AND Potravina IN ('Mléko polotučné pasterované', 'Chléb konzumní kmínový')
GROUP BY Rok_mzdy,Potravina;


-- ------------------------------------------------------------------------
-- 3. Která kategorie potravin zdražuje nejpomaleji (je u ní nejnižší percentuální meziroční nárůst)?
-- ------------------------------------------------------------------------

-- Alternativa: meziroční nárůst po jednotlivých letech. Seřazeno podle let pro každou potravinu zvlášť
-- NEVÝHODA - je toho moc ve výpisu, je to nepřehledné
-- Pro závěry nepoužito, zde jen pro případ nutnosti doplnit detaily
 WITH
	sqr (Rok1, Potravina1, Prum_cena_Kc1, rono) AS (
	WITH
		sq (Rok , Potravina , Prum_cena_Kc) AS (
		SELECT DISTINCT Rok_ceny , Potravina , Prum_cenaKc 
		FROM t_Jiri_Svoboda_projekt_SQL_prim
		)
	SELECT sq1.Rok, sq1.Potravina, sq1.Prum_cena_Kc, row_number() over (partition by sq1.Potravina order by  sq1.Rok) AS rn1 
	FROM   sq sq1
    )
SELECT sqr1.Potravina1 AS Potravina, sqr1.Rok1 AS Rok, sqr1.Prum_cena_Kc1 AS prum_Cena_Kc, sqr2.Rok1 AS Rok_pred, 
	sqr2.prum_Cena_Kc1 AS prum_Cena_Kc_pred, ROUND((sqr1.prum_Cena_Kc1-sqr2.prum_Cena_Kc1)/sqr2.prum_Cena_Kc1*100,1) AS proc_narust
FROM sqr sqr1
JOIN sqr sqr2
	ON sqr1.rono = sqr2.rono+1 AND sqr1.Potravina1 = sqr2.Potravina1
ORDER BY potravina, Rok;

-- Proto vznikla alternativa, kde je meziroční nárůst po jednotlivých letech zprůměrován a dále je uveden max a min meziroční nárůst ve sledovaném období

WITH
	sqr (Rok1, Potravina1, Prum_cena_Kc1, rono) AS (
	WITH
		sq (Rok , Potravina , Prum_cena_Kc) AS (
		SELECT DISTINCT Rok_ceny , Potravina , Prum_cenaKc 
		FROM t_Jiri_Svoboda_projekt_SQL_prim
		)
	SELECT sq1.Rok, sq1.Potravina, sq1.Prum_cena_Kc, row_number() over (partition by sq1.Potravina order by  sq1.Rok) AS rn1 
	FROM   sq sq1
    )
SELECT sqr1.Potravina1 AS Potravina, AVG((sqr1.prum_Cena_Kc1-sqr2.prum_Cena_Kc1)/sqr2.prum_Cena_Kc1*100) AS AVG_proc_narust,
	MAX((sqr1.prum_Cena_Kc1-sqr2.prum_Cena_Kc1)/sqr2.prum_Cena_Kc1*100) AS MAX_proc_narust,
	MIN((sqr1.prum_Cena_Kc1-sqr2.prum_Cena_Kc1)/sqr2.prum_Cena_Kc1*100) AS MIN_proc_narust
FROM sqr sqr1
JOIN sqr sqr2
	ON sqr1.rono = sqr2.rono+1 AND sqr1.Potravina1 = sqr2.Potravina1
GROUP BY Potravina
ORDER BY AVG_proc_narust;



-- ------------------------------------------------------------------------
-- 4. Existuje rok, ve kterém byl meziroční nárůst cen potravin výrazně vyšší než růst mezd (větší než 10 %)?
-- ------------------------------------------------------------------------


WITH cena1 (rokCena, procNarustCena) AS (
	WITH
		sqr (Rok1, Potravina1, prum_Cena_Kc1, rono) AS (
		WITH
			sq (Rok, Potravina, prum_Cena_Kc) AS (
			SELECT DISTINCT Rok_mzdy, Potravina, Prum_cenaKc
			FROM t_Jiri_Svoboda_projekt_SQL_prim
			)
		SELECT sq1.Rok, sq1.Potravina, sq1.prum_Cena_Kc, row_number() over (partition by sq1.Potravina order by  sq1.Rok) AS rn1 
		FROM   sq sq1
	    )
	SELECT sqr1.Rok1 AS RokCena, ROUND(AVG((sqr1.prum_Cena_Kc1-sqr2.prum_Cena_Kc1)/sqr2.prum_Cena_Kc1*100),1) AS proc_narust_cena
	FROM sqr sqr1
	JOIN sqr sqr2
		ON sqr1.rono = sqr2.rono+1 AND sqr1.Potravina1 = sqr2.Potravina1
	GROUP BY sqr1.Rok1
	ORDER BY sqr1.Rok1
	)
SELECT cena.rokCena, cena.procNarustCena, mzda.proc_narust_mzdy, (proc_narust_mzdy-cena.procNarustCena) AS 'narustMezd_mensiNez_narustcen_O:'
FROM cena1 as cena 
JOIN
	(
	WITH
		sqr (Rok1, Odvetvi1, prum_Mzda_Kc1, rono) AS (
		WITH
			sq (Rok, Odvetvi, prum_Mzda_Kc) AS (
			SELECT DISTINCT Rok_mzdy, Odvetvi, Prum_mzdaKc
			FROM t_Jiri_Svoboda_projekt_SQL_prim
			)
		SELECT sq1.Rok, sq1.Odvetvi, sq1.prum_Mzda_Kc, row_number() over (partition by sq1.Odvetvi order by  sq1.Rok) AS rn1 
		FROM   sq sq1
	    )
	SELECT sqr1.Rok1 AS Rok, ROUND(AVG((sqr1.prum_Mzda_Kc1-sqr2.prum_Mzda_Kc1)/sqr2.prum_Mzda_Kc1*100),1) AS proc_narust_mzdy
	FROM sqr sqr1
	JOIN sqr sqr2
		ON sqr1.rono = sqr2.rono+1 AND sqr1.Odvetvi1 = sqr2.Odvetvi1
	GROUP BY sqr1.Rok1
	ORDER BY sqr1.Rok1
	) AS mzda
	ON mzda.Rok = cena.rokCena


-- ------------------------------------------------------------------------
--  5. Má výška HDP vliv na změny ve mzdách a cenách potravin? Neboli, pokud HDP vzroste výrazněji v jednom roce, projeví se to na cenách potravin či mzdách ve stejném nebo následujícím roce výraznějším růstem?
-- ------------------------------------------------------------------------

WITH cena1 (rokCena, procNarustCena) AS (
	WITH
		sqr (Rok1, Potravina1, prum_Cena_Kc1, rono) AS (
		WITH
			sq (Rok, Potravina, prum_Cena_Kc) AS (
			SELECT DISTINCT Rok_mzdy, Potravina, Prum_cenaKc
			FROM t_Jiri_Svoboda_projekt_SQL_prim
			)
		SELECT sq1.Rok, sq1.Potravina, sq1.prum_Cena_Kc, row_number() over (partition by sq1.Potravina order by  sq1.Rok) AS rn1 
		FROM   sq sq1
	    )
	SELECT sqr1.Rok1 AS RokCena, ROUND(AVG((sqr1.prum_Cena_Kc1-sqr2.prum_Cena_Kc1)/sqr2.prum_Cena_Kc1*100),1) AS proc_narust_cena
	FROM sqr sqr1
	JOIN sqr sqr2
		ON sqr1.rono = sqr2.rono+1 AND sqr1.Potravina1 = sqr2.Potravina1
	GROUP BY sqr1.Rok1
	ORDER BY sqr1.Rok1
	)
SELECT cena.rokCena, cena.procNarustCena, mzda.proc_narust_mzdy, hdphdp.proc_narust_HDP -- FINALNI querry 
FROM cena1 as cena 
JOIN
	(
	WITH
		sqr (Rok1, Odvetvi1, prum_Mzda_Kc1, rono) AS (
		WITH
			sq (Rok, Odvetvi, prum_Mzda_Kc) AS (
			SELECT DISTINCT Rok_mzdy, Odvetvi, Prum_mzdaKc
			FROM t_Jiri_Svoboda_projekt_SQL_prim
			)
		SELECT sq1.Rok, sq1.Odvetvi, sq1.prum_Mzda_Kc, row_number() over (partition by sq1.Odvetvi order by  sq1.Rok) AS rn1 
		FROM   sq sq1
	    )
	SELECT sqr1.Rok1 AS Rok, ROUND(AVG((sqr1.prum_Mzda_Kc1-sqr2.prum_Mzda_Kc1)/sqr2.prum_Mzda_Kc1*100),1) AS proc_narust_mzdy
	FROM sqr sqr1
	JOIN sqr sqr2
		ON sqr1.rono = sqr2.rono+1 AND sqr1.Odvetvi1 = sqr2.Odvetvi1
	GROUP BY sqr1.Rok1
	ORDER BY sqr1.Rok1
	) AS mzda
	ON mzda.Rok = cena.rokCena
JOIN 
	(
	WITH
		sbqr (ZemeHDP, RokHDP, valHDP, rowNo) AS (	
		WITH
		sqHDP (Zeme_hdp, Rok_hdp, HDP_hdp) AS (
			SELECT Zeme_Evropy, Rok, HDP
			FROM t_Jiri_Svoboda_projekt_SQL_sec
			WHERE Zeme_Evropy = 'Czech Republic' AND Rok IN (
				SELECT DISTINCT Rok_mzdy
				FROM t_Jiri_Svoboda_projekt_SQL_prim
				)
			ORDER BY Rok
			) 
		SELECT sh1.Zeme_hdp, sh1.Rok_hdp, sh1.HDP_hdp, row_number() over (partition by sh1.Zeme_hdp order by sh1.Rok_hdp) AS rNo 
		FROM sqHDP sh1
	)
	SELECT sbqr1.RokHDP AS RokHDP, sbqr1.valHDP AS valHDP, sbqr2.RokHDP AS RokHDP_predchozi, sbqr2.valHDP AS valHDP_predchozi,
		ROUND((sbqr1.valHDP-sbqr2.valHDP)/sbqr2.valHDP*100,2) AS proc_narust_HDP
	FROM sbqr sbqr1
	JOIN sbqr sbqr2
		on sbqr1.rowNo = sbqr2.rowNo+1	
	) AS hdphdp
	ON hdphdp.RokHDP= mzda.Rok
	
