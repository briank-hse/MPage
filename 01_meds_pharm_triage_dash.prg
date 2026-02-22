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
    DECLARE v_summary_rows = vc WITH noconstant(""), maxlen=65534
    DECLARE v_matrix_rows = vc WITH noconstant(""), maxlen=65534
    DECLARE pat_idx = i4 WITH noconstant(0)
    DECLARE idx = i4 WITH noconstant(0)
    DECLARE t_score = i4 WITH noconstant(0)
    DECLARE t_triggers = vc WITH noconstant(""), maxlen=2000
    DECLARE num_pats = i4 WITH noconstant(0)
    DECLARE stat = i4 WITH noconstant(0)
    DECLARE err_code = i4 WITH noconstant(0)
    DECLARE err_msg = c132 WITH noconstant("")
    DECLARE summary_idx = i4 WITH noconstant(0)

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
            2 flag_high_alert_iv = i2
    )

    RECORD rec_ward_summary (
        1 cnt = i4
        1 list[*]
            2 ward_name = vc
            2 pat_count = i4
    )

    ; 1a. Execute Patient List Rules via API
    DECLARE curr_list_id = f8 WITH noconstant(0.0)
    SET curr_list_id = curr_ward_cd

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
    ; Check if the Cerner API crashed due to list size/memory
    SET err_code = ERROR(err_msg, 1)
    IF (err_code != 0)
        SELECT INTO $OUTDEV
        FROM DUMMYT D
        DETAIL call print(CONCAT("<tr><td colspan='4' style='color:red; padding:20px;'><b>API Execution Failed (List too large or invalid):</b> ", TRIM(err_msg), "</td></tr>"))
        WITH NOCOUNTER
        GO TO exit_script
    ENDIF

    ; 1b. Populate Cohort from API Results
    DECLARE api_pats = i4 WITH noconstant(0)
    SET api_pats = SIZE(600123_reply->patients, 5)
    IF (api_pats > 0)
        ; Hard cap to prevent Oracle DUMMYT query timeouts
        IF (api_pats > 800) SET api_pats = 800 ENDIF

        SELECT INTO "NL:"
        FROM (DUMMYT D WITH SEQ = VALUE(api_pats)), ENCOUNTER E, PERSON P
        PLAN D
        JOIN E WHERE E.ENCNTR_ID = 600123_reply->patients[D.SEQ].encntr_id
            AND E.ACTIVE_IND = 1
            AND E.ENCNTR_STATUS_CD = 854.00       ; Must be an Active encounter
            AND E.LOC_NURSE_UNIT_CD > 0.0         ; Must be assigned to a valid nurse unit
            AND E.ENCNTR_TYPE_CLASS_CD = 391.00   ; Must be an Inpatient
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
            rec_cohort->list[rec_cohort->cnt].ward_name = TRIM(UAR_GET_CODE_DISPLAY(E.LOC_NURSE_UNIT_CD))
            IF (TEXTLEN(rec_cohort->list[rec_cohort->cnt].ward_name) = 0)
                rec_cohort->list[rec_cohort->cnt].ward_name = "Unknown Ward"
            ENDIF
            rec_cohort->list[rec_cohort->cnt].room_bed = CONCAT(TRIM(UAR_GET_CODE_DISPLAY(E.LOC_ROOM_CD)), "-", TRIM(UAR_GET_CODE_DISPLAY(E.LOC_BED_CD)))
        WITH NOCOUNTER
    ENDIF

    SET num_pats = rec_cohort->cnt
    ; Prevent Oracle IN-clause crashes and severe server lag
    DECLARE over_limit_flag = i2 WITH noconstant(0)
    IF (num_pats > 300)
        SET num_pats = 300
        SET over_limit_flag = 1
    ENDIF

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

                ; Check for High-Alert Continuous Infusions via native IV_IND flag
                IF (FINDSTRING("MAGNESIUM", UNOM) > 0 OR FINDSTRING("OXYTOCIN", UNOM) > 0 OR FINDSTRING("INSULIN", UNOM) > 0 OR FINDSTRING("LABETALOL", UNOM) > 0 OR FINDSTRING("HYDRALAZINE", UNOM) > 0)
                    IF (O.IV_IND = 1)
                        rec_cohort->list[idx].flag_high_alert_iv = 1
                    ENDIF
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

            IF (rec_cohort->list[pat_idx].flag_high_alert_iv = 1) SET t_score = t_score + 5 SET t_triggers = CONCAT(t_triggers, "<span class='trig-pill' style='background:#f8d7da; border-color:#f5c6cb; color:#721c24; font-weight:bold;' title='Active continuous IV infusion of high-alert medication'>High-Alert IV</span>") ENDIF
            IF (rec_cohort->list[pat_idx].flag_transfusion = 1 OR rec_cohort->list[pat_idx].flag_ebl = 1) SET t_score = t_score + 3 SET t_triggers = CONCAT(t_triggers, "<span class='trig-pill' title='Blood Volume Infused or EBL > 1000ml in last 7 days'>Haemorrhage/Transfusion</span>") ENDIF
            IF (rec_cohort->list[pat_idx].flag_preeclampsia = 1) SET t_score = t_score + 3 SET t_triggers = CONCAT(t_triggers, "<span class='trig-pill' title='Active problem or diagnosis of Pre-Eclampsia'>Pre-Eclampsia</span>") ENDIF
            IF (rec_cohort->list[pat_idx].flag_dvt = 1) SET t_score = t_score + 3 SET t_triggers = CONCAT(t_triggers, "<span class='trig-pill' title='Active problem or diagnosis of DVT or Pulmonary Embolism'>VTE/DVT</span>") ENDIF
            IF (rec_cohort->list[pat_idx].flag_epilepsy = 1) SET t_score = t_score + 3 SET t_triggers = CONCAT(t_triggers, "<span class='trig-pill' title='Active problem or diagnosis of Epilepsy or Seizure'>Epilepsy</span>") ENDIF
            IF (rec_cohort->list[pat_idx].flag_insulin = 1) SET t_score = t_score + 3 SET t_triggers = CONCAT(t_triggers, "<span class='trig-pill' title='Active inpatient order for Insulin'>Insulin</span>") ENDIF
            IF (rec_cohort->list[pat_idx].flag_antiepileptic = 1) SET t_score = t_score + 3 SET t_triggers = CONCAT(t_triggers, "<span class='trig-pill' title='Active inpatient order for Levetiracetam, Lamotrigine, Valproate, or Carbamazepine'>Antiepileptic</span>") ENDIF
            IF (rec_cohort->list[pat_idx].flag_poly_severe = 1) SET t_score = t_score + 3 SET t_triggers = CONCAT(t_triggers, "<span class='trig-pill' title='10 or more active inpatient medications'>Severe Polypharmacy</span>") ENDIF
            IF (rec_cohort->list[pat_idx].flag_anticoag = 1) SET t_score = t_score + 2 SET t_triggers = CONCAT(t_triggers, "<span class='trig-pill' title='Active inpatient order for Tinzaparin, Heparin, or Enoxaparin'>Anticoagulant</span>") ENDIF
            IF (rec_cohort->list[pat_idx].flag_antihypertensive = 1) SET t_score = t_score + 2 SET t_triggers = CONCAT(t_triggers, "<span class='trig-pill' title='Active inpatient order for Labetalol, Nifedipine, or Methyldopa'>Antihypertensive</span>") ENDIF
            IF (rec_cohort->list[pat_idx].flag_neuraxial = 1) SET t_score = t_score + 1 SET t_triggers = CONCAT(t_triggers, "<span class='trig-pill' title='Active inpatient order for Bupivacaine or Levobupivacaine'>Neuraxial Infusion</span>") ENDIF
            IF (rec_cohort->list[pat_idx].flag_poly_mod = 1) SET t_score = t_score + 1 SET t_triggers = CONCAT(t_triggers, "<span class='trig-pill' title='5 to 9 active inpatient medications'>Mod Polypharmacy</span>") ENDIF

            SET rec_cohort->list[pat_idx].score = t_score
            IF (t_score >= 3) SET rec_cohort->list[pat_idx].color = "Red"
            ELSEIF (t_score >= 1) SET rec_cohort->list[pat_idx].color = "Amber"
            ELSE SET rec_cohort->list[pat_idx].color = "Green" ENDIF

            IF (TEXTLEN(t_triggers) > 0) 
                 SET rec_cohort->list[pat_idx].summary = t_triggers
            ELSE 
                 SET rec_cohort->list[pat_idx].summary = "Routine (Low Risk)" 
            ENDIF
        ENDFOR

        ; 6b. Aggregate patient counts by ward for evaluated cohort
        FOR (pat_idx = 1 TO num_pats)
            IF (rec_ward_summary->cnt > 0)
                SET summary_idx = LOCATEVAL(idx, 1, rec_ward_summary->cnt, rec_cohort->list[pat_idx].ward_name, rec_ward_summary->list[idx].ward_name)
            ELSE
                SET summary_idx = 0
            ENDIF
            IF (summary_idx > 0)
                SET rec_ward_summary->list[summary_idx].pat_count = rec_ward_summary->list[summary_idx].pat_count + 1
            ELSE
                SET rec_ward_summary->cnt = rec_ward_summary->cnt + 1
                SET stat = ALTERLIST(rec_ward_summary->list, rec_ward_summary->cnt)
                SET rec_ward_summary->list[rec_ward_summary->cnt].ward_name = rec_cohort->list[pat_idx].ward_name
                SET rec_ward_summary->list[rec_ward_summary->cnt].pat_count = 1
            ENDIF
        ENDFOR

    ELSE
        SET v_ward_rows = "<tr><td colspan='4' style='text-align:center; padding: 20px;'>No active patients found on this list.</td></tr>"
    ENDIF

    ; 7a. Build scoring reference matrix row HTML
    SET v_matrix_rows = ""
    SET v_matrix_rows = CONCAT(v_matrix_rows, "<tr style='background:#fff;'><td colspan='4' style='padding:15px 10px 5px 10px;'>")
    SET v_matrix_rows = CONCAT(v_matrix_rows, "<details class='ref-details'>")
    SET v_matrix_rows = CONCAT(v_matrix_rows, "<summary>View Scoring Reference Matrix</summary>")
    SET v_matrix_rows = CONCAT(v_matrix_rows, "<table class='ref-table'>")
    SET v_matrix_rows = CONCAT(v_matrix_rows, "<thead><tr><th width='60%'>Clinical Criteria</th><th width='20%'>Category</th><th width='20%'>Points</th></tr></thead><tbody>")
    SET v_matrix_rows = CONCAT(v_matrix_rows, "<tr class='tr-red'><td>Continuous IV infusion of high-alert medication (e.g., MgSO4, Oxytocin)</td><td>Medication</td><td>+5</td></tr>")
    SET v_matrix_rows = CONCAT(v_matrix_rows, "<tr class='tr-red'><td>Massive Haemorrhage / Blood Transfusion</td><td>Clinical Event</td><td>+3</td></tr>")
    SET v_matrix_rows = CONCAT(v_matrix_rows, "<tr class='tr-red'><td>High Risk Diagnosis (Pre-eclampsia, VTE, Epilepsy)</td><td>Problem/Diagnosis</td><td>+3</td></tr>")
    SET v_matrix_rows = CONCAT(v_matrix_rows, "<tr class='tr-red'><td>High Alert Med (Insulin, Antiepileptics)</td><td>Medication</td><td>+3</td></tr>")
    SET v_matrix_rows = CONCAT(v_matrix_rows, "<tr class='tr-red'><td>Severe Polypharmacy (&ge;10 active meds)</td><td>Medication</td><td>+3</td></tr>")
    SET v_matrix_rows = CONCAT(v_matrix_rows, "<tr class='tr-amber'><td>Targeted Med (Anticoagulant, Antihypertensive)</td><td>Medication</td><td>+2</td></tr>")
    SET v_matrix_rows = CONCAT(v_matrix_rows, "<tr><td>Moderate Polypharmacy (5-9 active meds)</td><td>Medication</td><td>+1</td></tr>")
    SET v_matrix_rows = CONCAT(v_matrix_rows, "<tr><td>Neuraxial / Epidural Infusion Active</td><td>Medication</td><td>+1</td></tr>")
    SET v_matrix_rows = CONCAT(v_matrix_rows, "</tbody></table>")
    SET v_matrix_rows = CONCAT(v_matrix_rows, "</details>")
    SET v_matrix_rows = CONCAT(v_matrix_rows, "</td></tr>")

    ; 7a. Build summary HTML rows in-memory (sorted by ward name)
    IF (rec_ward_summary->cnt > 0)
        SET v_summary_rows = ""
        SELECT INTO "NL:"
            SORT_WARD = CNVTUPPER(rec_ward_summary->list[D.SEQ].ward_name)
        FROM (DUMMYT D WITH SEQ = VALUE(rec_ward_summary->cnt))
        PLAN D
        ORDER BY SORT_WARD, D.SEQ
        HEAD REPORT
            v_summary_rows = CONCAT(v_summary_rows, "<tr style='background:#f0f4f8;'><td colspan='4' style='padding:10px; font-weight:bold; border-top:2px solid #005A84;'>Patient Distribution by Ward (Evaluated Cohort)</td></tr>")
        DETAIL
            v_summary_rows = CONCAT(v_summary_rows,
                "<tr>",
                "<td colspan='2' style='font-weight:bold; border-right:1px solid #e0e0e0;'>", rec_ward_summary->list[D.SEQ].ward_name, "</td>",
                "<td colspan='2'>Total Patients: ", TRIM(CNVTSTRING(rec_ward_summary->list[D.SEQ].pat_count)), "</td>",
                "</tr>"
            )
        WITH NOCOUNTER
    ENDIF

    ; 7b. Build HTML Rows (Ordered by Score Descending)
    SELECT INTO $OUTDEV
        PAT_SCORE = rec_cohort->list[D.SEQ].score
    FROM (DUMMYT D WITH SEQ = VALUE(num_pats))
    PLAN D
    ORDER BY PAT_SCORE DESC, D.SEQ
    HEAD REPORT
        call print("") ; clear buffer
        IF (num_pats = 0)
            call print(v_ward_rows)
        ENDIF
        IF (over_limit_flag = 1)
            call print("<tr><td colspan='4' style='background:#fff3cd; color:#856404; text-align:center; padding:10px;'><b>Warning:</b> List is too large. Only the first 300 patients have been evaluated.</td></tr>")
        ENDIF
    DETAIL
      call print(CONCAT(
          "<tr>",
          "<td><b>", rec_cohort->list[D.SEQ].room_bed, "</b></td>",
          "<td><a class='patient-link' href='javascript:APPLINK(0,^Powerchart.exe^,^/PERSONID=",
          TRIM(CNVTSTRING(rec_cohort->list[D.SEQ].person_id)),
          " /ENCNTRID=", TRIM(CNVTSTRING(rec_cohort->list[D.SEQ].encntr_id)),
          " /FIRSTTAB=", CHAR(34), "Pharmacist MPage - New", CHAR(34), "^)'>",
          rec_cohort->list[D.SEQ].name, "</a></td>",
          "<td><span class='badge-", rec_cohort->list[D.SEQ].color, "'>Score: ", TRIM(CNVTSTRING(rec_cohort->list[D.SEQ].score)), "</span></td>",
          "<td>", rec_cohort->list[D.SEQ].summary, "</td>",
          "</tr>"
      ))
    FOOT REPORT
        IF (TEXTLEN(v_matrix_rows) > 0)
            call print(v_matrix_rows)
        ENDIF
        IF (TEXTLEN(v_summary_rows) > 0)
            call print(v_summary_rows)
        ENDIF
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
        ROW + 1 call print(^            } else if (xhr.status == 492) {^)
        ROW + 1 call print(^                document.getElementById('triageBody').innerHTML = "<tr><td colspan='4' style='color:#856404; background-color:#fff3cd; padding:20px; border:1px solid #ffeeba; text-align:center;'><b>List Too Large:</b> The selected patient list contains too many records to load efficiently. Please select a smaller, more specific list to view acuity scores.</td></tr>";^)
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
        ROW + 1 call print(^  body { font-family: Tahoma, Arial, sans-serif; background: #ffffff; padding: 10px; color: #333; margin: 0; font-size: 12px; }^)
        ROW + 1 call print(^  .dashboard-header { background: #005A84; color: #fff; padding: 6px 12px; font-size: 14px; font-weight: bold; border: 1px solid #005A84; }^)
        ROW + 1 call print(^  .dashboard-content { background: #fff; padding: 15px; border: 1px solid #ccc; border-top: none; min-height: 400px; }^)
        ROW + 1 call print(^  .info-box { background: #f9f9f9; border: 1px solid #ddd; padding: 8px 12px; margin-bottom: 15px; font-size: 12px; }^)
        ROW + 1 call print(^  h3 { font-size: 13px; margin: 0 0 8px 0; font-weight: bold; color: #005A84; }^)
        ROW + 1 call print(^  select { padding: 4px; font-size: 12px; border: 1px solid #7a9ea9; width: 300px; font-family: Tahoma, Arial, sans-serif; }^)
        ROW + 1 call print(^  button { padding: 4px 12px; background: #e0e0e0; color: #333; border: 1px solid #7a9ea9; cursor: pointer; font-size: 12px; margin-left: 10px; font-family: Tahoma, Arial, sans-serif; }^)
        ROW + 1 call print(^  button:hover { background: #d0d0d0; border-color: #005A84; }^)
        ROW + 1 call print(^  .ward-tbl { width: 100%; margin-top: 15px; border-collapse: collapse; font-size: 12px; background: #fff; border: 1px solid #ccc; }^)
        ROW + 1 call print(^  .ward-tbl th, .ward-tbl td { padding: 6px 8px; border-bottom: 1px solid #e0e0e0; border-right: 1px solid #e0e0e0; text-align: left; }^)
        ROW + 1 call print(^  .ward-tbl th { background: #f0f0f0; font-weight: bold; color: #333; border-bottom: 2px solid #ccc; }^)
        ROW + 1 call print(^  .ward-tbl tr:hover { background: #e8f4f8; }^)
        ROW + 1 call print(^  .badge-Red { background: #cc0000; color: white; padding: 2px 6px; border-radius: 2px; font-weight:bold; font-size:11px; display:inline-block; min-width:50px; text-align:center; }^)
        ROW + 1 call print(^  .badge-Amber { background: #ff9900; color: white; padding: 2px 6px; border-radius: 2px; font-weight:bold; font-size:11px; display:inline-block; min-width:50px; text-align:center; }^)
        ROW + 1 call print(^  .badge-Green { background: #008000; color: white; padding: 2px 6px; border-radius: 2px; font-weight:bold; font-size:11px; display:inline-block; min-width:50px; text-align:center; }^)
        ROW + 1 call print(^  .patient-link { color: #005A84; text-decoration: none; }^)
        ROW + 1 call print(^  .patient-link:hover { text-decoration: underline; color: #003a54; }^)
        ROW + 1 call print(^  .trig-pill { display: inline-block; background: #e9ecef; border: 1px solid #ced4da; border-radius: 10px; padding: 2px 8px; margin: 2px 2px 2px 0; font-size: 11px; color: #495057; cursor: help; }^)
        ROW + 1 call print(^  .ref-details { margin: 10px 0; background: #fff; border: 1px solid #ddd; padding: 10px; border-radius: 4px; box-shadow: 0 1px 2px rgba(0,0,0,0.05); }^)
        ROW + 1 call print(^  .ref-details summary { font-weight: bold; color: #005A84; cursor: pointer; font-size: 13px; outline: none; }^)
        ROW + 1 call print(^  .ref-table { width: 100%; border-collapse: collapse; font-size: 11px; margin-top: 10px; }^)
        ROW + 1 call print(^  .ref-table th, .ref-table td { border: 1px solid #ddd; padding: 6px 8px; text-align: left; }^)
        ROW + 1 call print(^  .ref-table th { background-color: #f0f4f8; color: #333; }^)
        ROW + 1 call print(^  .tr-red { background-color: #f8d7da; border-left: 4px solid #dc3545; }^)
        ROW + 1 call print(^  .tr-amber { background-color: #fff3cd; border-left: 4px solid #ffc107; }^)
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

#exit_script
END
GO
