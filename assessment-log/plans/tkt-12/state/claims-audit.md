# Claims audit (MC-2): every number or measured claim in README.md and SOLUTION.md and where it comes from

All figures are local (Apple M1 Pro, 500k seed) and quoted from existing records; none was re-measured for the documents.

| Claim in SOLUTION.md | Source |
|---|---|
| Baseline: 421 ms and 1,414 queries; 3,921 ms and 14,787; 58,019 ms and 199,064; 284 KB, 2,936 KB, 37,287 KB; 2.09 GB peak | benchmarks/task-2-dashboard.md, "Baseline results" |
| Main query 44 to 153 ms; profiler turned 421 ms into 1,292 ms | same, "EXPLAIN" and "Diagnosis tools" |
| Pagination: 61 ms and 66 ms, 950 and 6.4 times faster, 53 queries, 12 KB | same, "After pagination" |
| Eager loading: 66 to 49 ms, 61 to 44 ms, 53 to 4 queries, 26 to 30% | same, "After eager loading" |
| Index: main query 43 to 0.21 ms and 46.4 to 0.15 ms; page 46 to 51 ms to 7 to 8 ms; 6.4 to 6.7 times; deep page 164 to 176 ms | same, "After the composite index" |
| Plain build froze writers 210 ms; concurrent build 0.34 s, max insert 10 ms; index 5.7 MB against 19 MB; 0.096 ms against 0.088 ms | same, "Build, size and writes" and "Three-column alternative" |
| Score reader: page 6 to 7 ms, 4 queries, export 3,767 to 2,552 ms, 19 of 50 and 16 of 50 changed rows | same, "After the score reader" |
| `ab`: 2.44 to 157.13 req/s (c=1), 2.98 to 172.57 (c=3) | same, baseline load test and "After the score reader" |
| Status list about 58 ms on a cache miss; export date filter 27 ms and 4.3 ms | same, TKT-7 "Other queries" and D-025 |
| 81.0% of seed rows show a score | benchmarks/score-report-500k-seed.txt, D-026 |
| Report 4.7 s, 14 distinct values, 446,246 mapped and 53,754 unmapped rows | benchmarks/status-report-500k-seed.txt, D-029 |
| Rehearsal: add column 0.9 ms, 1.005 s lock timeout, 100 batches median 60 ms, 5.7 s, 294 to 541 MB, 443,210 dead rows, 3,434 HOT updates, 216 ms partial index, about 65 ms count, renames under 0.5 ms | the TKT-11 rehearsal (ticket TKT-11 comments, D-029) |
| Export 2,552 ms median for 200,000 rows (3,767 ms before) | same as score reader row; D-021 says 3.8 s for the first measurement |
| Over 200 tests (208) | `bin/rails test` on this branch |
| Rate limit 10 per 3 minutes; 20 history rows; 7 days; 30 minutes; batches of 5,000 | `SessionsController`, `ExportRequest`, `AssessmentCsvExport` constants |

README numbers: 500,000 assessments and 20 companies, 200,000 in the largest, about 1 minute (CLAUDE.md, D-019); small seed 3 companies and 300 assessments (`db/seeds.rb`, fresh-clone run); default ports 5433 and 3000 (`database.yml`, `bin/dev`).

Automated cross-check: `test/docs/docs_test.rb` asserts that 58,019, 199,064, 1,414, 2,552 and 3,767 appear in both SOLUTION.md and the benchmarks file.
