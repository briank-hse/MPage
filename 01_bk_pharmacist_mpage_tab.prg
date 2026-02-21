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
; 2. GP MEDICATION DETAILS - BLOBGET + MEMREALLOC, DETAIL LOOP FOR MULTI-RECORD
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
    
    ; Strip default 00:00 midnight times to clean up the display
    rec_blob->list[nCnt].dt_tm    = REPLACE(FORMAT(CE.PERFORMED_DT_TM, "DD/MM/YYYY HH:MM"), " 00:00", "", 0)
    
    rec_blob->list[nCnt].prsnl    = PR.NAME_FULL_FORMATTED

    tlen       = 0
    bsize      = 0
    vCleanText = " "

    ; Step 1: BLOBGET - fetches full gc32768 content past vc truncation limit
    bloblen = blobgetlen(CB.BLOB_CONTENTS)
    stat    = memrealloc(blob_in, 1, build("C", bloblen))
    totlen  = blobget(blob_in, 0, CB.BLOB_CONTENTS)

    ; Step 2: Decompress - output buffer sized to uncompressed length
    stat = memrealloc(blob_out, 1, build("C", CB.BLOB_LENGTH))
    call uar_ocf_uncompress(blob_in, textlen(blob_in), blob_out, CB.BLOB_LENGTH, tlen)

    ; Step 3: RTF to plain text - output buffer sized to uncompressed length
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

    ; Step 4: Clean text
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
        vCleanText = REPLACE(vCleanText, CHAR(11), "<br />", 0)
        
        vCleanText = REPLACE(vCleanText, "<br /><br /><br /><br /><br /><br />", "<br /><br />", 0)
        vCleanText = REPLACE(vCleanText, "<br /><br /><br /><br /><br />", "<br /><br />", 0)
        vCleanText = REPLACE(vCleanText, "<br /><br /><br /><br />", "<br /><br />", 0)
        vCleanText = REPLACE(vCleanText, "<br /><br /><br />", "<br /><br />", 0)
        
        vCleanText = TRIM(vCleanText, 3)
    ENDIF

    rec_blob->list[nCnt].blob_text = vCleanText

WITH NOCOUNTER, RDBARRAYFETCH=1

; ========================================================================== 
; 3. ANTIMICROBIAL DOT - Variable Declarations                               
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

; ========================================================================== 
; 3a. ANTIMICROBIAL DOT - PASS 1: Determine Date Range for Chart Axis        
; ========================================================================== 
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
  set v_axis_html = concat(
    '<div class="axisbar"><div>Date range: ', format(v_min_dt,"DD-MMM-YYYY;;D"),
    ' to ', format(v_max_dt,"DD-MMM-YYYY;;D"), '</div></div>'
  )
  set v_header_html = ''
  set v_i = 0
  while (v_i < v_days)
    if (v_i = 0 or format(v_min_dt + v_i,"MM;;D") != format(v_min_dt + v_i - 1,"MM;;D"))
      set v_header_html = concat(v_header_html,
        '<span class="tick" title="', format(v_min_dt + v_i,"YYYY-MM-DD;;D"), '">',
          '<span class="mo">', format(v_min_dt + v_i,"MMM;;D"), '</span>',
          format(v_min_dt + v_i,"DD;;D"), '</span>'
      )
    else
      set v_header_html = concat(v_header_html,
        '<span class="tick" title="', format(v_min_dt + v_i,"YYYY-MM-DD;;D"), '">',
        format(v_min_dt + v_i,"DD;;D"), '</span>'
      )
    endif
    set v_i = v_i + 1
  endwhile
endif

set v_chart_meta = concat('')
set v_table_meta = '<div class="sub"><b>MRN:</b> '
set v_table_meta = concat(v_table_meta, v_mrn, " &nbsp; <b>Name:</b> ", v_name)
set v_table_meta = concat(v_table_meta, " &nbsp; <b>Begin:</b> ", v_begin_dt_str)
set v_table_meta = concat(v_table_meta, " &nbsp;  End:</b> ", v_end_dt_str)
set v_table_meta = concat(v_table_meta, " &nbsp; <b>Admission:</b> ", v_admit_dt)
set v_table_meta = concat(v_table_meta, " &nbsp; <b>LOS:</b> ", v_los, " days")
set v_table_meta = concat(v_table_meta, " &nbsp; <b>Lookback:</b> ", v_lookback, " days</div>")

; ========================================================================== 
; 3b. ANTIMICROBIAL DOT - PASS 2: Build Chart Rows (per Medication)          
; ========================================================================== 
select into "nl:"
  oc.primary_mnemonic
, m.event_id
, mdy = format(ce.performed_dt_tm, "YYYYMMDD;;D")
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
join oc where oc.catalog_cd = cr.parent_cd
  and oc.catalog_type_cd = 2516
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

      v_indication = ""
      v_discontinue_rsn = ""
      v_findpos = findstring(concat("~", v_key8, ":"), v_details_kv)
      if (v_findpos > 0)
        v_after  = substring(v_findpos + 10, textlen(v_details_kv) - (v_findpos + 9), v_details_kv)
        v_endpos = findstring("~", v_after)
        v_detail_str = ""
        if (v_endpos > 0) v_detail_str = substring(1, v_endpos - 1, v_after)
        else v_detail_str = v_after
        endif
        v_pipe_pos = findstring("|", v_detail_str)
        if (v_pipe_pos > 0)
          v_indication = substring(1, v_pipe_pos - 1, v_detail_str)
          v_discontinue_rsn = substring(v_pipe_pos + 1, textlen(v_detail_str) - v_pipe_pos, v_detail_str)
        else
          v_indication = v_detail_str
        endif
      endif

      if (v_count_i > 0)
        v_title = concat(v_curr_med, " - ", format(v_min_dt + v_i,"DD/MM/YYYY;;D"), " / ", v_count_str,
                          if(v_count_i = 1) " admin" else " admins" endif,
                          "&#10;Indication: ", v_indication,
                          "&#10;Discontinue Reason: ", v_discontinue_rsn)
        v_strip = concat(v_strip, '<span class="cell on" title="', v_title, '">', trim(v_count_str), '</span>')
      else
        v_strip = concat(v_strip, '<span class="cell" title="', format(v_min_dt + v_i,"DD/MM/YYYY;;D"), '"></span>')
      endif
      v_i = v_i + 1
    endwhile
    
    v_chart_rows = concat(v_chart_rows, 
      '<tr', if(mod(v_row_cnt, 2) = 0) ' class="even"' else '' endif, '>',
      '<td class="label medname sticky-med">', v_curr_med, '</td>',
      '<td class="label dot-val sticky-dot"><span class="pill" title="', v_curr_med, ' - Total Days of Therapy: ', trim(cnvtstring(v_med_dot_total)), '">', cnvtstring(v_med_dot_total), '</span></td>',
      '<td><div class="strip">', v_strip, '</div></td>',
      '</tr>')
  endif

foot report
  if (v_days > 0)
      v_sum_strip = ""
      v_spacer_strip = "" 
      v_i = 0
      while (v_i < v_days)
          v_key8 = format(v_min_dt + v_i, "YYYYMMDD;;D")
          if (findstring(concat("~", v_key8, "~"), v_all_days_list) > 0)
              v_sum_strip = concat(v_sum_strip, '<span class="cell sum-yes" title="Antimicrobial Administered"></span>')
          else
              v_sum_strip = concat(v_sum_strip, '<span class="cell sum-no" title="No Antimicrobials"></span>')
          endif
          v_spacer_strip = concat(v_spacer_strip, '<span class="cell spacer-bit"></span>')
          v_i = v_i + 1
      endwhile
       
      v_chart_rows = concat(v_chart_rows,
          '<tr class="summary-row">',
            '<td class="label sticky-med">Antimicrobial Summary</td>',
            '<td class="label sticky-dot"></td>',
            '<td><div class="strip">', v_sum_strip, '</div></td>',
          '</tr>')
  endif
with nocounter

; ========================================================================== 
; 3c. ANTIMICROBIAL DOT - PASS 3: Build Table Rows (per Order)               
; ========================================================================== 
set v_table_rows = ""
select into "nl:"
  oc.primary_mnemonic
, day_key = format(ce.performed_dt_tm, "yyyymmdd")
, o.current_start_dt_tm
, o_order_status_disp = uar_get_code_display(o.order_status_cd)
, o.status_dt_tm
, indication = substring(1,60,trim(od_indication.oe_field_display_value))
, ordered_target_dose = oi.ordered_dose
, ordered_target_dose_unit = uar_get_code_display(oi.ordered_dose_unit_cd)
, o.order_id
from
  person p, clinical_event ce, med_admin_event m, orders o, order_ingredient oi,
  ce_event_order_link cl, code_value_event_r cr, order_catalog oc,
  order_catalog_synonym ocs, order_entry_format oe, order_detail od_indication

plan p where p.person_id = CNVTREAL($patient_id)
join ce where ce.person_id = p.person_id
  and ce.performed_dt_tm between cnvtdatetime(curdate-$LOOKBACK,0) and cnvtdatetime(curdate,235959)
join m where m.event_id = ce.event_id
  and m.event_type_cd = value(uar_get_code_by("MEANING",4000040,"TASKCOMPLETE"))
join o where o.order_id = m.template_order_id
join oi where oi.order_id = o.order_id
join cl where cl.event_id = ce.event_id
join cr where cr.event_cd = ce.event_cd
join oc where oc.catalog_cd = cr.parent_cd
  and oc.catalog_type_cd = 2516
join ocs where ocs.catalog_cd = oc.catalog_cd
join oe where oe.oe_format_id = ocs.oe_format_id
  and oe.oe_format_id in (14497910, 14498121)
join od_indication where od_indication.order_id = outerjoin(o.order_id)
  and od_indication.oe_field_meaning_id = outerjoin(15)

order by o.order_id, cnvtupper(oc.primary_mnemonic), day_key

head report
  v_table_rows = ""
  v_row_cnt = 0

head o.order_id
  v_drug  = oc.primary_mnemonic
  v_dose  = 0.0
  v_unit  = ""
  v_ind   = ""
  v_start = ""
  v_stat  = ""
  v_sdt   = ""
  v_oid   = cnvtstring(o.order_id)
  v_dot   = 0

head day_key
  v_dot = v_dot + 1

foot o.order_id
  v_dose  = ordered_target_dose
  v_unit  = ordered_target_dose_unit
  v_ind   = indication
  v_start = format(o.current_start_dt_tm,"DD/MM/YYYY;;d")
  v_stat  = o_order_status_disp
  v_sdt   = format(o.status_dt_tm,"DD/MM/YYYY;;d")
  
  v_row_cnt = v_row_cnt + 1
  
  v_table_rows = concat(v_table_rows,
    '<tr', if(mod(v_row_cnt, 2) = 0) ' class="even"' else '' endif, '>',
      "<td>", v_drug, "</td>",
      '<td class="dot-val"><span class="pill">', cnvtstring(v_dot), '</span></td>',
      "<td>", trim(format(v_dose,"########.##")), " ", v_unit, "</td>",
      "<td>", v_ind, "</td>",
      "<td>", v_start, "</td>",
      "<td>", v_stat, "</td>",
      "<td>", v_sdt, "</td>",
      "<td>", v_oid, "</td>",
    "</tr>"
  )
with nocounter

if (textlen(v_table_rows) = 0)
  set v_table_rows = '<tr><td colspan="8">No antimicrobial orders found in the selected window.</td></tr>'
endif

; =============================================================================
; 3.5 MATERNITY ACUITY SCORE CALCULATION 
; =============================================================================
RECORD rec_acuity (
    1 score = i4
    1 color = vc
    1 poly_count = i4
    1 reason_cnt = i4
    1 reasons[*]
        2 text = vc
        2 points = i4
)

; Calculate Polypharmacy & High Risk Meds
SELECT INTO "NL:"
    MNEM = CNVTUPPER(O.ORDER_MNEMONIC)
FROM ORDERS O
PLAN O WHERE O.PERSON_ID = CNVTREAL($patient_id)
    AND O.ORDER_STATUS_CD = 2550.00 ; Active
    AND O.CATALOG_TYPE_CD = 2516.00 ; Pharmacy
DETAIL
    rec_acuity->poly_count = rec_acuity->poly_count + 1

    IF (FINDSTRING("TINZAPARIN", MNEM) > 0 OR FINDSTRING("HEPARIN", MNEM) > 0)
        rec_acuity->score = rec_acuity->score + 2
        rec_acuity->reason_cnt = rec_acuity->reason_cnt + 1
        stat = alterlist(rec_acuity->reasons, rec_acuity->reason_cnt)
        rec_acuity->reasons[rec_acuity->reason_cnt].text = "High Risk Med: Anticoagulant"
        rec_acuity->reasons[rec_acuity->reason_cnt].points = 2
    ELSEIF (FINDSTRING("INSULIN", MNEM) > 0)
        rec_acuity->score = rec_acuity->score + 2
        rec_acuity->reason_cnt = rec_acuity->reason_cnt + 1
        stat = alterlist(rec_acuity->reasons, rec_acuity->reason_cnt)
        rec_acuity->reasons[rec_acuity->reason_cnt].text = "High Risk Med: Insulin"
        rec_acuity->reasons[rec_acuity->reason_cnt].points = 2
    ELSEIF (FINDSTRING("LABETALOL", MNEM) > 0 OR FINDSTRING("NIFEDIPINE", MNEM) > 0)
        rec_acuity->score = rec_acuity->score + 2
        rec_acuity->reason_cnt = rec_acuity->reason_cnt + 1
        stat = alterlist(rec_acuity->reasons, rec_acuity->reason_cnt)
        rec_acuity->reasons[rec_acuity->reason_cnt].text = "High Risk Med: Antihypertensive"
        rec_acuity->reasons[rec_acuity->reason_cnt].points = 2
    ELSEIF (FINDSTRING("BUPIVACAINE", MNEM) > 0 OR FINDSTRING("LEVOBUPIVACAINE", MNEM) > 0)
        rec_acuity->score = rec_acuity->score + 2
        rec_acuity->reason_cnt = rec_acuity->reason_cnt + 1
        stat = alterlist(rec_acuity->reasons, rec_acuity->reason_cnt)
        rec_acuity->reasons[rec_acuity->reason_cnt].text = "High Risk Med: Neuraxial / Epidural"
        rec_acuity->reasons[rec_acuity->reason_cnt].points = 2
    ENDIF
WITH NOCOUNTER

; Add polypharmacy score logic
IF (rec_acuity->poly_count >= 10)
    SET rec_acuity->score = rec_acuity->score + 3
    SET rec_acuity->reason_cnt = rec_acuity->reason_cnt + 1
    SET stat = alterlist(rec_acuity->reasons, rec_acuity->reason_cnt)
    SET rec_acuity->reasons[rec_acuity->reason_cnt].text = CONCAT("Severe Polypharmacy (", TRIM(CNVTSTRING(rec_acuity->poly_count)), " active meds)")
    SET rec_acuity->reasons[rec_acuity->reason_cnt].points = 3
ELSEIF (rec_acuity->poly_count >= 5)
    SET rec_acuity->score = rec_acuity->score + 1
    SET rec_acuity->reason_cnt = rec_acuity->reason_cnt + 1
    SET stat = alterlist(rec_acuity->reasons, rec_acuity->reason_cnt)
    SET rec_acuity->reasons[rec_acuity->reason_cnt].text = CONCAT("Moderate Polypharmacy (", TRIM(CNVTSTRING(rec_acuity->poly_count)), " active meds)")
    SET rec_acuity->reasons[rec_acuity->reason_cnt].points = 1
ENDIF

; Check Clinical Events for Massive EBL or Blood Transfusions (7 day lookback)
SELECT INTO "NL:"
FROM CLINICAL_EVENT CE
PLAN CE WHERE CE.PERSON_ID = CNVTREAL($patient_id)
    AND CE.EVENT_CD IN (15071366.00, 82546829.00) ; Blood Volume Infused, Total EBL
    AND CE.PERFORMED_DT_TM > CNVTLOOKBEHIND("7,D")
    AND CE.RESULT_STATUS_CD IN (25, 34, 35)
ORDER BY CE.EVENT_CD, CE.PERFORMED_DT_TM DESC
HEAD CE.EVENT_CD
    IF (CE.EVENT_CD = 15071366.00) ; Blood transfusion
        rec_acuity->score = rec_acuity->score + 3
        rec_acuity->reason_cnt = rec_acuity->reason_cnt + 1
        stat = alterlist(rec_acuity->reasons, rec_acuity->reason_cnt)
        rec_acuity->reasons[rec_acuity->reason_cnt].text = "Blood Transfusion documented in last 7 days"
        rec_acuity->reasons[rec_acuity->reason_cnt].points = 3
    ELSEIF (CE.EVENT_CD = 82546829.00 AND CNVTREAL(CE.RESULT_VAL) > 1000) ; Total EBL > 1000
        rec_acuity->score = rec_acuity->score + 3
        rec_acuity->reason_cnt = rec_acuity->reason_cnt + 1
        stat = alterlist(rec_acuity->reasons, rec_acuity->reason_cnt)
        rec_acuity->reasons[rec_acuity->reason_cnt].text = "Massive Obstetric Haemorrhage (EBL > 1000ml)"
        rec_acuity->reasons[rec_acuity->reason_cnt].points = 3
    ENDIF
WITH NOCOUNTER

; Determine Final Acuity Color Mapping
IF (rec_acuity->score >= 3)
    SET rec_acuity->color = "Red"
ELSEIF (rec_acuity->score >= 1)
    SET rec_acuity->color = "Amber"
ELSE
    SET rec_acuity->color = "Green"
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
; 5. HTML OUTPUT - IE5 QUIRKS MODE COMPATIBLE
; =============================================================================
HEAD REPORT
    ROW + 1 call print(^<!DOCTYPE html>^)
    ROW + 1 call print(^<html><head>^)
    ROW + 1 call print(^<meta http-equiv='X-UA-Compatible' content='IE=edge'>^)
    ROW + 1 call print(^<META content='CCLLINK' name='discern'>^)

    ROW + 1 call print(^<script>^)
    ROW + 1 call print(concat(^var totalBlobs = ^, TRIM(CNVTSTRING(size(rec_blob->list, 5))), ^;^))
    ROW + 1 call print(^var currentBlob = 1;^)
    
    ; Dynamic Resizer for IE5 Quirks Mode
    ROW + 1 call print(^function resizeLayout() {^)
    ROW + 1 call print(^  var h = document.body.clientHeight - 90;^)
    ROW + 1 call print(^  if (h < 300) h = 300;^)
    ROW + 1 call print(^  var side = document.getElementById('scroll-side');^)
    ROW + 1 call print(^  var main = document.getElementById('scroll-main');^)
    ROW + 1 call print(^  var table = document.getElementById('gp-table');^)
    ROW + 1 call print(^  if(table) table.style.height = h + 'px';^)
    ROW + 1 call print(^  if(side) side.style.height = h + 'px';^)
    ROW + 1 call print(^  if(main) main.style.height = (h - 32) + 'px';^)
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

    ROW + 1 call print(^function showRestricted() {^)
    ROW + 1 call print(^  document.getElementById('med-list').className = 'list-view mode-restricted';^)
    ROW + 1 call print(^  document.getElementById('header-row-inf').style.display = 'none';^)
    ROW + 1 call print(^  document.getElementById('gp-blob-view').style.display = 'none';^)
    ROW + 1 call print(^  document.getElementById('dot-view').style.display = 'none';^)
    ROW + 1 call print(^  document.getElementById('acuity-view').style.display = 'none';^)
    ROW + 1 call print(^  document.getElementById('med-container').style.display = 'block';^)
    ROW + 1 call print(^  document.getElementById('btn1').className = 'tab-btn active';^)
    ROW + 1 call print(^  document.getElementById('btn2').className = 'tab-btn';^)
    ROW + 1 call print(^  document.getElementById('btn3').className = 'tab-btn';^)
    ROW + 1 call print(^  document.getElementById('btn4').className = 'tab-btn';^)
    ROW + 1 call print(^  document.getElementById('btn5').className = 'tab-btn';^)
    ROW + 1 call print(^  document.getElementById('btn6').className = 'tab-btn';^)
    ROW + 1 call print(^}^)

    ROW + 1 call print(^function showAll() {^)
    ROW + 1 call print(^  document.getElementById('med-list').className = 'list-view mode-all';^)
    ROW + 1 call print(^  document.getElementById('header-row-inf').style.display = 'none';^)
    ROW + 1 call print(^  document.getElementById('gp-blob-view').style.display = 'none';^)
    ROW + 1 call print(^  document.getElementById('dot-view').style.display = 'none';^)
    ROW + 1 call print(^  document.getElementById('acuity-view').style.display = 'none';^)
    ROW + 1 call print(^  document.getElementById('med-container').style.display = 'block';^)
    ROW + 1 call print(^  document.getElementById('btn1').className = 'tab-btn';^)
    ROW + 1 call print(^  document.getElementById('btn2').className = 'tab-btn active';^)
    ROW + 1 call print(^  document.getElementById('btn3').className = 'tab-btn';^)
    ROW + 1 call print(^  document.getElementById('btn4').className = 'tab-btn';^)
    ROW + 1 call print(^  document.getElementById('btn5').className = 'tab-btn';^)
    ROW + 1 call print(^  document.getElementById('btn6').className = 'tab-btn';^)
    ROW + 1 call print(^}^)

    ROW + 1 call print(^function showInfusions() {^)
    ROW + 1 call print(^  document.getElementById('med-list').className = 'list-view mode-infusion';^)
    ROW + 1 call print(^  document.getElementById('header-row-inf').style.display = 'block';^)
    ROW + 1 call print(^  document.getElementById('gp-blob-view').style.display = 'none';^)
    ROW + 1 call print(^  document.getElementById('dot-view').style.display = 'none';^)
    ROW + 1 call print(^  document.getElementById('acuity-view').style.display = 'none';^)
    ROW + 1 call print(^  document.getElementById('med-container').style.display = 'block';^)
    ROW + 1 call print(^  document.getElementById('btn1').className = 'tab-btn';^)
    ROW + 1 call print(^  document.getElementById('btn2').className = 'tab-btn';^)
    ROW + 1 call print(^  document.getElementById('btn3').className = 'tab-btn active';^)
    ROW + 1 call print(^  document.getElementById('btn4').className = 'tab-btn';^)
    ROW + 1 call print(^  document.getElementById('btn5').className = 'tab-btn';^)
    ROW + 1 call print(^  document.getElementById('btn6').className = 'tab-btn';^)
    ROW + 1 call print(^}^)

    ROW + 1 call print(^function showGP() {^)
    ROW + 1 call print(^  document.getElementById('med-list').className = 'list-view mode-hidden';^)
    ROW + 1 call print(^  document.getElementById('header-row-inf').style.display = 'none';^)
    ROW + 1 call print(^  document.getElementById('med-container').style.display = 'none';^)
    ROW + 1 call print(^  document.getElementById('dot-view').style.display = 'none';^)
    ROW + 1 call print(^  document.getElementById('acuity-view').style.display = 'none';^)
    ROW + 1 call print(^  document.getElementById('gp-blob-view').style.display = 'block';^)
    ROW + 1 call print(^  document.getElementById('btn1').className = 'tab-btn';^)
    ROW + 1 call print(^  document.getElementById('btn2').className = 'tab-btn';^)
    ROW + 1 call print(^  document.getElementById('btn3').className = 'tab-btn';^)
    ROW + 1 call print(^  document.getElementById('btn4').className = 'tab-btn active';^)
    ROW + 1 call print(^  document.getElementById('btn5').className = 'tab-btn';^)
    ROW + 1 call print(^  document.getElementById('btn6').className = 'tab-btn';^)
    ROW + 1 call print(^  resizeLayout();^)
    ROW + 1 call print(^}^)

    ROW + 1 call print(^function showHolder2() {^)
    ROW + 1 call print(^  document.getElementById('med-list').className = 'list-view mode-hidden';^)
    ROW + 1 call print(^  document.getElementById('header-row-inf').style.display = 'none';^)
    ROW + 1 call print(^  document.getElementById('gp-blob-view').style.display = 'none';^)
    ROW + 1 call print(^  document.getElementById('med-container').style.display = 'none';^)
    ROW + 1 call print(^  document.getElementById('acuity-view').style.display = 'none';^)
    ROW + 1 call print(^  document.getElementById('dot-view').style.display = 'block';^)
    ROW + 1 call print(^  document.getElementById('btn1').className = 'tab-btn';^)
    ROW + 1 call print(^  document.getElementById('btn2').className = 'tab-btn';^)
    ROW + 1 call print(^  document.getElementById('btn3').className = 'tab-btn';^)
    ROW + 1 call print(^  document.getElementById('btn4').className = 'tab-btn';^)
    ROW + 1 call print(^  document.getElementById('btn5').className = 'tab-btn active';^)
    ROW + 1 call print(^  document.getElementById('btn6').className = 'tab-btn';^)
    ROW + 1 call print(^}^)

    ROW + 1 call print(^function showAcuity() {^)
    ROW + 1 call print(^  document.getElementById('med-list').className = 'list-view mode-hidden';^)
    ROW + 1 call print(^  document.getElementById('header-row-inf').style.display = 'none';^)
    ROW + 1 call print(^  document.getElementById('gp-blob-view').style.display = 'none';^)
    ROW + 1 call print(^  document.getElementById('med-container').style.display = 'none';^)
    ROW + 1 call print(^  document.getElementById('dot-view').style.display = 'none';^)
    ROW + 1 call print(^  document.getElementById('acuity-view').style.display = 'block';^)
    ROW + 1 call print(^  document.getElementById('btn1').className = 'tab-btn';^)
    ROW + 1 call print(^  document.getElementById('btn2').className = 'tab-btn';^)
    ROW + 1 call print(^  document.getElementById('btn3').className = 'tab-btn';^)
    ROW + 1 call print(^  document.getElementById('btn4').className = 'tab-btn';^)
    ROW + 1 call print(^  document.getElementById('btn5').className = 'tab-btn';^)
    ROW + 1 call print(^  document.getElementById('btn6').className = 'tab-btn active';^)
    ROW + 1 call print(^}^)

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
    
    ; --- LEGACY TABLE PANE CSS WITH NAVIGATION ---
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
    
    ROW + 1 call print(^.mode-restricted .is-normal { display: none; }^)
    ROW + 1 call print(^.mode-restricted .is-infusion { display: none; }^)
    ROW + 1 call print(^.mode-all .is-infusion { display: none; }^)
    ROW + 1 call print(^.mode-infusion .is-restricted { display: none; }^)
    ROW + 1 call print(^.mode-infusion .is-normal { display: none; }^)
    ROW + 1 call print(^.mode-hidden { display: none; }^)

    ; --- EXACT CSS FROM PROVIDED DOT SCRIPT ---
    ROW + 1 call print(^.wrap *, .wrap *:before, .wrap *:after{box-sizing:border-box}^)
    ROW + 1 call print(concat(^#dot-view {margin:0;font:^, v_font_size, ^/1.4 -apple-system,BlinkMacSystemFont,Segoe UI,Roboto,Arial,sans-serif;color:#111;background:#fff;padding:16px;}^))
    ROW + 1 call print(^.wrap{max-width:1200px;margin:0 auto;}^)
    ROW + 1 call print(^.wrap h1{font-size:18px;margin:0 0 8px;}^)
    ROW + 1 call print(^.wrap h2{font-size:15px;margin:16px 0 8px;padding-top:0;}^)
    ROW + 1 call print(^.sub{color:#444;margin:4px 0 16px;}^)
    ROW + 1 call print(^.legend{margin-top:6px;color:#555;font-size:12px}^)
    ROW + 1 call print(^.axisbar{display:flex;justify-content:space-between;margin:10px 0 8px calc(260px + 46px + 4px);color:#333;font-size:12px;}^)
    ROW + 1 call print(^.chart-wrap{overflow-x:auto;border:1px solid #ddd;background:#fff;margin-bottom:12px;}^)
    ROW + 1 call print(^table.chart-tbl{border-collapse:collapse;border-spacing:0;width:100%;}^)
    ROW + 1 call print(^col.med{width:260px}^)
    ROW + 1 call print(^col.dot{width:46px}^)
    ROW + 1 call print(^table.chart-tbl th, table.chart-tbl td{vertical-align:top;padding:0px 4px;text-align:left;font-size:12px;}^)
    ROW + 1 call print(^table.chart-tbl thead th{vertical-align:middle;}^)
    ROW + 1 call print(^table.data-tbl th {^)
    ROW + 1 call print(^  background:#e7eaee !important;^)
    ROW + 1 call print(^  color:#2f3c4b;^)
    ROW + 1 call print(^  border:1px solid #b5b5b5;^)
    ROW + 1 call print(^  padding:4px 8px !important;^)
    ROW + 1 call print(^  text-align:left;^)
    ROW + 1 call print(^  font-weight:600 !important;^)
    ROW + 1 call print(^  height:26px !important;^)
    ROW + 1 call print(^  line-height:1.2 !important;^)
    ROW + 1 call print(^  vertical-align:middle !important;^)
    ROW + 1 call print(^  font-size:12px !important;^)
    ROW + 1 call print(^}^)
    ROW + 1 call print(^table.chart-tbl thead th.label {^)
    ROW + 1 call print(^  background:#e7eaee !important;^)
    ROW + 1 call print(^  color:#2f3c4b;^)
    ROW + 1 call print(^  border:1px solid #b5b5b5;^)
    ROW + 1 call print(^  padding:4px 8px !important;^)
    ROW + 1 call print(^  text-align:left;^)
    ROW + 1 call print(^  font-weight:600 !important;^)
    ROW + 1 call print(^  height:26px !important;^)
    ROW + 1 call print(^  line-height:1.2 !important;^)
    ROW + 1 call print(^  vertical-align:middle !important;^)
    ROW + 1 call print(^  font-size:12px !important;^)
    ROW + 1 call print(^}^)
    ROW + 1 call print(^table.chart-tbl thead tr.ticks th{background:transparent;border:0;padding:0;color:#555;}^)
    ROW + 1 call print(^table.chart-tbl thead tr.ticks th.sticky-med, table.chart-tbl thead tr.ticks th.sticky-dot {border-right:1px solid #ccc;border-bottom:1px solid #b5b5b5;}^)
    ROW + 1 call print(concat(^table.chart-tbl td.medname{font-size:^, v_med_font_size, ^ !important;vertical-align:middle;padding:2px 6px;}^))
    ROW + 1 call print(^table.chart-tbl tbody td.label{vertical-align:middle;padding:2px 6px;}^)
    ROW + 1 call print(^.dot-val, table.data-tbl td.dot-val, table.chart-tbl td.dot-val{text-align:center !important;vertical-align:middle !important;}^)
    ROW + 1 call print(^table.chart-tbl tbody td.dot-val{background:#fff;}^)
    ROW + 1 call print(^table.chart-tbl tbody th.sticky-med, table.chart-tbl tbody td.sticky-med {position:sticky;left:0;background:#fff;z-index:10;border-right:1px solid #ccc;border-bottom:1px solid #d6d9dd;padding-left:8px;width:260px;}^)
    ROW + 1 call print(^table.chart-tbl tbody th.sticky-dot, table.chart-tbl tbody td.sticky-dot {position:sticky;left:260px;background:#fff;z-index:10;border-right:1px solid #ccc;border-bottom:1px solid #d6d9dd;width:46px;}^)
    ROW + 1 call print(^tr.even td.sticky-med, tr.even td.sticky-dot { background: #f5f5f5 !important; }^)
    ROW + 1 call print(^tr.even td.dot-val { background: #f5f5f5 !important; }^)
    ROW + 1 call print(^table.data-tbl tr.even td { background: #f5f5f5; }^)
    ROW + 1 call print(^table.chart-tbl tbody th.label{z-index:11;}^)
    ROW + 1 call print(^table.chart-tbl thead th.sticky-med {position:sticky;left:0;z-index:15;}^)
    ROW + 1 call print(^table.chart-tbl thead th.sticky-dot {position:sticky;left:260px;z-index:15;}^)
    ROW + 1 call print(^table.data-tbl{border-collapse:collapse;width:100%;margin-top:12px;font-size:12px;border:1px solid #b5b5b5;border-bottom:2px solid #a0a0a0;}^)
    ROW + 1 call print(^table.data-tbl td{border:1px solid #d6d9dd;padding:4px 6px;text-align:left;background:#fff;}^)
    ROW + 1 call print(^table.data-tbl tbody tr:last-child td{border-bottom:2px solid #a0a0a0;}^)
    ROW + 1 call print(^.strip{display:flex;gap:1px;align-items:center;padding:4px 0;font-size:0;white-space:nowrap;overflow:visible;}^)
    ROW + 1 call print(^.cell,.tick{flex:0 0 14px;width:14px;height:14px;display:inline-flex;align-items:center;justify-content:center;text-align:center;font-size:10px;}^)
    ROW + 1 call print(^.tick{color:#555;border:1px solid transparent;border-radius:3px;position:relative}^)
    ROW + 1 call print(^.ticks .strip{padding-top:20px}^)
    ROW + 1 call print(^.ticks .tick{overflow:visible;text-overflow:initial}^)
    ROW + 1 call print(^.tick .mo{position:absolute;top:-14px;left:50%;transform:translateX(-50%);font-size:10px;color:#555;white-space:nowrap;pointer-events:none}^)
    ROW + 1 call print(^.cell{border:1px solid #ccc;border-radius:3px;background:#fff}^)
    ROW + 1 call print(^.cell.on{background:#0086CE;border-color:#0D66A1;color:#fff;font-weight:600}^)
    ROW + 1 call print(^.cell.on:empty::before{content:"1"}^)
    ROW + 1 call print(^.cell.sum-yes{background:#ED1C24;border-color:#cc0000;}^)
    ROW + 1 call print(^.cell.sum-no{background:#A8D08D;border-color:#88b070;}^)
    ROW + 1 call print(^.summary-row td{border-top:1px solid #ccc;padding-top:4px;}^)
    ROW + 1 call print(^.ticks th{border-bottom:0;background:#fff}^)
    ROW + 1 call print(^.pill{display:inline-block;padding:2px 6px;border-radius:12px;background:#eef;color:#334;}^)
    
    ; --- ACUITY SCORE STYLING ---
    ROW + 1 call print(^.acuity-banner { padding: 20px; color: #fff; font-size: 24px; font-weight: bold; text-align: center; margin: 15px; border-radius: 5px; }^)
    ROW + 1 call print(^.acuity-Red { background-color: #dc3545; border: 2px solid #b02a37; }^)
    ROW + 1 call print(^.acuity-Amber { background-color: #ffc107; color: #333; border: 2px solid #d39e00; }^)
    ROW + 1 call print(^.acuity-Green { background-color: #28a745; border: 2px solid #1e7e34; }^)
    ROW + 1 call print(^.acuity-reasons { background: #f8f9fa; border: 1px solid #ddd; padding: 15px; margin: 15px; border-radius: 5px; font-size: 14px; }^)
    
    ROW + 1 call print(^</style>^)
    ROW + 1 call print(^</head>^)

    ROW + 1 call print(^<body onload='showRestricted(); resizeLayout();'>^)

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
    ROW + 1 call print(^<div id='btn6' class='tab-btn' onclick='showAcuity()'>Maternity Acuity</div>^)
    ROW + 1 call print(^</div>^)
    
    ; =========================================================================
    ; TAB 6: ACUITY VIEW
    ; =========================================================================
    ROW + 1 call print(^<div id='acuity-view' style='display:none;' class='content-box'>^)
    ROW + 1 call print(CONCAT(^<div class='acuity-banner acuity-^, rec_acuity->color, ^'>Acuity Score: ^, TRIM(CNVTSTRING(rec_acuity->score)), ^ (Triage: ^, rec_acuity->color, ^)</div>^))
    
    ROW + 1 call print(^<div class='acuity-reasons'>^)
    ROW + 1 call print(^<h3 style='margin-top:0;'>Triggered Risk Factors</h3><ul>^)
    
    IF (rec_acuity->reason_cnt > 0)
        FOR (x = 1 TO rec_acuity->reason_cnt)
            ROW + 1 call print(CONCAT(^<li><b>[+^, TRIM(CNVTSTRING(rec_acuity->reasons[x].points)), ^ Points]</b> ^, rec_acuity->reasons[x].text, ^</li>^))
        ENDFOR
    ELSE
        ROW + 1 call print(^<li>No specific high-risk triggers detected (Routine Low-Acuity).</li>^)
    ENDIF
    
    ROW + 1 call print(^</ul></div>^)
    ROW + 1 call print(^<div class='legend' style='margin:15px;'><i>References: ISMP High-Alert Medications in Acute Care; WHO Medication Without Harm (Polypharmacy criteria); HIQA National Standards for Patient Safety. Note: Laboratory parameters are excluded from this calculation.</i></div>^)
    ROW + 1 call print(^</div>^)

    ; =========================================================================
    ; TAB 5: DOT Blob View (Exact Extracted HTML code generation)
    ; =========================================================================
    ROW + 1 call print(^<div id='dot-view' style='display:none;' class='content-box'>^)
    ROW + 1 call print(^<div class="wrap">^)
    ROW + 1 call print(^<h1>Antimicrobial Administrations by Date</h1>^)
    ROW + 1 call print(^<div class="legend">Each blue square marks a <b>day</b> where the medication has been administered. A number indicates the count of administrations for that day.<br><b>Summary:</b> Red = Antimicrobial given, Green = No antimicrobial given.</div>^)
    ROW + 1 call print(v_axis_html)
    
    ROW + 1 call print(^<div class="chart-wrap">^)
    ROW + 1 call print(^<table class="chart-tbl"><colgroup><col class="med"><col class="dot"><col></colgroup><thead>^)
    ROW + 1 call print(^<tr><th class="label sticky-med">Medication</th><th class="label sticky-dot">DOT</th><th class="label">Days</th></tr>^)
    if (textlen(v_header_html) > 0)
        ROW + 1 call print(^<tr class="ticks"><th class="sticky-med"></th><th class="sticky-dot"></th><th><div class="strip">^)
        ROW + 1 call print(v_header_html)
        ROW + 1 call print(^</div></th></tr>^)
    endif
    ROW + 1 call print(^</thead><tbody>^)

    v_pos = findstring(v_token, v_chart_rows)
    while (v_pos > 0)
        v_seglen = v_pos + v_toklen - 1
        v_rowseg = substring(1, v_seglen, v_chart_rows)
        ROW + 1 call print(v_rowseg)
        v_len = textlen(v_chart_rows)
        v_chart_rows = substring(v_pos + v_toklen, v_len - (v_pos + v_toklen - 1), v_chart_rows)
        v_pos = findstring(v_token, v_chart_rows)
    endwhile
    if (textlen(v_chart_rows) > 0)
        ROW + 1 call print(v_chart_rows)
    endif
    ROW + 1 call print(^</tbody></table></div>^) 

    ROW + 1 call print(^<h2>Antimicrobial Order Details</h2>^)
    ROW + 1 call print(^<table class="data-tbl">^)
    ROW + 1 call print(^<colgroup><col class="med"><col class="dot"></colgroup>^)
    ROW + 1 call print(^<thead><tr>^)
    ROW + 1 call print(^<th>Medication</th><th>DOT</th><th>Target Dose</th><th>Indication</th>^)
    ROW + 1 call print(^<th>Start Date</th><th>Latest Status</th><th>Status Date</th><th>Order ID</th>^)
    ROW + 1 call print(^</tr></thead>^)
    ROW + 1 call print(^<tbody>^)

    v_pos = findstring(v_token, v_table_rows)
    while (v_pos > 0)
        v_seglen = v_pos + v_toklen - 1
        v_rowseg = substring(1, v_seglen, v_table_rows)
        ROW + 1 call print(v_rowseg)
        v_len = textlen(v_table_rows)
        v_table_rows = substring(v_pos + v_toklen, v_len - (v_pos + v_toklen - 1), v_table_rows)
        v_pos = findstring(v_token, v_table_rows)
    endwhile
    if (textlen(v_table_rows) > 0)
        ROW + 1 call print(v_table_rows)
    endif

    ROW + 1 call print(^</tbody></table>^)
    ROW + 1 call print(^<div class="legend" style="margin-top:8px;">Days of therapy (DOT) for antimicrobial orders which have been administered are included in this report.</div>^)
    ROW + 1 call print(^</div></div>^)

    ; =========================================================================
    ; GP Blob View - IE5 Table Split Pane UI with Navigation
    ; =========================================================================
    ROW + 1 call print(^<div id='gp-blob-view' style='display:none;'>^)
    ROW + 1 call print(^<table id="gp-table" width="100%" border="0" cellpadding="0" cellspacing="0" style="height:500px;"><tr>^)
    
    ROW + 1 call print(^<td class="gp-sidebar"><div id="scroll-side" class="gp-scroll-side">^)
    FOR (x = 1 TO size(rec_blob->list, 5))
        IF (x = 1)
            ROW + 1 call print(concat(^<a id="nav-^, TRIM(CNVTSTRING(x)), ^" class="gp-nav-item active-nav" href="javascript:goToBlob(^, TRIM(CNVTSTRING(x)), ^)">&#128196; ^, rec_blob->list[x].dt_tm, ^</a>^))
        ELSE
            ROW + 1 call print(concat(^<a id="nav-^, TRIM(CNVTSTRING(x)), ^" class="gp-nav-item" href="javascript:goToBlob(^, TRIM(CNVTSTRING(x)), ^)">&#128196; ^, rec_blob->list[x].dt_tm, ^</a>^))
        ENDIF
    ENDFOR
    IF (size(rec_blob->list, 5) = 0)
        ROW + 1 call print(^<div class="gp-nav-item">No records</div>^)
    ENDIF
    ROW + 1 call print(^</div></td>^)

    ROW + 1 call print(^<td class="gp-content">^)
    
    ROW + 1 call print(^<div class="gp-content-header">^)
    ROW + 1 call print(^  <button class="nav-btn" onclick="prevBlob()">&laquo; Previous</button>^)
    ROW + 1 call print(^  <button class="nav-btn" onclick="nextBlob()">Next &raquo;</button>^)
    ROW + 1 call print(^</div>^)
    
    ROW + 1 call print(^<div id="scroll-main" class="gp-scroll-main">^)
    FOR (x = 1 TO size(rec_blob->list, 5))
        ROW + 1 call print(concat(^<a name="blob-^, TRIM(CNVTSTRING(x)), ^"></a>^))
        ROW + 1 call print(^<div class="blob-record">^)
        ROW + 1 call print(concat(^<div class="blob-meta">Performed: ^, rec_blob->list[x].dt_tm, ^ by ^, rec_blob->list[x].prsnl, ^</div>^) )
        ROW + 1 call print(^<div class="blob-text">^)

        vLen  = textlen(rec_blob->list[x].blob_text)
        bsize = 1
        WHILE (bsize <= vLen)
            call print(substring(bsize, 500, rec_blob->list[x].blob_text))
            bsize = bsize + 500
        ENDWHILE

        ROW + 1 call print(^</div></div>^)
    ENDFOR
    IF (size(rec_blob->list, 5) = 0)
        ROW + 1 call print(^<p>No GP Medication Details found for this patient.</p>^)
    ENDIF
    
    ROW + 1 call print(^<div style="height: 500px; width: 100%;"></div>^)
    
    ROW + 1 call print(^</div></td>^) 
    
    ROW + 1 call print(^</tr></table></div>^) 
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
                AND
                (FINDSTRING("Glucose", MNEMONIC) > 0 OR FINDSTRING("Sodium", MNEMONIC) > 0 OR FINDSTRING("Maintelyte", MNEMONIC) > 0)
            )
                ROW + 1 call print(^<div class='inf-row is-infusion'>^)
                call print(concat(^<div class='inf-col' style='width:120px;'>^, START_DT, ^</div>^))
                call print(concat(^<div class='inf-col' style='width:250px;'><b>^, MNEMONIC, ^</b></div>^))
                call print(^<div class='inf-col' style='width:80px;'><span class='type-badge' style='background:#17a2b8;'>FLUID</span></div>^)
                call print(^<div class='inf-col' style='width:150px;'>^)
                call print(concat(
                    ~<a class='print-link' href='javascript:CCLLINK("01_BK_NICU_FLUID_FFL_FLIPPED:Group1", "MINE, ~,
                    TRIM(CNVTSTRING($patient_id)), ~, ~, TRIM(CNVTSTRING(ORDER_ID)), ~" ,0)'>Print Fluid Label</a>~
                ))
                call print(^</div><div style='clear:both;'></div></div>^)

            ELSEIF (FINDSTRING("INTERMITTENT", CNVTUPPER(DISP_CAT)) > 0)
                ROW + 1 call print(^<div class='inf-row is-infusion'>^)
                call print(concat(^<div class='inf-col' style='width:120px;'>^, START_DT, ^</div>^))
                call print(concat(^<div class='inf-col' style='width:250px;'><b>^, MNEMONIC, ^</b></div>^))
                call print(^<div class='inf-col' style='width:80px;'><span class='type-badge' style='background:#ffc107; color:black;'>INTERM</span></div>^)
                call print(^<div class='inf-col' style='width:150px;'>^)
                call print(concat(
                    ~<a class='print-link' href='javascript:CCLLINK("01_BK_NICU_INTER_FFL_FLIPPED:Group1", "MINE, ~,
                    TRIM(CNVTSTRING($patient_id)), ~, ~, TRIM(CNVTSTRING(ORDER_ID)), ~" ,0)'>Print Intermittent Label</a>~
                ))
                call print(^</div><div style='clear:both;'></div></div>^)

            ELSEIF (FINDSTRING("UD", CNVTUPPER(DISP_CAT)) > 0)
                ROW + 1 call print(^<div class='inf-row is-infusion'>^)
                call print(concat(^<div class='inf-col' style='width:120px;'>^, START_DT, ^</div>^))
                call print(concat(^<div class='inf-col' style='width:250px;'><b>^, MNEMONIC, ^</b></div>^))
                call print(^<div class='inf-col' style='width:80px;'><span class='type-badge' style='background:#6c757d;'>PN / UD</span></div>^)
                call print(^<div class='inf-col' style='width:150px;'>^)
                call print(concat(
                    ~<a class='print-link' href='javascript:CCLLINK("01_BK_NICU_PN_FFL_FLIPPED:Group1", "MINE, ~,
                    TRIM(CNVTSTRING($patient_id)), ~, ~, TRIM(CNVTSTRING(ORDER_ID)), ~" ,0)'>Print PN Label</a>~
                ))
                call print(^</div><div style='clear:both;'></div></div>^)

            ELSE
                ROW + 1 call print(^<div class='inf-row is-infusion'>^)
                call print(concat(^<div class='inf-col' style='width:120px;'>^, START_DT, ^</div>^))
                call print(concat(^<div class='inf-col' style='width:250px;'><b>^, MNEMONIC, ^</b></div>^))
                call print(^<div class='inf-col' style='width:80px;'><span class='type-badge' style='background:#28a745;'>SCI</span></div>^)
                call print(^<div class='inf-col' style='width:150px;'>^)
                call print(concat(
                    ~<a class='print-link' href='javascript:CCLLINK("01_BK_NICU_INF_FFL_FLIPPED:Group1", "MINE, ~,
                    TRIM(CNVTSTRING($patient_id)), ~, ~, TRIM(CNVTSTRING(ORDER_ID)), ~" ,0)'>Print SCI Label</a>~
                ))
                call print(^</div><div style='clear:both;'></div></div>^)
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