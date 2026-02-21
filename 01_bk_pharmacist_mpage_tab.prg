DROP PROGRAM 01_bk_pharmacist_mpage_tab GO
CREATE PROGRAM 01_bk_pharmacist_mpage_tab

PROMPT
    "Output to File/Printer/MINE" = "MINE"
    , "User Id" = 0
    , "Patient ID" = 0
    , "Encounter Id" = 0
    , "Days Lookback" = 120
WITH OUTDEV, user_id, patient_id, encounter_id, LOOKBACK

; =============================================================================
; 1. GET MOST RECENT WEIGHT DOSING
; =============================================================================
DECLARE sWeightDisp = vc WITH noconstant("No weight dosing measured")

SELECT INTO "NL:"
FROM CLINICAL_EVENT CE
PLAN CE WHERE CE.PERSON_ID = CNVTREAL($patient_id)
    AND CE.EVENT_CD = 14516898.00
    AND CE.VALID_UNTIL_DT_TM > CNVTDATETIME(CURDATE, curtime)
    AND CE.RESULT_STATUS_CD IN (25, 34, 35)
ORDER BY
    CE.EVENT_END_DT_TM DESC
    , CE.CLINSIG_UPDT_DT_TM DESC
HEAD REPORT
    sWeightDisp = CONCAT(
        TRIM(CE.RESULT_VAL), " ",
        UAR_GET_CODE_DISPLAY(CE.RESULT_UNITS_CD),
        " (", FORMAT(CE.EVENT_END_DT_TM, "DD/MM/YY"), ")"
    )
WITH NOCOUNTER, MAXREC=1

; =============================================================================
; 2. GP MEDICATION DETAILS
; =============================================================================
RECORD rec_blob (
  1 list[*]
    2 event_id  = f8
    2 dt_tm     = vc
    2 prsnl     = vc
    2 blob_text = vc
)

DECLARE OcfCD      = f8  WITH noconstant(0.0)
DECLARE stat       = i4  WITH noconstant(0)
DECLARE stat_rtf   = i4  WITH noconstant(0)
DECLARE tlen       = i4  WITH noconstant(0)
DECLARE bsize      = i4  WITH noconstant(0)
DECLARE totlen     = i4  WITH noconstant(0)
DECLARE bloblen    = i4  WITH noconstant(0)
DECLARE vLen       = i4  WITH noconstant(0)
DECLARE nCnt       = i4  WITH noconstant(0)
DECLARE x          = i4  WITH noconstant(0)
DECLARE blob_in    = vc  WITH noconstant(" ")
DECLARE blob_out   = vc  WITH noconstant(" ")
DECLARE rtf_out    = vc  WITH noconstant(" ")
DECLARE vCleanText = vc  WITH noconstant(" ")

SET stat = uar_get_meaning_by_codeset(120, "OCFCOMP", 1, OcfCD)

SELECT INTO "NL:"
FROM CLINICAL_EVENT CE
    , CE_BLOB CB
    , PRSNL PR
PLAN CE WHERE CE.PERSON_ID = CNVTREAL($patient_id)
    AND CE.EVENT_CD = 25256529.00
    AND CE.VALID_UNTIL_DT_TM > SYSDATE
JOIN CB WHERE CB.EVENT_ID = CE.EVENT_ID
    AND CB.VALID_UNTIL_DT_TM > SYSDATE
JOIN PR WHERE PR.PERSON_ID = CE.PERFORMED_PRSNL_ID
ORDER BY CE.PERFORMED_DT_TM DESC

DETAIL
    nCnt = size(rec_blob->list, 5) + 1
    stat = alterlist(rec_blob->list, nCnt)
    rec_blob->list[nCnt].event_id = CE.EVENT_ID
    rec_blob->list[nCnt].dt_tm    = REPLACE(FORMAT(CE.PERFORMED_DT_TM, "DD/MM/YYYY HH:MM"), " 00:00", "", 0)
    rec_blob->list[nCnt].prsnl    = PR.NAME_FULL_FORMATTED

    tlen       = 0
    bsize      = 0
    vCleanText = " "

    bloblen = blobgetlen(CB.BLOB_CONTENTS)
    stat    = memrealloc(blob_in, 1, build("C", bloblen))
    totlen  = blobget(blob_in, 0, CB.BLOB_CONTENTS)

    stat = memrealloc(blob_out, 1, build("C", CB.BLOB_LENGTH))
    call uar_ocf_uncompress(blob_in, textlen(blob_in), blob_out, CB.BLOB_LENGTH, tlen)

    IF (tlen > 0)
        stat = memrealloc(rtf_out, 1, build("C", CB.BLOB_LENGTH))
        IF (FINDSTRING("{\rtf", blob_out, 1, 0) > 0)
            blob_out = REPLACE(blob_out, "\line", "\par", 0)
            tlen = TEXTLEN(blob_out)
            stat_rtf = uar_rtf2(blob_out, tlen, rtf_out, CB.BLOB_LENGTH, bsize, 0)
        ELSE
            rtf_out = blob_out
            bsize = tlen
        ENDIF
    ENDIF

    IF (bsize > 0)
        vCleanText = REPLACE(SUBSTRING(1, bsize, rtf_out), CHAR(0), " ", 0)
    ENDIF

    IF (TEXTLEN(TRIM(vCleanText)) <= 1)
        vCleanText = "<i>-- No narrative note found --</i>"
    ELSE
        vCleanText = REPLACE(vCleanText, "&",     "&amp;", 0)
        vCleanText = REPLACE(vCleanText, "<",     "&lt;",  0)
        vCleanText = REPLACE(vCleanText, ">",     "&gt;",  0)
        vCleanText = REPLACE(vCleanText, concat(CHAR(13), CHAR(10)), "<br />", 0)
        vCleanText = REPLACE(vCleanText, CHAR(13), "<br />", 0)
        vCleanText = REPLACE(vCleanText, CHAR(10), "<br />", 0)
        vCleanText = REPLACE(vCleanText, "<br /><br /><br /><br /><br /><br />", "<br /><br />", 0)
        vCleanText = REPLACE(vCleanText, "<br /><br /><br /><br />", "<br /><br />", 0)
        vCleanText = TRIM(vCleanText, 3)
    ENDIF

    rec_blob->list[nCnt].blob_text = vCleanText

WITH NOCOUNTER, RDBARRAYFETCH=1

; ========================================================================== 
; 3. ANTIMICROBIAL DOT
; ========================================================================== 
declare v_font_size   = vc with noconstant("13px")
declare v_med_font_size = vc with noconstant("14px")
declare v_mrn         = vc with noconstant("")
declare v_name        = vc with noconstant("")
declare v_admit_dt    = vc with noconstant("")
declare v_los         = vc with noconstant("")
declare v_lookback    = vc with noconstant("")
declare v_chart_meta  = vc with noconstant(""), maxlen=2000
declare v_table_meta  = vc with noconstant(""), maxlen=2000
declare v_axis_html   = vc with noconstant(""), maxlen=2000
declare v_header_html = vc with noconstant(""), maxlen=65534
declare v_chart_rows  = vc with noconstant(""), maxlen=65534
declare v_min_dt      = dq8 with noconstant(0)
declare v_max_dt      = dq8 with noconstant(0)
declare v_first       = i2 with noconstant(1)
declare v_days        = i4 with noconstant(0)
declare v_curr_med    = vc with noconstant("")
declare v_dates_kv    = vc with noconstant(""), maxlen=65534
declare v_details_kv  = vc with noconstant(""), maxlen=65534
declare v_cnt_day     = i4 with noconstant(0)
declare v_i           = i4 with noconstant(0)
declare v_key8        = vc with noconstant("")
declare v_count_str   = vc with noconstant("")
declare v_count_i     = i4 with noconstant(0)
declare v_title       = vc with noconstant(""), maxlen=1000
declare v_strip       = vc with noconstant(""), maxlen=65534
declare v_med_dot_total = i4 with noconstant(0)
declare v_row_cnt     = i4 with noconstant(0)
declare v_all_days_list = vc with noconstant(""), maxlen=65534
declare v_sum_strip     = vc with noconstant(""), maxlen=65534
declare v_spacer_strip  = vc with noconstant(""), maxlen=65534
declare v_findpos          = i4 with noconstant(0)
declare v_after          = vc with noconstant(""), maxlen=65534
declare v_endpos           = i4 with noconstant(0)
declare v_detail_str       = vc with noconstant("")
declare v_pipe_pos         = i4 with noconstant(0)
declare v_indication       = vc with noconstant(""), maxlen=255
declare v_discontinue_rsn = vc with noconstant(""), maxlen=255
declare v_drug        = vc with noconstant("")
declare v_dose        = f8 with noconstant(0.0)
declare v_unit        = vc with noconstant("")
declare v_ind         = vc with noconstant("")
declare v_start       = vc with noconstant("")
declare v_stat        = vc with noconstant("")
declare v_sdt         = vc with noconstant("")
declare v_oid         = vc with noconstant("")
declare v_dot         = i4 with noconstant(0)
declare v_table_rows  = vc with noconstant(""), maxlen=65534
declare v_low_dt      = dq8 with noconstant(null)
declare v_high_now_dt = dq8 with noconstant(null)
declare v_begin_dt_str= vc with noconstant("")
declare v_end_dt_str  = vc with noconstant("")
declare v_today       = dq8 with noconstant(0)
declare v_token       = vc with noconstant("</tr>")
declare v_toklen      = i4 with noconstant(5)
declare v_pos         = i4 with noconstant(0)
declare v_len         = i4 with noconstant(0)
declare v_seglen      = i4 with noconstant(0)
declare v_rowseg      = vc with noconstant(""), maxlen=65534
declare v_chunk       = i4 with constant(32000)

select into "nl:"
  day_dt = cnvtdate(ce.performed_dt_tm)
, name_full = p.name_full_formatted
, pa.alias
, e.arrive_dt_tm
from
  person p, person_alias pa, encounter e, clinical_event ce, ce_event_order_link cl,
  med_admin_event m, orders o, order_catalog oc, order_catalog_synonym ocs,
  code_value_event_r cr, order_entry_format oe
plan p where p.person_id = CNVTREAL($patient_id)
join pa where pa.person_id = p.person_id and pa.person_alias_type_cd = 10.00
join e where e.person_id = p.person_id
join ce where ce.person_id = p.person_id
  and ce.performed_dt_tm between cnvtdatetime(curdate-$LOOKBACK,0) and cnvtdatetime(curdate,235959)
join m where m.event_id = ce.event_id
  and m.event_type_cd = value(uar_get_code_by("MEANING",4000040,"TASKCOMPLETE"))
join o where o.order_id = m.template_order_id
join cl where cl.event_id = ce.event_id
join cr where cr.event_cd = ce.event_cd
join oc where oc.catalog_cd = cr.parent_cd and oc.catalog_type_cd = 2516
join ocs where ocs.catalog_cd = oc.catalog_cd
join oe where ocs.oe_format_id = oe.oe_format_id
  and oe.catalog_type_cd = 2516.00 and oe.oe_format_id in (14497910, 14498121)
order by day_dt

head report
  v_first = 1
  v_mrn   = pa.alias
  v_name  = name_full
  v_admit_dt = format(e.arrive_dt_tm,"DD/MM/YYYY;;d")
  v_low_dt   = cnvtdatetime(cnvtdate(e.arrive_dt_tm),0)
  v_high_now_dt = cnvtdatetime(curdate,0)
  v_today      = cnvtdate(curdate)
  v_los      = cnvtstring((datetimediff(v_high_now_dt,v_low_dt,7))+1)
  v_lookback = cnvtstring($LOOKBACK)
  v_begin_dt_str = format((curdate-$LOOKBACK),"DD/MM/YYYY;;d")
  v_end_dt_str   = format(curdate,"DD/MM/YYYY;;d")

head day_dt
  if (v_first = 1)
    v_min_dt = day_dt
    v_max_dt = day_dt
    v_first  = 0
  else
    if (day_dt < v_min_dt) v_min_dt = day_dt endif
    if (day_dt > v_max_dt) v_max_dt = day_dt endif
  endif
with nocounter

if (v_first = 0)
  if (v_max_dt < v_today) set v_max_dt = v_today endif
  if (v_max_dt > v_today) set v_max_dt = v_today endif
endif

if (v_first = 1)
  set v_days = 0
  set v_axis_html = ""
  set v_chart_rows = '<tr><td colspan="3">No administrations found in the selected window.</td></tr>'
  set v_header_html = ""
else
  set v_days = (datetimediff(v_max_dt, v_min_dt, 7)) + 1
  set v_axis_html = concat('<div class="axisbar"><div>Date range: ', format(v_min_dt,"DD-MMM-YYYY;;D"), ' to ', format(v_max_dt,"DD-MMM-YYYY;;D"), '</div></div>')
  set v_header_html = ''
  set v_i = 0
  while (v_i < v_days)
    if (v_i = 0 or format(v_min_dt + v_i,"MM;;D") != format(v_min_dt + v_i - 1,"MM;;D"))
      set v_header_html = concat(v_header_html, '<span class="tick" title="', format(v_min_dt + v_i,"YYYY-MM-DD;;D"), '"><span class="mo">', format(v_min_dt + v_i,"MMM;;D"), '</span>', format(v_min_dt + v_i,"DD;;D"), '</span>')
    else
      set v_header_html = concat(v_header_html, '<span class="tick" title="', format(v_min_dt + v_i,"YYYY-MM-DD;;D"), '">', format(v_min_dt + v_i,"DD;;D"), '</span>')
    endif
    set v_i = v_i + 1
  endwhile
endif

select into "nl:"
  oc.primary_mnemonic, m.event_id, mdy = format(ce.performed_dt_tm, "YYYYMMDD;;D")
, indication = substring(1,60,trim(od_indication.oe_field_display_value))
, discontinue_reason = substring(1,60,trim(od_dcreason.oe_field_display_value))
from
  person p, clinical_event ce, med_admin_event m, orders o,
  ce_event_order_link cl, code_value_event_r cr, order_catalog oc,
  order_catalog_synonym ocs, order_entry_format oe,
  order_detail od_indication, order_detail od_dcreason
plan p where p.person_id = CNVTREAL($patient_id)
join ce where ce.person_id = p.person_id
  and ce.performed_dt_tm between cnvtdatetime(curdate-$LOOKBACK,0) and cnvtdatetime(curdate,235959)
join m where m.event_id = ce.event_id
  and m.event_type_cd = value(uar_get_code_by("MEANING",4000040,"TASKCOMPLETE"))
join o where o.order_id = m.template_order_id
join cl where cl.event_id = ce.event_id
join cr where cr.event_cd = ce.event_cd
join oc where oc.catalog_cd = cr.parent_cd and oc.catalog_type_cd = 2516
join ocs where ocs.catalog_cd = oc.catalog_cd
join oe where oe.oe_format_id = ocs.oe_format_id
  and oe.oe_format_id in (14497910, 14498121)
join od_indication where od_indication.order_id = outerjoin(o.order_id)
  and od_indication.oe_field_meaning = outerjoin("INDICATION")
join od_dcreason where od_dcreason.order_id = outerjoin(o.order_id)
  and od_dcreason.oe_field_meaning = outerjoin("DCREASON")
order by cnvtupper(oc.primary_mnemonic), mdy, m.event_id

head report
  v_curr_med = ""
  v_dates_kv = ""
  v_details_kv = ""
  v_all_days_list = "" 
  v_row_cnt = 0

head oc.primary_mnemonic
  v_curr_med = oc.primary_mnemonic
  v_dates_kv = ""
  v_details_kv = ""
  v_med_dot_total = 0 

head mdy
  v_cnt_day = 0

head m.event_id
  v_cnt_day = v_cnt_day + 1

foot mdy
  v_dates_kv = concat(v_dates_kv, "~", mdy, ":", cnvtstring(v_cnt_day), "~")
  v_details_kv = concat(v_details_kv, "~", mdy, ":", indication, "|", discontinue_reason, "~")
  v_med_dot_total = v_med_dot_total + 1 
  if (findstring(concat("~", mdy, "~"), v_all_days_list) = 0)
    v_all_days_list = concat(v_all_days_list, "~", mdy, "~")
  endif

foot oc.primary_mnemonic
  if (v_days > 0)
    v_row_cnt = v_row_cnt + 1
    v_strip = ""
    v_i = 0
    while (v_i < v_days)
      v_key8 = format(v_min_dt + v_i, "YYYYMMDD;;D")
      v_findpos = findstring(concat("~", v_key8, ":"), v_dates_kv)
      if (v_findpos > 0)
        v_after  = substring(v_findpos + 10, textlen(v_dates_kv) - (v_findpos + 9), v_dates_kv)
        v_endpos = findstring("~", v_after)
        if (v_endpos > 0) v_count_str = substring(1, v_endpos - 1, v_after)
        else v_count_str = v_after
        endif
      else
        v_count_str = ""
      endif
      v_count_i = cnvtint(v_count_str)
      if (v_count_i > 0)
        v_strip = concat(v_strip, '<span class="cell on">', trim(v_count_str), '</span>')
      else
        v_strip = concat(v_strip, '<span class="cell"></span>')
      endif
      v_i = v_i + 1
    endwhile
    v_chart_rows = concat(v_chart_rows, '<tr', if(mod(v_row_cnt, 2) = 0) ' class="even"' else '' endif, '><td class="label medname sticky-med">', v_curr_med, '</td><td class="label dot-val sticky-dot"><span class="pill">', cnvtstring(v_med_dot_total), '</span></td><td><div class="strip">', v_strip, '</div></td></tr>')
  endif

foot report
  if (v_days > 0)
      v_sum_strip = ""
      v_spacer_strip = "" 
      v_i = 0
      while (v_i < v_days)
          v_key8 = format(v_min_dt + v_i, "YYYYMMDD;;D")
          if (findstring(concat("~", v_key8, "~"), v_all_days_list) > 0)
              v_sum_strip = concat(v_sum_strip, '<span class="cell sum-yes"></span>')
          else
              v_sum_strip = concat(v_sum_strip, '<span class="cell sum-no"></span>')
          endif
          v_i = v_i + 1
      endwhile
      v_chart_rows = concat(v_chart_rows, '<tr class="summary-row"><td class="label sticky-med">Antimicrobial Summary</td><td class="label sticky-dot"></td><td><div class="strip">', v_sum_strip, '</div></td></tr>')
  endif
with nocounter


; =============================================================================
; 3.5 SINGLE PATIENT ACUITY SCORE CALCULATION
; =============================================================================
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

    1 reasons[*]
        2 text = vc
        2 points = i4
        2 detail_html = vc
)

; Gather Active Problems
SELECT INTO "NL:"
    NOM = N.SOURCE_STRING, UNOM = CNVTUPPER(N.SOURCE_STRING), DT_STR = FORMAT(P.ONSET_DT_TM, "DD/MM/YYYY")
FROM PROBLEM P, NOMENCLATURE N
PLAN P WHERE P.PERSON_ID = CNVTREAL($patient_id) AND P.ACTIVE_IND = 1 AND P.LIFE_CYCLE_STATUS_CD = 3301.00
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
    NOM = N.SOURCE_STRING, UNOM = CNVTUPPER(N.SOURCE_STRING), DT_STR = FORMAT(D.DIAG_DT_TM, "DD/MM/YYYY")
FROM DIAGNOSIS D, NOMENCLATURE N
PLAN D WHERE D.PERSON_ID = CNVTREAL($patient_id) AND D.ACTIVE_IND = 1
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
    MNEM = O.ORDER_MNEMONIC, UNOM = CNVTUPPER(O.ORDER_MNEMONIC)
    , DT_STR = FORMAT(O.CURRENT_START_DT_TM, "DD/MM/YYYY HH:MM"), SDL = O.SIMPLIFIED_DISPLAY_LINE
FROM ORDERS O, ACT_PW_COMP APC
PLAN O WHERE O.PERSON_ID = CNVTREAL($patient_id) AND O.ORDER_STATUS_CD = 2550.00 AND O.CATALOG_TYPE_CD = 2516.00 
    AND O.ORIG_ORD_AS_FLAG = 0 AND O.TEMPLATE_ORDER_ID = 0
JOIN APC WHERE APC.PARENT_ENTITY_ID = OUTERJOIN(O.ORDER_ID) AND APC.PARENT_ENTITY_NAME = OUTERJOIN("ORDERS") AND APC.ACTIVE_IND = OUTERJOIN(1)
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

IF (rec_acuity->poly_count >= 10) SET rec_acuity->flag_poly_severe = 1
ELSEIF (rec_acuity->poly_count >= 5) SET rec_acuity->flag_poly_mod = 1
ENDIF

; Check Clinical Events
SELECT INTO "NL:"
    VAL = CE.RESULT_VAL, TITLE = UAR_GET_CODE_DISPLAY(CE.EVENT_CD), DT_STR = FORMAT(CE.PERFORMED_DT_TM, "DD/MM/YYYY HH:MM")
FROM CLINICAL_EVENT CE
PLAN CE WHERE CE.PERSON_ID = CNVTREAL($patient_id)
    AND CE.EVENT_CD IN (15071366.00, 82546829.00, 15083551.00, 19995695.00) AND CE.VALID_UNTIL_DT_TM > SYSDATE
    AND CE.PERFORMED_DT_TM > CNVTLOOKBEHIND("7,D") AND CE.RESULT_STATUS_CD IN (25, 34, 35)
DETAIL
    IF (CE.EVENT_CD = 15071366.00)
        rec_acuity->flag_transfusion = 1
        rec_acuity->det_transfusion = CONCAT(rec_acuity->det_transfusion, "<div class='trigger-det-item'><b>", TRIM(TITLE), "</b>: ", TRIM(VAL), " (", DT_STR, ")</div>")
    ELSEIF (CE.EVENT_CD IN (82546829.00, 15083551.00, 19995695.00) AND CNVTREAL(VAL) > 1000.0)
        rec_acuity->flag_ebl = 1
        rec_acuity->det_ebl = CONCAT(rec_acuity->det_ebl, "<div class='trigger-det-item'><b>", TRIM(TITLE), "</b>: ", TRIM(VAL), " ml (", DT_STR, ")</div>")
    ENDIF
WITH NOCOUNTER

; Tally Single Patient Final Score
IF (rec_acuity->flag_transfusion = 1 OR rec_acuity->flag_ebl = 1)
    SET rec_acuity->score = rec_acuity->score + 3
    SET rec_acuity->reason_cnt = rec_acuity->reason_cnt + 1
    SET stat = alterlist(rec_acuity->reasons, rec_acuity->reason_cnt)
    SET rec_acuity->reasons[rec_acuity->reason_cnt].text = "Massive Haemorrhage (>1000ml EBL) or Transfusion"
    SET rec_acuity->reasons[rec_acuity->reason_cnt].points = 3
    SET rec_acuity->reasons[rec_acuity->reason_cnt].detail_html = CONCAT(rec_acuity->det_transfusion, rec_acuity->det_ebl)
ENDIF
IF (rec_acuity->flag_preeclampsia = 1)
    SET rec_acuity->score = rec_acuity->score + 3
    SET rec_acuity->reason_cnt = rec_acuity->reason_cnt + 1
    SET stat = alterlist(rec_acuity->reasons, rec_acuity->reason_cnt)
    SET rec_acuity->reasons[rec_acuity->reason_cnt].text = "Active Diagnosis/Problem: Pre-Eclampsia"
    SET rec_acuity->reasons[rec_acuity->reason_cnt].points = 3
    SET rec_acuity->reasons[rec_acuity->reason_cnt].detail_html = rec_acuity->det_preeclampsia
ENDIF
IF (rec_acuity->flag_dvt = 1)
    SET rec_acuity->score = rec_acuity->score + 3
    SET rec_acuity->reason_cnt = rec_acuity->reason_cnt + 1
    SET stat = alterlist(rec_acuity->reasons, rec_acuity->reason_cnt)
    SET rec_acuity->reasons[rec_acuity->reason_cnt].text = "Active Diagnosis/Problem: DVT or Pulmonary Embolism"
    SET rec_acuity->reasons[rec_acuity->reason_cnt].points = 3
    SET rec_acuity->reasons[rec_acuity->reason_cnt].detail_html = rec_acuity->det_dvt
ENDIF
IF (rec_acuity->flag_epilepsy = 1)
    SET rec_acuity->score = rec_acuity->score + 3
    SET rec_acuity->reason_cnt = rec_acuity->reason_cnt + 1
    SET stat = alterlist(rec_acuity->reasons, rec_acuity->reason_cnt)
    SET rec_acuity->reasons[rec_acuity->reason_cnt].text = "Active Diagnosis/Problem: Epilepsy/Seizure Disorder"
    SET rec_acuity->reasons[rec_acuity->reason_cnt].points = 3
    SET rec_acuity->reasons[rec_acuity->reason_cnt].detail_html = rec_acuity->det_epilepsy
ENDIF
IF (rec_acuity->flag_insulin = 1)
    SET rec_acuity->score = rec_acuity->score + 3
    SET rec_acuity->reason_cnt = rec_acuity->reason_cnt + 1
    SET stat = alterlist(rec_acuity->reasons, rec_acuity->reason_cnt)
    SET rec_acuity->reasons[rec_acuity->reason_cnt].text = "High Alert Med: Insulin"
    SET rec_acuity->reasons[rec_acuity->reason_cnt].points = 3
    SET rec_acuity->reasons[rec_acuity->reason_cnt].detail_html = rec_acuity->det_insulin
ENDIF
IF (rec_acuity->flag_antiepileptic = 1)
    SET rec_acuity->score = rec_acuity->score + 3
    SET rec_acuity->reason_cnt = rec_acuity->reason_cnt + 1
    SET stat = alterlist(rec_acuity->reasons, rec_acuity->reason_cnt)
    SET rec_acuity->reasons[rec_acuity->reason_cnt].text = "High Alert Med: Antiepileptic"
    SET rec_acuity->reasons[rec_acuity->reason_cnt].points = 3
    SET rec_acuity->reasons[rec_acuity->reason_cnt].detail_html = rec_acuity->det_antiepileptic
ENDIF
IF (rec_acuity->flag_poly_severe = 1)
    SET rec_acuity->score = rec_acuity->score + 3
    SET rec_acuity->reason_cnt = rec_acuity->reason_cnt + 1
    SET stat = alterlist(rec_acuity->reasons, rec_acuity->reason_cnt)
    SET rec_acuity->reasons[rec_acuity->reason_cnt].text = CONCAT("Severe Polypharmacy (", TRIM(CNVTSTRING(rec_acuity->poly_count)), " active meds)")
    SET rec_acuity->reasons[rec_acuity->reason_cnt].points = 3
    SET rec_acuity->reasons[rec_acuity->reason_cnt].detail_html = rec_acuity->det_poly
ENDIF
IF (rec_acuity->flag_anticoag = 1)
    SET rec_acuity->score = rec_acuity->score + 2
    SET rec_acuity->reason_cnt = rec_acuity->reason_cnt + 1
    SET stat = alterlist(rec_acuity->reasons, rec_acuity->reason_cnt)
    SET rec_acuity->reasons[rec_acuity->reason_cnt].text = "Targeted Med: Anticoagulant (LMWH/Heparin)"
    SET rec_acuity->reasons[rec_acuity->reason_cnt].points = 2
    SET rec_acuity->reasons[rec_acuity->reason_cnt].detail_html = rec_acuity->det_anticoag
ENDIF
IF (rec_acuity->flag_antihypertensive = 1)
    SET rec_acuity->score = rec_acuity->score + 2
    SET rec_acuity->reason_cnt = rec_acuity->reason_cnt + 1
    SET stat = alterlist(rec_acuity->reasons, rec_acuity->reason_cnt)
    SET rec_acuity->reasons[rec_acuity->reason_cnt].text = "Targeted Med: Antihypertensive"
    SET rec_acuity->reasons[rec_acuity->reason_cnt].points = 2
    SET rec_acuity->reasons[rec_acuity->reason_cnt].detail_html = rec_acuity->det_antihypertensive
ENDIF
IF (rec_acuity->flag_neuraxial = 1)
    SET rec_acuity->score = rec_acuity->score + 1
    SET rec_acuity->reason_cnt = rec_acuity->reason_cnt + 1
    SET stat = alterlist(rec_acuity->reasons, rec_acuity->reason_cnt)
    SET rec_acuity->reasons[rec_acuity->reason_cnt].text = "Medication: Neuraxial/Epidural Infusion"
    SET rec_acuity->reasons[rec_acuity->reason_cnt].points = 1
    SET rec_acuity->reasons[rec_acuity->reason_cnt].detail_html = rec_acuity->det_neuraxial
ENDIF
IF (rec_acuity->flag_poly_mod = 1)
    SET rec_acuity->score = rec_acuity->score + 1
    SET rec_acuity->reason_cnt = rec_acuity->reason_cnt + 1
    SET stat = alterlist(rec_acuity->reasons, rec_acuity->reason_cnt)
    SET rec_acuity->reasons[rec_acuity->reason_cnt].text = CONCAT("Moderate Polypharmacy (", TRIM(CNVTSTRING(rec_acuity->poly_count)), " active meds)")
    SET rec_acuity->reasons[rec_acuity->reason_cnt].points = 1
    SET rec_acuity->reasons[rec_acuity->reason_cnt].detail_html = rec_acuity->det_poly
ENDIF

IF (rec_acuity->score >= 3) SET rec_acuity->color = "Red"
ELSEIF (rec_acuity->score >= 1) SET rec_acuity->color = "Amber"
ELSE SET rec_acuity->color = "Green"
ENDIF

; =============================================================================
; 3.6 WARD-LEVEL TRIAGE LIST LOOP (Memory & Split-Table Optimized)
; =============================================================================
DECLARE curr_ward_cd = f8 WITH noconstant(0.0)
DECLARE curr_ward_disp = vc WITH noconstant("")
DECLARE v_ward_rows = vc WITH noconstant(""), maxlen=65534

DECLARE pat_idx = i4 WITH noconstant(0)
DECLARE idx = i4 WITH noconstant(0)
DECLARE t_score = i4 WITH noconstant(0)
DECLARE t_triggers = c1000 WITH noconstant("")
DECLARE num_pats = i4 WITH noconstant(0)

RECORD rec_cohort (
    1 cnt = i4
    1 list[*]
        2 person_id = f8
        2 encntr_id = f8
        2 name = vc
        2 room_bed = vc
        2 score = i4
        2 color = vc
        2 summary = c1000  ; <-- FIXED: Explicit memory sizing to prevent truncation
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

; 1. Get Current Ward
SELECT INTO "NL:"
FROM ENCOUNTER E
PLAN E WHERE E.ENCNTR_ID = CNVTREAL($encounter_id)
DETAIL
    curr_ward_cd = E.LOC_NURSE_UNIT_CD
    curr_ward_disp = UAR_GET_CODE_DISPLAY(E.LOC_NURSE_UNIT_CD)
WITH NOCOUNTER

IF (curr_ward_cd > 0.0)
    ; 2. Populate Active Patients on this Ward (Excluding Babies and Test Patients)
    SELECT INTO "NL:"
    FROM ENCOUNTER E, PERSON P
    PLAN E WHERE E.LOC_NURSE_UNIT_CD = curr_ward_cd 
        AND E.ACTIVE_IND = 1 
        AND E.ENCNTR_STATUS_CD = 854.00 ; STRICTLY ACTIVE ONLY
    JOIN P WHERE P.PERSON_ID = E.PERSON_ID 
        AND P.ACTIVE_IND = 1
        AND P.BIRTH_DT_TM < CNVTLOOKBEHIND("10,Y") ; Exclude patients under 10 years old (Babies)
        AND FINDSTRING("ZZZTEST", CNVTUPPER(P.NAME_FULL_FORMATTED)) = 0 ; Exclude test patients
    ORDER BY E.LOC_ROOM_CD, E.LOC_BED_CD
    DETAIL
        rec_cohort->cnt = rec_cohort->cnt + 1
        stat = alterlist(rec_cohort->list, rec_cohort->cnt)
        rec_cohort->list[rec_cohort->cnt].person_id = P.PERSON_ID
        rec_cohort->list[rec_cohort->cnt].encntr_id = E.ENCNTR_ID
        rec_cohort->list[rec_cohort->cnt].name = P.NAME_FULL_FORMATTED
        rec_cohort->list[rec_cohort->cnt].room_bed = CONCAT(TRIM(UAR_GET_CODE_DISPLAY(E.LOC_ROOM_CD)), "-", TRIM(UAR_GET_CODE_DISPLAY(E.LOC_BED_CD)))
    WITH NOCOUNTER

    SET num_pats = rec_cohort->cnt

    IF (num_pats > 0)
        ; 3. Bulk Evaluate Problems using EXPAND
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

        ; 4. Bulk Evaluate Diagnoses using EXPAND
        SELECT INTO "NL:"
            UNOM = CNVTUPPER(N.SOURCE_STRING)
        FROM DIAGNOSIS D, NOMENCLATURE N
        PLAN D WHERE EXPAND(pat_idx, 1, num_pats, D.PERSON_ID, rec_cohort->list[pat_idx].person_id)
            AND D.ACTIVE_IND = 1
        JOIN N WHERE N.NOMENCLATURE_ID = D.NOMENCLATURE_ID
        DETAIL
            idx = LOCATEVAL(pat_idx, 1, num_pats, D.PERSON_ID, rec_cohort->list[pat_idx].person_id)
            IF (idx > 0)
                IF (FINDSTRING("PRE-ECLAMPSIA", UNOM) > 0 OR FINDSTRING("PREECLAMPSIA", UNOM) > 0) rec_cohort->list[idx].flag_preeclampsia = 1
                ELSEIF (FINDSTRING("DEEP VEIN THROMBOSIS", UNOM) > 0 OR FINDSTRING("PULMONARY EMBOLISM", UNOM) > 0 OR FINDSTRING("DVT", UNOM) > 0) rec_cohort->list[idx].flag_dvt = 1
                ELSEIF (FINDSTRING("EPILEPSY", UNOM) > 0 OR FINDSTRING("SEIZURE", UNOM) > 0) rec_cohort->list[idx].flag_epilepsy = 1
                ENDIF
            ENDIF
        WITH NOCOUNTER

        ; 5. Bulk Evaluate Orders using EXPAND (With PowerPlan PRN Exclusions)
        SELECT INTO "NL:"
            UNOM = CNVTUPPER(O.ORDER_MNEMONIC)
        FROM ORDERS O, ACT_PW_COMP APC
        PLAN O WHERE EXPAND(pat_idx, 1, num_pats, O.PERSON_ID, rec_cohort->list[pat_idx].person_id)
            AND O.ORDER_STATUS_CD = 2550.00 AND O.CATALOG_TYPE_CD = 2516.00 AND O.ORIG_ORD_AS_FLAG = 0 AND O.TEMPLATE_ORDER_ID = 0
        JOIN APC WHERE APC.PARENT_ENTITY_ID = OUTERJOIN(O.ORDER_ID) AND APC.PARENT_ENTITY_NAME = OUTERJOIN("ORDERS") AND APC.ACTIVE_IND = OUTERJOIN(1)
        ORDER BY O.ORDER_ID
        HEAD O.ORDER_ID
            idx = LOCATEVAL(pat_idx, 1, num_pats, O.PERSON_ID, rec_cohort->list[pat_idx].person_id)
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

        ; 6. Bulk Evaluate Clinical Events using EXPAND
        SELECT INTO "NL:"
        FROM CLINICAL_EVENT CE
        PLAN CE WHERE EXPAND(pat_idx, 1, num_pats, CE.PERSON_ID, rec_cohort->list[pat_idx].person_id)
            AND CE.EVENT_CD IN (15071366.00, 82546829.00, 15083551.00, 19995695.00) 
            AND CE.VALID_UNTIL_DT_TM > SYSDATE AND CE.PERFORMED_DT_TM > CNVTLOOKBEHIND("7,D") AND CE.RESULT_STATUS_CD IN (25, 34, 35)
        DETAIL
            idx = LOCATEVAL(pat_idx, 1, num_pats, CE.PERSON_ID, rec_cohort->list[pat_idx].person_id)
            IF (idx > 0)
                IF (CE.EVENT_CD = 15071366.00) rec_cohort->list[idx].flag_transfusion = 1
                ELSEIF (CNVTREAL(CE.RESULT_VAL) > 1000.0) rec_cohort->list[idx].flag_ebl = 1
                ENDIF
            ENDIF
        WITH NOCOUNTER

        ; 7. Calculate Final Scores in Memory
        FOR (pat_idx = 1 TO num_pats)
            SET t_score = 0
            SET t_triggers = ""

            IF (rec_cohort->list[pat_idx].poly_count >= 10) SET rec_cohort->list[pat_idx].flag_poly_severe = 1
            ELSEIF (rec_cohort->list[pat_idx].poly_count >= 5) SET rec_cohort->list[pat_idx].flag_poly_mod = 1
            ENDIF

            IF (rec_cohort->list[pat_idx].flag_transfusion = 1 OR rec_cohort->list[pat_idx].flag_ebl = 1) SET t_score = t_score + 3 SET t_triggers = CONCAT(TRIM(t_triggers), "Haemorrhage/Transfusion; ") ENDIF
            IF (rec_cohort->list[pat_idx].flag_preeclampsia = 1) SET t_score = t_score + 3 SET t_triggers = CONCAT(TRIM(t_triggers), "Pre-Eclampsia; ") ENDIF
            IF (rec_cohort->list[pat_idx].flag_dvt = 1) SET t_score = t_score + 3 SET t_triggers = CONCAT(TRIM(t_triggers), "VTE/DVT; ") ENDIF
            IF (rec_cohort->list[pat_idx].flag_epilepsy = 1) SET t_score = t_score + 3 SET t_triggers = CONCAT(TRIM(t_triggers), "Epilepsy; ") ENDIF
            IF (rec_cohort->list[pat_idx].flag_insulin = 1) SET t_score = t_score + 3 SET t_triggers = CONCAT(TRIM(t_triggers), "Insulin; ") ENDIF
            IF (rec_cohort->list[pat_idx].flag_antiepileptic = 1) SET t_score = t_score + 3 SET t_triggers = CONCAT(TRIM(t_triggers), "Antiepileptic; ") ENDIF
            IF (rec_cohort->list[pat_idx].flag_poly_severe = 1) SET t_score = t_score + 3 SET t_triggers = CONCAT(TRIM(t_triggers), "Severe Polypharmacy; ") ENDIF
            IF (rec_cohort->list[pat_idx].flag_anticoag = 1) SET t_score = t_score + 2 SET t_triggers = CONCAT(TRIM(t_triggers), "Anticoagulant; ") ENDIF
            IF (rec_cohort->list[pat_idx].flag_antihypertensive = 1) SET t_score = t_score + 2 SET t_triggers = CONCAT(TRIM(t_triggers), "Antihypertensive; ") ENDIF
            IF (rec_cohort->list[pat_idx].flag_neuraxial = 1) SET t_score = t_score + 1 SET t_triggers = CONCAT(TRIM(t_triggers), "Neuraxial Infusion; ") ENDIF
            IF (rec_cohort->list[pat_idx].flag_poly_mod = 1) SET t_score = t_score + 1 SET t_triggers = CONCAT(TRIM(t_triggers), "Mod Polypharmacy; ") ENDIF

            SET rec_cohort->list[pat_idx].score = t_score
            IF (t_score >= 3) SET rec_cohort->list[pat_idx].color = "Red"
            ELSEIF (t_score >= 1) SET rec_cohort->list[pat_idx].color = "Amber"
            ELSE SET rec_cohort->list[pat_idx].color = "Green" ENDIF

            IF (TEXTLEN(TRIM(t_triggers)) > 0) SET rec_cohort->list[pat_idx].summary = SUBSTRING(1, TEXTLEN(TRIM(t_triggers))-1, TRIM(t_triggers))
            ELSE SET rec_cohort->list[pat_idx].summary = "Routine (Low Risk)" ENDIF
        ENDFOR

        ; 8. Build HTML Rows (Ordered by Score Descending)
        SELECT INTO "NL:"
            PAT_SCORE = rec_cohort->list[D.SEQ].score
        FROM (DUMMYT D WITH SEQ = VALUE(num_pats))
        PLAN D
        ORDER BY PAT_SCORE DESC, D.SEQ
        DETAIL
            ; FIXED: Hardcoded TD widths to align perfectly with the split header
            v_ward_rows = CONCAT(v_ward_rows, 
                "<tr>",
                "<td width='15%'><b>", TRIM(rec_cohort->list[D.SEQ].room_bed), "</b></td>",
                "<td width='25%'><a class='patient-link' href='javascript:APPLINK(0,^Powerchart.exe^,^/PERSONID=", TRIM(CNVTSTRING(rec_cohort->list[D.SEQ].person_id)), 
                " /ENCNTRID=", TRIM(CNVTSTRING(rec_cohort->list[D.SEQ].encntr_id)), "^)'>", TRIM(rec_cohort->list[D.SEQ].name), "</a></td>",
                "<td width='15%'><span class='badge-", TRIM(rec_cohort->list[D.SEQ].color), "'>Score: ", TRIM(CNVTSTRING(rec_cohort->list[D.SEQ].score)), "</span></td>",
                "<td width='45%'>", TRIM(rec_cohort->list[D.SEQ].summary), "</td>",
                "</tr>"
            )
        WITH NOCOUNTER
    ELSE
        SET v_ward_rows = "<tr><td colspan='4' style='text-align:center; padding: 20px;'>No active maternity patients found on this ward.</td></tr>"
    ENDIF

ELSE
    SET v_ward_rows = "<tr><td colspan='4' style='text-align:center; padding: 20px;'><b>Cannot generate triage list:</b> Patient is not admitted to a specific nursing ward.</td></tr>"
ENDIF
; =============================================================================
; 4. MAIN MEDICATION QUERY
; =============================================================================
SELECT DISTINCT INTO $OUTDEV
    P_NAME   = P.NAME_FULL_FORMATTED
    , MRN    = PA.ALIAS
    , ORDER_ID   = O.ORDER_ID
    , MNEMONIC   = O.ORDER_MNEMONIC
    , CDL        = O.CLINICAL_DISPLAY_LINE
    , START_DT   = FORMAT(O.CURRENT_START_DT_TM, "DD/MM/YYYY HH:MM")
    , DISP_CAT   = NULLVAL(OD_CAT.OE_FIELD_DISPLAY_VALUE, " ")
    , ORDER_FORM = NULLVAL(OD_FORM.OE_FIELD_DISPLAY_VALUE, " ")
FROM
    DUMMYT D
    , PERSON P
    , PERSON_ALIAS PA
    , ORDERS O
    , ORDER_DETAIL OD_CAT
    , ORDER_DETAIL OD_FORM

PLAN D
JOIN P WHERE P.PERSON_ID = outerjoin(CNVTREAL($patient_id))
JOIN PA WHERE PA.PERSON_ID = outerjoin(P.PERSON_ID)
    AND PA.PERSON_ALIAS_TYPE_CD = outerjoin(10.00)
    AND PA.END_EFFECTIVE_DT_TM > outerjoin(SYSDATE)
JOIN O WHERE O.PERSON_ID = outerjoin(P.PERSON_ID)
    AND O.ORDER_STATUS_CD = outerjoin(2550.00)
    AND O.ACTIVE_IND = outerjoin(1)
    AND O.ORIG_ORDER_DT_TM > outerjoin(CNVTLOOKBEHIND("400,D", CNVTDATETIME(CURDATE,curtime)))
    AND O.TEMPLATE_ORDER_ID = outerjoin(0)
JOIN OD_CAT WHERE OD_CAT.ORDER_ID = outerjoin(O.ORDER_ID)
    AND OD_CAT.OE_FIELD_MEANING_ID = outerjoin(2007)
JOIN OD_FORM WHERE OD_FORM.ORDER_ID = outerjoin(O.ORDER_ID)
    AND OD_FORM.OE_FIELD_MEANING_ID = outerjoin(2014)
ORDER BY
    D.SEQ
    , O.ORDER_MNEMONIC

; =============================================================================
; 5. HTML OUTPUT
; =============================================================================
HEAD REPORT
    ROW + 1 call print(^<!DOCTYPE html>^)
    ROW + 1 call print(^<html><head>^)
    ROW + 1 call print(^<meta http-equiv='X-UA-Compatible' content='IE=edge'>^)
    ROW + 1 call print(^<META content='CCLLINK' name='discern'>^)

    ROW + 1 call print(^<script>^)
    ROW + 1 call print(concat(^var totalBlobs = ^, TRIM(CNVTSTRING(size(rec_blob->list, 5))), ^;^))
    ROW + 1 call print(^var currentBlob = 1;^)
    
    ROW + 1 call print(^function resizeLayout() {^)
    ROW + 1 call print(^  var h = document.body.clientHeight - 90;^)
    ROW + 1 call print(^  if (h < 300) h = 300;^)
    
    ; Restored explicit, safe resizing for GP and DOT tabs
    ROW + 1 call print(^  var side = document.getElementById('scroll-side');^)
    ROW + 1 call print(^  var main = document.getElementById('scroll-main');^)
    ROW + 1 call print(^  var table = document.getElementById('gp-table');^)
    ROW + 1 call print(^  if(table) table.style.height = h + 'px';^)
    ROW + 1 call print(^  if(side) side.style.height = h + 'px';^)
    ROW + 1 call print(^  if(main) main.style.height = (h - 32) + 'px';^)
    
    ROW + 1 call print(^  var medContainer = document.getElementById('med-container');^)
    ROW + 1 call print(^  if(medContainer) medContainer.style.height = h + 'px';^)
    ROW + 1 call print(^  var dotView = document.getElementById('dot-view');^)
    ROW + 1 call print(^  if(dotView) dotView.style.height = h + 'px';^)
    ROW + 1 call print(^  var acuityView = document.getElementById('acuity-view');^)
    ROW + 1 call print(^  if(acuityView) acuityView.style.height = h + 'px';^)
    
    ; Ward View specific sizing
    ROW + 1 call print(^  var wardView = document.getElementById('ward-view');^)
    ROW + 1 call print(^  if(wardView) wardView.style.height = h + 'px';^)
    ROW + 1 call print(^  var wScroll = document.getElementById('ward-scroll');^)
    ROW + 1 call print(^  if(wScroll) wScroll.style.height = (h - 110) + 'px';^)
    ROW + 1 call print(^}^)
    ROW + 1 call print(^window.onresize = resizeLayout;^)

    ROW + 1 call print(^function goToBlob(idx) {^)
    ROW + 1 call print(^  if (idx < 1 || idx > totalBlobs) return;^)
    ROW + 1 call print(^  currentBlob = idx;^)
    ROW + 1 call print(^  for (var i = 1; i <= totalBlobs; i++) {^)
    ROW + 1 call print(^    var navItem = document.getElementById('nav-' + i);^)
    ROW + 1 call print(^    if (navItem) {^)
    ROW + 1 call print(^      if (i == idx) { navItem.className = 'gp-nav-item active-nav'; }^)
    ROW + 1 call print(^      else { navItem.className = 'gp-nav-item'; }^)
    ROW + 1 call print(^    }^)
    ROW + 1 call print(^  }^)
    ROW + 1 call print(^  window.location.hash = 'blob-' + idx;^)
    ROW + 1 call print(^}^)
    
    ROW + 1 call print(^function nextBlob() { goToBlob(currentBlob + 1); }^)
    ROW + 1 call print(^function prevBlob() { goToBlob(currentBlob - 1); }^)
    
    ROW + 1 call print(^function toggleTrigger(idx) {^)
    ROW + 1 call print(^  var det = document.getElementById('trig-det-' + idx);^)
    ROW + 1 call print(^  var icon = document.getElementById('trig-icon-' + idx);^)
    ROW + 1 call print(^  if(det.style.display === 'block') { det.style.display = 'none'; icon.innerHTML = '+'; }^)
    ROW + 1 call print(^  else { det.style.display = 'block'; icon.innerHTML = '&minus;'; }^)
    ROW + 1 call print(^}^)

    ROW + 1 call print(^function hideAllViews() {^)
    ROW + 1 call print(^  document.getElementById('med-list').className = 'list-view mode-hidden';^)
    ROW + 1 call print(^  document.getElementById('header-row-inf').style.display = 'none';^)
    ROW + 1 call print(^  document.getElementById('gp-blob-view').style.display = 'none';^)
    ROW + 1 call print(^  document.getElementById('med-container').style.display = 'none';^)
    ROW + 1 call print(^  document.getElementById('dot-view').style.display = 'none';^)
    ROW + 1 call print(^  document.getElementById('acuity-view').style.display = 'none';^)
    ROW + 1 call print(^  document.getElementById('ward-view').style.display = 'none';^)
    ROW + 1 call print(^  for(var i=1; i<=7; i++) { var btn = document.getElementById('btn'+i); if(btn) btn.className = 'tab-btn'; }^)
    ROW + 1 call print(^}^)

    ROW + 1 call print(^function showRestricted() { hideAllViews(); document.getElementById('med-list').className = 'list-view mode-restricted'; document.getElementById('med-container').style.display = 'block'; document.getElementById('btn1').className = 'tab-btn active'; resizeLayout(); }^)
    ROW + 1 call print(^function showAll() { hideAllViews(); document.getElementById('med-list').className = 'list-view mode-all'; document.getElementById('med-container').style.display = 'block'; document.getElementById('btn2').className = 'tab-btn active'; resizeLayout(); }^)
    ROW + 1 call print(^function showInfusions() { hideAllViews(); document.getElementById('med-list').className = 'list-view mode-infusion'; document.getElementById('header-row-inf').style.display = 'block'; document.getElementById('med-container').style.display = 'block'; document.getElementById('btn3').className = 'tab-btn active'; resizeLayout(); }^)
    ROW + 1 call print(^function showGP() { hideAllViews(); document.getElementById('gp-blob-view').style.display = 'block'; document.getElementById('btn4').className = 'tab-btn active'; resizeLayout(); }^)
    ROW + 1 call print(^function showHolder2() { hideAllViews(); document.getElementById('dot-view').style.display = 'block'; document.getElementById('btn5').className = 'tab-btn active'; resizeLayout(); }^)
    ROW + 1 call print(^function showAcuity() { hideAllViews(); document.getElementById('acuity-view').style.display = 'block'; document.getElementById('btn6').className = 'tab-btn active'; resizeLayout(); }^)
    ROW + 1 call print(^function showWard() { hideAllViews(); document.getElementById('ward-view').style.display = 'block'; document.getElementById('btn7').className = 'tab-btn active'; resizeLayout(); }^)
    ROW + 1 call print(^</script>^)

    ROW + 1 call print(^<style>^)
    ROW + 1 call print(^body { font-family: Arial, sans-serif; background: #f4f4f4; padding: 6px 10px; color:#333; margin: 0; overflow: hidden; }^)
    ROW + 1 call print(^.pat-header { background: #fff; padding: 6px 10px; font-size: 14px; border: 1px solid #ddd; margin-bottom: 8px; box-shadow: 0 1px 2px rgba(0,0,0,0.05); }^)
    ROW + 1 call print(^.wt-val { color: #0076a8; font-weight: bold; }^)
    ROW + 1 call print(^.wt-label { font-weight: bold; color: #555; }^)
    ROW + 1 call print(^.tab-row { overflow: hidden; border-bottom: 2px solid #ddd; margin-bottom: 8px; width: 100%; }^)
    ROW + 1 call print(^.tab-btn { float: left; padding: 6px 15px; margin-right: 5px; cursor: pointer; background: transparent; border: none; border-bottom: 3px solid transparent; color: #666; font-size: 13px; }^)
    ROW + 1 call print(^.tab-btn:hover { background: #e9ecef; color: #333; }^)
    ROW + 1 call print(^.tab-btn.active { border-bottom: 3px solid #0076a8; color: #000; font-weight: bold; background: transparent; }^)
    ROW + 1 call print(^.content-box { clear: both; background: #fff; padding: 0; border: 1px solid #ddd; height: 500px; overflow-y: auto; }^)
    ROW + 1 call print(^.order-item { padding: 10px; border-bottom: 1px solid #eee; margin: 10px; }^)
    ROW + 1 call print(^.is-restricted { background-color: #fff0f0; border-left: 4px solid #dc3545; }^)
    ROW + 1 call print(^.is-normal { border-left: 4px solid #009668; }^)
    ROW + 1 call print(^.inf-header { display: none; background-color: #f8f9fa; color: #333; padding: 10px; font-weight: bold; border-bottom: 2px solid #ddd; margin: 10px; }^)
    ROW + 1 call print(^.inf-row { background-color: #fff; border-bottom: 1px solid #eee; padding: 10px; overflow: hidden; margin: 0 10px; }^)
    ROW + 1 call print(^.inf-col { float: left; padding: 5px; font-size: 13px; }^)
    ROW + 1 call print(^.print-link { color: #0076a8; text-decoration: none; cursor: pointer; font-weight: bold; }^)
    ROW + 1 call print(^.print-link:hover { text-decoration: underline; }^)
    ROW + 1 call print(^.type-badge { font-size:10px; font-weight:bold; padding:3px 8px; color:white; }^)
    
    ROW + 1 call print(^.gp-sidebar { background: #f8f9fa; border-right: 1px solid #ddd; vertical-align: top; width: 130px; }^)
    ROW + 1 call print(^.gp-content { vertical-align: top; background: #fff; border: 1px solid #ddd; }^)
    ROW + 1 call print(^.gp-content-header { background: #f4f6f8; padding: 3px 8px; border-bottom: 1px solid #ddd; text-align: right; }^)
    ROW + 1 call print(^.nav-btn { background: #fff; border: 1px solid #ccc; padding: 4px 0; cursor: pointer; font-size: 12px; margin-left: 5px; color: #333; font-weight: bold; width: 100px; text-align: center; }^)
    ROW + 1 call print(^.nav-btn:hover { background: #e9ecef; }^)
    ROW + 1 call print(^.gp-scroll-side { overflow-y: auto; overflow-x: hidden; width: 100%; border: 1px solid #ddd; border-right: none; }^)
    ROW + 1 call print(^.gp-scroll-main { overflow-y: auto; overflow-x: hidden; width: 100%; padding: 15px; }^)
    ROW + 1 call print(^.gp-nav-item { display: block; padding: 8px 10px; color: #333; text-decoration: none; font-size: 13px; border-bottom: 1px solid #eee; }^)
    ROW + 1 call print(^.gp-nav-item:hover { background: #e2e6ea; color: #0076a8; }^)
    ROW + 1 call print(^.active-nav { background: #0076a8 !important; color: #fff !important; font-weight: bold; }^)
    ROW + 1 call print(^.blob-record { border: 1px solid #ddd; margin-bottom: 30px; padding: 15px; border-left: 4px solid #6f42c1; background: #fff; }^)
    ROW + 1 call print(^.blob-meta { background: #f4f6f8; padding: 8px 12px; font-size: 12px; margin-bottom: 10px; font-weight: bold; color: #444; }^)
    ROW + 1 call print(^.blob-text { white-space: pre-wrap; font-family: Arial, sans-serif; font-size: 13px; line-height: 1.6; color: #222; margin-top: 0; }^)
    
    ROW + 1 call print(^.wrap *, .wrap *:before, .wrap *:after{box-sizing:border-box}^)
    ROW + 1 call print(concat(^#dot-view {margin:0;font:^, v_font_size, ^/1.4 -apple-system,BlinkMacSystemFont,Segoe UI,Roboto,Arial,sans-serif;color:#111;background:#fff;padding:16px;}^))
    ROW + 1 call print(^.wrap{max-width:1200px;margin:0 auto;}^)
    ROW + 1 call print(^.wrap h1{font-size:18px;margin:0 0 8px;}^)
    ROW + 1 call print(^.wrap h2{font-size:15px;margin:16px 0 8px;padding-top:0;}^)
    ROW + 1 call print(^.legend{margin-top:6px;color:#555;font-size:12px}^)
    ROW + 1 call print(^.axisbar{display:flex;justify-content:space-between;margin:10px 0 8px calc(260px + 46px + 4px);color:#333;font-size:12px;}^)
    ROW + 1 call print(^.chart-wrap{overflow-x:auto;border:1px solid #ddd;background:#fff;margin-bottom:12px;}^)
    ROW + 1 call print(^table.chart-tbl{border-collapse:collapse;border-spacing:0;width:100%;}^)
    ROW + 1 call print(^col.med{width:260px} col.dot{width:46px}^)
    ROW + 1 call print(^table.chart-tbl th, table.chart-tbl td{vertical-align:top;padding:0px 4px;text-align:left;font-size:12px;}^)
    ROW + 1 call print(^table.chart-tbl thead th.label {background:#e7eaee !important;color:#2f3c4b;border:1px solid #b5b5b5;padding:4px 8px !important;font-weight:600 !important;height:26px !important;line-height:1.2 !important;vertical-align:middle !important;}^)
    ROW + 1 call print(^table.chart-tbl thead tr.ticks th{background:transparent;border:0;padding:0;color:#555;}^)
    ROW + 1 call print(^table.chart-tbl thead tr.ticks th.sticky-med, table.chart-tbl thead tr.ticks th.sticky-dot {border-right:1px solid #ccc;border-bottom:1px solid #b5b5b5;}^)
    ROW + 1 call print(^table.chart-tbl tbody td.label{vertical-align:middle;padding:2px 6px;}^)
    ROW + 1 call print(^.dot-val{text-align:center !important;vertical-align:middle !important;background:#fff;}^)
    ROW + 1 call print(^table.chart-tbl tbody th.sticky-med, table.chart-tbl tbody td.sticky-med {position:sticky;left:0;background:#fff;z-index:10;border-right:1px solid #ccc;border-bottom:1px solid #d6d9dd;padding-left:8px;width:260px;}^)
    ROW + 1 call print(^table.chart-tbl tbody th.sticky-dot, table.chart-tbl tbody td.sticky-dot {position:sticky;left:260px;background:#fff;z-index:10;border-right:1px solid #ccc;border-bottom:1px solid #d6d9dd;width:46px;}^)
    ROW + 1 call print(^tr.even td.sticky-med, tr.even td.sticky-dot, tr.even td.dot-val { background: #f5f5f5 !important; }^)
    ROW + 1 call print(^.strip{display:flex;gap:1px;align-items:center;padding:4px 0;font-size:0;white-space:nowrap;overflow:visible;}^)
    ROW + 1 call print(^.cell,.tick{flex:0 0 14px;width:14px;height:14px;display:inline-flex;align-items:center;justify-content:center;text-align:center;font-size:10px;}^)
    ROW + 1 call print(^.tick{color:#555;border:1px solid transparent;border-radius:3px;position:relative}^)
    ROW + 1 call print(^.ticks .strip{padding-top:20px}^)
    ROW + 1 call print(^.tick .mo{position:absolute;top:-14px;left:50%;transform:translateX(-50%);font-size:10px;color:#555;white-space:nowrap;pointer-events:none}^)
    ROW + 1 call print(^.cell{border:1px solid #ccc;border-radius:3px;background:#fff}^)
    ROW + 1 call print(^.cell.on{background:#0086CE;border-color:#0D66A1;color:#fff;font-weight:600}^)
    ROW + 1 call print(^.cell.on:empty::before{content:"1"}^)
    ROW + 1 call print(^.cell.sum-yes{background:#ED1C24;border-color:#cc0000;}^)
    ROW + 1 call print(^.cell.sum-no{background:#A8D08D;border-color:#88b070;}^)
    ROW + 1 call print(^.pill{display:inline-block;padding:2px 6px;border-radius:12px;background:#eef;color:#334;}^)
    ROW + 1 call print(^.summary-row td{border-top:1px solid #ccc;padding-top:4px;}^)

    ROW + 1 call print(^.acuity-banner { padding: 15px; color: #fff; font-size: 22px; font-weight: bold; text-align: center; margin: 15px; border-radius: 5px; }^)
    ROW + 1 call print(^.acuity-Red { background-color: #dc3545; border-bottom: 4px solid #b02a37; }^)
    ROW + 1 call print(^.acuity-Amber { background-color: #ffc107; color: #333; border-bottom: 4px solid #d39e00; }^)
    ROW + 1 call print(^.acuity-Green { background-color: #28a745; border-bottom: 4px solid #1e7e34; }^)
    ROW + 1 call print(^.panel-header { font-size: 16px; margin-top: 0; padding-bottom: 8px; border-bottom: 2px solid #eee; color: #0076a8; }^)
    ROW + 1 call print(^.ref-table { width: 100%; border-collapse: collapse; font-size: 13px; margin-top: 0px; background: #fff; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }^)
    ROW + 1 call print(^.ref-table tr { cursor: help; }^)
    ROW + 1 call print(^.ref-table th, .ref-table td { border: 1px solid #ddd; padding: 8px 10px; text-align: left; }^)
    ROW + 1 call print(^.ref-table th { background-color: #f0f4f8; font-weight: bold; color: #333; }^)
    ROW + 1 call print(^.tr-active.red-tier { background-color: #f8d7da !important; border-left: 5px solid #dc3545; font-weight: bold; }^)
    ROW + 1 call print(^.tr-active.amber-tier { background-color: #fff3cd !important; border-left: 5px solid #ffc107; font-weight: bold; }^)
    
    ROW + 1 call print(^.trigger-list { list-style-type: none; padding: 0; }^)
    ROW + 1 call print(^.trigger-item-wrap { background: #f8f9fa; margin-bottom: 8px; border-left: 4px solid #0076a8; border-radius: 3px; }^)
    ROW + 1 call print(^.trigger-header { padding: 10px; font-size: 14px; cursor: pointer; }^)
    ROW + 1 call print(^.trigger-header:hover { background: #e2e6ea; }^)
    ROW + 1 call print(^.trigger-details { display: none; padding: 10px; border-top: 1px dashed #ccc; font-size: 12px; color: #444; background: #fff; margin-left: 10px; border-left: 1px solid #ccc; }^)
    ROW + 1 call print(^.trigger-det-item { padding: 3px 0; }^)
    ROW + 1 call print(^.exp-icon { float: right; font-weight: bold; color: #666; font-size: 16px; line-height: 1; }^)
    ROW + 1 call print(^.pts-badge { display: inline-block; background: #333; color: #fff; padding: 3px 8px; border-radius: 12px; font-size: 12px; margin-right: 10px; font-weight: bold; }^)
    
    ROW + 1 call print(^.mode-restricted .is-normal { display: none; }^)
    ROW + 1 call print(^.mode-restricted .is-infusion { display: none; }^)
    ROW + 1 call print(^.mode-all .is-infusion { display: none; }^)
    ROW + 1 call print(^.mode-infusion .is-restricted { display: none; }^)
    ROW + 1 call print(^.mode-infusion .is-normal { display: none; }^)
    ROW + 1 call print(^.mode-hidden { display: none; }^)
    
    ; WARD TABLE CSS FIXES (Split Table for Sticky Headers)
    ROW + 1 call print(^.ward-tbl { width: 100%; border-collapse: collapse; font-size: 14px; background: #fff; border: 1px solid #ddd; table-layout: fixed; }^)
    ROW + 1 call print(^.ward-tbl th, .ward-tbl td { padding: 10px 12px; border-bottom: 1px solid #eee; text-align: left; vertical-align: top; line-height: 1.4; word-wrap: break-word; }^)
    ROW + 1 call print(^.ward-tbl th { background: #f0f4f8; font-weight: bold; color: #333; border-bottom: 2px solid #ddd; }^)
    ROW + 1 call print(^.ward-tbl tbody tr:hover { background: #f9f9f9; }^)
    ROW + 1 call print(^.badge-Red { background: #dc3545; color: white; padding: 4px 10px; border-radius: 12px; font-weight:bold; font-size:12px; display:inline-block; min-width:60px; text-align:center; }^)
    ROW + 1 call print(^.badge-Amber { background: #ffc107; color: black; padding: 4px 10px; border-radius: 12px; font-weight:bold; font-size:12px; display:inline-block; min-width:60px; text-align:center; }^)
    ROW + 1 call print(^.badge-Green { background: #28a745; color: white; padding: 4px 10px; border-radius: 12px; font-weight:bold; font-size:12px; display:inline-block; min-width:60px; text-align:center; }^)
    ROW + 1 call print(^.patient-link { color: #0076a8; text-decoration: none; font-weight: bold; }^)
    ROW + 1 call print(^.patient-link:hover { text-decoration: underline; }^)

    ROW + 1 call print(^</style>^)
    ROW + 1 call print(^</head>^)

    ROW + 1 call print(^<body onload="showRestricted(); resizeLayout();">^)

    ROW + 1 call print(^<div class='pat-header'>^)
    ROW + 1 call print(concat(^<div style='float:left;'><b>^, NULLVAL(P_NAME, "Patient Not Found"), ^</b> | MRN: ^, NULLVAL(MRN, "N/A"), ^</div>^))
    ROW + 1 call print(concat(^<div style='float:right;'><span class='wt-label'>Last Dosing Weight:</span> <span class='wt-val'>^, sWeightDisp, ^</span></div>^))
    ROW + 1 call print(^<div style='clear:both;'></div>^)
    ROW + 1 call print(^</div>^)

    ROW + 1 call print(^<div class='tab-row'>^)
    ROW + 1 call print(^<div id='btn1' class='tab-btn' onclick='showRestricted()'>Antibiotics</div>^)
    ROW + 1 call print(^<div id='btn2' class='tab-btn' onclick='showAll()'>All Medications</div>^)
    ROW + 1 call print(^<div id='btn3' class='tab-btn' onclick='showInfusions()'>Infusions &amp; Labels</div>^)
    ROW + 1 call print(^<div id='btn4' class='tab-btn' onclick='showGP()'>Medication Details (GP)</div>^)
    ROW + 1 call print(^<div id='btn5' class='tab-btn' onclick='showHolder2()'>Antimicrobial DOT</div>^)
    ROW + 1 call print(^<div id='btn6' class='tab-btn' onclick='showAcuity()'>Patient Acuity</div>^)
    ROW + 1 call print(^<div id='btn7' class='tab-btn' onclick='showWard()'>Ward Triage List</div>^)
    ROW + 1 call print(^</div>^)

    ; =========================================================================
    ; TAB 7: WARD TRIAGE LIST VIEW (Split Block Layout)
    ; =========================================================================
    ROW + 1 call print(^<div id='ward-view' class='content-box' style='display:none; overflow:hidden;'>^) 
    
    ; Static Header Block (110px tall, padded right by 17px for scrollbar alignment)
    ROW + 1 call print(^<div id='ward-header' style='height: 110px;'>^)
    ROW + 1 call print(CONCAT(^<div class='acuity-banner' style='background:#0076a8; border-bottom:4px solid #005a80; margin:10px 15px;'>Acuity Triage: ^, curr_ward_disp, ^</div>^))
    ROW + 1 call print(^<div style="padding: 0 15px; padding-right: 32px;">^)
    ROW + 1 call print(^<table class='ward-tbl' style='margin-bottom:0; border-bottom:none;'>^)
    ROW + 1 call print(^<thead><tr><th width="15%">Bed / Room</th><th width="25%">Patient Name</th><th width="15%">Acuity Score</th><th width="45%">Active Triggers</th></tr></thead>^)
    ROW + 1 call print(^</table></div></div>^)
    
    ; Scrolling Body Block (Resized by JS function above)
    ROW + 1 call print(^<div id='ward-scroll' style='overflow-y:auto; padding: 0 15px;'>^)
    ROW + 1 call print(^<table class='ward-tbl' style='margin-top:0; border-top:none;'><tbody>^)
    ROW + 1 call print(v_ward_rows)
    ROW + 1 call print(^</tbody></table>^)
    ROW + 1 call print(^<div style="padding:15px; color:#666; font-size:12px; text-align:center;"><i>Clicking a patient's name will open their chart in PowerChart.<br/>Patients are automatically sorted by highest clinical risk.</i></div>^)
    ROW + 1 call print(^</div></div>^)

    ; =========================================================================
    ; TAB 6: ACUITY VIEW (Single Patient)
    ; =========================================================================
    ROW + 1 call print(^<div id='acuity-view' class='content-box' style='display:none;'>^)
    ROW + 1 call print(CONCAT(^<div class='acuity-banner acuity-^, rec_acuity->color, ^'>Patient Acuity Score: ^, TRIM(CNVTSTRING(rec_acuity->score)), ^ (Triage Tier: ^, CNVTUPPER(rec_acuity->color), ^)</div>^))
    
    ROW + 1 call print(^<table width="100%" border="0" cellpadding="0" cellspacing="0" style="margin-top:15px;"><tr>^)
    ROW + 1 call print(^<td width="48%" valign="top" style="padding: 0 10px 15px 15px;">^)
    ROW + 1 call print(^<h3 class='panel-header'>Patient Specific Triggers</h3>^)
    
    IF (rec_acuity->reason_cnt > 0)
        FOR (x = 1 TO rec_acuity->reason_cnt)
            ROW + 1 call print(^<div class='trigger-item-wrap'>^)
            ROW + 1 call print(CONCAT(^<div class='trigger-header' onclick='toggleTrigger(^, TRIM(CNVTSTRING(x)), ^)'><span class='pts-badge'>+^, TRIM(CNVTSTRING(rec_acuity->reasons[x].points)), ^ Points</span> ^, rec_acuity->reasons[x].text, ^<span class='exp-icon' id='trig-icon-^, TRIM(CNVTSTRING(x)), ^'>+</span></div>^))
            ROW + 1 call print(CONCAT(^<div class='trigger-details' id='trig-det-^, TRIM(CNVTSTRING(x)), ^'>^, rec_acuity->reasons[x].detail_html, ^</div>^))
            ROW + 1 call print(^</div>^)
        ENDFOR
    ELSE
        ROW + 1 call print(^<div style='background: #f8f9fa; padding: 10px; border-left: 4px solid #0076a8; border-radius: 3px; font-size: 14px; color:#666;'>No high-risk triggers detected. Patient remains Low Acuity (Routine Review).</div>^)
    ENDIF
    
    ROW + 1 call print(^<div style='margin-top:20px; font-size:12px; color:#666; background:#f9f9f9; padding:10px; border:1px solid #ddd;'>^)
    ROW + 1 call print(^<b>Triage Action Plan:</b><br/>^)
    IF (rec_acuity->color = "Red")
        ROW + 1 call print(^<b>RED (Score 3+):</b> High Risk. Requires clinical pharmacist review and medicines reconciliation within 24 hours.^)
    ELSEIF (rec_acuity->color = "Amber")
        ROW + 1 call print(^<b>AMBER (Score 1-2):</b> Medium Risk. Review during routine ward cover or before discharge.^)
    ELSE
        ROW + 1 call print(^<b>GREEN (Score 0):</b> Low Risk. Review only if requested by medical or midwifery team.^)
    ENDIF
    ROW + 1 call print(^</div>^)
    ROW + 1 call print(^</td>^)
    
    ROW + 1 call print(^<td width="52%" valign="top" style="padding: 0 15px 15px 10px;">^)
    ROW + 1 call print(^<h3 class='panel-header' style='margin-bottom: 2px;'>Scoring Reference Matrix</h3>^)
    ROW + 1 call print(^<div style='font-size:11px; color:#666; margin-bottom: 8px;'>Hover over a criteria row to view the exact database fields/strings being evaluated.<br>Criteria based on UKCPA Women's Health Group &amp; ISMP Guidelines. Lab parameters excluded.</div>^)
    ROW + 1 call print(^<table class='ref-table'>^)
    ROW + 1 call print(^<thead><tr><th width='60%'>Clinical Criteria</th><th width='20%'>Category</th><th width='20%'>Points</th></tr></thead><tbody>^)
    
    ROW + 1 call print(CONCAT(^<tr class='^, IF(rec_acuity->flag_ebl = 1 OR rec_acuity->flag_transfusion = 1) "tr-active red-tier" ELSE "" ENDIF, ^' title='Checks CLINICAL_EVENT for last 7 days. Looks for Blood Volume Infused (15071366) OR Delivery/Intraop/Total EBL > 1000ml.'><td>Massive Haemorrhage / Blood Transfusion</td><td>Clinical Event</td><td>+3</td></tr>^))
    ROW + 1 call print(CONCAT(^<tr class='^, IF(rec_acuity->flag_preeclampsia = 1 OR rec_acuity->flag_dvt = 1 OR rec_acuity->flag_epilepsy = 1) "tr-active red-tier" ELSE "" ENDIF, ^' title='Checks both ACTIVE PROBLEM and ACTIVE DIAGNOSIS lists for nomenclature strings containing: PRE-ECLAMPSIA, DVT, PULMONARY EMBOLISM, or EPILEPSY/SEIZURE.'><td>High Risk Diagnosis (Pre-eclampsia, VTE, Epilepsy)</td><td>Problem/Diagnosis</td><td>+3</td></tr>^))
    ROW + 1 call print(CONCAT(^<tr class='^, IF(rec_acuity->flag_insulin = 1 OR rec_acuity->flag_antiepileptic = 1) "tr-active red-tier" ELSE "" ENDIF, ^' title='Checks active inpatient pharmacy orders for mnemonics containing: INSULIN, LEVETIRACETAM, LAMOTRIGINE, VALPROATE, or CARBAMAZEPINE.'><td>High Alert Med (Insulin, Antiepileptics)</td><td>Medication</td><td>+3</td></tr>^))
    ROW + 1 call print(CONCAT(^<tr class='^, IF(rec_acuity->flag_poly_severe = 1) "tr-active red-tier" ELSE "" ENDIF, ^' title='Checks if patient has greater than or equal to 10 active inpatient pharmacy orders. (Excludes standard IV fluids and Care Plan PRNs)'><td>Severe Polypharmacy (&ge;10 active meds)</td><td>Medication</td><td>+3</td></tr>^))
    ROW + 1 call print(CONCAT(^<tr class='^, IF(rec_acuity->flag_anticoag = 1 OR rec_acuity->flag_antihypertensive = 1) "tr-active amber-tier" ELSE "" ENDIF, ^' title='Checks active inpatient pharmacy orders for mnemonics containing: TINZAPARIN, HEPARIN, ENOXAPARIN, LABETALOL, NIFEDIPINE, or METHYLDOPA.'><td>Targeted Med (Anticoagulant, Antihypertensive)</td><td>Medication</td><td>+2</td></tr>^))
    ROW + 1 call print(CONCAT(^<tr class='^, IF(rec_acuity->flag_poly_mod = 1) "tr-active amber-tier" ELSE "" ENDIF, ^' title='Checks if patient has between 5 and 9 active inpatient pharmacy orders. (Excludes standard IV fluids and Care Plan PRNs)'><td>Moderate Polypharmacy (5-9 active meds)</td><td>Medication</td><td>+1</td></tr>^))
    ROW + 1 call print(CONCAT(^<tr class='^, IF(rec_acuity->flag_neuraxial = 1) "tr-active amber-tier" ELSE "" ENDIF, ^' title='Checks active inpatient pharmacy orders for mnemonics containing: BUPIVACAINE or LEVOBUPIVACAINE.'><td>Neuraxial / Epidural Infusion Active</td><td>Medication</td><td>+1</td></tr>^))
    
    ROW + 1 call print(^</tbody></table>^)
    ROW + 1 call print(^</td></tr></table>^)
    ROW + 1 call print(^<div style="height: 100px; width: 100%;"></div>^)
    ROW + 1 call print(^</div>^)

    ; =========================================================================
    ; TAB 1, 2, 3: MEDICATION LIST
    ; =========================================================================
    ROW + 1 call print(^<div id='med-container' class='content-box'>^)
    ROW + 1 call print(^<div id='header-row-inf' class='inf-header'>^)
    ROW + 1 call print(^<div style='float:left; width:120px;'>Start Date</div>^)
    ROW + 1 call print(^<div style='float:left; width:250px;'>Infusion Name</div>^)
    ROW + 1 call print(^<div style='float:left; width:80px;'>Type</div>^)
    ROW + 1 call print(^<div style='float:left; width:150px;'>Action</div>^)
    ROW + 1 call print(^<div style='clear:both;'></div>^)
    ROW + 1 call print(^</div>^)

    ROW + 1 call print(^<div id='med-list' class='list-view'>^)

DETAIL
    IF (ORDER_ID > 0)
        IF (
               FINDSTRING("Linezolid",    MNEMONIC) > 0
            OR FINDSTRING("Ertapenem",    MNEMONIC) > 0
            OR FINDSTRING("Meropenem",    MNEMONIC) > 0
            OR FINDSTRING("Vancomycin",   MNEMONIC) > 0
            OR FINDSTRING("Gentamicin",   MNEMONIC) > 0
            OR FINDSTRING("Amikacin",     MNEMONIC) > 0
            OR FINDSTRING("Piperacillin", MNEMONIC) > 0
            OR FINDSTRING("Tazobactam",   MNEMONIC) > 0
            OR FINDSTRING("Cefotaxime",   MNEMONIC) > 0
        )
            ROW + 1 call print(^<div class='order-item is-restricted'>^)
            call print(concat(^<b>^, MNEMONIC, ^</b> <span style='color:red; font-size:10px; border:1px solid red; padding:0 3px;'>RESTRICTED</span>^))
        ELSE
            ROW + 1 call print(^<div class='order-item is-normal'>^)
            call print(concat(^<b>^, MNEMONIC, ^</b>^))
        ENDIF

        call print(concat(^<div style='font-size:12px; color:#555;'>^, CDL, ^</div>^))
        call print(concat(^<div style='font-size:11px; color:#999;'>Started: ^, START_DT, ^</div>^))
        call print(^</div>^)

        IF (
                FINDSTRING("CONTINUOUS",   CNVTUPPER(DISP_CAT)) > 0
            OR FINDSTRING("CONTINUOUS",   CNVTUPPER(ORDER_FORM)) > 0
            OR FINDSTRING("INFUSION",     CNVTUPPER(ORDER_FORM)) > 0
            OR FINDSTRING("ML/HR",        CNVTUPPER(CDL)) > 0
            OR FINDSTRING("INTERMITTENT", CNVTUPPER(DISP_CAT)) > 0
            OR FINDSTRING("UD",           CNVTUPPER(DISP_CAT)) > 0
        )
            IF (
                (FINDSTRING("CONTINUOUS", CNVTUPPER(DISP_CAT)) > 0 OR FINDSTRING("INFUSION", CNVTUPPER(ORDER_FORM)) > 0)
                AND (FINDSTRING("Glucose", MNEMONIC) > 0 OR FINDSTRING("Sodium", MNEMONIC) > 0 OR FINDSTRING("Maintelyte", MNEMONIC) > 0)
            )
                ROW + 1 call print(^<div class='inf-row is-infusion'>^)
                call print(concat(^<div class='inf-col' style='width:120px;'>^, START_DT, ^</div>^))
                call print(concat(^<div class='inf-col' style='width:250px;'><b>^, MNEMONIC, ^</b></div>^))
                call print(^<div class='inf-col' style='width:80px;'><span class='type-badge' style='background:#17a2b8;'>FLUID</span></div>^)
                call print(^<div class='inf-col' style='width:150px;'><a class='print-link' href='#'>Print Fluid Label</a></div><div style='clear:both;'></div></div>^)
            ELSEIF (FINDSTRING("INTERMITTENT", CNVTUPPER(DISP_CAT)) > 0)
                ROW + 1 call print(^<div class='inf-row is-infusion'>^)
                call print(concat(^<div class='inf-col' style='width:120px;'>^, START_DT, ^</div>^))
                call print(concat(^<div class='inf-col' style='width:250px;'><b>^, MNEMONIC, ^</b></div>^))
                call print(^<div class='inf-col' style='width:80px;'><span class='type-badge' style='background:#ffc107; color:black;'>INTERM</span></div>^)
                call print(^<div class='inf-col' style='width:150px;'><a class='print-link' href='#'>Print Intermittent Label</a></div><div style='clear:both;'></div></div>^)
            ELSEIF (FINDSTRING("UD", CNVTUPPER(DISP_CAT)) > 0)
                ROW + 1 call print(^<div class='inf-row is-infusion'>^)
                call print(concat(^<div class='inf-col' style='width:120px;'>^, START_DT, ^</div>^))
                call print(concat(^<div class='inf-col' style='width:250px;'><b>^, MNEMONIC, ^</b></div>^))
                call print(^<div class='inf-col' style='width:80px;'><span class='type-badge' style='background:#6c757d;'>PN / UD</span></div>^)
                call print(^<div class='inf-col' style='width:150px;'><a class='print-link' href='#'>Print PN Label</a></div><div style='clear:both;'></div></div>^)
            ELSE
                ROW + 1 call print(^<div class='inf-row is-infusion'>^)
                call print(concat(^<div class='inf-col' style='width:120px;'>^, START_DT, ^</div>^))
                call print(concat(^<div class='inf-col' style='width:250px;'><b>^, MNEMONIC, ^</b></div>^))
                call print(^<div class='inf-col' style='width:80px;'><span class='type-badge' style='background:#28a745;'>SCI</span></div>^)
                call print(^<div class='inf-col' style='width:150px;'><a class='print-link' href='#'>Print SCI Label</a></div><div style='clear:both;'></div></div>^)
            ENDIF
        ENDIF
    ENDIF

FOOT REPORT
    IF (ORDER_ID = 0)
        ROW + 1 call print(^<div style='padding: 15px; color: #666;'>No active orders found for this patient.</div>^)
    ENDIF
    ROW + 1 call print(^</div></div>^)
    ROW + 1 call print(^</body></html>^)

WITH NOFORMAT, SEPARATOR=" ", MAXCOL=32000, LANDSCAPE

FREE RECORD rec_blob
END
GO