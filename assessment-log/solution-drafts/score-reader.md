# SOLUTION.md draft: reading the score (TKT-8)

Draft section, merged into SOLUTION.md by TKT-12. Code: `app/services/score_reader.rb`. Report: `bin/rails scores:report`.

## We do not know the real data

The brief says the score shown to admins is "sometimes blank or obviously off" and says nothing about where the score is stored, what scale it uses, or how ten years of changes to the system left their mark on it. We are effectively blind. The reader is an educated guess that covers legacy problems seen before in systems like this one, kept small and written so that its rules can be removed once the real data is known.

## What the reader assumes

1. **Where the score lives:** the top-level keys `score`, `assessment_score`, `total_score` and `overall_score`, in that order. The first one that holds a valid value wins. Values are never combined. Nested keys, other names, and scores computed from individual answers are not looked at.
2. **What counts as a number:** a JSON number, or a string that is, after trimming, digits with an optional single decimal part (`.` or `,`) and an optional percent sign (a space before it is allowed). Text such as `"N/A"`, an empty string, `"85 out of 100"` and `"1.234,5"` are not numbers. A comma followed by exactly three digits (`"1,234"`) could be a thousands separator, so it is treated as ambiguous and invalid.
3. **Range:** 0 to 100. Anything outside is invalid. A value strictly between 0 and 1 (`0.85`) could mean 0.85 or 85, so it is **not** scaled: it is invalid and counted separately.
4. **Rounding:** half up, to a whole number.
5. **Result:** a whole number 0 to 100, or nothing. Nothing is shown as "Score not available" on the dashboard and left blank in the CSV. The status of the assessment never matters.

## Legacy problems it is meant to cover

Scores stored as text (`"85"`), with a percent sign (`"85%"`), with a decimal comma (`"84,5"`), with float noise (`84.99999`), under an older key name, next to a second score, missing, null, as `"N/A"` or an empty string, outside 0 to 100, as a proportion, in a root that is not an object (a JSON string that was encoded twice, an array, null).

## What it deliberately does not do

- It never rewrites stored data. What an admin sees can therefore differ from what is stored: `"85%"` is stored and `85` is shown. This is intended and a Score that cannot be trusted is shown as "Score not available" rather than guessed.
- Scales such as 1 to 5 or 0 to 10 cannot be told apart from low percentages and are read as percentages. This is a known limitation.
- It does not gate the score on the assessment's status (the statuses are still messy; see the status plan).

## How it is built to be pruned

Each rule (key order, scalar only, string to number, percent sign, decimal comma, range, proportion, rounding) is a separate unit with its own tests, and a reader can be built without any of them. `bin/rails scores:report` runs the reader over every row and prints how many rows fall into each case, how many needed each rule, and a few scrubbed examples per case. Once real data has been run through it, delete the rules whose counts are zero.

## How it keeps personal data out

The four candidate values are read in SQL, so the free-text answers stored beside the score never reach Ruby (the export already worked this way). The dashboard no longer loads the large `responses_json` column at all. Neither the dashboard nor the report logs a score value; if reading one row fails, only the error class and the assessment id are logged. The report prints a raw score token only when it is short and number-like (and scrubbed), otherwise it prints `[text, N characters]`.

## Ideal validation

Take a masked copy of production data, run `bin/rails scores:report` on it, and look at the examples for each case. That is the only way to know whether these assumptions fit. On the synthetic seed (500,000 rows, deliberately messy) 81.0% of rows show a score and 19.0% show "Score not available"; the real proportions on real data are unknown.
