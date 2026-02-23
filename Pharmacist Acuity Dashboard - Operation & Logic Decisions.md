# Pharmacist Acuity Dashboard: Operation & Logic Decisions

## Program Overview
The `01_meds_pharm_triage_dash` program is a custom Discern MPage script designed to dynamically process standard Cerner Patient Lists and score active inpatients based on clinical risk criteria. The script operates in two modes: a UI-rendering mode for the initial MPage layout, and an AJAX data-fetch mode that securely bridges large data queries utilizing `XMLCclRequest` endpoints.

## Cohort Identification & System Filtering

* **Inpatient Optimization:** The script processes up to 2,000 raw patients from a provider's list via the Cerner API before forcefully excluding any non-inpatient encounter (`ENCNTR_TYPE_CLASS_CD = 391.00`). Filtering out Ward Attender and Outpatient encounters prior to evaluation safely neutralizes the risk of duplicate active encounters being scored for a single patient.
* **UI Workload Cap:** Once the qualifying active inpatients are successfully identified, the evaluation array truncates at 300 patients. This hard cap guarantees sub-second rendering times, avoiding WebSphere memory timeouts, while still comfortably fitting the operational bandwidth of a single pharmacist's workflow.

## Clinical Data Evaluation & Scope Restructuring

* **Removal of Mutual Exclusions:** Previous iterations of the code utilized linear `ELSEIF` chains when scanning a patient's Problems, Diagnoses, and Orders arrays. This logic has been flattened. A patient presenting with deep vein thrombosis *and* severe pre-eclampsia will now correctly trigger flags for both clinical conditions simultaneously.
* **Double-Count Handling:** If a patient receives an intravenous administration of an antihypertensive agent (e.g., Labetalol), they will intentionally trigger both the `High-Alert IV` metric and the `Antihypertensive` metric, accurately reflecting the cumulative clinical risk.
* **Event Chronology:** To guarantee clinical relevance, the Clinical Event query is now strictly bound by `ORDER BY ... PERFORMED_DT_TM DESC`. The engine utilizes `HEAD` logic to evaluate solely the *most recent* recorded result for critical thresholds like IMEWS and Bedside Blood Glucose. However, historical variables such as Blood Transfusions or EBL remain cumulative across a rolling 7-day window.

## Polypharmacy Count & Medication Exclusions
To provide a clinically relevant medication burden count, routine background fluids (e.g., Sodium Chloride, Lactate) are globally excluded from the polypharmacy count. Specific oral comfort medications (e.g., Cyclizine, Ondansetron) are conditionally excluded *only* if ordered via a formalized pathway/PowerPlan (`APC.PATHWAY_ID > 0.0`).

## Scoring Matrix Updates (Oxytocin Protocol)
By request, the evaluation of postpartum Oxytocin infusions as a +5 High-Alert IV metric has been disabled within the engine. The frontend scoring matrix reflects this by moving the criteria to the bottom of the table, greying it out, and noting it as "Temporarily Disabled".

## Hardcoded Variable Configurations
The engine utilizes a few hardcoded Oracle identifiers (`854.00` for active encounters, `391.00` for inpatient class). Since this specific build is being architected explicitly for a single deployment site, utilizing these stable system-level OIDs ensures maximum execution speed without the overhead of dynamic `UAR_GET_CODE_BY` lookups.