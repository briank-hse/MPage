DROP PROGRAM 01_meds_pharm_triage_dash:group1 GO
CREATE PROGRAM 01_meds_pharm_triage_dash:group1

PROMPT
    "Output to File/Printer/MINE" = "MINE",
    "Personnel ID" = 0.0,
    "Ward Code" = 0.0
WITH OUTDEV, PRSNL_ID, WARD_CD

IF (CNVTREAL($WARD_CD) > 0.0)
    ; =========================================================================
    ; DATA FETCH MODE (AJAX) - RUN AMS RULES AND RETURN HTML ROWS ONLY
    ; =========================================================================
    DECLARE curr_ward_cd = f8 WITH noconstant(0.0)
    SET curr_ward_cd = CNVTREAL($WARD_CD)
    
    SET MODIFY MAXVARLEN 268435456
    DECLARE v_output = vc WITH noconstant("")
    DECLARE pat_idx = i4 WITH noconstant(0)
    DECLARE idx = i4 WITH noconstant(0)
    DECLARE num_pats = i4 WITH noconstant(0)
    DECLARE stat = i4 WITH noconstant(0)
    DECLARE err_code = i4 WITH noconstant(0)
    DECLARE err_msg = c132 WITH noconstant("")

    RECORD req_600144 (
        1 patient_list_id = f8
        1 prsnl_id = f8
        1 definition_version = i4
    )
    RECORD rep_600144 (
        1 arguments[*]
            2 argument_name = vc
            2 argument_value = vc
            2 parent_entity_name = vc
            2 parent_entity_id = f8
    )
    RECORD req_600123 (
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
    RECORD rep_600123 (
        1 patients[*]
            2 person_id = f8
            2 encntr_id = f8
    )

    ; Legacy rec_cohort completely retained, with AMS variables appended
    RECORD rec_cohort (
        1 cnt = i4
        1 list[*]
            2 person_id = f8
            2 encntr_id = f8
            2 name = vc
            2 ward_name = vc
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
            2 flag_imews = i2
            2 flag_bsbg = i2
            2 flag_high_alert_iv = i2
            2 flag_oxytocin_iv = i2
            2 flag_delivered = i2
            2 det_high_alert_iv = vc
            2 det_oxytocin = vc
            2 det_transfusion = vc
            2 det_ebl = vc
            2 det_preeclampsia = vc
            2 det_dvt = vc
            2 det_epilepsy = vc
            2 det_insulin = vc
            2 det_antiepileptic = vc
            2 det_anticoag = vc
            2 det_antihypertensive = vc
            2 det_neuraxial = vc
            2 det_imews = vc
            2 det_bsbg = vc
            ; --- NEW AMS VARIABLES APPENDED BELOW ---
            2 ams_active_ind = i2
            2 ams_drug_names = vc
            2 ams_indication = vc
            2 ams_duration = vc
            2 ams_dot_calc = i4
            2 flag_missing_ind = i2
    )

    ; --- Patient List API Execution ---
    SET req_600144->patient_list_id = curr_ward_cd
    SET req_600144->prsnl_id = CNVTREAL($PRSNL_ID)
    SET req_600144->definition_version = 1

    SET stat = tdbexecute(600005, 600024, 600144, "REC", req_600144, "REC", rep_600144)

    SELECT INTO "NL:"
    FROM DCP_PATIENT_LIST DPL
    PLAN DPL WHERE DPL.PATIENT_LIST_ID = curr_ward_cd
    DETAIL req_600123->patient_list_type_cd = DPL.PATIENT_LIST_TYPE_CD
    WITH NOCOUNTER

    SET req_600123->patient_list_id = curr_ward_cd
    SET stat = moverec(rep_600144->arguments, req_600123->arguments)
    SET req_600123->mv_flag = -1
    SET req_600123->rmv_pl_rows_flag = 0

    SET stat = tdbexecute(600005, 600024, 600123, "REC", req_600123, "REC", rep_600123)

    SET err_code = ERROR(err_msg, 1)
    IF (err_code != 0)
        SET v_output = CONCAT("<tr><td colspan='6' style='color:red;'><b>API Execution Failed:</b> ", TRIM(err_msg), "</td></tr>")
    ELSE
        DECLARE api_pats = i4 WITH noconstant(0)
        SET api_pats = SIZE(rep_600123->patients, 5)
        IF (api_pats > 0)
            IF (api_pats > 2000) SET api_pats = 2000 ENDIF

            SELECT INTO "NL:"
            FROM (DUMMYT D WITH SEQ = VALUE(api_pats)), ENCOUNTER E, PERSON P
            PLAN D
            JOIN E WHERE E.ENCNTR_ID = rep_600123->patients[D.SEQ].encntr_id
                AND E.ACTIVE_IND = 1
                AND E.ENCNTR_STATUS_CD = 854.00 
            JOIN P WHERE P.PERSON_ID = E.PERSON_ID AND P.ACTIVE_IND = 1
            ORDER BY E.LOC_ROOM_CD, E.LOC_BED_CD
            DETAIL
                rec_cohort->cnt = rec_cohort->cnt + 1
                stat = alterlist(rec_cohort->list, rec_cohort->cnt)
                rec_cohort->list[rec_cohort->cnt].person_id = P.PERSON_ID
                rec_cohort->list[rec_cohort->cnt].encntr_id = E.ENCNTR_ID
                rec_cohort->list[rec_cohort->cnt].name = P.NAME_FULL_FORMATTED
                rec_cohort->list[rec_cohort->cnt].ward_name = TRIM(UAR_GET_CODE_DISPLAY(E.LOC_NURSE_UNIT_CD))
                rec_cohort->list[rec_cohort->cnt].room_bed = CONCAT(TRIM(UAR_GET_CODE_DISPLAY(E.LOC_ROOM_CD)), "-", TRIM(UAR_GET_CODE_DISPLAY(E.LOC_BED_CD)))
            WITH NOCOUNTER
        ENDIF
        
        SET num_pats = rec_cohort->cnt

        IF (num_pats > 0)
            ; -------------------------------------------------------------
            ; AMS RULE 1: IDENTIFY ANTIMICROBIALS & INDICATIONS
            ; -------------------------------------------------------------
            SELECT INTO "NL:"
            FROM ORDERS O,
                 ORDER_DETAIL OD_IND,
                 ORDER_DETAIL OD_DUR
            PLAN O WHERE EXPAND(pat_idx, 1, num_pats, O.PERSON_ID, rec_cohort->list[pat_idx].person_id)
                AND O.CATALOG_TYPE_CD = 2516.00 ; Pharmacy 
                AND O.ACTIVE_IND = 1
                AND O.ORIG_ORD_AS_FLAG = 0 ; Normal order 
            JOIN OD_IND WHERE outerjoin(O.ORDER_ID) = OD_IND.ORDER_ID
                AND OD_IND.OE_FIELD_MEANING_ID = outerjoin(15) ; 15-INDICATION 
            JOIN OD_DUR WHERE outerjoin(O.ORDER_ID) = OD_DUR.ORDER_ID
                AND OD_DUR.OE_FIELD_MEANING_ID = outerjoin(2061) ; 2061-DURATION 
            DETAIL
                pat_idx = LOCATEVAL(idx, 1, num_pats, O.PERSON_ID, rec_cohort->list[idx].person_id)
                IF (pat_idx > 0)
                    ; SET command removed here (inside query block)
                    rec_cohort->list[pat_idx].ams_active_ind = 1
                    rec_cohort->list[pat_idx].ams_drug_names = CONCAT(rec_cohort->list[pat_idx].ams_drug_names, O.HNA_ORDER_MNEMONIC, "<br>")
                    
                    IF (OD_IND.OE_FIELD_DISPLAY_VALUE != "")
                        rec_cohort->list[pat_idx].ams_indication = OD_IND.OE_FIELD_DISPLAY_VALUE
                    ELSE
                        rec_cohort->list[pat_idx].flag_missing_ind = 1
                    ENDIF
                    
                    IF (OD_DUR.OE_FIELD_DISPLAY_VALUE != "")
                        rec_cohort->list[pat_idx].ams_duration = OD_DUR.OE_FIELD_DISPLAY_VALUE
                    ENDIF
                ENDIF
            WITH NOCOUNTER, EXPAND = 1
            
            ; -------------------------------------------------------------
            ; AMS RULE 2: CALCULATE DOT FROM ADMINISTRATIONS
            ; -------------------------------------------------------------
            SELECT INTO "NL:"
            FROM MED_ADMIN_EVENT MAE,
                 CLINICAL_EVENT CE,
                 ORDERS O
            PLAN O WHERE EXPAND(pat_idx, 1, num_pats, O.PERSON_ID, rec_cohort->list[pat_idx].person_id)
                 AND O.CATALOG_TYPE_CD = 2516.00
                 AND O.ACTIVE_IND = 1
            JOIN MAE WHERE MAE.TEMPLATE_ORDER_ID = O.ORDER_ID
                 AND MAE.EVENT_TYPE_CD = 8912520.00 ; "Administered" 
            JOIN CE WHERE CE.EVENT_ID = MAE.EVENT_ID
                 AND CE.RESULT_STATUS_CD IN (25.0, 35.0) ; auth, modified 
                 AND CE.VALID_UNTIL_DT_TM > CNVTDATETIME(CURDATE, CURTIME)
            DETAIL
                pat_idx = LOCATEVAL(idx, 1, num_pats, CE.PERSON_ID, rec_cohort->list[idx].person_id)
                IF (pat_idx > 0)
                    ; SET command removed here (inside query block)
                    rec_cohort->list[pat_idx].ams_dot_calc = rec_cohort->list[pat_idx].ams_dot_calc + 1
                ENDIF
            WITH NOCOUNTER, EXPAND = 1
        ENDIF

        ; -------------------------------------------------------------
        ; GENERATE HTML ROWS
        ; -------------------------------------------------------------
        FOR (pat_idx = 1 TO num_pats)
            IF (rec_cohort->list[pat_idx].ams_active_ind = 1)
                IF (rec_cohort->list[pat_idx].flag_missing_ind = 1)
                    ; SET command remains here (outside query block)
                    SET rec_cohort->list[pat_idx].summary = "<span class='pill pill-red'>Missing Indication</span>"
                ELSE
                    SET rec_cohort->list[pat_idx].summary = "<span class='pill pill-gray'>Routine</span>"
                ENDIF

                SET v_output = CONCAT(v_output,
                    "<tr>",
                    "<td><b>", rec_cohort->list[pat_idx].room_bed, "</b></td>",
                    "<td>", rec_cohort->list[pat_idx].name, "</td>",
                    "<td>", rec_cohort->list[pat_idx].ams_drug_names, "</td>",
                    "<td>", TRIM(CNVTSTRING(rec_cohort->list[pat_idx].ams_dot_calc)), "</td>",
                    "<td>", rec_cohort->list[pat_idx].ams_indication, "</td>",
                    "<td>", rec_cohort->list[pat_idx].summary, "</td>",
                    "</tr>"
                )
            ENDIF
        ENDFOR
        
        IF (TEXTLEN(v_output) = 0)
            SET v_output = "<tr><td colspan='6' style='text-align:center; padding: 20px;'>No patients on active antimicrobials found.</td></tr>"
        ENDIF

    ENDIF

    SET _memory_reply_string = v_output

ELSE
    ; =========================================================================
    ; UI MODE - RENDER DASHBOARD (WHEN WARD_CD IS 0.0)
    ; =========================================================================
    
    RECORD rec_data (
        1 prsnl_id = f8
        1 prsnl_name = vc
        1 list_cnt = i4
        1 lists[*]
            2 list_id = f8
            2 list_name = vc
    )

    DECLARE i = i4 WITH noconstant(0)
    SET rec_data->prsnl_id = CNVTREAL($PRSNL_ID)

    SELECT INTO "NL:"
    FROM PRSNL P
    PLAN P WHERE P.PERSON_ID = rec_data->prsnl_id
    DETAIL rec_data->prsnl_name = P.NAME_FULL_FORMATTED
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
        ROW + 1 call print(^<title>Antimicrobial Stewardship Dashboard</title>^)
        
        ROW + 1 call print(^<script>^)
        ROW + 1 call print(^var xhr = null;^)
        ROW + 1 call print(^function loadPatients() {^)
        ROW + 1 call print(^    var wardCode = document.getElementById('listSelector').value;^)
        ROW + 1 call print(^    if (wardCode == "0") { alert("Please select a ward list."); return; }^)
        ROW + 1 call print(^    document.getElementById('triageBody').innerHTML = "<tr><td colspan='6' style='text-align:center; padding: 20px;'><i>Calculating AMS metrics. Please wait...</i></td></tr>";^)
        ROW + 1 call print(^    if (xhr) { xhr.abort(); }^)
        ROW + 1 call print(^    xhr = new XMLCclRequest();^)
        ROW + 1 call print(^    xhr.onreadystatechange = function() {^)
        ROW + 1 call print(^        if (xhr.readyState == 4 && xhr.status == 200) {^)
        ROW + 1 call print(^            document.getElementById('triageBody').innerHTML = xhr.responseText;^)
        ROW + 1 call print(^        }^)
        ROW + 1 call print(^    };^)
        ROW + 1 call print(^    xhr.open('GET', '01_meds_ams_dashboard:group1', true);^)
        ROW + 1 call print(CONCAT(^    xhr.send('"MINE", ^, TRIM(CNVTSTRING(rec_data->prsnl_id)), ^, ' + wardCode);^))
        ROW + 1 call print(^}^)
        ROW + 1 call print(^</script>^)
        
        ROW + 1 call print(^<style>^)
        ROW + 1 call print(^  body { font-family: Tahoma, Arial, sans-serif; background: #ffffff; padding: 10px; color: #333; margin: 0; font-size: 12px; }^)
        ROW + 1 call print(^  .dashboard-header { background: #0D66A1; color: #fff; padding: 6px 12px; font-size: 14px; font-weight: bold; }^)
        ROW + 1 call print(^  .dashboard-content { background: #fff; padding: 15px; border: 1px solid #ccc; border-top: none; min-height: 400px; }^)
        ROW + 1 call print(^  select { padding: 4px; font-size: 12px; border: 1px solid #7a9ea9; width: 300px; font-family: Tahoma, Arial, sans-serif; }^)
        ROW + 1 call print(^  button { padding: 4px 12px; background: #e0e0e0; color: #333; border: 1px solid #7a9ea9; cursor: pointer; font-size: 12px; margin-left: 10px; }^)
        ROW + 1 call print(^  .ward-tbl { width: 100%; margin-top: 15px; border-collapse: collapse; font-size: 12px; border: 1px solid #ccc; }^)
        ROW + 1 call print(^  .ward-tbl th, .ward-tbl td { padding: 6px 8px; border-bottom: 1px solid #e0e0e0; text-align: left; }^)
        ROW + 1 call print(^  .ward-tbl th { background: #f0f0f0; font-weight: bold; border-bottom: 2px solid #ccc; }^)
        ROW + 1 call print(^  .pill { display: inline-block; padding: 2px 6px; border-radius: 12px; color: #fff; font-weight: bold; font-size: 11px; }^)
        ROW + 1 call print(^  .pill-red { background: #cc0000; }^)
        ROW + 1 call print(^  .pill-gray { background: #6c757d; }^)
        ROW + 1 call print(^</style>^)
        ROW + 1 call print(^</head><body>^)

        ROW + 1 call print(^<div class="dashboard-header">Antimicrobial Stewardship Dashboard (PoC)</div>^)
        ROW + 1 call print(^<div class="dashboard-content">^)
        
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
        ROW + 1 call print(^<thead><tr><th>Bed</th><th>Patient</th><th>Antibiotic(s)</th><th>DOT count</th><th>Indication</th><th>AMS Flags</th></tr></thead>^)
        ROW + 1 call print(^<tbody id='triageBody'>^)
        ROW + 1 call print(^<tr><td colspan='6' style='text-align:center; padding: 20px; color:#666;'>Select a ward list to generate AMS tracking.</td></tr>^)
        ROW + 1 call print(^</tbody></table></div>^)
        ROW + 1 call print(^</body></html>^)
    WITH NOCOUNTER, MAXCOL=65534, FORMAT=VARIABLE, NOHEADING
ENDIF
END
GO