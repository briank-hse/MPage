drop program 01_meds_dot_diag:Group1 go
create program 01_meds_dot_diag:Group1

prompt
  "Output to File/Printer/MINE" = "MINE"
  , "Patient_ID" = 0
  , "Days Lookback" = 180
with OUTDEV, PAT_PersonId, LOOKBACK

free record admin_rec
record admin_rec (1 cnt=i4 1 qual[*] 2 admin_dt_tm=dq8 2 order_id=f8 2 admin_id=f8 2 src=vc)

free record med_chk
record med_chk (
  1 cnt = i4
  1 qual[*]
    2 med_name  = vc
    2 doses_exp = i4
    2 dot_exp   = i4
    2 day_keys  = vc
    2 day_counts = vc
)

declare stat           = i4  with noconstant(0)
declare v_i            = i4  with noconstant(0)
declare v_n1           = i4  with noconstant(0)
declare v_chk          = vc  with noconstant(""), maxlen=65534
declare v_xchk         = vc  with noconstant(""), maxlen=65534
declare v_raw          = vc  with noconstant(""), maxlen=65534
declare v_out          = vc  with noconstant(""), maxlen=65534
declare v_today        = dq8 with noconstant(0)
declare v_min_dt       = dq8 with noconstant(0)
declare v_max_dt       = dq8 with noconstant(0)
declare v_days         = i4  with noconstant(0)
declare v_min_date     = i4  with noconstant(0)
declare v_pc_cnt       = i4  with noconstant(0)
declare v_sn_cnt       = i4  with noconstant(0)
declare v_pass_cnt     = i4  with noconstant(0)
declare v_fail_cnt     = i4  with noconstant(0)
declare v_warn_cnt     = i4  with noconstant(0)
declare v_dtdiff       = f8  with noconstant(0.0)
declare v_dtdiff_frac  = f8  with noconstant(0.0)
declare v_str1         = vc  with noconstant("")
declare v_str2         = vc  with noconstant("")
declare v_grand_dot    = i4  with noconstant(0)
declare v_all_day_keys = vc  with noconstant(""), maxlen=65534
declare v_out_of_range = i4  with noconstant(0)
declare v_med_fail     = i4  with noconstant(0)
declare v_col_mismatch = i4  with noconstant(0)
declare v_col_found    = i4  with noconstant(0)
declare v_test_key     = vc  with noconstant("")
declare v_temp_str     = vc  with noconstant(""), maxlen=65534
declare v_key_pos      = i4  with noconstant(0)
declare v_key_end      = i4  with noconstant(0)
declare v_display      = vc  with noconstant(""), maxlen=65534
declare v_col_key      = vc  with noconstant("")
declare v_col_hdr      = vc  with noconstant(""), maxlen=65534
declare v_cells        = vc  with noconstant(""), maxlen=65534
declare v_day_count    = i4  with noconstant(0)
declare v_table_rows   = i4  with noconstant(0)
declare v_table_display = vc with noconstant(""), maxlen=65534
declare v_order_days   = vc  with noconstant(""), maxlen=65534
declare v_table_doses  = i4  with noconstant(0)
declare v_table_dot    = i4  with noconstant(0)

/* ---- PASS 0A: PowerChart ---- */
select into "nl:"
from clinical_event ce, med_admin_event m, orders o, code_value_event_r cr,
     order_catalog oc, order_catalog_synonym ocs, order_entry_format oe
plan ce where ce.person_id = $PAT_PersonId
  and ce.performed_dt_tm between cnvtdatetime(curdate-$LOOKBACK,0) and cnvtdatetime(curdate,curtime)
  and ce.result_status_cd = 25.00
join m where m.event_id = ce.event_id and m.event_type_cd = 8912520.00
join o where o.order_id = m.template_order_id
join cr where cr.event_cd = ce.event_cd
join oc where oc.catalog_cd = cr.parent_cd and oc.catalog_type_cd = 2516
join ocs where ocs.catalog_cd = oc.catalog_cd
join oe where oe.oe_format_id = ocs.oe_format_id and oe.oe_format_id in (14497910,14498121)
order by m.event_id
head report admin_rec->cnt = 0
head m.event_id
  admin_rec->cnt = admin_rec->cnt + 1
  stat = alterlist(admin_rec->qual, admin_rec->cnt)
  admin_rec->qual[admin_rec->cnt].admin_dt_tm = ce.event_end_dt_tm
  admin_rec->qual[admin_rec->cnt].order_id    = o.order_id
  admin_rec->qual[admin_rec->cnt].admin_id    = ce.event_id
  admin_rec->qual[admin_rec->cnt].src         = "PC"
with nocounter

/* ---- PASS 0B: SurgiNet ---- */
select into "nl:"
from orders o, sa_medication_admin sma, sa_med_admin_item smai,
     order_catalog_synonym ocs, order_entry_format oe
plan o where o.person_id = $PAT_PersonId
join sma where sma.order_id = o.order_id and sma.active_ind = 1
join smai where smai.sa_medication_admin_id = sma.sa_medication_admin_id and smai.active_ind = 1
  and smai.admin_start_dt_tm >= cnvtdatetimeutc(cnvtdatetime(curdate-$LOOKBACK,0))
  and smai.admin_start_dt_tm <= cnvtdatetimeutc(cnvtdatetime(curdate,curtime))
join ocs where ocs.synonym_id = o.synonym_id
join oe where oe.oe_format_id = ocs.oe_format_id and oe.oe_format_id in (14497910,14498121)
order by smai.sa_med_admin_item_id
head smai.sa_med_admin_item_id
  admin_rec->cnt = admin_rec->cnt + 1
  stat = alterlist(admin_rec->qual, admin_rec->cnt)
  admin_rec->qual[admin_rec->cnt].admin_dt_tm = cnvtdatetimeutc(smai.admin_start_dt_tm)
  admin_rec->qual[admin_rec->cnt].order_id    = o.order_id
  admin_rec->qual[admin_rec->cnt].admin_id    = smai.sa_med_admin_item_id
  admin_rec->qual[admin_rec->cnt].src         = "SN"
with nocounter

/* ---- Date dimension ---- */
set v_today = cnvtdatetime(curdate, 0)
if (admin_rec->cnt > 0)
  set v_min_dt = cnvtdatetime(concat(format(admin_rec->qual[1].admin_dt_tm,"DD-MMM-YYYY;;D")," 00:00:00"))
  set v_max_dt = v_min_dt
  set v_i = 2
  while (v_i <= admin_rec->cnt)
    if (format(admin_rec->qual[v_i].admin_dt_tm,"YYYYMMDD;;D") < format(v_min_dt,"YYYYMMDD;;D"))
      set v_min_dt = cnvtdatetime(concat(format(admin_rec->qual[v_i].admin_dt_tm,"DD-MMM-YYYY;;D")," 00:00:00"))
    endif
    if (format(admin_rec->qual[v_i].admin_dt_tm,"YYYYMMDD;;D") > format(v_max_dt,"YYYYMMDD;;D"))
      set v_max_dt = cnvtdatetime(concat(format(admin_rec->qual[v_i].admin_dt_tm,"DD-MMM-YYYY;;D")," 00:00:00"))
    endif
    set v_i = v_i + 1
  endwhile
  if (v_max_dt < v_today) set v_max_dt = v_today endif
  set v_days     = cnvtint(datetimediff(v_max_dt, v_min_dt, 1)) + 1
  set v_min_date = curdate - (v_days - 1)
  set v_i = 1
  while (v_i <= admin_rec->cnt)
    if (admin_rec->qual[v_i].src = "PC") set v_pc_cnt = v_pc_cnt + 1
    elseif (admin_rec->qual[v_i].src = "SN") set v_sn_cnt = v_sn_cnt + 1
    endif
    set v_i = v_i + 1
  endwhile
endif

/* ---- Unique admin day keys ---- */
set v_all_day_keys = ""
set v_i = 1
while (v_i <= admin_rec->cnt)
  set v_str1 = concat("~", format(admin_rec->qual[v_i].admin_dt_tm,"YYYYMMDD;;D"), "~")
  if (findstring(v_str1, v_all_day_keys) = 0)
    set v_all_day_keys = concat(v_all_day_keys, v_str1)
  endif
  set v_i = v_i + 1
endwhile

/* ---- Per-med expected DOT/doses (mirrors PASS 2 logic) ---- */
set med_chk->cnt = 0
if (admin_rec->cnt > 0)
select into "nl:"
  med_name = trim(oc.primary_mnemonic)
, mdy      = format(admin_rec->qual[d.seq].admin_dt_tm,"YYYYMMDD;;D")
, src_id   = admin_rec->qual[d.seq].admin_id
from (dummyt d with seq = admin_rec->cnt), orders o, order_catalog oc
plan d join o where o.order_id = admin_rec->qual[d.seq].order_id
join oc where oc.catalog_cd = o.catalog_cd
order by cnvtupper(trim(oc.primary_mnemonic)), mdy, src_id
head med_name
  med_chk->cnt = med_chk->cnt + 1
  stat = alterlist(med_chk->qual, med_chk->cnt)
  med_chk->qual[med_chk->cnt].med_name  = med_name
  med_chk->qual[med_chk->cnt].doses_exp = 0
  med_chk->qual[med_chk->cnt].dot_exp   = 0
  med_chk->qual[med_chk->cnt].day_keys  = ""
  med_chk->qual[med_chk->cnt].day_counts = ""
head mdy
  v_day_count = 0
head src_id
  v_day_count = v_day_count + 1
  med_chk->qual[med_chk->cnt].doses_exp = med_chk->qual[med_chk->cnt].doses_exp + 1
foot mdy
  med_chk->qual[med_chk->cnt].dot_exp  = med_chk->qual[med_chk->cnt].dot_exp + 1
  med_chk->qual[med_chk->cnt].day_keys = concat(med_chk->qual[med_chk->cnt].day_keys, mdy, "/")
  med_chk->qual[med_chk->cnt].day_counts = concat(med_chk->qual[med_chk->cnt].day_counts, "~", mdy, ":", trim(cnvtstring(v_day_count),3), "~")
foot med_name
  v_grand_dot = v_grand_dot + med_chk->qual[med_chk->cnt].dot_exp
with nocounter
endif

/* ---- Expected order-detail table rows (mirrors main table grouping) ---- */
set v_table_display = ""
set v_table_rows = 0
if (admin_rec->cnt > 0)
select into "nl:"
  med_name = trim(oc.primary_mnemonic)
, day_key = format(admin_rec->qual[d.seq].admin_dt_tm,"YYYYMMDD;;D")
, src_id = admin_rec->qual[d.seq].admin_id
, o.order_id
from (dummyt d with seq = admin_rec->cnt), orders o, order_catalog oc
plan d join o where o.order_id = admin_rec->qual[d.seq].order_id
join oc where oc.catalog_cd = o.catalog_cd
order by o.order_id, cnvtupper(trim(oc.primary_mnemonic)), day_key, src_id
head o.order_id
  v_table_doses = 0
  v_table_dot = 0
  v_order_days = ""
head day_key
  if (findstring(concat("~", day_key, "~"), v_order_days) = 0)
    v_table_dot = v_table_dot + 1
    v_order_days = concat(v_order_days, "~", day_key, "~")
  endif
head src_id
  v_table_doses = v_table_doses + 1
foot o.order_id
  v_table_rows = v_table_rows + 1
  v_table_display = concat(v_table_display,
    trim(cnvtstring(v_table_rows),3), ". ",
    trim(med_name,3),
    " | Doses=", trim(cnvtstring(v_table_doses),3),
    " DOT=", trim(cnvtstring(v_table_dot),3),
    " | Order ID=", trim(cnvtstring(o.order_id,10,0),3),
    " | Admin days=", v_order_days,
    char(10))
with nocounter
endif

/* ---- Expected visible chart/table display ---- */
set v_display = ""
if (admin_rec->cnt > 0)
  set v_col_hdr = "Columns: "
  set v_i = 0
  while (v_i < v_days and v_i <= 200)
    set v_col_hdr = concat(v_col_hdr,
      "[", trim(cnvtstring(v_i),3), "]",
      format(v_min_date + v_i,"DD-MMM;;D"),
      if ((v_min_date + v_i) = curdate) "*TODAY*" else "" endif,
      " ")
    set v_i = v_i + 1
  endwhile
  if (v_days > 201)
    set v_col_hdr = concat(v_col_hdr, "... truncated after 201 columns")
  endif

  set v_display = concat(v_display,
    "--- EXPECTED MPAGE DISPLAY ---", char(10),
    "Date range header: ", format(v_min_dt,"DD-MMM-YYYY;;D"), " to ",
      format(v_max_dt,"DD-MMM-YYYY;;D"), " (", trim(cnvtstring(v_days),3), " days)", char(10),
    "Today highlight column: ", format(curdate,"YYYYMMDD;;D"), " (light blue)", char(10),
    v_col_hdr, char(10), char(10),
    "Medication chart rows: '.' = empty cell, number = blue admin square dose count, * marks today column", char(10))

  set v_n1 = 1
  while (v_n1 <= med_chk->cnt)
    set v_cells = ""
    set v_i = 0
    while (v_i < v_days and v_i <= 200)
      set v_col_key = format(v_min_date + v_i,"YYYYMMDD;;D")
      set v_key_pos = findstring(concat("~", v_col_key, ":"), med_chk->qual[v_n1].day_counts)
      if (v_key_pos > 0)
        set v_temp_str = substring(v_key_pos + 10, textlen(med_chk->qual[v_n1].day_counts) - (v_key_pos + 9), med_chk->qual[v_n1].day_counts)
        set v_key_end = findstring("~", v_temp_str)
        if (v_key_end > 0)
          set v_str1 = substring(1, v_key_end - 1, v_temp_str)
        else
          set v_str1 = v_temp_str
        endif
      else
        set v_str1 = "."
      endif
      set v_cells = concat(v_cells, if ((v_min_date + v_i) = curdate) "*" else "" endif, v_str1, " ")
      set v_i = v_i + 1
    endwhile
    set v_display = concat(v_display,
      trim(med_chk->qual[v_n1].med_name,3),
      " | Doses=", trim(cnvtstring(med_chk->qual[v_n1].doses_exp),3),
      " DOT=", trim(cnvtstring(med_chk->qual[v_n1].dot_exp),3),
      " | ", v_cells,
      if (v_days > 201) "... truncated" else "" endif,
      char(10))
    set v_n1 = v_n1 + 1
  endwhile

  set v_cells = ""
  set v_i = 0
  while (v_i < v_days and v_i <= 200)
    set v_col_key = format(v_min_date + v_i,"YYYYMMDD;;D")
    if (findstring(concat("~", v_col_key, "~"), v_all_day_keys) > 0)
      set v_str1 = "Y"
    else
      set v_str1 = "."
    endif
    set v_cells = concat(v_cells, if ((v_min_date + v_i) = curdate) "*" else "" endif, v_str1, " ")
    set v_i = v_i + 1
  endwhile
  set v_display = concat(v_display,
    "Antimicrobial Summary | Grand DOT=", trim(cnvtstring(v_grand_dot),3),
    " | ", v_cells,
    if (v_days > 201) "... truncated" else "" endif,
    char(10), char(10),
    "Expected Antimicrobial Order Details rows (order-level):", char(10),
    v_table_display)
endif

/* ===================== AUTOMATED CHECKS ===================== */
set v_chk = ""
if (admin_rec->cnt = 0)
  set v_chk = "[INFO] No admin records found - checks skipped"
else

/* C1: v_min_date and v_min_dt represent the same calendar date */
set v_str1 = format(v_min_date,"YYYYMMDD;;D")
set v_str2 = format(v_min_dt,  "YYYYMMDD;;D")
if (v_str1 = v_str2)
  set v_pass_cnt = v_pass_cnt + 1
  set v_chk = concat(v_chk, "[PASS] C1  v_min_date=", v_str1, " = v_min_dt=", v_str2, char(10))
else
  set v_fail_cnt = v_fail_cnt + 1
  set v_chk = concat(v_chk, "[FAIL] C1  v_min_date=", v_str1, " != v_min_dt=", v_str2, char(10))
endif

/* C2: Last chart column = today */
set v_str1 = format(v_min_date + (v_days - 1),"YYYYMMDD;;D")
set v_str2 = format(curdate,"YYYYMMDD;;D")
if (v_str1 = v_str2)
  set v_pass_cnt = v_pass_cnt + 1
  set v_chk = concat(v_chk, "[PASS] C2  col[", trim(cnvtstring(v_days-1),3), "]=", v_str1, " = today=", v_str2, char(10))
else
  set v_fail_cnt = v_fail_cnt + 1
  set v_chk = concat(v_chk, "[FAIL] C2  col[", trim(cnvtstring(v_days-1),3), "]=", v_str1, " != today=", v_str2, char(10))
endif

/* C3: datetimediff truncates to v_days-1 */
set v_dtdiff      = datetimediff(v_max_dt, v_min_dt, 1)
set v_n1          = cnvtint(v_dtdiff)
set v_dtdiff_frac = v_dtdiff - v_n1
if (v_n1 = v_days - 1)
  set v_pass_cnt = v_pass_cnt + 1
  set v_chk = concat(v_chk, "[PASS] C3  datetimediff=", cnvtstring(v_dtdiff), " -> int=", trim(cnvtstring(v_n1),3), " = v_days-1=", trim(cnvtstring(v_days-1),3), char(10))
else
  set v_fail_cnt = v_fail_cnt + 1
  set v_chk = concat(v_chk, "[FAIL] C3  datetimediff=", cnvtstring(v_dtdiff), " -> int=", trim(cnvtstring(v_n1),3), " != v_days-1=", trim(cnvtstring(v_days-1),3), char(10))
endif
if (v_dtdiff_frac > 0.001 and v_dtdiff_frac < 0.09)
  set v_warn_cnt = v_warn_cnt + 1
  set v_chk = concat(v_chk, "[WARN] C3w fractional=", cnvtstring(v_dtdiff_frac), " (BST/DST boundary - expected if range crosses clocks-change)", char(10))
elseif (v_dtdiff_frac >= 0.09)
  set v_warn_cnt = v_warn_cnt + 1
  set v_chk = concat(v_chk, "[WARN] C3w fractional=", cnvtstring(v_dtdiff_frac), " (unexpectedly large - investigate)", char(10))
endif

/* C4: v_max_dt = v_today */
set v_str1 = format(v_max_dt,"YYYYMMDD;;D")
set v_str2 = format(v_today, "YYYYMMDD;;D")
if (v_str1 = v_str2)
  set v_pass_cnt = v_pass_cnt + 1
  set v_chk = concat(v_chk, "[PASS] C4  v_max_dt=", v_str1, " = v_today=", v_str2, char(10))
else
  set v_fail_cnt = v_fail_cnt + 1
  set v_chk = concat(v_chk, "[FAIL] C4  v_max_dt=", v_str1, " != v_today=", v_str2, char(10))
endif

/* C5: All admin records within chart column range */
set v_out_of_range = 0
set v_str1 = format(v_min_date,"YYYYMMDD;;D")
set v_str2 = format(curdate,   "YYYYMMDD;;D")
set v_i = 1
while (v_i <= admin_rec->cnt)
  if (format(admin_rec->qual[v_i].admin_dt_tm,"YYYYMMDD;;D") < v_str1 or
      format(admin_rec->qual[v_i].admin_dt_tm,"YYYYMMDD;;D") > v_str2)
    set v_out_of_range = v_out_of_range + 1
  endif
  set v_i = v_i + 1
endwhile
if (v_out_of_range = 0)
  set v_pass_cnt = v_pass_cnt + 1
  set v_chk = concat(v_chk, "[PASS] C5  All ", trim(cnvtstring(admin_rec->cnt),3), " admin records within [", v_str1, "..", v_str2, "]", char(10))
else
  set v_fail_cnt = v_fail_cnt + 1
  set v_chk = concat(v_chk, "[FAIL] C5  ", trim(cnvtstring(v_out_of_range),3), " admin records outside chart range", char(10))
endif

/* C6: Per-med sanity: DOT <= doses and DOT <= v_days */
set v_med_fail = 0
set v_i = 1
while (v_i <= med_chk->cnt)
  if (med_chk->qual[v_i].dot_exp > med_chk->qual[v_i].doses_exp)
    set v_med_fail = v_med_fail + 1
    set v_chk = concat(v_chk, "[FAIL] C6  ", trim(med_chk->qual[v_i].med_name,3), ": DOT(", trim(cnvtstring(med_chk->qual[v_i].dot_exp),3), ")>doses(", trim(cnvtstring(med_chk->qual[v_i].doses_exp),3), ")", char(10))
  endif
  if (med_chk->qual[v_i].dot_exp > v_days)
    set v_med_fail = v_med_fail + 1
    set v_chk = concat(v_chk, "[FAIL] C6  ", trim(med_chk->qual[v_i].med_name,3), ": DOT(", trim(cnvtstring(med_chk->qual[v_i].dot_exp),3), ")>v_days(", trim(cnvtstring(v_days),3), ")", char(10))
  endif
  set v_i = v_i + 1
endwhile
if (v_med_fail = 0)
  set v_pass_cnt = v_pass_cnt + 1
  set v_chk = concat(v_chk, "[PASS] C6  Per-med DOT<=doses and DOT<=v_days for all ", trim(cnvtstring(med_chk->cnt),3), " medication(s)", char(10))
else
  set v_fail_cnt = v_fail_cnt + 1
endif

/* C7: Every unique admin day key maps to a chart column */
set v_col_mismatch = 0
set v_temp_str = v_all_day_keys
set v_key_pos  = findstring("~", v_temp_str)
while (v_key_pos > 0)
  set v_temp_str = substring(v_key_pos + 1, textlen(v_temp_str) - v_key_pos, v_temp_str)
  set v_key_end  = findstring("~", v_temp_str)
  if (v_key_end > 1)
    set v_test_key = substring(1, v_key_end - 1, v_temp_str)
    set v_col_found = 0
    set v_i = 0
    while (v_i < v_days and v_col_found = 0)
      if (format(v_min_date + v_i,"YYYYMMDD;;D") = v_test_key)
        set v_col_found = 1
      endif
      set v_i = v_i + 1
    endwhile
    if (v_col_found = 0)
      set v_col_mismatch = v_col_mismatch + 1
      set v_chk = concat(v_chk, "[FAIL] C7  Admin key ", v_test_key, " not found in any chart column", char(10))
    endif
    set v_temp_str = substring(v_key_end + 1, textlen(v_temp_str) - v_key_end, v_temp_str)
    set v_key_pos  = findstring("~", v_temp_str)
  else
    set v_key_pos = 0
  endif
endwhile
if (v_col_mismatch = 0)
  set v_pass_cnt = v_pass_cnt + 1
  set v_chk = concat(v_chk, "[PASS] C7  All unique admin day keys found in chart columns", char(10))
else
  set v_fail_cnt = v_fail_cnt + 1
endif

endif  /* end admin_rec->cnt > 0 */

/* ===================== CROSS-CHECK ===================== */
/* Produces exact text that the debug panel should show.   */
/* Paste both outputs here and compare section-by-section. */
set v_xchk = ""
if (admin_rec->cnt > 0)
  set v_xchk = concat(v_xchk,
    "=== EXPECTED DEBUG PANEL OUTPUT ===", char(10),
    "(Paste the main program debug panel below this block and", char(10),
    " verify each section matches exactly)", char(10),
    char(10))

  /* Line 1: Chart range + Grand DOT */
  set v_xchk = concat(v_xchk,
    "Chart range: ", format(v_min_dt,"DD-MMM-YYYY;;D"), " to ",
    format(v_max_dt,"DD-MMM-YYYY;;D"), " (", trim(cnvtstring(v_days),3),
    " days) | Grand DOT: ", trim(cnvtstring(v_grand_dot),3), char(10),
    char(10))

  /* Per-medication lines - same format as v_debug_meds in main program */
  set v_xchk = concat(v_xchk, "Per-medication (chart):", char(10))
  set v_i = 1
  while (v_i <= med_chk->cnt)
    set v_xchk = concat(v_xchk,
      trim(med_chk->qual[v_i].med_name,3),
      ": doses=", trim(cnvtstring(med_chk->qual[v_i].doses_exp),3),
      " DOT=", trim(cnvtstring(med_chk->qual[v_i].dot_exp),3), char(10))
    set v_i = v_i + 1
  endwhile

  /* Unique admin day keys - same format as v_all_days_list in main program  */
  /* (order may differ; keys must match)                                      */
  set v_xchk = concat(v_xchk,
    char(10), "Unique admin day keys (chart lookup keys):", char(10),
    v_all_day_keys, char(10))
endif

/* ===================== RAW DATA ===================== */
set v_raw = concat(
  "--- DATE VARIABLES ---", char(10),
  "v_today:    ", format(v_today,   "DD-MMM-YYYY HH:MM:SS;;D"), " | raw: ", cnvtstring(v_today),   char(10),
  "v_min_dt:   ", format(v_min_dt,  "DD-MMM-YYYY HH:MM:SS;;D"), " | raw: ", cnvtstring(v_min_dt),  char(10),
  "v_max_dt:   ", format(v_max_dt,  "DD-MMM-YYYY HH:MM:SS;;D"), " | raw: ", cnvtstring(v_max_dt),  char(10),
  "v_min_date: ", format(v_min_date,"DD-MMM-YYYY;;D"),            " | raw i4: ", trim(cnvtstring(v_min_date),3), char(10),
  "v_days: ", trim(cnvtstring(v_days),3),
  "  dtdiff: ", cnvtstring(v_dtdiff),
  "  grand_dot: ", trim(cnvtstring(v_grand_dot),3), char(10),
  char(10),
  "--- ALL ADMIN RECORDS (", trim(cnvtstring(admin_rec->cnt),3), ") ---", char(10)
)
set v_i = 1
while (v_i <= admin_rec->cnt)
  set v_raw = concat(v_raw,
    trim(cnvtstring(v_i),3), ": ",
    format(admin_rec->qual[v_i].admin_dt_tm,"DD-MMM-YYYY HH:MM;;D"),
    " | key=", format(admin_rec->qual[v_i].admin_dt_tm,"YYYYMMDD;;D"),
    " | raw=", cnvtstring(admin_rec->qual[v_i].admin_dt_tm),
    " | ord=", trim(cnvtstring(admin_rec->qual[v_i].order_id,10,0),3),
    " (", admin_rec->qual[v_i].src, ")", char(10))
  set v_i = v_i + 1
endwhile

set v_raw = concat(v_raw, char(10), "--- PER-MEDICATION EXPECTED (", trim(cnvtstring(med_chk->cnt),3), " meds) ---", char(10))
set v_i = 1
while (v_i <= med_chk->cnt)
  set v_raw = concat(v_raw,
    trim(med_chk->qual[v_i].med_name,3),
    ": doses=", trim(cnvtstring(med_chk->qual[v_i].doses_exp),3),
    " DOT=",   trim(cnvtstring(med_chk->qual[v_i].dot_exp),3),
    " days=[", trim(med_chk->qual[v_i].day_keys,3), "]", char(10))
  set v_i = v_i + 1
endwhile

set v_raw = concat(v_raw, char(10), "--- CHART COLUMN KEYS ---", char(10))
set v_i = 0
while (v_i < v_days and v_i <= 200)
  set v_raw = concat(v_raw,
    "col[", trim(cnvtstring(v_i),3), "]: ",
    format(v_min_date + v_i,"YYYYMMDD;;D"), " ",
    format(v_min_date + v_i,"DD-MMM-YYYY;;D"),
    if ((v_min_date + v_i) = curdate) " <-- TODAY" else "" endif,
    char(10))
  set v_i = v_i + 1
endwhile

/* ===================== OUTPUT ===================== */
set v_out = concat(
  "=== ANTIMICROBIAL DOT DIAGNOSTIC ===", char(10),
  "Patient ID: ", trim(cnvtstring($PAT_PersonId),3),
  "  Lookback: ", trim(cnvtstring($LOOKBACK),3), " days",
  "  Run: ", format(cnvtdatetime(curdate,curtime),"YYYY-MM-DD HH:MM:SS;;D"), char(10),
  char(10),
  "RESULT: ", trim(cnvtstring(v_pass_cnt),3), " passed | ",
             trim(cnvtstring(v_fail_cnt),3), " failed | ",
             trim(cnvtstring(v_warn_cnt),3), " warnings", char(10),
  char(10),
  v_chk,
  char(10),
  v_display,
  char(10),
  v_xchk,
  char(10),
  v_raw
)

set _memory_reply_string = concat(
  '<pre style="font-size:11px;line-height:1.5;font-family:monospace;',
  'white-space:pre;background:#f5f5f5;padding:14px;border:1px solid #ccc;',
  'user-select:all;cursor:text;">',
  v_out,
  '</pre>')

end
go
