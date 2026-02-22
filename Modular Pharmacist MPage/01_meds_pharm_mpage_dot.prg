drop program 01_meds_pharm_mpage_dot go
create program 01_meds_pharm_mpage_dot

%i cust_script:01_meds_pharm_mpage_struct

/* ====================================================================
 * ANTIMICROBIAL DOT - Variable Declarations
 * ==================================================================== */
declare v_min_dt      = dq8 with noconstant(0), protect
declare v_max_dt      = dq8 with noconstant(0), protect
declare v_first       = i2  with noconstant(1), protect
declare v_days        = i4  with noconstant(0), protect
declare v_curr_med    = vc  with noconstant(""), protect
declare v_dates_kv    = vc  with noconstant(""), maxlen=65534, protect
declare v_details_kv  = vc  with noconstant(""), maxlen=65534, protect
declare v_cnt_day     = i4  with noconstant(0), protect
declare v_i           = i4  with noconstant(0), protect
declare v_key8        = vc  with noconstant(""), protect
declare v_count_str   = vc  with noconstant(""), protect
declare v_count_i     = i4  with noconstant(0), protect
declare v_title       = vc  with noconstant(""), maxlen=1000, protect
declare v_strip       = vc  with noconstant(""), maxlen=65534, protect
declare v_med_dot_total = i4 with noconstant(0), protect
declare v_row_cnt     = i4  with noconstant(0), protect
declare v_all_days_list = vc with noconstant(""), maxlen=65534, protect
declare v_sum_strip     = vc with noconstant(""), maxlen=65534, protect
declare v_spacer_strip  = vc with noconstant(""), maxlen=65534, protect
declare v_findpos       = i4 with noconstant(0), protect
declare v_after         = vc with noconstant(""), maxlen=65534, protect
declare v_endpos        = i4 with noconstant(0), protect
declare v_detail_str    = vc with noconstant(""), protect
declare v_pipe_pos      = i4 with noconstant(0), protect
declare v_indication    = vc with noconstant(""), maxlen=255, protect
declare v_discontinue_rsn = vc with noconstant(""), maxlen=255, protect
declare v_drug        = vc with noconstant(""), protect
declare v_dose        = f8 with noconstant(0.0), protect
declare v_unit        = vc with noconstant(""), protect
declare v_ind         = vc with noconstant(""), protect
declare v_start       = vc with noconstant(""), protect
declare v_stat        = vc with noconstant(""), protect
declare v_sdt         = vc with noconstant(""), protect
declare v_oid         = vc with noconstant(""), protect
declare v_dot         = i4 with noconstant(0), protect
declare v_today       = dq8 with noconstant(0), protect

/* ====================================================================
 * PASS 1: Determine Date Range for Chart Axis
 * ==================================================================== */
select into "nl:"
  day_dt = cnvtdate(ce.performed_dt_tm)
from
  clinical_event ce, med_admin_event m, orders o, ce_event_order_link cl,
  code_value_event_r cr, order_catalog oc, order_catalog_synonym ocs, order_entry_format oe
plan ce where ce.person_id = mpage_data->req_info.patient_id
  and ce.performed_dt_tm between cnvtdatetime(curdate-mpage_data->req_info.lookback_days,0) and cnvtdatetime(curdate,235959)
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
  v_today = cnvtdate(curdate)
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
  set mpage_data->dot.axis_html = ""
  set mpage_data->dot.chart_rows = '<tr><td colspan="3">No administrations found in the selected window.</td></tr>'
  set mpage_data->dot.header_html = ""
else
  set v_days = (datetimediff(v_max_dt, v_min_dt, 7)) + 1
  set mpage_data->dot.axis_html = concat('<div class="axisbar"><div>Date range: ', format(v_min_dt,"DD-MMM-YYYY;;D"), ' to ', format(v_max_dt,"DD-MMM-YYYY;;D"), '</div></div>')
  set mpage_data->dot.header_html = ''
  set v_i = 0
  while (v_i < v_days)
    if (v_i = 0 or format(v_min_dt + v_i,"MM;;D") != format(v_min_dt + v_i - 1,"MM;;D"))
      set mpage_data->dot.header_html = concat(mpage_data->dot.header_html, '<span class="tick" title="', format(v_min_dt + v_i,"YYYY-MM-DD;;D"), '"><span class="mo">', format(v_min_dt + v_i,"MMM;;D"), '</span>', format(v_min_dt + v_i,"DD;;D"), '</span>')
    else
      set mpage_data->dot.header_html = concat(mpage_data->dot.header_html, '<span class="tick" title="', format(v_min_dt + v_i,"YYYY-MM-DD;;D"), '">', format(v_min_dt + v_i,"DD;;D"), '</span>')
    endif
    set v_i = v_i + 1
  endwhile
endif

/* ====================================================================
 * PASS 2: Build Chart Rows (per Medication)
 * ==================================================================== */
select into "nl:"
  oc.primary_mnemonic
, m.event_id
, mdy = format(ce.performed_dt_tm, "YYYYMMDD;;D")
, indication = substring(1,60,trim(od_indication.oe_field_display_value))
, discontinue_reason = substring(1,60,trim(od_dcreason.oe_field_display_value))
from
  clinical_event ce, med_admin_event m, orders o,
  ce_event_order_link cl, code_value_event_r cr, order_catalog oc,
  order_catalog_synonym ocs, order_entry_format oe,
  order_detail od_indication, order_detail od_dcreason
plan ce where ce.person_id = mpage_data->req_info.patient_id
  and ce.performed_dt_tm between cnvtdatetime(curdate-mpage_data->req_info.lookback_days,0) and cnvtdatetime(curdate,235959)
join m where m.event_id = ce.event_id
  and m.event_type_cd = value(uar_get_code_by("MEANING",4000040,"TASKCOMPLETE"))
join o where o.order_id = m.template_order_id
join cl where cl.event_id = ce.event_id
join cr where cr.event_cd = ce.event_cd
join oc where oc.catalog_cd = cr.parent_cd and oc.catalog_type_cd = 2516
join ocs where ocs.catalog_cd = oc.catalog_cd
join oe where oe.oe_format_id = ocs.oe_format_id and oe.oe_format_id in (14497910, 14498121)
join od_indication where od_indication.order_id = outerjoin(o.order_id) and od_indication.oe_field_meaning = outerjoin("INDICATION")
join od_dcreason where od_dcreason.order_id = outerjoin(o.order_id) and od_dcreason.oe_field_meaning = outerjoin("DCREASON")
order by cnvtupper(oc.primary_mnemonic), mdy, m.event_id

head report
  v_curr_med = ""
  v_dates_kv = ""
  v_details_kv = ""
  v_all_days_list = "" 
  v_row_cnt = 0
  mpage_data->dot.chart_rows = ""

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
        else v_count_str = v_after endif
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
        else v_detail_str = v_after endif
        v_pipe_pos = findstring("|", v_detail_str)
        if (v_pipe_pos > 0)
          v_indication = substring(1, v_pipe_pos - 1, v_detail_str)
          v_discontinue_rsn = substring(v_pipe_pos + 1, textlen(v_detail_str) - v_pipe_pos, v_detail_str)
        else
          v_indication = v_detail_str
        endif
      endif

      if (v_count_i > 0)
        v_title = concat(v_curr_med, " - ", format(v_min_dt + v_i,"DD/MM/YYYY;;D"), " / ", v_count_str, if(v_count_i = 1) " admin" else " admins" endif, "&#10;Indication: ", v_indication, "&#10;Discontinue Reason: ", v_discontinue_rsn)
        v_strip = concat(v_strip, '<span class="cell on" title="', v_title, '">', trim(v_count_str), '</span>')
      else
        v_strip = concat(v_strip, '<span class="cell" title="', format(v_min_dt + v_i,"DD/MM/YYYY;;D"), '"></span>')
      endif
      v_i = v_i + 1
    endwhile
    
    mpage_data->dot.chart_rows = concat(mpage_data->dot.chart_rows, '<tr', if(mod(v_row_cnt, 2) = 0) ' class="even"' else '' endif, '><td class="label medname sticky-med">', v_curr_med, '</td><td class="label dot-val sticky-dot"><span class="pill" title="', v_curr_med, ' - Total Days of Therapy: ', trim(cnvtstring(v_med_dot_total)), '">', cnvtstring(v_med_dot_total), '</span></td><td><div class="strip">', v_strip, '</div></td></tr>')
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
      mpage_data->dot.chart_rows = concat(mpage_data->dot.chart_rows, '<tr class="summary-row"><td class="label sticky-med">Antimicrobial Summary</td><td class="label sticky-dot"></td><td><div class="strip">', v_sum_strip, '</div></td></tr>')
  endif
with nocounter

/* ====================================================================
 * PASS 3: Build Table Rows (per Order)
 * ==================================================================== */
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
  clinical_event ce, med_admin_event m, orders o, order_ingredient oi,
  ce_event_order_link cl, code_value_event_r cr, order_catalog oc,
  order_catalog_synonym ocs, order_entry_format oe, order_detail od_indication
plan ce where ce.person_id = mpage_data->req_info.patient_id
  and ce.performed_dt_tm between cnvtdatetime(curdate-mpage_data->req_info.lookback_days,0) and cnvtdatetime(curdate,235959)
join m where m.event_id = ce.event_id
  and m.event_type_cd = value(uar_get_code_by("MEANING",4000040,"TASKCOMPLETE"))
join o where o.order_id = m.template_order_id
join oi where oi.order_id = o.order_id
join cl where cl.event_id = ce.event_id
join cr where cr.event_cd = ce.event_cd
join oc where oc.catalog_cd = cr.parent_cd and oc.catalog_type_cd = 2516
join ocs where ocs.catalog_cd = oc.catalog_cd
join oe where oe.oe_format_id = ocs.oe_format_id and oe.oe_format_id in (14497910, 14498121)
join od_indication where od_indication.order_id = outerjoin(o.order_id) and od_indication.oe_field_meaning_id = outerjoin(15)
order by o.order_id, cnvtupper(oc.primary_mnemonic), day_key

head report
  mpage_data->dot.table_rows = ""
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
  
  mpage_data->dot.table_rows = concat(mpage_data->dot.table_rows, '<tr', if(mod(v_row_cnt, 2) = 0) ' class="even"' else '' endif, '><td>', v_drug, '</td><td class="dot-val"><span class="pill">', cnvtstring(v_dot), '</span></td><td>', trim(format(v_dose,"########.##")), ' ', v_unit, '</td><td>', v_ind, '</td><td>', v_start, '</td><td>', v_stat, '</td><td>', v_sdt, '</td><td>', v_oid, '</td></tr>')
with nocounter

if (textlen(mpage_data->dot.table_rows) = 0)
  set mpage_data->dot.table_rows = '<tr><td colspan="8">No antimicrobial orders found in the selected window.</td></tr>'
endif

end
go