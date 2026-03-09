DROP PROGRAM 01_VTE_ASSESS_DASH_GH_V2:group1 GO
CREATE PROGRAM 01_VTE_ASSESS_DASH_GH_V2:group1

PROMPT
    "Output to File/Printer/MINE" = "MINE",
    "Personnel ID" = 0.0,
    "Ward Code" = 0.0
WITH OUTDEV, PRSNL_ID, WARD_CD

IF (CNVTREAL($WARD_CD) > 0.0)

    ; =========================================================================
    ; DATA FETCH MODE - VTE GUIDELINE DOSING VERIFICATION
    ; =========================================================================
    DECLARE curr_ward_cd = f8 WITH noconstant(CNVTREAL($WARD_CD))
    SET MODIFY MAXVARLEN 32000000

    DECLARE i            = i4 WITH noconstant(0)
    DECLARE m            = i4 WITH noconstant(0)
    DECLARE stat         = i4 WITH noconstant(0)
    DECLARE num_pats     = i4 WITH noconstant(0)
    DECLARE idx          = i4 WITH noconstant(0)
    
    DECLARE UNOM         = vc WITH noconstant("")
    DECLARE VAL          = vc WITH noconstant("")
    DECLARE temp_cdl     = vc WITH noconstant("")
    DECLARE dose_chunk   = vc WITH noconstant("")
    DECLARE final_num    = vc WITH noconstant("")
    
    DECLARE is_ghost     = i2 WITH noconstant(0)
    DECLARE has_vte_med  = i2 WITH noconstant(0)
    
    DECLARE pat_cursor   = i4 WITH noconstant(1)
    DECLARE batch_len    = i4 WITH noconstant(0)
    
    DECLARE t_dose_idx   = i4 WITH noconstant(0)
    DECLARE t_exp        = i4 WITH noconstant(0)
    
    ; Synchronized Weight Trackers
    DECLARE max_wt_dt    = dq8 WITH noconstant(0.0)
    DECLARE max_wt_val   = vc WITH noconstant("")

    ; --- STRICT DOSING WEIGHT CODES ONLY ---
    DECLARE w_dosing      = f8 WITH noconstant(UAR_GET_CODE_BY("DISPLAYKEY", 72, "WEIGHTDOSING"))
    DECLARE w_local_hard = f8 WITH noconstant(14516898.00) ; Hardcoded Dosing Weight 

    DECLARE PATIENT_LIMIT = i4 WITH noconstant(300)

    ; Core Patient Record
    RECORD rec_cohort (
        1 status_msg = vc       
        1 cnt = i4
        1 list[*]
            2 person_id   = f8
            2 encntr_id   = f8
            2 name        = vc
            2 room_bed    = vc
            
            ; --- WEIGHT VARIABLES ---
            2 weight_val  = vc
            2 weight_dt   = vc
            2 weight_num  = f8
            
            ; --- VTE VARIABLES ---
            2 med_cnt      = i4
            2 ui_color     = vc
            2 needs_review = i2
            2 patient_priority = i4
            2 meds[*]
                3 order_id       = f8
                3 mnemonic       = vc
                3 raw_cdl        = vc   
                3 actual_dose    = i4
                3 expected_dose  = i4
                3 dose_status    = vc
                3 dose_color     = vc
    )

    ; Array to protect database from timeouts
    RECORD batch_req ( 1 cnt = i4 1 list[50] 2 p_idx = i4 2 person_id = f8 2 encntr_id = f8 )

    RECORD 600144_request ( 1 patient_list_id = f8 1 prsnl_id = f8 1 definition_version = i4 )
    RECORD 600144_reply ( 1 arguments[*] 2 argument_name = vc 2 argument_value = vc 2 parent_entity_name = vc 2 parent_entity_id = f8 )
    RECORD 600123_request ( 1 patient_list_id = f8 1 patient_list_type_cd = f8 1 mv_flag = i2 1 rmv_pl_rows_flag = i2 1 arguments[*] 2 argument_name = vc 2 argument_value = vc 2 parent_entity_name = vc 2 parent_entity_id = f8 )
    RECORD 600123_reply ( 1 patients[*] 2 person_id = f8 2 encntr_id = f8 )

    ; --- 1. Fetch Patient List ---
    SET 600144_request->patient_list_id = curr_ward_cd
    SET 600144_request->prsnl_id = CNVTREAL($PRSNL_ID)
    SET 600144_request->definition_version = 1
    SET stat = tdbexecute(600005, 600024, 600144, "REC", 600144_request, "REC", 600144_reply)

    SELECT INTO "NL:" FROM DCP_PATIENT_LIST DPL PLAN DPL WHERE DPL.PATIENT_LIST_ID = curr_ward_cd
    DETAIL 600123_request->patient_list_type_cd = DPL.PATIENT_LIST_TYPE_CD WITH NOCOUNTER

    SET 600123_request->patient_list_id = curr_ward_cd
    SET stat = moverec(600144_reply->arguments, 600123_request->arguments)
    SET 600123_request->mv_flag = -1
    SET 600123_request->rmv_pl_rows_flag = 0
    SET stat = tdbexecute(600005, 600024, 600123, "REC", 600123_request, "REC", 600123_reply)

    DECLARE api_pats = i4 WITH noconstant(SIZE(600123_reply->patients, 5))

    IF (api_pats > 0)
        SELECT INTO "NL:"
        FROM (DUMMYT D WITH SEQ = VALUE(api_pats)), ENCOUNTER E, PERSON P
        PLAN D
        JOIN E WHERE E.ENCNTR_ID = 600123_reply->patients[D.SEQ].encntr_id AND E.ACTIVE_IND = 1 AND E.ENCNTR_STATUS_CD = 854.00
        JOIN P WHERE P.PERSON_ID = E.PERSON_ID AND P.ACTIVE_IND = 1
        ORDER BY E.LOC_ROOM_CD, E.LOC_BED_CD
        DETAIL
            rec_cohort->cnt = rec_cohort->cnt + 1
            stat = ALTERLIST(rec_cohort->list, rec_cohort->cnt)
            rec_cohort->list[rec_cohort->cnt].person_id = P.PERSON_ID
            rec_cohort->list[rec_cohort->cnt].encntr_id = E.ENCNTR_ID
            rec_cohort->list[rec_cohort->cnt].name = P.NAME_FULL_FORMATTED
            rec_cohort->list[rec_cohort->cnt].room_bed = CONCAT(TRIM(UAR_GET_CODE_DISPLAY(E.LOC_ROOM_CD)), "-", TRIM(UAR_GET_CODE_DISPLAY(E.LOC_BED_CD)))
            rec_cohort->list[rec_cohort->cnt].weight_val = "Not Recorded"
            rec_cohort->list[rec_cohort->cnt].weight_dt = ""
            rec_cohort->list[rec_cohort->cnt].weight_num = 0.0
            rec_cohort->list[rec_cohort->cnt].ui_color = "green"
            rec_cohort->list[rec_cohort->cnt].patient_priority = 0
        WITH NOCOUNTER
    ENDIF

    SET num_pats = rec_cohort->cnt
    SET rec_cohort->status_msg = "OK"

    IF (num_pats > PATIENT_LIMIT)
        SET rec_cohort->status_msg = CONCAT("LIMIT_EXCEEDED|", TRIM(CNVTSTRING(num_pats)))
    ELSEIF (num_pats > 0)
        
        ; =====================================================================
        ; STEP 1: FIND VTE ORDERS
        ; =====================================================================
        SET pat_cursor = 1
        WHILE (pat_cursor <= num_pats)
            SET batch_len = 0
            WHILE (batch_len < 50 AND pat_cursor <= num_pats)
                SET batch_len = batch_len + 1
                SET batch_req->list[batch_len].p_idx = pat_cursor
                SET batch_req->list[batch_len].person_id = rec_cohort->list[pat_cursor].person_id
                SET batch_req->list[batch_len].encntr_id = rec_cohort->list[pat_cursor].encntr_id
                SET pat_cursor = pat_cursor + 1
            ENDWHILE
            SET batch_req->cnt = batch_len

            SELECT INTO "NL:"
            FROM (DUMMYT D WITH SEQ = VALUE(batch_req->cnt)), ORDERS O
            PLAN D
            JOIN O WHERE O.PERSON_ID = batch_req->list[D.SEQ].person_id
                     AND O.ENCNTR_ID = batch_req->list[D.SEQ].encntr_id
                     AND O.CATALOG_TYPE_CD = 2516.00 
                     AND O.ORDER_STATUS_CD IN (2550.00, 2549.00) 
                     AND O.ACTIVE_IND = 1
                     AND O.ORIG_ORD_AS_FLAG = 0
            DETAIL
                idx = batch_req->list[D.SEQ].p_idx
                UNOM = CNVTUPPER(O.ORDER_MNEMONIC)
                is_ghost = 0
                
                IF (O.PROJECTED_STOP_DT_TM > 0.0 AND O.PROJECTED_STOP_DT_TM < CNVTDATETIME(CURDATE, CURTIME3))
                    is_ghost = 1
                ENDIF
                
                IF (is_ghost = 0)
                    IF (FINDSTRING("ENOXAPARIN", UNOM) > 0 OR FINDSTRING("TINZAPARIN", UNOM) > 0)
                        rec_cohort->list[idx].med_cnt = rec_cohort->list[idx].med_cnt + 1
                        stat = ALTERLIST(rec_cohort->list[idx].meds, rec_cohort->list[idx].med_cnt)
                        
                        rec_cohort->list[idx].meds[rec_cohort->list[idx].med_cnt].order_id = O.ORDER_ID
                        rec_cohort->list[idx].meds[rec_cohort->list[idx].med_cnt].mnemonic = O.ORDER_MNEMONIC
                        rec_cohort->list[idx].meds[rec_cohort->list[idx].med_cnt].raw_cdl = O.CLINICAL_DISPLAY_LINE
                        rec_cohort->list[idx].meds[rec_cohort->list[idx].med_cnt].actual_dose = 0
                    ENDIF
                ENDIF
            WITH NOCOUNTER
        ENDWHILE

        ; =====================================================================
        ; STEP 2: PULL DOSING WEIGHTS ONLY FOR VTE PATIENTS 
        ; =====================================================================
        FOR (i = 1 TO num_pats)
            IF (rec_cohort->list[i].med_cnt > 0)
                SET max_wt_dt = 0.0
                SET max_wt_val = ""
                
                SELECT INTO "NL:"
                FROM CLINICAL_EVENT CE
                PLAN CE WHERE CE.PERSON_ID = rec_cohort->list[i].person_id
                          AND CE.EVENT_CD IN (w_local_hard, w_dosing)
                          AND CE.VALID_UNTIL_DT_TM > CNVTDATETIME(CURDATE, CURTIME3)
                          AND CE.RESULT_STATUS_CD IN (24, 25, 28, 34, 35)
                DETAIL
                    VAL = TRIM(CE.RESULT_VAL, 3)
                    IF (VAL != "") 
                        IF (CE.EVENT_END_DT_TM > max_wt_dt)
                            max_wt_dt = CE.EVENT_END_DT_TM
                            max_wt_val = VAL
                        ENDIF
                    ENDIF
                FOOT REPORT
                    IF (max_wt_val != "")
                        rec_cohort->list[i].weight_val = CONCAT(max_wt_val, " kg")
                        rec_cohort->list[i].weight_dt = FORMAT(max_wt_dt, "DD-MMM-YYYY HH:MM;;D")
                        rec_cohort->list[i].weight_num = CNVTREAL(max_wt_val)
                    ENDIF
                WITH NOCOUNTER
            ENDIF
        ENDFOR
        
        ; =====================================================================
        ; STEP 3: SURGICAL PARSER & GUIDELINE LOGIC
        ; =====================================================================
        FOR (i = 1 TO num_pats)
            SET has_vte_med = 0
            IF (rec_cohort->list[i].med_cnt > 0)
                SET has_vte_med = 1
            ENDIF
            
            FOR (m = 1 TO rec_cohort->list[i].med_cnt)
                ; Force upper case and systematically strip commas (e.g. "4,500" -> "4500")
                SET temp_cdl = REPLACE(CNVTUPPER(rec_cohort->list[i].meds[m].raw_cdl), ",", "", 0)
                SET UNOM = CNVTUPPER(rec_cohort->list[i].meds[m].mnemonic)
                
                ; --- Clean Prefix Parser ---
                SET t_dose_idx = FINDSTRING("DOSE:", temp_cdl)
                IF (t_dose_idx > 0)
                    ; Snip off everything after DOSE: and strip leading spaces
                    SET dose_chunk = TRIM(SUBSTRING(t_dose_idx + 5, 100, temp_cdl), 3)
                    ; Isolate just the first space-delimited block (e.g. "4500")
                    SET final_num = PIECE(dose_chunk, " ", 1, "")
                    SET rec_cohort->list[i].meds[m].actual_dose = CNVTINT(final_num)
                ELSE
                    SET rec_cohort->list[i].meds[m].actual_dose = 0
                ENDIF
                
                ; --- RCOG Guideline Math ---
                SET t_exp = 0
                IF (rec_cohort->list[i].weight_num > 0.0)
                    IF (FINDSTRING("ENOXAPARIN", UNOM) > 0)
                        IF (rec_cohort->list[i].weight_num < 50.0) SET t_exp = 20
                        ELSEIF (rec_cohort->list[i].weight_num < 73.0) SET t_exp = 40
                        ELSEIF (rec_cohort->list[i].weight_num < 87.0) SET t_exp = 50
                        ELSEIF (rec_cohort->list[i].weight_num < 99.0) SET t_exp = 60
                        ELSEIF (rec_cohort->list[i].weight_num < 112.0) SET t_exp = 70
                        ELSEIF (rec_cohort->list[i].weight_num < 127.0) SET t_exp = 80
                        ELSEIF (rec_cohort->list[i].weight_num <= 140.0) SET t_exp = 90
                        ELSE SET t_exp = 99999 ; >140kg protocol
                        ENDIF
                    ELSEIF (FINDSTRING("TINZAPARIN", UNOM) > 0)
                        IF (rec_cohort->list[i].weight_num < 50.0) SET t_exp = 3500
                        ELSEIF (rec_cohort->list[i].weight_num < 73.0) SET t_exp = 4500
                        ELSEIF (rec_cohort->list[i].weight_num < 87.0) SET t_exp = 6000
                        ELSEIF (rec_cohort->list[i].weight_num < 99.0) SET t_exp = 7000
                        ELSEIF (rec_cohort->list[i].weight_num < 112.0) SET t_exp = 8000
                        ELSEIF (rec_cohort->list[i].weight_num < 127.0) SET t_exp = 9000
                        ELSEIF (rec_cohort->list[i].weight_num <= 140.0) SET t_exp = 10000
                        ELSE SET t_exp = 99999 ; >140kg protocol
                        ENDIF
                    ENDIF
                ENDIF
                
                SET rec_cohort->list[i].meds[m].expected_dose = t_exp
                
                ; --- Status Assignment ---
                IF (rec_cohort->list[i].weight_num = 0.0)
                    SET rec_cohort->list[i].meds[m].dose_status = "Pending Dosing Weight"
                    SET rec_cohort->list[i].meds[m].dose_color = "red"
                ELSEIF (t_exp = 0)
                    SET rec_cohort->list[i].meds[m].dose_status = "Non-Standard / Manual Review"
                    SET rec_cohort->list[i].meds[m].dose_color = "gray"
                ELSEIF (t_exp = 99999)
                    SET rec_cohort->list[i].meds[m].dose_status = ">140kg: Seek specialist advice"
                    SET rec_cohort->list[i].meds[m].dose_color = "red"
                ELSEIF (rec_cohort->list[i].meds[m].actual_dose = 0)
                    SET rec_cohort->list[i].meds[m].dose_status = CONCAT("Target: ", TRIM(CNVTSTRING(t_exp)), " (Verify dosage manually)")
                    SET rec_cohort->list[i].meds[m].dose_color = "orange"
                ELSEIF (rec_cohort->list[i].meds[m].actual_dose = t_exp)
                    SET rec_cohort->list[i].meds[m].dose_status = CONCAT("Guideline Match (", TRIM(CNVTSTRING(t_exp)), ")")
                    SET rec_cohort->list[i].meds[m].dose_color = "green"
                ELSEIF (rec_cohort->list[i].meds[m].actual_dose > t_exp)
                    SET rec_cohort->list[i].meds[m].dose_status = CONCAT("POTENTIAL OVERDOSE (Target: ", TRIM(CNVTSTRING(t_exp)), ")")
                    SET rec_cohort->list[i].meds[m].dose_color = "red"
                ELSE
                    SET rec_cohort->list[i].meds[m].dose_status = CONCAT("POTENTIAL UNDERDOSE (Target: ", TRIM(CNVTSTRING(t_exp)), ")")
                    SET rec_cohort->list[i].meds[m].dose_color = "red"
                ENDIF
            ENDFOR
            
            ; --- Priority Engine for Row Sorting ---
            IF (has_vte_med = 1)
                SET rec_cohort->list[i].ui_color = "green" 
                SET rec_cohort->list[i].patient_priority = 500 ; Default safe
                
                IF (rec_cohort->list[i].weight_num = 0.0)
                    SET rec_cohort->list[i].ui_color = "red"
                    SET rec_cohort->list[i].patient_priority = 1000 ; Bump missing weights to absolute top
                ENDIF
                
                FOR (m = 1 TO rec_cohort->list[i].med_cnt)
                    IF (rec_cohort->list[i].meds[m].dose_color = "red")
                        SET rec_cohort->list[i].ui_color = "red"
                        SET rec_cohort->list[i].patient_priority = 900 ; Bump mismatches above green
                    ELSEIF (rec_cohort->list[i].meds[m].dose_color = "orange" AND rec_cohort->list[i].patient_priority < 800)
                        SET rec_cohort->list[i].ui_color = "orange"
                        SET rec_cohort->list[i].patient_priority = 800 ; Bump parses issues above green
                    ENDIF
                ENDFOR
            ENDIF
        ENDFOR
    ENDIF

    ; =========================================================================
    ; JSON EXPORT
    ; =========================================================================
    SET _memory_reply_string = cnvtrectojson(rec_cohort)

ELSE
    ; =========================================================================
    ; UI MODE - SPA FRONTEND
    ; =========================================================================
    RECORD rec_data ( 1 prsnl_id = f8 1 prsnl_name = vc 1 list_cnt = i4 1 lists[*] 2 list_id = f8 2 list_name = vc )

    SET rec_data->prsnl_id = CNVTREAL($PRSNL_ID)

    SELECT INTO "NL:" FROM PRSNL P PLAN P WHERE P.PERSON_ID = rec_data->prsnl_id DETAIL rec_data->prsnl_name = P.NAME_FULL_FORMATTED WITH NOCOUNTER
    SELECT INTO "NL:" FROM DCP_PATIENT_LIST DPL PLAN DPL WHERE DPL.OWNER_PRSNL_ID = rec_data->prsnl_id ORDER BY DPL.NAME
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
        ROW + 1 call print(^<!DOCTYPE html><html><head>^)
        ROW + 1 call print(^<meta http-equiv='X-UA-Compatible' content='IE=edge'>^)
        ROW + 1 call print(^<META content='XMLCCLREQUEST' name='discern'>^)
        ROW + 1 call print(^<title>VTE Dosing Review</title>^)
        ROW + 1 call print(^<script>^)
        ROW + 1 call print(^var xhr = null;^)
        
        ROW + 1 call print(^function loadPatients() {^)
        ROW + 1 call print(^    var wardCode = document.getElementById('listSelector').value;^)
        ROW + 1 call print(^    if (wardCode == "0") return;^)
        ROW + 1 call print(^    document.getElementById('triageBody').innerHTML = "<tr><td colspan='3' style='text-align:center; padding: 50px;'><h3 style='color:#2b6cb0; margin:0;'>Retrieving VTE Orders & Calculating Guidelines...</h3></td></tr>";^)
        
        ROW + 1 call print(^    xhr = new XMLCclRequest();^)
        ROW + 1 call print(^    xhr.onreadystatechange = function() {^)
        ROW + 1 call print(^        if (xhr.readyState == 4) {^)
        ROW + 1 call print(^            if (xhr.status == 200) { renderTable(xhr.responseText); }^)
        ROW + 1 call print(^            else if (xhr.status == 500) { renderTimeoutWarning(); }^) 
        ROW + 1 call print(^            else { document.getElementById('triageBody').innerHTML = '<tr><td colspan="3" style="text-align:center; padding:60px 20px;"><div class="warning-box"><h3 style="margin-top:0;">&#8505;&#65039; HTTP Error ' + xhr.status + '</h3><p>An unexpected network error occurred.</p></div></td></tr>'; }^)
        ROW + 1 call print(^        }^)
        ROW + 1 call print(^    };^)
        ; CRITICAL FIX: The program name is updated here to match the current script name
        ROW + 1 call print(^    xhr.open('GET', '01_VTE_ASSESS_DASH_GH_V2:group1', true);^)
        ROW + 1 call print(CONCAT(^    xhr.send('"MINE", ^, TRIM(CNVTSTRING(rec_data->prsnl_id)), ^, ' + wardCode);^))
        ROW + 1 call print(^}^)

        ROW + 1 call print(^function renderTimeoutWarning() {^)
        ROW + 1 call print(^    var msgHtml = "<tr><td colspan='3' style='text-align:center; padding: 60px 20px;'>";^)
        ROW + 1 call print(^    msgHtml += "<div class='warning-box'>";^)
        ROW + 1 call print(^    msgHtml += "<h3 style='margin-top:0;'>&#8505;&#65039; System Notice: Query Timeout</h3>";^)
        ROW + 1 call print(^    msgHtml += "<p>The requested data volume exceeds standard reporting execution limits.</p>";^)
        ROW + 1 call print(^    msgHtml += "</div></td></tr>";^)
        ROW + 1 call print(^    document.getElementById('triageBody').innerHTML = msgHtml;^)
        ROW + 1 call print(^}^)

        ROW + 1 call print(^function escapeHTML(str) {^)
        ROW + 1 call print(^    if(!str) return "";^)
        ROW + 1 call print(^    return str.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#039;");^)
        ROW + 1 call print(^}^)

        ROW + 1 call print(^function renderTable(jsonString) {^)
        ROW + 1 call print(^    try {^)
        ROW + 1 call print(^        var data = JSON.parse(jsonString);^)
        ROW + 1 call print(^        var root = data.REC_COHORT || data.rec_cohort;^)
        
        ROW + 1 call print(^        var statusMsg = root.STATUS_MSG || root.status_msg || "";^)
        ROW + 1 call print(^        if (statusMsg.indexOf("LIMIT_EXCEEDED") > -1) {^)
        ROW + 1 call print(^            var pCnt = statusMsg.split("|")[1];^)
        ROW + 1 call print(^            var msgHtml = "<tr><td colspan='3' style='text-align:center; padding: 60px 20px;'>";^)
        ROW + 1 call print(^            msgHtml += "<div class='warning-box'>";^)
        ROW + 1 call print(^            msgHtml += "<h3 style='margin-top:0;'>&#8505;&#65039; System Notice: Parameter Exceeded</h3>";^)
        ROW + 1 call print(^            msgHtml += "<p>The selected list requests queries for <b>" + pCnt + "</b> concurrent records. The limit is 300.</p>";^)
        ROW + 1 call print(^            msgHtml += "</div></td></tr>";^)
        ROW + 1 call print(^            document.getElementById('triageBody').innerHTML = msgHtml;^)
        ROW + 1 call print(^            return;^)
        ROW + 1 call print(^        }^)

        ROW + 1 call print(^        var list = root.LIST || root.list || [];^)
        ROW + 1 call print(^        if (!Array.isArray(list)) { list = [list]; }^) 
        
        ROW + 1 call print(^        if (list.length === 0) { document.getElementById('triageBody').innerHTML = "<tr><td colspan='3' align='center'>No active patients found.</td></tr>"; return; }^)
        
        ; ---> SORTING ENGINE: Highest risk bubbles to the top <---
        ROW + 1 call print(^        list.sort(function(a,b) {^)
        ROW + 1 call print(^            var pA = parseInt(a.PATIENT_PRIORITY || a.patient_priority || 0, 10);^)
        ROW + 1 call print(^            var pB = parseInt(b.PATIENT_PRIORITY || b.patient_priority || 0, 10);^)
        ROW + 1 call print(^            return pB - pA;^)
        ROW + 1 call print(^        });^)
        
        ROW + 1 call print(^        var html = '';^)
        ROW + 1 call print(^        var renderedCount = 0;^)
        
        ROW + 1 call print(^        for (var i=0; i<list.length; i++) {^)
        ROW + 1 call print(^            var pat = list[i];^)
        ROW + 1 call print(^            var mcnt = pat.MED_CNT || pat.med_cnt || 0;^)
        
        ; HIDE PATIENTS WITHOUT VTE MEDS
        ROW + 1 call print(^            if (mcnt === 0) continue;^)
        ROW + 1 call print(^            renderedCount++;^)
        
        ROW + 1 call print(^            var name = pat.NAME || pat.name || "";^)
        ROW + 1 call print(^            var enc = pat.ENCNTR_ID || pat.encntr_id || "";^)
        ROW + 1 call print(^            var per = pat.PERSON_ID || pat.person_id || "";^)
        ROW + 1 call print(^            var bed = pat.ROOM_BED || pat.room_bed || "";^)
        ROW + 1 call print(^            var wgt = pat.WEIGHT_VAL || pat.weight_val || "Not Recorded";^)
        ROW + 1 call print(^            var wgt_dt = pat.WEIGHT_DT || pat.weight_dt || "";^)
        ROW + 1 call print(^            var uiCol = pat.UI_COLOR || pat.ui_color || "green";^)
        
        ROW + 1 call print(^            var rowClass = "row-" + uiCol;^)
        
        ROW + 1 call print(^            html += "<tr class='" + rowClass + "'>";^)
        ROW + 1 call print(^            html += "<td style='width:25%; border-right:1px dashed #e2e8f0; vertical-align:top;'>";^)
        ROW + 1 call print(^            html += "<div class='bed-title'>" + bed + "</div>";^)
        ROW + 1 call print(^            html += "<a class='patient-link' href=\"javascript:APPLINK(0,'Powerchart.exe','/PERSONID=" + per + " /ENCNTRID=" + enc + "')\">" + name + "</a></td>";^)
        
        ROW + 1 call print(^            html += "<td style='width:50%; padding-left:15px; border-right:1px dashed #e2e8f0; vertical-align:top;'>";^)
        ROW + 1 call print(^            var meds = pat.MEDS || pat.meds || [];^)
        ROW + 1 call print(^            if (!Array.isArray(meds)) { meds = [meds]; }^)
        ROW + 1 call print(^            for(var m=0; m<meds.length; m++) {^)
        ROW + 1 call print(^                var med = meds[m];^)
        ROW + 1 call print(^                var mnom = med.MNEMONIC || med.mnemonic || "";^)
        ROW + 1 call print(^                var mcdl = med.RAW_CDL || med.raw_cdl || "";^)
        ROW + 1 call print(^                var dStat = med.DOSE_STATUS || med.dose_status || "";^)
        ROW + 1 call print(^                var dCol = med.DOSE_COLOR || med.dose_color || "gray";^)
        ROW + 1 call print(^                html += "<div class='med-row med-row-active'><div class='med-name'>" + escapeHTML(mnom) + "</div>";^)
        
        ; ADVICE BADGE MOVED TO PROMINENT NEW LINE
        ROW + 1 call print(^                if (dCol === "green") { html += "<div style='margin-bottom:8px;'><span class='badge-green'>&#10003; " + escapeHTML(dStat) + "</span></div>"; }^)
        ROW + 1 call print(^                else if (dCol === "red") { html += "<div style='margin-bottom:8px;'><span class='badge-red'>&#9888; " + escapeHTML(dStat) + "</span></div>"; }^)
        ROW + 1 call print(^                else if (dCol === "orange") { html += "<div style='margin-bottom:8px;'><span class='badge-amber'>&#9888; " + escapeHTML(dStat) + "</span></div>"; }^)
        ROW + 1 call print(^                else { html += "<div style='margin-bottom:8px;'><span class='badge-gray'>" + escapeHTML(dStat) + "</span></div>"; }^)
        
        ROW + 1 call print(^                html += "<div class='med-ind'>" + escapeHTML(mcdl) + "</div></div>";^)
        ROW + 1 call print(^            }^)
        ROW + 1 call print(^            html += "</td>";^)

        ROW + 1 call print(^            html += "<td style='width:25%; padding-left:15px; vertical-align:top;'>";^)
        ROW + 1 call print(^            if (wgt === "Not Recorded") {^)
        ROW + 1 call print(^                html += "<div style='color:#c53030; font-weight:bold; font-size:14px;'>&#9888; NO DOSING WEIGHT</div>";^)
        ROW + 1 call print(^                html += "<div style='font-size:11px; color:#e53e3e; margin-top:4px;'>Unable to verify dosing.</div>";^)
        ROW + 1 call print(^            } else {^)
        ROW + 1 call print(^                html += "<div style='color:#2b6cb0; font-weight:bold; font-size:16px;'>" + wgt + "</div>";^)
        ROW + 1 call print(^                html += "<div style='font-size:11px; color:#718096; margin-top:4px;'>Recorded: " + wgt_dt + "</div>";^)
        ROW + 1 call print(^            }^)
        ROW + 1 call print(^            html += "</td></tr>";^)
        ROW + 1 call print(^        }^)
        
        ROW + 1 call print(^        if (renderedCount === 0 && list.length > 0) {^)
        ROW + 1 call print(^            html = "<tr><td colspan='3' align='center' style='padding:50px; color:#718096; font-size:14px;'>&#10003; No patients on this ward are currently prescribed VTE prophylaxis.</td></tr>";^)
        ROW + 1 call print(^        }^)
        
        ROW + 1 call print(^        document.getElementById('triageBody').innerHTML = html;^)
        ROW + 1 call print(^    } catch (e) { document.getElementById('triageBody').innerHTML = "<tr><td colspan='3'>JSON Parse Error: " + e.message + "</td></tr>"; }^)
        ROW + 1 call print(^}^)
        ROW + 1 call print(^</script>^)

        ROW + 1 call print(^<style>^)
        ROW + 1 call print(^  body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; background: #f4f7f6; padding: 20px; color: #2d3748; margin: 0; font-size: 13px; line-height: 1.4; }^)
        ROW + 1 call print(^  .dashboard-container { box-shadow: 0 4px 16px rgba(0,0,0,0.06); border-radius: 8px; background: #fff; overflow: hidden; border: 1px solid #e2e8f0; }^)
        ROW + 1 call print(^  .dashboard-header { background: linear-gradient(135deg, #2b6cb0 0%, #2c5282 100%); color: #fff; padding: 18px 24px; font-size: 18px; font-weight: 600; letter-spacing: 0.3px; }^)
        ROW + 1 call print(^  .dashboard-content { padding: 24px; min-height: 400px; }^)
        ROW + 1 call print(^  .warning-box { background:#ffffff; border:1px solid #90cdf4; border-left: 4px solid #3182ce; border-radius:8px; padding:20px; max-width:500px; margin:0 auto; color:#2b6cb0; text-align:left; }^)
        ROW + 1 call print(^  select { padding: 8px 12px; font-size: 13px; border: 1px solid #cbd5e0; width: 320px; border-radius: 4px; outline: none; color: #4a5568; }^)
        ROW + 1 call print(^  select:focus { border-color: #3182ce; box-shadow: 0 0 0 2px rgba(49, 130, 206, 0.2); }^)
        ROW + 1 call print(^  button { padding: 8px 18px; background: #3182ce; color: white; border: none; cursor: pointer; font-size: 13px; margin-left: 12px; font-weight: 600; border-radius: 4px; transition: background 0.2s; }^)
        ROW + 1 call print(^  button:hover { background: #2b6cb0; }^)
        ROW + 1 call print(^  .ward-tbl { width: 100%; margin-top: 20px; border-collapse: collapse; font-size: 12px; background: #fff; }^)
        ROW + 1 call print(^  .ward-tbl th { background: #f7fafc; font-weight: 600; color: #4a5568; text-align: left; text-transform: uppercase; font-size: 11px; letter-spacing: 0.5px; padding: 12px 14px; border-bottom: 2px solid #e2e8f0; }^)
        ROW + 1 call print(^  .ward-tbl td { padding: 16px 14px; border-bottom: 1px solid #edf2f7; vertical-align: top; }^)
        ROW + 1 call print(^  .ward-tbl tr:hover { background-color: #fcfcfc; }^)
        
        ROW + 1 call print(^  .row-action { border-left: 5px solid #e53e3e; background-color: #fff5f5; }^)
        ROW + 1 call print(^  .row-red { border-left: 5px solid #e53e3e; background-color: #fff5f5; }^)
        ROW + 1 call print(^  .row-orange { border-left: 5px solid #dd6b20; background-color: #fffaf0; }^)
        ROW + 1 call print(^  .row-green { border-left: 5px solid #48bb78; background-color: #f0fff4; }^)
        ROW + 1 call print(^  .row-normal { border-left: 5px solid transparent; }^)
        
        ROW + 1 call print(^  .bed-title { font-size: 11px; color: #718096; font-weight: 600; margin-bottom: 4px; text-transform: uppercase; letter-spacing: 0.3px; }^)
        ROW + 1 call print(^  .patient-link { color: #2b6cb0; text-decoration: none; font-size: 14px; font-weight: 600; }^)
        ROW + 1 call print(^  .patient-link:hover { text-decoration: underline; color: #2c5282; }^)
        
        ROW + 1 call print(^  .med-row { padding: 12px 14px; border-radius: 6px; margin-bottom: 8px; display: inline-block; width: 100%; box-sizing: border-box; }^)
        ROW + 1 call print(^  .med-row:last-child { margin-bottom: 0; }^)
        ROW + 1 call print(^  .med-row-active { background-color: #ffffff; border: 1px solid #e2e8f0; box-shadow: 0 1px 2px rgba(0,0,0,0.05); }^)
        ROW + 1 call print(^  .med-name { font-weight: 600; color: #2b6cb0; font-size: 14px; display:block; margin-bottom:6px; }^)
        ROW + 1 call print(^  .med-ind { font-size: 11px; color: #718096; line-height: 1.4; }^)
        
        ROW + 1 call print(^  .badge-green { display: inline-block; background: #c6f6d5; color: #22543d; padding: 4px 8px; border-radius: 4px; font-weight:bold; font-size:11px; border: 1px solid #9ae6b4; }^)
        ROW + 1 call print(^  .badge-red { display: inline-block; background: #fed7d7; color: #822727; padding: 4px 8px; border-radius: 4px; font-weight:bold; font-size:11px; border: 1px solid #feb2b2; }^)
        ROW + 1 call print(^  .badge-amber { display: inline-block; background: #feebc8; color: #744210; padding: 4px 8px; border-radius: 4px; font-weight:bold; font-size:11px; border: 1px solid #fbd38d; }^)
        ROW + 1 call print(^  .badge-gray { display: inline-block; background: #edf2f7; color: #4a5568; padding: 4px 8px; border-radius: 4px; font-weight:bold; font-size:11px; border: 1px solid #cbd5e0; }^)
        ROW + 1 call print(^</style>^)
        ROW + 1 call print(^</head><body>^)
        
        ROW + 1 call print(^<div class="dashboard-container">^)
        ROW + 1 call print(^<div class="dashboard-header">VTE Dosing Review</div>^)
        ROW + 1 call print(^<div class="dashboard-content">^)
        
        IF (rec_data->list_cnt > 0)
            ROW + 1 call print(^<select id="listSelector">^)
            ROW + 1 call print(^<option value="0">-- Select a Patient List --</option>^)
            FOR (i = 1 TO rec_data->list_cnt)
                ROW + 1 call print(CONCAT(^<option value="^, TRIM(CNVTSTRING(rec_data->lists[i].list_id)), ^">^, rec_data->lists[i].list_name, ^</option>^))
            ENDFOR
            ROW + 1 call print(^</select>^)
            ROW + 1 call print(^<button onclick="loadPatients()">Review VTE Dosing</button>^)
        ENDIF

        ROW + 1 call print(^<table class='ward-tbl'>^)
        ROW + 1 call print(^<thead><tr><th width="25%">Patient & Location</th><th width="50%">Active VTE Prophylaxis</th><th width="25%">Dosing Weight</th></tr></thead>^)
        ROW + 1 call print(^<tbody id='triageBody'>^)
        ROW + 1 call print(^<tr><td colspan='3' style='text-align:center; padding: 60px 20px; color:#a0aec0; font-size:14px;'>Select a patient list above to review VTE orders.</td></tr>^)
        ROW + 1 call print(^</tbody></table>^)
        ROW + 1 call print(^</div></div>^)
        ROW + 1 call print(^</body></html>^)
    WITH NOCOUNTER, MAXCOL=65534, FORMAT=VARIABLE, NOHEADING

ENDIF
END
GO
