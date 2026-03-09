DROP PROGRAM 01_ams_stewardship_dash_GH:group1 GO
CREATE PROGRAM 01_ams_stewardship_dash_GH:group1

PROMPT
    "Output to File/Printer/MINE" = "MINE",
    "Personnel ID" = 0.0,
    "Ward Code" = 0.0
WITH OUTDEV, PRSNL_ID, WARD_CD

IF (CNVTREAL($WARD_CD) > 0.0)

    ; =========================================================================
    ; DATA FETCH MODE - SPA BACKEND WITH SAFEGUARD THRESHOLDS
    ; =========================================================================
    DECLARE curr_ward_cd = f8 WITH noconstant(CNVTREAL($WARD_CD))
    SET MODIFY MAXVARLEN 32000000

    DECLARE i            = i4 WITH noconstant(0)
    DECLARE m            = i4 WITH noconstant(0)
    DECLARE v_i          = i4 WITH noconstant(0)
    DECLARE stat         = i4 WITH noconstant(0)
    DECLARE num_pats     = i4 WITH noconstant(0)
    DECLARE idx          = i4 WITH noconstant(0)
    DECLARE m_idx        = i4 WITH noconstant(0)
    DECLARE m_loc        = i4 WITH noconstant(0)
    DECLARE sort_i       = i4 WITH noconstant(0)
    DECLARE sort_j       = i4 WITH noconstant(0)
    
    DECLARE t_start      = i4 WITH noconstant(0)
    DECLARE t_end        = i4 WITH noconstant(0)
    DECLARE t_len        = i4 WITH noconstant(0)
    DECLARE t_idx        = i4 WITH noconstant(0)
    
    DECLARE UNOM         = vc WITH noconstant("")
    DECLARE VAL          = vc WITH noconstant("")
    DECLARE temp_cdl     = vc WITH noconstant("")
    DECLARE v_route      = vc WITH noconstant("")
    
    DECLARE t_score      = i4 WITH noconstant(0)
    DECLARE t_triggers   = vc WITH noconstant("")
    DECLARE is_abx       = i2 WITH noconstant(0)
    DECLARE is_ghost     = i2 WITH noconstant(0)
    DECLARE pat_has_active_abx = i2 WITH noconstant(0)
    
    DECLARE pat_cursor   = i4 WITH noconstant(1)
    DECLARE batch_len    = i4 WITH noconstant(0)

    ; Fast code-value lookup for Medication Administrations
    DECLARE mae_task_cd   = f8 WITH noconstant(UAR_GET_CODE_BY("MEANING", 4000040, "TASKCOMPLETE"))
    DECLARE t_first_dt    = dq8 WITH noconstant(0.0)
    DECLARE t_last_dt     = dq8 WITH noconstant(0.0)
    DECLARE t_dot_count   = i4 WITH noconstant(0)
    DECLARE t_prev_date   = vc WITH noconstant("")
    DECLARE curr_date_str = vc WITH noconstant("")

    ; Hard Limit to protect database
    DECLARE PATIENT_LIMIT = i4 WITH noconstant(150)

    ; Core Patient Record (Converted to JSON automatically)
    RECORD rec_cohort (
        1 status_msg = vc       ; <--- NEW: Tells JS if we hit a limit
        1 cnt = i4
        1 list[*]
            2 person_id = f8
            2 encntr_id = f8
            2 name      = vc
            2 room_bed  = vc
            
            ; --- ACUITY VARIABLES ---
            2 score              = i4
            2 color              = vc
            2 summary            = vc
            2 poly_count         = i4
            2 med_tracker        = vc
            2 flag_imews         = i2
            2 det_imews          = vc
            2 flag_high_alert_iv = i2
            2 flag_anticoag      = i2
            
            ; --- ANTIMICROBIAL VARIABLES ---
            2 med_cnt            = i4
            2 action_req         = i2
            2 restricted_cnt     = i4
            2 ivost_cnt          = i4
            2 action_summary     = vc
            2 patient_priority   = i4
            2 meds[*]
                3 order_id       = f8
                3 mnemonic       = vc
                3 indication     = vc
                3 raw_cdl        = vc   
                3 is_iv_flag     = i2   
                3 is_restricted  = i2
                3 dot            = i4   
                3 first_admin_dt = dq8  
                3 last_admin_dt  = dq8  
                3 last_admin_str = vc   
                3 priority_rank  = i4
                3 current_route  = vc
    )

    RECORD temp_med (
        1 list[1]
            2 order_id       = f8
            2 mnemonic       = vc
            2 indication     = vc
            2 raw_cdl        = vc
            2 is_iv_flag     = i2
            2 is_restricted  = i2
            2 dot            = i4
            2 first_admin_dt = dq8
            2 last_admin_dt  = dq8
            2 last_admin_str = vc
            2 priority_rank  = i4
            2 current_route  = vc
    )

    ; Array to protect database from timeouts
    RECORD batch_req ( 1 cnt = i4 1 list[50] 2 p_idx = i4 2 person_id = f8 2 encntr_id = f8 )

    ; TINY ARRAY FOR SURGICAL STRIKE ON ADMINISTRATIONS
    RECORD target_ords ( 1 cnt = i4 1 list[*] 2 order_id = f8 2 pat_idx = i4 2 med_idx = i4 )

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
        WITH NOCOUNTER
    ENDIF

    SET num_pats = rec_cohort->cnt
    SET rec_cohort->status_msg = "OK"

    ; =========================================================================
    ; THE PRE-EMPTIVE SHIELD: CHECK IF LIST IS TOO BIG
    ; =========================================================================
    IF (num_pats > PATIENT_LIMIT)
        ; Set the flag to send to the browser, and skip all database queries!
        SET rec_cohort->status_msg = CONCAT("LIMIT_EXCEEDED|", TRIM(CNVTSTRING(num_pats)))
    ELSEIF (num_pats > 0)
        ; =====================================================================
        ; SAFE TO PROCEED: THE MINI-BATCH LOOP 
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

            ; -----------------------------------------------------------------
            ; MINI-BATCH QUERY 1: ACTIVE ORDERS
            ; -----------------------------------------------------------------
            SELECT INTO "NL:"
            FROM (DUMMYT D WITH SEQ = VALUE(batch_req->cnt)), ORDERS O, ORDER_DETAIL OD
            PLAN D
            JOIN O WHERE O.PERSON_ID = batch_req->list[D.SEQ].person_id
                     AND O.ENCNTR_ID = batch_req->list[D.SEQ].encntr_id
                     AND O.CATALOG_TYPE_CD = 2516.00 
                     AND O.ORDER_STATUS_CD IN (2550.00, 2549.00) 
                     AND O.ACTIVE_IND = 1
                     AND O.ORIG_ORD_AS_FLAG = 0
            JOIN OD WHERE OD.ORDER_ID = OUTERJOIN(O.ORDER_ID)
                      AND OD.OE_FIELD_MEANING_ID = OUTERJOIN(15) 
                      AND OD.ACTION_SEQUENCE = OUTERJOIN(1)
            DETAIL
                idx = batch_req->list[D.SEQ].p_idx
                UNOM = CNVTUPPER(O.ORDER_MNEMONIC)
                is_ghost = 0
                is_abx = 0
                
                ; CPU-Level Ghost Filter to safely eliminate discontinued meds
                IF (O.PROJECTED_STOP_DT_TM > 0.0 AND O.PROJECTED_STOP_DT_TM < CNVTDATETIME(CURDATE, CURTIME3))
                    is_ghost = 1
                ENDIF
                
                IF (is_ghost = 0)
                    IF (FINDSTRING(UNOM, rec_cohort->list[idx].med_tracker) = 0)
                        rec_cohort->list[idx].poly_count = rec_cohort->list[idx].poly_count + 1
                        rec_cohort->list[idx].med_tracker = CONCAT(rec_cohort->list[idx].med_tracker, "|", UNOM)
                    ENDIF
                    
                    IF (FINDSTRING("MAGNESIUM", UNOM) > 0 OR FINDSTRING("NORADRENALINE", UNOM) > 0)
                        IF (O.IV_IND = 1) rec_cohort->list[idx].flag_high_alert_iv = 1 ENDIF
                    ENDIF
                    IF (FINDSTRING("HEPARIN", UNOM) > 0 OR FINDSTRING("ENOXAPARIN", UNOM) > 0)
                        rec_cohort->list[idx].flag_anticoag = 1
                    ENDIF

                    IF (FINDSTRING("PENEM", UNOM)>0 OR FINDSTRING("MYCIN", UNOM)>0 OR FINDSTRING("CEF", UNOM)>0) is_abx = 1 ENDIF
                    IF (FINDSTRING("CILLIN", UNOM)>0 OR FINDSTRING("ZOLE", UNOM)>0 OR FINDSTRING("LINEZOLID", UNOM)>0) is_abx = 1 ENDIF
                    IF (FINDSTRING("GENTAMICIN", UNOM)>0 OR FINDSTRING("CEPH", UNOM)>0 OR FINDSTRING("BACTAM", UNOM)>0) is_abx = 1 ENDIF
                    IF (FINDSTRING("FLOXACIN", UNOM)>0 OR FINDSTRING("CLAVULANATE", UNOM)>0 OR FINDSTRING("AMOXICLAV", UNOM)>0) is_abx = 1 ENDIF
                    IF (FINDSTRING("TRIMOXAZOLE", UNOM)>0 OR FINDSTRING("TRIMETHOPRIM", UNOM)>0 OR FINDSTRING("FURANTOIN", UNOM)>0) is_abx = 1 ENDIF
                    IF (FINDSTRING("CYCLINE", UNOM)>0 OR FINDSTRING("PLANIN", UNOM)>0 OR FINDSTRING("FUNGIN", UNOM)>0) is_abx = 1 ENDIF
                    IF (FINDSTRING("CYCLOVIR", UNOM)>0 OR FINDSTRING("RIFAMP", UNOM)>0 OR FINDSTRING("AMPHOTERICIN", UNOM)>0) is_abx = 1 ENDIF
                    
                    IF (FINDSTRING("OMEPRAZOLE", UNOM)>0 OR FINDSTRING("PANTOPRAZOLE", UNOM)>0 OR FINDSTRING("LANSOPRAZOLE", UNOM)>0) is_abx = 0 ENDIF
                    IF (FINDSTRING("ESOMEPRAZOLE", UNOM)>0 OR FINDSTRING("RABEPRAZOLE", UNOM)>0 OR FINDSTRING("ARIPIPRAZOLE", UNOM)>0) is_abx = 0 ENDIF
                    IF (FINDSTRING("CARBIMAZOLE", UNOM)>0) is_abx = 0 ENDIF
                ENDIF

                IF (is_abx = 1)
                    m_idx = 0
                    IF (rec_cohort->list[idx].med_cnt > 0)
                        m_idx = LOCATEVAL(m_loc, 1, rec_cohort->list[idx].med_cnt, O.ORDER_MNEMONIC, rec_cohort->list[idx].meds[m_loc].mnemonic)
                    ENDIF

                    IF (m_idx = 0)
                        rec_cohort->list[idx].med_cnt = rec_cohort->list[idx].med_cnt + 1
                        m_idx = rec_cohort->list[idx].med_cnt
                        stat = ALTERLIST(rec_cohort->list[idx].meds, m_idx)
                        
                        rec_cohort->list[idx].meds[m_idx].order_id = O.ORDER_ID
                        rec_cohort->list[idx].meds[m_idx].mnemonic = O.ORDER_MNEMONIC
                        rec_cohort->list[idx].meds[m_idx].raw_cdl = O.CLINICAL_DISPLAY_LINE
                        rec_cohort->list[idx].meds[m_idx].is_iv_flag = O.IV_IND
                        rec_cohort->list[idx].meds[m_idx].priority_rank = 0
                        rec_cohort->list[idx].meds[m_idx].first_admin_dt = 0.0
                        rec_cohort->list[idx].meds[m_idx].last_admin_dt = 0.0
                        rec_cohort->list[idx].meds[m_idx].dot = 0
                        
                        IF (OD.OE_FIELD_DISPLAY_VALUE > " ")
                            rec_cohort->list[idx].meds[m_idx].indication = OD.OE_FIELD_DISPLAY_VALUE
                        ELSE
                            rec_cohort->list[idx].meds[m_idx].indication = "None Documented"
                        ENDIF
                        
                        IF (   FINDSTRING("MEROPENEM", UNOM)>0 OR FINDSTRING("PIPERACILLIN", UNOM)>0 OR FINDSTRING("TAZOBACTAM", UNOM)>0 
                            OR FINDSTRING("LINEZOLID", UNOM)>0 OR FINDSTRING("VANCOMYCIN", UNOM)>0 OR FINDSTRING("TEICOPLANIN", UNOM)>0 
                            OR FINDSTRING("DAPTOMYCIN", UNOM)>0 OR FINDSTRING("COLISTIN", UNOM)>0 OR FINDSTRING("CEFOTAXIME", UNOM)>0 
                            OR FINDSTRING("AMPHOTERICIN", UNOM)>0)
                            rec_cohort->list[idx].meds[m_idx].is_restricted = 1
                        ENDIF

                        temp_cdl = CNVTUPPER(TRIM(O.CLINICAL_DISPLAY_LINE, 3))
                        v_route = "UNK"
                        IF (FINDSTRING("ROUTE: INTRAVENOUS", temp_cdl) > 0 OR FINDSTRING("ROUTE: IV", temp_cdl) > 0 OR O.IV_IND = 1) v_route = "IV"
                        ELSEIF (FINDSTRING("ROUTE: INTRAMUSCULAR", temp_cdl) > 0 OR FINDSTRING("ROUTE: IM", temp_cdl) > 0) v_route = "IM"
                        ELSEIF (FINDSTRING("ROUTE: SUBCUTANEOUS", temp_cdl) > 0 OR FINDSTRING("ROUTE: SC", temp_cdl) > 0) v_route = "SC"
                        ELSEIF (FINDSTRING("ROUTE: ORAL", temp_cdl) > 0 OR FINDSTRING("ROUTE: PO", temp_cdl) > 0 OR FINDSTRING("TABLET", temp_cdl) > 0) v_route = "PO"
                        ELSEIF (FINDSTRING("ROUTE: NG", temp_cdl) > 0 OR FINDSTRING("ROUTE: PEG", temp_cdl) > 0 OR FINDSTRING("ENTERAL", temp_cdl) > 0) v_route = "ENT"
                        ELSEIF (FINDSTRING(" IV ", temp_cdl) > 0 OR FINDSTRING(",IV", temp_cdl) > 0) v_route = "IV"
                        ELSEIF (FINDSTRING(" PO ", temp_cdl) > 0 OR FINDSTRING(",PO", temp_cdl) > 0) v_route = "PO"
                        ENDIF
                        
                        rec_cohort->list[idx].meds[m_idx].current_route = v_route
                        
                        ; --- BUILD TARGET LIST FOR INDEX STRIKE ---
                        target_ords->cnt = target_ords->cnt + 1
                        stat = ALTERLIST(target_ords->list, target_ords->cnt)
                        target_ords->list[target_ords->cnt].order_id = O.ORDER_ID
                        target_ords->list[target_ords->cnt].pat_idx = idx
                        target_ords->list[target_ords->cnt].med_idx = m_idx
                    ENDIF
                ENDIF
            WITH NOCOUNTER

            ; -----------------------------------------------------------------
            ; MINI-BATCH QUERY 2: VITALS (IMEWS)
            ; -----------------------------------------------------------------
            SELECT INTO "NL:"
            FROM (DUMMYT D WITH SEQ = VALUE(batch_req->cnt)), CLINICAL_EVENT CE
            PLAN D
            JOIN CE WHERE CE.PERSON_ID = batch_req->list[D.SEQ].person_id
                      AND CE.ENCNTR_ID = batch_req->list[D.SEQ].encntr_id
                      AND CE.EVENT_CD = 15068265.00 ; IMEWS Score
                      AND CE.VALID_UNTIL_DT_TM > CNVTDATETIME(CURDATE, CURTIME3)
                      AND CE.PERFORMED_DT_TM > CNVTLOOKBEHIND("24,H")
                      AND CE.RESULT_STATUS_CD IN (25, 34, 35)
            ORDER BY D.SEQ, CE.EVENT_CD, CE.PERFORMED_DT_TM DESC
            HEAD D.SEQ
                idx = batch_req->list[D.SEQ].p_idx
                VAL = TRIM(CE.RESULT_VAL, 3)
                IF (CNVTINT(VAL) >= 2) 
                    rec_cohort->list[idx].flag_imews = 1 
                    rec_cohort->list[idx].det_imews = VAL 
                ENDIF
            WITH NOCOUNTER

        ENDWHILE

        ; ---------------------------------------------------------------------
        ; PASS 3: SURGICAL STRIKE ON ADMINISTRATIONS
        ; ---------------------------------------------------------------------
        IF (target_ords->cnt > 0)
            FOR (v_i = 1 TO target_ords->cnt)
                SET t_first_dt = 0.0
                SET t_last_dt = 0.0
                SET t_dot_count = 0
                SET t_prev_date = ""
                
                SELECT INTO "NL:"
                FROM MED_ADMIN_EVENT MAE
                PLAN MAE WHERE MAE.TEMPLATE_ORDER_ID = target_ords->list[v_i].order_id
                           AND MAE.EVENT_TYPE_CD = mae_task_cd
                ORDER BY MAE.BEG_DT_TM
                DETAIL
                    IF (t_first_dt = 0.0) t_first_dt = MAE.BEG_DT_TM ENDIF
                    t_last_dt = MAE.BEG_DT_TM
                    
                    curr_date_str = FORMAT(MAE.BEG_DT_TM, "YYYYMMDD;;D")
                    IF (curr_date_str != t_prev_date)
                        t_dot_count = t_dot_count + 1
                        t_prev_date = curr_date_str
                    ENDIF
                WITH NOCOUNTER
                
                SET t_pat_idx = target_ords->list[v_i].pat_idx
                SET t_med_idx = target_ords->list[v_i].med_idx
                
                IF (rec_cohort->list[t_pat_idx].meds[t_med_idx].first_admin_dt = 0.0 OR (t_first_dt > 0.0 AND t_first_dt < rec_cohort->list[t_pat_idx].meds[t_med_idx].first_admin_dt))
                    SET rec_cohort->list[t_pat_idx].meds[t_med_idx].first_admin_dt = t_first_dt
                ENDIF
                
                IF (t_last_dt > rec_cohort->list[t_pat_idx].meds[t_med_idx].last_admin_dt)
                    SET rec_cohort->list[t_pat_idx].meds[t_med_idx].last_admin_dt = t_last_dt
                ENDIF
                
                SET rec_cohort->list[t_pat_idx].meds[t_med_idx].dot = rec_cohort->list[t_pat_idx].meds[t_med_idx].dot + t_dot_count
            ENDFOR
        ENDIF

        ; ---------------------------------------------------------------------
        ; SCORING & UI STRING GENERATION
        ; ---------------------------------------------------------------------
        FOR (i = 1 TO num_pats)
            SET t_score = 0
            SET t_triggers = ""
            SET pat_has_active_abx = 0
            
            IF (rec_cohort->list[i].poly_count >= 10) 
                SET t_score = t_score + 3 
                SET t_triggers = CONCAT(t_triggers, "<span class='trig-pill'>Polypharmacy (", TRIM(CNVTSTRING(rec_cohort->list[i].poly_count)), " orders)</span>") 
            ELSE
                SET t_triggers = CONCAT(t_triggers, "<span class='trig-pill'>", TRIM(CNVTSTRING(rec_cohort->list[i].poly_count)), " Active Meds</span>") 
            ENDIF

            IF (rec_cohort->list[i].flag_high_alert_iv = 1) SET t_score = t_score + 5 SET t_triggers = CONCAT(t_triggers, "<span class='trig-pill'>High-Alert IV</span>") ENDIF
            IF (rec_cohort->list[i].flag_imews = 1) SET t_score = t_score + 3 SET t_triggers = CONCAT(t_triggers, "<span class='trig-pill'>IMEWS Score: ", rec_cohort->list[i].det_imews, "</span>") ENDIF
            IF (rec_cohort->list[i].flag_anticoag = 1) SET t_score = t_score + 2 SET t_triggers = CONCAT(t_triggers, "<span class='trig-pill'>Anticoagulant</span>") ENDIF

            SET rec_cohort->list[i].score = t_score
            IF (t_score >= 3) SET rec_cohort->list[i].color = "Red" 
            ELSEIF (t_score >= 1) SET rec_cohort->list[i].color = "Amber" 
            ELSE SET rec_cohort->list[i].color = "Green" 
            ENDIF
            
            SET rec_cohort->list[i].summary = t_triggers

            FOR (m = 1 TO rec_cohort->list[i].med_cnt)
                SET pat_has_active_abx = 1
                SET rec_cohort->list[i].meds[m].priority_rank = 50
                
                IF (rec_cohort->list[i].meds[m].first_admin_dt > 0.0)
                    IF (rec_cohort->list[i].meds[m].dot < 1) 
                        SET rec_cohort->list[i].meds[m].dot = 1 
                    ENDIF
                    SET rec_cohort->list[i].meds[m].last_admin_str = FORMAT(rec_cohort->list[i].meds[m].last_admin_dt, "DD-MMM HH:MM;;D")
                ELSE
                    SET rec_cohort->list[i].meds[m].dot = 0
                    SET rec_cohort->list[i].meds[m].last_admin_str = "Pending First Dose"
                ENDIF
                
                IF (rec_cohort->list[i].meds[m].is_restricted = 1)
                    SET rec_cohort->list[i].restricted_cnt = rec_cohort->list[i].restricted_cnt + 1
                    SET rec_cohort->list[i].action_req = 1
                    SET rec_cohort->list[i].meds[m].priority_rank = 100
                ENDIF
                
                IF (rec_cohort->list[i].meds[m].current_route = "IV")
                    SET rec_cohort->list[i].meds[m].priority_rank = rec_cohort->list[i].meds[m].priority_rank + 20
                    IF (rec_cohort->list[i].meds[m].dot > 2)
                        SET rec_cohort->list[i].action_req = 1
                        SET rec_cohort->list[i].ivost_cnt = rec_cohort->list[i].ivost_cnt + 1
                        SET rec_cohort->list[i].meds[m].priority_rank = rec_cohort->list[i].meds[m].priority_rank + 30
                    ENDIF
                ENDIF
            ENDFOR
            
            IF (rec_cohort->list[i].med_cnt > 1)
                FOR (sort_i = 1 TO rec_cohort->list[i].med_cnt - 1)
                    FOR (sort_j = sort_i + 1 TO rec_cohort->list[i].med_cnt)
                        IF (rec_cohort->list[i].meds[sort_i].priority_rank < rec_cohort->list[i].meds[sort_j].priority_rank)
                            SET stat = moverec(rec_cohort->list[i].meds[sort_i], temp_med->list[1])
                            SET stat = moverec(rec_cohort->list[i].meds[sort_j], rec_cohort->list[i].meds[sort_i])
                            SET stat = moverec(temp_med->list[1], rec_cohort->list[i].meds[sort_j])
                        ENDIF
                    ENDFOR
                ENDFOR
            ENDIF

            IF (rec_cohort->list[i].restricted_cnt > 0)
                SET rec_cohort->list[i].action_summary = CONCAT(rec_cohort->list[i].action_summary, "<span class='review-flag review-flag-red'>Restricted x ", TRIM(CNVTSTRING(rec_cohort->list[i].restricted_cnt)), "</span>")
            ENDIF
            IF (rec_cohort->list[i].ivost_cnt > 0)
                SET rec_cohort->list[i].action_summary = CONCAT(rec_cohort->list[i].action_summary, "<span class='review-flag review-flag-amber'>IVOST Review x ", TRIM(CNVTSTRING(rec_cohort->list[i].ivost_cnt)), "</span>")
            ENDIF
            IF (rec_cohort->list[i].med_cnt > 1)
                SET rec_cohort->list[i].action_summary = CONCAT(rec_cohort->list[i].action_summary, "<span class='review-flag review-flag-blue'>Multiple Active Agents</span>")
            ENDIF
            
            IF (rec_cohort->list[i].action_summary = "")
                IF (pat_has_active_abx = 1)
                    SET rec_cohort->list[i].action_summary = "<span class='review-flag review-flag-green'>No immediate AMS trigger</span>"
                ENDIF
            ENDIF

            SET rec_cohort->list[i].patient_priority = (rec_cohort->list[i].action_req * 1000) + (rec_cohort->list[i].restricted_cnt * 50) + t_score
            IF (pat_has_active_abx = 0) SET rec_cohort->list[i].patient_priority = rec_cohort->list[i].patient_priority - 10000 ENDIF 
        ENDFOR
    ENDIF

    ; =========================================================================
    ; JSON EXPORT
    ; =========================================================================
    SET _memory_reply_string = cnvtrectojson(rec_cohort)

ELSE
    ; =========================================================================
    ; UI MODE - THE SPA FRONTEND WITH DUAL SHIELD (CLINICAL STYLING)
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
        ROW + 1 call print(^<title>AMS SPA Dashboard</title>^)
        ROW + 1 call print(^<script>^)
        ROW + 1 call print(^var xhr = null;^)
        
        ROW + 1 call print(^function loadPatients() {^)
        ROW + 1 call print(^    var wardCode = document.getElementById('listSelector').value;^)
        ROW + 1 call print(^    if (wardCode == "0") return;^)
        ROW + 1 call print(^    document.getElementById('triageBody').innerHTML = "<tr><td colspan='2' style='text-align:center; padding: 50px;'><h3 style='color:#00695C; margin:0;'>Calculating Administration DOTs...</h3></td></tr>";^)
        
        ROW + 1 call print(^    xhr = new XMLCclRequest();^)
        ROW + 1 call print(^    xhr.onreadystatechange = function() {^)
        ROW + 1 call print(^        if (xhr.readyState == 4) {^)
        ROW + 1 call print(^            if (xhr.status == 200) { renderTable(xhr.responseText); }^)
        ROW + 1 call print(^            else if (xhr.status == 500) { renderTimeoutWarning(); }^) ; <--- JAVASCRIPT SHIELD
        ROW + 1 call print(^            else { document.getElementById('triageBody').innerHTML = '<tr><td colspan="2" style="text-align:center; padding:60px 20px;"><div style="background:#ffffff; border:1px solid #90cdf4; border-left:4px solid #3182ce; border-radius:8px; padding:20px; max-width:500px; margin:0 auto; color:#2b6cb0;"><h3 style="margin-top:0;">&#8505;&#65039; HTTP Error ' + xhr.status + '</h3><p>An unexpected network error occurred.</p></div></td></tr>'; }^)
        ROW + 1 call print(^        }^)
        ROW + 1 call print(^    };^)
        ROW + 1 call print(^    xhr.open('GET', '01_ams_stewardship_dash_GH:group1', true);^)
        ROW + 1 call print(CONCAT(^    xhr.send('"MINE", ^, TRIM(CNVTSTRING(rec_data->prsnl_id)), ^, ' + wardCode);^))
        ROW + 1 call print(^}^)

        ; --- DRIER, SYSTEM-FOCUSED 500 TIMEOUT WARNING ---
        ROW + 1 call print(^function renderTimeoutWarning() {^)
        ROW + 1 call print(^    var msgHtml = "<tr><td colspan='2' style='text-align:center; padding: 60px 20px;'>";^)
        ROW + 1 call print(^    msgHtml += "<div style='background:#ffffff; border:1px solid #90cdf4; border-left: 4px solid #3182ce; border-radius:8px; padding:20px; max-width:500px; margin:0 auto; color:#2b6cb0; text-align:left;'>";^)
        ROW + 1 call print(^    msgHtml += "<h3 style='margin-top:0;'>&#8505;&#65039; System Notice: Query Timeout</h3>";^)
        ROW + 1 call print(^    msgHtml += "<p style='color:#4a5568;'>The requested patient list may include a high number of patients or a patient whose history includes orders which exceed standard reporting execution limits.</p>";^)
        ROW + 1 call print(^    msgHtml += "<p style='margin-bottom:0; color:#4a5568;'><i>Please utilize standard PowerChart tabs for review, or select a smaller list.</i></p>";^)
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
        
        ; --- DRIER, SYSTEM-FOCUSED LIMIT WARNING ---
        ROW + 1 call print(^        var statusMsg = root.STATUS_MSG || root.status_msg || "";^)
        ROW + 1 call print(^        if (statusMsg.indexOf("LIMIT_EXCEEDED") > -1) {^)
        ROW + 1 call print(^            var pCnt = statusMsg.split("|")[1];^)
        ROW + 1 call print(^            var msgHtml = "<tr><td colspan='2' style='text-align:center; padding: 60px 20px;'>";^)
        ROW + 1 call print(^            msgHtml += "<div style='background:#ffffff; border:1px solid #90cdf4; border-left: 4px solid #3182ce; border-radius:8px; padding:20px; max-width:500px; margin:0 auto; color:#2b6cb0; text-align:left;'>";^)
        ROW + 1 call print(^            msgHtml += "<h3 style='margin-top:0;'>&#8505;&#65039; System Notice: Parameter Exceeded</h3>";^)
        ROW + 1 call print(^            msgHtml += "<p style='color:#4a5568;'>The selected list requests queries for <b>" + pCnt + "</b> concurrent records.</p>";^)
        ROW + 1 call print(^            msgHtml += "<p style='color:#4a5568;'>To maintain overall database performance, the maximum permitted parameter for this dashboard is <b>150 records</b>.</p>";^)
        ROW + 1 call print(^            msgHtml += "<p style='margin-bottom:0; color:#4a5568;'><i>Please select a smaller list from the dropdown menu to proceed.</i></p>";^)
        ROW + 1 call print(^            msgHtml += "</div></td></tr>";^)
        ROW + 1 call print(^            document.getElementById('triageBody').innerHTML = msgHtml;^)
        ROW + 1 call print(^            return;^)
        ROW + 1 call print(^        }^)

        ROW + 1 call print(^        var list = root.LIST || root.list || [];^)
        ROW + 1 call print(^        if (!Array.isArray(list)) { list = [list]; }^) 
        
        ROW + 1 call print(^        if (list.length === 0) { document.getElementById('triageBody').innerHTML = "<tr><td colspan='2' align='center'>No active patients found.</td></tr>"; return; }^)
        
        ROW + 1 call print(^        list.sort(function(a,b) {^)
        ROW + 1 call print(^            var pA = a.PATIENT_PRIORITY || a.patient_priority || 0;^)
        ROW + 1 call print(^            var pB = b.PATIENT_PRIORITY || b.patient_priority || 0;^)
        ROW + 1 call print(^            return pB - pA;^)
        ROW + 1 call print(^        });^)
        
        ROW + 1 call print(^        var html = '';^)
        ROW + 1 call print(^        for (var i=0; i<list.length; i++) {^)
        ROW + 1 call print(^            var pat = list[i];^)
        ROW + 1 call print(^            var name = pat.NAME || pat.name || "";^)
        ROW + 1 call print(^            var enc = pat.ENCNTR_ID || pat.encntr_id || "";^)
        ROW + 1 call print(^            var per = pat.PERSON_ID || pat.person_id || "";^)
        ROW + 1 call print(^            var bed = pat.ROOM_BED || pat.room_bed || "";^)
        ROW + 1 call print(^            var score = pat.SCORE || pat.score || 0;^)
        ROW + 1 call print(^            var col = pat.COLOR || pat.color || "Green";^)
        ROW + 1 call print(^            var sum = pat.SUMMARY || pat.summary || "";^)
        ROW + 1 call print(^            var act_sum = pat.ACTION_SUMMARY || pat.action_summary || "";^)
        ROW + 1 call print(^            var pcnt = pat.POLY_COUNT || pat.poly_count || 0;^)
        ROW + 1 call print(^            var mcnt = pat.MED_CNT || pat.med_cnt || 0;^)
        ROW + 1 call print(^            var areq = pat.ACTION_REQ || pat.action_req || 0;^)
        ROW + 1 call print(^            var prio = pat.PATIENT_PRIORITY || pat.patient_priority || 0;^)
        
        ROW + 1 call print(^            var rowClass = (areq == 1) ? "row-action" : (prio < 0 ? "row-inactive" : "row-normal");^)
        
        ROW + 1 call print(^            html += "<tr class='" + rowClass + "'>";^)
        ROW + 1 call print(^            html += "<td style='width:25%; border-right:1px dashed #e2e8f0; vertical-align:top;'>";^)
        ROW + 1 call print(^            html += "<div class='bed-title'>" + bed + "</div>";^)
        ROW + 1 call print(^            html += "<a class='patient-link' href=\"javascript:APPLINK(0,'Powerchart.exe','/PERSONID=" + per + " /ENCNTRID=" + enc + "')\">" + name + "</a><br/>";^)
        ROW + 1 call print(^            html += "<div style='margin-top:6px;'><span class='badge-" + col + "'>Acuity: " + score + "</span>";^)
        ROW + 1 call print(^            html += "<span style='font-size:10px; color:#718096; margin-left:6px;'>Orders: " + pcnt + "</span></div>";^)
        ROW + 1 call print(^            html += "<div class='acuity-summary'>" + sum + "</div>";^)
        ROW + 1 call print(^            html += "<div style='margin-top:8px;'>" + act_sum + "</div></td>";^)
        
        ROW + 1 call print(^            html += "<td style='width:75%; padding-left:20px; vertical-align:top;'>";^)
        ROW + 1 call print(^            if (mcnt === 0) { html += "<div style='color:#a0aec0; font-style:italic; padding-top:10px;'>No active antimicrobials detected.</div>"; }^)
        ROW + 1 call print(^            else {^)
        ROW + 1 call print(^                var meds = pat.MEDS || pat.meds || [];^)
        ROW + 1 call print(^                if (!Array.isArray(meds)) { meds = [meds]; }^)
        
        ROW + 1 call print(^                meds.sort(function(a,b) {^)
        ROW + 1 call print(^                    var mPA = a.PRIORITY_RANK || a.priority_rank || 0;^)
        ROW + 1 call print(^                    var mPB = b.PRIORITY_RANK || b.priority_rank || 0;^)
        ROW + 1 call print(^                    return mPB - mPA;^)
        ROW + 1 call print(^                });^)
        
        ROW + 1 call print(^                for(var m=0; m<meds.length; m++) {^)
        ROW + 1 call print(^                    var med = meds[m];^)
        ROW + 1 call print(^                    var mnom = med.MNEMONIC || med.mnemonic || "";^)
        ROW + 1 call print(^                    var mroute = med.CURRENT_ROUTE || med.current_route || "UNK";^)
        ROW + 1 call print(^                    var mind = med.INDICATION || med.indication || "";^)
        ROW + 1 call print(^                    var mrest = med.IS_RESTRICTED || med.is_restricted || 0;^)
        ROW + 1 call print(^                    var mdot = med.DOT || med.dot || 0;^)
        ROW + 1 call print(^                    var mlast = med.LAST_ADMIN_STR || med.last_admin_str || "Pending";^)
        
        ROW + 1 call print(^                    html += "<div class='med-row med-row-active'><span class='med-name'>" + escapeHTML(mnom) + "</span>";^)
        
        ROW + 1 call print(^                    if (mroute==="IV" || mroute==="IM" || mroute==="SC") { html += " <span class='pill pill-par'>" + mroute + "</span>"; }^)
        ROW + 1 call print(^                    else if (mroute==="PO" || mroute==="ENT" || mroute==="PR") { html += " <span class='pill pill-ent'>" + mroute + "</span>"; }^)
        ROW + 1 call print(^                    else if (mroute !== "UNK" && mroute !== "") { html += " <span class='pill pill-oth'>" + mroute + "</span>"; }^)
        
        ROW + 1 call print(^                    if (mroute === "IV" && mdot > 2) { html += " <span class='pill-warn' title='> 48h of IV therapy'>IVOST?</span>"; }^)
        ROW + 1 call print(^                    if (mrest == 1) { html += " <span class='pill-rest'>RESTRICTED</span>"; }^)
        
        ROW + 1 call print(^                    html += "<div class='med-ind'>Ind: <span style='font-weight:600; color:#4a5568;'>" + escapeHTML(mind) + "</span></div>";^)
        
        ROW + 1 call print(^                    if (mdot > 0) {^)
        ROW + 1 call print(^                        html += "<div class='med-dot'>Day " + mdot + " (Last Dose: " + escapeHTML(mlast) + ")</div>";^)
        ROW + 1 call print(^                    } else {^)
        ROW + 1 call print(^                        html += "<div class='med-dot'>Pending first administration</div>";^)
        ROW + 1 call print(^                    }^)
        ROW + 1 call print(^                    html += "</div>";^)
        ROW + 1 call print(^                }^)
        ROW + 1 call print(^            }^)
        ROW + 1 call print(^            html += "</td></tr>";^)
        ROW + 1 call print(^        }^)
        ROW + 1 call print(^        document.getElementById('triageBody').innerHTML = html;^)
        ROW + 1 call print(^    } catch (e) { document.getElementById('triageBody').innerHTML = "<tr><td colspan='2'>JSON Parse Error: " + e.message + "</td></tr>"; }^)
        ROW + 1 call print(^}^)
        ROW + 1 call print(^</script>^)

        ROW + 1 call print(^<style>^)
        ROW + 1 call print(^  body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; background: #f4f7f6; padding: 20px; color: #2d3748; margin: 0; font-size: 13px; line-height: 1.4; }^)
        ROW + 1 call print(^  .dashboard-container { box-shadow: 0 4px 16px rgba(0,0,0,0.06); border-radius: 8px; background: #fff; overflow: hidden; border: 1px solid #e2e8f0; }^)
        ROW + 1 call print(^  .dashboard-header { background: linear-gradient(135deg, #00695C 0%, #004D40 100%); color: #fff; padding: 18px 24px; font-size: 18px; font-weight: 600; letter-spacing: 0.3px; }^)
        ROW + 1 call print(^  .dashboard-content { padding: 24px; min-height: 400px; }^)
        ROW + 1 call print(^  .info-box { background: #e6fffa; border-left: 4px solid #319795; padding: 12px 16px; margin-bottom: 24px; font-size: 13px; color: #234e52; border-radius: 0 4px 4px 0; }^)
        ROW + 1 call print(^  select { padding: 8px 12px; font-size: 13px; border: 1px solid #cbd5e0; width: 320px; border-radius: 4px; outline: none; color: #4a5568; }^)
        ROW + 1 call print(^  select:focus { border-color: #319795; box-shadow: 0 0 0 2px rgba(49, 151, 149, 0.2); }^)
        ROW + 1 call print(^  button { padding: 8px 18px; background: #319795; color: white; border: none; cursor: pointer; font-size: 13px; margin-left: 12px; font-weight: 600; border-radius: 4px; transition: background 0.2s; }^)
        ROW + 1 call print(^  button:hover { background: #2c7a7b; }^)
        ROW + 1 call print(^  .ward-tbl { width: 100%; margin-top: 20px; border-collapse: collapse; font-size: 12px; background: #fff; }^)
        ROW + 1 call print(^  .ward-tbl th { background: #f7fafc; font-weight: 600; color: #4a5568; text-align: left; text-transform: uppercase; font-size: 11px; letter-spacing: 0.5px; padding: 12px 14px; border-bottom: 2px solid #e2e8f0; }^)
        ROW + 1 call print(^  .ward-tbl td { padding: 16px 14px; border-bottom: 1px solid #edf2f7; vertical-align: top; }^)
        ROW + 1 call print(^  .ward-tbl tr:hover { background-color: #fcfcfc; }^)
        
        ROW + 1 call print(^  .row-action { border-left: 5px solid #dd6b20; }^)
        ROW + 1 call print(^  .row-normal { border-left: 5px solid transparent; }^)
        ROW + 1 call print(^  .row-inactive { border-left: 5px solid transparent; opacity: 0.7; }^)
        
        ROW + 1 call print(^  .bed-title { font-size: 11px; color: #718096; font-weight: 600; margin-bottom: 4px; text-transform: uppercase; letter-spacing: 0.3px; }^)
        ROW + 1 call print(^  .patient-link { color: #2b6cb0; text-decoration: none; font-size: 14px; font-weight: 600; }^)
        ROW + 1 call print(^  .patient-link:hover { text-decoration: underline; color: #2c5282; }^)
        
        ROW + 1 call print(^  .badge-Red { background: #fed7d7; color: #c53030; padding: 2px 8px; border-radius: 4px; font-weight:bold; font-size:10px; border: 1px solid #feb2b2; }^)
        ROW + 1 call print(^  .badge-Amber { background: #feebc8; color: #c05621; padding: 2px 8px; border-radius: 4px; font-weight:bold; font-size:10px; border: 1px solid #fbd38d; }^)
        ROW + 1 call print(^  .badge-Green { background: #c6f6d5; color: #276749; padding: 2px 8px; border-radius: 4px; font-weight:bold; font-size:10px; border: 1px solid #9ae6b4; }^)
        ROW + 1 call print(^  .trig-pill { display: inline-block; background: #edf2f7; border: 1px solid #e2e8f0; border-radius: 4px; padding: 2px 6px; margin: 2px 4px 2px 0; font-size: 10px; color: #4a5568; }^)
        ROW + 1 call print(^  .acuity-summary { font-size: 11px; margin-top: 6px; color: #718096; line-height: 1.5; }^)

        ROW + 1 call print(^  .med-row { padding: 10px 12px; border-radius: 6px; margin-bottom: 6px; display: inline-block; width: 100%; box-sizing: border-box; }^)
        ROW + 1 call print(^  .med-row:last-child { margin-bottom: 0; }^)
        ROW + 1 call print(^  .med-row-active { background-color: #f0f9ff; border: 1px solid #bae6fd; }^)
        ROW + 1 call print(^  .med-name { font-weight: 600; color: #2d3748; font-size: 13px; display:inline-block; }^)
        ROW + 1 call print(^  .med-ind { font-size: 11px; margin-top: 4px; color: #718096; }^)
        ROW + 1 call print(^  .med-dot { font-size: 11px; color: #4a5568; margin-top: 4px; font-weight: 600; }^)

        ROW + 1 call print(^  .pill-rest { background: #fff5f5; color: #c53030; border: 1px solid #feb2b2; padding: 2px 6px; border-radius: 12px; font-weight: 600; font-size: 9px; margin-left: 6px; display:inline-block; vertical-align: middle; cursor: help; }^)
        ROW + 1 call print(^  .pill-par { background: #ebf4ff; color: #4c51bf; border: 1px solid #c3dafe; padding: 2px 6px; border-radius: 12px; font-weight: 600; font-size: 9px; margin-left: 6px; display:inline-block; vertical-align: middle; cursor: help; }^)
        ROW + 1 call print(^  .pill-ent { background: #f0fff4; color: #2f855a; border: 1px solid #9ae6b4; padding: 2px 6px; border-radius: 12px; font-weight: 600; font-size: 9px; margin-left: 6px; display:inline-block; vertical-align: middle; cursor: help; }^)
        ROW + 1 call print(^  .pill-oth { background: #e6fffa; color: #234e52; border: 1px solid #81e6d9; padding: 2px 6px; border-radius: 12px; font-weight: 600; font-size: 9px; margin-left: 6px; display:inline-block; vertical-align: middle; cursor: help; }^)
        ROW + 1 call print(^  .pill-warn { background: #fffaf0; color: #dd6b20; border: 1px solid #fbd38d; padding: 2px 6px; border-radius: 12px; font-weight: 600; font-size: 9px; margin-left: 6px; display:inline-block; vertical-align: middle; cursor: help; }^)

        ROW + 1 call print(^  .review-flag { display:inline-block; padding:2px 8px; border-radius:12px; font-size:10px; font-weight:700; margin:0 6px 6px 0; }^)
        ROW + 1 call print(^  .review-flag-red { background:#fff5f5; color:#c53030; border:1px solid #feb2b2; }^)
        ROW + 1 call print(^  .review-flag-amber { background:#fffaf0; color:#dd6b20; border:1px solid #fbd38d; }^)
        ROW + 1 call print(^  .review-flag-blue { background:#ebf8ff; color:#2b6cb0; border:1px solid #90cdf4; }^)
        ROW + 1 call print(^  .review-flag-green { background:#f0fff4; color:#2f855a; border:1px solid #9ae6b4; }^)

        ROW + 1 call print(^</style>^)
        ROW + 1 call print(^</head><body>^)
        
        ROW + 1 call print(^<div class="dashboard-container">^)
        ROW + 1 call print(^<div class="dashboard-header">Point Prevalence AMS Dashboard</div>^)
        ROW + 1 call print(^<div class="dashboard-content">^)
        ROW + 1 call print(^<div class="info-box">^)
        ROW + 1 call print(CONCAT(^<b>Pharmacist Logged In:</b> ^, rec_data->prsnl_name, ^<br/>^))
        ROW + 1 call print(^</div>^)

        IF (rec_data->list_cnt > 0)
            ROW + 1 call print(^<select id="listSelector">^)
            ROW + 1 call print(^<option value="0">-- Select a Patient List to Audit --</option>^)
            FOR (i = 1 TO rec_data->list_cnt)
                ROW + 1 call print(CONCAT(^<option value="^, TRIM(CNVTSTRING(rec_data->lists[i].list_id)), ^">^, rec_data->lists[i].list_name, ^</option>^))
            ENDFOR
            ROW + 1 call print(^</select>^)
            ROW + 1 call print(^<button onclick="loadPatients()">Load Ward Audit</button>^)
        ENDIF

        ROW + 1 call print(^<table class='ward-tbl'>^)
        ROW + 1 call print(^<thead><tr><th width="25%">Patient & Location</th><th width="75%">Active Antimicrobials & DOT</th></tr></thead>^)
        ROW + 1 call print(^<tbody id='triageBody'>^)
        ROW + 1 call print(^<tr><td colspan='2' style='text-align:center; padding: 60px 20px; color:#a0aec0; font-size:14px;'>Select a patient list above to render the SPA grid.</td></tr>^)
        ROW + 1 call print(^</tbody></table>^)
        ROW + 1 call print(^</div></div>^)
        ROW + 1 call print(^</body></html>^)
    WITH NOCOUNTER, MAXCOL=65534, FORMAT=VARIABLE, NOHEADING

ENDIF
END
GO

