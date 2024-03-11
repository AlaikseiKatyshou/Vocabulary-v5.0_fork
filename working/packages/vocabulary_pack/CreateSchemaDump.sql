CREATE OR REPLACE FUNCTION vocabulary_pack.CreateSchemaDump (pSchemaName TEXT)
RETURNS VOID AS
$BODY$
	/*
	Creates text dump for concept, concept_relationship, relationship, concept_synonym, concept_ancestor, domain, drug_strength, concept_class, vocabulary, vocabulary_conversion in specified schema
	Usage:
	1. Connect as devv5
	2. Run SELECT vocabulary_pack.CreateSchemaDump ('dev_test');
	3. Files will be created in the specified location (see iExportPath below)
	*/
DECLARE
	iExportPath CONSTANT TEXT:='/data/vocab_dump/custom_dump';
BEGIN
	PERFORM SET_CONFIG('search_path', pSchemaName, TRUE);

	EXECUTE FORMAT ($$
		COPY (
			SELECT concept_id,
				concept_name,
				domain_id,
				vocabulary_id,
				concept_class_id,
				standard_concept,
				concept_code,
				TO_CHAR(valid_start_date, 'DD-MON-YYYY') valid_start_date,
				TO_CHAR(valid_end_date, 'DD-MON-YYYY') valid_end_date,
				invalid_reason
			FROM concept
		) TO PROGRAM 'gzip -2 > %1$s/concept.csv.gz' CSV HEADER;

		COPY vocabulary TO PROGRAM 'gzip -2 > %1$s/vocabulary.csv.gz' CSV HEADER;

		COPY (
			SELECT concept_id_1,
				concept_id_2,
				relationship_id,
				TO_CHAR(valid_start_date, 'DD-MON-YYYY') valid_start_date,
				TO_CHAR(valid_end_date, 'DD-MON-YYYY') valid_end_date,
				invalid_reason
			FROM concept_relationship
			WHERE invalid_reason IS NULL
		) TO PROGRAM 'gzip -2 > %1$s/concept_relationship.csv.gz' CSV HEADER;

		COPY relationship TO PROGRAM 'gzip -2 > %1$s/relationship.csv.gz' CSV HEADER;
		COPY concept_synonym TO PROGRAM 'gzip -2 > %1$s/concept_synonym.csv.gz' CSV HEADER;
		COPY concept_ancestor TO PROGRAM 'gzip -2 > %1$s/concept_ancestor.csv.gz' CSV HEADER;
		COPY domain TO PROGRAM 'gzip -2 > %1$s/domain.csv.gz' CSV HEADER;

		COPY (
			SELECT drug_concept_id,
				ingredient_concept_id,
				amount_value,
				amount_unit_concept_id,
				numerator_value,
				numerator_unit_concept_id,
				denominator_value,
				denominator_unit_concept_id,
				box_size,
				TO_CHAR(valid_start_date, 'DD-MON-YYYY') valid_start_date,
				TO_CHAR(valid_end_date, 'DD-MON-YYYY') valid_end_date,
				invalid_reason
			FROM drug_strength
		) TO PROGRAM 'gzip -2 > %1$s/drug_strength.csv.gz' CSV HEADER;

		COPY concept_class TO PROGRAM 'gzip -2 > %1$s/concept_class.csv.gz' CSV HEADER;

		COPY (
			SELECT vocabulary_id_v4,
				vocabulary_id_v5,
				omop_req,
				click_default,
				available,
				url,
				click_disabled,
				TO_CHAR(latest_update, 'DD-MON-YYYY') latest_update
			FROM vocabulary_conversion
		) TO PROGRAM 'gzip -2 > %1$s/vocabulary_conversion.csv.gz' CSV HEADER;
	$$, iExportPath);
END;
$BODY$
LANGUAGE 'plpgsql' STRICT;