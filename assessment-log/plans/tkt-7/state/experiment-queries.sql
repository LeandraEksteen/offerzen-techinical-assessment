\echo '#### Q1 page 1, largest company'
EXPLAIN (ANALYZE, BUFFERS) SELECT "assessments".* FROM "assessments" WHERE "assessments"."company_id" = 1 ORDER BY "assessments"."assessment_date" DESC, "assessments"."id" DESC LIMIT 51 OFFSET 0;
\echo '#### Q2 normal user, 2024 filter, company 2, page 1'
EXPLAIN (ANALYZE, BUFFERS) SELECT "assessments".* FROM "assessments" WHERE "assessments"."company_id" = 2 AND (assessments.assessment_date >= '2024-01-01') AND (assessments.assessment_date <= '2024-12-31') ORDER BY "assessments"."assessment_date" DESC, "assessments"."id" DESC LIMIT 51 OFFSET 0;
\echo '#### Q3 deep page 3000, largest company'
EXPLAIN (ANALYZE, BUFFERS) SELECT "assessments".* FROM "assessments" WHERE "assessments"."company_id" = 1 ORDER BY "assessments"."assessment_date" DESC, "assessments"."id" DESC LIMIT 51 OFFSET 149950;
\echo '#### Q4 status options (DISTINCT), largest company'
EXPLAIN (ANALYZE, BUFFERS) SELECT DISTINCT NULLIF(lower(btrim(status, E' \t\r\n')), '') FROM "assessments" WHERE "assessments"."company_id" = 1;
\echo '#### Q5 export batch, largest company, id > 0'
EXPLAIN (ANALYZE, BUFFERS) SELECT "assessments"."id", "assessments"."assessment_date", "assessments"."created_at", "assessments"."status", (CASE WHEN jsonb_typeof(responses_json->'score') = 'number' THEN (responses_json->'score')::text END), "assessments"."employee_id" FROM "assessments" WHERE "assessments"."company_id" = 1 AND (assessments.id > 0) ORDER BY assessments.id LIMIT 5000;
\echo '#### Q6 export batch with date range 2024, largest company'
EXPLAIN (ANALYZE, BUFFERS) SELECT "assessments"."id" FROM "assessments" WHERE "assessments"."company_id" = 1 AND (assessments.assessment_date >= '2024-01-01') AND (assessments.assessment_date <= '2024-12-31') AND (assessments.id > 0) ORDER BY assessments.id LIMIT 5000;
\echo '#### Q7 status filter pending, largest company, page 1'
EXPLAIN (ANALYZE, BUFFERS) SELECT "assessments".* FROM "assessments" WHERE "assessments"."company_id" = 1 AND (NULLIF(lower(btrim(status, E' \t\r\n')), '') = 'pending') ORDER BY "assessments"."assessment_date" DESC, "assessments"."id" DESC LIMIT 51 OFFSET 0;
\echo '#### Q8 small company 15, page 1'
EXPLAIN (ANALYZE, BUFFERS) SELECT "assessments".* FROM "assessments" WHERE "assessments"."company_id" = 15 ORDER BY "assessments"."assessment_date" DESC, "assessments"."id" DESC LIMIT 51 OFFSET 0;
