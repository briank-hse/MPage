drop program 01_meds_dot_date_comb_edge3:Group1 go
create program 01_meds_dot_date_comb_edge3:Group1

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
declare v_row_cnt     = i4 with noconstant(0)
declare v_med_attr    = vc with noconstant("")
declare v_all_days_list = vc with noconstant(""), maxlen=65534
declare v_grand_total_dot   = i4 with noconstant(0)
declare v_cell_bg         = vc with noconstant("")
declare v_indication       = vc with noconstant(""), maxlen=255
declare v_discontinue_rsn  = vc with noconstant(""), maxlen=255
declare v_low_dt      = dq8 with noconstant(null)
declare v_high_now_dt = dq8 with noconstant(null)
declare v_today       = dq8 with noconstant(0)

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

declare v_begin_dt_str = vc with noconstant("")
declare v_end_dt_str   = vc with noconstant("")
declare v_sum_strip    = vc with noconstant(""), maxlen=65534
declare v_spacer_strip = vc with noconstant(""), maxlen=65534

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


/* ========================================================================== */
/* PASS 0A & 0B: DATA GATHERING                                               */
/* ========================================================================== */
select into "nl:"
from clinical_event ce, med_admin_event m, orders o, code_value_event_r cr, order_catalog oc, order_catalog_synonym ocs, order_entry_format oe
plan ce where ce.person_id = $PAT_PersonId and ce.performed_dt_tm between cnvtdatetime(curdate-$LOOKBACK,0) and cnvtdatetime(curdate,235959)
join m where m.event_id = ce.event_id and m.event_type_cd = value(uar_get_code_by("MEANING",4000040,"TASKCOMPLETE"))
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
join smai where smai.sa_medication_admin_id = sma.sa_medication_admin_id and smai.active_ind = 1 and smai.admin_start_dt_tm >= cnvtdatetimeutc(cnvtdatetime(curdate-$LOOKBACK,0))
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
  v_today = cnvtdate(curdate)
  v_los = cnvtstring((datetimediff(v_high_now_dt,v_low_dt,7))+1)
  v_lookback = cnvtstring($LOOKBACK)
  v_begin_dt_str = format((curdate-$LOOKBACK),"DD/MM/YYYY;;d")
  v_end_dt_str = format(curdate,"DD/MM/YYYY;;d")
with nocounter

if (admin_rec->cnt > 0)
  set v_first = 0
  set v_min_dt = cnvtdate(admin_rec->qual[1].admin_dt_tm)
  set v_max_dt = cnvtdate(admin_rec->qual[1].admin_dt_tm)
  set v_i = 1
  while (v_i <= admin_rec->cnt)
    if (cnvtdate(admin_rec->qual[v_i].admin_dt_tm) < v_min_dt) set v_min_dt = cnvtdate(admin_rec->qual[v_i].admin_dt_tm) endif
    if (cnvtdate(admin_rec->qual[v_i].admin_dt_tm) > v_max_dt) set v_max_dt = cnvtdate(admin_rec->qual[v_i].admin_dt_tm) endif
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
  set v_days = (datetimediff(v_max_dt, v_min_dt, 7)) + 1
  set v_axis_html = concat(' <span style="font-weight:normal; font-size:11px; color:#555;">(Date range: ', format(v_min_dt,"DD-MMM-YYYY;;D"), ' to ', format(v_max_dt,"DD-MMM-YYYY;;D"), ')</span>')
  set v_header_html = ''
  set v_i = 0
  while (v_i < v_days)
    if (v_i = 0 or format(v_min_dt + v_i,"MM;;D") != format(v_min_dt + v_i - 1,"MM;;D"))
      set v_header_html = concat(v_header_html, '<div class="grid-cell tick" title="', format(v_min_dt + v_i,"YYYY-MM-DD;;D"), '"><span class="mo">', format(v_min_dt + v_i,"MMM;;D"), '</span>', format(v_min_dt + v_i,"DD;;D"), '</div>')
    else
      set v_header_html = concat(v_header_html, '<div class="grid-cell tick" title="', format(v_min_dt + v_i,"YYYY-MM-DD;;D"), '">', format(v_min_dt + v_i,"DD;;D"), '</div>')
    endif
    set v_i = v_i + 1
  endwhile
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
, src_id = admin_rec->qual[d.seq].admin_id
, admin_src = admin_rec->qual[d.seq].src
from (dummyt d with seq = admin_rec->cnt), orders o, order_catalog oc, order_detail od_indication, order_detail od_dcreason
plan d join o where o.order_id = admin_rec->qual[d.seq].order_id
join oc where oc.catalog_cd = o.catalog_cd
join od_indication where od_indication.order_id = outerjoin(o.order_id) and od_indication.oe_field_meaning = outerjoin("INDICATION")
join od_dcreason where od_dcreason.order_id = outerjoin(o.order_id) and od_dcreason.oe_field_meaning = outerjoin("DCREASON")
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
    v_cell_bg = if(mod(v_row_cnt, 2) = 0) ' even-cell' else '' endif
    v_med_attr = concat(' data-med="', v_curr_med, '"')

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
        v_strip = concat(v_strip, '<div class="grid-cell cell on dimmable', v_cell_bg, '"', v_med_attr, ' title="', v_title, '">', trim(v_count_str), '</div>')
      else
        v_strip = concat(v_strip, '<div class="grid-cell cell dimmable', v_cell_bg, '"', v_med_attr, ' title="', format(v_min_dt + v_i,"DD/MM/YYYY;;D"), '"></div>')
      endif
      v_i = v_i + 1
    endwhile

    /* APPEND TO RECORD ARRAY */
    html_chart->cnt = html_chart->cnt + 1
    stat = alterlist(html_chart->qual, html_chart->cnt)
    html_chart->qual[html_chart->cnt].text = concat(
      '<div class="grid-cell label medname sticky-med med-trigger dimmable', v_cell_bg, '"', v_med_attr, ' title="Click to filter by ', v_curr_med, '">', v_curr_med, ' <span class="filter-icon">&#x25BC;</span></div>',
      '<div class="grid-cell dot-val sticky-doses dimmable', v_cell_bg, '"', v_med_attr, '><span class="pill" title="', v_curr_med, ' - Total Doses: ', trim(cnvtstring(v_med_dose_total), 3), '">', trim(cnvtstring(v_med_dose_total), 3), '</span></div>',
      '<div class="grid-cell dot-val sticky-dot dimmable', v_cell_bg, '"', v_med_attr, '><span class="pill" title="', v_curr_med, ' - Total Days of Therapy: ', trim(cnvtstring(v_med_dot_total), 3), '">', trim(cnvtstring(v_med_dot_total), 3), '</span></div>',
      v_strip
    )
  endif

foot report
  if (v_days > 0)
      v_sum_strip = ""
      v_spacer_strip = ""
      v_i = 0
      while (v_i < v_days)
          v_key8 = format(v_min_dt + v_i, "YYYYMMDD;;D")
          if (findstring(concat("~", v_key8, "~"), v_all_days_list) > 0)
             v_sum_strip = concat(v_sum_strip, '<div class="grid-cell cell sum-yes sum-border" title="Antimicrobial Administered"></div>')
          else
              v_sum_strip = concat(v_sum_strip, '<div class="grid-cell cell sum-no sum-border" title="No Antimicrobials"></div>')
          endif
          v_i = v_i + 1
      endwhile

      /* APPEND SUMMARY TO RECORD ARRAY */
      html_chart->cnt = html_chart->cnt + 1
      stat = alterlist(html_chart->qual, html_chart->cnt)
      html_chart->qual[html_chart->cnt].text = concat(
          '<div class="grid-cell label sticky-med sum-border always-on">Antimicrobial Summary</div>',
          '<div class="grid-cell label sticky-doses sum-border always-on"></div>',
          '<div class="grid-cell label dot-val sticky-dot sum-border always-on"><span class="pill" title="Total Summary Days of Therapy: ', trim(cnvtstring(v_grand_total_dot), 3), '">', trim(cnvtstring(v_grand_total_dot), 3), '</span></div>',
          v_sum_strip
      )
  endif
with nocounter
endif

/* ========================================================================== */
/* PASS 2.5: ENCOUNTER TRACKS (Appended to Array)                             */
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
        if (track_ends[v_t] <= v_s_idx)
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
                 if (v_i = enc_rec->qual[v_e].start_idx) set v_cell_text = "A" endif
              else
                 set v_cell_title = concat(v_cell_title, " | Arrive: Unknown")
              endif

              if (enc_rec->qual[v_e].disch_dt = null or enc_rec->qual[v_e].disch_dt = 0)
                set v_cell_title = concat(v_cell_title, " | Active")
              else
                set v_cell_title = concat(v_cell_title, " | DC: ", format(enc_rec->qual[v_e].disch_dt, "DD/MM/YYYY;;d"))
                if (v_i = enc_rec->qual[v_e].end_idx)
                   if (v_cell_text = "A") set v_cell_text = "A/D" else set v_cell_text = "D" endif
                endif
              endif
            endif
          endif
        endfor
        set v_strip = concat(v_strip, '<div class="grid-cell cell enc-border ', v_cell_class, '" title="', v_cell_title, '"><span class="enc-cell-text">', v_cell_text, '</span></div>')
        set v_i = v_i + 1
      endwhile

      /* APPEND ENCOUNTER TRACK TO RECORD ARRAY */
      set html_chart->cnt = html_chart->cnt + 1
      set stat = alterlist(html_chart->qual, html_chart->cnt)
      set html_chart->qual[html_chart->cnt].text = concat(
        '<div class="grid-cell label enc-label-cell sticky-med enc-border always-on">', v_enc_label, '</div>',
        '<div class="grid-cell sticky-doses enc-border always-on"></div>',
        '<div class="grid-cell sticky-dot enc-border always-on"></div>',
        v_strip
      )
    endfor
  endif
endif

/* ========================================================================== */
/* PASS 3: BUILD TABLE ROWS (Appended to Array)                               */
/* ========================================================================== */
set html_table->cnt = 0
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
, strength_val = substring(1,60,trim(od_strength.oe_field_display_value))
, strength_unit  = substring(1,60,trim(od_strengthunit.oe_field_display_value))
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
order by o.order_id, cnvtupper(trim(oc.primary_mnemonic)), day_key

head report
  v_row_cnt = 0

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

head day_key
  v_dot = v_dot + 1

detail
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
      "<td>", v_disp, "</td>",
      "<td>", v_ind, "</td>",
      "<td>", v_start, "</td>",
      "<td>", v_stat, "</td>",
      "<td>", v_sdt, "</td>",
      "<td>", v_oid, "</td>",
      build2(~<td><a href="javascript:APPLINK(0,'Powerchart.exe','/PERSONID=~, trim(cnvtstring($PAT_PersonId, 20, 0), 3), ~ /ENCNTRID=~, v_encntr_id, ~')">~, v_fin, ~</a></td>~),
    "</tr>"
  )
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
select into $outdev
from dummyt d
head report
  row +1 '<!doctype html><html lang="en"><head>'
  row +1 '<meta charset="utf-8" /><meta name="viewport" content="width=device-width, initial-scale=1" />'
  row +1 '<meta name="discern" content="CCLLINK,APPLINK"/>'
  row +1 '<title>Antimicrobial Days of Therapy - By Date</title>'
  row +1 '<style>'
  row +1 ':root{--bg-main:#fff;--bg-alt:#f5f5f5;--border-color:#d6d9dd;--border-dark:#b5b5b5;--cerner-blue:#0086CE;'
  row +1 '--header-bg:rgba(231, 234, 238, 0.85);--sticky-bg:#ffffff;--sticky-bg-alt:#f5f5f5;}'
  row +1 '*,*:before,*:after{box-sizing:border-box}'
  row +1 call print(concat('body{margin:0;font:', v_font_size, '/1.4 -apple-system,BlinkMacSystemFont,Segoe UI,Roboto,Arial,sans-serif;color:#111;background:var(--bg-main);padding:0;}'))
  row +1 '.wrap{width:100%; max-width:100%; margin:0; padding:0; box-sizing:border-box;}'
  row +1 'h1{font-size:18px;margin:0 0 8px;}'
  row +1 'h2{font-size:15px;margin:16px 0 8px;padding-top:0;}'
  row +1 '.sub{color:#444;margin:4px 0 16px;}'
  row +1 '.meta-flex { display: flex; flex-wrap: wrap; gap: 16px; align-items: center; }'
  row +1 '.legend{margin-top:6px;color:#555;font-size:12px}'

  /* CSS GRID ARCHITECTURE */
  row +1 '.chart-wrap { overflow-x:auto; overflow-y:hidden; margin-bottom:12px; width:100%; display:block; }'
  row +1 '.chart-grid { display: grid; background: var(--bg-main); width: max-content; border-top: 1px solid var(--border-dark); border-left: 1px solid var(--border-dark); font-size: 12px; }'
  row +1 '.grid-cell { border-right: 1px solid var(--border-dark); border-bottom: 1px solid var(--border-dark); background: var(--bg-main); padding: 0; display: flex; align-items: center; min-width: 0; }'
  row +1 'table.data-tbl th, .grid-cell.label { background: var(--header-bg) !important; color: #2f3c4b; font-weight: 600 !important; padding: 4px 8px; }'
  row +1 'table.data-tbl th { text-align:left; height:26px; font-size:12px !important; }'
  row +1 '.grid-cell.label { min-height: 26px; }'

  /* Fixed 180/40/40 sticky sizing logic */
  row +1 '.sticky-med { position:sticky; left:0; z-index:10; background:var(--sticky-bg); overflow:hidden; white-space:nowrap; text-overflow:ellipsis; width:180px; min-width:180px; max-width:180px; }'
  row +1 '.sticky-doses { position:sticky; left:180px; z-index:10; background:var(--sticky-bg); width:40px; min-width:40px; max-width:40px; text-align:center; }'
  row +1 '.sticky-dot { position:sticky; left:220px; z-index:10; background:var(--sticky-bg); box-shadow: 2px 0 5px -2px rgba(0,0,0,0.2); width:40px; min-width:40px; max-width:40px; text-align:center; }'
  row +1 '.hdr-intersect { z-index:20 !important; }'
  
  /* Content Alignment & Striping */
  row +1 '.even-cell { background: var(--bg-alt) !important; }'
  row +1 '.even-cell.sticky-med, .even-cell.sticky-doses, .even-cell.sticky-dot { background: var(--sticky-bg-alt) !important; }'
  row +1 '.dot-val { justify-content: center; }'
  row +1 call print(concat('.grid-cell.medname { padding:2px 6px; font-size:', v_med_font_size, ' !important; }'))
  
  /* EDGE 5 Interactive UI Classes */
  row +1 '.med-trigger { cursor: pointer; color: var(--cerner-blue); transition: background 0.2s; }'
  row +1 '.med-trigger:hover { background-color: #e0f0ff !important; }'
  row +1 '.filter-icon { font-size: 8px; opacity: 0.5; margin-left: 6px; }'
  row +1 '.dimmed { opacity: 0.15; filter: grayscale(100%); pointer-events: none; transition: opacity 0.3s ease; }'
  row +1 '.dimmable { transition: opacity 0.3s ease; }'
  row +1 '.active-filter { background-color: #e0f0ff !important; font-weight: 700; }'
  
  /* Physical 14px width constraint and Date Ticks */
  row +1 '.cell, .tick { width:14px; min-width:14px; max-width:14px; justify-content:center; font-size:10px; }'
  row +1 '.cell { color:transparent; }'
  row +1 '.tick { height:30px; position:relative; overflow:visible !important; align-items:flex-end; padding-bottom:2px; }'
  row +1 '.tick .mo { position:absolute; bottom:16px; left:50%; transform:translateX(-50%); color:#555; white-space:nowrap; pointer-events:none; }'
  row +1 '.grid-cell.axis-header { display:block; line-height:18px; overflow:hidden; white-space:nowrap; text-overflow:ellipsis; }'

  row +1 '.cell.on { background:transparent !important; color:var(--bg-main) !important; font-weight:600; position:relative; z-index:1; }'
  row +1 '.cell.on::after { content:""; position:absolute; top:50%; left:50%; transform:translate(-50%, -50%); width:14px; height:14px; background:var(--cerner-blue); border-radius:1px; z-index:-1; }'
  row +1 '.cell.on:empty::before { content:"1"; }'
  row +1 '.cell.sum-yes { background:#ED1C24 !important; }'
  row +1 '.cell.sum-no { background:#A8D08D !important; }'
  row +1 '.sum-border { border-top:2px solid #a0a0a0 !important; }'
  row +1 '.pill { display:inline-block; padding:2px 6px; border-radius:12px; background:#eef; color:#334; line-height:1; }'
  
  /* Encounter Formatting */
  row +1 '.cell.enc-c1 { background:#e0f0ff !important; }'
  row +1 '.cell.enc-c2 { background:#d1e8ff !important; }'
  row +1 '.cell.enc-c3 { background:#e8f4fd !important; }'
  row +1 '.cell.enc-c4 { background:#d9f0fa !important; }'
  row +1 '.enc-border { border-top:1px solid #c8dff5 !important; }'
  row +1 '.enc-label-cell { font-size:11px !important; }'
  row +1 '.enc-label-cell a { color:var(--cerner-blue); text-decoration:none; font-weight:600; }'
  row +1 '.enc-cell-text { font-size:8px; font-weight:700; color:#111; line-height:1; }'
  
  /* Table Layout Rules */
  row +1 'table.data-tbl { width:100%; min-width:1000px; border-collapse:separate; border-spacing:0; margin-top:12px; font-size:12px; border-top:1px solid var(--border-dark); border-left:1px solid var(--border-dark); border-bottom:2px solid #a0a0a0; table-layout:fixed; }'
  row +1 'table.data-tbl th, table.data-tbl td { border-right:1px solid var(--border-dark); border-bottom:1px solid var(--border-dark); padding:4px 6px; text-align:left; background:var(--bg-main); word-break:break-word; overflow-wrap:break-word; overflow:hidden; transition: background-color 0.2s; }'
  row +1 'table.data-tbl th:nth-child(1), table.data-tbl td:nth-child(1) { box-sizing:border-box !important; width:180px; min-width:180px; max-width:180px; }'
  row +1 'table.data-tbl th:nth-child(2), table.data-tbl td:nth-child(2) { box-sizing:border-box !important; width:40px; min-width:40px; max-width:40px; text-align:center; padding:4px 0; }'
  row +1 'table.data-tbl th:nth-child(3), table.data-tbl td:nth-child(3) { box-sizing:border-box !important; width:40px; min-width:40px; max-width:40px; text-align:center; padding:4px 0; }'
  row +1 'table.data-tbl tr.even td { background:var(--bg-alt); }'
  row +1 'table.data-tbl tbody tr:last-child td { border-bottom:none; }'
  row +1 'table.data-tbl tbody tr:hover td { background-color: #f0f7ff; cursor: default; }'

  row +1 '</style></head><body><div class="wrap">'

  /* --- CHART SECTION --- */
  row +1 '<h1>Antimicrobial Administrations by Date</h1>'
  row +1 '<div class="legend">Each blue square marks a <b>day</b> where the medication has been administered. A number indicates the count of administrations for that day.<br><b>Summary:</b> Red = Antimicrobial given, Green = No antimicrobial given.<br/><b>Interactive:</b> Click a medication name to isolate its history across the chart and table.</div>'

  row +1 '<div class="chart-wrap">'
  row +1 call print(concat('<div class="chart-grid" style="grid-template-columns: 180px 40px 40px repeat(', trim(cnvtstring(v_days), 3), ', 20px);">'))
  row +1 call print(concat('<div class="grid-cell label sticky-med hdr-intersect always-on">Medication</div><div class="grid-cell label sticky-doses hdr-intersect always-on">Doses</div><div class="grid-cell label sticky-dot hdr-intersect always-on">DOT</div><div class="grid-cell label axis-header always-on" style="grid-column: 4 / span ', trim(cnvtstring(v_days), 3), ';">Days'))
  row +1 call print(v_axis_html)
  row +1 '</div>'
  
  if (textlen(v_header_html) > 0)
    row +1 '<div class="grid-cell sticky-med hdr-intersect always-on"></div><div class="grid-cell sticky-doses hdr-intersect always-on"></div><div class="grid-cell sticky-dot hdr-intersect always-on"></div>'
    row +1 call print(v_header_html)
  endif

  /* Output Chart HTML Array safely */
  v_i = 1
  while (v_i <= html_chart->cnt)
     row +1 call print(html_chart->qual[v_i].text)
     v_i = v_i + 1
  endwhile
  
  row +1 '</div></div>'

  /* --- TABLE SECTION --- */
  row +1 '<h2>Antimicrobial Order Details</h2>'
  row +1 '<div style="width: 100%; overflow-x: auto; display: block;">'
  row +1 '<table class="data-tbl"><colgroup>'
  row +1 '<col style="width:180px"><col style="width:40px"><col style="width:40px">'
  row +1 '<col style="width:100px"><col style="display:none;">'
  row +1 '<col style="width:350px">'
  row +1 '<col style="width:250px">'
  row +1 '<col style="width:100px"><col style="width:120px"><col style="width:100px"><col style="width:100px"><col style="width:120px">'
  row +1 '</colgroup>'
  row +1 '<thead><tr>'
  row +1 '<th>Medication</th><th style="text-align:center;">Doses</th><th style="text-align:center;">DOT</th><th>Target Dose</th><th style="display:none;">Dose</th><th>Order Detail</th><th>Indication</th>'
  row +1 '<th>Start Date</th><th>Latest Status</th><th>Status Date</th><th>Order ID</th><th>FIN</th>'
  row +1 '</tr></thead>'
  row +1 '<tbody>'

  /* Output Table HTML Array safely */
  v_i = 1
  while (v_i <= html_table->cnt)
     row +1 call print(html_table->qual[v_i].text)
     v_i = v_i + 1
  endwhile

  row +1 '</tbody></table></div>'
  
  /* Javascript Interactive UI Engine */
  row +1 '<script>'
  row +1 'document.addEventListener("DOMContentLoaded", function() {'
  row +1 '  const items = document.querySelectorAll(".dimmable");'
  row +1 '  const triggers = document.querySelectorAll(".med-trigger");'
  row +1 '  triggers.forEach(function(trigger) {'
  row +1 '    trigger.addEventListener("click", function() {'
  row +1 '      const medName = this.getAttribute("data-med");'
  row +1 '      const isCurrentlyActive = this.classList.contains("active-filter");'
  row +1 '      triggers.forEach(function(t) { t.classList.remove("active-filter"); });'
  row +1 '      if (isCurrentlyActive) {'
  row +1 '        items.forEach(function(el) { el.classList.remove("dimmed"); });'
  row +1 '      } else {'
  row +1 '        this.classList.add("active-filter");'
  row +1 '        items.forEach(function(el) {'
  row +1 '          if (el.getAttribute("data-med") === medName || el.classList.contains("always-on")) {'
  row +1 '            el.classList.remove("dimmed");'
  row +1 '          } else {'
  row +1 '            el.classList.add("dimmed");'
  row +1 '          }'
  row +1 '        });'
  row +1 '      }'
  row +1 '    });'
  row +1 '  });'
  row +1 '});'
  row +1 '</script>'

  /* --- DEBUG PANEL --- */
  row +1 '<div style="margin-top:24px;padding:10px 14px;border:1px solid #f0a000;background:#fffbe6;color:#333;font-size:11px;font-family:monospace;">'
  row +1 '<b style="font-size:12px;">&#9888; DEBUG INFO (Array Buffer Mode Active)</b><br/>'
  row +1 call print(concat('Patient ID: ', trim(cnvtstring($PAT_PersonId), 3), ' &nbsp;|&nbsp; Lookback: ', trim(cnvtstring($LOOKBACK), 3), ' days<br/>'))
  row +1 call print(concat('MRN: ', v_mrn, '<br/>'))
  row +1 call print(concat('Admission: ', v_admit_dt, ' &nbsp;|&nbsp; LOS: ', v_los, ' days<br/>'))
  row +1 call print(concat('Query window: ', v_begin_dt_str, ' to ', v_end_dt_str, '<br/>'))
  row +1 call print(concat('Total admin_rec entries: ', trim(cnvtstring(admin_rec->cnt), 3), ' (PowerChart: ', trim(cnvtstring(v_pc_cnt), 3), ', SN Anesthesia: ', trim(cnvtstring(v_sn_cnt), 3), ')<br/>'))
  row +1 call print(concat('Chart date range: ', format(v_min_dt,"DD-MMM-YYYY;;D"), ' to ', format(v_max_dt,"DD-MMM-YYYY;;D"), ' (', trim(cnvtstring(v_days), 3), ' days)<br/>'))
  row +1 call print(concat('html_chart array count: ', trim(cnvtstring(html_chart->cnt), 3), '<br/>'))
  row +1 call print(concat('html_table array count: ', trim(cnvtstring(html_table->cnt), 3), '<br/>'))
  row +1 '</div>'

  /* --- FOOTER --- */
  row +1 call print(build2('<div style="margin-top:24px;padding-top:8px;border-top:1px solid var(--border-dark);color:#666;font-size:12px;">Generated on ', format(cnvtdatetime(curdate, curtime), "YYYY-MM-DD HH:MM:SS;;D"), '.</div></div></body></html>'))
with NOFORMAT, maxcol = 35000, time = 60

end
go
