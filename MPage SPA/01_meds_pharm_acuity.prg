/**
 * PROGRAM: 01_meds_pharm_acuity:group1
 *
 * SPA JSON BACKEND - Patient Acuity
 * Extracted from the legacy pharmacist MPage Acuity tab.
 * Returns JSON via CNVTRECTOJSON(reply).
 * Backend owns Acuity CSS, scaffold HTML, and static markup.
 * Shell owns tab lifecycle and trigger expand/collapse binding.
 */
DROP PROGRAM 01_meds_pharm_acuity:group1 GO
CREATE PROGRAM 01_meds_pharm_acuity:group1

PROMPT "Output to File/Printer/MINE" = "MINE", "PatientID" = 0, "EncntrID" = 0
WITH OUTDEV, pid, eid

RECORD reply (
    1 status
        2 code         = vc
        2 message      = vc
    1 meta
        2 module       = vc
        2 title        = vc
        2 patient_id   = f8
        2 encntr_id    = f8
        2 reason_count = i4
        2 poly_count   = i4
    1 ui
        2 html_parts[*]
            3 text = vc
        2 css_parts[*]
            3 text = vc
    1 acuity
        2 score        = i4
        2 color        = vc
        2 triage_tier  = vc
        2 action_plan  = vc
        2 reason_count = i4
        2 poly_count   = i4
    1 reasons[*]
        2 text        = vc
        2 points      = i4
        2 detail_html = vc
)

RECORD rec_acuity (
    1 score = i4
    1 color = vc
    1 poly_count = i4
    1 reason_cnt = i4
    1 flag_ebl = i2
    1 flag_transfusion = i2
    1 flag_preeclampsia = i2
    1 flag_dvt = i2
    1 flag_epilepsy = i2
    1 flag_insulin = i2
    1 flag_antiepileptic = i2
    1 flag_anticoag = i2
    1 flag_antihypertensive = i2
    1 flag_neuraxial = i2
    1 flag_poly_severe = i2
    1 flag_poly_mod = i2
    1 flag_imews = i2
    1 flag_bsbg = i2
    1 flag_high_alert_iv = i2
    1 flag_oxytocin_iv = i2
    1 flag_delivered = i2
    1 det_ebl = vc
    1 det_transfusion = vc
    1 det_preeclampsia = vc
    1 det_dvt = vc
    1 det_epilepsy = vc
    1 det_insulin = vc
    1 det_antiepileptic = vc
    1 det_anticoag = vc
    1 det_antihypertensive = vc
    1 det_neuraxial = vc
    1 det_poly = vc
    1 det_imews = vc
    1 det_bsbg = vc
    1 det_high_alert_iv = vc
    1 det_oxytocin = vc
    1 reasons[*]
        2 text = vc
        2 points = i4
        2 detail_html = vc
)

DECLARE stat = i4 WITH NOCONSTANT(0)
DECLARE x = i4 WITH NOCONSTANT(0)
DECLARE v_html_idx = i4 WITH NOCONSTANT(0)
DECLARE v_html_part = vc WITH NOCONSTANT(""), MAXLEN=65534
DECLARE v_triage_tier = vc WITH NOCONSTANT(" ")
DECLARE v_action_plan = vc WITH NOCONSTANT(" ")

SET reply->status.code = "error"
SET reply->status.message = "Patient ID is required."
SET reply->meta.module = "01_meds_pharm_acuity:group1"
SET reply->meta.title = "Patient Acuity"
SET reply->meta.patient_id = CNVTREAL($pid)
SET reply->meta.encntr_id = CNVTREAL($eid)

IF (CNVTREAL($pid) > 0)

    ; Gather Active Problems
    SELECT INTO "NL:"
        NOM = N.SOURCE_STRING
        , UNOM = CNVTUPPER(N.SOURCE_STRING)
        , DT_STR = FORMAT(P.ONSET_DT_TM, "DD/MM/YYYY")
    FROM PROBLEM P
        , NOMENCLATURE N
    PLAN P WHERE P.PERSON_ID = CNVTREAL($pid)
        AND P.ACTIVE_IND = 1
        AND P.LIFE_CYCLE_STATUS_CD = 3301.00
    JOIN N WHERE N.NOMENCLATURE_ID = P.NOMENCLATURE_ID
    DETAIL
        IF (FINDSTRING("PRE-ECLAMPSIA", UNOM) > 0 OR FINDSTRING("PREECLAMPSIA", UNOM) > 0)
            rec_acuity->flag_preeclampsia = 1
            rec_acuity->det_preeclampsia = CONCAT(rec_acuity->det_preeclampsia, "<div class='trigger-det-item'><b>", TRIM(NOM), "</b> (Onset: ", DT_STR, ")</div>")
        ELSEIF (FINDSTRING("DEEP VEIN THROMBOSIS", UNOM) > 0 OR FINDSTRING("PULMONARY EMBOLISM", UNOM) > 0 OR FINDSTRING("DVT", UNOM) > 0)
            rec_acuity->flag_dvt = 1
            rec_acuity->det_dvt = CONCAT(rec_acuity->det_dvt, "<div class='trigger-det-item'><b>", TRIM(NOM), "</b> (Onset: ", DT_STR, ")</div>")
        ELSEIF (FINDSTRING("EPILEPSY", UNOM) > 0 OR FINDSTRING("SEIZURE", UNOM) > 0)
            rec_acuity->flag_epilepsy = 1
            rec_acuity->det_epilepsy = CONCAT(rec_acuity->det_epilepsy, "<div class='trigger-det-item'><b>", TRIM(NOM), "</b> (Onset: ", DT_STR, ")</div>")
        ENDIF
    WITH NOCOUNTER

    ; Gather Active Diagnoses
    SELECT INTO "NL:"
        NOM = N.SOURCE_STRING
        , UNOM = CNVTUPPER(N.SOURCE_STRING)
        , DT_STR = FORMAT(D.DIAG_DT_TM, "DD/MM/YYYY")
    FROM DIAGNOSIS D
        , NOMENCLATURE N
    PLAN D WHERE D.PERSON_ID = CNVTREAL($pid)
        AND D.ACTIVE_IND = 1
    JOIN N WHERE N.NOMENCLATURE_ID = D.NOMENCLATURE_ID
    DETAIL
        IF (FINDSTRING("PRE-ECLAMPSIA", UNOM) > 0 OR FINDSTRING("PREECLAMPSIA", UNOM) > 0)
            rec_acuity->flag_preeclampsia = 1
            rec_acuity->det_preeclampsia = CONCAT(rec_acuity->det_preeclampsia, "<div class='trigger-det-item'><b>", TRIM(NOM), "</b> (Diagnosed: ", DT_STR, ")</div>")
        ELSEIF (FINDSTRING("DEEP VEIN THROMBOSIS", UNOM) > 0 OR FINDSTRING("PULMONARY EMBOLISM", UNOM) > 0 OR FINDSTRING("DVT", UNOM) > 0)
            rec_acuity->flag_dvt = 1
            rec_acuity->det_dvt = CONCAT(rec_acuity->det_dvt, "<div class='trigger-det-item'><b>", TRIM(NOM), "</b> (Diagnosed: ", DT_STR, ")</div>")
        ELSEIF (FINDSTRING("EPILEPSY", UNOM) > 0 OR FINDSTRING("SEIZURE", UNOM) > 0)
            rec_acuity->flag_epilepsy = 1
            rec_acuity->det_epilepsy = CONCAT(rec_acuity->det_epilepsy, "<div class='trigger-det-item'><b>", TRIM(NOM), "</b> (Diagnosed: ", DT_STR, ")</div>")
        ENDIF
    WITH NOCOUNTER

    ; Calculate Polypharmacy & High Risk Medications
    SELECT INTO "NL:"
        MNEM = O.ORDER_MNEMONIC
        , UNOM = CNVTUPPER(O.ORDER_MNEMONIC)
        , DT_STR = FORMAT(O.CURRENT_START_DT_TM, "DD/MM/YYYY HH:MM")
        , SDL = O.SIMPLIFIED_DISPLAY_LINE
    FROM ORDERS O
        , ACT_PW_COMP APC
    PLAN O WHERE O.PERSON_ID = CNVTREAL($pid)
        AND O.ORDER_STATUS_CD = 2550.00
        AND O.CATALOG_TYPE_CD = 2516.00
        AND O.ORIG_ORD_AS_FLAG = 0
        AND O.TEMPLATE_ORDER_ID = 0
    JOIN APC WHERE APC.PARENT_ENTITY_ID = OUTERJOIN(O.ORDER_ID)
        AND APC.PARENT_ENTITY_NAME = OUTERJOIN("ORDERS")
        AND APC.ACTIVE_IND = OUTERJOIN(1)
    ORDER BY O.ORDER_ID
    HEAD O.ORDER_ID
        IF ((APC.PATHWAY_ID > 0.0 AND (FINDSTRING("CHLORPHENAMINE", UNOM) > 0 OR FINDSTRING("CYCLIZINE", UNOM) > 0 OR FINDSTRING("LACTULOSE", UNOM) > 0 OR FINDSTRING("ONDANSETRON", UNOM) > 0))
            OR FINDSTRING("SODIUM CHLORIDE", UNOM) > 0 OR FINDSTRING("LACTATE", UNOM) > 0 OR FINDSTRING("GLUCOSE", UNOM) > 0
            OR FINDSTRING("MAINTELYTE", UNOM) > 0 OR FINDSTRING("WATER FOR INJECTION", UNOM) > 0)
            stat = 1
        ELSE
            rec_acuity->poly_count = rec_acuity->poly_count + 1
            rec_acuity->det_poly = CONCAT(rec_acuity->det_poly, "<div class='trigger-det-item'>&bull; <b>", TRIM(MNEM), "</b> ", TRIM(SDL), " (Started: ", DT_STR, ")</div>")
        ENDIF

        IF (FINDSTRING("MAGNESIUM", UNOM) > 0 OR FINDSTRING("INSULIN", UNOM) > 0 OR FINDSTRING("LABETALOL", UNOM) > 0 OR FINDSTRING("HYDRALAZINE", UNOM) > 0 OR FINDSTRING("VASOPRESSIN", UNOM) > 0 OR FINDSTRING("NORADRENALINE", UNOM) > 0)
            IF (O.IV_IND = 1)
                rec_acuity->flag_high_alert_iv = 1
                rec_acuity->det_high_alert_iv = CONCAT(rec_acuity->det_high_alert_iv, "<div class='trigger-det-item'><b>", TRIM(MNEM), "</b> ", TRIM(SDL), " (Started: ", DT_STR, ")</div>")
            ENDIF
        ENDIF

        IF (FINDSTRING("TINZAPARIN", UNOM) > 0 OR FINDSTRING("HEPARIN", UNOM) > 0 OR FINDSTRING("ENOXAPARIN", UNOM) > 0)
            rec_acuity->flag_anticoag = 1
            rec_acuity->det_anticoag = CONCAT(rec_acuity->det_anticoag, "<div class='trigger-det-item'><b>", TRIM(MNEM), "</b> ", TRIM(SDL), " (Started: ", DT_STR, ")</div>")
        ELSEIF (FINDSTRING("INSULIN", UNOM) > 0)
            rec_acuity->flag_insulin = 1
            rec_acuity->det_insulin = CONCAT(rec_acuity->det_insulin, "<div class='trigger-det-item'><b>", TRIM(MNEM), "</b> ", TRIM(SDL), " (Started: ", DT_STR, ")</div>")
        ELSEIF (FINDSTRING("LEVETIRACETAM", UNOM) > 0 OR FINDSTRING("LAMOTRIGINE", UNOM) > 0 OR FINDSTRING("VALPROATE", UNOM) > 0 OR FINDSTRING("CARBAMAZEPINE", UNOM) > 0)
            rec_acuity->flag_antiepileptic = 1
            rec_acuity->det_antiepileptic = CONCAT(rec_acuity->det_antiepileptic, "<div class='trigger-det-item'><b>", TRIM(MNEM), "</b> ", TRIM(SDL), " (Started: ", DT_STR, ")</div>")
        ELSEIF (FINDSTRING("LABETALOL", UNOM) > 0 OR FINDSTRING("NIFEDIPINE", UNOM) > 0 OR FINDSTRING("METHYLDOPA", UNOM) > 0)
            rec_acuity->flag_antihypertensive = 1
            rec_acuity->det_antihypertensive = CONCAT(rec_acuity->det_antihypertensive, "<div class='trigger-det-item'><b>", TRIM(MNEM), "</b> ", TRIM(SDL), " (Started: ", DT_STR, ")</div>")
        ELSEIF (FINDSTRING("BUPIVACAINE", UNOM) > 0 OR FINDSTRING("LEVOBUPIVACAINE", UNOM) > 0)
            rec_acuity->flag_neuraxial = 1
            rec_acuity->det_neuraxial = CONCAT(rec_acuity->det_neuraxial, "<div class='trigger-det-item'><b>", TRIM(MNEM), "</b> ", TRIM(SDL), " (Started: ", DT_STR, ")</div>")
        ENDIF
    WITH NOCOUNTER

    IF (rec_acuity->poly_count >= 10)
        SET rec_acuity->flag_poly_severe = 1
    ELSEIF (rec_acuity->poly_count >= 5)
        SET rec_acuity->flag_poly_mod = 1
    ENDIF

    ; Check Clinical Events
    SELECT INTO "NL:"
        VAL = CE.RESULT_VAL
        , TITLE = UAR_GET_CODE_DISPLAY(CE.EVENT_CD)
        , DT_STR = FORMAT(CE.PERFORMED_DT_TM, "DD/MM/YYYY HH:MM")
    FROM CLINICAL_EVENT CE
    PLAN CE WHERE CE.PERSON_ID = CNVTREAL($pid)
        AND CE.EVENT_CD IN (15071366.00, 82546829.00, 15083551.00, 19995695.00, 15068265.00, 10933794.00, 28082563.00, 15068250.00)
        AND CE.VALID_UNTIL_DT_TM > SYSDATE
        AND CE.PERFORMED_DT_TM > CNVTLOOKBEHIND("7,D")
        AND CE.RESULT_STATUS_CD IN (25, 34, 35)
    ORDER BY CE.EVENT_CD, CE.PERFORMED_DT_TM DESC
    HEAD CE.EVENT_CD
        IF (CE.EVENT_CD = 15068265.00)
            IF (CE.PERFORMED_DT_TM > CNVTLOOKBEHIND("24,H") AND CNVTINT(CE.RESULT_VAL) >= 2)
                rec_acuity->flag_imews = 1
                rec_acuity->det_imews = CONCAT("<div class='trigger-det-item'><b>Score: ", TRIM(VAL, 3), "</b> (", DT_STR, ")</div>")
            ENDIF
        ELSEIF (CE.EVENT_CD = 10933794.00)
            IF (CE.PERFORMED_DT_TM > CNVTLOOKBEHIND("24,H") AND CNVTREAL(CE.RESULT_VAL) > 11.1)
                rec_acuity->flag_bsbg = 1
                rec_acuity->det_bsbg = CONCAT("<div class='trigger-det-item'><b>Value: ", TRIM(VAL, 3), " mmol/L</b> (", DT_STR, ")</div>")
            ENDIF
        ENDIF
    DETAIL
        IF (CE.EVENT_CD = 15071366.00)
            rec_acuity->flag_transfusion = 1
            rec_acuity->det_transfusion = CONCAT(rec_acuity->det_transfusion, "<div class='trigger-det-item'><b>", TRIM(TITLE), "</b>: ", TRIM(VAL), " (", DT_STR, ")</div>")
        ELSEIF (CE.EVENT_CD IN (82546829.00, 15083551.00, 19995695.00) AND CNVTREAL(VAL) > 1000.0)
            rec_acuity->flag_ebl = 1
            rec_acuity->det_ebl = CONCAT(rec_acuity->det_ebl, "<div class='trigger-det-item'><b>", TRIM(TITLE), "</b>: ", TRIM(VAL), " ml (", DT_STR, ")</div>")
        ELSEIF (CE.EVENT_CD IN (28082563.00, 15068250.00))
            rec_acuity->flag_delivered = 1
        ENDIF
    WITH NOCOUNTER

    ; Tally Final Score
    IF (rec_acuity->flag_high_alert_iv = 1)
        SET rec_acuity->score = rec_acuity->score + 5
        SET rec_acuity->reason_cnt = rec_acuity->reason_cnt + 1
        SET stat = ALTERLIST(rec_acuity->reasons, rec_acuity->reason_cnt)
        SET rec_acuity->reasons[rec_acuity->reason_cnt].text = "Continuous IV infusion of high-alert medication"
        SET rec_acuity->reasons[rec_acuity->reason_cnt].points = 5
        SET rec_acuity->reasons[rec_acuity->reason_cnt].detail_html = rec_acuity->det_high_alert_iv
    ENDIF
    IF (rec_acuity->flag_imews = 1)
        SET rec_acuity->score = rec_acuity->score + 3
        SET rec_acuity->reason_cnt = rec_acuity->reason_cnt + 1
        SET stat = ALTERLIST(rec_acuity->reasons, rec_acuity->reason_cnt)
        SET rec_acuity->reasons[rec_acuity->reason_cnt].text = "Physiological Instability (IMEWS Score &ge;2)"
        SET rec_acuity->reasons[rec_acuity->reason_cnt].points = 3
        SET rec_acuity->reasons[rec_acuity->reason_cnt].detail_html = rec_acuity->det_imews
    ENDIF
    IF (rec_acuity->flag_transfusion = 1 OR rec_acuity->flag_ebl = 1)
        SET rec_acuity->score = rec_acuity->score + 3
        SET rec_acuity->reason_cnt = rec_acuity->reason_cnt + 1
        SET stat = ALTERLIST(rec_acuity->reasons, rec_acuity->reason_cnt)
        SET rec_acuity->reasons[rec_acuity->reason_cnt].text = "Massive Haemorrhage (>1000ml EBL) or Transfusion"
        SET rec_acuity->reasons[rec_acuity->reason_cnt].points = 3
        SET rec_acuity->reasons[rec_acuity->reason_cnt].detail_html = CONCAT(rec_acuity->det_transfusion, rec_acuity->det_ebl)
    ENDIF
    IF (rec_acuity->flag_preeclampsia = 1)
        SET rec_acuity->score = rec_acuity->score + 3
        SET rec_acuity->reason_cnt = rec_acuity->reason_cnt + 1
        SET stat = ALTERLIST(rec_acuity->reasons, rec_acuity->reason_cnt)
        SET rec_acuity->reasons[rec_acuity->reason_cnt].text = "Active Diagnosis/Problem: Pre-Eclampsia"
        SET rec_acuity->reasons[rec_acuity->reason_cnt].points = 3
        SET rec_acuity->reasons[rec_acuity->reason_cnt].detail_html = rec_acuity->det_preeclampsia
    ENDIF
    IF (rec_acuity->flag_dvt = 1)
        SET rec_acuity->score = rec_acuity->score + 3
        SET rec_acuity->reason_cnt = rec_acuity->reason_cnt + 1
        SET stat = ALTERLIST(rec_acuity->reasons, rec_acuity->reason_cnt)
        SET rec_acuity->reasons[rec_acuity->reason_cnt].text = "Active Diagnosis/Problem: DVT or Pulmonary Embolism"
        SET rec_acuity->reasons[rec_acuity->reason_cnt].points = 3
        SET rec_acuity->reasons[rec_acuity->reason_cnt].detail_html = rec_acuity->det_dvt
    ENDIF
    IF (rec_acuity->flag_epilepsy = 1)
        SET rec_acuity->score = rec_acuity->score + 3
        SET rec_acuity->reason_cnt = rec_acuity->reason_cnt + 1
        SET stat = ALTERLIST(rec_acuity->reasons, rec_acuity->reason_cnt)
        SET rec_acuity->reasons[rec_acuity->reason_cnt].text = "Active Diagnosis/Problem: Epilepsy/Seizure Disorder"
        SET rec_acuity->reasons[rec_acuity->reason_cnt].points = 3
        SET rec_acuity->reasons[rec_acuity->reason_cnt].detail_html = rec_acuity->det_epilepsy
    ENDIF
    IF (rec_acuity->flag_insulin = 1)
        SET rec_acuity->score = rec_acuity->score + 3
        SET rec_acuity->reason_cnt = rec_acuity->reason_cnt + 1
        SET stat = ALTERLIST(rec_acuity->reasons, rec_acuity->reason_cnt)
        SET rec_acuity->reasons[rec_acuity->reason_cnt].text = "High Alert Med: Insulin"
        SET rec_acuity->reasons[rec_acuity->reason_cnt].points = 3
        SET rec_acuity->reasons[rec_acuity->reason_cnt].detail_html = rec_acuity->det_insulin
    ENDIF
    IF (rec_acuity->flag_antiepileptic = 1)
        SET rec_acuity->score = rec_acuity->score + 3
        SET rec_acuity->reason_cnt = rec_acuity->reason_cnt + 1
        SET stat = ALTERLIST(rec_acuity->reasons, rec_acuity->reason_cnt)
        SET rec_acuity->reasons[rec_acuity->reason_cnt].text = "High Alert Med: Antiepileptic"
        SET rec_acuity->reasons[rec_acuity->reason_cnt].points = 3
        SET rec_acuity->reasons[rec_acuity->reason_cnt].detail_html = rec_acuity->det_antiepileptic
    ENDIF
    IF (rec_acuity->flag_poly_severe = 1)
        SET rec_acuity->score = rec_acuity->score + 3
        SET rec_acuity->reason_cnt = rec_acuity->reason_cnt + 1
        SET stat = ALTERLIST(rec_acuity->reasons, rec_acuity->reason_cnt)
        SET rec_acuity->reasons[rec_acuity->reason_cnt].text = CONCAT("Severe Polypharmacy (", TRIM(CNVTSTRING(rec_acuity->poly_count)), " active meds)")
        SET rec_acuity->reasons[rec_acuity->reason_cnt].points = 3
        SET rec_acuity->reasons[rec_acuity->reason_cnt].detail_html = rec_acuity->det_poly
    ENDIF
    IF (rec_acuity->flag_anticoag = 1)
        SET rec_acuity->score = rec_acuity->score + 2
        SET rec_acuity->reason_cnt = rec_acuity->reason_cnt + 1
        SET stat = ALTERLIST(rec_acuity->reasons, rec_acuity->reason_cnt)
        SET rec_acuity->reasons[rec_acuity->reason_cnt].text = "Targeted Med: Anticoagulant (LMWH/Heparin)"
        SET rec_acuity->reasons[rec_acuity->reason_cnt].points = 2
        SET rec_acuity->reasons[rec_acuity->reason_cnt].detail_html = rec_acuity->det_anticoag
    ENDIF
    IF (rec_acuity->flag_antihypertensive = 1)
        SET rec_acuity->score = rec_acuity->score + 2
        SET rec_acuity->reason_cnt = rec_acuity->reason_cnt + 1
        SET stat = ALTERLIST(rec_acuity->reasons, rec_acuity->reason_cnt)
        SET rec_acuity->reasons[rec_acuity->reason_cnt].text = "Targeted Med: Antihypertensive"
        SET rec_acuity->reasons[rec_acuity->reason_cnt].points = 2
        SET rec_acuity->reasons[rec_acuity->reason_cnt].detail_html = rec_acuity->det_antihypertensive
    ENDIF
    IF (rec_acuity->flag_bsbg = 1)
        SET rec_acuity->score = rec_acuity->score + 2
        SET rec_acuity->reason_cnt = rec_acuity->reason_cnt + 1
        SET stat = ALTERLIST(rec_acuity->reasons, rec_acuity->reason_cnt)
        SET rec_acuity->reasons[rec_acuity->reason_cnt].text = "Uncontrolled bedside blood glucose (> 11.1 mmol/L)"
        SET rec_acuity->reasons[rec_acuity->reason_cnt].points = 2
        SET rec_acuity->reasons[rec_acuity->reason_cnt].detail_html = rec_acuity->det_bsbg
    ENDIF
    IF (rec_acuity->flag_neuraxial = 1)
        SET rec_acuity->score = rec_acuity->score + 1
        SET rec_acuity->reason_cnt = rec_acuity->reason_cnt + 1
        SET stat = ALTERLIST(rec_acuity->reasons, rec_acuity->reason_cnt)
        SET rec_acuity->reasons[rec_acuity->reason_cnt].text = "Medication: Neuraxial/Epidural Infusion"
        SET rec_acuity->reasons[rec_acuity->reason_cnt].points = 1
        SET rec_acuity->reasons[rec_acuity->reason_cnt].detail_html = rec_acuity->det_neuraxial
    ENDIF
    IF (rec_acuity->flag_poly_mod = 1)
        SET rec_acuity->score = rec_acuity->score + 1
        SET rec_acuity->reason_cnt = rec_acuity->reason_cnt + 1
        SET stat = ALTERLIST(rec_acuity->reasons, rec_acuity->reason_cnt)
        SET rec_acuity->reasons[rec_acuity->reason_cnt].text = CONCAT("Moderate Polypharmacy (", TRIM(CNVTSTRING(rec_acuity->poly_count)), " active meds)")
        SET rec_acuity->reasons[rec_acuity->reason_cnt].points = 1
        SET rec_acuity->reasons[rec_acuity->reason_cnt].detail_html = rec_acuity->det_poly
    ENDIF

    IF (rec_acuity->score >= 3)
        SET rec_acuity->color = "Red"
    ELSEIF (rec_acuity->score >= 1)
        SET rec_acuity->color = "Amber"
    ELSE
        SET rec_acuity->color = "Green"
    ENDIF

    SET v_triage_tier = CNVTUPPER(rec_acuity->color)
    IF (rec_acuity->color = "Red")
        SET v_action_plan = "<b>RED (Score 3+):</b> High Risk. Requires clinical pharmacist review and medicines reconciliation within 24 hours."
    ELSEIF (rec_acuity->color = "Amber")
        SET v_action_plan = "<b>AMBER (Score 1-2):</b> Medium Risk. Review during routine ward cover or before discharge."
    ELSE
        SET v_action_plan = "<b>GREEN (Score 0):</b> Low Risk. Review only if requested by medical or midwifery team."
    ENDIF

    SET reply->status.code = "success"
    IF (rec_acuity->reason_cnt > 0)
        SET reply->status.message = "Acuity score calculated."
    ELSE
        SET reply->status.message = "No high-risk triggers detected. Patient remains low acuity."
    ENDIF

    SET reply->meta.reason_count = rec_acuity->reason_cnt
    SET reply->meta.poly_count = rec_acuity->poly_count

    SET reply->acuity.score = rec_acuity->score
    SET reply->acuity.color = rec_acuity->color
    SET reply->acuity.triage_tier = v_triage_tier
    SET reply->acuity.action_plan = v_action_plan
    SET reply->acuity.reason_count = rec_acuity->reason_cnt
    SET reply->acuity.poly_count = rec_acuity->poly_count

    IF (rec_acuity->reason_cnt > 0)
        FOR (x = 1 TO rec_acuity->reason_cnt)
            SET stat = ALTERLIST(reply->reasons, x)
            SET reply->reasons[x].text = rec_acuity->reasons[x].text
            SET reply->reasons[x].points = rec_acuity->reasons[x].points
            SET reply->reasons[x].detail_html = rec_acuity->reasons[x].detail_html
        ENDFOR
    ENDIF

    SET stat = ALTERLIST(reply->ui.css_parts, 3)
    SET reply->ui.css_parts[1].text = BUILD2(
        ".module-acuity{max-width:100%}"
        , ".acuity-wrap{background:#fff}"
        , ".acuity-banner{padding:15px;color:#fff;font-size:22px;font-weight:700;text-align:center;margin:0 0 15px;border-radius:5px}"
        , ".acuity-Red{background-color:#dc3545;border-bottom:4px solid #b02a37}"
        , ".acuity-Amber{background-color:#ffc107;color:#333;border-bottom:4px solid #d39e00}"
        , ".acuity-Green{background-color:#28a745;border-bottom:4px solid #1e7e34}"
        , ".acuity-columns{display:flex;gap:20px;align-items:flex-start;flex-wrap:wrap}"
        , ".acuity-col{min-width:320px}"
        , ".acuity-col-left{flex:1 1 420px}"
        , ".acuity-col-right{flex:1 1 460px}"
        , ".acuity-panel-header{font-size:16px;margin:0 0 10px;padding-bottom:8px;border-bottom:2px solid #eee;color:#0076a8}"
        , ".acuity-ref-note{font-size:11px;color:#666;margin:0 0 8px}"
        , ".acuity-action-plan{margin-top:20px;font-size:12px;color:#666;background:#f9f9f9;padding:10px;border:1px solid #ddd}"
    )
    SET reply->ui.css_parts[2].text = BUILD2(
        ".trigger-item-wrap{background:#f8f9fa;margin-bottom:8px;border-left:4px solid #0076a8;border-radius:3px;overflow:hidden}"
        , ".trigger-header{display:block;width:100%;padding:10px;font-size:14px;cursor:pointer;border:0;background:transparent;text-align:left;color:#333}"
        , ".trigger-header:hover{background:#e2e6ea}"
        , ".trigger-header:focus{outline:2px solid #0076a8;outline-offset:-2px}"
        , ".trigger-details{padding:10px;border-top:1px dashed #ccc;font-size:12px;color:#444;background:#fff;margin-left:10px;border-left:1px solid #ccc}"
        , ".trigger-det-item{padding:3px 0}"
        , ".exp-icon{float:right;font-weight:700;color:#666;font-size:16px;line-height:1}"
        , ".pts-badge{display:inline-block;background:#333;color:#fff;padding:3px 8px;border-radius:12px;font-size:12px;margin-right:10px;font-weight:700}"
        , ".acuity-none{background:#f8f9fa;padding:10px;border-left:4px solid #0076a8;border-radius:3px;font-size:14px;color:#666}"
        , ".ref-table{width:100%;border-collapse:collapse;font-size:13px;margin-top:0;background:#fff;box-shadow:0 1px 3px rgba(0,0,0,.1)}"
        , ".ref-table tr{cursor:help}"
        , ".ref-table th,.ref-table td{border:1px solid #ddd;padding:8px 10px;text-align:left;vertical-align:top}"
    )
    SET reply->ui.css_parts[3].text = BUILD2(
        ".ref-table th{background-color:#f0f4f8;font-weight:700;color:#333}"
        , ".tr-active.red-tier{background-color:#f8d7da !important;border-left:5px solid #dc3545;font-weight:700}"
        , ".tr-active.amber-tier{background-color:#fff3cd !important;border-left:5px solid #ffc107;font-weight:700}"
        , ".tr-disabled{background:#f9f9f9;color:#999}"
        , "@media (max-width:960px){.acuity-columns{display:block}.acuity-col-right{margin-top:20px}}"
    )

    SET v_html_idx = 1
    SET stat = ALTERLIST(reply->ui.html_parts, v_html_idx)
    SET reply->ui.html_parts[v_html_idx].text = BUILD2(
        "<section class='panel module-shell module-acuity'><div class='acuity-wrap'>"
        , "<div class='acuity-banner acuity-", rec_acuity->color, "'>Patient Acuity Score: ", TRIM(CNVTSTRING(rec_acuity->score)), " (Triage Tier: ", v_triage_tier, ")</div>"
        , "<div class='acuity-columns'><div class='acuity-col acuity-col-left'><h3 class='acuity-panel-header'>Patient Specific Triggers</h3>"
    )

    IF (rec_acuity->reason_cnt > 0)
        FOR (x = 1 TO rec_acuity->reason_cnt)
            SET v_html_part = BUILD2(
                "<div class='trigger-item-wrap'>"
                , "<button type='button' class='trigger-header' data-trigger-id='", TRIM(CNVTSTRING(x)), "' aria-expanded='false' aria-controls='trig-det-", TRIM(CNVTSTRING(x)), "'>"
                , "<span class='pts-badge'>+", TRIM(CNVTSTRING(rec_acuity->reasons[x].points)), " Points</span> "
                , rec_acuity->reasons[x].text
                , "<span class='exp-icon' id='trig-icon-", TRIM(CNVTSTRING(x)), "'>+</span></button>"
                , "<div class='trigger-details' id='trig-det-", TRIM(CNVTSTRING(x)), "' hidden>"
                , rec_acuity->reasons[x].detail_html
                , "</div></div>"
            )
            SET v_html_idx = v_html_idx + 1
            SET stat = ALTERLIST(reply->ui.html_parts, v_html_idx)
            SET reply->ui.html_parts[v_html_idx].text = v_html_part
        ENDFOR
    ELSE
        SET v_html_idx = v_html_idx + 1
        SET stat = ALTERLIST(reply->ui.html_parts, v_html_idx)
        SET reply->ui.html_parts[v_html_idx].text = "<div class='acuity-none'>No high-risk triggers detected. Patient remains Low Acuity (Routine Review).</div>"
    ENDIF

    SET v_html_idx = v_html_idx + 1
    SET stat = ALTERLIST(reply->ui.html_parts, v_html_idx)
    SET reply->ui.html_parts[v_html_idx].text = BUILD2(
        "<div class='acuity-action-plan'><b>Triage Action Plan:</b><br/>"
        , v_action_plan
        , "</div></div><div class='acuity-col acuity-col-right'><h3 class='acuity-panel-header'>Scoring Reference Matrix</h3>"
        , "<div class='acuity-ref-note'>Hover over a criteria row to view the exact database fields/strings being evaluated.<br>Criteria based on UKCPA Women's Health Group &amp; ISMP Guidelines. Lab parameters excluded.</div>"
        , "<table class='ref-table'><thead><tr><th width='60%'>Clinical Criteria</th><th width='20%'>Category</th><th width='20%'>Points</th></tr></thead><tbody>"
    )

    SET v_html_idx = v_html_idx + 1
    SET stat = ALTERLIST(reply->ui.html_parts, v_html_idx)
    SET reply->ui.html_parts[v_html_idx].text = CONCAT("<tr class='", IF(rec_acuity->flag_high_alert_iv = 1) "tr-active red-tier" ELSE "" ENDIF, "' title='Continuous IV infusion of high-alert medication (e.g., MgSO4)'><td>Continuous IV infusion of high-alert medication (e.g., MgSO4)</td><td>Medication</td><td>+5</td></tr>")

    SET v_html_idx = v_html_idx + 1
    SET stat = ALTERLIST(reply->ui.html_parts, v_html_idx)
    SET reply->ui.html_parts[v_html_idx].text = CONCAT("<tr class='", IF(rec_acuity->flag_imews = 1) "tr-active red-tier" ELSE "" ENDIF, "' title='Physiological Instability (IMEWS Score &ge;2)'><td>Physiological Instability (IMEWS Score &ge;2)</td><td>Physiology</td><td>+3</td></tr>")

    SET v_html_idx = v_html_idx + 1
    SET stat = ALTERLIST(reply->ui.html_parts, v_html_idx)
    SET reply->ui.html_parts[v_html_idx].text = CONCAT("<tr class='", IF(rec_acuity->flag_ebl = 1 OR rec_acuity->flag_transfusion = 1) "tr-active red-tier" ELSE "" ENDIF, "' title='Checks CLINICAL_EVENT for last 7 days. Looks for Blood Volume Infused (15071366) OR Delivery/Intraop/Total EBL > 1000ml.'><td>Massive Haemorrhage / Blood Transfusion</td><td>Clinical Event</td><td>+3</td></tr>")

    SET v_html_idx = v_html_idx + 1
    SET stat = ALTERLIST(reply->ui.html_parts, v_html_idx)
    SET reply->ui.html_parts[v_html_idx].text = CONCAT("<tr class='", IF(rec_acuity->flag_preeclampsia = 1 OR rec_acuity->flag_dvt = 1 OR rec_acuity->flag_epilepsy = 1) "tr-active red-tier" ELSE "" ENDIF, "' title='Checks both ACTIVE PROBLEM and ACTIVE DIAGNOSIS lists for nomenclature strings containing: PRE-ECLAMPSIA, DVT, PULMONARY EMBOLISM, or EPILEPSY/SEIZURE.'><td>High Risk Diagnosis (Pre-eclampsia, VTE, Epilepsy)</td><td>Problem/Diagnosis</td><td>+3</td></tr>")

    SET v_html_idx = v_html_idx + 1
    SET stat = ALTERLIST(reply->ui.html_parts, v_html_idx)
    SET reply->ui.html_parts[v_html_idx].text = CONCAT("<tr class='", IF(rec_acuity->flag_insulin = 1 OR rec_acuity->flag_antiepileptic = 1) "tr-active red-tier" ELSE "" ENDIF, "' title='Checks active inpatient pharmacy orders for mnemonics containing: INSULIN, LEVETIRACETAM, LAMOTRIGINE, VALPROATE, or CARBAMAZEPINE.'><td>High Alert Med (Insulin, Antiepileptics)</td><td>Medication</td><td>+3</td></tr>")

    SET v_html_idx = v_html_idx + 1
    SET stat = ALTERLIST(reply->ui.html_parts, v_html_idx)
    SET reply->ui.html_parts[v_html_idx].text = CONCAT("<tr class='", IF(rec_acuity->flag_poly_severe = 1) "tr-active red-tier" ELSE "" ENDIF, "' title='Checks if patient has greater than or equal to 10 active inpatient pharmacy orders. (Excludes standard IV fluids and Care Plan PRNs)'><td>Severe Polypharmacy (&ge;10 active meds)</td><td>Medication</td><td>+3</td></tr>")

    SET v_html_idx = v_html_idx + 1
    SET stat = ALTERLIST(reply->ui.html_parts, v_html_idx)
    SET reply->ui.html_parts[v_html_idx].text = CONCAT("<tr class='", IF(rec_acuity->flag_anticoag = 1 OR rec_acuity->flag_antihypertensive = 1) "tr-active amber-tier" ELSE "" ENDIF, "' title='Checks active inpatient pharmacy orders for mnemonics containing: TINZAPARIN, HEPARIN, ENOXAPARIN, LABETALOL, NIFEDIPINE, or METHYLDOPA.'><td>Targeted Med (Anticoagulant, Antihypertensive)</td><td>Medication</td><td>+2</td></tr>")

    SET v_html_idx = v_html_idx + 1
    SET stat = ALTERLIST(reply->ui.html_parts, v_html_idx)
    SET reply->ui.html_parts[v_html_idx].text = CONCAT("<tr class='", IF(rec_acuity->flag_bsbg = 1) "tr-active amber-tier" ELSE "" ENDIF, "' title='Uncontrolled bedside blood glucose (> 11.1 mmol/L)'><td>Uncontrolled bedside blood glucose (> 11.1 mmol/L)</td><td>Laboratory</td><td>+2</td></tr>")

    SET v_html_idx = v_html_idx + 1
    SET stat = ALTERLIST(reply->ui.html_parts, v_html_idx)
    SET reply->ui.html_parts[v_html_idx].text = CONCAT("<tr class='", IF(rec_acuity->flag_poly_mod = 1) "tr-active amber-tier" ELSE "" ENDIF, "' title='Checks if patient has between 5 and 9 active inpatient pharmacy orders. (Excludes standard IV fluids and Care Plan PRNs)'><td>Moderate Polypharmacy (5-9 active meds)</td><td>Medication</td><td>+1</td></tr>")

    SET v_html_idx = v_html_idx + 1
    SET stat = ALTERLIST(reply->ui.html_parts, v_html_idx)
    SET reply->ui.html_parts[v_html_idx].text = CONCAT("<tr class='", IF(rec_acuity->flag_neuraxial = 1) "tr-active amber-tier" ELSE "" ENDIF, "' title='Checks active inpatient pharmacy orders for mnemonics containing: BUPIVACAINE or LEVOBUPIVACAINE.'><td>Neuraxial / Epidural Infusion Active</td><td>Medication</td><td>+1</td></tr>")

    SET v_html_idx = v_html_idx + 1
    SET stat = ALTERLIST(reply->ui.html_parts, v_html_idx)
    SET reply->ui.html_parts[v_html_idx].text = "<tr class='tr-disabled'><td>Postpartum Oxytocin Infusion (PPH Management) - Temporarily Disabled</td><td>Medication</td><td>+0</td></tr>"

    SET v_html_idx = v_html_idx + 1
    SET stat = ALTERLIST(reply->ui.html_parts, v_html_idx)
    SET reply->ui.html_parts[v_html_idx].text = "</tbody></table></div></div></div></section>"
ENDIF

SET _memory_reply_string = CNVTRECTOJSON(reply)
END GO
