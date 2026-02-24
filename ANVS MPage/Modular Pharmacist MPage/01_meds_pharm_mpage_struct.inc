/* 01_meds_pharm_mpage_struct.inc */
record mpage_data (
    ; --- Context & Prompts ---
    1 req_info
        2 patient_id = f8
        2 encounter_id = f8
        2 user_id = f8
        2 lookback_days = i4
        2 outdev = vc
    
    ; --- Header / Patient Info ---
    1 pat_info
        2 name = vc
        2 mrn = vc
        2 weight_dosing = vc
        2 admit_dt = vc
        2 los = vc
        2 begin_dt_str = vc
        2 end_dt_str = vc

    ; --- GP Medications (Tab: Medication Details GP) ---
    1 gp_meds[*]
        2 event_id = f8
        2 dt_tm = vc
        2 prsnl = vc
        2 blob_text = vc

    ; --- Main Medications (Tabs: Antibiotics, All Meds, Infusions) ---
    1 orders[*]
        2 order_id = f8
        2 mnemonic = vc
        2 cdl = vc
        2 start_dt = vc
        2 disp_cat = vc
        2 order_form = vc
        
    ; --- Antimicrobial DOT (Tab: Antimicrobial DOT) ---
    1 dot
        2 axis_html = vc
        2 header_html = vc
        2 chart_rows = vc
        2 table_rows = vc
)
