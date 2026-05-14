drop program 01_meds_dot_date_comb_edge4:Group1 go
create program 01_meds_dot_date_comb_edge4:Group1

/*****************************************************************************
  Antimicrobial Days of Therapy - Combined Chart and Table View (EDGE 5)
  
  - EDGE 5 FIX: Bypassed 64k character limit using Record Structure Arrays.
  - EDGE 5 FIX: Resolved 'call alterlist()' syntax crashes in select blocks.
  - EDGE 5 FIX: Resolved comma-separation 'uninitialized' variable bugs.
  - Retains full Interactive Focus Mode, Data Table, Tooltips, and APPLINKs.
******************************************************************************/

prompt
  "Output to File/Printer/MINE" = "MINE"
  , "Patient_ID" = 0
  , "Days Lookback" = 180
with OUTDEV, PAT_PersonId, LOOKBACK

/* ========================================================================== */
/* Variable Declarations                                                      */
/* ========================================================================== */
declare v_font_size      = vc with noconstant("13px")
declare v_med_font_size = vc with noconstant("14px")
declare v_mrn          = vc with noconstant("")
declare v_name        = vc with noconstant("")
declare v_admit_dt    = vc with noconstant("")
declare v_los         = vc with noconstant("")
declare v_lookback    = vc with noconstant("")
declare v_axis_html   = vc with noconstant(""), maxlen=2000
declare v_header_html = vc with noconstant(""), maxlen=65534
declare v_month_html  = vc with noconstant(""), maxlen=65534
declare v_mo_span     = i4 with noconstant(0)
declare v_mo_name     = vc with noconstant("")
declare v_mo_start    = i4 with noconstant(0)
declare v_min_dt      = dq8 with noconstant(0)
declare v_max_dt      = dq8 with noconstant(0)
declare v_first       = i2 with noconstant(1)
declare v_days          = i4 with noconstant(0)
declare v_curr_med    = vc with noconstant("")
declare v_dates_kv    = vc with noconstant(""), maxlen=65534
declare v_details_kv  = vc with noconstant(""), maxlen=65534
declare v_cnt_day     = i4 with noconstant(0)
declare v_i           = i4 with noconstant(0)
declare v_key8        = vc with noconstant("")
declare v_count_str   = vc with noconstant("")
declare v_count_i     = i4 with noconstant(0)
declare v_title       = vc with noconstant(""), maxlen=1000
declare v_strip        = vc with noconstant(""), maxlen=65534
declare v_med_dot_total   = i4 with noconstant(0)
declare v_med_dose_total  = i4 with noconstant(0)
declare v_row_cnt     = i4 with noconstant(0)
declare v_med_attr    = vc with noconstant("")
declare v_all_days_list = vc with noconstant(""), maxlen=65534
declare v_table_dot_days_list = vc with noconstant(""), maxlen=65534
declare v_grand_total_dot   = i4 with noconstant(0)
declare v_cell_bg         = vc with noconstant("")
declare v_indication       = vc with noconstant(""), maxlen=255
declare v_discontinue_rsn  = vc with noconstant(""), maxlen=255
declare v_route            = vc with noconstant(""), maxlen=255
declare v_route_upper      = vc with noconstant(""), maxlen=255
declare v_route_code       = vc with noconstant(""), maxlen=8
declare v_route_class      = vc with noconstant(""), maxlen=16
declare v_low_dt      = dq8 with noconstant(null)
declare v_high_now_dt = dq8 with noconstant(null)
declare v_today        = dq8 with noconstant(0)
declare v_vitals_end_dt = dq8 with noconstant(0)

declare v_findpos          = i4 with noconstant(0)
declare v_after            = vc with noconstant(""), maxlen=65534
declare v_endpos           = i4 with noconstant(0)
declare v_detail_str       = vc with noconstant("")
declare v_pipe_pos         = i4 with noconstant(0)

declare v_drug        = vc with noconstant("")
declare v_dose        = f8 with noconstant(0.0)
declare v_unit        = vc with noconstant("")
declare v_ind         = vc with noconstant("")
declare v_start       = vc with noconstant("")
declare v_stat        = vc with noconstant("")
declare v_sdt         = vc with noconstant("")
declare v_oid         = vc with noconstant("")
declare v_dot         = i4 with noconstant(0)
declare v_doses       = i4 with noconstant(0)
declare v_dose_str        = vc with noconstant("")
declare v_actual_dose_str = vc with noconstant("")
declare v_s               = vc with noconstant("")
declare v_v               = vc with noconstant("")
declare v_order_src       = vc with noconstant("")
declare v_disp            = vc with noconstant("")
declare v_fin             = vc with noconstant("")
declare v_encntr_id       = vc with noconstant("")

declare v_pc_cnt      = i4 with noconstant(0)
declare v_sn_cnt      = i4 with noconstant(0)

declare v_e             = i4 with noconstant(0)
declare v_s_idx         = i4 with noconstant(0)
declare v_e_idx         = i4 with noconstant(0)
declare v_t             = i4 with noconstant(0)
declare v_max_track     = i4 with noconstant(0)
declare v_assigned      = i2 with noconstant(0)
declare v_cell_class    = vc with noconstant(""), maxlen=100
declare v_cell_title    = vc with noconstant(""), maxlen=255
declare v_cell_text     = vc with noconstant(""), maxlen=10
declare v_enc_label     = vc with noconstant(""), maxlen=2000
declare v_color_idx     = i4 with noconstant(0)
declare track_ends[50]  = i4
declare stat            = i4 with noconstant(0)

declare v_min_date     = i4 with noconstant(0)
declare v_debug_admins = vc with noconstant(""), maxlen=65534
declare v_debug_meds   = vc with noconstant(""), maxlen=65534
declare v_debug_display = vc with noconstant(""), maxlen=65534
declare v_debug_cells   = vc with noconstant(""), maxlen=65534
declare v_debug_table   = vc with noconstant(""), maxlen=65534
declare v_begin_dt_str = vc with noconstant("")
declare v_end_dt_str   = vc with noconstant("")
declare v_sum_strip    = vc with noconstant(""), maxlen=65534
declare v_spacer_strip = vc with noconstant(""), maxlen=65534
declare v_day_idx      = i4 with noconstant(0)
declare v_plot_w       = i4 with noconstant(0)
declare v_plot_h       = i4 with noconstant(44)
declare v_plot_y0      = i4 with noconstant(7)
declare v_x            = i4 with noconstant(0)
declare v_y            = i4 with noconstant(0)
declare v_y2           = i4 with noconstant(0)
declare v_vital_val    = f8 with noconstant(0.0)
declare v_vital_title  = vc with noconstant(""), maxlen=500
declare v_temp_points  = vc with noconstant(""), maxlen=65534
declare v_temp_marks   = vc with noconstant(""), maxlen=65534
declare v_hr_points    = vc with noconstant(""), maxlen=65534
declare v_hr_marks     = vc with noconstant(""), maxlen=65534
declare v_sys_points   = vc with noconstant(""), maxlen=65534
declare v_dia_points   = vc with noconstant(""), maxlen=65534
declare v_bp_poly      = vc with noconstant(""), maxlen=65534
declare v_sys_marks    = vc with noconstant(""), maxlen=65534
declare v_dia_marks    = vc with noconstant(""), maxlen=65534
declare v_spo2_points  = vc with noconstant(""), maxlen=65534
declare v_spo2_marks   = vc with noconstant(""), maxlen=65534
declare v_vitals_html  = vc with noconstant(""), maxlen=65534
declare v_vitals_count = i4 with noconstant(0)
declare v_temp_count   = i4 with noconstant(0)
declare v_hr_count     = i4 with noconstant(0)
declare v_bp_count     = i4 with noconstant(0)
declare v_spo2_count   = i4 with noconstant(0)

/* ========================================================================== */
/* HTML OUTPUT BUFFERS (Bypasses 64k limit)                                   */
/* ========================================================================== */
free record html_chart
record html_chart (
  1 cnt = i4
  1 qual[*]
    2 text = vc
)

free record html_table
record html_table (
  1 cnt = i4
  1 qual[*]
    2 text = vc
)

/* Records for Data */
free record admin_rec
record admin_rec (1 cnt=i4 1 qual[*] 2 admin_dt_tm=dq8 2 order_id=f8 2 admin_id=f8 2 src=vc)

free record enc_rec
record enc_rec (1 cnt=i4 1 qual[*] 2 encntr_id=f8 2 fin=vc 2 arrive_dt=dq8 2 disch_dt=dq8 2 start_idx=i4 2 end_idx=i4 2 track=i4)

free record enc_sort_rec
record enc_sort_rec (1 cnt=i4 1 qual[*] 2 orig_idx=i4 2 start_idx=i4 2 end_idx=i4)

free record vital_day_rec
record vital_day_rec (
  1 cnt = i4
  1 qual[*]
    2 temp_val = f8
    2 temp_dt = dq8
    2 temp_name = vc
    2 temp_units = vc
    2 hr_val = f8
    2 hr_dt = dq8
    2 hr_name = vc
    2 hr_units = vc
    2 sys_val = f8
    2 sys_dt = dq8
    2 sys_name = vc
    2 sys_units = vc
    2 dia_val = f8
    2 dia_dt = dq8
    2 dia_name = vc
    2 dia_units = vc
    2 spo2_val = f8
    2 spo2_dt = dq8
    2 spo2_name = vc
    2 spo2_units = vc
)


/* ========================================================================== */
/* PASS 0A & 0B: DATA GATHERING                                               */
/* ========================================================================== */
select into "nl:"
from clinical_event ce, med_admin_event m, orders o, code_value_event_r cr, order_catalog oc, order_catalog_synonym ocs, order_entry_format oe
plan ce where ce.person_id = $PAT_PersonId
  and ce.performed_dt_tm between cnvtdatetime(curdate-$LOOKBACK,0) and cnvtdatetime(curdate,curtime)
  and ce.result_status_cd = 25.00
join m where m.event_id = ce.event_id and m.event_type_cd = 8912520.00
join o where o.order_id = m.template_order_id
join cr where cr.event_cd = ce.event_cd
join oc where oc.catalog_cd = cr.parent_cd and oc.catalog_type_cd = 2516
join ocs where ocs.catalog_cd = oc.catalog_cd
join oe where oe.oe_format_id = ocs.oe_format_id and oe.oe_format_id in (14497910, 14498121)
order by m.event_id
head report admin_rec->cnt = 0
head m.event_id
  admin_rec->cnt = admin_rec->cnt + 1
  stat = alterlist(admin_rec->qual, admin_rec->cnt)
  admin_rec->qual[admin_rec->cnt].admin_dt_tm = ce.event_end_dt_tm
  admin_rec->qual[admin_rec->cnt].order_id = o.order_id
  admin_rec->qual[admin_rec->cnt].admin_id = ce.event_id
  admin_rec->qual[admin_rec->cnt].src = "PC"
with nocounter

select into "nl:"
from orders o, sa_medication_admin sma, sa_med_admin_item smai, order_catalog_synonym ocs, order_entry_format oe
plan o where o.person_id = $PAT_PersonId
join sma where sma.order_id = o.order_id and sma.active_ind = 1
join smai where smai.sa_medication_admin_id = sma.sa_medication_admin_id and smai.active_ind = 1
  and smai.admin_start_dt_tm >= cnvtdatetimeutc(cnvtdatetime(curdate-$LOOKBACK,0))
  and smai.admin_start_dt_tm <= cnvtdatetimeutc(cnvtdatetime(curdate,curtime))
join ocs where ocs.synonym_id = o.synonym_id
join oe where oe.oe_format_id = ocs.oe_format_id and oe.oe_format_id in (14497910, 14498121)
order by smai.sa_med_admin_item_id
head smai.sa_med_admin_item_id
  admin_rec->cnt = admin_rec->cnt + 1
  stat = alterlist(admin_rec->qual, admin_rec->cnt)
  admin_rec->qual[admin_rec->cnt].admin_dt_tm = cnvtdatetimeutc(smai.admin_start_dt_tm)
  admin_rec->qual[admin_rec->cnt].order_id = o.order_id
  admin_rec->qual[admin_rec->cnt].admin_id = smai.sa_med_admin_item_id
  admin_rec->qual[admin_rec->cnt].src = "SN"
with nocounter


/* Build admin timestamp sample for debug */
set v_debug_admins = ""
set v_i = 1
while (v_i <= admin_rec->cnt and v_i <= 8)
  set v_debug_admins = concat(v_debug_admins,
    trim(cnvtstring(v_i),3), ": ",
    format(admin_rec->qual[v_i].admin_dt_tm,"DD-MMM-YYYY HH:MM;;D"),
    " | key=", format(admin_rec->qual[v_i].admin_dt_tm,"YYYYMMDD;;D"),
    " | raw=", cnvtstring(admin_rec->qual[v_i].admin_dt_tm),
    " (", admin_rec->qual[v_i].src, ")<br/>")
  set v_i = v_i + 1
endwhile
if (admin_rec->cnt > 8)
  set v_debug_admins = concat(v_debug_admins, "...last: ",
    format(admin_rec->qual[admin_rec->cnt].admin_dt_tm,"DD-MMM-YYYY HH:MM;;D"),
    " | key=", format(admin_rec->qual[admin_rec->cnt].admin_dt_tm,"YYYYMMDD;;D"),
    " | raw=", cnvtstring(admin_rec->qual[admin_rec->cnt].admin_dt_tm),
    " (", admin_rec->qual[admin_rec->cnt].src, ")<br/>")
endif

/* ========================================================================== */
/* PASS 1: DATE DIMENSIONS                                                    */
/* ========================================================================== */
select into "nl:"
from person p, person_alias pa, encounter e
plan p where p.person_id = $PAT_PersonId
join pa where pa.person_id = p.person_id and pa.person_alias_type_cd = 10.00
join e where e.person_id = p.person_id
head report
  v_first = 1
  v_mrn = pa.alias
  v_name = p.name_full_formatted
  v_admit_dt = format(e.arrive_dt_tm,"DD/MM/YYYY;;d")
  v_low_dt = cnvtdatetime(cnvtdate(e.arrive_dt_tm),0)
  v_high_now_dt = cnvtdatetime(curdate,0)
  v_today = cnvtdatetime(curdate, 0)
  v_los = cnvtstring((datetimediff(v_high_now_dt,v_low_dt,7))+1)
  v_lookback = cnvtstring($LOOKBACK)
  v_begin_dt_str = format((curdate-$LOOKBACK),"DD/MM/YYYY;;d")
  v_end_dt_str = format(curdate,"DD/MM/YYYY;;d")
with nocounter

if (admin_rec->cnt > 0)
  set v_first = 0
  set v_min_dt = cnvtdatetime(concat(format(admin_rec->qual[1].admin_dt_tm, "DD-MMM-YYYY;;D"), " 00:00:00"))
  set v_max_dt = v_min_dt
  set v_i = 2
  while (v_i <= admin_rec->cnt)
    if (format(admin_rec->qual[v_i].admin_dt_tm, "YYYYMMDD;;D") < format(v_min_dt, "YYYYMMDD;;D"))
      set v_min_dt = cnvtdatetime(concat(format(admin_rec->qual[v_i].admin_dt_tm, "DD-MMM-YYYY;;D"), " 00:00:00"))
    endif
    if (format(admin_rec->qual[v_i].admin_dt_tm, "YYYYMMDD;;D") > format(v_max_dt, "YYYYMMDD;;D"))
      set v_max_dt = cnvtdatetime(concat(format(admin_rec->qual[v_i].admin_dt_tm, "DD-MMM-YYYY;;D"), " 00:00:00"))
    endif
    set v_i = v_i + 1
  endwhile
  if (v_max_dt < v_today) set v_max_dt = v_today endif

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

if (v_first = 1)
  set v_days = 0
  set v_axis_html = ""
  set v_header_html = ""
  set html_chart->cnt = 1
  set stat = alterlist(html_chart->qual, 1)
  set html_chart->qual[1].text = '<div class="grid-cell" style="grid-column: 1 / -1; padding: 10px;">No administrations found.</div>'
else
  set v_days = cnvtint(datetimediff(v_max_dt, v_min_dt, 1)) + 1
  set v_min_date = curdate - (v_days - 1)
  set v_axis_html = concat(' <span style="font-weight:normal; font-size:11px; color:#555;">(Date range: ', format(v_min_dt,"DD-MMM-YYYY;;D"), ' to ', format(v_max_dt,"DD-MMM-YYYY;;D"), ')</span>')
  set v_header_html = ''
  set v_month_html  = ''
  set v_mo_span  = 0
  set v_mo_name  = ''
  set v_mo_start = 0
  set v_i = 0
  /* Pass A: day-number row */
  while (v_i < v_days)
    if ((v_min_date + v_i) = curdate)
      set v_cell_class = " today-col"
    else
      set v_cell_class = ""
    endif
    set v_header_html = concat(v_header_html, '<div class="grid-cell tick', v_cell_class, '" title="', format(v_min_date + v_i,"YYYY-MM-DD;;D"), '">', format(v_min_date + v_i,"DD;;D"), '</div>')
    set v_i = v_i + 1
  endwhile
  /* Pass B: month-span row - walk days, emit span div when month changes or at end */
  set v_i = 0
  while (v_i < v_days)
    if (v_i = 0)
      set v_mo_name  = format(v_min_date + v_i, "MMM;;D")
      set v_mo_start = 0
      set v_mo_span  = 1
    elseif (format(v_min_date + v_i,"MM;;D") != format(v_min_date + v_i - 1,"MM;;D"))
      set v_month_html = concat(v_month_html, '<div class="grid-cell mo-span always-on" style="grid-column:span ', trim(cnvtstring(v_mo_span),3), ';">', v_mo_name, '</div>')
      set v_mo_name  = format(v_min_date + v_i, "MMM;;D")
      set v_mo_start = v_i
      set v_mo_span  = 1
    else
      set v_mo_span  = v_mo_span + 1
    endif
    set v_i = v_i + 1
  endwhile
  /* flush last month */
  set v_month_html = concat(v_month_html, '<div class="grid-cell mo-span always-on" style="grid-column:span ', trim(cnvtstring(v_mo_span),3), ';">', v_mo_name, '</div>')
endif


/* ========================================================================== */
/* PASS 2: BUILD CHART ROWS (Appended to Array)                               */
/* ========================================================================== */
set html_chart->cnt = 0
if (admin_rec->cnt > 0)
select into "nl:"
  med_name = trim(oc.primary_mnemonic)
, mdy = format(admin_rec->qual[d.seq].admin_dt_tm, "YYYYMMDD;;D")
, indication = substring(1,60,trim(od_indication.oe_field_display_value))
, discontinue_reason = substring(1,60,trim(od_dcreason.oe_field_display_value))
, route = substring(1,60,trim(od_route.oe_field_display_value))
, src_id = admin_rec->qual[d.seq].admin_id
, admin_src = admin_rec->qual[d.seq].src
from (dummyt d with seq = admin_rec->cnt), orders o, order_catalog oc, order_detail od_indication, order_detail od_dcreason, order_detail od_route
plan d join o where o.order_id = admin_rec->qual[d.seq].order_id
join oc where oc.catalog_cd = o.catalog_cd
join od_indication where od_indication.order_id = outerjoin(o.order_id) and od_indication.oe_field_meaning = outerjoin("INDICATION")
join od_dcreason where od_dcreason.order_id = outerjoin(o.order_id) and od_dcreason.oe_field_meaning = outerjoin("DCREASON")
join od_route where od_route.order_id = outerjoin(o.order_id) and od_route.oe_field_meaning_id = outerjoin(2050)
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
  v_details_kv = concat(v_details_kv, "~", mdy, ":", indication, "|", discontinue_reason, "|", route, "~")
  v_med_dot_total = v_med_dot_total + 1
  if (findstring(concat("~", mdy, "~"), v_all_days_list) = 0)
    v_all_days_list = concat(v_all_days_list, "~", mdy, "~")
  endif

foot med_name
  if (v_days > 0)
    v_row_cnt = v_row_cnt + 1
    v_grand_total_dot = v_grand_total_dot + v_med_dot_total
    v_strip = ""
    v_debug_cells = ""
    v_i = 0
    v_cell_bg = if(mod(v_row_cnt, 2) = 0) ' even-cell' else '' endif
    v_med_attr = concat(' data-med="', v_curr_med, '"')

    while (v_i < v_days)
      v_key8 = format(v_min_date + v_i, "YYYYMMDD;;D")
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
      v_route = ""
      v_findpos = findstring(concat("~", v_key8, ":"), v_details_kv)
      if (v_findpos > 0)
        v_after = substring(v_findpos + 10, textlen(v_details_kv) - (v_findpos + 9), v_details_kv)
        v_endpos = findstring("~", v_after)
        v_detail_str = ""
        if (v_endpos > 0) v_detail_str = substring(1, v_endpos - 1, v_after)
        else v_detail_str = v_after
        endif
        v_pipe_pos = findstring("|", v_detail_str)
        if (v_pipe_pos > 0)
          v_indication = substring(1, v_pipe_pos - 1, v_detail_str)
          v_after = substring(v_pipe_pos + 1, textlen(v_detail_str) - v_pipe_pos, v_detail_str)
          v_pipe_pos = findstring("|", v_after)
          if (v_pipe_pos > 0)
            v_discontinue_rsn = substring(1, v_pipe_pos - 1, v_after)
            v_route = substring(v_pipe_pos + 1, textlen(v_after) - v_pipe_pos, v_after)
          else
            v_discontinue_rsn = v_after
          endif
        else
          v_indication = v_detail_str
        endif
      endif

      if (v_count_i > 0)
        if (trim(v_route, 3) = "")
          v_route = "--"
        endif
        v_route_upper = cnvtupper(trim(v_route, 3))
        if (v_route_upper = "--")
          v_route_code = "--"
          v_route_class = " route-unk"
        elseif (findstring("INTRAVENOUS", v_route_upper) > 0 or v_route_upper = "IV")
          v_route_code = "IV"
          v_route_class = " route-iv"
        elseif (findstring("ORAL", v_route_upper) > 0 or v_route_upper = "PO" or findstring("BY MOUTH", v_route_upper) > 0)
          v_route_code = "PO"
          v_route_class = " route-po"
        elseif (findstring("INTRAMUSCULAR", v_route_upper) > 0 or v_route_upper = "IM")
          v_route_code = "IM"
          v_route_class = " route-im"
        elseif (findstring("SUBCUT", v_route_upper) > 0 or v_route_upper = "SC" or v_route_upper = "SQ")
          v_route_code = "SC"
          v_route_class = " route-sc"
        elseif (findstring("ENTERAL", v_route_upper) > 0 or findstring("NASOGASTRIC", v_route_upper) > 0 or findstring("NG", v_route_upper) > 0)
          v_route_code = "EN"
          v_route_class = " route-en"
        elseif (findstring("RECTAL", v_route_upper) > 0 or v_route_upper = "PR")
          v_route_code = "PR"
          v_route_class = " route-pr"
        elseif (findstring("INHAL", v_route_upper) > 0 or findstring("NEB", v_route_upper) > 0)
          v_route_code = "IN"
          v_route_class = " route-in"
        elseif (findstring("TOPICAL", v_route_upper) > 0)
          v_route_code = "TP"
          v_route_class = " route-tp"
        elseif (findstring("BUCCAL", v_route_upper) > 0)
          v_route_code = "BU"
          v_route_class = " route-bu"
        else
          v_route_code = "OT"
          v_route_class = " route-ot"
        endif
        v_title = concat(v_curr_med, " - ", format(v_min_date + v_i,"DD/MM/YYYY;;D"), " / ", v_count_str, if(v_count_i = 1) " admin" else " admins" endif, "&#10;Indication: ", v_indication, "&#10;Discontinue Reason: ", v_discontinue_rsn, "&#10;Route: ", v_route)
        if ((v_min_date + v_i) = curdate)
          v_cell_class = " today-col"
        else
          v_cell_class = ""
        endif
        v_strip = concat(v_strip, '<div class="grid-cell cell on dimmable', v_cell_bg, v_route_class, v_cell_class, '"', v_med_attr, ' data-day-idx="', trim(cnvtstring(v_i), 3), '" title="', v_title, '"><span class="dose-count">', trim(v_count_str), '</span><span class="route-code">', v_route_code, '</span></div>')
        v_debug_cells = concat(v_debug_cells, if ((v_min_date + v_i) = curdate) "*" else "" endif, trim(v_count_str), " ")
      else
        if ((v_min_date + v_i) = curdate)
          v_cell_class = " today-col"
        else
          v_cell_class = ""
        endif
        v_strip = concat(v_strip, '<div class="grid-cell cell dimmable', v_cell_bg, v_cell_class, '"', v_med_attr, ' data-day-idx="', trim(cnvtstring(v_i), 3), '" title="', format(v_min_date + v_i,"DD/MM/YYYY;;D"), '"></div>')
        v_debug_cells = concat(v_debug_cells, if ((v_min_date + v_i) = curdate) "*" else "" endif, ". ")
      endif
      v_i = v_i + 1
    endwhile

    /* APPEND TO RECORD ARRAY */
    html_chart->cnt = html_chart->cnt + 1
    stat = alterlist(html_chart->qual, html_chart->cnt)
    html_chart->qual[html_chart->cnt].text = concat(
      '<div class="grid-cell label medname sticky-med med-trigger dimmable', v_cell_bg, '"', v_med_attr, ' title="Click to filter by ', v_curr_med, '">', v_curr_med, '</div>',
      '<div class="grid-cell dot-val sticky-doses dimmable', v_cell_bg, '"', v_med_attr, '><span class="pill" title="', v_curr_med, ' - Total Doses: ', trim(cnvtstring(v_med_dose_total), 3), '">', trim(cnvtstring(v_med_dose_total), 3), '</span></div>',
      '<div class="grid-cell dot-val sticky-dot dimmable', v_cell_bg, '"', v_med_attr, '><span class="pill" title="', v_curr_med, ' - Total Days of Therapy: ', trim(cnvtstring(v_med_dot_total), 3), '">', trim(cnvtstring(v_med_dot_total), 3), '</span></div>',
      v_strip
    )
    v_debug_meds = concat(v_debug_meds, v_curr_med,
      ": doses=", trim(cnvtstring(v_med_dose_total),3),
      " DOT=", trim(cnvtstring(v_med_dot_total),3), "<br/>")
    v_debug_display = concat(v_debug_display, v_curr_med,
      " | Doses=", trim(cnvtstring(v_med_dose_total),3),
      " DOT=", trim(cnvtstring(v_med_dot_total),3),
      " | ", v_debug_cells, "<br/>")
  endif

foot report
  if (v_days > 0)
      v_sum_strip = ""
      v_spacer_strip = ""
      v_debug_cells = ""
      v_i = 0
      while (v_i < v_days)
          v_key8 = format(v_min_date + v_i, "YYYYMMDD;;D")
          if ((v_min_date + v_i) = curdate)
            v_cell_class = " today-col"
          else
            v_cell_class = ""
          endif
          if (findstring(concat("~", v_key8, "~"), v_all_days_list) > 0)
             v_sum_strip = concat(v_sum_strip, '<div class="grid-cell cell sum-yes sum-border', v_cell_class, '" title="Antimicrobial Administered"></div>')
             v_debug_cells = concat(v_debug_cells, if ((v_min_date + v_i) = curdate) "*" else "" endif, "Y ")
          else
             v_sum_strip = concat(v_sum_strip, '<div class="grid-cell cell sum-no sum-border', v_cell_class, '" title="No Antimicrobials"></div>')
             v_debug_cells = concat(v_debug_cells, if ((v_min_date + v_i) = curdate) "*" else "" endif, ". ")
          endif
          v_i = v_i + 1
      endwhile
      v_debug_display = concat(v_debug_display,
        "Antimicrobial Summary | Grand DOT=", trim(cnvtstring(v_grand_total_dot),3),
        " | ", v_debug_cells, "<br/>")

      /* APPEND SUMMARY TO RECORD ARRAY */
      html_chart->cnt = html_chart->cnt + 1
      stat = alterlist(html_chart->qual, html_chart->cnt)
      html_chart->qual[html_chart->cnt].text = concat(
          '<div class="grid-cell label sticky-med sum-border always-on has-help" data-help="Summary: Red = Antimicrobial given, Green = No antimicrobial given." title="Summary: Red = Antimicrobial given, Green = No antimicrobial given.">Antimicrobial Summary</div>',
          '<div class="grid-cell label sticky-doses sum-border always-on"></div>',
          '<div class="grid-cell label dot-val sticky-dot sum-border always-on"><span class="pill" title="Total Summary Days of Therapy: ', trim(cnvtstring(v_grand_total_dot), 3), '">', trim(cnvtstring(v_grand_total_dot), 3), '</span></div>',
          v_sum_strip
      )
  endif
with nocounter
endif

/* ========================================================================== */
/* PASS 2.5: ENCOUNTER TRACKS (Appended to Array)                            */
/* ========================================================================== */
if (admin_rec->cnt > 0 and v_days > 0)
  select into "nl:"
    o.encntr_id
  from (dummyt d with seq = admin_rec->cnt), orders o, encounter e, encntr_alias ea
  plan d join o where o.order_id = admin_rec->qual[d.seq].order_id
  join e where e.encntr_id = o.encntr_id
  join ea where ea.encntr_id = outerjoin(o.encntr_id) and ea.encntr_alias_type_cd = outerjoin(1077.00) and ea.active_ind = outerjoin(1)
  order by o.encntr_id
  head report
    enc_rec->cnt = 0
  head o.encntr_id
    enc_rec->cnt = enc_rec->cnt + 1
    stat = alterlist(enc_rec->qual, enc_rec->cnt)
    enc_rec->qual[enc_rec->cnt].encntr_id = o.encntr_id
    enc_rec->qual[enc_rec->cnt].fin       = trim(ea.alias)
    enc_rec->qual[enc_rec->cnt].arrive_dt = e.arrive_dt_tm
    enc_rec->qual[enc_rec->cnt].disch_dt  = e.disch_dt_tm
  with nocounter

  if (enc_rec->cnt > 0)
    for (v_e = 1 to enc_rec->cnt)
      if (enc_rec->qual[v_e].arrive_dt = null or enc_rec->qual[v_e].arrive_dt = 0)
        set v_s_idx = 0
      else
        set v_s_idx = datetimediff(enc_rec->qual[v_e].arrive_dt, v_min_dt, 7)
        if (v_s_idx < 0) set v_s_idx = 0 endif
        if (v_s_idx >= v_days) set v_s_idx = v_days - 1 endif
      endif

      if (enc_rec->qual[v_e].disch_dt = null or enc_rec->qual[v_e].disch_dt = 0)
        set v_e_idx = v_days - 1
      else
        set v_e_idx = datetimediff(enc_rec->qual[v_e].disch_dt, v_min_dt, 7)
        if (v_e_idx < v_s_idx) set v_e_idx = v_s_idx endif
        if (v_e_idx >= v_days) set v_e_idx = v_days - 1 endif
      endif
      set enc_rec->qual[v_e].start_idx = v_s_idx
      set enc_rec->qual[v_e].end_idx   = v_e_idx
    endfor
  endif

  select into "nl:"
    s_idx = enc_rec->qual[d.seq].start_idx
  from (dummyt d with seq = enc_rec->cnt)
  order by s_idx, d.seq
  head report
    enc_sort_rec->cnt = 0
  detail
    enc_sort_rec->cnt = enc_sort_rec->cnt + 1
    stat = alterlist(enc_sort_rec->qual, enc_sort_rec->cnt)
    enc_sort_rec->qual[enc_sort_rec->cnt].orig_idx  = d.seq
    enc_sort_rec->qual[enc_sort_rec->cnt].start_idx = enc_rec->qual[d.seq].start_idx
    enc_sort_rec->qual[enc_sort_rec->cnt].end_idx   = enc_rec->qual[d.seq].end_idx
  with nocounter

  for (v_t = 1 to 50)
    set track_ends[v_t] = -1
  endfor
  if (enc_sort_rec->cnt > 0)
    for (v_e = 1 to enc_sort_rec->cnt)
      set v_s_idx    = enc_sort_rec->qual[v_e].start_idx
      set v_e_idx    = enc_sort_rec->qual[v_e].end_idx
      set v_assigned = 0
      set v_t        = 1
      while (v_t <= 50 and v_assigned = 0)
        if (track_ends[v_t] < v_s_idx)
          set enc_rec->qual[enc_sort_rec->qual[v_e].orig_idx].track = v_t
          set track_ends[v_t] = v_e_idx
          if (v_t > v_max_track) set v_max_track = v_t endif
          set v_assigned = 1
        endif
        set v_t = v_t + 1
      endwhile
    endfor
  endif

  if (v_max_track > 0)
    for (v_t = 1 to v_max_track)
      set v_enc_label = ""
      for (v_e = 1 to enc_rec->cnt)
        if (enc_rec->qual[v_e].track = v_t)
          if (v_enc_label != "") set v_enc_label = concat(v_enc_label, ", ") endif
          set v_enc_label = build2(v_enc_label,
            ~<a href="javascript:APPLINK(0,'Powerchart.exe','/PERSONID=~, trim(cnvtstring($PAT_PersonId, 20, 0), 3),
            ~ /ENCNTRID=~, trim(cnvtstring(enc_rec->qual[v_e].encntr_id, 20, 0), 3), ~')">~, trim(enc_rec->qual[v_e].fin), ~</a>~)
        endif
      endfor

      set v_strip = ""
      set v_i = 0
      while (v_i < v_days)
        set v_cell_class = "spacer-bit"
        set v_cell_title = ""
        set v_cell_text  = ""
        for (v_e = 1 to enc_rec->cnt)
          if (enc_rec->qual[v_e].track = v_t)
            if (v_i >= enc_rec->qual[v_e].start_idx and v_i <= enc_rec->qual[v_e].end_idx)
              set v_color_idx = mod(v_e, 4) + 1
              set v_cell_class = concat("enc-c", trim(cnvtstring(v_color_idx), 3))
              set v_cell_title = concat("FIN: ", trim(enc_rec->qual[v_e].fin))

              if (enc_rec->qual[v_e].arrive_dt != null and enc_rec->qual[v_e].arrive_dt != 0)
                 set v_cell_title = concat(v_cell_title, " | Arrive: ", format(enc_rec->qual[v_e].arrive_dt, "DD/MM/YYYY;;d"))
                 if (v_i = enc_rec->qual[v_e].start_idx) set v_cell_text = "&#9650;" endif
              else
                 set v_cell_title = concat(v_cell_title, " | Arrive: Unknown")
              endif

              if (enc_rec->qual[v_e].disch_dt = null or enc_rec->qual[v_e].disch_dt = 0)
                set v_cell_title = concat(v_cell_title, " | Active")
              else
                set v_cell_title = concat(v_cell_title, " | DC: ", format(enc_rec->qual[v_e].disch_dt, "DD/MM/YYYY;;d"))
                if (v_i = enc_rec->qual[v_e].end_idx)
                   if (v_cell_text = "&#9650;") set v_cell_text = "&#9670;" else set v_cell_text = "&#9660;" endif
                endif
              endif
            endif
          endif
        endfor
        if ((v_min_date + v_i) = curdate)
          set v_cell_class = concat(v_cell_class, " today-col")
        endif
        set v_strip = concat(v_strip, '<div class="grid-cell cell ', v_cell_class, '" title="', v_cell_title, '"><span class="enc-cell-text">', v_cell_text, '</span></div>')
        set v_i = v_i + 1
      endwhile

      /* APPEND ENCOUNTER TRACK TO RECORD ARRAY */
      set html_chart->cnt = html_chart->cnt + 1
      set stat = alterlist(html_chart->qual, html_chart->cnt)
      set html_chart->qual[html_chart->cnt].text = concat(
        '<div class="grid-cell label enc-label-cell sticky-med always-on has-help" data-help="Encounter: &#9650; Admit, &#9660; Discharge, &#9670; Same-day admit &amp; discharge." title="Encounter: &#9650; Admit, &#9660; Discharge, &#9670; Same-day admit &amp; discharge.">Encounter</div>',
        '<div class="grid-cell label sticky-doses always-on"></div>',
        '<div class="grid-cell label sticky-dot always-on"></div>',
        v_strip
      )
    endfor
  endif
endif

/* ========================================================================== */
/* PASS 2.75: CLINICAL MONITORING TRENDS                                      */
/* ========================================================================== */
set v_vitals_html = ""
set v_vitals_count = 0
set v_temp_count = 0
set v_hr_count = 0
set v_bp_count = 0
set v_spo2_count = 0

if (v_days > 0)
  set vital_day_rec->cnt = v_days
  set stat = alterlist(vital_day_rec->qual, v_days)
  set v_vitals_end_dt = cnvtdatetime(concat(format(v_max_dt, "DD-MMM-YYYY;;D"), " 23:59:59"))

  select into "nl:"
    vital_dt = ce.event_end_dt_tm
  , vital_cd = ce.event_cd
  , vital_val = cnvtreal(ce.result_val)
  , vital_name = substring(1, 80, uar_get_code_display(ce.event_cd))
  , vital_units = substring(1, 30, uar_get_code_display(ce.result_units_cd))
  from clinical_event ce, dummyt d1
  plan ce where ce.person_id = $PAT_PersonId
    and ce.event_end_dt_tm between v_min_dt and v_vitals_end_dt
    and ce.valid_until_dt_tm > cnvtdatetime(curdate, curtime)
    and ce.result_status_cd in (25.00, 34.00, 35.00)
    and ce.event_cd in (
      10933766.00, 10933787.00, 10933780.00, 14516112.00,
      10933752.00, 14506600.00,
      9096676.00, 9096691.00,
      9111827.00
    )
  join d1 where cnvtreal(ce.result_val) > 0.0
  order by ce.event_end_dt_tm, ce.event_id
  detail
    v_day_idx = datetimediff(vital_dt, v_min_dt, 7)
    if (v_day_idx >= 0 and v_day_idx < v_days)
      v_day_idx = v_day_idx + 1
      if (vital_cd = 10933766.00 or vital_cd = 10933787.00 or vital_cd = 10933780.00 or vital_cd = 14516112.00)
        vital_day_rec->qual[v_day_idx].temp_val = vital_val
        vital_day_rec->qual[v_day_idx].temp_dt = vital_dt
        vital_day_rec->qual[v_day_idx].temp_name = vital_name
        vital_day_rec->qual[v_day_idx].temp_units = vital_units
      elseif (vital_cd = 10933752.00 or vital_cd = 14506600.00)
        vital_day_rec->qual[v_day_idx].hr_val = vital_val
        vital_day_rec->qual[v_day_idx].hr_dt = vital_dt
        vital_day_rec->qual[v_day_idx].hr_name = vital_name
        vital_day_rec->qual[v_day_idx].hr_units = vital_units
      elseif (vital_cd = 9096676.00)
        vital_day_rec->qual[v_day_idx].sys_val = vital_val
        vital_day_rec->qual[v_day_idx].sys_dt = vital_dt
        vital_day_rec->qual[v_day_idx].sys_name = vital_name
        vital_day_rec->qual[v_day_idx].sys_units = vital_units
      elseif (vital_cd = 9096691.00)
        vital_day_rec->qual[v_day_idx].dia_val = vital_val
        vital_day_rec->qual[v_day_idx].dia_dt = vital_dt
        vital_day_rec->qual[v_day_idx].dia_name = vital_name
        vital_day_rec->qual[v_day_idx].dia_units = vital_units
      elseif (vital_cd = 9111827.00)
        vital_day_rec->qual[v_day_idx].spo2_val = vital_val
        vital_day_rec->qual[v_day_idx].spo2_dt = vital_dt
        vital_day_rec->qual[v_day_idx].spo2_name = vital_name
        vital_day_rec->qual[v_day_idx].spo2_units = vital_units
      endif
    endif
  with nocounter

  set v_plot_w = v_days * 14

  set v_temp_points = ""
  set v_temp_marks = ""
  set v_hr_points = ""
  set v_hr_marks = ""
  set v_sys_points = ""
  set v_dia_points = ""
  set v_bp_poly = ""
  set v_sys_marks = ""
  set v_dia_marks = ""
  set v_spo2_points = ""
  set v_spo2_marks = ""

  set v_i = 1
  while (v_i <= v_days)
    set v_x = ((v_i - 1) * 14) + 7

    if (vital_day_rec->qual[v_i].temp_val > 0)
      set v_vital_val = vital_day_rec->qual[v_i].temp_val
      if (v_vital_val < 34.0) set v_vital_val = 34.0 endif
      if (v_vital_val > 40.0) set v_vital_val = 40.0 endif
      set v_y = v_plot_y0 + cnvtint(((40.0 - v_vital_val) * v_plot_h) / 6.0)
      set v_temp_points = concat(v_temp_points, trim(cnvtstring(v_x), 3), ",", trim(cnvtstring(v_y), 3), " ")
      set v_vital_title = concat(vital_day_rec->qual[v_i].temp_name, " ", trim(format(vital_day_rec->qual[v_i].temp_val, "###.##")), " ", vital_day_rec->qual[v_i].temp_units, " - ", format(vital_day_rec->qual[v_i].temp_dt, "DD-MMM-YYYY HH:MM;;D"))
      set v_temp_marks = concat(v_temp_marks, '<circle class="vital-dot temp-dot" data-day-idx="', trim(cnvtstring(v_i - 1), 3), '" cx="', trim(cnvtstring(v_x), 3), '" cy="', trim(cnvtstring(v_y), 3), '" r="2.5"><title>', v_vital_title, '</title></circle>')
      set v_temp_count = v_temp_count + 1
    endif

    if (vital_day_rec->qual[v_i].hr_val > 0)
      set v_vital_val = vital_day_rec->qual[v_i].hr_val
      if (v_vital_val < 40.0) set v_vital_val = 40.0 endif
      if (v_vital_val > 180.0) set v_vital_val = 180.0 endif
      set v_y = v_plot_y0 + cnvtint(((180.0 - v_vital_val) * v_plot_h) / 140.0)
      set v_hr_points = concat(v_hr_points, trim(cnvtstring(v_x), 3), ",", trim(cnvtstring(v_y), 3), " ")
      set v_vital_title = concat(vital_day_rec->qual[v_i].hr_name, " ", trim(format(vital_day_rec->qual[v_i].hr_val, "###.##")), " ", vital_day_rec->qual[v_i].hr_units, " - ", format(vital_day_rec->qual[v_i].hr_dt, "DD-MMM-YYYY HH:MM;;D"))
      set v_hr_marks = concat(v_hr_marks, '<circle class="vital-dot hr-dot" data-day-idx="', trim(cnvtstring(v_i - 1), 3), '" cx="', trim(cnvtstring(v_x), 3), '" cy="', trim(cnvtstring(v_y), 3), '" r="2.5"><title>', v_vital_title, '</title></circle>')
      set v_hr_count = v_hr_count + 1
    endif

    if (vital_day_rec->qual[v_i].sys_val > 0)
      set v_vital_val = vital_day_rec->qual[v_i].sys_val
      if (v_vital_val < 40.0) set v_vital_val = 40.0 endif
      if (v_vital_val > 200.0) set v_vital_val = 200.0 endif
      set v_y = v_plot_y0 + cnvtint(((200.0 - v_vital_val) * v_plot_h) / 160.0)
      set v_sys_points = concat(v_sys_points, trim(cnvtstring(v_x), 3), ",", trim(cnvtstring(v_y), 3), " ")
      set v_vital_title = concat(vital_day_rec->qual[v_i].sys_name, " ", trim(format(vital_day_rec->qual[v_i].sys_val, "###.##")), " ", vital_day_rec->qual[v_i].sys_units, " - ", format(vital_day_rec->qual[v_i].sys_dt, "DD-MMM-YYYY HH:MM;;D"))
      set v_sys_marks = concat(v_sys_marks, '<circle class="vital-dot bp-dot" data-day-idx="', trim(cnvtstring(v_i - 1), 3), '" cx="', trim(cnvtstring(v_x), 3), '" cy="', trim(cnvtstring(v_y), 3), '" r="2.5"><title>', v_vital_title, '</title></circle>')
      set v_bp_count = v_bp_count + 1
    endif

    if (vital_day_rec->qual[v_i].dia_val > 0)
      set v_vital_val = vital_day_rec->qual[v_i].dia_val
      if (v_vital_val < 40.0) set v_vital_val = 40.0 endif
      if (v_vital_val > 200.0) set v_vital_val = 200.0 endif
      set v_y2 = v_plot_y0 + cnvtint(((200.0 - v_vital_val) * v_plot_h) / 160.0)
      set v_dia_points = concat(v_dia_points, trim(cnvtstring(v_x), 3), ",", trim(cnvtstring(v_y2), 3), " ")
      set v_vital_title = concat(vital_day_rec->qual[v_i].dia_name, " ", trim(format(vital_day_rec->qual[v_i].dia_val, "###.##")), " ", vital_day_rec->qual[v_i].dia_units, " - ", format(vital_day_rec->qual[v_i].dia_dt, "DD-MMM-YYYY HH:MM;;D"))
      set v_dia_marks = concat(v_dia_marks, '<circle class="vital-dot bp-dot" data-day-idx="', trim(cnvtstring(v_i - 1), 3), '" cx="', trim(cnvtstring(v_x), 3), '" cy="', trim(cnvtstring(v_y2), 3), '" r="2.5"><title>', v_vital_title, '</title></circle>')
      if (vital_day_rec->qual[v_i].sys_val <= 0)
        set v_bp_count = v_bp_count + 1
      endif
      if (vital_day_rec->qual[v_i].sys_val > 0)
        set v_vital_val = vital_day_rec->qual[v_i].sys_val
        if (v_vital_val < 40.0) set v_vital_val = 40.0 endif
        if (v_vital_val > 200.0) set v_vital_val = 200.0 endif
        set v_y = v_plot_y0 + cnvtint(((200.0 - v_vital_val) * v_plot_h) / 160.0)
        set v_bp_poly = concat(v_bp_poly, '<line class="bp-fill-line" x1="', trim(cnvtstring(v_x), 3), '" y1="', trim(cnvtstring(v_y), 3), '" x2="', trim(cnvtstring(v_x), 3), '" y2="', trim(cnvtstring(v_y2), 3), '"></line>')
      endif
    endif

    if (vital_day_rec->qual[v_i].spo2_val > 0)
      set v_vital_val = vital_day_rec->qual[v_i].spo2_val
      if (v_vital_val < 80.0) set v_vital_val = 80.0 endif
      if (v_vital_val > 100.0) set v_vital_val = 100.0 endif
      set v_y = v_plot_y0 + cnvtint(((100.0 - v_vital_val) * v_plot_h) / 20.0)
      set v_spo2_points = concat(v_spo2_points, trim(cnvtstring(v_x), 3), ",", trim(cnvtstring(v_y), 3), " ")
      set v_vital_title = concat(vital_day_rec->qual[v_i].spo2_name, " ", trim(format(vital_day_rec->qual[v_i].spo2_val, "###.##")), " ", vital_day_rec->qual[v_i].spo2_units, " - ", format(vital_day_rec->qual[v_i].spo2_dt, "DD-MMM-YYYY HH:MM;;D"))
      set v_spo2_marks = concat(v_spo2_marks, '<circle class="vital-dot spo2-dot" data-day-idx="', trim(cnvtstring(v_i - 1), 3), '" cx="', trim(cnvtstring(v_x), 3), '" cy="', trim(cnvtstring(v_y), 3), '" r="2.5"><title>', v_vital_title, '</title></circle>')
      set v_spo2_count = v_spo2_count + 1
    endif

    set v_i = v_i + 1
  endwhile

  set v_vitals_count = v_temp_count + v_hr_count + v_bp_count + v_spo2_count
endif

/* ========================================================================== */
/* PASS 3: BUILD TABLE ROWS (Appended to Array)                               */
/* ========================================================================== */
set html_table->cnt = 0
if (admin_rec->cnt > 0)
select into "nl:"
  med_name = trim(oc.primary_mnemonic)
, admin_src = admin_rec->qual[d.seq].src
, day_key = format(admin_rec->qual[d.seq].admin_dt_tm, "YYYYMMDD;;D")
, src_id = admin_rec->qual[d.seq].admin_id
, o.current_start_dt_tm
, o_order_status_disp = uar_get_code_display(o.order_status_cd)
, o.status_dt_tm
, indication = substring(1,60,trim(od_indication.oe_field_display_value))
, ordered_target_dose = oi.ordered_dose
, ordered_target_dose_unit = uar_get_code_display(oi.ordered_dose_unit_cd)
, strength_val = substring(1,60,trim(od_strength.oe_field_display_value))
, strength_unit = substring(1,60,trim(od_strengthunit.oe_field_display_value))
, volume_val     = substring(1,60,trim(od_volume.oe_field_display_value))
, volume_unit    = substring(1,60,trim(od_volumeunit.oe_field_display_value))
, simplified_disp = trim(o.simplified_display_line)
, fin_alias = trim(ea.alias)
, encntr_id_val = o.encntr_id
, o.order_id
from (dummyt d with seq = admin_rec->cnt), orders o, order_catalog oc, order_ingredient oi, order_detail od_indication, order_detail od_strength, order_detail od_strengthunit, order_detail od_volume, order_detail od_volumeunit, encntr_alias ea
plan d join o where o.order_id = admin_rec->qual[d.seq].order_id
join oc where oc.catalog_cd = o.catalog_cd
join oi where oi.order_id = outerjoin(o.order_id) and oi.comp_sequence = outerjoin(1)
join od_indication where od_indication.order_id = outerjoin(o.order_id) and od_indication.oe_field_meaning_id = outerjoin(15)
join od_strength where od_strength.order_id = outerjoin(o.order_id) and od_strength.oe_field_meaning_id = outerjoin(2056)
join od_strengthunit where od_strengthunit.order_id = outerjoin(o.order_id) and od_strengthunit.oe_field_meaning_id = outerjoin(2057)
join od_volume where od_volume.order_id = outerjoin(o.order_id) and od_volume.oe_field_meaning_id = outerjoin(2058)
join od_volumeunit where od_volumeunit.order_id = outerjoin(o.order_id) and od_volumeunit.oe_field_meaning_id = outerjoin(2059)
join ea where ea.encntr_id = outerjoin(o.encntr_id) and ea.encntr_alias_type_cd = outerjoin(1077.00)
order by o.order_id, cnvtupper(trim(oc.primary_mnemonic)), day_key, src_id

head report
  v_row_cnt = 0
  v_table_dot_days_list = ""

head o.order_id
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
  v_oid = cnvtstring(o.order_id)
  v_dot = 0
  v_doses = 0
  v_table_dot_days_list = ""

head day_key
  v_key8 = day_key
  if (findstring(concat("~", v_key8, "~"), v_table_dot_days_list) = 0)
    v_dot = v_dot + 1
    v_table_dot_days_list = concat(v_table_dot_days_list, "~", v_key8, "~")
  endif

head src_id
  v_doses = v_doses + 1

foot o.order_id
  v_dose = ordered_target_dose
  v_unit = ordered_target_dose_unit
  v_ind = indication
  v_disp = simplified_disp
  v_fin = fin_alias
  v_encntr_id = trim(cnvtstring(encntr_id_val, 20, 0))
  v_start = format(o.current_start_dt_tm,"DD/MM/YYYY;;d")
  v_stat = o_order_status_disp
  v_sdt = format(o.status_dt_tm,"DD/MM/YYYY;;d")

  if (v_dose > 0)
    v_dose_str = trim(format(v_dose, "########.####"))
    while (textlen(v_dose_str) > 0 and substring(textlen(v_dose_str), 1, v_dose_str) = "0")
      v_dose_str = substring(1, textlen(v_dose_str) - 1, v_dose_str)
    endwhile
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
  if (textlen(trim(strength_val)) > 0)
    v_s = trim(strength_val)
    if (textlen(trim(strength_unit)) > 0)
      v_s = concat(v_s, " ", trim(strength_unit))
    endif
  endif
  if (textlen(trim(volume_val)) > 0)
    v_v = trim(volume_val)
    if (textlen(trim(volume_unit)) > 0)
      v_v = concat(v_v, " ", trim(volume_unit))
    endif
  endif
  if (textlen(v_s) > 0)
    v_actual_dose_str = v_s
  endif
  if (textlen(v_v) > 0 and textlen(v_s) = 0)
    v_actual_dose_str = v_v
  endif
  if (textlen(v_actual_dose_str) = 0 and textlen(v_dose_str) > 0)
    v_actual_dose_str = v_dose_str
  endif
  if (trim(v_fin) = "")
    v_fin = "--"
  endif

  v_route_upper = cnvtupper(trim(v_disp, 3))
  if (trim(v_route_upper, 3) = "")
    v_route_class = " route-unk"
  elseif (findstring("INTRAVENOUS", v_route_upper) > 0 or v_route_upper = "IV" or findstring(" IV", v_route_upper) > 0)
    v_route_class = " route-iv"
  elseif (findstring("ORAL", v_route_upper) > 0 or findstring(" PO", v_route_upper) > 0 or findstring("BY MOUTH", v_route_upper) > 0)
    v_route_class = " route-po"
  elseif (findstring("INTRAMUSCULAR", v_route_upper) > 0 or findstring(" IM", v_route_upper) > 0)
    v_route_class = " route-im"
  elseif (findstring("SUBCUT", v_route_upper) > 0 or findstring(" SC", v_route_upper) > 0 or findstring(" SQ", v_route_upper) > 0)
    v_route_class = " route-sc"
  elseif (findstring("ENTERAL", v_route_upper) > 0 or findstring("NASOGASTRIC", v_route_upper) > 0 or findstring(" NG", v_route_upper) > 0)
    v_route_class = " route-en"
  elseif (findstring("INHAL", v_route_upper) > 0 or findstring("NEB", v_route_upper) > 0)
    v_route_class = " route-in"
  elseif (findstring("TOPICAL", v_route_upper) > 0)
    v_route_class = " route-tp"
  elseif (findstring("BUCCAL", v_route_upper) > 0)
    v_route_class = " route-bu"
  elseif (findstring("RECTAL", v_route_upper) > 0 or findstring(" PR,", v_route_upper) > 0 or findstring(" PR ", v_route_upper) > 0)
    v_route_class = " route-pr"
  else
    v_route_class = " route-ot"
  endif

  v_row_cnt = v_row_cnt + 1

  /* APPEND TO TABLE ARRAY */
  html_table->cnt = html_table->cnt + 1
  stat = alterlist(html_table->qual, html_table->cnt)
  html_table->qual[html_table->cnt].text = concat(
    '<tr class="dimmable', if(mod(v_row_cnt, 2) = 0) ' even' else '' endif, '" data-med="', v_drug, '">',
      '<td>', v_drug, if(v_order_src = "SN") ' <span style="color:#888;font-size:10px;">(Anes)</span>' else '' endif, '</td>',
      '<td class="dot-val"><span class="pill">', trim(cnvtstring(v_doses), 3), '</span></td>',
      '<td class="dot-val"><span class="pill">', trim(cnvtstring(v_dot), 3), '</span></td>',
      "<td>", v_dose_str, "</td>",
      '<td style="display:none;">', v_actual_dose_str, '</td>',
      '<td class="order-detail', v_route_class, '">', v_disp, "</td>",
      "<td>", v_ind, "</td>",
      "<td>", v_start, "</td>",
      "<td>", v_stat, "</td>",
      "<td>", v_sdt, "</td>",
      "<td>", v_oid, "</td>",
      build2(~<td><a href="javascript:APPLINK(0,'Powerchart.exe','/PERSONID=~, trim(cnvtstring($PAT_PersonId, 20, 0), 3), ~ /ENCNTRID=~, v_encntr_id, ~')">~, v_fin, ~</a></td>~),
    "</tr>"
  )
  v_debug_table = concat(v_debug_table,
    trim(cnvtstring(html_table->cnt),3), ". ",
    v_drug,
    " | Doses=", trim(cnvtstring(v_doses),3),
    " DOT=", trim(cnvtstring(v_dot),3),
    " | Order ID=", v_oid,
    " | FIN=", v_fin,
    "<br/>")
with nocounter
endif

if (html_table->cnt = 0)
  set html_table->cnt = 1
  set stat = alterlist(html_table->qual, 1)
  set html_table->qual[1].text = '<tr><td colspan="11">No antimicrobial orders found in the selected window.</td></tr>'
endif

/* ========================================================================== */
/* FINAL HTML OUTPUT GENERATION (Reads from Array Buffers)                    */
/* ========================================================================== */

/* Output via _memory_reply_string for XMLCclRequest compatibility          */
/* select into $outdev is not valid in XCR context.                         */
/* _memory_reply_string is a built-in gvc — no declare needed.              */

set _memory_reply_string = ""

/* --- HEAD & CSS --- */
set _memory_reply_string = concat(_memory_reply_string, '<!doctype html><html lang="en"><head>')
set _memory_reply_string = concat(_memory_reply_string, '<meta charset="utf-8" /><meta name="viewport" content="width=device-width, initial-scale=1" />')
set _memory_reply_string = concat(_memory_reply_string, '<meta name="discern" content="CCLLINK,APPLINK"/>')
set _memory_reply_string = concat(_memory_reply_string, '<title>Antimicrobial Days of Therapy - By Date</title>')
set _memory_reply_string = concat(_memory_reply_string, '<style>')
set _memory_reply_string = concat(_memory_reply_string, ':root{--bg-main:#fff;--bg-alt:#fafafa;--border-color:#d6d9dd;--border-dark:#b5b5b5;--border-light:#dde1e5;--cerner-blue:#0086CE;')
set _memory_reply_string = concat(_memory_reply_string, '--header-bg:#e7eaee;--sticky-bg:#ffffff;--sticky-bg-alt:#fafafa;}')
set _memory_reply_string = concat(_memory_reply_string, '*,*:before,*:after{box-sizing:border-box}')
set _memory_reply_string = concat(_memory_reply_string, concat('body{margin:0;font:', v_font_size, '/1.4 -apple-system,BlinkMacSystemFont,Segoe UI,Roboto,Arial,sans-serif;color:#111;background:var(--bg-main);padding:0;}'))
set _memory_reply_string = concat(_memory_reply_string, '.wrap{width:100%; max-width:100%; margin:0; padding:0; box-sizing:border-box;}')
set _memory_reply_string = concat(_memory_reply_string, 'h1{font-size:18px;margin:0 0 8px;}')
set _memory_reply_string = concat(_memory_reply_string, 'h2{font-size:15px;margin:16px 0 2px;padding-top:0;}')
set _memory_reply_string = concat(_memory_reply_string, '.sub{color:#444;margin:4px 0 16px;}')
set _memory_reply_string = concat(_memory_reply_string, '.meta-flex { display: flex; flex-wrap: wrap; gap: 16px; align-items: center; }')
set _memory_reply_string = concat(_memory_reply_string, '.legend{margin-top:6px;color:#555;font-size:12px}')
set _memory_reply_string = concat(_memory_reply_string, '.chart-wrap { overflow-x:auto; overflow-y:visible; margin-bottom:12px; width:100%; display:block; }')
set _memory_reply_string = concat(_memory_reply_string, '.chart-grid { display: grid; background: var(--bg-main); width: max-content; border-left: 1px solid var(--border-dark); font-size: 12px; }')
set _memory_reply_string = concat(_memory_reply_string, '.grid-cell { border-right: 1px solid var(--border-light); border-bottom: none; background: var(--bg-main); padding: 0; display: flex; align-items: center; min-width: 0; }')
set _memory_reply_string = concat(_memory_reply_string, '.grid-cell.label, .grid-cell.sticky-med, .grid-cell.sticky-doses, .grid-cell.sticky-dot { border-right-color: var(--border-dark) !important; border-bottom: 1px solid var(--border-dark) !important; }')
set _memory_reply_string = concat(_memory_reply_string, 'table.data-tbl th, .grid-cell.label:not(.medname) { background: var(--header-bg) !important; color: #2f3c4b; font-weight: 600 !important; padding: 4px 8px; }')
set _memory_reply_string = concat(_memory_reply_string, 'table.data-tbl th { text-align:left; height:26px; font-size:12px !important; }')
set _memory_reply_string = concat(_memory_reply_string, '.has-help{cursor:help;text-decoration:underline dotted #6b7280;text-underline-offset:2px;position:relative;overflow:visible!important;}')
set _memory_reply_string = concat(_memory_reply_string, '.has-help:hover::after{content:attr(data-help);position:absolute;left:50%;top:100%;transform:translateX(-50%);z-index:2000;width:260px;padding:6px 8px;border:1px solid #6b7280;background:#fff;color:#111;text-align:left;font-weight:400;line-height:1.25;white-space:normal;box-shadow:0 2px 6px rgba(0,0,0,.18);}')
set _memory_reply_string = concat(_memory_reply_string, '.grid-cell.has-help:hover::after{content:none;display:none;}')
set _memory_reply_string = concat(_memory_reply_string, '.grid-cell.label { min-height: 26px; }')
set _memory_reply_string = concat(_memory_reply_string, '.sticky-med { position:sticky; left:0; z-index:10; background:var(--sticky-bg); overflow:hidden; white-space:nowrap; text-overflow:ellipsis; width:200px; min-width:200px; max-width:200px; }')
set _memory_reply_string = concat(_memory_reply_string, '.sticky-med.has-help{overflow:visible!important;z-index:50;}')
set _memory_reply_string = concat(_memory_reply_string, '.sticky-doses { position:sticky; left:200px; z-index:10; background:var(--sticky-bg); width:40px; min-width:40px; max-width:40px; text-align:center; justify-content:center; }')
set _memory_reply_string = concat(_memory_reply_string, '.sticky-dot { position:sticky; left:240px; z-index:10; background:var(--sticky-bg); box-shadow: 2px 0 5px -2px rgba(0,0,0,0.2); width:40px; min-width:40px; max-width:40px; text-align:center; justify-content:center; }')
set _memory_reply_string = concat(_memory_reply_string, '.hdr-intersect { z-index:20 !important; border-top:1px solid var(--border-dark) !important; }')
set _memory_reply_string = concat(_memory_reply_string, '.even-cell.sticky-med, .even-cell.sticky-doses, .even-cell.sticky-dot, .even-cell.medname { background: var(--bg-alt) !important; }')
set _memory_reply_string = concat(_memory_reply_string, '.dot-val { justify-content: center; }')
set _memory_reply_string = concat(_memory_reply_string, concat('.grid-cell.medname { padding:2px 6px; font-size:', v_med_font_size, ' !important; }'))
set _memory_reply_string = concat(_memory_reply_string, '.med-trigger { cursor: pointer; color: #111; transition: background 0.2s; }')
set _memory_reply_string = concat(_memory_reply_string, '.med-trigger:hover { background-color: #e0f0ff !important; }')
set _memory_reply_string = concat(_memory_reply_string, '.route-toggle-cell{justify-content:flex-start;padding:2px 6px!important;}')
set _memory_reply_string = concat(_memory_reply_string, '.route-toggle-wrap{display:flex;align-items:center;gap:6px;}')
set _memory_reply_string = concat(_memory_reply_string, '.route-toggle-label{font-size:11px;line-height:1;color:#2f3c4b;font-weight:600;}')
set _memory_reply_string = concat(_memory_reply_string, '.route-toggle{position:relative;width:30px;height:16px;border:1px solid #9eb4c8;border-radius:999px;background:#fff;padding:0;cursor:pointer;}')
set _memory_reply_string = concat(_memory_reply_string, '.route-toggle::after{content:"";position:absolute;top:2px;left:2px;width:10px;height:10px;border-radius:50%;background:#7b8794;transition:left .15s ease,background .15s ease;}')
set _memory_reply_string = concat(_memory_reply_string, '.route-toggle:hover{border-color:#0086ce;}')
set _memory_reply_string = concat(_memory_reply_string, '.route-toggle.active{background:#e0f0ff;border-color:#0086ce;}')
set _memory_reply_string = concat(_memory_reply_string, '.route-toggle.active::after{left:16px;background:#0086ce;}')
set _memory_reply_string = concat(_memory_reply_string, '.route-code{display:none;font-size:8px;line-height:1;font-weight:700;}')
set _memory_reply_string = concat(_memory_reply_string, '.route-mode .chart-wrap .dose-count{display:none;}')
set _memory_reply_string = concat(_memory_reply_string, '.route-mode .chart-wrap .route-code{display:inline;}')
set _memory_reply_string = concat(_memory_reply_string, '.route-mode .chart-wrap .cell.on.route-iv::after{background:#0086ce;}')
set _memory_reply_string = concat(_memory_reply_string, '.route-mode .chart-wrap .cell.on.route-po::after{background:#2f9e44;}')
set _memory_reply_string = concat(_memory_reply_string, '.route-mode .chart-wrap .cell.on.route-im::after{background:#ae3ec9;}')
set _memory_reply_string = concat(_memory_reply_string, '.route-mode .chart-wrap .cell.on.route-sc::after{background:#f08c00;}')
set _memory_reply_string = concat(_memory_reply_string, '.route-mode .chart-wrap .cell.on.route-en::after{background:#7950f2;}')
set _memory_reply_string = concat(_memory_reply_string, '.route-mode .chart-wrap .cell.on.route-pr::after{background:#d6336c;}')
set _memory_reply_string = concat(_memory_reply_string, '.route-mode .chart-wrap .cell.on.route-in::after{background:#15aabf;}')
set _memory_reply_string = concat(_memory_reply_string, '.route-mode .chart-wrap .cell.on.route-tp::after{background:#7048e8;}')
set _memory_reply_string = concat(_memory_reply_string, '.route-mode .chart-wrap .cell.on.route-bu::after{background:#0c8599;}')
set _memory_reply_string = concat(_memory_reply_string, '.route-mode .chart-wrap .cell.on.route-ot::after{background:#495057;}')
set _memory_reply_string = concat(_memory_reply_string, '.route-mode .chart-wrap .cell.on.route-unk::after{background:#adb5bd;}')
set _memory_reply_string = concat(_memory_reply_string, '.tick.today-col{background:#e7f4ff!important;}')
set _memory_reply_string = concat(_memory_reply_string, 'body .cell.on.today-col::after{background:#7dc4eb;}')
set _memory_reply_string = concat(_memory_reply_string, '.filter-icon { font-size: 8px; opacity: 0.5; margin-left: 6px; }')
set _memory_reply_string = concat(_memory_reply_string, '.dimmed { opacity: 0.15; filter: grayscale(100%); pointer-events: none; transition: opacity 0.3s ease; }')
set _memory_reply_string = concat(_memory_reply_string, '.dimmable { transition: opacity 0.3s ease; }')
set _memory_reply_string = concat(_memory_reply_string, '.active-filter { background-color: #e0f0ff !important; font-weight: 700; }')
set _memory_reply_string = concat(_memory_reply_string, '.grid-cell.dimmed.sticky-med, .grid-cell.dimmed.sticky-doses, .grid-cell.dimmed.sticky-dot { opacity: 1 !important; filter: none !important; color: #b5b5b5 !important; }')
set _memory_reply_string = concat(_memory_reply_string, '.grid-cell.dimmed.sticky-med .pill, .grid-cell.dimmed.sticky-doses .pill, .grid-cell.dimmed.sticky-dot .pill { background: #f0f0f0 !important; color: #b5b5b5 !important; box-shadow: none !important; }')
set _memory_reply_string = concat(_memory_reply_string, '.row-hover:not(.on):not(.always-on) { background-color: transparent !important; }')
set _memory_reply_string = concat(_memory_reply_string, '.cell.row-hover:not(.on)::after { background:#b8d4ee !important; }')
set _memory_reply_string = concat(_memory_reply_string, '.cell, .tick { width:14px; min-width:14px; max-width:14px; justify-content:center; font-size:10px; }')
set _memory_reply_string = concat(_memory_reply_string, '.cell { border-right:1px solid #f8f8f8 !important; border-bottom:none !important; border-left:none !important; color:transparent; background:transparent !important; position:relative; z-index:1; }')
set _memory_reply_string = concat(_memory_reply_string, '.tick { border-right:none !important; height:22px; position:relative; overflow:visible !important; align-items:center; padding-bottom:0; justify-content:center; font-size:10px; color:#555; }')
set _memory_reply_string = concat(_memory_reply_string, '.tick::after { content:""; position:absolute; right:0; bottom:0; width:1px; height:6px; background:var(--border-dark); }')
set _memory_reply_string = concat(_memory_reply_string, '.mo-span { height:20px; font-size:11px; font-weight:600; color:#2f3c4b; background:var(--header-bg) !important; border-top:1px solid var(--border-dark) !important; border-right:1px solid var(--border-dark) !important; border-bottom:1px solid var(--border-dark) !important; padding:0 4px; overflow:hidden; white-space:nowrap; text-overflow:ellipsis; align-items:center; }')
set _memory_reply_string = concat(_memory_reply_string, '.grid-cell.axis-header { display:block; line-height:18px; overflow:visible; white-space:nowrap; border-top:1px solid var(--border-dark) !important; }')
set _memory_reply_string = concat(_memory_reply_string, '.cell::after { content:""; position:absolute; top:50%; left:50%; transform:translate(-50%,-50%); width:14px; height:12px; background:#F5F5F6; border-radius:0px; z-index:-1; }')
set _memory_reply_string = concat(_memory_reply_string, '.cell.on { color:var(--bg-main) !important; font-weight:600; }')
set _memory_reply_string = concat(_memory_reply_string, '.cell.on::after { width:14px; height:12px; background:var(--cerner-blue); border-radius:0px; }')
set _memory_reply_string = concat(_memory_reply_string, '.cell.on:empty::before { content:"1"; }')
set _memory_reply_string = concat(_memory_reply_string, '.cell.sum-yes, .cell.sum-no, .cell.enc-c1, .cell.enc-c2, .cell.enc-c3, .cell.enc-c4 { background:transparent !important; }')
set _memory_reply_string = concat(_memory_reply_string, '.cell.sum-yes::after { width:14px; height:12px; background: #f37074be; }')
set _memory_reply_string = concat(_memory_reply_string, '.cell.sum-no::after { width:14px; height:12px; background: #a8d08dbe; }')
set _memory_reply_string = concat(_memory_reply_string, '.sum-border { border-top:2px solid #a0a0a0 !important; }')
set _memory_reply_string = concat(_memory_reply_string, '.pill { display:inline-block; padding:2px 6px; border-radius:12px; background:#eef; color:#334; line-height:1; }')
set _memory_reply_string = concat(_memory_reply_string, '.cell.enc-c1::after { width:14px; height:12px; background:#b8d8f8; }')
set _memory_reply_string = concat(_memory_reply_string, '.cell.enc-c2::after { width:14px; height:12px; background: #b3d0ebb4; }')
set _memory_reply_string = concat(_memory_reply_string, '.cell.enc-c3::after { width:14px; height:12px; background:#c8e8fb; }')
set _memory_reply_string = concat(_memory_reply_string, '.cell.enc-c4::after { width:14px; height:12px; background:#aad8f7; }')
set _memory_reply_string = concat(_memory_reply_string, '.enc-border { border-top:2px solid #90b8e0 !important; }')
set _memory_reply_string = concat(_memory_reply_string, '.enc-label-cell { font-size:11px !important; }')
set _memory_reply_string = concat(_memory_reply_string, '.enc-label-cell a { color:var(--cerner-blue); text-decoration:none; font-weight:600; }')
set _memory_reply_string = concat(_memory_reply_string, '.enc-cell-text { font-size:8px; font-weight:700; color:#111; line-height:1; overflow:hidden; max-width:14px; display:block; text-align:center; }')
set _memory_reply_string = concat(_memory_reply_string, '.vitals-wrap{position:relative;overflow-x:auto;overflow-y:visible;width:100%;margin:2px 0 10px;display:block;}')
set _memory_reply_string = concat(_memory_reply_string, '.vitals-grid{display:grid;width:max-content;border-left:1px solid var(--border-dark);background:var(--bg-main);font-size:12px;}')
set _memory_reply_string = concat(_memory_reply_string, '.vitals-grid .grid-cell{border-bottom:1px solid var(--border-dark);}')
set _memory_reply_string = concat(_memory_reply_string, '.vitals-title{font-size:14px!important;font-weight:700!important;color:#111!important;background:var(--bg-main)!important;}')
set _memory_reply_string = concat(_memory_reply_string, '.vital-scale{font-size:10px;color:#2f3c4b;line-height:1.15;justify-content:center;text-align:center;}')
set _memory_reply_string = concat(_memory_reply_string, '.vital-plot{height:58px;background:repeating-linear-gradient(to right,#f7f8fa 0,#f7f8fa 13px,#e7eaee 13px,#e7eaee 14px);border-right:1px solid var(--border-dark);border-bottom:1px solid var(--border-dark);position:relative;}')
set _memory_reply_string = concat(_memory_reply_string, '.vital-svg{display:block;width:100%;height:58px;overflow:visible;}')
set _memory_reply_string = concat(_memory_reply_string, '.vital-line{fill:none;stroke-width:1.5;vector-effect:non-scaling-stroke;}')
set _memory_reply_string = concat(_memory_reply_string, '.temp-line{stroke:#2f5f9f;}.hr-line{stroke:#9b2f2f;}.sys-line{stroke:#2f8f46;}.dia-line{stroke:#b57921;}.spo2-line{stroke:#25aeb8;}')
set _memory_reply_string = concat(_memory_reply_string, '.vital-dot{stroke:#fff;stroke-width:.8;vector-effect:non-scaling-stroke;}.temp-dot{fill:#2f5f9f;}.hr-dot{fill:#9b2f2f;}.bp-dot{fill:#2f8f46;}.spo2-dot{fill:#25aeb8;}')
set _memory_reply_string = concat(_memory_reply_string, '.bp-fill-line{stroke:#84c98f;stroke-width:3;opacity:.28;vector-effect:non-scaling-stroke;}')
set _memory_reply_string = concat(_memory_reply_string, '.vital-ref{stroke:#6b7280;stroke-width:1;stroke-dasharray:3 3;opacity:.65;vector-effect:non-scaling-stroke;}')
set _memory_reply_string = concat(_memory_reply_string, '.vital-no-data{position:absolute;inset:0;display:flex;align-items:center;padding-left:8px;color:#777;font-size:11px;background:rgba(255,255,255,.7);}')
set _memory_reply_string = concat(_memory_reply_string, '.vital-guide{display:none;position:absolute;top:0;bottom:0;width:1px;background:#111;opacity:.45;z-index:100;pointer-events:none;}')
set _memory_reply_string = concat(_memory_reply_string, 'table.data-tbl { width:100%; min-width:1460px; border-collapse:separate; border-spacing:0; margin-top:2px; font-size:12px; border-top:1px solid var(--border-dark); border-left:1px solid var(--border-dark); border-bottom:2px solid #a0a0a0; table-layout:fixed; }')
set _memory_reply_string = concat(_memory_reply_string, 'table.data-tbl th, table.data-tbl td { border-right:1px solid var(--border-dark); border-bottom:1px solid var(--border-dark); padding:4px 6px; text-align:left; background:var(--bg-main); word-break:break-word; overflow-wrap:break-word; overflow:hidden; transition: background-color 0.2s; }')
set _memory_reply_string = concat(_memory_reply_string, 'table.data-tbl th:nth-child(1), table.data-tbl td:nth-child(1) { box-sizing:border-box !important; width:200px; min-width:200px; max-width:200px; }')
set _memory_reply_string = concat(_memory_reply_string, 'table.data-tbl th:nth-child(2), table.data-tbl td:nth-child(2) { box-sizing:border-box !important; width:40px; min-width:40px; max-width:40px; text-align:center; padding:4px 0; }')
set _memory_reply_string = concat(_memory_reply_string, 'table.data-tbl th:nth-child(3), table.data-tbl td:nth-child(3) { box-sizing:border-box !important; width:40px; min-width:40px; max-width:40px; text-align:center; padding:4px 0; }')
set _memory_reply_string = concat(_memory_reply_string, 'table.data-tbl th:nth-child(4), table.data-tbl td:nth-child(4) { box-sizing:border-box !important; width:100px; min-width:100px; max-width:100px; }')
set _memory_reply_string = concat(_memory_reply_string, 'table.data-tbl th:nth-child(6), table.data-tbl td:nth-child(6) { box-sizing:border-box !important; width:350px; min-width:350px; max-width:350px; }')
set _memory_reply_string = concat(_memory_reply_string, 'table.data-tbl th:nth-child(7), table.data-tbl td:nth-child(7) { box-sizing:border-box !important; width:250px; min-width:250px; max-width:250px; }')
set _memory_reply_string = concat(_memory_reply_string, '.order-detail{position:relative;}')
set _memory_reply_string = concat(_memory_reply_string, '.route-mode .order-detail{padding-left:22px!important;}')
set _memory_reply_string = concat(_memory_reply_string, '.route-mode .order-detail::before{content:"--";position:absolute;left:0;top:0;bottom:0;width:17px;background:#adb5bd;color:#fff;display:flex;align-items:center;justify-content:center;font-size:8px;font-weight:700;line-height:1;}')
set _memory_reply_string = concat(_memory_reply_string, '.route-mode .order-detail.route-iv::before{content:"IV";background:#0086ce;}')
set _memory_reply_string = concat(_memory_reply_string, '.route-mode .order-detail.route-po::before{content:"PO";background:#2f9e44;}')
set _memory_reply_string = concat(_memory_reply_string, '.route-mode .order-detail.route-im::before{content:"IM";background:#ae3ec9;}')
set _memory_reply_string = concat(_memory_reply_string, '.route-mode .order-detail.route-sc::before{content:"SC";background:#f08c00;}')
set _memory_reply_string = concat(_memory_reply_string, '.route-mode .order-detail.route-en::before{content:"EN";background:#7950f2;}')
set _memory_reply_string = concat(_memory_reply_string, '.route-mode .order-detail.route-pr::before{content:"PR";background:#d6336c;}')
set _memory_reply_string = concat(_memory_reply_string, '.route-mode .order-detail.route-in::before{content:"IN";background:#15aabf;}')
set _memory_reply_string = concat(_memory_reply_string, '.route-mode .order-detail.route-tp::before{content:"TP";background:#7048e8;}')
set _memory_reply_string = concat(_memory_reply_string, '.route-mode .order-detail.route-bu::before{content:"BU";background:#0c8599;}')
set _memory_reply_string = concat(_memory_reply_string, '.route-mode .order-detail.route-ot::before{content:"OT";background:#495057;}')
set _memory_reply_string = concat(_memory_reply_string, '.route-mode .order-detail.route-unk::before{content:"--";background:#adb5bd;}')
set _memory_reply_string = concat(_memory_reply_string, 'table.data-tbl tr.even td { background:var(--bg-alt); }')
set _memory_reply_string = concat(_memory_reply_string, 'table.data-tbl tbody tr:last-child td { border-bottom:none; }')
set _memory_reply_string = concat(_memory_reply_string, 'table.data-tbl tbody tr:hover td { background-color: #f0f7ff; cursor: default; }')
set _memory_reply_string = concat(_memory_reply_string, '</style></head><body><div class="wrap">')

/* --- CHART SECTION --- */
set _memory_reply_string = concat(_memory_reply_string, '<div class="legend">Each blue square marks a <b>day</b> where the medication has been administered. A number indicates the count of administrations for that day. Light blue column = current day to present time.<br/><b>Interactive:</b> Click a medication name to isolate its history across the chart and table.</div>')
set _memory_reply_string = concat(_memory_reply_string, '<div class="chart-wrap">')
if (v_days > 0)
  set _memory_reply_string = concat(_memory_reply_string, concat('<div class="chart-grid" style="grid-template-columns: 200px 40px 40px repeat(', trim(cnvtstring(v_days), 3), ', 14px);">'))
  set _memory_reply_string = concat(_memory_reply_string, concat('<div class="grid-cell label sticky-med hdr-intersect always-on">Medication</div><div class="grid-cell label sticky-doses hdr-intersect always-on">Doses</div><div class="grid-cell label sticky-dot hdr-intersect always-on">DOT</div><div class="grid-cell label axis-header always-on" style="grid-column: 4 / span ', trim(cnvtstring(v_days), 3), '; min-width:320px;">Date range: ', format(v_min_dt,"DD-MMM-YYYY;;D"), ' to ', format(v_max_dt,"DD-MMM-YYYY;;D"), ' (', trim(cnvtstring(v_days), 3), ' days)</div>'))

  if (textlen(v_header_html) > 0)
    set _memory_reply_string = concat(_memory_reply_string, '<div class="grid-cell sticky-med hdr-intersect always-on route-toggle-cell" style="background:var(--header-bg);border-bottom:1px solid var(--border-dark);"><span class="route-toggle-wrap"><span class="route-toggle-label">Route</span><button type="button" id="routeToggle" class="route-toggle" aria-pressed="false" title="Toggle chart squares between dose counts and route codes"></button></span></div>')
    set _memory_reply_string = concat(_memory_reply_string, '<div class="grid-cell sticky-doses hdr-intersect always-on" style="background:var(--header-bg);border-right:1px solid var(--border-dark);border-bottom:1px solid var(--border-dark);"></div>')
    set _memory_reply_string = concat(_memory_reply_string, '<div class="grid-cell sticky-dot hdr-intersect always-on" style="background:var(--header-bg);border-right:1px solid var(--border-dark);border-bottom:1px solid var(--border-dark);"></div>')
    set _memory_reply_string = concat(_memory_reply_string, v_month_html)
    set _memory_reply_string = concat(_memory_reply_string, '<div class="grid-cell sticky-med hdr-intersect always-on" style="background:var(--header-bg);border-right:1px solid var(--border-dark);border-bottom:1px solid var(--border-dark);"></div>')
    set _memory_reply_string = concat(_memory_reply_string, '<div class="grid-cell sticky-doses hdr-intersect always-on" style="background:var(--header-bg);border-right:1px solid var(--border-dark);border-bottom:1px solid var(--border-dark);"></div>')
    set _memory_reply_string = concat(_memory_reply_string, '<div class="grid-cell sticky-dot hdr-intersect always-on" style="background:var(--header-bg);border-right:1px solid var(--border-dark);border-bottom:1px solid var(--border-dark);"></div>')
    set _memory_reply_string = concat(_memory_reply_string, v_header_html)
  endif

  /* Output Chart HTML Array */
  set v_i = 1
  while (v_i <= html_chart->cnt)
    set _memory_reply_string = concat(_memory_reply_string, html_chart->qual[v_i].text)
    set v_i = v_i + 1
  endwhile

  set _memory_reply_string = concat(_memory_reply_string, '</div>')
else
  set _memory_reply_string = concat(_memory_reply_string, '<div style="padding:10px;border:1px solid var(--border-dark);background:var(--bg-main);">No administrations found.</div>')
endif
set _memory_reply_string = concat(_memory_reply_string, '</div>')

/* --- CLINICAL MONITORING TRENDS --- */
if (v_days > 0)
  set _memory_reply_string = concat(_memory_reply_string, concat('<div class="vitals-wrap"><div id="vitalGuide" class="vital-guide"></div><div class="vitals-grid" style="grid-template-columns: 200px 40px 40px repeat(', trim(cnvtstring(v_days), 3), ', 14px);">'))
  set _memory_reply_string = concat(_memory_reply_string, concat('<div class="grid-cell label sticky-med hdr-intersect always-on vitals-title">Clinical Monitoring Trends</div><div class="grid-cell label sticky-doses hdr-intersect always-on"></div><div class="grid-cell label sticky-dot hdr-intersect always-on"></div><div class="grid-cell label axis-header always-on" style="grid-column: 4 / span ', trim(cnvtstring(v_days), 3), ';">Aligned to medication date range</div>'))

  set _memory_reply_string = concat(_memory_reply_string, '<div class="grid-cell label sticky-med always-on">Temperature</div><div class="grid-cell label sticky-doses always-on vital-scale">40C<br/>34C</div><div class="grid-cell label sticky-dot always-on"></div>')
  set _memory_reply_string = concat(_memory_reply_string, concat('<div class="vital-plot" style="grid-column: 4 / span ', trim(cnvtstring(v_days), 3), '; width:', trim(cnvtstring(v_plot_w), 3), 'px;"><svg class="vital-svg" width="', trim(cnvtstring(v_plot_w), 3), '" height="58" viewBox="0 0 ', trim(cnvtstring(v_plot_w), 3), ' 58" preserveAspectRatio="none"><polyline class="vital-line temp-line" points="', v_temp_points, '"></polyline>', v_temp_marks, '</svg>'))
  if (v_temp_count = 0)
    set _memory_reply_string = concat(_memory_reply_string, '<div class="vital-no-data">No temperature data</div>')
  endif
  set _memory_reply_string = concat(_memory_reply_string, '</div>')

  set _memory_reply_string = concat(_memory_reply_string, '<div class="grid-cell label sticky-med always-on">Heart Rate / Pulse</div><div class="grid-cell label sticky-doses always-on vital-scale">180<br/>40</div><div class="grid-cell label sticky-dot always-on"></div>')
  set _memory_reply_string = concat(_memory_reply_string, concat('<div class="vital-plot" style="grid-column: 4 / span ', trim(cnvtstring(v_days), 3), '; width:', trim(cnvtstring(v_plot_w), 3), 'px;"><svg class="vital-svg" width="', trim(cnvtstring(v_plot_w), 3), '" height="58" viewBox="0 0 ', trim(cnvtstring(v_plot_w), 3), ' 58" preserveAspectRatio="none"><line class="vital-ref" x1="0" y1="32" x2="', trim(cnvtstring(v_plot_w), 3), '" y2="32"></line><polyline class="vital-line hr-line" points="', v_hr_points, '"></polyline>', v_hr_marks, '</svg>'))
  if (v_hr_count = 0)
    set _memory_reply_string = concat(_memory_reply_string, '<div class="vital-no-data">No heart rate data</div>')
  endif
  set _memory_reply_string = concat(_memory_reply_string, '</div>')

  set _memory_reply_string = concat(_memory_reply_string, '<div class="grid-cell label sticky-med always-on">Blood Pressure</div><div class="grid-cell label sticky-doses always-on vital-scale">200<br/>40</div><div class="grid-cell label sticky-dot always-on">Sys<br/>Dia</div>')
  set _memory_reply_string = concat(_memory_reply_string, concat('<div class="vital-plot" style="grid-column: 4 / span ', trim(cnvtstring(v_days), 3), '; width:', trim(cnvtstring(v_plot_w), 3), 'px;"><svg class="vital-svg" width="', trim(cnvtstring(v_plot_w), 3), '" height="58" viewBox="0 0 ', trim(cnvtstring(v_plot_w), 3), ' 58" preserveAspectRatio="none">', v_bp_poly, '<polyline class="vital-line sys-line" points="', v_sys_points, '"></polyline><polyline class="vital-line dia-line" points="', v_dia_points, '"></polyline>', v_sys_marks, v_dia_marks, '</svg>'))
  if (v_bp_count = 0)
    set _memory_reply_string = concat(_memory_reply_string, '<div class="vital-no-data">No blood pressure data</div>')
  endif
  set _memory_reply_string = concat(_memory_reply_string, '</div>')

  set _memory_reply_string = concat(_memory_reply_string, '<div class="grid-cell label sticky-med always-on">SpO2</div><div class="grid-cell label sticky-doses always-on vital-scale">100<br/>80</div><div class="grid-cell label sticky-dot always-on"></div>')
  set _memory_reply_string = concat(_memory_reply_string, concat('<div class="vital-plot" style="grid-column: 4 / span ', trim(cnvtstring(v_days), 3), '; width:', trim(cnvtstring(v_plot_w), 3), 'px;"><svg class="vital-svg" width="', trim(cnvtstring(v_plot_w), 3), '" height="58" viewBox="0 0 ', trim(cnvtstring(v_plot_w), 3), ' 58" preserveAspectRatio="none"><line class="vital-ref" x1="0" y1="20" x2="', trim(cnvtstring(v_plot_w), 3), '" y2="20"></line><polyline class="vital-line spo2-line" points="', v_spo2_points, '"></polyline>', v_spo2_marks, '</svg>'))
  if (v_spo2_count = 0)
    set _memory_reply_string = concat(_memory_reply_string, '<div class="vital-no-data">No SpO2 data</div>')
  endif
  set _memory_reply_string = concat(_memory_reply_string, '</div></div></div>')
endif

/* --- TABLE SECTION --- */
set _memory_reply_string = concat(_memory_reply_string, '<h2>Antimicrobial Order Details</h2>')
set _memory_reply_string = concat(_memory_reply_string, '<div style="width: 100%; overflow-x: auto; display: block;">')
set _memory_reply_string = concat(_memory_reply_string, '<table class="data-tbl"><colgroup>')
set _memory_reply_string = concat(_memory_reply_string, '<col style="width:200px"><col style="width:40px"><col style="width:40px">')
set _memory_reply_string = concat(_memory_reply_string, '<col style="width:100px"><col style="display:none;">')
set _memory_reply_string = concat(_memory_reply_string, '<col style="width:350px">')
set _memory_reply_string = concat(_memory_reply_string, '<col style="width:250px">')
set _memory_reply_string = concat(_memory_reply_string, '<col><col><col><col><col>')
set _memory_reply_string = concat(_memory_reply_string, '</colgroup>')
set _memory_reply_string = concat(_memory_reply_string, '<thead><tr>')
set _memory_reply_string = concat(_memory_reply_string, '<th>Medication</th><th style="text-align:center;">Doses</th><th class="has-help" style="text-align:center;" data-help="Order-level DOT: number of calendar days this individual order was administered. Overlapping orders for the same medication may each have DOT on the same day, so order DOT values may not sum to medication-level DOT.">DOT</th><th>Target Dose</th><th style="display:none;">Dose</th><th>Order Detail</th><th>Indication</th>')
set _memory_reply_string = concat(_memory_reply_string, '<th>Start Date</th><th>Latest Status</th><th>Status Date</th><th>Order ID</th><th>FIN</th>')
set _memory_reply_string = concat(_memory_reply_string, '</tr></thead>')
set _memory_reply_string = concat(_memory_reply_string, '<tbody>')

/* Output Table HTML Array */
set v_i = 1
while (v_i <= html_table->cnt)
  set _memory_reply_string = concat(_memory_reply_string, html_table->qual[v_i].text)
  set v_i = v_i + 1
endwhile

set _memory_reply_string = concat(_memory_reply_string, '</tbody></table></div>')

/* --- JAVASCRIPT INTERACTIVE UI ENGINE --- */
set _memory_reply_string = concat(_memory_reply_string, '<script>')
set _memory_reply_string = concat(_memory_reply_string, 'document.addEventListener("DOMContentLoaded", function() {')
set _memory_reply_string = concat(_memory_reply_string, '  const items = document.querySelectorAll(".dimmable");')
set _memory_reply_string = concat(_memory_reply_string, '  const triggers = document.querySelectorAll(".med-trigger");')
set _memory_reply_string = concat(_memory_reply_string, '  const routeToggle = document.getElementById("routeToggle");')
set _memory_reply_string = concat(_memory_reply_string, '  const chartWrap = document.querySelector(".chart-wrap");')
set _memory_reply_string = concat(_memory_reply_string, '  const vitalsWrap = document.querySelector(".vitals-wrap");')
set _memory_reply_string = concat(_memory_reply_string, '  const vitalGuide = document.getElementById("vitalGuide");')
set _memory_reply_string = concat(_memory_reply_string, '  const dayTargets = document.querySelectorAll("[data-day-idx]");')
set _memory_reply_string = concat(_memory_reply_string, '  const routeRoot = document.body;')
set _memory_reply_string = concat(_memory_reply_string, '  if (chartWrap && vitalsWrap) {')
set _memory_reply_string = concat(_memory_reply_string, '    chartWrap.addEventListener("scroll", function() { vitalsWrap.scrollLeft = chartWrap.scrollLeft; });')
set _memory_reply_string = concat(_memory_reply_string, '    vitalsWrap.addEventListener("scroll", function() { chartWrap.scrollLeft = vitalsWrap.scrollLeft; });')
set _memory_reply_string = concat(_memory_reply_string, '  }')
set _memory_reply_string = concat(_memory_reply_string, '  function showDayGuide(dayIdx) {')
set _memory_reply_string = concat(_memory_reply_string, '    if (!vitalGuide) return;')
set _memory_reply_string = concat(_memory_reply_string, '    var idx = parseInt(dayIdx, 10);')
set _memory_reply_string = concat(_memory_reply_string, '    if (isNaN(idx)) return;')
set _memory_reply_string = concat(_memory_reply_string, '    vitalGuide.style.left = ((idx * 14) + 287) + "px";')
set _memory_reply_string = concat(_memory_reply_string, '    vitalGuide.style.display = "block";')
set _memory_reply_string = concat(_memory_reply_string, '  }')
set _memory_reply_string = concat(_memory_reply_string, '  function hideDayGuide() { if (vitalGuide) vitalGuide.style.display = "none"; }')
set _memory_reply_string = concat(_memory_reply_string, '  dayTargets.forEach(function(el) {')
set _memory_reply_string = concat(_memory_reply_string, '    el.addEventListener("mouseenter", function() { showDayGuide(this.getAttribute("data-day-idx")); });')
set _memory_reply_string = concat(_memory_reply_string, '    el.addEventListener("mouseleave", hideDayGuide);')
set _memory_reply_string = concat(_memory_reply_string, '  });')
set _memory_reply_string = concat(_memory_reply_string, '  if (routeToggle && chartWrap) {')
set _memory_reply_string = concat(_memory_reply_string, '    routeToggle.addEventListener("click", function() {')
set _memory_reply_string = concat(_memory_reply_string, '      const routeMode = !routeRoot.classList.contains("route-mode");')
set _memory_reply_string = concat(_memory_reply_string, '      routeRoot.classList.toggle("route-mode", routeMode);')
set _memory_reply_string = concat(_memory_reply_string, '      routeToggle.classList.toggle("active", routeMode);')
set _memory_reply_string = concat(_memory_reply_string, '      routeToggle.setAttribute("aria-pressed", routeMode ? "true" : "false");')
set _memory_reply_string = concat(_memory_reply_string, '    });')
set _memory_reply_string = concat(_memory_reply_string, '  }')
set _memory_reply_string = concat(_memory_reply_string, '  triggers.forEach(function(trigger) {')
set _memory_reply_string = concat(_memory_reply_string, '    trigger.addEventListener("click", function() {')
set _memory_reply_string = concat(_memory_reply_string, '      const medName = this.getAttribute("data-med");')
set _memory_reply_string = concat(_memory_reply_string, '      const isCurrentlyActive = this.classList.contains("active-filter");')
set _memory_reply_string = concat(_memory_reply_string, '      triggers.forEach(function(t) { t.classList.remove("active-filter"); });')
set _memory_reply_string = concat(_memory_reply_string, '      if (isCurrentlyActive) {')
set _memory_reply_string = concat(_memory_reply_string, '        items.forEach(function(el) { el.classList.remove("dimmed"); });')
set _memory_reply_string = concat(_memory_reply_string, '      } else {')
set _memory_reply_string = concat(_memory_reply_string, '        this.classList.add("active-filter");')
set _memory_reply_string = concat(_memory_reply_string, '        items.forEach(function(el) {')
set _memory_reply_string = concat(_memory_reply_string, '          if (el.getAttribute("data-med") === medName || el.classList.contains("always-on")) {')
set _memory_reply_string = concat(_memory_reply_string, '            el.classList.remove("dimmed");')
set _memory_reply_string = concat(_memory_reply_string, '          } else {')
set _memory_reply_string = concat(_memory_reply_string, '            el.classList.add("dimmed");')
set _memory_reply_string = concat(_memory_reply_string, '          }')
set _memory_reply_string = concat(_memory_reply_string, '        });')
set _memory_reply_string = concat(_memory_reply_string, '      }')
set _memory_reply_string = concat(_memory_reply_string, '    });')
set _memory_reply_string = concat(_memory_reply_string, '  });')
set _memory_reply_string = concat(_memory_reply_string, '  items.forEach(function(item) {')
set _memory_reply_string = concat(_memory_reply_string, '    item.addEventListener("mouseenter", function() {')
set _memory_reply_string = concat(_memory_reply_string, '      var med = this.getAttribute("data-med");')
set _memory_reply_string = concat(_memory_reply_string, '      if (med) {')
set _memory_reply_string = concat(_memory_reply_string, ~      var siblings = document.querySelectorAll('.dimmable[data-med="' + med + '"]');~)
set _memory_reply_string = concat(_memory_reply_string, '        siblings.forEach(function(el) { el.classList.add("row-hover"); });')
set _memory_reply_string = concat(_memory_reply_string, '      }')
set _memory_reply_string = concat(_memory_reply_string, '    });')
set _memory_reply_string = concat(_memory_reply_string, '    item.addEventListener("mouseleave", function() {')
set _memory_reply_string = concat(_memory_reply_string, '      var med = this.getAttribute("data-med");')
set _memory_reply_string = concat(_memory_reply_string, '      if (med) {')
set _memory_reply_string = concat(_memory_reply_string, ~      var siblings = document.querySelectorAll('.dimmable[data-med="' + med + '"]');~)
set _memory_reply_string = concat(_memory_reply_string, '        siblings.forEach(function(el) { el.classList.remove("row-hover"); });')
set _memory_reply_string = concat(_memory_reply_string, '      }')
set _memory_reply_string = concat(_memory_reply_string, '    });')
set _memory_reply_string = concat(_memory_reply_string, '  });')
set _memory_reply_string = concat(_memory_reply_string, '});')
set _memory_reply_string = concat(_memory_reply_string, '</script>')

/* --- DEBUG PANEL --- */
set _memory_reply_string = concat(_memory_reply_string, '<details id="debug-panel" style="margin-top:24px;padding:10px 14px;border:1px solid #f0a000;background:#fffbe6;color:#333;font-size:11px;font-family:monospace;">')
set _memory_reply_string = concat(_memory_reply_string, '<summary style="cursor:pointer;font-size:12px;font-weight:bold;user-select:none;">&#9888; DEBUG INFO</summary><div style="margin-top:8px;">')
set _memory_reply_string = concat(_memory_reply_string, concat('Patient ID: ', trim(cnvtstring($PAT_PersonId), 3), ' &nbsp;|&nbsp; Lookback: ', trim(cnvtstring($LOOKBACK), 3), ' days<br/>'))
set _memory_reply_string = concat(_memory_reply_string, concat('Admission: ', v_admit_dt, ' &nbsp;|&nbsp; LOS: ', v_los, ' days<br/>'))
set _memory_reply_string = concat(_memory_reply_string, concat('Query window: ', v_begin_dt_str, ' to ', v_end_dt_str, '<br/>'))
set _memory_reply_string = concat(_memory_reply_string, concat('Total admin_rec: ', trim(cnvtstring(admin_rec->cnt), 3), ' (PC: ', trim(cnvtstring(v_pc_cnt), 3), ', SN: ', trim(cnvtstring(v_sn_cnt), 3), ')<br/>'))
set _memory_reply_string = concat(_memory_reply_string, '<hr style="border:0;border-top:1px solid #e0c060;margin:4px 0;"/>')
set _memory_reply_string = concat(_memory_reply_string, concat('v_min_dt:   ', format(v_min_dt,"DD-MMM-YYYY HH:MM:SS;;D"), ' (raw: ', cnvtstring(v_min_dt), ')<br/>'))
set _memory_reply_string = concat(_memory_reply_string, concat('v_max_dt:   ', format(v_max_dt,"DD-MMM-YYYY HH:MM:SS;;D"), ' (raw: ', cnvtstring(v_max_dt), ')<br/>'))
set _memory_reply_string = concat(_memory_reply_string, concat('v_today:    ', format(v_today,"DD-MMM-YYYY HH:MM:SS;;D"), ' (raw: ', cnvtstring(v_today), ')<br/>'))
set _memory_reply_string = concat(_memory_reply_string, concat('v_min_date: ', format(v_min_date,"DD-MMM-YYYY;;D"), ' (raw i4: ', cnvtstring(v_min_date), ')<br/>'))
set _memory_reply_string = concat(_memory_reply_string, concat('Chart range: ', format(v_min_dt,"DD-MMM-YYYY;;D"), ' to ', format(v_max_dt,"DD-MMM-YYYY;;D"), ' (', trim(cnvtstring(v_days), 3), ' days) | Grand DOT: ', trim(cnvtstring(v_grand_total_dot),3), '<br/>'))
set _memory_reply_string = concat(_memory_reply_string, concat('Vitals plotted days: ', trim(cnvtstring(v_vitals_count), 3), ' (Temp: ', trim(cnvtstring(v_temp_count), 3), ', HR: ', trim(cnvtstring(v_hr_count), 3), ', BP: ', trim(cnvtstring(v_bp_count), 3), ', SpO2: ', trim(cnvtstring(v_spo2_count), 3), ')<br/>'))
set _memory_reply_string = concat(_memory_reply_string, '<hr style="border:0;border-top:1px solid #e0c060;margin:4px 0;"/>')
set _memory_reply_string = concat(_memory_reply_string, '<b>Unique admin day keys (chart lookup keys):</b><br/>')
set _memory_reply_string = concat(_memory_reply_string, concat(v_all_days_list, '<br/>'))
set _memory_reply_string = concat(_memory_reply_string, '<hr style="border:0;border-top:1px solid #e0c060;margin:4px 0;"/>')
set _memory_reply_string = concat(_memory_reply_string, '<b>Admin timestamps (first 8 + last):</b><br/>')
set _memory_reply_string = concat(_memory_reply_string, v_debug_admins)
set _memory_reply_string = concat(_memory_reply_string, '<hr style="border:0;border-top:1px solid #e0c060;margin:4px 0;"/>')
set _memory_reply_string = concat(_memory_reply_string, '<b>Per-medication (chart):</b><br/>')
set _memory_reply_string = concat(_memory_reply_string, v_debug_meds)
set _memory_reply_string = concat(_memory_reply_string, '<hr style="border:0;border-top:1px solid #e0c060;margin:4px 0;"/>')
set _memory_reply_string = concat(_memory_reply_string, '<b>Actual emitted MPage display:</b><br/>')
set _memory_reply_string = concat(_memory_reply_string, concat('Date range header: ', format(v_min_dt,"DD-MMM-YYYY;;D"), ' to ', format(v_max_dt,"DD-MMM-YYYY;;D"), ' (', trim(cnvtstring(v_days), 3), ' days)<br/>'))
set _memory_reply_string = concat(_memory_reply_string, concat('Today highlight column: ', format(curdate,"YYYYMMDD;;D"), '<br/>'))
set _memory_reply_string = concat(_memory_reply_string, 'Chart rows emitted from html_chart buffers (. = empty, number = admin square dose count, Y = summary admin day, * = today column):<br/>')
set _memory_reply_string = concat(_memory_reply_string, v_debug_display)
set _memory_reply_string = concat(_memory_reply_string, '<br/><b>Actual emitted table rows:</b><br/>')
set _memory_reply_string = concat(_memory_reply_string, v_debug_table)
set _memory_reply_string = concat(_memory_reply_string, '<hr style="border:0;border-top:1px solid #e0c060;margin:4px 0;"/>')
set _memory_reply_string = concat(_memory_reply_string, concat('html_chart rows: ', trim(cnvtstring(html_chart->cnt), 3), ' | html_table rows: ', trim(cnvtstring(html_table->cnt), 3), '<br/>'))
set _memory_reply_string = concat(_memory_reply_string, '</div></details>')

/* --- FOOTER --- */
set _memory_reply_string = concat(_memory_reply_string, build2('<div style="margin-top:24px;padding-top:8px;border-top:1px solid var(--border-dark);color:#666;font-size:12px;">Generated on ', format(cnvtdatetime(curdate, curtime), "YYYY-MM-DD HH:MM:SS;;D"), '.</div></div></body></html>'))

end
go
