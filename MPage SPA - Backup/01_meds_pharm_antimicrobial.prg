DROP PROGRAM 01_meds_pharm_antimicrobial:group1 GO
CREATE PROGRAM 01_meds_pharm_antimicrobial:group1

PROMPT "Output to File/Printer/MINE" = "MINE", "Patient_ID" = 0, "Days Lookback" = 200
WITH OUTDEV, PAT_PersonId, LOOKBACK

DECLARE v_font_size      = vc WITH NOCONSTANT("13px")
DECLARE v_med_font_size  = vc WITH NOCONSTANT("14px")
DECLARE v_mrn            = vc WITH NOCONSTANT("")
DECLARE v_name           = vc WITH NOCONSTANT("")
DECLARE v_admit_dt       = vc WITH NOCONSTANT("")
DECLARE v_los            = vc WITH NOCONSTANT("")
DECLARE v_lookback       = vc WITH NOCONSTANT("")
DECLARE v_effective_lookback = i4 WITH NOCONSTANT(200)
DECLARE v_min_dt         = dq8 WITH NOCONSTANT(0)
DECLARE v_max_dt         = dq8 WITH NOCONSTANT(0)
DECLARE v_first          = i2 WITH NOCONSTANT(1)
DECLARE v_days           = i4 WITH NOCONSTANT(0)
DECLARE v_curr_med       = vc WITH NOCONSTANT("")
DECLARE v_dates_kv       = vc WITH NOCONSTANT(""), MAXLEN=65534
DECLARE v_details_kv     = vc WITH NOCONSTANT(""), MAXLEN=65534
DECLARE v_cnt_day        = i4 WITH NOCONSTANT(0)
DECLARE v_i              = i4 WITH NOCONSTANT(0)
DECLARE v_key8           = vc WITH NOCONSTANT("")
DECLARE v_count_str      = vc WITH NOCONSTANT("")
DECLARE v_count_i        = i4 WITH NOCONSTANT(0)
DECLARE v_title          = vc WITH NOCONSTANT(""), MAXLEN=2000
DECLARE v_med_dot_total  = i4 WITH NOCONSTANT(0)
DECLARE v_med_dose_total = i4 WITH NOCONSTANT(0)
DECLARE v_doses          = i4 WITH NOCONSTANT(0)
DECLARE v_row_cnt        = i4 WITH NOCONSTANT(0)
DECLARE v_all_days_list  = vc WITH NOCONSTANT(""), MAXLEN=65534
DECLARE v_grand_total_dot   = i4 WITH NOCONSTANT(0)
DECLARE v_grand_total_doses = i4 WITH NOCONSTANT(0)
DECLARE v_e              = i4 WITH NOCONSTANT(0)
DECLARE v_s_idx          = i4 WITH NOCONSTANT(0)
DECLARE v_e_idx          = i4 WITH NOCONSTANT(0)
DECLARE v_t              = i4 WITH NOCONSTANT(0)
DECLARE v_max_track      = i4 WITH NOCONSTANT(0)
DECLARE v_assigned       = i2 WITH NOCONSTANT(0)
DECLARE v_cell_class     = vc WITH NOCONSTANT(""), MAXLEN=100
DECLARE v_cell_title     = vc WITH NOCONSTANT(""), MAXLEN=255
DECLARE v_enc_label      = vc WITH NOCONSTANT(""), MAXLEN=2000
DECLARE v_color_idx      = i4 WITH NOCONSTANT(0)
DECLARE track_ends[50]   = i4
DECLARE v_findpos        = i4 WITH NOCONSTANT(0)
DECLARE v_after          = vc WITH NOCONSTANT(""), MAXLEN=65534
DECLARE v_endpos         = i4 WITH NOCONSTANT(0)
DECLARE v_detail_str     = vc WITH NOCONSTANT("")
DECLARE v_pipe_pos       = i4 WITH NOCONSTANT(0)
DECLARE v_indication     = vc WITH NOCONSTANT(""), MAXLEN=255
DECLARE v_discontinue_rsn = vc WITH NOCONSTANT(""), MAXLEN=255
DECLARE v_drug           = vc WITH NOCONSTANT("")
DECLARE v_dose           = f8 WITH NOCONSTANT(0.0)
DECLARE v_unit           = vc WITH NOCONSTANT("")
DECLARE v_ind            = vc WITH NOCONSTANT("")
DECLARE v_start          = vc WITH NOCONSTANT("")
DECLARE v_stat           = vc WITH NOCONSTANT("")
DECLARE v_sdt            = vc WITH NOCONSTANT("")
DECLARE v_oid            = vc WITH NOCONSTANT("")
DECLARE v_dot            = i4 WITH NOCONSTANT(0)
DECLARE v_low_dt         = dq8 WITH NOCONSTANT(NULL)
DECLARE v_high_now_dt    = dq8 WITH NOCONSTANT(NULL)
DECLARE v_begin_dt_str   = vc WITH NOCONSTANT("")
DECLARE v_end_dt_str     = vc WITH NOCONSTANT("")
DECLARE v_today          = dq8 WITH NOCONSTANT(0)
DECLARE v_local_dt       = dq8 WITH NOCONSTANT(0)
DECLARE v_dose_str       = vc WITH NOCONSTANT("")
DECLARE v_actual_dose_str = vc WITH NOCONSTANT("")
DECLARE v_s              = vc WITH NOCONSTANT("")
DECLARE v_v              = vc WITH NOCONSTANT("")
DECLARE v_order_src      = vc WITH NOCONSTANT("")
DECLARE v_disp           = vc WITH NOCONSTANT("")
DECLARE v_fin            = vc WITH NOCONSTANT("")
DECLARE v_encntr_id      = vc WITH NOCONSTANT("")
DECLARE v_pc_cnt         = i4 WITH NOCONSTANT(0)
DECLARE v_sn_cnt         = i4 WITH NOCONSTANT(0)
DECLARE stat             = i4 WITH NOCONSTANT(0)
DECLARE v_track_idx      = i4 WITH NOCONSTANT(0)
DECLARE v_day_idx        = i4 WITH NOCONSTANT(0)
DECLARE v_enc_idx        = i4 WITH NOCONSTANT(0)
DECLARE v_track_fin_list = vc WITH NOCONSTANT(""), MAXLEN=2000
DECLARE v_new_month      = i2 WITH NOCONSTANT(0)
DECLARE v_status_msg     = vc WITH NOCONSTANT(""), MAXLEN=255
DECLARE v_target_dose    = vc WITH NOCONSTANT(""), MAXLEN=255
DECLARE v_order_detail   = vc WITH NOCONSTANT(""), MAXLEN=255
DECLARE v_args           = vc WITH NOCONSTANT(""), MAXLEN=255

FREE RECORD admin_rec
RECORD admin_rec (
  1 cnt = i4
  1 qual[*]
    2 admin_dt_tm = dq8
    2 order_id    = f8
    2 admin_id    = f8
    2 src         = vc
)

FREE RECORD enc_rec
RECORD enc_rec (
  1 cnt = i4
  1 qual[*]
    2 encntr_id = f8
    2 fin       = vc
    2 arrive_dt = dq8
    2 disch_dt  = dq8
    2 start_idx = i4
    2 end_idx   = i4
    2 track     = i4
)

FREE RECORD enc_sort_rec
RECORD enc_sort_rec (
  1 cnt = i4
  1 qual[*]
    2 orig_idx  = i4
    2 start_idx = i4
    2 end_idx   = i4
)

RECORD reply (
  1 status
    2 code    = vc
    2 message = vc
  1 meta
    2 module              = vc
    2 title               = vc
    2 patient_id          = f8
    2 encntr_id           = f8
    2 mrn                 = vc
    2 patient_name        = vc
    2 admit_date          = vc
    2 los_days            = vc
    2 lookback_days       = i4
    2 begin_date          = vc
    2 end_date            = vc
    2 chart_start_date    = vc
    2 chart_end_date      = vc
    2 day_count           = i4
    2 powerchart_admins   = i4
    2 anesthesia_admins   = i4
    2 medication_rows     = i4
    2 order_rows          = i4
    2 encounter_count     = i4
    2 track_count         = i4
    2 grand_total_dot     = i4
    2 grand_total_doses   = i4
  1 headers[*]
    2 day_key      = vc
    2 day_label    = vc
    2 month_label  = vc
    2 iso_date     = vc
    2 new_month    = i2
  1 summary_days[*]
    2 day_key          = vc
    2 antimicrobial_ind = i2
  1 timeline[*]
    2 medication_name = vc
    2 doses_total     = i4
    2 dot_total       = i4
    2 days[*]
      3 day_key             = vc
      3 admin_count         = i4
      3 on_ind              = i2
      3 title               = vc
      3 indication          = vc
      3 discontinue_reason  = vc
  1 encounter_tracks[*]
    2 track_label = vc
    2 track_no    = i4
    2 encounters[*]
      3 encntr_id    = f8
      3 fin          = vc
      3 arrive_date  = vc
      3 discharge_date = vc
      3 start_idx    = i4
      3 end_idx      = i4
      3 color_class  = vc
      3 applink_app  = vc
      3 applink_args = vc
    2 days[*]
      3 day_key      = vc
      3 cell_class   = vc
      3 title        = vc
  1 order_details[*]
    2 medication_name  = vc
    2 source           = vc
    2 doses_total      = i4
    2 dot_total        = i4
    2 target_dose      = vc
    2 actual_dose      = vc
    2 order_detail     = vc
    2 indication       = vc
    2 start_date       = vc
    2 latest_status    = vc
    2 status_date      = vc
    2 order_id         = vc
    2 fin              = vc
    2 encntr_id        = vc
    2 applink_app      = vc
    2 applink_args     = vc
)

SET reply->status.code = "success"
SET reply->status.message = "Antimicrobial data loaded."
SET reply->meta.module = "01_meds_pharm_antimicrobial:group1"
SET reply->meta.title = "Antimicrobial"
SET reply->meta.patient_id = CNVTREAL($PAT_PersonId)
SET reply->meta.encntr_id = 0
SET v_effective_lookback = CNVTINT($LOOKBACK)
IF (v_effective_lookback <= 0 OR v_effective_lookback > 10000)
  SET v_effective_lookback = 180
ENDIF
SET reply->meta.lookback_days = v_effective_lookback

SELECT INTO "nl:"
FROM PERSON P, CLINICAL_EVENT CE, MED_ADMIN_EVENT M, ORDERS O,
     CODE_VALUE_EVENT_R CR, ORDER_CATALOG OC,
     ORDER_CATALOG_SYNONYM OCS, ORDER_ENTRY_FORMAT OE
PLAN P WHERE P.PERSON_ID = $PAT_PersonId
JOIN CE WHERE CE.PERSON_ID = P.PERSON_ID
  AND CE.PERFORMED_DT_TM BETWEEN CNVTDATETIME(CURDATE-v_effective_lookback,0) AND CNVTDATETIME(CURDATE,235959)
JOIN M WHERE M.EVENT_ID = CE.EVENT_ID
  AND M.EVENT_TYPE_CD = VALUE(UAR_GET_CODE_BY("MEANING",4000040,"TASKCOMPLETE"))
JOIN O WHERE O.ORDER_ID = M.TEMPLATE_ORDER_ID
JOIN CR WHERE CR.EVENT_CD = CE.EVENT_CD
JOIN OC WHERE OC.CATALOG_CD = CR.PARENT_CD AND OC.CATALOG_TYPE_CD = 2516
JOIN OCS WHERE OCS.CATALOG_CD = OC.CATALOG_CD
JOIN OE WHERE OE.OE_FORMAT_ID = OCS.OE_FORMAT_ID
  AND OE.OE_FORMAT_ID IN (14497910, 14498121)
ORDER BY M.EVENT_ID
HEAD REPORT
  admin_rec->cnt = 0
HEAD M.EVENT_ID
  admin_rec->cnt = admin_rec->cnt + 1
  CALL ALTERLIST(admin_rec->qual, admin_rec->cnt)
  admin_rec->qual[admin_rec->cnt].admin_dt_tm = CE.EVENT_END_DT_TM
  admin_rec->qual[admin_rec->cnt].order_id    = O.ORDER_ID
  admin_rec->qual[admin_rec->cnt].admin_id    = CE.EVENT_ID
  admin_rec->qual[admin_rec->cnt].src         = "PC"
WITH NOCOUNTER

SELECT INTO "nl:"
FROM PERSON P, ORDERS O, SA_MEDICATION_ADMIN SMA, SA_MED_ADMIN_ITEM SMAI,
     ORDER_CATALOG_SYNONYM OCS, ORDER_ENTRY_FORMAT OE
PLAN P WHERE P.PERSON_ID = $PAT_PersonId
JOIN O WHERE O.PERSON_ID = P.PERSON_ID
JOIN SMA WHERE SMA.ORDER_ID = O.ORDER_ID
  AND SMA.ACTIVE_IND = 1
JOIN SMAI WHERE SMAI.SA_MEDICATION_ADMIN_ID = SMA.SA_MEDICATION_ADMIN_ID
  AND SMAI.ACTIVE_IND = 1
  AND SMAI.ADMIN_START_DT_TM >= CNVTDATETIMEUTC(CNVTDATETIME(CURDATE-v_effective_lookback,0))
JOIN OCS WHERE OCS.SYNONYM_ID = O.SYNONYM_ID
JOIN OE WHERE OE.OE_FORMAT_ID = OCS.OE_FORMAT_ID
  AND OE.OE_FORMAT_ID IN (14497910, 14498121)
  AND OE.CATALOG_TYPE_CD = 2516.00
ORDER BY SMAI.SA_MED_ADMIN_ITEM_ID
HEAD SMAI.SA_MED_ADMIN_ITEM_ID
  v_local_dt = CNVTDATETIMEUTC(SMAI.ADMIN_START_DT_TM)
  admin_rec->cnt = admin_rec->cnt + 1
  CALL ALTERLIST(admin_rec->qual, admin_rec->cnt)
  admin_rec->qual[admin_rec->cnt].admin_dt_tm = v_local_dt
  admin_rec->qual[admin_rec->cnt].order_id    = O.ORDER_ID
  admin_rec->qual[admin_rec->cnt].admin_id    = SMAI.SA_MED_ADMIN_ITEM_ID
  admin_rec->qual[admin_rec->cnt].src         = "SN"
WITH NOCOUNTER

SELECT INTO "nl:"
FROM PERSON P, PERSON_ALIAS PA, ENCOUNTER E
PLAN P WHERE P.PERSON_ID = $PAT_PersonId
JOIN PA WHERE PA.PERSON_ID = P.PERSON_ID AND PA.PERSON_ALIAS_TYPE_CD = 10.00
JOIN E WHERE E.PERSON_ID = P.PERSON_ID
ORDER BY E.ARRIVE_DT_TM DESC
HEAD REPORT
  v_first = 1
  v_mrn = PA.ALIAS
  v_name = P.NAME_FULL_FORMATTED
  v_admit_dt = FORMAT(E.ARRIVE_DT_TM,"DD/MM/YYYY;;d")
  v_low_dt = CNVTDATETIME(CNVTDATE(E.ARRIVE_DT_TM),0)
  v_high_now_dt = CNVTDATETIME(CURDATE,0)
  v_today = CNVTDATE(CURDATE)
  v_los = CNVTSTRING((DATETIMEDIFF(v_high_now_dt,v_low_dt,7))+1)
  v_lookback = CNVTSTRING(v_effective_lookback)
  v_begin_dt_str = FORMAT((CURDATE-v_effective_lookback),"DD/MM/YYYY;;d")
  v_end_dt_str = FORMAT(CURDATE,"DD/MM/YYYY;;d")
WITH NOCOUNTER

IF (admin_rec->cnt > 0)
  SET v_first = 0
  SET v_min_dt = CNVTDATE(admin_rec->qual[1].admin_dt_tm)
  SET v_max_dt = CNVTDATE(admin_rec->qual[1].admin_dt_tm)
  SET v_i = 1
  WHILE (v_i <= admin_rec->cnt)
    SET v_local_dt = CNVTDATE(admin_rec->qual[v_i].admin_dt_tm)
    IF (v_local_dt < v_min_dt)
      SET v_min_dt = v_local_dt
    ENDIF
    IF (v_local_dt > v_max_dt)
      SET v_max_dt = v_local_dt
    ENDIF
    SET v_i = v_i + 1
  ENDWHILE
  IF (v_max_dt < v_today)
    SET v_max_dt = v_today
  ENDIF

  SET v_pc_cnt = 0
  SET v_sn_cnt = 0
  SET v_i = 1
  WHILE (v_i <= admin_rec->cnt)
    IF (admin_rec->qual[v_i].src = "PC")
      SET v_pc_cnt = v_pc_cnt + 1
    ELSEIF (admin_rec->qual[v_i].src = "SN")
      SET v_sn_cnt = v_sn_cnt + 1
    ENDIF
    SET v_i = v_i + 1
  ENDWHILE
ELSE
  SET v_days = 0
ENDIF

IF (v_first = 0)
  SET v_days = (DATETIMEDIFF(v_max_dt, v_min_dt, 7)) + 1
  SET reply->meta.chart_start_date = FORMAT(v_min_dt, "DD/MM/YYYY;;d")
  SET reply->meta.chart_end_date = FORMAT(v_max_dt, "DD/MM/YYYY;;d")
ELSE
  SET reply->status.message = "No antimicrobial administrations found in the selected window."
ENDIF

SET reply->meta.mrn = v_mrn
SET reply->meta.patient_name = v_name
SET reply->meta.admit_date = v_admit_dt
SET reply->meta.los_days = v_los
SET reply->meta.begin_date = v_begin_dt_str
SET reply->meta.end_date = v_end_dt_str
SET reply->meta.day_count = v_days
SET reply->meta.powerchart_admins = v_pc_cnt
SET reply->meta.anesthesia_admins = v_sn_cnt
SET reply->meta.medication_rows = 0
SET reply->meta.order_rows = 0
SET reply->meta.encounter_count = 0
SET reply->meta.track_count = 0
SET reply->meta.grand_total_dot = 0
SET reply->meta.grand_total_doses = 0

IF (v_days > 0)
  SET v_i = 0
  WHILE (v_i < v_days)
    SET v_day_idx = v_i + 1
    SET stat = ALTERLIST(reply->headers, v_day_idx)
    SET v_key8 = FORMAT(v_min_dt + v_i, "YYYYMMDD;;D")
    IF (v_i = 0 OR FORMAT(v_min_dt + v_i,"MM;;D") != FORMAT(v_min_dt + v_i - 1,"MM;;D"))
      SET v_new_month = 1
    ELSE
      SET v_new_month = 0
    ENDIF
    SET reply->headers[v_day_idx].day_key = v_key8
    SET reply->headers[v_day_idx].day_label = FORMAT(v_min_dt + v_i, "DD;;D")
    IF (v_new_month = 1)
      SET reply->headers[v_day_idx].month_label = FORMAT(v_min_dt + v_i, "MMM;;D")
    ELSE
      SET reply->headers[v_day_idx].month_label = ""
    ENDIF
    SET reply->headers[v_day_idx].iso_date = FORMAT(v_min_dt + v_i, "YYYY-MM-DD;;D")
    SET reply->headers[v_day_idx].new_month = v_new_month
    SET v_i = v_i + 1
  ENDWHILE
ENDIF

IF (admin_rec->cnt > 0)
SELECT INTO "nl:"
  med_name           = TRIM(OC.PRIMARY_MNEMONIC)
, mdy                = FORMAT(admin_rec->qual[d.seq].admin_dt_tm, "YYYYMMDD;;D")
, indication         = SUBSTRING(1,60,TRIM(OD_INDICATION.OE_FIELD_DISPLAY_VALUE))
, discontinue_reason = SUBSTRING(1,60,TRIM(OD_DCREASON.OE_FIELD_DISPLAY_VALUE))
, src_id             = admin_rec->qual[d.seq].admin_id
, admin_src          = admin_rec->qual[d.seq].src
FROM
  (DUMMYT D WITH SEQ = admin_rec->cnt)
, ORDERS O
, ORDER_CATALOG OC
, ORDER_DETAIL OD_INDICATION
, ORDER_DETAIL OD_DCREASON
PLAN D
JOIN O WHERE O.ORDER_ID = admin_rec->qual[d.seq].order_id
JOIN OC WHERE OC.CATALOG_CD = O.CATALOG_CD
JOIN OD_INDICATION WHERE OD_INDICATION.ORDER_ID = OUTERJOIN(O.ORDER_ID)
  AND OD_INDICATION.OE_FIELD_MEANING = OUTERJOIN("INDICATION")
JOIN OD_DCREASON WHERE OD_DCREASON.ORDER_ID = OUTERJOIN(O.ORDER_ID)
  AND OD_DCREASON.OE_FIELD_MEANING = OUTERJOIN("DCREASON")
ORDER BY CNVTUPPER(TRIM(OC.PRIMARY_MNEMONIC)), MDY, SRC_ID

HEAD REPORT
  v_curr_med = ""
  v_dates_kv = ""
  v_details_kv = ""
  v_all_days_list = ""
  v_row_cnt = 0
  v_grand_total_dot = 0
  v_grand_total_doses = 0

HEAD med_name
  v_curr_med = med_name
  v_dates_kv = ""
  v_details_kv = ""
  v_med_dot_total = 0
  v_med_dose_total = 0

HEAD mdy
  v_cnt_day = 0

HEAD src_id
  v_cnt_day = v_cnt_day + 1
  v_med_dose_total = v_med_dose_total + 1

FOOT mdy
  v_dates_kv = CONCAT(v_dates_kv, "~", mdy, ":", CNVTSTRING(v_cnt_day), "~")
  v_details_kv = CONCAT(v_details_kv, "~", mdy, ":", indication, "|", discontinue_reason, "~")
  v_med_dot_total = v_med_dot_total + 1
  IF (FINDSTRING(CONCAT("~", mdy, "~"), v_all_days_list) = 0)
    v_all_days_list = CONCAT(v_all_days_list, "~", mdy, "~")
  ENDIF

FOOT med_name
  IF (v_days > 0)
    reply->meta.medication_rows = reply->meta.medication_rows + 1
    v_grand_total_dot = v_grand_total_dot + v_med_dot_total
    v_grand_total_doses = v_grand_total_doses + v_med_dose_total
    stat = ALTERLIST(reply->timeline, reply->meta.medication_rows)
    reply->timeline[reply->meta.medication_rows].medication_name = v_curr_med
    reply->timeline[reply->meta.medication_rows].doses_total = v_med_dose_total
    reply->timeline[reply->meta.medication_rows].dot_total = v_med_dot_total

    v_i = 0
    WHILE (v_i < v_days)
      v_day_idx = v_i + 1
      stat = ALTERLIST(reply->timeline[reply->meta.medication_rows].days, v_day_idx)
      v_key8 = FORMAT(v_min_dt + v_i, "YYYYMMDD;;D")
      v_findpos = FINDSTRING(CONCAT("~", v_key8, ":"), v_dates_kv)
      IF (v_findpos > 0)
        v_after = SUBSTRING(v_findpos + 10, TEXTLEN(v_dates_kv) - (v_findpos + 9), v_dates_kv)
        v_endpos = FINDSTRING("~", v_after)
        IF (v_endpos > 0)
          v_count_str = SUBSTRING(1, v_endpos - 1, v_after)
        ELSE
          v_count_str = v_after
        ENDIF
      ELSE
        v_count_str = ""
      ENDIF
      v_count_i = CNVTINT(v_count_str)

      v_indication = ""
      v_discontinue_rsn = ""
      v_findpos = FINDSTRING(CONCAT("~", v_key8, ":"), v_details_kv)
      IF (v_findpos > 0)
        v_after = SUBSTRING(v_findpos + 10, TEXTLEN(v_details_kv) - (v_findpos + 9), v_details_kv)
        v_endpos = FINDSTRING("~", v_after)
        v_detail_str = ""
        IF (v_endpos > 0)
          v_detail_str = SUBSTRING(1, v_endpos - 1, v_after)
        ELSE
          v_detail_str = v_after
        ENDIF
        v_pipe_pos = FINDSTRING("|", v_detail_str)
        IF (v_pipe_pos > 0)
          v_indication = SUBSTRING(1, v_pipe_pos - 1, v_detail_str)
          v_discontinue_rsn = SUBSTRING(v_pipe_pos + 1, TEXTLEN(v_detail_str) - v_pipe_pos, v_detail_str)
        ELSE
          v_indication = v_detail_str
        ENDIF
      ENDIF

      IF (v_count_i > 0)
        v_title = CONCAT(v_curr_med, " - ", FORMAT(v_min_dt + v_i,"DD/MM/YYYY;;D"),
          " / ", v_count_str,
          IF(v_count_i = 1) " admin" ELSE " admins" ENDIF,
          "&#10;Indication: ", v_indication,
          "&#10;Discontinue Reason: ", v_discontinue_rsn)
      ELSE
        v_title = FORMAT(v_min_dt + v_i,"DD/MM/YYYY;;D")
      ENDIF

      reply->timeline[reply->meta.medication_rows].days[v_day_idx].day_key = v_key8
      reply->timeline[reply->meta.medication_rows].days[v_day_idx].admin_count = v_count_i
      IF (v_count_i > 0)
        reply->timeline[reply->meta.medication_rows].days[v_day_idx].on_ind = 1
      ELSE
        reply->timeline[reply->meta.medication_rows].days[v_day_idx].on_ind = 0
      ENDIF
      reply->timeline[reply->meta.medication_rows].days[v_day_idx].title = v_title
      reply->timeline[reply->meta.medication_rows].days[v_day_idx].indication = v_indication
      reply->timeline[reply->meta.medication_rows].days[v_day_idx].discontinue_reason = v_discontinue_rsn
      v_i = v_i + 1
    ENDWHILE
  ENDIF

FOOT REPORT
  IF (v_days > 0)
    v_i = 0
    WHILE (v_i < v_days)
      v_day_idx = v_i + 1
      stat = ALTERLIST(reply->summary_days, v_day_idx)
      v_key8 = FORMAT(v_min_dt + v_i, "YYYYMMDD;;D")
      reply->summary_days[v_day_idx].day_key = v_key8
      IF (FINDSTRING(CONCAT("~", v_key8, "~"), v_all_days_list) > 0)
        reply->summary_days[v_day_idx].antimicrobial_ind = 1
      ELSE
        reply->summary_days[v_day_idx].antimicrobial_ind = 0
      ENDIF
      v_i = v_i + 1
    ENDWHILE
  ENDIF
WITH NOCOUNTER
ENDIF

SET reply->meta.grand_total_dot = v_grand_total_dot
SET reply->meta.grand_total_doses = v_grand_total_doses

IF (admin_rec->cnt > 0 AND v_days > 0)
  SELECT INTO "nl:"
    O.ENCNTR_ID
  FROM (DUMMYT D WITH SEQ = admin_rec->cnt)
    , ORDERS O
    , ENCOUNTER E
    , ENCNTR_ALIAS EA
  PLAN D
  JOIN O WHERE O.ORDER_ID = admin_rec->qual[d.seq].order_id
  JOIN E WHERE E.ENCNTR_ID = O.ENCNTR_ID
  JOIN EA WHERE EA.ENCNTR_ID = OUTERJOIN(O.ENCNTR_ID)
    AND EA.ENCNTR_ALIAS_TYPE_CD = OUTERJOIN(1077.00)
    AND EA.ACTIVE_IND = OUTERJOIN(1)
  ORDER BY O.ENCNTR_ID
  HEAD REPORT
    enc_rec->cnt = 0
  HEAD O.ENCNTR_ID
    enc_rec->cnt = enc_rec->cnt + 1
    CALL ALTERLIST(enc_rec->qual, enc_rec->cnt)
    enc_rec->qual[enc_rec->cnt].encntr_id = O.ENCNTR_ID
    enc_rec->qual[enc_rec->cnt].fin       = TRIM(EA.ALIAS)
    enc_rec->qual[enc_rec->cnt].arrive_dt = E.ARRIVE_DT_TM
    enc_rec->qual[enc_rec->cnt].disch_dt  = E.DISCH_DT_TM
  WITH NOCOUNTER

  IF (enc_rec->cnt > 0)
    FOR (v_e = 1 TO enc_rec->cnt)
      IF (enc_rec->qual[v_e].arrive_dt = NULL OR enc_rec->qual[v_e].arrive_dt = 0)
        SET v_s_idx = 0
      ELSE
        SET v_s_idx = DATETIMEDIFF(enc_rec->qual[v_e].arrive_dt, v_min_dt, 7)
        IF (v_s_idx < 0)
          SET v_s_idx = 0
        ENDIF
        IF (v_s_idx >= v_days)
          SET v_s_idx = v_days - 1
        ENDIF
      ENDIF

      IF (enc_rec->qual[v_e].disch_dt = NULL OR enc_rec->qual[v_e].disch_dt = 0)
        SET v_e_idx = v_days - 1
      ELSE
        SET v_e_idx = DATETIMEDIFF(enc_rec->qual[v_e].disch_dt, v_min_dt, 7)
        IF (v_e_idx < v_s_idx)
          SET v_e_idx = v_s_idx
        ENDIF
        IF (v_e_idx >= v_days)
          SET v_e_idx = v_days - 1
        ENDIF
      ENDIF

      SET enc_rec->qual[v_e].start_idx = v_s_idx
      SET enc_rec->qual[v_e].end_idx = v_e_idx
    ENDFOR
  ENDIF

  SELECT INTO "nl:"
    s_idx = enc_rec->qual[d.seq].start_idx
  FROM (DUMMYT D WITH SEQ = enc_rec->cnt)
  ORDER BY s_idx, d.seq
  HEAD REPORT
    enc_sort_rec->cnt = 0
  DETAIL
    enc_sort_rec->cnt = enc_sort_rec->cnt + 1
    CALL ALTERLIST(enc_sort_rec->qual, enc_sort_rec->cnt)
    enc_sort_rec->qual[enc_sort_rec->cnt].orig_idx = d.seq
    enc_sort_rec->qual[enc_sort_rec->cnt].start_idx = enc_rec->qual[d.seq].start_idx
    enc_sort_rec->qual[enc_sort_rec->cnt].end_idx = enc_rec->qual[d.seq].end_idx
  WITH NOCOUNTER

  FOR (v_t = 1 TO 50)
    SET track_ends[v_t] = -1
  ENDFOR
  SET v_max_track = 0
  IF (enc_sort_rec->cnt > 0)
    FOR (v_e = 1 TO enc_sort_rec->cnt)
      SET v_s_idx = enc_sort_rec->qual[v_e].start_idx
      SET v_e_idx = enc_sort_rec->qual[v_e].end_idx
      SET v_assigned = 0
      SET v_t = 1
      WHILE (v_t <= 50 AND v_assigned = 0)
        IF (track_ends[v_t] <= v_s_idx)
          SET enc_rec->qual[enc_sort_rec->qual[v_e].orig_idx].track = v_t
          SET track_ends[v_t] = v_e_idx
          IF (v_t > v_max_track)
            SET v_max_track = v_t
          ENDIF
          SET v_assigned = 1
        ENDIF
        SET v_t = v_t + 1
      ENDWHILE
    ENDFOR
  ENDIF

  SET reply->meta.encounter_count = enc_rec->cnt
  SET reply->meta.track_count = v_max_track

  IF (v_max_track > 0)
    FOR (v_t = 1 TO v_max_track)
      SET v_track_idx = v_t
      SET stat = ALTERLIST(reply->encounter_tracks, v_track_idx)
      SET reply->encounter_tracks[v_track_idx].track_no = v_t
      SET v_track_fin_list = ""
      SET v_enc_idx = 0
      FOR (v_e = 1 TO enc_rec->cnt)
        IF (enc_rec->qual[v_e].track = v_t)
          IF (v_track_fin_list != "")
            SET v_track_fin_list = CONCAT(v_track_fin_list, ", ")
          ENDIF
          SET v_track_fin_list = CONCAT(v_track_fin_list, TRIM(enc_rec->qual[v_e].fin))
          SET v_enc_idx = v_enc_idx + 1
          SET stat = ALTERLIST(reply->encounter_tracks[v_track_idx].encounters, v_enc_idx)
          SET v_color_idx = MOD(v_e, 4) + 1
          SET v_args = BUILD2('/PERSONID=', TRIM(CNVTSTRING($PAT_PersonId, 20, 0)), ' /ENCNTRID=', TRIM(CNVTSTRING(enc_rec->qual[v_e].encntr_id, 20, 0)), ' /FIRSTTAB="Pharmacist MPage"')
          SET reply->encounter_tracks[v_track_idx].encounters[v_enc_idx].encntr_id = enc_rec->qual[v_e].encntr_id
          SET reply->encounter_tracks[v_track_idx].encounters[v_enc_idx].fin = enc_rec->qual[v_e].fin
          IF (enc_rec->qual[v_e].arrive_dt = NULL OR enc_rec->qual[v_e].arrive_dt = 0)
            SET reply->encounter_tracks[v_track_idx].encounters[v_enc_idx].arrive_date = "Unknown"
          ELSE
            SET reply->encounter_tracks[v_track_idx].encounters[v_enc_idx].arrive_date = FORMAT(enc_rec->qual[v_e].arrive_dt, "DD/MM/YYYY;;d")
          ENDIF
          IF (enc_rec->qual[v_e].disch_dt = NULL OR enc_rec->qual[v_e].disch_dt = 0)
            SET reply->encounter_tracks[v_track_idx].encounters[v_enc_idx].discharge_date = "Active"
          ELSE
            SET reply->encounter_tracks[v_track_idx].encounters[v_enc_idx].discharge_date = FORMAT(enc_rec->qual[v_e].disch_dt, "DD/MM/YYYY;;d")
          ENDIF
          SET reply->encounter_tracks[v_track_idx].encounters[v_enc_idx].start_idx = enc_rec->qual[v_e].start_idx
          SET reply->encounter_tracks[v_track_idx].encounters[v_enc_idx].end_idx = enc_rec->qual[v_e].end_idx
          SET reply->encounter_tracks[v_track_idx].encounters[v_enc_idx].color_class = BUILD2('enc-c', TRIM(CNVTSTRING(v_color_idx)))
          SET reply->encounter_tracks[v_track_idx].encounters[v_enc_idx].applink_app = 'Powerchart.exe'
          SET reply->encounter_tracks[v_track_idx].encounters[v_enc_idx].applink_args = v_args
        ENDIF
      ENDFOR
      SET reply->encounter_tracks[v_track_idx].track_label = v_track_fin_list

      SET v_i = 0
      WHILE (v_i < v_days)
        SET v_day_idx = v_i + 1
        SET stat = ALTERLIST(reply->encounter_tracks[v_track_idx].days, v_day_idx)
        SET v_cell_class = 'spacer-bit'
        SET v_cell_title = ''
        FOR (v_e = 1 TO enc_rec->cnt)
          IF (enc_rec->qual[v_e].track = v_t)
            IF (v_i >= enc_rec->qual[v_e].start_idx AND v_i <= enc_rec->qual[v_e].end_idx)
              SET v_color_idx = MOD(v_e, 4) + 1
              SET v_cell_class = BUILD2('enc-c', TRIM(CNVTSTRING(v_color_idx)))
              SET v_cell_title = BUILD2('FIN: ', TRIM(enc_rec->qual[v_e].fin))
              IF (enc_rec->qual[v_e].arrive_dt != NULL AND enc_rec->qual[v_e].arrive_dt != 0)
                SET v_cell_title = CONCAT(v_cell_title, ' | Arrive: ', FORMAT(enc_rec->qual[v_e].arrive_dt, 'DD/MM/YYYY;;d'))
              ELSE
                SET v_cell_title = CONCAT(v_cell_title, ' | Arrive: Unknown')
              ENDIF
              IF (enc_rec->qual[v_e].disch_dt = NULL OR enc_rec->qual[v_e].disch_dt = 0)
                SET v_cell_title = CONCAT(v_cell_title, ' | Active')
              ELSE
                SET v_cell_title = CONCAT(v_cell_title, ' | DC: ', FORMAT(enc_rec->qual[v_e].disch_dt, 'DD/MM/YYYY;;d'))
              ENDIF
            ENDIF
          ENDIF
        ENDFOR
        SET reply->encounter_tracks[v_track_idx].days[v_day_idx].day_key = FORMAT(v_min_dt + v_i, 'YYYYMMDD;;D')
        SET reply->encounter_tracks[v_track_idx].days[v_day_idx].cell_class = v_cell_class
        SET reply->encounter_tracks[v_track_idx].days[v_day_idx].title = v_cell_title
        SET v_i = v_i + 1
      ENDWHILE
    ENDFOR
  ENDIF
ENDIF

IF (admin_rec->cnt > 0)
SELECT INTO "nl:"
  med_name                 = TRIM(OC.PRIMARY_MNEMONIC)
, admin_src                = admin_rec->qual[d.seq].src
, day_key                  = FORMAT(admin_rec->qual[d.seq].admin_dt_tm, "YYYYMMDD")
, O.CURRENT_START_DT_TM
, o_order_status_disp      = UAR_GET_CODE_DISPLAY(O.ORDER_STATUS_CD)
, O.STATUS_DT_TM
, indication               = SUBSTRING(1,60,TRIM(OD_INDICATION.OE_FIELD_DISPLAY_VALUE))
, ordered_target_dose      = OI.ORDERED_DOSE
, ordered_target_dose_unit = UAR_GET_CODE_DISPLAY(OI.ORDERED_DOSE_UNIT_CD)
, strength_val             = SUBSTRING(1,60,TRIM(OD_STRENGTH.OE_FIELD_DISPLAY_VALUE))
, strength_unit            = SUBSTRING(1,60,TRIM(OD_STRENGTHUNIT.OE_FIELD_DISPLAY_VALUE))
, volume_val               = SUBSTRING(1,60,TRIM(OD_VOLUME.OE_FIELD_DISPLAY_VALUE))
, volume_unit              = SUBSTRING(1,60,TRIM(OD_VOLUMEUNIT.OE_FIELD_DISPLAY_VALUE))
, simplified_disp          = TRIM(O.SIMPLIFIED_DISPLAY_LINE)
, fin_alias                = TRIM(EA.ALIAS)
, encntr_id_val            = O.ENCNTR_ID
, O.ORDER_ID
FROM
  (DUMMYT D WITH SEQ = admin_rec->cnt)
, ORDERS O
, ORDER_CATALOG OC
, ORDER_INGREDIENT OI
, ORDER_DETAIL OD_INDICATION
, ORDER_DETAIL OD_STRENGTH
, ORDER_DETAIL OD_STRENGTHUNIT
, ORDER_DETAIL OD_VOLUME
, ORDER_DETAIL OD_VOLUMEUNIT
, ENCNTR_ALIAS EA
PLAN D
JOIN O WHERE O.ORDER_ID = admin_rec->qual[d.seq].order_id
JOIN OC WHERE OC.CATALOG_CD = O.CATALOG_CD
JOIN OI WHERE OI.ORDER_ID = OUTERJOIN(O.ORDER_ID)
  AND OI.COMP_SEQUENCE = OUTERJOIN(1)
JOIN OD_INDICATION WHERE OD_INDICATION.ORDER_ID = OUTERJOIN(O.ORDER_ID)
  AND OD_INDICATION.OE_FIELD_MEANING_ID = OUTERJOIN(15)
JOIN OD_STRENGTH WHERE OD_STRENGTH.ORDER_ID = OUTERJOIN(O.ORDER_ID)
  AND OD_STRENGTH.OE_FIELD_MEANING_ID = OUTERJOIN(2056)
JOIN OD_STRENGTHUNIT WHERE OD_STRENGTHUNIT.ORDER_ID = OUTERJOIN(O.ORDER_ID)
  AND OD_STRENGTHUNIT.OE_FIELD_MEANING_ID = OUTERJOIN(2057)
JOIN OD_VOLUME WHERE OD_VOLUME.ORDER_ID = OUTERJOIN(O.ORDER_ID)
  AND OD_VOLUME.OE_FIELD_MEANING_ID = OUTERJOIN(2058)
JOIN OD_VOLUMEUNIT WHERE OD_VOLUMEUNIT.ORDER_ID = OUTERJOIN(O.ORDER_ID)
  AND OD_VOLUMEUNIT.OE_FIELD_MEANING_ID = OUTERJOIN(2059)
JOIN EA WHERE EA.ENCNTR_ID = OUTERJOIN(O.ENCNTR_ID)
  AND EA.ENCNTR_ALIAS_TYPE_CD = OUTERJOIN(1077.00)
ORDER BY O.ORDER_ID, CNVTUPPER(TRIM(OC.PRIMARY_MNEMONIC)), DAY_KEY

HEAD REPORT
  v_row_cnt = 0

HEAD O.ORDER_ID
  v_drug = med_name
  v_order_src = admin_src
  v_dose = 0.0
  v_unit = ""
  v_ind = ""
  v_disp = ""
  v_fin = ""
  v_encntr_id = ""
  v_start = ""
  v_stat = ""
  v_sdt = ""
  v_oid = CNVTSTRING(O.ORDER_ID)
  v_dot = 0
  v_doses = 0

HEAD DAY_KEY
  v_dot = v_dot + 1

DETAIL
  v_doses = v_doses + 1

FOOT O.ORDER_ID
  v_dose = ordered_target_dose
  v_unit = ordered_target_dose_unit
  v_ind = indication
  v_disp = simplified_disp
  v_fin = fin_alias
  v_encntr_id = TRIM(CNVTSTRING(encntr_id_val, 20, 0))
  v_start = FORMAT(O.CURRENT_START_DT_TM,"DD/MM/YYYY;;d")
  v_stat = o_order_status_disp
  v_sdt = FORMAT(O.STATUS_DT_TM,"DD/MM/YYYY;;d")

  IF (v_dose > 0)
    v_dose_str = TRIM(FORMAT(v_dose, "########.####"))
    WHILE (TEXTLEN(v_dose_str) > 0 AND SUBSTRING(TEXTLEN(v_dose_str), 1, v_dose_str) = "0")
      v_dose_str = SUBSTRING(1, TEXTLEN(v_dose_str) - 1, v_dose_str)
    ENDWHILE
    IF (TEXTLEN(v_dose_str) > 0 AND SUBSTRING(TEXTLEN(v_dose_str), 1, v_dose_str) = ".")
      v_dose_str = SUBSTRING(1, TEXTLEN(v_dose_str) - 1, v_dose_str)
    ENDIF
    v_dose_str = CONCAT(TRIM(v_dose_str), " ", v_unit)
  ELSE
    v_dose_str = ""
  ENDIF

  v_actual_dose_str = ""
  v_s = ""
  v_v = ""
  IF (TEXTLEN(TRIM(strength_val)) > 0)
    v_s = TRIM(strength_val)
    IF (TEXTLEN(TRIM(strength_unit)) > 0)
      v_s = CONCAT(v_s, " ", TRIM(strength_unit))
    ENDIF
  ENDIF
  IF (TEXTLEN(TRIM(volume_val)) > 0)
    v_v = TRIM(volume_val)
    IF (TEXTLEN(TRIM(volume_unit)) > 0)
      v_v = CONCAT(v_v, " ", TRIM(volume_unit))
    ENDIF
  ENDIF
  IF (TEXTLEN(v_s) > 0)
    v_actual_dose_str = v_s
  ELSEIF (TEXTLEN(v_v) > 0)
    v_actual_dose_str = v_v
  ELSEIF (TEXTLEN(v_dose_str) > 0)
    v_actual_dose_str = v_dose_str
  ENDIF

  IF (TRIM(v_fin) = "")
    v_fin = "--"
  ENDIF

  v_target_dose = v_dose_str
  v_order_detail = v_disp
  reply->meta.order_rows = reply->meta.order_rows + 1
  stat = ALTERLIST(reply->order_details, reply->meta.order_rows)
  v_args = BUILD2('/PERSONID=', TRIM(CNVTSTRING($PAT_PersonId, 20, 0)), ' /ENCNTRID=', v_encntr_id, ' /FIRSTTAB="Pharmacist MPage"')
  reply->order_details[reply->meta.order_rows].medication_name = v_drug
  reply->order_details[reply->meta.order_rows].source = v_order_src
  reply->order_details[reply->meta.order_rows].doses_total = v_doses
  reply->order_details[reply->meta.order_rows].dot_total = v_dot
  reply->order_details[reply->meta.order_rows].target_dose = v_target_dose
  reply->order_details[reply->meta.order_rows].actual_dose = v_actual_dose_str
  reply->order_details[reply->meta.order_rows].order_detail = v_order_detail
  reply->order_details[reply->meta.order_rows].indication = v_ind
  reply->order_details[reply->meta.order_rows].start_date = v_start
  reply->order_details[reply->meta.order_rows].latest_status = v_stat
  reply->order_details[reply->meta.order_rows].status_date = v_sdt
  reply->order_details[reply->meta.order_rows].order_id = v_oid
  reply->order_details[reply->meta.order_rows].fin = v_fin
  reply->order_details[reply->meta.order_rows].encntr_id = v_encntr_id
  reply->order_details[reply->meta.order_rows].applink_app = 'Powerchart.exe'
  reply->order_details[reply->meta.order_rows].applink_args = v_args
WITH NOCOUNTER
ENDIF

IF (reply->meta.medication_rows = 0 AND reply->meta.order_rows = 0)
  SET reply->status.message = "No antimicrobial orders found in the selected window."
ENDIF

SET _memory_reply_string = CNVTRECTOJSON(reply)
END GO



