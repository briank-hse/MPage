drop program 01_meds_DOT_by_date_comb_html3 go
create program 01_meds_DOT_by_date_comb_html3

/*****************************************************************************
  Antimicrobial Days of Therapy - Combined Chart and Table View
  MODIFIED: 
  - Implemented Unified Record Structure (admin_rec) to merge PowerChart (MAE)
    and SN Anesthesia (SA) administrations safely.
  - Retained all legacy variables, styling, and chunking logic.
  - Applied IE-quirks wrapper fix for fixed-width chart columns (180px).
  - Added mathematical grand totals for DOT to the summary row.
  - Added new 'Dose' column splitting Target Dose space, powered by 
    ORDER_DETAIL STRENGTH (2056) and STRENGTHUNIT (2057).
  - Fixed hidden whitespace in Cerner OEF fields dropping volume-only doses.
******************************************************************************/

prompt
  "Output to File/Printer/MINE" = "MINE"
  , "Patient_ID" = 0
  , "Days Lookback" = 180
with OUTDEV, PAT_PersonId, LOOKBACK

/* ========================================================================== */
/* Variable Declarations                                                      */
/* ========================================================================== */

/* --- Set Font Size --- */
declare v_font_size      = vc with noconstant("13px")
declare v_med_font_size = vc with noconstant("14px")

/* --- Meta and Header Variables --- */
declare v_mrn         = vc with noconstant("")
declare v_name        = vc with noconstant("")
declare v_admit_dt    = vc with noconstant("")
declare v_los         = vc with noconstant("")
declare v_lookback    = vc with noconstant("")
declare v_chart_meta  = vc with noconstant(""), maxlen=2000
declare v_table_meta  = vc with noconstant(""), maxlen=2000

/* --- Chart-Specific Variables --- */
declare v_axis_html   = vc with noconstant(""), maxlen=2000
declare v_header_html = vc with noconstant(""), maxlen=65534
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
declare v_med_dot_total   = i4 with noconstant(0)
declare v_med_dose_total  = i4 with noconstant(0)
declare v_doses           = i4 with noconstant(0)
declare v_row_cnt     = i4 with noconstant(0)

/* --- Summary Row Variables --- */
declare v_all_days_list = vc with noconstant(""), maxlen=65534
declare v_sum_strip     = vc with noconstant(""), maxlen=65534
declare v_spacer_strip  = vc with noconstant(""), maxlen=65534
declare v_total_summary_dot = i4 with noconstant(0)
declare v_grand_total_dot   = i4 with noconstant(0)
declare v_grand_total_doses = i4 with noconstant(0)

/* --- Chart Parsing Variables --- */
declare v_findpos          = i4 with noconstant(0)
declare v_after            = vc with noconstant(""), maxlen=65534
declare v_endpos           = i4 with noconstant(0)
declare v_detail_str       = vc with noconstant("")
declare v_pipe_pos         = i4 with noconstant(0)
declare v_indication       = vc with noconstant(""), maxlen=255
declare v_discontinue_rsn  = vc with noconstant(""), maxlen=255

/* --- Table-Specific Variables --- */
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
declare v_chart_rows  = vc with noconstant(""), maxlen=65534

/* --- General Working Variables --- */
declare v_low_dt      = dq8 with noconstant(null)
declare v_high_now_dt = dq8 with noconstant(null)
declare v_begin_dt_str= vc with noconstant("")
declare v_end_dt_str  = vc with noconstant("")
declare v_today       = dq8 with noconstant(0)
declare v_debug_info  = vc with noconstant(""), maxlen=2000
declare v_local_dt    = dq8 with noconstant(0)
declare v_dose_str    = vc with noconstant("")
declare v_actual_dose_str = vc with noconstant("")
declare v_s           = vc with noconstant("")
declare v_v           = vc with noconstant("")
declare v_order_src   = vc with noconstant("")

/* --- Debug Count Variables --- */
declare v_pc_cnt      = i4 with noconstant(0)
declare v_sn_cnt      = i4 with noconstant(0)

/* --- Safe Print/Chunking Variables --- */
declare v_token       = vc with noconstant("</tr>")
declare v_toklen      = i4 with noconstant(5)
declare v_pos         = i4 with noconstant(0)
declare v_len         = i4 with noconstant(0)
declare v_seglen      = i4 with noconstant(0)
declare v_rowseg      = vc with noconstant(""), maxlen=65534
declare v_chunk       = i4 with constant(32000)

/* ========================================================================== */
/* Unified Record Structure Definition                                        */
/* ========================================================================== */
free record admin_rec
record admin_rec (
  1 cnt = i4
  1 qual[*]
    2 admin_dt_tm = dq8
    2 order_id    = f8
    2 admin_id    = f8
    2 src         = vc
)

/* ========================================================================== */
/* PASS 0A: Gather PowerChart Administrations (MAE)                           */
/* ========================================================================== */
select into "nl:"
from person p, clinical_event ce, med_admin_event m, orders o,
     code_value_event_r cr, order_catalog oc,
     order_catalog_synonym ocs, order_entry_format oe
plan p where p.person_id = $PAT_PersonId
join ce where ce.person_id = p.person_id
  and ce.performed_dt_tm between cnvtdatetime(curdate-$LOOKBACK,0) and cnvtdatetime(curdate,235959)
join m where m.event_id = ce.event_id
  and m.event_type_cd = value(uar_get_code_by("MEANING",4000040,"TASKCOMPLETE"))
join o where o.order_id = m.template_order_id
join cr where cr.event_cd = ce.event_cd
join oc where oc.catalog_cd = cr.parent_cd and oc.catalog_type_cd = 2516
join ocs where ocs.catalog_cd = oc.catalog_cd
join oe where oe.oe_format_id = ocs.oe_format_id
  and oe.oe_format_id in (14497910, 14498121)
order by m.event_id
head report
  admin_rec->cnt = 0
head m.event_id
  admin_rec->cnt = admin_rec->cnt + 1
  call alterlist(admin_rec->qual, admin_rec->cnt)
  admin_rec->qual[admin_rec->cnt].admin_dt_tm = ce.event_end_dt_tm
  admin_rec->qual[admin_rec->cnt].order_id    = o.order_id
  admin_rec->qual[admin_rec->cnt].admin_id    = ce.event_id
  admin_rec->qual[admin_rec->cnt].src         = "PC"
with nocounter

/* ========================================================================== */
/* PASS 0B: Gather SN Anesthesia Administrations (SA)                         */
/* ========================================================================== */
select into "nl:"
from person p, orders o, sa_medication_admin sma, sa_med_admin_item smai,
     order_catalog_synonym ocs, order_entry_format oe
plan p where p.person_id = $PAT_PersonId
join o where o.person_id = p.person_id
join sma where sma.order_id = o.order_id
  and sma.active_ind = 1
join smai where smai.sa_medication_admin_id = sma.sa_medication_admin_id
  and smai.active_ind = 1
  and smai.admin_start_dt_tm >= cnvtdatetimeutc(cnvtdatetime(curdate-$LOOKBACK,0))
join ocs where ocs.synonym_id = o.synonym_id
join oe where oe.oe_format_id = ocs.oe_format_id
  and oe.oe_format_id in (14497910, 14498121)
  and oe.catalog_type_cd = 2516.00
order by smai.sa_med_admin_item_id
head smai.sa_med_admin_item_id
  v_local_dt = cnvtdatetimeutc(smai.admin_start_dt_tm)
  admin_rec->cnt = admin_rec->cnt + 1
  call alterlist(admin_rec->qual, admin_rec->cnt)
  admin_rec->qual[admin_rec->cnt].admin_dt_tm = v_local_dt
  admin_rec->qual[admin_rec->cnt].order_id    = o.order_id
  admin_rec->qual[admin_rec->cnt].admin_id    = smai.sa_med_admin_item_id
  admin_rec->qual[admin_rec->cnt].src         = "SN"
with nocounter

/* ========================================================================== */
/* PASS 1: Determine Date Range & Demographics                                */
/* ========================================================================== */
select into "nl:"
from person p, person_alias pa, encounter e
plan p where p.person_id = $PAT_PersonId
join pa where pa.person_id = p.person_id and pa.person_alias_type_cd = 10.00
join e where e.person_id = p.person_id
head report
  v_first = 1
  v_mrn   = pa.alias
  v_name  = p.name_full_formatted
  v_admit_dt = format(e.arrive_dt_tm,"DD/MM/YYYY;;d")
  v_low_dt   = cnvtdatetime(cnvtdate(e.arrive_dt_tm),0)
  v_high_now_dt = cnvtdatetime(curdate,0)
  v_today      = cnvtdate(curdate)
  v_los      = cnvtstring((datetimediff(v_high_now_dt,v_low_dt,7))+1)
  v_lookback = cnvtstring($LOOKBACK)
  v_begin_dt_str = format((curdate-$LOOKBACK),"DD/MM/YYYY;;d")
  v_end_dt_str   = format(curdate,"DD/MM/YYYY;;d")
  v_debug_info = concat("Query Range Start: ", format(cnvtdate(curdate - $LOOKBACK), "DD-MMM-YYYY;;D"), 
                       " | Patient_ID: ", cnvtstring($PAT_PersonId), " | Total Admins: ", cnvtstring(admin_rec->cnt))
with nocounter

/* Dynamically find min/max dates from populated memory record */
if (admin_rec->cnt > 0)
  set v_first = 0
  set v_min_dt = cnvtdate(admin_rec->qual[1].admin_dt_tm)
  set v_max_dt = cnvtdate(admin_rec->qual[1].admin_dt_tm)
  set v_i = 1
  while (v_i <= admin_rec->cnt)
    set v_local_dt = cnvtdate(admin_rec->qual[v_i].admin_dt_tm)
    if (v_local_dt < v_min_dt) set v_min_dt = v_local_dt endif
    if (v_local_dt > v_max_dt) set v_max_dt = v_local_dt endif
    set v_i = v_i + 1
  endwhile
  if (v_max_dt < v_today) set v_max_dt = v_today endif
  
  /* Count PC vs SN */
  set v_pc_cnt = 0
  set v_sn_cnt = 0
  set v_i = 1
  while (v_i <= admin_rec->cnt)
    if (admin_rec->qual[v_i].src = "PC") set v_pc_cnt = v_pc_cnt + 1
    elseif (admin_rec->qual[v_i].src = "SN") set v_sn_cnt = v_sn_cnt + 1
    endif
    set v_i = v_i + 1
  endwhile
endif

/* --- Build Chart Axis and Header HTML --- */
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

/* --- Build Meta Strings --- */
set v_chart_meta = concat('')
set v_table_meta = '<div class="sub"><b>MRN:</b> '
set v_table_meta = concat(v_table_meta, v_mrn)
set v_table_meta = concat(v_table_meta, " &nbsp; <b>Begin:</b> ", v_begin_dt_str)
set v_table_meta = concat(v_table_meta, " &nbsp;  End:</b> ", v_end_dt_str)
set v_table_meta = concat(v_table_meta, " &nbsp; <b>Admission:</b> ", v_admit_dt)
set v_table_meta = concat(v_table_meta, " &nbsp; <b>LOS:</b> ", v_los, " days")
set v_table_meta = concat(v_table_meta, " &nbsp; <b>Lookback:</b> ", v_lookback, " days</div>")

/* ========================================================================== */
/* PASS 2: Build Chart Rows (Driven from Record Structure)                    */
/* ========================================================================== */
set v_chart_rows = ""
if (admin_rec->cnt > 0)
select into "nl:"
  med_name = trim(oc.primary_mnemonic)
, mdy = format(admin_rec->qual[d.seq].admin_dt_tm, "YYYYMMDD;;D")
, indication = substring(1,60,trim(od_indication.oe_field_display_value))
, discontinue_reason = substring(1,60,trim(od_dcreason.oe_field_display_value))
, src_id = admin_rec->qual[d.seq].admin_id
, admin_src = admin_rec->qual[d.seq].src
from
  (dummyt d with seq = admin_rec->cnt)
, orders o
, order_catalog oc
, order_detail od_indication
, order_detail od_dcreason
plan d
join o where o.order_id = admin_rec->qual[d.seq].order_id
join oc where oc.catalog_cd = o.catalog_cd
join od_indication where od_indication.order_id = outerjoin(o.order_id)
  and od_indication.oe_field_meaning = outerjoin("INDICATION")
join od_dcreason where od_dcreason.order_id = outerjoin(o.order_id)
  and od_dcreason.oe_field_meaning = outerjoin("DCREASON")

order by cnvtupper(trim(oc.primary_mnemonic)), mdy, src_id

head report
  v_curr_med = ""
  v_dates_kv = ""
  v_details_kv = ""
  v_all_days_list = ""
  v_row_cnt = 0
  v_grand_total_dot = 0

head med_name
  v_curr_med = med_name
  v_dates_kv = ""
  v_details_kv = ""
  v_med_dot_total  = 0
  v_med_dose_total = 0 

head mdy
  v_cnt_day = 0

head src_id
  v_cnt_day = v_cnt_day + 1
  v_med_dose_total = v_med_dose_total + 1

foot mdy
  v_dates_kv = concat(v_dates_kv, "~", mdy, ":", cnvtstring(v_cnt_day), "~")
  v_details_kv = concat(v_details_kv, "~", mdy, ":", indication, "|", discontinue_reason, "~")
  v_med_dot_total = v_med_dot_total + 1
    
  if (findstring(concat("~", mdy, "~"), v_all_days_list) = 0)
    v_all_days_list = concat(v_all_days_list, "~", mdy, "~")
  endif

foot med_name
  if (v_days > 0)
    v_row_cnt = v_row_cnt + 1
    
    v_grand_total_dot = v_grand_total_dot + v_med_dot_total
    
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
        v_after = substring(v_findpos + 10, textlen(v_details_kv) - (v_findpos + 9), v_details_kv)
        v_endpos = findstring("~", v_after)
        v_detail_str = ""
        if (v_endpos > 0) v_detail_str = substring(1, v_endpos - 1, v_after)
        else v_detail_str = v_after
        endif
        v_pipe_pos = 0
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
      '<td width="180" class="label medname sticky-med"><div style="width:180px; word-wrap:break-word; white-space:normal;">', v_curr_med, '</div></td>',
      '<td width="46" class="label dot-val sticky-doses"><div style="width:46px; text-align:center;"><span class="pill" title="', v_curr_med, ' - Total Doses: ', trim(cnvtstring(v_med_dose_total)), '">', cnvtstring(v_med_dose_total), '</span></div></td>',
      '<td width="46" class="label dot-val sticky-dot"><div style="width:46px; text-align:center;"><span class="pill" title="', v_curr_med, ' - Total Days of Therapy: ', trim(cnvtstring(v_med_dot_total)), '">', cnvtstring(v_med_dot_total), '</span></div></td>',
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
            '<td width="180" class="label sticky-med"><div style="width:180px; white-space:normal;">Antimicrobial Summary</div></td>',
            '<td width="46" class="label sticky-doses"><div style="width:46px;"></div></td>',
            '<td width="46" class="label dot-val sticky-dot"><div style="width:46px; text-align:center;"><span class="pill" title="Total Summary Days of Therapy: ', cnvtstring(v_grand_total_dot), '">', cnvtstring(v_grand_total_dot), '</span></div></td>',
            '<td><div class="strip">', v_sum_strip, '</div></td>',
          '</tr>')
  endif

with nocounter
endif ; admin_rec->cnt > 0 (Pass 2)

/* ========================================================================== */
/* PASS 3: Build Table Rows (Driven from Record Structure)                    */
/* ========================================================================== */
set v_table_rows = ""
if (admin_rec->cnt > 0)
select into "nl:"
  med_name = trim(oc.primary_mnemonic)
, admin_src = admin_rec->qual[d.seq].src
, day_key = format(admin_rec->qual[d.seq].admin_dt_tm, "yyyymmdd")
, o.current_start_dt_tm
, o_order_status_disp = uar_get_code_display(o.order_status_cd)
, o.status_dt_tm
, indication = substring(1,60,trim(od_indication.oe_field_display_value))
, ordered_target_dose = oi.ordered_dose
, ordered_target_dose_unit = uar_get_code_display(oi.ordered_dose_unit_cd)
  /* NOTE: Added trim flag 3 here to completely strip hidden Cerner whitespace */
, strength_val = substring(1,60,trim(od_strength.oe_field_display_value, 3))
, strength_unit  = substring(1,60,trim(od_strengthunit.oe_field_display_value, 3))
, volume_val     = substring(1,60,trim(od_volume.oe_field_display_value, 3))
, volume_unit    = substring(1,60,trim(od_volumeunit.oe_field_display_value, 3))
, o.order_id
from
  (dummyt d with seq = admin_rec->cnt)
, orders o
, order_catalog oc
, order_ingredient oi
, order_detail od_indication
, order_detail od_strength
, order_detail od_strengthunit
, order_detail od_volume
, order_detail od_volumeunit
plan d
join o where o.order_id = admin_rec->qual[d.seq].order_id
join oc where oc.catalog_cd = o.catalog_cd
join oi where oi.order_id = outerjoin(o.order_id)
  and oi.comp_sequence = outerjoin(1)
join od_indication where od_indication.order_id = outerjoin(o.order_id)
  and od_indication.oe_field_meaning_id = outerjoin(15)
join od_strength where od_strength.order_id = outerjoin(o.order_id)
  and od_strength.oe_field_meaning_id = outerjoin(2056)
join od_strengthunit where od_strengthunit.order_id = outerjoin(o.order_id)
  and od_strengthunit.oe_field_meaning_id = outerjoin(2057)
join od_volume where od_volume.order_id = outerjoin(o.order_id)
  and od_volume.oe_field_meaning_id = outerjoin(2058)
join od_volumeunit where od_volumeunit.order_id = outerjoin(o.order_id)
  and od_volumeunit.oe_field_meaning_id = outerjoin(2059)

order by o.order_id, cnvtupper(trim(oc.primary_mnemonic)), day_key

head report
  v_table_rows = ""
  v_row_cnt = 0

head o.order_id
  v_drug      = med_name
  v_order_src = admin_src
  v_dose  = 0.0
  v_unit  = ""
  v_ind   = ""
  v_start = ""
  v_stat  = ""
  v_sdt   = ""
  v_oid   = cnvtstring(o.order_id)
  v_dot   = 0
  v_doses = 0

head day_key
  v_dot = v_dot + 1

detail
  v_doses = v_doses + 1

foot o.order_id
  v_dose  = ordered_target_dose
  v_unit  = ordered_target_dose_unit
  v_ind   = indication
  v_start = format(o.current_start_dt_tm,"DD/MM/YYYY;;d")
  v_stat  = o_order_status_disp
  v_sdt   = format(o.status_dt_tm,"DD/MM/YYYY;;d")
  
  if (v_dose > 0)
    ; Format with enough decimal places then strip trailing zeros
    v_dose_str = trim(format(v_dose, "########.####"))
    ; Strip trailing zeros after decimal point
    while (textlen(v_dose_str) > 0 and substring(textlen(v_dose_str), 1, v_dose_str) = "0")
      v_dose_str = substring(1, textlen(v_dose_str) - 1, v_dose_str)
    endwhile
    ; Strip trailing decimal point
    if (textlen(v_dose_str) > 0 and substring(textlen(v_dose_str), 1, v_dose_str) = ".")
      v_dose_str = substring(1, textlen(v_dose_str) - 1, v_dose_str)
    endif
    v_dose_str = concat(trim(v_dose_str), " ", v_unit)
  else
    v_dose_str = ""
  endif
  
  v_actual_dose_str = ""
  v_s = ""
  v_v = ""
  
  if (textlen(strength_val) > 0)
    v_s = strength_val
    if (textlen(strength_unit) > 0)
      v_s = concat(v_s, " ", strength_unit)
    endif
  endif
  
  if (textlen(volume_val) > 0)
    v_v = volume_val
    if (textlen(volume_unit) > 0)
      v_v = concat(v_v, " ", volume_unit)
    endif
  endif
  
  if (textlen(v_s) > 0 and textlen(v_v) > 0)
    v_actual_dose_str = concat(v_s, " / ", v_v)
  elseif (textlen(v_s) > 0)
    v_actual_dose_str = v_s
  elseif (textlen(v_v) > 0)
    v_actual_dose_str = v_v
  endif
  
  ; Fallback: if order_detail fields empty, use order_ingredient dose (same as Target Dose)
  if (textlen(v_actual_dose_str) = 0 and textlen(v_dose_str) > 0)
    v_actual_dose_str = v_dose_str
  endif
  
  v_row_cnt = v_row_cnt + 1
  
  v_table_rows = concat(v_table_rows,
    '<tr', if(mod(v_row_cnt, 2) = 0) ' class="even"' else '' endif, '>',
      '<td width="180">', v_drug,
        if(v_order_src = "SN") ' <span style="color:#888;font-size:10px;">(Anes)</span>' else '' endif,
      '</td>',
      '<td width="46" class="dot-val"><span class="pill">', cnvtstring(v_doses), '</span></td>',
      '<td width="46" class="dot-val"><span class="pill">', cnvtstring(v_dot), '</span></td>',
      "<td>", v_dose_str, "</td>",
      "<td>", v_actual_dose_str, "</td>",
      "<td>", v_ind, "</td>",
      "<td>", v_start, "</td>",
      "<td>", v_stat, "</td>",
      "<td>", v_sdt, "</td>",
      "<td>", v_oid, "</td>",
    "</tr>"
  )
with nocounter
endif ; admin_rec->cnt > 0 (Pass 3)

if (textlen(v_table_rows) = 0)
  set v_table_rows = '<tr><td colspan="9">No antimicrobial orders found in the selected window.</td></tr>'
endif

/* ========================================================================== */
/* Final HTML Output Generation                                               */
/* ========================================================================== */
select into $outdev
from dummyt d
head report
  row +1 '<!doctype html><html lang="en"><head>'
  row +1 '<meta charset="utf-8" /><meta name="viewport" content="width=device-width, initial-scale=1" />'
  row +1 '<meta name="discern" content="CCLLINK"/>'
  row +1 '<title>Antimicrobial Days of Therapy - By Date</title>'
  row +1 '<style>'
  row +1 '*,*:before,*:after{box-sizing:border-box}'
  row +1 call print(concat('body{margin:0;font:', v_font_size, '/1.4 -apple-system,BlinkMacSystemFont,Segoe UI,Roboto,Arial,sans-serif;color:#111;background:#fff;padding:16px;}'))
  row +1 '.wrap{max-width:1200px;margin:0 auto;}'
  row +1 'h1{font-size:18px;margin:0 0 8px;}'
  row +1 'h2{font-size:15px;margin:16px 0 8px;padding-top:0;}'
  row +1 '.sub{color:#444;margin:4px 0 16px;}'
  row +1 '.legend{margin-top:6px;color:#555;font-size:12px}'
  row +1 '.axisbar{display:flex;justify-content:space-between;margin:10px 0 8px calc(180px + 46px + 4px);color:#333;font-size:12px;}'
    
  row +1 '.chart-wrap{overflow-x:auto;border:1px solid #ddd;background:#fff;margin-bottom:12px;}'
  row +1 'table.chart-tbl{border-collapse:collapse;border-spacing:0;}'
  row +1 'col.med{width:180px}'
  row +1 'col.doses{width:46px}'
  row +1 'col.dot{width:46px}'
  row +1 'table.chart-tbl th, table.chart-tbl td{vertical-align:top;padding:0px 4px;text-align:left;font-size:12px;}'
  row +1 'table.chart-tbl thead th{vertical-align:middle;}'
  
  row +1 'table.data-tbl th {'
  row +1 '  background:#e7eaee !important;'
  row +1 '  color:#2f3c4b;'
  row +1 '  border:1px solid #b5b5b5;'
  row +1 '  padding:4px 8px !important;'
  row +1 '  text-align:left;'
  row +1 '  font-weight:600 !important;'
  row +1 '  height:26px !important;'
  row +1 '  line-height:1.2 !important;'
  row +1 '  vertical-align:middle !important;'
  row +1 '  font-size:12px !important;'
  row +1 '}'

  row +1 'table.chart-tbl thead th.label {'
  row +1 '  background:#e7eaee !important;'
  row +1 '  color:#2f3c4b;'
  row +1 '  border:1px solid #b5b5b5;'
  row +1 '  padding:4px 8px !important;'
  row +1 '  text-align:left;'
  row +1 '  font-weight:600 !important;'
  row +1 '  height:26px !important;'
  row +1 '  line-height:1.2 !important;'
  row +1 '  vertical-align:middle !important;'
  row +1 '  font-size:12px !important;'
  row +1 '}'

  row +1 'table.chart-tbl thead tr.ticks th{background:transparent;border:0;padding:0;color:#555;}'
  row +1 'table.chart-tbl thead tr.ticks th.sticky-med, table.chart-tbl thead tr.ticks th.sticky-doses, table.chart-tbl thead tr.ticks th.sticky-dot {border-right:1px solid #ccc;border-bottom:1px solid #b5b5b5;}'

  row +1 call print(concat('table.chart-tbl td.medname{font-size:', v_med_font_size, ' !important;vertical-align:middle;padding:2px 6px;}'))
  row +1 'table.chart-tbl tbody td.label{vertical-align:middle;padding:2px 6px;}'
  
  row +1 '.dot-val, table.data-tbl td.dot-val, table.chart-tbl td.dot-val{text-align:center !important;vertical-align:middle !important;}'
  row +1 'table.chart-tbl tbody td.dot-val{background:#fff;}'
    
  row +1 'table.chart-tbl tbody th.sticky-med, table.chart-tbl tbody td.sticky-med {position:sticky;left:0;background:#fff;z-index:10;border-right:1px solid #ccc;border-bottom:1px solid #d6d9dd;padding-left:8px;width:180px;}'
  row +1 'table.chart-tbl tbody th.sticky-doses, table.chart-tbl tbody td.sticky-doses {position:sticky;left:180px;background:#fff;z-index:10;border-right:1px solid #ccc;border-bottom:1px solid #d6d9dd;width:46px;}'
  row +1 'table.chart-tbl tbody th.sticky-dot, table.chart-tbl tbody td.sticky-dot {position:sticky;left:226px;background:#fff;z-index:10;border-right:1px solid #ccc;border-bottom:1px solid #d6d9dd;width:46px;}'
  
  row +1 'tr.even td.sticky-med, tr.even td.sticky-doses, tr.even td.sticky-dot { background: #f5f5f5 !important;}'
  row +1 'tr.even td.dot-val { background: #f5f5f5 !important;}'
  row +1 'table.data-tbl tr.even td { background: #f5f5f5;}'

  row +1 'table.chart-tbl tbody th.label{z-index:11;}'
  row +1 'table.chart-tbl thead th.sticky-med {position:sticky;left:0;z-index:15;}'
  row +1 'table.chart-tbl thead th.sticky-doses {position:sticky;left:180px;z-index:15;}'
  row +1 'table.chart-tbl thead th.sticky-dot {position:sticky;left:226px;z-index:15;}'
    
  row +1 'table.data-tbl{border-collapse:collapse;margin-top:12px;font-size:12px;border:1px solid #b5b5b5;border-bottom:2px solid #a0a0a0;}'
  row +1 'table.data-tbl td{border:1px solid #d6d9dd;padding:4px 6px;text-align:left;background:#fff;}'
  row +1 'table.data-tbl td{border:1px solid #d6d9dd;padding:4px 6px;text-align:left;background:#fff;}'
  
  row +1 'table.data-tbl tbody tr:last-child td{border-bottom:2px solid #a0a0a0;}'
    
  row +1 '.strip{display:flex;gap:1px;align-items:center;padding:4px 0;font-size:0;white-space:nowrap;overflow:visible;}'
    
  row +1 '.cell,.tick{flex:0 0 14px;width:14px;height:14px;display:inline-flex;align-items:center;justify-content:center;text-align:center;font-size:10px;}'
  row +1 '.tick{color:#555;border:1px solid transparent;border-radius:3px;position:relative}'
  row +1 '.ticks .strip{padding-top:20px}'
  row +1 '.ticks .tick{overflow:visible;text-overflow:initial}'
  row +1 '.tick .mo{position:absolute;top:-14px;left:50%;transform:translateX(-50%);font-size:10px;color:#555;white-space:nowrap;pointer-events:none}'
  row +1 '.cell{border:1px solid #ccc;border-radius:3px;background:#fff}'
  row +1 '.cell.on{background:#0086CE;border-color:#0D66A1;color:#fff;font-weight:600}'
  row +1 '.cell.on:empty::before{content:"1"}'
    
  row +1 '.cell.sum-yes{background:#ED1C24;border-color:#cc0000;}'
  row +1 '.cell.sum-no{background:#A8D08D;border-color:#88b070;}'
  row +1 '.summary-row td{border-top:1px solid #ccc;padding-top:4px;}'
    
  row +1 '.ticks th{border-bottom:0;background:#fff}'
  row +1 '.pill{display:inline-block;padding:2px 6px;border-radius:12px;background:#eef;color:#334;}'
  row +1 '</style></head><body><div class="wrap">'

  /* --- CHART SECTION --- */
  row +1 '<h1>Antimicrobial Administrations by Date</h1>'
  row +1 '<div class="legend">Each blue square marks a <b>day</b> where the medication has been administered. A number indicates the count of administrations for that day.<br><b>Summary:</b> Red = Antimicrobial given, Green = No antimicrobial given.</div>'
  row +1 call print(v_axis_html)
    
  row +1 '<div class="chart-wrap">'
  row +1 '<table width="100%" class="chart-tbl"><colgroup><col width="180" class="med"><col width="46" class="doses"><col width="46" class="dot"><col></colgroup><thead>'
  row +1 '<tr><th width="180" class="label sticky-med"><div style="width:180px; text-align:left;">Medication</div></th><th width="46" class="label sticky-doses"><div style="width:46px; text-align:center;">Doses</div></th><th width="46" class="label sticky-dot"><div style="width:46px; text-align:center;">DOT</div></th><th class="label">Days</th></tr>'
  if (textlen(v_header_html) > 0)
    row +1 '<tr class="ticks"><th class="sticky-med"></th><th class="sticky-doses"></th><th class="sticky-dot"></th><th><div class="strip">'
    row +1 call print(v_header_html)
    row +1 '</div></th></tr>'
  endif
  row +1 '</thead><tbody>'

  v_pos = findstring(v_token, v_chart_rows)
  while (v_pos > 0)
    v_seglen = v_pos + v_toklen - 1
    v_rowseg = substring(1, v_seglen, v_chart_rows)
    row +1 call print(v_rowseg)
    v_len = textlen(v_chart_rows)
    v_chart_rows = substring(v_pos + v_toklen, v_len - (v_pos + v_toklen - 1), v_chart_rows)
    v_pos = findstring(v_token, v_chart_rows)
  endwhile
  if (textlen(v_chart_rows) > 0)
    row +1 call print(v_chart_rows)
  endif
  row +1 '</tbody></table></div>'

  /* --- TABLE SECTION --- */
  row +1 '<h2>Antimicrobial Order Details</h2>'
  row +1 '<table width="100%" class="data-tbl">'
  row +1 '<colgroup><col width="180" class="med"><col width="46" class="doses"><col width="46" class="dot"><col style="width:12%;"><col style="width:12%;"></colgroup>'
  row +1 '<thead><tr>'
  row +1 '<th>Medication</th><th style="text-align:center;">Doses</th><th style="text-align:center;">DOT</th><th>Target Dose</th><th>Dose</th><th>Indication</th>'
  row +1 '<th>Start Date</th><th>Latest Status</th><th>Status Date</th><th>Order ID</th>'
  row +1 '</tr></thead>'
  row +1 '<tbody>'

  v_pos = findstring(v_token, v_table_rows)
  while (v_pos > 0)
    v_seglen = v_pos + v_toklen - 1
    v_rowseg = substring(1, v_seglen, v_table_rows)
    row +1 call print(v_rowseg)
    v_len = textlen(v_table_rows)
    v_table_rows = substring(v_pos + v_toklen, v_len - (v_pos + v_toklen - 1), v_table_rows)
    v_pos = findstring(v_token, v_table_rows)
  endwhile
  if (textlen(v_table_rows) > 0)
    row +1 call print(v_table_rows)
  endif

  row +1 '</tbody></table>'
  row +1 '<div class="legend" style="margin-top:8px;">Days of therapy (DOT) for antimicrobial orders which have been administered are included in this report.</div>'

  /* --- DEBUG PANEL --- */
  row +1 '<div style="margin-top:24px;padding:10px 14px;border:1px solid #f0a000;background:#fffbe6;color:#333;font-size:11px;font-family:monospace;">'
  row +1 '<b style="font-size:12px;">&#9888; DEBUG INFO (remove before go-live)</b><br/>'
  row +1 call print(concat('Patient ID: ', cnvtstring($PAT_PersonId), ' &nbsp;|&nbsp; Lookback: ', cnvtstring($LOOKBACK), ' days<br/>'))
  row +1 call print(concat('MRN: ', v_mrn, '<br/>'))
  row +1 call print(concat('Admission: ', v_admit_dt, ' &nbsp;|&nbsp; LOS: ', v_los, ' days<br/>'))
  row +1 call print(concat('Query window: ', v_begin_dt_str, ' to ', v_end_dt_str, '<br/>'))
  row +1 call print(concat('Total admin_rec entries: ', cnvtstring(admin_rec->cnt), ' (PowerChart: ', cnvtstring(v_pc_cnt), ', SN Anesthesia: ', cnvtstring(v_sn_cnt), ')<br/>'))
  row +1 call print(concat('Chart date range: ', format(v_min_dt,"DD-MMM-YYYY;;D"), ' to ', format(v_max_dt,"DD-MMM-YYYY;;D"), ' (', cnvtstring(v_days), ' days)<br/>'))
  row +1 call print(concat('v_chart_rows length: ', cnvtstring(textlen(v_chart_rows)), ' chars (limit 65534)<br/>'))
  row +1 call print(concat('v_table_rows length: ', cnvtstring(textlen(v_table_rows)), ' chars (limit 65534)<br/>'))
  row +1 '</div>'

  /* --- FOOTER --- */
  row +1 '<div style="margin-top:24px;padding-top:8px;border-top:1px solid #ddd;color:#666;font-size:12px;">Generated on '
  row +1 call print(format(cnvtdatetime(curdate, curtime), "YYYY-MM-DD HH:MM:SS;;D"))
  row +1 '.</div></div></body></html>'
with NOFORMAT, maxcol = 35000, time = 60

end
go