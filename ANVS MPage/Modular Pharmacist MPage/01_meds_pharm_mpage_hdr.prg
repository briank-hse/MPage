drop program 01_meds_pharm_mpage_hdr go
create program 01_meds_pharm_mpage_hdr

%i cust_script:01_meds_pharm_mpage_struct

/* ====================================================================
 * 1. GET MOST RECENT WEIGHT DOSING
 * ==================================================================== */
set mpage_data->pat_info.weight_dosing = "No weight dosing measured"

select into "nl:"
from clinical_event ce
plan ce where ce.person_id = mpage_data->req_info.patient_id
    and ce.event_cd = 14516898.00
    and ce.valid_until_dt_tm > cnvtdatetime(curdate, curtime)
    and ce.result_status_cd in (25, 34, 35)
order by
    ce.event_end_dt_tm desc
    , ce.clinsig_updt_dt_tm desc
head report
    mpage_data->pat_info.weight_dosing = concat(
        trim(ce.result_val), " ",
        uar_get_code_display(ce.result_units_cd),
        " (", format(ce.event_end_dt_tm, "DD/MM/YY"), ")"
    )
with nocounter, maxrec=1

/* ====================================================================
 * 2. GET DEMOGRAPHICS & ENCOUNTER DETAILS
 * Populates the Meta strings needed for the DOT chart headers.
 * ==================================================================== */
declare v_low_dt = dq8 with noconstant(null), protect
declare v_high_now_dt = dq8 with noconstant(null), protect

select into "nl:"
from person p
    , person_alias pa
    , encounter e
plan p where p.person_id = mpage_data->req_info.patient_id
join pa where pa.person_id = p.person_id 
    and pa.person_alias_type_cd = 10.00
    and pa.end_effective_dt_tm > sysdate
    and pa.active_ind = 1
join e where e.person_id = p.person_id
    and e.active_ind = 1
    /* Safely use encounter_id if passed via prompt, else fallback to latest */
    and e.encounter_id = coalesce(nullif(mpage_data->req_info.encounter_id, 0), e.encounter_id)
order by 
    e.arrive_dt_tm desc
head report
    mpage_data->pat_info.name = p.name_full_formatted
    mpage_data->pat_info.mrn = pa.alias
    
    /* Safely format arrival time and calculate LOS for DOT table header */
    if (e.arrive_dt_tm > 0)
        mpage_data->pat_info.admit_dt = format(e.arrive_dt_tm, "DD/MM/YYYY;;d")
        v_low_dt = cnvtdatetime(cnvtdate(e.arrive_dt_tm), 0)
        v_high_now_dt = cnvtdatetime(curdate, 0)
        mpage_data->pat_info.los = cnvtstring((datetimediff(v_high_now_dt, v_low_dt, 7)) + 1)
    else
        mpage_data->pat_info.admit_dt = "Unknown"
        mpage_data->pat_info.los = "N/A"
    endif

with nocounter, maxrec=1

/* ====================================================================
 * 3. CALCULATE GLOBAL DATE STRINGS
 * ==================================================================== */
set mpage_data->pat_info.begin_dt_str = format((curdate - mpage_data->req_info.lookback_days), "DD/MM/YYYY;;d")
set mpage_data->pat_info.end_dt_str = format(curdate, "DD/MM/YYYY;;d")

end
go