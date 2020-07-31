/**************************************************************************
* Copyright 2016 Observational Health Data Sciences and Informatics (OHDSI)
*
* Licensed under the Apache License, Version 2.0 (the "License");
* you may not use this file except in compliance with the License.
* You may obtain a copy of the License at
*
* http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an "AS IS" BASIS,
* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
* See the License for the specific language governing permissions and
* limitations under the License.
* 
* Authors: Polina Talapova, Timur Vakhitov, Christian Reich
* Date: 2020
**************************************************************************/
--1. Update latest_update field to new date
DO $_$
BEGIN
	PERFORM VOCABULARY_PACK.SetLatestUpdate(
	pVocabularyName			=> 'CPT4',
	pVocabularyDate			=> (SELECT vocabulary_date FROM sources.mrsmap LIMIT 1),
	pVocabularyVersion		=> (SELECT EXTRACT (YEAR FROM vocabulary_date)||' Release' FROM sources.mrsmap LIMIT 1),
	pVocabularyDevSchema	=> 'DEV_CPT4'
);
END $_$;

--2. Truncate all working tables
TRUNCATE TABLE concept_stage;
TRUNCATE TABLE concept_relationship_stage;
TRUNCATE TABLE concept_synonym_stage;
TRUNCATE TABLE pack_content_stage;
TRUNCATE TABLE drug_strength_stage;

--3. Add CPT4 concepts from the source into the concept_stage using the MRCONSO table provided by UMLS  https://www.ncbi.nlm.nih.gov/books/NBK9685/table/ch03.T.concept_names_and_sources_file_mr/
INSERT INTO concept_stage (
	concept_name,
	domain_id,
	vocabulary_id,
	concept_class_id,
	standard_concept,
	concept_code,
	valid_start_date,
	valid_end_date,
	invalid_reason
	)
SELECT DISTINCT vocabulary_pack.CutConceptName(UPPER(SUBSTRING(str FROM 1 FOR 1)) ||substring(str FROM 2 FOR LENGTH(str))) AS concept_name,   -- field with a term name from mrconso
  '' AS domain_id, -- is about to be assigned at the end
	'CPT4' AS vocabulary_id, 
	'CPT4' AS concept_class_id,
	'S' AS standard_concept,
	scui AS concept_code, -- = mrconso.code
	(SELECT latest_update
	FROM vocabulary
	WHERE vocabulary_id = 'CPT4'
	) AS valid_start_date,
	TO_DATE('20991231', 'yyyymmdd') AS valid_end_date,
	NULL AS invalid_reason
FROM sources.mrconso
   JOIN umls_mrsty USING (cui) -- need to add this table to sources https://download.nlm.nih.gov/umls/kss/2020AA/umls-2020AA-metathesaurus.zip => MRSTY
WHERE sab = 'CPT'
	AND suppress NOT IN (
		'E', -- Non-obsolete content marked suppressible by an editor
		'O', -- All obsolete content, whether they are obsolesced by the source or by NLM
		'Y' -- Non-obsolete content deemed suppressible during inversion
		)
	AND tty IN (
		'PT', -- Designated preferred name
		'GLP' -- Global period
		)
; -- 10488

--4. Add CPT4 codes which have no entry in sab = 'CPT' (only sab = 'HCPT'). Note, they are not HCPCS codes! 
INSERT INTO concept_stage (
	concept_name,
	domain_id,
	vocabulary_id,
	concept_class_id,
	standard_concept,
	concept_code,
	valid_start_date,
	valid_end_date,
	invalid_reason
	)
SELECT vocabulary_pack.CutConceptName(UPPER(SUBSTRING(str FROM 1 FOR 1)) ||substring(str FROM 2 FOR LENGTH(str))) AS concept_name,
        '' AS domain_id, -- is about to be assigned at the end
       'CPT4' AS vocabulary_id,
       'CPT4' AS concept_class_id,
       'S' AS standard_concept,
       scui AS concept_code,
       (SELECT latest_update
        	FROM vocabulary
        	WHERE vocabulary_id = 'CPT4') AS valid_start_date,
       TO_DATE('20991231','yyyymmdd') AS valid_end_date,
       NULL as invalid_reason
  FROM sources.mrconso
  JOIN umls_mrsty USING (cui)
  WHERE scui IN (SELECT scui FROM sources.mrconso WHERE sab = 'HCPT')
  AND   scui NOT IN (SELECT scui FROM sources.mrconso WHERE sab = 'CPT')
  AND ((tty = 'PT'
  AND suppress = 'N') or (tty = 'OP' and suppress = 'O'))
 and scui not in (select concept_code from concept where vocabulary_id = 'CPT4'); -- 29

--5. Add Place of Sevice (POS) CPT terms which do not appear in patient data and used for hierarchical search
INSERT INTO concept_stage (
	concept_name,
	domain_id,
	vocabulary_id,
	concept_class_id,
	standard_concept,
	concept_code,
	valid_start_date,
	valid_end_date,
	invalid_reason
	)
SELECT DISTINCT vocabulary_pack.CutConceptName(UPPER(SUBSTRING(str FROM 1 FOR 1)) ||substring(str FROM 2 FOR LENGTH(str))) AS concept_name, 
  'Place of Service' as domain_id, -- OMOP predefined
	'CPT4' AS vocabulary_id,
	'Place of Service' AS concept_class_id,
	NULL AS standard_concept, 
	scui AS concept_code,
	(SELECT latest_update
		FROM vocabulary
		WHERE vocabulary_id = 'CPT4'
		) AS valid_start_date,
	TO_DATE('20991231', 'yyyymmdd') AS valid_end_date,
	NULL AS invalid_reason
FROM sources.mrconso
  JOIN umls_mrsty USING (cui)
WHERE sab = 'CPT'
	AND suppress NOT IN (
		'E', -- Non-obsolete content marked suppressible by an editor
		'O', -- All obsolete content, whether they are obsolesced by the source or by NLM
		'Y' -- Non-obsolete content deemed suppressible during inversion
		)
	AND tty = 'POS'; -- 48 Places of service

--6. Add CPT Modifiers
INSERT INTO concept_stage (
	concept_name,
	domain_id,
	vocabulary_id,
	concept_class_id,
	standard_concept,
	concept_code,
	valid_start_date,
	valid_end_date,
	invalid_reason
	)
SELECT DISTINCT FIRST_VALUE(vocabulary_pack.CutConceptName(UPPER(SUBSTRING(str FROM 1 FOR 1)) ||substring(str FROM 2 FOR LENGTH(str)))) OVER (
		PARTITION BY scui ORDER BY CASE 
				WHEN LENGTH(str) <= 255
					THEN LENGTH(str)
				ELSE 0
				END DESC,
				LENGTH(str) ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS concept_name,
         '' AS domain_id, -- is about to be assigned at the end
	'CPT4' AS vocabulary_id,
	'CPT4 Modifier' AS concept_class_id,
	'S' AS standard_concept,
	scui AS concept_code,
	(SELECT latest_update
		FROM vocabulary
		WHERE vocabulary_id = 'CPT4'
		) AS valid_start_date,
	TO_DATE('20991231', 'yyyymmdd') AS valid_end_date,
	NULL AS invalid_reason
FROM sources.mrconso
  JOIN umls_mrsty USING (cui)
WHERE sab IN (
		'CPT',
		'HCPT'
		)
	AND suppress NOT IN (
		'E',
		'O',
		'Y'
		)
	AND tty = 'MP';-- 393 Preferred names of modifiers
 
--7. Add Hierarchical CPT terms, which are considered to be Classificaton (do not appear in patient data, only for hierarchical search)
INSERT INTO concept_stage (
	concept_name,
	domain_id,
	vocabulary_id,
	concept_class_id,
	standard_concept,
	concept_code,
	valid_start_date,
	valid_end_date,
	invalid_reason
	)
SELECT DISTINCT vocabulary_pack.CutConceptName(UPPER(SUBSTRING(str FROM 1 FOR 1)) ||substring(str FROM 2 FOR LENGTH(str))) AS concept_name,
	'' AS domain_id, -- is about to be assigned at the end
	'CPT4' AS vocabulary_id,
	'CPT4 Hierarchy' AS concept_class_id,
	'C' AS standard_concept, 
	scui AS concept_code,
	(SELECT latest_update
		FROM vocabulary
		WHERE vocabulary_id = 'CPT4'
		) AS valid_start_date,
	TO_DATE('20991231', 'yyyymmdd') AS valid_end_date,
	NULL AS invalid_reason
FROM sources.mrconso
  JOIN umls_mrsty USING (cui)
WHERE sab IN (
		'CPT',
		'HCPT'
		)
	AND suppress NOT IN (
		'E',
		'O',
		'Y'
		)
	AND tty = 'HT'; -- 3347 Hierarchical terms
	
--8. Pick up all different str values that are not obsolete or suppressed
INSERT INTO concept_synonym_stage (
	synonym_concept_code,
	synonym_name,
	synonym_vocabulary_id,
	language_concept_id
	)
SELECT DISTINCT scui AS synonym_concept_code,
	SUBSTR(str, 1, 1000) AS synonym_name,
	'CPT4' AS synonym_vocabulary_id,
	4180186 AS language_concept_id
FROM sources.mrconso
WHERE sab IN (
		'CPT',
		'HCPT'
		)
	AND suppress NOT IN (
		'E',
		'O',
		'Y'
		); -- 62649
		
--9. Add names concatenated with the names of source concept classes 
INSERT INTO concept_synonym_stage (
	synonym_concept_code,
	synonym_name,
	synonym_vocabulary_id,
	language_concept_id
	)
SELECT DISTINCT scui AS synonym_concept_code,
	vocabulary_pack.CutConceptName(concept_name)||' | '||'['||sty||']' AS synonym_name,
	'CPT4' AS synonym_vocabulary_id,
	4180186 AS language_concept_id
FROM concept_stage c
JOIN sources.mrconso b on b.code = c.concept_code
JOIN umls_mrsty using (cui)
WHERE sab IN (
		'CPT',
		'HCPT')
	 ; -- 15382

--10. Insert existing concepts that are absent in mrconso
INSERT INTO concept_stage (
	concept_name,
	domain_id,
	vocabulary_id,
	concept_class_id,
	standard_concept,
	concept_code,
	valid_start_date,
	valid_end_date,
	invalid_reason
	)
SELECT c.concept_name,
	c.domain_id,
	c.vocabulary_id,
	c.concept_class_id,
	CASE 
		WHEN coalesce(c.invalid_reason, 'D') = 'D'
			AND c.vocabulary_id = 'CPT4' and standard_concept <> 'C'
			THEN 'S'
		ELSE c.standard_concept
		END AS standard_concept,
	c.concept_code,
	c.valid_start_date,
	c.valid_end_date,
	CASE 
		WHEN c.invalid_reason = 'D'
			AND c.vocabulary_id = 'CPT4'
			THEN NULL
		ELSE c.invalid_reason
		END AS invalid_reason
FROM concept c
WHERE c.vocabulary_id = 'CPT4'
	AND NOT EXISTS (
		SELECT 1
		FROM concept_stage cs_int
		WHERE cs_int.concept_code = c.concept_code
		); -- 1981

--11. Create hierarchical relationships between HT and normal CPT codes
INSERT INTO concept_relationship_stage (
	concept_code_1,
	concept_code_2,
	relationship_id,
	vocabulary_id_1,
	vocabulary_id_2,
	valid_start_date,
	valid_end_date,
	invalid_reason
	)
SELECT c1.code AS concept_code_1,
	c2.code AS concept_code_2,
	'Is a' AS relationship_id,
	'CPT4' AS vocabulary_id_1,
	'CPT4' AS vocabulary_id_2,
	TO_DATE('19700101', 'yyyymmdd') AS valid_start_date,
	TO_DATE('20991231', 'yyyymmdd') AS valid_end_date,
	NULL AS invalid_reason
FROM (
	SELECT aui AS aui1,
		REGEXP_REPLACE(ptr, '(.+\.)(A\d+)$', '\2', 'g') AS aui2
	FROM sources.mrhier
	WHERE sab = 'CPT'
		AND rela = 'isa'
	) h
JOIN sources.mrconso c1 ON c1.aui = h.aui1
	AND c1.sab = 'CPT'
JOIN sources.mrconso c2 ON c2.aui = h.aui2
	AND c2.sab = 'CPT'
WHERE NOT EXISTS (
		SELECT 1
		FROM concept_relationship_stage crs
		WHERE crs.concept_code_1 = c1.code
			AND crs.concept_code_2 = c2.code
			AND crs.relationship_id = 'Is a'
			AND crs.vocabulary_id_1 = 'CPT4'
			AND crs.vocabulary_id_2 = 'CPT4'
		); -- 14292
		
--12. Add everything from the Manual tables
DO $_$
BEGIN
     PERFORM VOCABULARY_PACK.ProcessManualConcepts();
END $_$; -- OK

DO $_$
BEGIN
     PERFORM VOCABULARY_PACK.ProcessManualSynonyms();
END $_$;
/*ERROR: synonym_concept_code+synonym_vocabulary_id not found in the concept/concept_stage: 87426+CPT4
  Where: PL/pgSQL function vocabulary_pack.checkmanualsynonyms() line 22 at RAISE
SQL statement "SELECT vocabulary_pack.CheckManualSynonyms()"
PL/pgSQL function vocabulary_pack.processmanualsynonyms() line 11 at PERFORM
SQL statement "SELECT VOCABULARY_PACK.ProcessManualSynonyms()"
PL/pgSQL function inline_code_block line 3 at PERFORM*/

DO $_$
BEGIN
	PERFORM VOCABULARY_PACK.ProcessManualRelationships();
END $_$;
/*ERROR: concept_code_1+vocabulary_id_1 not found in the concept/concept_stage: 0202U+CPT4
  Where: PL/pgSQL function vocabulary_pack.checkmanualrelationships() line 33 at RAISE
SQL statement "SELECT vocabulary_pack.CheckManualRelationships()"
PL/pgSQL function vocabulary_pack.processmanualrelationships() line 11 at PERFORM
SQL statement "SELECT VOCABULARY_PACK.ProcessManualRelationships()"
PL/pgSQL function inline_code_block line 3 at PERFORM
1 statement failed.*/	

--13. Extract "hiden" CPT4 codes inside concept_names of another CPT4 codes.
INSERT INTO concept_relationship_stage (
	concept_code_1,
	concept_code_2,
	relationship_id,
	vocabulary_id_1,
	vocabulary_id_2,
	valid_start_date,
	valid_end_date,
	invalid_reason
	)
SELECT *
FROM (
	SELECT unnest(regexp_matches(concept_name, '\((\d\d\d\d[A-Z])\)', 'gi')) AS concept_code_1,
		concept_code AS concept_code_2,
		'Subsumes' AS relationship_id,
		'CPT4' AS vocabulary_id_1,
		'CPT4' AS vocabulary_id_2,
		TO_DATE('19700101', 'yyyymmdd') AS valid_start_date,
		TO_DATE('20991231', 'yyyymmdd') AS valid_end_date,
		NULL AS invalid_reason
	FROM concept_stage
	WHERE vocabulary_id = 'CPT4'
	) AS s
WHERE NOT EXISTS (
		SELECT 1
		FROM concept_relationship_stage crs
		WHERE crs.concept_code_1 = s.concept_code_1
			AND crs.concept_code_2 = s.concept_code_2
			AND crs.relationship_id = 'Subsumes'
			AND crs.vocabulary_id_1 = 'CPT4'
			AND crs.vocabulary_id_2 = 'CPT4'
		);

--14. Update dates from mrsat.atv (only for new concepts)
UPDATE concept_stage cs
SET valid_start_date = i.dt
FROM (
	SELECT MAX(TO_DATE(s.atv, 'yyyymmdd')) dt,
		cs.concept_code
	FROM concept_stage cs
	LEFT JOIN sources.mrconso m ON m.scui = cs.concept_code
		AND m.sab IN (
			'CPT',
			'HCPT'
			)
	LEFT JOIN sources.mrsat s ON s.cui = m.cui
		AND s.atn = 'DA'
	WHERE NOT EXISTS (
			-- only new codes we don't already have
			SELECT 1
			FROM concept co
			WHERE co.concept_code = cs.concept_code
				AND co.vocabulary_id = cs.vocabulary_id
			)
		AND cs.vocabulary_id = 'CPT4'
		AND cs.concept_class_id = 'CPT4'
		AND s.atv IS NOT NULL
	GROUP BY concept_code
	) i
WHERE i.concept_code = cs.concept_code; -- 29

--15. Working with replacement mappings
DO $_$
BEGIN
	PERFORM VOCABULARY_PACK.CheckReplacementMappings();
END $_$;

--16. Add mapping from deprecated to fresh concepts
DO $_$
BEGIN
	PERFORM VOCABULARY_PACK.AddFreshMAPSTO();
END $_$;

--17. Deprecate 'Maps to' mappings to deprecated and upgraded concepts
DO $_$
BEGIN
	PERFORM VOCABULARY_PACK.DeprecateWrongMAPSTO();
END $_$;

--18. Delete ambiguous 'Maps to' mappings
DO $_$
BEGIN
	PERFORM VOCABULARY_PACK.DeleteAmbiguousMAPSTO();
END $_$;

--19. Update domain_id according to the source 
UPDATE concept_stage cs
   SET domain_id = t1.domain_id
FROM (SELECT DISTINCT concept_code,
             CASE
               WHEN tui IN ('T059','T025') THEN 'Measurement'
               WHEN tui = 'T074' THEN 'Device'
               WHEN tui IN ('T121','T129','T116','T109','T200') THEN 'Drug'
               WHEN tui IN ('T073','T093') THEN 'Place of Service'
               WHEN tui IN ('T061','T060','T065','T057','T169','T063','T062','T066','T170','T058') THEN 'Procedure'
               ELSE 'Observation'
             END AS domain_id
      FROM concept_stage a
        JOIN sources.mrconso b ON a.concept_code = code
        JOIN dev_cpt4.umls_mrsty USING (cui)
      WHERE sab IN ('CPT','HCPT')) t1
WHERE t1.concept_code = cs.concept_code; -- 14849 

--20. Update domain_id for CPT4 according to mappings
UPDATE concept_stage cs
SET domain_id = i.domain_id
FROM (
	SELECT DISTINCT cs1.concept_code,
		first_value(c2.domain_id) OVER (
			PARTITION BY cs1.concept_code ORDER BY CASE c2.domain_id
					WHEN 'Condition'
						THEN 1
					WHEN 'Observation'
						THEN 2
					WHEN 'Procedure'
						THEN 3
					WHEN 'Measurement'
						THEN 4
					WHEN 'Device'
						THEN 5
					ELSE 6
					END
			) AS domain_id
	FROM concept_relationship_stage crs
	JOIN concept_stage cs1 ON cs1.concept_code = crs.concept_code_1
		AND cs1.vocabulary_id = crs.vocabulary_id_1
		AND cs1.vocabulary_id = 'CPT4' 
	JOIN concept c2 ON c2.concept_code = crs.concept_code_2
		AND c2.vocabulary_id = crs.vocabulary_id_2
		AND c2.standard_concept = 'S'  and c2.vocabulary_id <> 'CPT4'
	WHERE crs.relationship_id = 'Maps to'
		AND crs.invalid_reason IS NULL
	
	UNION ALL
	
	SELECT DISTINCT cs1.concept_code,
		first_value(c2.domain_id) OVER (
			PARTITION BY cs1.concept_code ORDER BY CASE c2.domain_id
					WHEN 'Condition'
						THEN 1
					WHEN 'Observation'
						THEN 2
					WHEN 'Procedure'
						THEN 3
					WHEN 'Measurement'
						THEN 4
					WHEN 'Device'
						THEN 5
					ELSE 6
					END
			)
	FROM concept_relationship cr
	JOIN concept c1 ON c1.concept_id = cr.concept_id_1
		AND c1.vocabulary_id = 'CPT4'
	JOIN concept c2 ON c2.concept_id = cr.concept_id_2
		AND c2.standard_concept = 'S' and c2.vocabulary_id <> 'CPT4'
	JOIN concept_stage cs1 ON cs1.concept_code = c1.concept_code
		AND cs1.vocabulary_id = c1.vocabulary_id
	WHERE cr.relationship_id = 'Maps to'
		AND cr.invalid_reason IS NULL
		AND NOT EXISTS (
			SELECT 1
			FROM concept_relationship_stage crs_int
			WHERE crs_int.concept_code_1 = cs1.concept_code
				AND crs_int.vocabulary_id_1 = cs1.vocabulary_id
				AND crs_int.relationship_id = cr.relationship_id
			)
	) i
WHERE i.concept_code = cs.concept_code
	AND cs.vocabulary_id = 'CPT4'
	and cs.domain_id <> i.domain_id; -- 19 

-- At the end, the concept_stage, concept_relationship_stage and concept_synonym_stage tables are ready to be fed into the generic_update script
