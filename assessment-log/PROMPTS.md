# Prompts

Verbatim, in order. 45 prompts so far, covering the planning phase. The summary below is for the planning phase and is extended when the build is done.

## Summary: how the planning went

**What this is.** The planning half of an OfferZen take-home (extend a legacy Rails app: a company-scoped CSV export, a faster dashboard with a trustworthy score, and a safe status normalisation). The work was done with an AI coding assistant. These prompts show how the author directed it.

**How the author worked**
- **Rules before code.** First prompt set the ground rules: no commits or PRs without permission, no assumptions (ask instead), and ticket everything as on a real team (one epic, one groomed ticket per task, one PR per ticket). Deliverables were handed over before the brief, so they stayed in view.
- **Context before tasks, tasks before scaffold.** The brief was given in two steps, and the scaffold (tables, sign-in, seed data) was inferred from the tasks rather than assumed.
- **A spec with provenance.** Every requirement is traced to its source (the brief or a dated author decision) in `spec/`. Questions were asked task by task, each with a recommended answer, and the answers were logged as decisions.
- **Pushing back on recommendations with domain reasoning.** Several of the assistant's proposals were overruled for stated reasons: async instead of streaming (ten years of data, an already slow dashboard); filtering on `assessment_date`, not `created_at` (an assessment can be scheduled but not completed); a status dropdown built from stored values, since an alias list cannot be kept current without write-side enforcement; the database constraint dropped ("not the db's responsibility"); no "scores may differ" footnote, because a displayed score must not make the user doubt it.
- **Treating health data carefully.** One shared PII scrubber for exports, logs and error logs; an export allow-list; email shown instead of name with a compliance caution; only distinct values and counts shared in the mapping sheet.
- **Honesty about unknowns.** The score's shape is not in the brief. Rather than hiding that, the author chose an explicit, documented contract (read-time only, easy to prune once real data is seen) and asked for the assumptions to be stated plainly in code comments and SOLUTION.md, with a masked production copy as the ideal validation.
- **Measure, don't feel.** Performance work is baselined first and shipped one change at a time with numbers ("no changing things and saying it feels faster"). The author reasoned through tools (Bullet, rack-mini-profiler, APM, local versus staging versus production) before choosing what to improve.
- **Safe change thinking.** For Task 3 the author put it in order: stop bad data at the source first (assessor front end, a change request with a cut-over date, Ruby validation), agree a mapping with the assessors, then backfill through a new column with a kept legacy column. That gives a rollback by rename instead of a full restore, with a backup right before the rename. The assistant added dual-write, lock-timeout and verification points, and the author accepted them.
- **Checking the assistant's work.** The author caught that the Task 3 questions had been skipped and sent the assistant back, asked it to check against the full PDF, and asked for each task's constraints to be reviewed before moving on.

**Outputs of this phase**
- 45 prompts, 22 numbered decisions (`DECISIONS.md`).
- An approved spec with 44 requirements: 40 active, 3 out of scope, 1 dropped (`spec/`).
- One epic and 12 tickets in build order (`tickets/`).
- No application code yet.

---

## Prompt 1

You are my coding assistant
Today we're going to be completing a technical assessment for an interview

I'm gonna give you the deliverables first as it's important to keep in mind.
We need to keep a running log of the prompts I used and the decisions I make along the way.
There is a repo ready with basic scaffolding - https://github.com/LeandraEksteen/offerzen-techinical-assessment also already cloned in this directory.

Rules of engagement:
1.At no point are you going to make commits or pr's without my permission.
2.Make no assumptions, if unsure you ask me to clarify/decide
3.We don't have a ticket system like Jira for this, but we're gonna treat it like we do. Every task gets a groomed ticket and the overall ticket gets an epic. We'll keep the 'tickets' in memory and each pr will be linked to a ticket.

Deliverables
1. A single GitHub repository containing:
• All the source code for the assignment
• A README.md with instructions to run locally.
• A SOLUTION.md describing the design and trade-offs you made.
2. Video Demo (5-10 minutes using Loom or similar):
• Demonstrate the working project by doing a voice over
• Walk through your code architecture
• Explain key design decisions and any trade-offs made
• Highlight interesting technical implementations

Any questions at this point?

---

## Prompt 2

1.I'll give the requirement in due time, just wanna get the basics covered first
2.Let's make a separate folder in the repo for the tickets/decisions.md/prompts.md and any other related files - interviewers can use it or not

3. verbatim with a summary at the top once we're done
4. yes but we'll keep it in the folder as per 2
5. yes
6. No
7. Yes

---

## Prompt 3

1. yes
2. already merged to main, we can switch to main here
3. main
4. yes
5. same


Ok on to the context:

TakeHome Assignment: Safely Extending a Legacy Rails Feature (4hour
scope)
Context
You’re taking over a 10yearold Ruby on Rails app used by companies to manage ergonomic/health assessments for their
employees. You inherit a small but realistic slice around “Assessments” with typical legacy rough edges. Your job is to add a
commonly requested export, make one targeted performance improvement, and design a safe data change plan — without
rewrites.
What’s known about the current module (based on observed behavior and logs):
• CSV export can pull assessments for any company when given a company identifier; it includes raw answer data and personal
identifiers.
• The assessments dashboard is slow with many records; filtering by date and status is inconsistent, and the displayed score is
sometimes blank or obviously off.
• Logs include full request parameters and occasionally raw assessment data.
• The status field has many inconsistent values accumulated over years (for example: empty string, nil, “n/a”, “complete”, “comp”,
“done”, “pending”, “in_progress”, “needs_follow_up”, “archived”).
Business and data context:
• Multitenant: company admins must only see and export their own company’s data.
• Healthrelated data: treat data handling and logging with extra care.
• The assessments table is large; avoid changes that would stall the app.
• You own your release lifecycle (Herokulike environment) and should think through a safe rollout and rollback.
Assume entities roughly include: companies, employees (belong to a company), and assessments (belong to an employee
and company) with fields such as company_id, employee_id, employee_email, status, responses_json, created_at.
Core technologies to use:
• Ruby on Rails
• PostgreSQL
• TypeScript
Operate with restraint. Favor targeted, safe improvements over broad refactors. Preserve what works while adding clear
value.
Requirements
Design and implement the following. Keep the scope tight and pragmatic. You may create minimal scaffolding as needed,
but keep the UI and any new structures small and focused.

Ignore the 4 hours timebox.
There are 3 tasks, I'll give them next once we've agreed on the context above.

---

## Prompt 4

1. I know this is a strange one. I'm going to give you the tasks first and then we infer from them what scaffold we're gonna make to allow for the tasks
2. Let's keep it as simple as possible
3. Yes we'll do that
4. Yes please
5. Wait first

Task 1: CompanyScoped CSV Export with Focused Filters and Redactions
Add or revise CSV export so that:
• A company admin can export assessments for their own company only.
• Filters are limited to exactly two: date range and status.
• The exported file excludes or redacts fields that should not leave the system in raw form (for example, freetext answers and
personal identifiers).
• Provide a minimal UI to initiate the export (TypeScript) with basic feedback to the user.

Notes:
• Either a streaming or an asynchronous approach is acceptable; choose one, keep it minimal, and justify it in SOLUTION.md.
• Do not rely on a clientprovided company identifier to grant access.
• Avoid exposing sensitive values in logs related to this feature.
Task 2: Make the Assessments Dashboard Snappier and Fix the Score Display
Company admins report the dashboard page is slow and that the score shown is sometimes blank or wrong. Improve the
experience without changing what the page fundamentally shows.
Do the following:
• Achieve one measurable performance improvement that helps with larger data sets. In SOLUTION.md, include a short before/after
note on how you measured and why you chose this change.
• Ensure the score displayed for each assessment is consistently present and correct under normal circumstances.
• Reduce the chance of sensitive information being written to logs in this area.
Constraints:
• Keep the page working while you improve it.
• Avoid broad refactors; make the smallest reasonable change to achieve the goal.
Task 3: Normalize Assessment Status Values With a Safe Release Plan (PlanOnly Backfill)
Production should standardize status values going forward to:
• pending
• in_progress
• completed
• needs_follow_up
• archived
Do the following:
• Implement a change so new and updated records use only the allowed values.
• Design, but do not fully execute, a plan to bring historical records into alignment. Outline how you would map existing values to
the new set and how you would handle unknowns.
• In SOLUTION.md, provide a stepbystep release and rollback plan suitable for a Herokulike environment, including how you would
capture a database backup before the change and how you would recover if needed. Clarify which steps are safe to run while the
app is live and which you’d schedule during a lowtraffic window.
Constraints:
• Keep the app responsive throughout.
• Avoid changes that would lock or stall the large assessments table.
Scope control:
• Keep TypeScript truly minimal (small UI to trigger export and show basic feedback).
• Automated tests are optional; focus on correctness, safety, and SOLUTION.md.

---

## Prompt 5

Let's keep the order as per the brief and use /to-agent-spec to make a spec for this -> then we can create the tickets and epic files

---

## Prompt 6

Let's do the grilling in order of task please

---

## Prompt 7

T1-1
If we expect large amounts of data to be exported it could cause the front end to freeze as the data is fetched/transformed/zipped etc. We know from the context this company has 10 years worth of assessment data and the one dashboard is already slow. So let's rather go the async way.
The user selects the filters and clicks download. After a second or two the page auto refreshes
Then there is a 'history' table on the download page where the download is shown and the status is 'in progress'. Let's be sure to use batching where needed for huge amounts of records. Assuming this is mainly text so the final size should not be too big.
We'll display for the user to refresh the page in a few mins
When download is done the user should be able to download
We can investigate polling and maybe have a banner show when done no matter where on the website the user is, but for a simple V1 let's keep it as a async job that updates the download table when done.

T1-2 We're talking PII/sensitive info here
We should make a service that scrubs PII from any and all models - this is for export and logs/error logs
Otherwise I agree

T1-3
For an assessment I would assume there would be a created_date and an assessment_date since an assessment can be scheduled but not necessarily completed yet. So let's have the filter work on assessment date
Otherwise I agree

T1-4
Yes we can do table form log in, I meant let's not go full third party login

T1-5
Ok so assuming real life where we need to complete task one without knowing task 2 or 3 is coming how would we do this
Yes the status values are inconsistent but each mean something
So the status dropdown needs to be a unique list of all possible statuses in the table. Since we dont have write side enforcement yet at this stage, to keep a alias list current isnt feasible.
showing all the 'non standard' options to the user isn't ideal, but it's exactly why at this point I would advocate for a write side enforcement, standardisation and alias/backfill.

T1-6
Yes. agreed

---

## Prompt 8

T1-7
Exactly - final product would be S3 or some other file sharing system
You say auto delete cause of health data but we're removing personal identifiers etc. So yes, we can implement a 7 day expiry OR what if we don't store the csv and email it to the logged in account instead?
T1-8
Yes exactly
T1-9
Yes 
T1-10
Yes
T1-11
Unique per company records as per the admin logged in, so not the entire table, just the relevant records. also it would be fine to group to whitespace strip and case insensitive at this stage to reduce duplicates on the front end with no change to the data
Nil and "" could mean different things
If the field is default nil it means it wasn't filled in. that means if its ' ' the assessor deliberately made it blank or there was possibly an issue with saving the status. But for simplicity let's put it together as no status

---

## Prompt 9

T1-7
Yes, in real life I would implement the S3 route with email as a nice to have we can discuss if there is a need
T1-12
yes

T2-1 - let's grill deeper on this one
what does 'obviously off' look like in this world
we assume responses_json contains the score - anything else from the context or doc that points to score

---

## Prompt 10

(Attached: `Senior_Full_Stack_Developer__Ruby_on_Rails__Assignment (2).pdf`, the original OfferZen brief.)

check against the full doc and ask Q's again

---

## Prompt 11

what if the json's keys are off?
so yes, it could be a scale/percentage, decimal point instead of comma, text issue
but also what if the system expects the json to have the score as 'score' but legacy systems recorded it as 'assessment_score' or something? We have no idea either if there is multiple scores in the json.
we'll have to make an educated guess/assumption and stick with it

---

## Prompt 12

Yes, this is important though as we're possibly transforming existing data
So ensure this approach is summarised as comments in the code for the next dev to see.

And make it clear in the solution doc what assumptions we're making here, we're effectively blind but trying to cater for known legacy issues I've previously encountered.

Ideally we would take a masked production copy and run this score transformation on it and evaluate some of these cases.

---

## Prompt 13

Q-B yes that's what I meant. The user could be seeing something different than what is in the db due to our normalisation, it's an important call out

Q-C yes as a POC we can do this. We already know we're talking 100's of thousands of records, we just want a few per normalisation case to eyeball accuracy

T2-1C
Yes, status shouldn't gate score
Once we've normalised the statuses we can maybe look at gating/adding an alert/error log or something - make a note for future development - but with the 'dirty' statuses this is the best route

T2-1D
you say numeric read of the stored value but we agreed that the score is in a json
so are we gonna assume for task one we only read {score:10} in task 1 with no normalisation right?

T2-3 
yes I think so. maybe use email instead of name as an identifier? not sure what the compliance requirement is so let's play it safe

T2-4
Ok so here we're talking performance improving right?
Before even thinking of what to improve we need to agree what we're assuming and how we're benchmarking
Few bechmarks we could do:
on a local instance run n+1 query checks (like bullet) and rack-mini-profiler
I would want to benchmark local, staging, prod separate as they could behave differently - but usually similiar 
if we have datadog or some other apm data this could also be useful to check 
Then assuming we don't already have pagination that's the first thing to add that could add instant value
Eager loading is something bullet would also show
And then assuming once again we don't have any indexes adding to the filter fields company id, status, assessment_date is the logical next step
Not sure what explain analyze is 
So we want to benchmark a normal user and then load test on our local/staging making each change incrementally and noting the change in time

---

## Prompt 14

yes
yes
hmmmm no, when we actually show the score to the user we need to be sure and not have the user doubt. 
yes
yes

---

## Prompt 15

yes
then before going to Task 3 let's just make sure we've covered task 2's constraints in full

• Keep the page working while you improve it.
• Avoid broad refactors; make the smallest reasonable change to achieve the goal.

what are the risks for the page breaking as we're making the improvements?
-for the score normalisation we're going to be extensively testing on local/staging first + making sure we do defensive programming - I would rather the user see 'score not available' than an error screen cause of a nil error
-for performance improvement as soon as we see incremental improvement eg pagination we can ship it while we test the rest, adding those is low risk and possibly high reward - obviously tested first

avoid broad refactors
-the score normalisation is difficult cause we have 0 idea what the data looks like so we might be over-engineering a solution here, but what I will say is once we see the data we can remove the 'rules' that are not applicable to this dataset and simplify it more
-for the performance this is covered by the incremental + becnhmarking approach. No changing things and saying 'it feels faster'

---

## Prompt 16

agree with all

---

## Prompt 17

no man, we skipped the Task 3 Q's

---

## Prompt 18

Let me give you my thinking first, it might answer your questions - also this is not really an implementation ticket just a plan

first thing once we get the go ahead is to stop the bad data from coming in.
this needs to be done on the assessor side - whatever front end they use and then if it's a separate service we can also implement validation/rejection on the api layer
and then as a last resort we can add some constraint on the db although I don't like that option. we should rather prevent any non standard value being written on the ruby side

then once we've stopped the bad data we'll make a google sheet with all the status values currently in the table for all records and try to map them to the new standard values. where in doubt we'll pull in the assessors to confirm if our mapping is correct.

For the backfill/migration there are two options, both with pros and cons
We can create a new column with the mapped status, fill that up and then rename the old staus to legacy_status and the new one to status. I'm thinking this won't stall the table? Also then we don't need to worry about restoring an entire db in the case something goes wrong, it's only a rename migration rollback. any data added to the table inbetween is safe. We could then at a later stage drop the legacy_status column once we're happy

alternative is to make a backup, run an update on every row (maybe each in a transaction) and if something goes wrong roll back only that transaction? not sure if that would work. 

I think the safest and less disrupting option is the new column with gradual migration. You would be able to do all of the migrations live, and as long as the inserts for the new column is batched I think even in high traffic times we would be good? Obviously we would try and choose a low traffic time for safety.

am I missing anything?

---

## Prompt 19

1. yes exactly
2. The only cost is a permanently odd column name. - is this rename then not something we schedule in low traffic? I don;t want to keep dragging this tech debt forever
3. yes 100%
4. yes and no. in real life we would make a Change Request/Brief for the assessors with a cut over date. So they would be prepared. Also the front end would be changed for them from free text to dropdown, don;t think I mentioned this, I just assumed since we're standardising to 5 it was obvious. 
5. yes - cost is the same but we win with rollback/safety
6. exactly
7. yes, only the distinct statuses with counts. might also be worth to say when last it was used (could indicate a legacy system/employee)
8. this is why I would still want to rename
9. yes backfill needs to be 100% before we switch 


Questions:
T3-A
I'd prefer leaving clean behind, so I would maybe do an immediate alias once backfill is done and then schedule some maintenance/downtime to rename or just do it in low traffic

T3-B
Yes. Its not the db's responsibility

T3-C
implement a change so new and updated records use only the allowed values -> we can create a small assessor side  input screen to show the before (freetext) to the after (dropdown with validation)

T3-D
Yes

---

## Prompt 20

T3-E 
Before the cut-over date, the app logs a count of would-be rejections with no values, and the dropdown is already live - the page obviosuly cant be saved without an input. 

T3-F
Yes

T3-G
Yes - it's just an approximate indication. We'd assume status would be the last thing updated on a record

T3-H
Exactly. Obviously we would still do a backup right before the rename just in case


For task 3 did we cover the constraints?
Constraints:
• Keep the app responsive throughout.
• Avoid changes that would lock or stall the large assessments table.

I think so from my massive paragraph

---

## Prompt 21

Yes to both

---

## Prompt 22

Approve

---

## Prompt 23

Write them

---

## Prompt 24

Commit log on branch

---

## Prompt 25

we're done with planning now, so let's add a summary in the relevant file/s
the idea of this assessment is also to show my thinking and how I work
makes sense?

---

## Prompt 26

Edit summary first

---

## Prompt 27

commit and make the pr for this.
include all out tickets, logging files etc

---

## Prompt 28

I've merged
Let's start implementing let's use /build /implement where relevant
but we're doing one ticket/pr at a time, not in parallel for now

---

## Prompt 29

Implement

---

## Prompt 30

Commit and open PR

---

## Prompt 31

merged, let's continue

---

## Prompt 32

Implement

---

## Prompt 33

Commit and open PR

---

## Prompt 34

merged, continue

---

## Prompt 35

Implement

---

## Prompt 36

Commit and open PR

---

## Prompt 37

Cool this is the first of the 3 tasks, let's write some /test-plan 
staging in this case is our local
and then test

---

## Prompt 38

Yes, and allow setup

---

## Prompt 39

choose the correct profile, the leandra gmail one

---

## Prompt 40

oh if you can do in browser here thats fine as well

---

## Prompt 41

Commit to PR branch

---

## Prompt 42

can we add screenshots of the basic functionality in the pr

---

## Prompt 43

merged, let's continue

---

## Prompt 44

Implement

---

## Prompt 45

Commit and open PR
