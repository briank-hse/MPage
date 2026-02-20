drop program 01_meds_pharm_mpage_gp go
create program 01_meds_pharm_mpage_gp

%i cust_script:01_meds_pharm_mpage_struct

/* ====================================================================
 * GP MEDICATION DETAILS - BLOBGET & MEMREALLOC
 * ==================================================================== */
declare OcfCD      = f8  with noconstant(0.0), protect
declare stat       = i4  with noconstant(0), protect
declare stat_rtf   = i4  with noconstant(0), protect
declare tlen       = i4  with noconstant(0), protect
declare bsize      = i4  with noconstant(0), protect
declare totlen     = i4  with noconstant(0), protect
declare bloblen    = i4  with noconstant(0), protect
declare nCnt       = i4  with noconstant(0), protect
declare blob_in    = vc  with noconstant(" "), protect
declare blob_out   = vc  with noconstant(" "), protect
declare rtf_out    = vc  with noconstant(" "), protect
declare vCleanText = vc  with noconstant(" "), protect

set stat = uar_get_meaning_by_codeset(120, "OCFCOMP", 1, OcfCD)

select into "nl:"
from clinical_event ce
    , ce_blob cb
    , prsnl pr
plan ce where ce.person_id = mpage_data->req_info.patient_id
    and ce.event_cd = 25256529.00
    and ce.valid_until_dt_tm > sysdate
join cb where cb.event_id = ce.event_id
    and cb.valid_until_dt_tm > sysdate
join pr where pr.person_id = ce.performed_prsnl_id
order by ce.performed_dt_tm desc
head report
    nCnt = 0
detail
    nCnt = nCnt + 1
    stat = alterlist(mpage_data->gp_meds, nCnt)
    mpage_data->gp_meds[nCnt].event_id = ce.event_id
    
    ; Strip default 00:00 midnight times to clean up the display
    mpage_data->gp_meds[nCnt].dt_tm = replace(format(ce.performed_dt_tm, "DD/MM/YYYY HH:MM"), " 00:00", "", 0)
    mpage_data->gp_meds[nCnt].prsnl = pr.name_full_formatted

    tlen       = 0
    bsize      = 0
    vCleanText = " "

    ; Step 1: BLOBGET
    bloblen = blobgetlen(cb.blob_contents)
    stat    = memrealloc(blob_in, 1, build("C", bloblen))
    totlen  = blobget(blob_in, 0, cb.blob_contents)

    ; Step 2: Decompress
    stat = memrealloc(blob_out, 1, build("C", cb.blob_length))
    call uar_ocf_uncompress(blob_in, textlen(blob_in), blob_out, cb.blob_length, tlen)

    ; Step 3: RTF to plain text
    if (tlen > 0)
        stat = memrealloc(rtf_out, 1, build("C", cb.blob_length))
        if (findstring("{\rtf", blob_out, 1, 0) > 0)
            blob_out = replace(blob_out, "\line", "\par", 0)
            tlen = textlen(blob_out)
            stat_rtf = uar_rtf2(blob_out, tlen, rtf_out, cb.blob_length, bsize, 0)
        else
            rtf_out = blob_out
            bsize = tlen
        endif
    endif

    ; Step 4: Clean text
    if (bsize > 0)
        vCleanText = replace(substring(1, bsize, rtf_out), char(0), " ", 0)
    endif

    if (textlen(trim(vCleanText)) <= 1)
        vCleanText = "<i>-- No narrative note found --</i>"
    else
        vCleanText = replace(vCleanText, "&",     "&amp;", 0)
        vCleanText = replace(vCleanText, "<",     "&lt;",  0)
        vCleanText = replace(vCleanText, ">",     "&gt;",  0)
        vCleanText = replace(vCleanText, concat(char(13), char(10)), "<br />", 0)
        vCleanText = replace(vCleanText, char(13), "<br />", 0)
        vCleanText = replace(vCleanText, char(10), "<br />", 0)
        vCleanText = replace(vCleanText, char(11), "<br />", 0) 
        
        ; Strip excessive returns
        vCleanText = replace(vCleanText, "<br /><br /><br /><br /><br /><br />", "<br /><br />", 0)
        vCleanText = replace(vCleanText, "<br /><br /><br /><br /><br />", "<br /><br />", 0)
        vCleanText = replace(vCleanText, "<br /><br /><br /><br />", "<br /><br />", 0)
        vCleanText = replace(vCleanText, "<br /><br /><br />", "<br /><br />", 0)
        
        vCleanText = trim(vCleanText, 3)
    endif

    mpage_data->gp_meds[nCnt].blob_text = vCleanText

with nocounter

end
go