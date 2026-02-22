drop program 01_meds_pharm_mpage_main go
create program 01_meds_pharm_mpage_main

prompt
    "Output to File/Printer/MINE" = "MINE"
    , "User Id" = 0
    , "Patient ID" = 0
    , "Encounter Id" = 0
    , "Days Lookback" = 120
with OUTDEV, user_id, patient_id, encounter_id, LOOKBACK

/* ====================================================================
 * 1. GLOBAL RECORD STRUCTURE (THE CONTRACT)
 * ==================================================================== */
free record mpage_data
%i cust_script:01_meds_pharm_mpage_struct

/* ====================================================================
 * 2. INITIALIZE CONTEXT
 * ==================================================================== */
set mpage_data->req_info.patient_id = CNVTREAL($patient_id)
set mpage_data->req_info.encounter_id = CNVTREAL($encounter_id)
set mpage_data->req_info.user_id = CNVTREAL($user_id)
set mpage_data->req_info.lookback_days = $LOOKBACK
set mpage_data->req_info.outdev = $OUTDEV

/* ====================================================================
 * 3. EXECUTE DATA GATHERING MODULES
 * ==================================================================== */
execute 01_meds_pharm_mpage_hdr:group1
execute 01_meds_pharm_mpage_gp:group1
execute 01_meds_pharm_mpage_meds:group1
execute 01_meds_pharm_mpage_dot:group1

/* ====================================================================
 * 4. EXECUTE PRESENTATION MODULE
 * ==================================================================== */
execute 01_meds_pharm_mpage_rndr:group1

end
go