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
DECLARE v_html_idx       = i4 WITH NOCONSTANT(0)
DECLARE v_html_part      = vc WITH NOCONSTANT(""), MAXLEN=65534
DECLARE v_html_text      = vc WITH NOCONSTANT(""), MAXLEN=65534
DECLARE v_html_attr      = vc WITH NOCONSTANT(""), MAXLEN=65534
DECLARE v_html_attr2     = vc WITH NOCONSTANT(""), MAXLEN=65534
DECLARE v_chart_cols     = vc WITH NOCONSTANT(""), MAXLEN=255
DECLARE v_chart_start_lbl = vc WITH NOCONSTANT(""), MAXLEN=64
DECLARE v_chart_end_lbl   = vc WITH NOCONSTANT(""), MAXLEN=64
DECLARE v_month_span     = i4 WITH NOCONSTANT(0)
DECLARE v_next_idx       = i4 WITH NOCONSTANT(0)
DECLARE v_marker         = vc WITH NOCONSTANT(""), MAXLEN=16
DECLARE v_row_class      = vc WITH NOCONSTANT(""), MAXLEN=32
DECLARE v_generated_ts   = vc WITH NOCONSTANT(""), MAXLEN=32
DECLARE v_day_zero_idx   = i4 WITH NOCONSTANT(0)

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
  1 ui
    2 html_parts[*]
      3 text = vc
    2 css_parts[*]
      3 text = vc
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

SET stat = ALTERLIST(reply->ui.css_parts, 5)
SET reply->ui.css_parts[1].text = BUILD2(
  ".module-micro{max-width:100%}"
  , ".module-micro .micro-title{display:none;margin:0 0 8px;padding-bottom:8px;border-bottom:3px solid #0c7aa6;color:#0c7aa6;font-size:18px;font-weight:400}"
  , ".module-micro h2{font-size:15px;margin:16px 0 2px;padding-top:0;color:#111}"
  , ".module-micro .legend{margin-top:6px;color:#555;font-size:12px}"
  , ".module-micro .chart-wrap{overflow-x:auto;overflow-y:hidden;margin-bottom:12px;width:100%;display:block}"
  , ".module-micro .chart-grid{display:grid;background:#fff;width:max-content;border-left:1px solid #b5b5b5;font-size:12px}"
  , ".module-micro .grid-cell{border-right:1px solid #dde1e5;border-bottom:none;background:#fff;padding:0;display:flex;align-items:center;min-width:0}"
  , ".module-micro .grid-cell.label,.module-micro .grid-cell.sticky-med{border-right-color:#b5b5b5!important;border-bottom:1px solid #b5b5b5!important}"
  , ".module-micro .grid-cell.sticky-doses,.module-micro .grid-cell.sticky-dot{border-right-color:#b5b5b5!important;border-bottom:1px solid #b5b5b5!important}"
  , ".module-micro table.data-tbl th,.module-micro .grid-cell.label:not(.medname){background:#e7eaee!important;color:#2f3c4b;font-weight:600!important;padding:4px 8px}"
  , ".module-micro table.data-tbl th{text-align:left;height:26px;font-size:12px!important}"
  , ".module-micro .grid-cell.label{min-height:26px}"
  , ".module-micro .sticky-med{position:sticky;left:0;z-index:10;background:#fff;overflow:hidden;white-space:nowrap;text-overflow:ellipsis;width:200px;min-width:200px;max-width:200px}"
  , ".module-micro .sticky-doses{position:sticky;left:200px;z-index:10;background:#fff;width:40px;min-width:40px;max-width:40px;text-align:center;justify-content:center}"
  , ".module-micro .sticky-dot{position:sticky;left:240px;z-index:10;background:#fff;box-shadow:2px 0 5px -2px rgba(0,0,0,.2);width:40px;min-width:40px;max-width:40px;text-align:center;justify-content:center}"
  , ".module-micro .hdr-intersect{z-index:20!important;border-top:1px solid #b5b5b5!important}"
  , ".module-micro .even-cell.sticky-med,.module-micro .even-cell.sticky-doses,.module-micro .even-cell.sticky-dot,.module-micro .even-cell.medname{background:#fafafa!important}"
)
SET reply->ui.css_parts[2].text = BUILD2(
  ".module-micro .dot-val{justify-content:center}"
  , ".module-micro .grid-cell.medname{padding:2px 6px;font-size:14px!important}"
  , ".module-micro .med-trigger{cursor:pointer;color:#111;transition:background .2s}"
  , ".module-micro .med-trigger:hover{background-color:#e0f0ff!important}"
  , ".module-micro .filter-icon{font-size:8px;opacity:.5;margin-left:6px}"
  , ".module-micro .dimmed{opacity:.15;filter:grayscale(100%);pointer-events:none;transition:opacity .3s ease}"
  , ".module-micro .dimmable{transition:opacity .3s ease}"
  , ".module-micro .active-filter{background-color:#e0f0ff!important;font-weight:700}"
  , ".module-micro .grid-cell.dimmed.sticky-med,.module-micro .grid-cell.dimmed.sticky-doses,.module-micro .grid-cell.dimmed.sticky-dot{opacity:1!important;filter:none!important;color:#b5b5b5!important}"
  , ".module-micro .grid-cell.dimmed.sticky-med .pill,.module-micro .grid-cell.dimmed.sticky-doses .pill,.module-micro .grid-cell.dimmed.sticky-dot .pill{background:#f0f0f0!important;color:#b5b5b5!important;box-shadow:none!important}"
  , ".module-micro .row-hover:not(.on):not(.always-on){background-color:transparent!important}"
  , ".module-micro .cell.row-hover:not(.on)::after{background:#b8d4ee!important}"
  , ".module-micro .cell,.module-micro .tick{width:14px;min-width:14px;max-width:14px;justify-content:center;font-size:10px}"
  , ".module-micro .cell{border-right:1px solid #f8f8f8!important;border-bottom:none!important;border-left:none!important;color:transparent;background:transparent!important;position:relative;z-index:1}"
  , ".module-micro .tick{border-right:none!important;height:22px;position:relative;overflow:visible!important;align-items:center;padding-bottom:0;justify-content:center;font-size:10px;color:#555}"
  , ".module-micro .tick::after{content:'';position:absolute;right:0;bottom:0;width:1px;height:6px;background:#b5b5b5}"
  , ".module-micro .mo-span{height:20px;font-size:11px;font-weight:600;color:#2f3c4b;background:#e7eaee!important;border-top:1px solid #b5b5b5!important;border-right:1px solid #b5b5b5!important;border-bottom:1px solid #b5b5b5!important;padding:0 4px;overflow:hidden;white-space:nowrap;text-overflow:ellipsis;align-items:center}"
  , ".module-micro .grid-cell.axis-header{display:block;line-height:18px;overflow:visible;white-space:nowrap;border-top:1px solid #b5b5b5!important}"
)
SET reply->ui.css_parts[3].text = BUILD2(
  ".module-micro .cell::after{content:'';position:absolute;top:50%;left:50%;transform:translate(-50%,-50%);width:14px;height:12px;background:#F5F5F6;border-radius:0;z-index:-1}"
  , ".module-micro .cell.on{color:#fff!important;font-weight:600}"
  , ".module-micro .cell.on::after{width:14px;height:12px;background:#0086ce;border-radius:0}"
  , ".module-micro .cell.on:empty::before{content:'1'}"
  , ".module-micro .cell.sum-yes,.module-micro .cell.sum-no,.module-micro .cell.enc-c1,.module-micro .cell.enc-c2,.module-micro .cell.enc-c3,.module-micro .cell.enc-c4{background:transparent!important}"
  , ".module-micro .cell.sum-yes::after{width:14px;height:12px;background:#f37074be}"
  , ".module-micro .cell.sum-no::after{width:14px;height:12px;background:#a8d08dbe}"
  , ".module-micro .sum-border{border-top:2px solid #a0a0a0!important}"
  , ".module-micro .pill,.module-micro .pill-num{display:inline-block;padding:2px 6px;border-radius:12px;background:#eef;color:#334;line-height:1}"
  , ".module-micro .cell.enc-c1::after{width:14px;height:12px;background:#b8d8f8}"
  , ".module-micro .cell.enc-c2::after{width:14px;height:12px;background:#b3d0ebb4}"
  , ".module-micro .cell.enc-c3::after{width:14px;height:12px;background:#c8e8fb}"
  , ".module-micro .cell.enc-c4::after{width:14px;height:12px;background:#aad8f7}"
  , ".module-micro .enc-border{border-top:2px solid #90b8e0!important}"
  , ".module-micro .enc-label-cell{font-size:11px!important}"
  , ".module-micro .enc-label-cell a,.module-micro .fin-link{color:#0086ce;text-decoration:none;font-weight:600}"
  , ".module-micro .enc-label-cell a:hover,.module-micro .fin-link:hover{text-decoration:underline}"
  , ".module-micro .enc-cell-text{font-size:8px;font-weight:700;color:#111;line-height:1;overflow:hidden;max-width:14px;display:block;text-align:center}"
)
SET reply->ui.css_parts[4].text = BUILD2(
  ".module-micro .table-wrap{width:100%;overflow-x:auto;display:block}"
  , ".module-micro table.data-tbl{width:100%;min-width:1460px;border-collapse:separate;border-spacing:0;margin-top:2px;font-size:12px;border-top:1px solid #b5b5b5;border-left:1px solid #b5b5b5;border-bottom:2px solid #a0a0a0;table-layout:fixed}"
  , ".module-micro table.data-tbl th,.module-micro table.data-tbl td{border-right:1px solid #b5b5b5;border-bottom:1px solid #b5b5b5;padding:4px 6px;text-align:left;background:#fff;word-break:break-word;overflow-wrap:break-word;overflow:hidden;transition:background-color .2s}"
  , ".module-micro table.data-tbl th:nth-child(1),.module-micro table.data-tbl td:nth-child(1){box-sizing:border-box!important;width:200px;min-width:200px;max-width:200px}"
  , ".module-micro table.data-tbl th:nth-child(2),.module-micro table.data-tbl td:nth-child(2){box-sizing:border-box!important;width:40px;min-width:40px;max-width:40px;text-align:center;padding:4px 0}"
  , ".module-micro table.data-tbl th:nth-child(3),.module-micro table.data-tbl td:nth-child(3){box-sizing:border-box!important;width:40px;min-width:40px;max-width:40px;text-align:center;padding:4px 0}"
  , ".module-micro table.data-tbl th:nth-child(4),.module-micro table.data-tbl td:nth-child(4){box-sizing:border-box!important;width:100px;min-width:100px;max-width:100px}"
  , ".module-micro table.data-tbl th:nth-child(6),.module-micro table.data-tbl td:nth-child(6){box-sizing:border-box!important;width:350px;min-width:350px;max-width:350px}"
  , ".module-micro table.data-tbl th:nth-child(7),.module-micro table.data-tbl td:nth-child(7){box-sizing:border-box!important;width:250px;min-width:250px;max-width:250px}"
  , ".module-micro table.data-tbl tr.even td{background:#fafafa}"
  , ".module-micro table.data-tbl tbody tr:last-child td{border-bottom:none}"
  , ".module-micro table.data-tbl tbody tr:hover td{background-color:#f0f7ff;cursor:default}"
  , ".module-micro .micro-footer{margin-top:24px;padding-top:8px;border-top:1px solid #b5b5b5;color:#666;font-size:12px}"
  , "@media (max-width:1100px){.module-micro .viewer{padding:12px}.module-micro .chart-wrap{margin-bottom:8px}.module-micro .table-wrap{overflow-x:auto;display:block}}"
)

SET v_html_idx = 0
SET v_generated_ts = TRIM(FORMAT(CNVTDATETIME(CURDATE, CURTIME3), "YYYY-MM-DD HH:MM:SS;;Q"), 3)

SET v_html_idx = v_html_idx + 1
SET stat = ALTERLIST(reply->ui.html_parts, v_html_idx)
SET reply->ui.html_parts[v_html_idx].text = BUILD2(
  "<section class='panel module-shell module-micro'><div class='panel-body'>"
  , "<div class='micro-title'>Antimicrobial Days of Therapy</div>"
  , "<div class='legend'>Each blue square marks a <b>day</b> where the medication has been administered. A number indicates the count of administrations for that day.<br>"
  , "<b>Summary:</b> Red = Antimicrobial given, Green = No antimicrobial given. &nbsp;<b>Encounter:</b> &#9650; Admit, &#9660; Discharge, &#9670; Same-day admit &amp; discharge.<br />"
  , "<b>Interactive:</b> Click a medication name to isolate its history across the chart and table.</div>"
)

IF (reply->meta.medication_rows = 0)
  SET v_html_text = TRIM(reply->status.message, 3)
  IF (v_html_text = "")
    SET v_html_text = "No antimicrobial orders found in the selected window."
  ENDIF
  SET v_html_text = REPLACE(REPLACE(REPLACE(v_html_text, "&", "&amp;", 0), "<", "&lt;", 0), ">", "&gt;", 0)
  SET v_html_idx = v_html_idx + 1
  SET stat = ALTERLIST(reply->ui.html_parts, v_html_idx)
  SET reply->ui.html_parts[v_html_idx].text = BUILD2("<div class='empty-state'>", v_html_text, "</div></div></section>")
ELSE
  SET v_chart_start_lbl = FORMAT(v_min_dt, "DD-MMM-YYYY;;D")
  SET v_chart_end_lbl = FORMAT(v_max_dt, "DD-MMM-YYYY;;D")
  SET v_chart_cols = BUILD2("grid-template-columns: 200px 40px 40px repeat(", TRIM(CNVTSTRING(size(reply->headers, 5), 20, 0)), ", 14px);")
  SET v_chart_start_lbl = REPLACE(REPLACE(REPLACE(TRIM(v_chart_start_lbl, 3), "&", "&amp;", 0), "<", "&lt;", 0), ">", "&gt;", 0)
  SET v_chart_end_lbl = REPLACE(REPLACE(REPLACE(TRIM(v_chart_end_lbl, 3), "&", "&amp;", 0), "<", "&lt;", 0), ">", "&gt;", 0)

  SET v_html_idx = v_html_idx + 1
  SET stat = ALTERLIST(reply->ui.html_parts, v_html_idx)
  SET reply->ui.html_parts[v_html_idx].text = BUILD2(
    "<div class='chart-wrap'><div class='chart-grid' style='", v_chart_cols, "'>"
    , "<div class='grid-cell label sticky-med hdr-intersect always-on'>Medication</div>"
    , "<div class='grid-cell label sticky-doses hdr-intersect always-on'>Doses</div>"
    , "<div class='grid-cell label sticky-dot hdr-intersect always-on'>DOT</div>"
    , "<div class='grid-cell label axis-header always-on' style='grid-column: 4 / span ", TRIM(CNVTSTRING(size(reply->headers, 5), 20, 0)), "; min-width:320px;'>Date range: "
    , v_chart_start_lbl, " to ", v_chart_end_lbl, " (", TRIM(CNVTSTRING(size(reply->headers, 5), 20, 0)), " days)</div>"
  )

  SET v_html_idx = v_html_idx + 1
  SET stat = ALTERLIST(reply->ui.html_parts, v_html_idx)
  SET v_html_part = "<div class='grid-cell hdr-intersect always-on' style='grid-column:span 3;background:#e7eaee;border-right:1px solid #b5b5b5;border-bottom:1px solid #b5b5b5;'></div>"
  SET v_i = 1
  WHILE (v_i <= size(reply->headers, 5))
    SET v_month_span = 1
    SET v_next_idx = v_i + 1
    WHILE (v_next_idx <= size(reply->headers, 5) AND reply->headers[v_next_idx].new_month = 0)
      SET v_month_span = v_month_span + 1
      SET v_next_idx = v_next_idx + 1
    ENDWHILE
    SET v_html_text = TRIM(reply->headers[v_i].month_label, 3)
    SET v_html_text = REPLACE(REPLACE(REPLACE(v_html_text, "&", "&amp;", 0), "<", "&lt;", 0), ">", "&gt;", 0)
    SET v_html_part = BUILD2(v_html_part, "<div class='grid-cell mo-span always-on' style='grid-column:span ", TRIM(CNVTSTRING(v_month_span, 20, 0)), ";'>", v_html_text, "</div>")
    SET v_i = v_next_idx
  ENDWHILE
  SET reply->ui.html_parts[v_html_idx].text = v_html_part

  SET v_html_idx = v_html_idx + 1
  SET stat = ALTERLIST(reply->ui.html_parts, v_html_idx)
  SET v_html_part = "<div class='grid-cell hdr-intersect always-on' style='grid-column:span 3;background:#e7eaee;border-right:1px solid #b5b5b5;border-bottom:1px solid #b5b5b5;'></div>"
  SET v_day_idx = 1
  WHILE (v_day_idx <= size(reply->headers, 5))
    SET v_html_attr = TRIM(reply->headers[v_day_idx].iso_date, 3)
    SET v_html_attr = REPLACE(REPLACE(REPLACE(v_html_attr, "&", "&amp;", 0), "<", "&lt;", 0), ">", "&gt;", 0)
    SET v_html_attr = REPLACE(v_html_attr, "'", "&#39;", 0)
    SET v_html_text = TRIM(reply->headers[v_day_idx].day_label, 3)
    SET v_html_text = REPLACE(REPLACE(REPLACE(v_html_text, "&", "&amp;", 0), "<", "&lt;", 0), ">", "&gt;", 0)
    SET v_html_part = BUILD2(v_html_part, "<div class='grid-cell tick' title='", v_html_attr, "'>", v_html_text, "</div>")
    SET v_day_idx = v_day_idx + 1
  ENDWHILE
  SET reply->ui.html_parts[v_html_idx].text = v_html_part

  SET v_i = 1
  WHILE (v_i <= reply->meta.medication_rows)
    IF (MOD(v_i, 2) = 0)
      SET v_row_class = " even-cell"
    ELSE
      SET v_row_class = ""
    ENDIF

    SET v_html_text = TRIM(reply->timeline[v_i].medication_name, 3)
    SET v_html_text = REPLACE(REPLACE(REPLACE(v_html_text, "&", "&amp;", 0), "<", "&lt;", 0), ">", "&gt;", 0)
    SET v_html_attr = REPLACE(v_html_text, "'", "&#39;", 0)
    SET v_html_attr2 = BUILD2(TRIM(reply->timeline[v_i].medication_name, 3), " - Total Doses: ", TRIM(CNVTSTRING(reply->timeline[v_i].doses_total, 20, 0)))
    SET v_html_attr2 = REPLACE(REPLACE(REPLACE(v_html_attr2, "&", "&amp;", 0), "<", "&lt;", 0), ">", "&gt;", 0)
    SET v_html_attr2 = REPLACE(v_html_attr2, "'", "&#39;", 0)

    SET v_html_part = BUILD2(
      "<div class='grid-cell label medname sticky-med med-trigger dimmable", v_row_class, "' data-med='", v_html_attr, "' title='Click to filter by ", v_html_attr, "'>", v_html_text, "</div>"
      , "<div class='grid-cell dot-val sticky-doses dimmable", v_row_class, "' data-med='", v_html_attr, "'><span class='pill' title='", v_html_attr2, "'>", TRIM(CNVTSTRING(reply->timeline[v_i].doses_total, 20, 0)), "</span></div>"
    )

    SET v_html_attr2 = BUILD2(TRIM(reply->timeline[v_i].medication_name, 3), " - Total Days of Therapy: ", TRIM(CNVTSTRING(reply->timeline[v_i].dot_total, 20, 0)))
    SET v_html_attr2 = REPLACE(REPLACE(REPLACE(v_html_attr2, "&", "&amp;", 0), "<", "&lt;", 0), ">", "&gt;", 0)
    SET v_html_attr2 = REPLACE(v_html_attr2, "'", "&#39;", 0)
    SET v_html_part = BUILD2(v_html_part, "<div class='grid-cell dot-val sticky-dot dimmable", v_row_class, "' data-med='", v_html_attr, "'><span class='pill' title='", v_html_attr2, "'>", TRIM(CNVTSTRING(reply->timeline[v_i].dot_total, 20, 0)), "</span></div>")

    SET v_day_idx = 1
    WHILE (v_day_idx <= size(reply->headers, 5))
      IF (v_day_idx <= size(reply->timeline[v_i].days, 5))
        SET v_html_attr2 = REPLACE(reply->timeline[v_i].days[v_day_idx].title, "&#10;", CHAR(10), 0)
        SET v_html_attr2 = REPLACE(REPLACE(REPLACE(v_html_attr2, "&", "&amp;", 0), "<", "&lt;", 0), ">", "&gt;", 0)
        SET v_html_attr2 = REPLACE(v_html_attr2, "'", "&#39;", 0)
      ELSE
        SET v_html_attr2 = TRIM(reply->headers[v_day_idx].iso_date, 3)
        SET v_html_attr2 = REPLACE(REPLACE(REPLACE(v_html_attr2, "&", "&amp;", 0), "<", "&lt;", 0), ">", "&gt;", 0)
        SET v_html_attr2 = REPLACE(v_html_attr2, "'", "&#39;", 0)
      ENDIF
      IF (v_day_idx <= size(reply->timeline[v_i].days, 5) AND reply->timeline[v_i].days[v_day_idx].on_ind = 1)
        SET v_html_part = BUILD2(v_html_part, "<div class='grid-cell cell on dimmable", v_row_class, "' data-med='", v_html_attr, "' title='", v_html_attr2, "'>", TRIM(CNVTSTRING(reply->timeline[v_i].days[v_day_idx].admin_count, 20, 0)), "</div>")
      ELSE
        SET v_html_part = BUILD2(v_html_part, "<div class='grid-cell cell dimmable", v_row_class, "' data-med='", v_html_attr, "' title='", v_html_attr2, "'></div>")
      ENDIF
      SET v_day_idx = v_day_idx + 1
    ENDWHILE

    SET v_html_idx = v_html_idx + 1
    SET stat = ALTERLIST(reply->ui.html_parts, v_html_idx)
    SET reply->ui.html_parts[v_html_idx].text = v_html_part
    SET v_i = v_i + 1
  ENDWHILE

  IF (size(reply->summary_days, 5) > 0)
    SET v_html_idx = v_html_idx + 1
    SET stat = ALTERLIST(reply->ui.html_parts, v_html_idx)
    SET v_html_attr = BUILD2("Total Summary Days of Therapy: ", TRIM(CNVTSTRING(reply->meta.grand_total_dot, 20, 0)))
    SET v_html_attr = REPLACE(REPLACE(REPLACE(v_html_attr, "&", "&amp;", 0), "<", "&lt;", 0), ">", "&gt;", 0)
    SET v_html_attr = REPLACE(v_html_attr, "'", "&#39;", 0)
    SET v_html_part = BUILD2(
      "<div class='grid-cell label sticky-med sum-border always-on'>Antimicrobial Summary</div>"
      , "<div class='grid-cell label sticky-doses sum-border always-on'></div>"
      , "<div class='grid-cell label dot-val sticky-dot sum-border always-on'><span class='pill' title='", v_html_attr, "'>", TRIM(CNVTSTRING(reply->meta.grand_total_dot, 20, 0)), "</span></div>"
    )
    SET v_day_idx = 1
    WHILE (v_day_idx <= size(reply->summary_days, 5))
      IF (reply->summary_days[v_day_idx].antimicrobial_ind = 1)
        SET v_html_attr = "Antimicrobial Administered"
        SET v_html_text = "sum-yes"
      ELSE
        SET v_html_attr = "No Antimicrobials"
        SET v_html_text = "sum-no"
      ENDIF
      SET v_html_attr = REPLACE(REPLACE(REPLACE(v_html_attr, "&", "&amp;", 0), "<", "&lt;", 0), ">", "&gt;", 0)
      SET v_html_attr = REPLACE(v_html_attr, "'", "&#39;", 0)
      SET v_html_part = BUILD2(v_html_part, "<div class='grid-cell cell ", v_html_text, " sum-border' title='", v_html_attr, "'></div>")
      SET v_day_idx = v_day_idx + 1
    ENDWHILE
    SET reply->ui.html_parts[v_html_idx].text = v_html_part
  ENDIF

  SET v_track_idx = 1
  WHILE (v_track_idx <= size(reply->encounter_tracks, 5))
    SET v_html_part = "<div class='grid-cell label enc-label-cell sticky-med always-on'>Encounter</div><div class='grid-cell label sticky-doses always-on'></div><div class='grid-cell label sticky-dot always-on'></div>"
    SET v_day_idx = 1
    WHILE (v_day_idx <= size(reply->headers, 5))
      SET v_day_zero_idx = v_day_idx - 1
      SET v_marker = " "
      SET v_enc_idx = 1
      WHILE (v_enc_idx <= size(reply->encounter_tracks[v_track_idx].encounters, 5))
        IF (v_day_zero_idx >= reply->encounter_tracks[v_track_idx].encounters[v_enc_idx].start_idx AND v_day_zero_idx <= reply->encounter_tracks[v_track_idx].encounters[v_enc_idx].end_idx)
          IF (v_day_zero_idx = reply->encounter_tracks[v_track_idx].encounters[v_enc_idx].start_idx AND v_day_zero_idx = reply->encounter_tracks[v_track_idx].encounters[v_enc_idx].end_idx)
            SET v_marker = "&#9670;"
          ELSEIF (v_day_zero_idx = reply->encounter_tracks[v_track_idx].encounters[v_enc_idx].start_idx)
            SET v_marker = "&#9650;"
          ELSEIF (v_day_zero_idx = reply->encounter_tracks[v_track_idx].encounters[v_enc_idx].end_idx)
            SET v_marker = "&#9660;"
          ENDIF
        ENDIF
        SET v_enc_idx = v_enc_idx + 1
      ENDWHILE
      IF (v_day_idx <= size(reply->encounter_tracks[v_track_idx].days, 5))
        SET v_html_attr = TRIM(reply->encounter_tracks[v_track_idx].days[v_day_idx].cell_class, 3)
        SET v_html_attr2 = TRIM(reply->encounter_tracks[v_track_idx].days[v_day_idx].title, 3)
      ELSE
        SET v_html_attr = "spacer-bit"
        SET v_html_attr2 = " "
      ENDIF
      SET v_html_attr2 = REPLACE(REPLACE(REPLACE(v_html_attr2, "&", "&amp;", 0), "<", "&lt;", 0), ">", "&gt;", 0)
      SET v_html_attr2 = REPLACE(v_html_attr2, "'", "&#39;", 0)
      SET v_html_part = BUILD2(v_html_part, "<div class='grid-cell cell ", v_html_attr, "' title='", v_html_attr2, "'><span class='enc-cell-text'>", v_marker, "</span></div>")
      SET v_day_idx = v_day_idx + 1
    ENDWHILE
    SET v_html_idx = v_html_idx + 1
    SET stat = ALTERLIST(reply->ui.html_parts, v_html_idx)
    SET reply->ui.html_parts[v_html_idx].text = v_html_part
    SET v_track_idx = v_track_idx + 1
  ENDWHILE

  SET v_html_idx = v_html_idx + 1
  SET stat = ALTERLIST(reply->ui.html_parts, v_html_idx)
  SET reply->ui.html_parts[v_html_idx].text = BUILD2(
    "</div></div>"
    , "<h2>Antimicrobial Order Details</h2>"
    , "<div class='table-wrap'><table class='data-tbl'><colgroup>"
    , "<col style='width:200px'><col style='width:40px'><col style='width:40px'>"
    , "<col style='width:100px'><col style='display:none;'>"
    , "<col style='width:350px'><col style='width:250px'>"
    , "<col><col><col><col><col></colgroup>"
    , "<thead><tr><th>Medication</th><th style='text-align:center;'>Doses</th><th style='text-align:center;'>DOT</th><th>Target Dose</th>"
    , "<th style='display:none;'>Dose</th><th>Order Detail</th><th>Indication</th><th>Start Date</th>"
    , "<th>Latest Status</th><th>Status Date</th><th>Order ID</th><th>FIN</th></tr></thead><tbody>"
  )

  IF (reply->meta.order_rows = 0)
    SET v_html_idx = v_html_idx + 1
    SET stat = ALTERLIST(reply->ui.html_parts, v_html_idx)
    SET reply->ui.html_parts[v_html_idx].text = "<tr><td colspan='11'>No antimicrobial orders found in the selected window.</td></tr>"
  ELSE
    SET v_i = 1
    WHILE (v_i <= reply->meta.order_rows)
      IF (MOD(v_i, 2) = 0)
        SET v_row_class = " class='even dimmable'"
      ELSE
        SET v_row_class = " class='dimmable'"
      ENDIF

      SET v_html_text = TRIM(reply->order_details[v_i].medication_name, 3)
      SET v_html_text = REPLACE(REPLACE(REPLACE(v_html_text, "&", "&amp;", 0), "<", "&lt;", 0), ">", "&gt;", 0)
      SET v_html_attr = REPLACE(v_html_text, "'", "&#39;", 0)
      SET v_html_attr2 = TRIM(reply->order_details[v_i].applink_app, 3)
      IF (v_html_attr2 = "")
        SET v_html_attr2 = "Powerchart.exe"
      ENDIF
      SET v_html_attr2 = REPLACE(REPLACE(REPLACE(v_html_attr2, "&", "&amp;", 0), "<", "&lt;", 0), ">", "&gt;", 0)
      SET v_html_attr2 = REPLACE(v_html_attr2, "'", "&#39;", 0)

      SET v_html_part = BUILD2("<tr", v_row_class, " data-med='", v_html_attr, "'>")
      IF (reply->order_details[v_i].source = "SN")
        SET v_html_part = BUILD2(v_html_part, "<td>", v_html_text, " <span style='color:#888;font-size:10px;'>(Anes)</span></td>")
      ELSE
        SET v_html_part = BUILD2(v_html_part, "<td>", v_html_text, "</td>")
      ENDIF

      SET v_html_part = BUILD2(
        v_html_part
        , "<td class='dot-val'><span class='pill'>", TRIM(CNVTSTRING(reply->order_details[v_i].doses_total, 20, 0)), "</span></td>"
        , "<td class='dot-val'><span class='pill'>", TRIM(CNVTSTRING(reply->order_details[v_i].dot_total, 20, 0)), "</span></td>"
      )

      SET v_html_text = TRIM(reply->order_details[v_i].target_dose, 3)
      SET v_html_text = REPLACE(REPLACE(REPLACE(v_html_text, "&", "&amp;", 0), "<", "&lt;", 0), ">", "&gt;", 0)
      SET v_html_part = BUILD2(v_html_part, "<td>", v_html_text, "</td>")

      SET v_html_text = TRIM(reply->order_details[v_i].actual_dose, 3)
      SET v_html_text = REPLACE(REPLACE(REPLACE(v_html_text, "&", "&amp;", 0), "<", "&lt;", 0), ">", "&gt;", 0)
      SET v_html_part = BUILD2(v_html_part, "<td style='display:none;'>", v_html_text, "</td>")

      SET v_html_text = TRIM(reply->order_details[v_i].order_detail, 3)
      SET v_html_text = REPLACE(REPLACE(REPLACE(v_html_text, "&", "&amp;", 0), "<", "&lt;", 0), ">", "&gt;", 0)
      SET v_html_part = BUILD2(v_html_part, "<td>", v_html_text, "</td>")

      SET v_html_text = TRIM(reply->order_details[v_i].indication, 3)
      SET v_html_text = REPLACE(REPLACE(REPLACE(v_html_text, "&", "&amp;", 0), "<", "&lt;", 0), ">", "&gt;", 0)
      SET v_html_part = BUILD2(v_html_part, "<td>", v_html_text, "</td>")

      SET v_html_text = TRIM(reply->order_details[v_i].start_date, 3)
      SET v_html_text = REPLACE(REPLACE(REPLACE(v_html_text, "&", "&amp;", 0), "<", "&lt;", 0), ">", "&gt;", 0)
      SET v_html_part = BUILD2(v_html_part, "<td>", v_html_text, "</td>")

      SET v_html_text = TRIM(reply->order_details[v_i].latest_status, 3)
      SET v_html_text = REPLACE(REPLACE(REPLACE(v_html_text, "&", "&amp;", 0), "<", "&lt;", 0), ">", "&gt;", 0)
      SET v_html_part = BUILD2(v_html_part, "<td>", v_html_text, "</td>")

      SET v_html_text = TRIM(reply->order_details[v_i].status_date, 3)
      SET v_html_text = REPLACE(REPLACE(REPLACE(v_html_text, "&", "&amp;", 0), "<", "&lt;", 0), ">", "&gt;", 0)
      SET v_html_part = BUILD2(v_html_part, "<td>", v_html_text, "</td>")

      SET v_html_text = TRIM(reply->order_details[v_i].order_id, 3)
      SET v_html_text = REPLACE(REPLACE(REPLACE(v_html_text, "&", "&amp;", 0), "<", "&lt;", 0), ">", "&gt;", 0)
      SET v_html_part = BUILD2(v_html_part, "<td>", v_html_text, "</td>")

      SET v_html_text = TRIM(reply->order_details[v_i].fin, 3)
      IF (v_html_text = "")
        SET v_html_text = "--"
      ENDIF
      SET v_html_text = REPLACE(REPLACE(REPLACE(v_html_text, "&", "&amp;", 0), "<", "&lt;", 0), ">", "&gt;", 0)
      SET v_html_attr = TRIM(reply->order_details[v_i].applink_args, 3)
      SET v_html_attr = REPLACE(REPLACE(REPLACE(v_html_attr, "&", "&amp;", 0), "<", "&lt;", 0), ">", "&gt;", 0)
      SET v_html_attr = REPLACE(v_html_attr, "'", "&#39;", 0)
      SET v_html_part = BUILD2(v_html_part, "<td><a href='#' class='fin-link' data-app='", v_html_attr2, "' data-args='", v_html_attr, "'>", v_html_text, "</a></td></tr>")

      SET v_html_idx = v_html_idx + 1
      SET stat = ALTERLIST(reply->ui.html_parts, v_html_idx)
      SET reply->ui.html_parts[v_html_idx].text = v_html_part
      SET v_i = v_i + 1
    ENDWHILE
  ENDIF

  SET v_html_idx = v_html_idx + 1
  SET stat = ALTERLIST(reply->ui.html_parts, v_html_idx)
  SET v_html_text = REPLACE(REPLACE(REPLACE(TRIM(v_generated_ts, 3), "&", "&amp;", 0), "<", "&lt;", 0), ">", "&gt;", 0)
  SET reply->ui.html_parts[v_html_idx].text = BUILD2("</tbody></table></div><div class='micro-footer'>Generated on ", v_html_text, "</div></div></section>")
ENDIF

SET _memory_reply_string = CNVTRECTOJSON(reply)
END GO



