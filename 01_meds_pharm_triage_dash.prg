DROP PROGRAM 01_meds_pharm_triage_dash:group1 GO
CREATE PROGRAM 01_meds_pharm_triage_dash:group1

PROMPT
    "Output to File/Printer/MINE" = "MINE",
    "Personnel ID" = 0.0
WITH OUTDEV, PRSNL_ID

; =============================================================================
; 1. RECORD STRUCTURE SETUP
; =============================================================================
RECORD rec_data (
    1 prsnl_id = f8
    1 prsnl_name = vc
    1 list_cnt = i4
    1 lists[*]
        2 list_id = f8
        2 list_name = vc
)

SET rec_data->prsnl_id = CNVTREAL($PRSNL_ID)

; =============================================================================
; 2. GET USER DETAILS
; =============================================================================
SELECT INTO "NL:"
FROM PRSNL P
PLAN P WHERE P.PERSON_ID = rec_data->prsnl_id
DETAIL
    rec_data->prsnl_name = P.NAME_FULL_FORMATTED
WITH NOCOUNTER

; =============================================================================
; 3. GET ACTIVE INPATIENT WARDS ("NURSEUNIT" / Nurses Hat Symbol)
; =============================================================================
SELECT INTO "NL:"
FROM CODE_VALUE CV
PLAN CV WHERE CV.CODE_SET = 220
    AND CV.ACTIVE_IND = 1
    AND CV.CDF_MEANING = "NURSEUNIT"
ORDER BY CV.DISPLAY
DETAIL
    rec_data->list_cnt = rec_data->list_cnt + 1
    stat = ALTERLIST(rec_data->lists, rec_data->list_cnt)
    rec_data->lists[rec_data->list_cnt].list_id = CV.CODE_VALUE
    rec_data->lists[rec_data->list_cnt].list_name = CV.DISPLAY
WITH NOCOUNTER

; =============================================================================
; 4. HTML OUTPUT
; =============================================================================
SELECT INTO $OUTDEV
FROM DUMMYT D
PLAN D
HEAD REPORT
    ROW + 1 call print(^<!DOCTYPE html>^)
    ROW + 1 call print(^<html><head>^)
    ROW + 1 call print(^<meta http-equiv='X-UA-Compatible' content='IE=edge'>^)
    ROW + 1 call print(^<title>Pharmacist Acuity Dashboard POC</title>^)
    ROW + 1 call print(^<style>^)
    ROW + 1 call print(^  body { font-family: -apple-system, BlinkMacSystemFont, Segoe UI, Roboto, Arial, sans-serif; background: #f4f6f8; padding: 20px; color: #333; margin: 0; }^)
    ROW + 1 call print(^  .dashboard-header { background: #0076a8; color: #fff; padding: 15px 20px; border-radius: 5px 5px 0 0; font-size: 20px; font-weight: bold; }^)
    ROW + 1 call print(^  .dashboard-content { background: #fff; padding: 20px; border: 1px solid #ddd; border-top: none; border-radius: 0 0 5px 5px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); min-height: 400px; }^)
    ROW + 1 call print(^  .info-box { background: #e9ecef; border-left: 4px solid #6c757d; padding: 10px 15px; margin-bottom: 20px; font-size: 14px; }^)
    ROW + 1 call print(^  select { padding: 8px; font-size: 14px; border: 1px solid #ccc; border-radius: 4px; width: 300px; }^)
    ROW + 1 call print(^  button { padding: 8px 15px; background: #28a745; color: #fff; border: none; border-radius: 4px; cursor: pointer; font-size: 14px; margin-left: 10px; font-weight: bold; }^)
    ROW + 1 call print(^  button:hover { background: #218838; }^)
    ROW + 1 call print(^</style>^)
    ROW + 1 call print(^</head><body>^)

    ROW + 1 call print(^<div class="dashboard-header">Pharmacist Acuity Dashboard - Architecture Test (Ward Level)</div>^)
    ROW + 1 call print(^<div class="dashboard-content">^)

    ROW + 1 call print(CONCAT(^<div class="info-box">^))
    ROW + 1 call print(CONCAT(^<b>Logged-in User:</b> ^, NULLVAL(rec_data->prsnl_name, "Unknown User"), ^<br/>^))
    ROW + 1 call print(CONCAT(^<b>User ID:</b> ^, TRIM(CNVTSTRING(rec_data->prsnl_id)), ^<br/>^))
    ROW + 1 call print(CONCAT(^<b>Inpatient Wards Found:</b> ^, TRIM(CNVTSTRING(rec_data->list_cnt))))
    ROW + 1 call print(^</div>^)

    ROW + 1 call print(^<h3>Select an Inpatient Ward to Triage</h3>^)
    
    IF (rec_data->list_cnt > 0)
        ROW + 1 call print(^<select id="listSelector">^)
        ROW + 1 call print(^<option value="0">-- Select a Ward --</option>^)
        FOR (i = 1 TO rec_data->list_cnt)
            ROW + 1 call print(CONCAT(^<option value="^, TRIM(CNVTSTRING(rec_data->lists[i].list_id)), ^">^, rec_data->lists[i].list_name, ^</option>^))
        ENDFOR
        ROW + 1 call print(^</select>^)
        
        ROW + 1 call print(^<button onclick="alert('In the next step, we will wire this to load the Acuity script for Ward Code Value: ' + document.getElementById('listSelector').value)">Load Patients</button>^)
    ELSE
        ROW + 1 call print(^<p style="color: #dc3545;"><i>No active inpatient wards found.</i></p>^)
    ENDIF

    ROW + 1 call print(^</div>^)
    ROW + 1 call print(^</body></html>^)
WITH NOCOUNTER, MAXCOL=32000, FORMAT=VARIABLE, NOHEADING

END
GO