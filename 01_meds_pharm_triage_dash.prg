DROP PROGRAM 01_meds_pharm_triage_dash:group1 GO
CREATE PROGRAM 01_meds_pharm_triage_dash:group1

PROMPT
    "Output to File/Printer/MINE" = "MINE",
    "Personnel ID" = 0.0,
    "Ward Code" = 0.0
WITH OUTDEV, PRSNL_ID, WARD_CD

IF (CNVTREAL($WARD_CD) > 0.0)
    ; =========================================================================
    ; DATA FETCH MODE (AJAX) - RUN CLINICAL RULES AND RETURN HTML ROWS ONLY
    ; =========================================================================
    DECLARE curr_ward_cd = f8 WITH noconstant(0.0)
    SET curr_ward_cd = CNVTREAL($WARD_CD)
    
    DECLARE v_ward_rows = vc WITH noconstant(""), maxlen=65534
    DECLARE pat_idx = i4 WITH noconstant(0)
    DECLARE idx = i4 WITH noconstant(0)
    DECLARE t_score = i4 WITH noconstant(0)
    DECLARE t_triggers = vc WITH noconstant(""), maxlen=500
    DECLARE num_pats = i4 WITH noconstant(0)
    DECLARE stat = i4 WITH noconstant(0)

    RECORD 600144_request (
        1 patient_list_id = f8
        1 prsnl_id = f8
        1 definition_version = i4
    )
    RECORD 600144_reply (
        1 arguments[*]
            2 argument_name = vc
            2 argument_value = vc
            2 parent_entity_name = vc
            2 parent_entity_id = f8
    )
    RECORD 600123_request (
        1 patient_list_id = f8
        1 patient_list_type_cd = f8
        1 mv_flag = i2
        1 rmv_pl_rows_flag = i2
        1 arguments[*]
            2 argument_name = vc
            2 argument_value = vc
            2 parent_entity_name = vc
            2 parent_entity_id = f8
    )
    RECORD 600123_reply (
        1 patients[*]
            2 person_id = f8
            2 encntr_id = f8
    )

    RECORD rec_cohort (
        1 cnt = i4
        1 list[*]
            2 person_id = f8
            2 encntr_id = f8
            2 name = vc
            2 room_bed = vc
            2 score = i4
            2 color = vc
            2 summary = vc
            2 poly_count = i4
            2 flag_ebl = i2
            2 flag_transfusion = i2
            2 flag_preeclampsia = i2
            2 flag_dvt = i2
            2 flag_epilepsy = i2
            2 flag_insulin = i2
            2 flag_antiepileptic = i2
            2 flag_anticoag = i2
            2 flag_antihypertensive = i2
            2 flag_neuraxial = i2
            2 flag_poly_severe = i2
            2 flag_poly_mod = i2
    )

    ; 1a. Execute Patient List Rules via API
    DECLARE curr_list_id = f8 WITH noconstant(curr_ward_cd)

    SET 600144_request->patient_list_id = curr_list_id
    SET 600144_request->prsnl_id = CNVTREAL($PRSNL_ID)
    SET 600144_request->definition_version = 1

    SET stat = tdbexecute(600005, 600024, 600144, "REC", 600144_request, "REC", 600144_reply)

    SELECT INTO "NL:"
    FROM DCP_PATIENT_LIST DPL
    PLAN DPL WHERE DPL.PATIENT_LIST_ID = curr_list_id
    DETAIL 600123_request->patient_list_type_cd = DPL.PATIENT_LIST_TYPE_CD
    WITH NOCOUNTER

    SET 600123_request->patient_list_id = curr_list_id
    SET stat = moverec(600144_reply->arguments, 600123_request->arguments)
    SET 600123_request->mv_flag = -1
    SET 600123_request->rmv_pl_rows_flag = 0

    SET stat = tdbexecute(600005, 600024, 600123, "REC", 600123_request, "REC", 600123_reply)

    ; 1b. Populate Cohort from API Results
    IF (SIZE(600123_reply->patients, 5) > 0)
        SELECT INTO "NL:"
        FROM (DUMMYT D WITH SEQ=SIZE(600123_reply->patients, 5)), ENCOUNTER E, PERSON P
        PLAN D
        JOIN E WHERE E.ENCNTR_ID = 600123_reply->patients[D.SEQ].encntr_id
            AND E.ACTIVE_IND = 1
        JOIN P WHERE P.PERSON_ID = E.PERSON_ID AND P.ACTIVE_IND = 1
            AND P.BIRTH_DT_TM < CNVTLOOKBEHIND("1,Y")
            AND CNVTUPPER(P.NAME_LAST_KEY) != "ZZZTEST"
            AND CNVTUPPER(P.NAME_LAST_KEY) != "BABY"
            AND CNVTUPPER(P.NAME_LAST_KEY) != "INFANT"
        ORDER BY E.LOC_ROOM_CD, E.LOC_BED_CD
        DETAIL
            rec_cohort->cnt = rec_cohort->cnt + 1
            stat = alterlist(rec_cohort->list, rec_cohort->cnt)
            rec_cohort->list[rec_cohort->cnt].person_id = P.PERSON_ID
            rec_cohort->list[rec_cohort->cnt].encntr_id = E.ENCNTR_ID
            rec_cohort->list[rec_cohort->cnt].name = P.NAME_FULL_FORMATTED
            rec_cohort->list[rec_cohort->cnt].room_bed = CONCAT(TRIM(UAR_GET_CODE_DISPLAY(E.LOC_ROOM_CD)), "-", TRIM(UAR_GET_CODE_DISPLAY(E.LOC_BED_CD)))
        WITH NOCOUNTER
    ENDIF

    SET num_pats = rec_cohort->cnt

    IF (num_pats > 0)
        ; 2. Bulk Evaluate Problems (Lifelong: PERSON_ID)
        SELECT INTO "NL:"
            UNOM = CNVTUPPER(N.SOURCE_STRING)
        FROM PROBLEM P, NOMENCLATURE N
        PLAN P WHERE EXPAND(pat_idx, 1, num_pats, P.PERSON_ID, rec_cohort->list[pat_idx].person_id)
            AND P.ACTIVE_IND = 1 AND P.LIFE_CYCLE_STATUS_CD = 3301.00
        JOIN N WHERE N.NOMENCLATURE_ID = P.NOMENCLATURE_ID
        DETAIL
            idx = LOCATEVAL(pat_idx, 1, num_pats, P.PERSON_ID, rec_cohort->list[pat_idx].person_id)
            IF (idx > 0)
                IF (FINDSTRING("PRE-ECLAMPSIA", UNOM) > 0 OR FINDSTRING("PREECLAMPSIA", UNOM) > 0) rec_cohort->list[idx].flag_preeclampsia = 1
                ELSEIF (FINDSTRING("DEEP VEIN THROMBOSIS", UNOM) > 0 OR FINDSTRING("PULMONARY EMBOLISM", UNOM) > 0 OR FINDSTRING("DVT", UNOM) > 0) rec_cohort->list[idx].flag_dvt = 1
                ELSEIF (FINDSTRING("EPILEPSY", UNOM) > 0 OR FINDSTRING("SEIZURE", UNOM) > 0) rec_cohort->list[idx].flag_epilepsy = 1
                ENDIF
            ENDIF
        WITH NOCOUNTER

        ; 3. Bulk Evaluate Diagnoses (Current Admission: ENCNTR_ID)
        SELECT INTO "NL:"
            UNOM = CNVTUPPER(N.SOURCE_STRING)
        FROM DIAGNOSIS D, NOMENCLATURE N
        PLAN D WHERE EXPAND(pat_idx, 1, num_pats, D.ENCNTR_ID, rec_cohort->list[pat_idx].encntr_id)
            AND D.ACTIVE_IND = 1
        JOIN N WHERE N.NOMENCLATURE_ID = D.NOMENCLATURE_ID
        DETAIL
            idx = LOCATEVAL(pat_idx, 1, num_pats, D.ENCNTR_ID, rec_cohort->list[pat_idx].encntr_id)
            IF (idx > 0)
                IF (FINDSTRING("PRE-ECLAMPSIA", UNOM) > 0 OR FINDSTRING("PREECLAMPSIA", UNOM) > 0) rec_cohort->list[idx].flag_preeclampsia = 1
                ELSEIF (FINDSTRING("DEEP VEIN THROMBOSIS", UNOM) > 0 OR FINDSTRING("PULMONARY EMBOLISM", UNOM) > 0 OR FINDSTRING("DVT", UNOM) > 0) rec_cohort->list[idx].flag_dvt = 1
                ELSEIF (FINDSTRING("EPILEPSY", UNOM) > 0 OR FINDSTRING("SEIZURE", UNOM) > 0) rec_cohort->list[idx].flag_epilepsy = 1
                ENDIF
            ENDIF
        WITH NOCOUNTER

        ; 4. Bulk Evaluate Orders (Current Admission: ENCNTR_ID)
        SELECT INTO "NL:"
            UNOM = CNVTUPPER(O.ORDER_MNEMONIC)
        FROM ORDERS O, ACT_PW_COMP APC
        PLAN O WHERE EXPAND(pat_idx, 1, num_pats, O.ENCNTR_ID, rec_cohort->list[pat_idx].encntr_id)
            AND O.ORDER_STATUS_CD = 2550.00 AND O.CATALOG_TYPE_CD = 2516.00 AND O.ORIG_ORD_AS_FLAG = 0 AND O.TEMPLATE_ORDER_ID = 0
        JOIN APC WHERE APC.PARENT_ENTITY_ID = OUTERJOIN(O.ORDER_ID) AND APC.PARENT_ENTITY_NAME = OUTERJOIN("ORDERS") AND APC.ACTIVE_IND = OUTERJOIN(1)
        ORDER BY O.ORDER_ID
        HEAD O.ORDER_ID
            idx = LOCATEVAL(pat_idx, 1, num_pats, O.ENCNTR_ID, rec_cohort->list[pat_idx].encntr_id)
            IF (idx > 0)
                IF ((APC.PATHWAY_ID > 0.0 AND (FINDSTRING("CHLORPHENAMINE", UNOM)>0 OR FINDSTRING("CYCLIZINE", UNOM)>0 OR FINDSTRING("LACTULOSE", UNOM)>0 OR FINDSTRING("ONDANSETRON", UNOM)>0))
                OR FINDSTRING("SODIUM CHLORIDE", UNOM)>0 OR FINDSTRING("LACTATE", UNOM)>0 OR FINDSTRING("GLUCOSE", UNOM)>0 OR FINDSTRING("MAINTELYTE", UNOM)>0 OR FINDSTRING("WATER FOR INJECTION", UNOM)>0)
                    stat = 1
                ELSE
                    rec_cohort->list[idx].poly_count = rec_cohort->list[idx].poly_count + 1
                ENDIF

                IF (FINDSTRING("TINZAPARIN", UNOM)>0 OR FINDSTRING("ENOXAPARIN", UNOM)>0 OR FINDSTRING("HEPARIN", UNOM)>0) rec_cohort->list[idx].flag_anticoag = 1
                ELSEIF (FINDSTRING("INSULIN", UNOM)>0) rec_cohort->list[idx].flag_insulin = 1
                ELSEIF (FINDSTRING("LEVETIRACETAM", UNOM)>0 OR FINDSTRING("LAMOTRIGINE", UNOM)>0 OR FINDSTRING("VALPROATE", UNOM)>0 OR FINDSTRING("CARBAMAZEPINE", UNOM)>0) rec_cohort->list[idx].flag_antiepileptic = 1
                ELSEIF (FINDSTRING("LABETALOL", UNOM)>0 OR FINDSTRING("NIFEDIPINE", UNOM)>0 OR FINDSTRING("METHYLDOPA", UNOM)>0) rec_cohort->list[idx].flag_antihypertensive = 1
                ELSEIF (FINDSTRING("BUPIVACAINE", UNOM)>0 OR FINDSTRING("LEVOBUPIVACAINE", UNOM)>0) rec_cohort->list[idx].flag_neuraxial = 1
                ENDIF
            ENDIF
        WITH NOCOUNTER

        ; 5. Bulk Evaluate Clinical Events (Current Admission: ENCNTR_ID)
        SELECT INTO "NL:"
        FROM CLINICAL_EVENT CE
        PLAN CE WHERE EXPAND(pat_idx, 1, num_pats, CE.ENCNTR_ID, rec_cohort->list[pat_idx].encntr_id)
            AND CE.EVENT_CD IN (15071366.00, 82546829.00, 15083551.00, 19995695.00)
            AND CE.VALID_UNTIL_DT_TM > SYSDATE AND CE.PERFORMED_DT_TM > CNVTLOOKBEHIND("7,D") AND CE.RESULT_STATUS_CD IN (25, 34, 35)
        DETAIL
            idx = LOCATEVAL(pat_idx, 1, num_pats, CE.ENCNTR_ID, rec_cohort->list[pat_idx].encntr_id)
            IF (idx > 0)
                IF (CE.EVENT_CD = 15071366.00) rec_cohort->list[idx].flag_transfusion = 1
                ELSEIF (CNVTREAL(CE.RESULT_VAL) > 1000.0) rec_cohort->list[idx].flag_ebl = 1
                ENDIF
            ENDIF
        WITH NOCOUNTER

        ; 6. Calculate Final Scores in Memory
        FOR (pat_idx = 1 TO num_pats)
            SET t_score = 0
            SET t_triggers = ""

            IF (rec_cohort->list[pat_idx].poly_count >= 10) SET rec_cohort->list[pat_idx].flag_poly_severe = 1
            ELSEIF (rec_cohort->list[pat_idx].poly_count >= 5) SET rec_cohort->list[pat_idx].flag_poly_mod = 1
            ENDIF

            IF (rec_cohort->list[pat_idx].flag_transfusion = 1 OR rec_cohort->list[pat_idx].flag_ebl = 1) SET t_score = t_score + 3 SET t_triggers = CONCAT(t_triggers, "Haemorrhage/Transfusion; ") ENDIF
            IF (rec_cohort->list[pat_idx].flag_preeclampsia = 1) SET t_score = t_score + 3 SET t_triggers = CONCAT(t_triggers, "Pre-Eclampsia; ") ENDIF
            IF (rec_cohort->list[pat_idx].flag_dvt = 1) SET t_score = t_score + 3 SET t_triggers = CONCAT(t_triggers, "VTE/DVT; ") ENDIF
            IF (rec_cohort->list[pat_idx].flag_epilepsy = 1) SET t_score = t_score + 3 SET t_triggers = CONCAT(t_triggers, "Epilepsy; ") ENDIF
            IF (rec_cohort->list[pat_idx].flag_insulin = 1) SET t_score = t_score + 3 SET t_triggers = CONCAT(t_triggers, "Insulin; ") ENDIF
            IF (rec_cohort->list[pat_idx].flag_antiepileptic = 1) SET t_score = t_score + 3 SET t_triggers = CONCAT(t_triggers, "Antiepileptic; ") ENDIF
            IF (rec_cohort->list[pat_idx].flag_poly_severe = 1) SET t_score = t_score + 3 SET t_triggers = CONCAT(t_triggers, "Severe Polypharmacy; ") ENDIF
            IF (rec_cohort->list[pat_idx].flag_anticoag = 1) SET t_score = t_score + 2 SET t_triggers = CONCAT(t_triggers, "Anticoagulant; ") ENDIF
            IF (rec_cohort->list[pat_idx].flag_antihypertensive = 1) SET t_score = t_score + 2 SET t_triggers = CONCAT(t_triggers, "Antihypertensive; ") ENDIF
            IF (rec_cohort->list[pat_idx].flag_neuraxial = 1) SET t_score = t_score + 1 SET t_triggers = CONCAT(t_triggers, "Neuraxial Infusion; ") ENDIF
            IF (rec_cohort->list[pat_idx].flag_poly_mod = 1) SET t_score = t_score + 1 SET t_triggers = CONCAT(t_triggers, "Mod Polypharmacy; ") ENDIF

            SET rec_cohort->list[pat_idx].score = t_score
            IF (t_score >= 3) SET rec_cohort->list[pat_idx].color = "Red"
            ELSEIF (t_score >= 1) SET rec_cohort->list[pat_idx].color = "Amber"
            ELSE SET rec_cohort->list[pat_idx].color = "Green" ENDIF

            IF (TEXTLEN(t_triggers) > 0) 
                 SET rec_cohort->list[pat_idx].summary = SUBSTRING(1, TEXTLEN(t_triggers)-1, t_triggers)
            ELSE 
                 SET rec_cohort->list[pat_idx].summary = "Routine (Low Risk)" 
            ENDIF
        ENDFOR

        ; 7. Build HTML Rows (Ordered by Score Descending)
        SELECT INTO "NL:"
            PAT_SCORE = rec_cohort->list[D.SEQ].score
        FROM (DUMMYT D WITH SEQ = VALUE(num_pats))
        PLAN D
        ORDER BY PAT_SCORE DESC, D.SEQ
        DETAIL
            v_ward_rows = CONCAT(v_ward_rows,
                "<tr>",
                "<td><b>", rec_cohort->list[D.SEQ].room_bed, "</b></td>",
                "<td><a class='patient-link' href='javascript:APPLINK(0,^Powerchart.exe^,^/PERSONID=", TRIM(CNVTSTRING(rec_cohort->list[D.SEQ].person_id)),
                " /ENCNTRID=", TRIM(CNVTSTRING(rec_cohort->list[D.SEQ].encntr_id)), "^)'>", rec_cohort->list[D.SEQ].name, "</a></td>",
                "<td><span class='badge-", rec_cohort->list[D.SEQ].color, "'>Score: ", TRIM(CNVTSTRING(rec_cohort->list[D.SEQ].score)), "</span></td>",
                "<td>", rec_cohort->list[D.SEQ].summary, "</td>",
                "</tr>"
            )
        WITH NOCOUNTER
    ELSE
        SET v_ward_rows = "<tr><td colspan='4' style='text-align:center; padding: 20px;'>No active patients found on this list.</td></tr>"
    ENDIF

    ; Return HTML rows plus debug info
    SELECT INTO $OUTDEV
    FROM DUMMYT D
    PLAN D
    DETAIL
        call print(CONCAT(""))
        call print(v_ward_rows)
    WITH NOCOUNTER, MAXCOL=32000, FORMAT=VARIABLE, NOHEADING

ELSE
    ; =========================================================================
    ; UI MODE - RENDER DASHBOARD AND DROPDOWN (WHEN WARD_CD IS 0.0)
    ; =========================================================================
    RECORD rec_data (
        1 prsnl_id = f8
        1 prsnl_name = vc
        1 list_cnt = i4
        1 lists[*]
            2 list_id = f8
            2 list_name = vc
    )

    SET rec_data->prsnl_id = CNVTREAL($PRSNL_ID)

    SELECT INTO "NL:"
    FROM PRSNL P
    PLAN P WHERE P.PERSON_ID = rec_data->prsnl_id
    DETAIL
        rec_data->prsnl_name = P.NAME_FULL_FORMATTED
    WITH NOCOUNTER

    SELECT INTO "NL:"
    FROM DCP_PATIENT_LIST DPL
    PLAN DPL WHERE DPL.OWNER_PRSNL_ID = rec_data->prsnl_id
    ORDER BY DPL.NAME
    DETAIL
        rec_data->list_cnt = rec_data->list_cnt + 1
        stat = ALTERLIST(rec_data->lists, rec_data->list_cnt)
        rec_data->lists[rec_data->list_cnt].list_id = DPL.PATIENT_LIST_ID
        rec_data->lists[rec_data->list_cnt].list_name = DPL.NAME
    WITH NOCOUNTER

    SELECT INTO $OUTDEV
    FROM DUMMYT D
    PLAN D
    HEAD REPORT
        ROW + 1 call print(^<!DOCTYPE html>^)
        ROW + 1 call print(^<html><head>^)
        ROW + 1 call print(^<meta http-equiv='X-UA-Compatible' content='IE=edge'>^)
        ROW + 1 call print(^<META content='XMLCCLREQUEST' name='discern'>^)
        ROW + 1 call print(^<title>Pharmacist Acuity Dashboard</title>^)

        ROW + 1 call print(^<script>^)
        ; NEW LOGIC: Declare globally so the Discern browser doesn't garbage collect it
        ROW + 1 call print(^var xhr = null;^)
        
        ROW + 1 call print(^function loadPatients() {^)
        ROW + 1 call print(^    var wardCode = document.getElementById('listSelector').value;^)
        ROW + 1 call print(^    if (wardCode == "0") { alert("Please select a valid patient list."); return; }^)
        ROW + 1 call print(^    document.getElementById('debugWardCode').innerHTML = wardCode;^)
        ROW + 1 call print(^    document.getElementById('triageBody').innerHTML = "<tr><td colspan='4' style='text-align:center; padding: 20px;'><i>Running clinical acuity rules. This may take a few moments...</i></td></tr>";^)
        
        ; NEW LOGIC: Abort any hanging previous request before starting a new one
        ROW + 1 call print(^    if (xhr) { xhr.abort(); }^)
        
        ; NEW LOGIC: Re-initialize the request object into the global variable
        ROW + 1 call print(^    xhr = new XMLCclRequest();^)
        ROW + 1 call print(^    xhr.onreadystatechange = function() {^)
        ROW + 1 call print(^        if (xhr.readyState == 4) {^)
        ROW + 1 call print(^            if (xhr.status == 200) {^)
        ROW + 1 call print(^                document.getElementById('triageBody').innerHTML = xhr.responseText;^)
        ROW + 1 call print(^            } else {^)
        ROW + 1 call print(^                document.getElementById('triageBody').innerHTML = '<tr><td colspan="4" style="color:red;padding:20px;font-family:monospace;">DEBUG - Status: ' + xhr.status + '<br/>Response: ' + xhr.responseText + '</td></tr>';^)
        ROW + 1 call print(^            }^)
        ROW + 1 call print(^        }^)
        ROW + 1 call print(^    };^)
        
        ROW + 1 call print(^    xhr.open('GET', '01_meds_pharm_triage_dash:group1', true);^)
        ROW + 1 call print(CONCAT(^    xhr.send('"MINE", ^, TRIM(CNVTSTRING(rec_data->prsnl_id)), ^, ' + wardCode);^))
        ROW + 1 call print(^}^)
        ROW + 1 call print(^</script>^)

        ROW + 1 call print(^<style>^)
        ROW + 1 call print(^  body { font-family: -apple-system, BlinkMacSystemFont, Segoe UI, Roboto, Arial, sans-serif; background: #f4f6f8; padding: 20px; color: #333; margin: 0; }^)
        ROW + 1 call print(^  .dashboard-header { background: #0076a8; color: #fff; padding: 15px 20px; border-radius: 5px 5px 0 0; font-size: 20px; font-weight: bold; }^)
        ROW + 1 call print(^  .dashboard-content { background: #fff; padding: 20px; border: 1px solid #ddd; border-top: none; border-radius: 0 0 5px 5px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); min-height: 400px; }^)
        ROW + 1 call print(^  .info-box { background: #e9ecef; border-left: 4px solid #6c757d; padding: 10px 15px; margin-bottom: 20px; font-size: 14px; }^)
        ROW + 1 call print(^  select { padding: 8px; font-size: 14px; border: 1px solid #ccc; border-radius: 4px; width: 300px; }^)
        ROW + 1 call print(^  button { padding: 8px 15px; background: #28a745; color: #fff; border: none; border-radius: 4px; cursor: pointer; font-size: 14px; margin-left: 10px; font-weight: bold; }^)
        ROW + 1 call print(^  button:hover { background: #218838; }^)
        ROW + 1 call print(^  .ward-tbl { width: 100%; margin-top: 20px; border-collapse: collapse; font-size: 14px; background: #fff; border: 1px solid #ddd; }^)
        ROW + 1 call print(^  .ward-tbl th, .ward-tbl td { padding: 12px; border-bottom: 1px solid #eee; text-align: left; word-wrap: break-word; overflow-wrap: break-word; white-space: normal; }^)
        ROW + 1 call print(^  .ward-tbl th { background: #f0f4f8; font-weight: bold; color: #333; }^)
        ROW + 1 call print(^  .ward-tbl tr:hover { background: #f9f9f9; }^)
        ROW + 1 call print(^  .badge-Red { background: #dc3545; color: white; padding: 4px 10px; border-radius: 12px; font-weight:bold; font-size:12px; display:inline-block; min-width:60px; text-align:center; }^)
        ROW + 1 call print(^  .badge-Amber { background: #ffc107; color: black; padding: 4px 10px; border-radius: 12px; font-weight:bold; font-size:12px; display:inline-block; min-width:60px; text-align:center; }^)
        ROW + 1 call print(^  .badge-Green { background: #28a745; color: white; padding: 4px 10px; border-radius: 12px; font-weight:bold; font-size:12px; display:inline-block; min-width:60px; text-align:center; }^)
        ROW + 1 call print(^  .patient-link { color: #0076a8; text-decoration: none; font-weight: bold; }^)
        ROW + 1 call print(^  .patient-link:hover { text-decoration: underline; }^)
        ROW + 1 call print(^</style>^)
        ROW + 1 call print(^</head><body>^)

        ROW + 1 call print(^<div class="dashboard-header">Pharmacist Acuity Dashboard</div>^)
        ROW + 1 call print(^<div class="dashboard-content">^)

        ROW + 1 call print(CONCAT(^<div class="info-box">^))
        ROW + 1 call print(CONCAT(^<b>Logged-in User:</b> ^, NULLVAL(rec_data->prsnl_name, "Unknown User"), ^ (PRSNL_ID: ^, TRIM(CNVTSTRING(rec_data->prsnl_id)), ^)<br/>^))
        ROW + 1 call print(CONCAT(^<b>Patient Lists Available:</b> ^, CNVTSTRING(rec_data->list_cnt), ^<br/>^))
        ROW + 1 call print(^<b>Selected Patient List ID:</b> <span id="debugWardCode">none selected</span>^)
        ROW + 1 call print(^</div>^)

        ROW + 1 call print(^<h3>Select a Patient List to Triage</h3>^)

        IF (rec_data->list_cnt > 0)
            ROW + 1 call print(^<select id="listSelector">^)
            ROW + 1 call print(^<option value="0">-- Select a Patient List --</option>^)
            FOR (i = 1 TO rec_data->list_cnt)
                ROW + 1 call print(CONCAT(^<option value="^, TRIM(CNVTSTRING(rec_data->lists[i].list_id)), ^">^, rec_data->lists[i].list_name, ^</option>^))
            ENDFOR
            ROW + 1 call print(^</select>^)
            ROW + 1 call print(^<button onclick="loadPatients()">Load Patients</button>^)
        ELSE
            ROW + 1 call print(^<p style="color: #dc3545;"><i>No active patient lists found.</i></p>^)
        ENDIF

        ROW + 1 call print(^<table class='ward-tbl'>^)
        ROW + 1 call print(^<thead><tr><th>Bed / Room</th><th>Patient Name</th><th>Acuity Score</th><th>Active Triggers</th></tr></thead>^)
        ROW + 1 call print(^<tbody id='triageBody'>^)
        ROW + 1 call print(^<tr><td colspan='4' style='text-align:center; padding: 20px; color:#666;'>Select a patient list and click "Load Patients" to generate the triage list.</td></tr>^)
        ROW + 1 call print(^</tbody></table>^)

        ROW + 1 call print(^</div>^)
        ROW + 1 call print(^</body></html>^)
    WITH NOCOUNTER, MAXCOL=32000, FORMAT=VARIABLE, NOHEADING
ENDIF

END
GO
