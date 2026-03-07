/**
 * PROGRAM: 01_meds_pharm_anvs:group1
 *
 * SPA JSON BACKEND - GP Medications (ANVS blob extraction)
 * Returns pure JSON via CNVTRECTOJSON(reply).
 * No HTML, no CSS, no JS.
 *
 * JSON shape:
 *   reply.status.code / reply.status.message
 *   reply.meta.module / .title / .patient_id / .encntr_id / .total_records
 *   reply.medications[*].event_id / .dt_tm / .prsnl / .blob_text
 *
 * blob_text: plain text with \n newlines only.
 *   - HTML entities and <br /> tags from CCL are NOT injected here.
 *   - The SPA shell JS renderer handles display escaping.
 *   - parseBlobText() in the shell already splits on \n and strips tags.
 */
DROP PROGRAM 01_meds_pharm_anvs:group1 GO
CREATE PROGRAM 01_meds_pharm_anvs:group1

PROMPT
    "Output to File/Printer/MINE" = "MINE"
    , "PatientID"   = 0
    , "EncntrID"    = 0
WITH OUTDEV, pid, eid

; =============================================================================
; RECORD STRUCTURES
; =============================================================================
RECORD reply (
    1 status
        2 code    = vc
        2 message = vc
    1 meta
        2 module        = vc
        2 title         = vc
        2 patient_id    = f8
        2 encntr_id     = f8
        2 total_records = i4
        2 pid_raw       = vc
    1 diag_event_codes[*]
        2 event_cd      = f8
        2 event_cd_disp = vc
        2 row_count     = i4
    1 medications[*]
        2 event_id  = f8
        2 dt_tm     = vc
        2 prsnl     = vc
        2 blob_text = vc
)

RECORD rec_blob (
    1 list[*]
        2 event_id  = f8
        2 dt_tm     = vc
        2 prsnl     = vc
        2 blob_text = vc
)

; =============================================================================
; DECLARATIONS
; =============================================================================
DECLARE OcfCD      = f8  WITH noconstant(0.0)
DECLARE stat       = i4  WITH noconstant(0)
DECLARE stat_rtf   = i4  WITH noconstant(0)
DECLARE tlen       = i4  WITH noconstant(0)
DECLARE bsize      = i4  WITH noconstant(0)
DECLARE totlen     = i4  WITH noconstant(0)
DECLARE bloblen    = i4  WITH noconstant(0)
DECLARE nCnt       = i4  WITH noconstant(0)
DECLARE x          = i4  WITH noconstant(0)
DECLARE blob_in    = vc  WITH noconstant(" ")
DECLARE blob_out   = vc  WITH noconstant(" ")
DECLARE rtf_out    = vc  WITH noconstant(" ")
DECLARE vCleanText = vc  WITH noconstant(" ")

SET stat = uar_get_meaning_by_codeset(120, "OCFCOMP", 1, OcfCD)

; =============================================================================
; DIAGNOSTIC ??? identify EVENT_CD values for CE_BLOB rows on this patient
; Remove this block once correct EVENT_CD is confirmed.
; =============================================================================
RECORD rec_diag (
    1 list[*]
        2 event_cd      = f8
        2 event_cd_disp = vc
        2 row_count     = i4
)

DECLARE diag_cnt = i4 WITH noconstant(0)

SELECT INTO "NL:"
FROM CLINICAL_EVENT CE
    , CE_BLOB CB
PLAN CE WHERE CE.PERSON_ID = CNVTREAL($pid)
    AND CE.VALID_UNTIL_DT_TM > CNVTDATETIME(CURDATE, CURTIME3)
JOIN CB WHERE CB.EVENT_ID = CE.EVENT_ID
    AND CB.VALID_UNTIL_DT_TM > CNVTDATETIME(CURDATE, CURTIME3)
ORDER BY CE.EVENT_CD

HEAD CE.EVENT_CD
    diag_cnt = diag_cnt + 1
    stat = alterlist(rec_diag->list, diag_cnt)
    rec_diag->list[diag_cnt].event_cd      = CE.EVENT_CD
    rec_diag->list[diag_cnt].event_cd_disp = UAR_GET_CODE_DISPLAY(CE.EVENT_CD)
    rec_diag->list[diag_cnt].row_count     = 0

DETAIL
    rec_diag->list[diag_cnt].row_count = rec_diag->list[diag_cnt].row_count + 1

WITH NOCOUNTER

; =============================================================================
; BLOB EXTRACTION ??? preserved from 01_meds_pharm_anvs_edge
; =============================================================================
SELECT INTO "NL:"
FROM CLINICAL_EVENT CE
    , CE_BLOB CB
    , PRSNL PR
PLAN CE WHERE CE.PERSON_ID = CNVTREAL($pid)
    AND CE.EVENT_CD = 25256529.00
    AND CE.VALID_UNTIL_DT_TM > CNVTDATETIME(CURDATE, CURTIME3)
JOIN CB WHERE CB.EVENT_ID = CE.EVENT_ID
    AND CB.VALID_UNTIL_DT_TM > CNVTDATETIME(CURDATE, CURTIME3)
JOIN PR WHERE PR.PERSON_ID = CE.PERFORMED_PRSNL_ID
ORDER BY CE.PERFORMED_DT_TM DESC

DETAIL
    nCnt = size(rec_blob->list, 5) + 1
    stat = alterlist(rec_blob->list, nCnt)
    rec_blob->list[nCnt].event_id = CE.EVENT_ID
    rec_blob->list[nCnt].dt_tm    = REPLACE(FORMAT(CE.PERFORMED_DT_TM, "DD/MM/YYYY HH:MM"), " 00:00", "", 0)
    rec_blob->list[nCnt].prsnl    = PR.NAME_FULL_FORMATTED

    tlen       = 0
    bsize      = 0
    vCleanText = " "

    bloblen = blobgetlen(CB.BLOB_CONTENTS)
    stat    = memrealloc(blob_in, 1, build("C", bloblen))
    totlen  = blobget(blob_in, 0, CB.BLOB_CONTENTS)

    stat = memrealloc(blob_out, 1, build("C", CB.BLOB_LENGTH))
    call uar_ocf_uncompress(blob_in, textlen(blob_in), blob_out, CB.BLOB_LENGTH, tlen)

    IF (tlen > 0)
        stat = memrealloc(rtf_out, 1, build("C", CB.BLOB_LENGTH))
        IF (FINDSTRING("{\rtf", blob_out, 1, 0) > 0)
            blob_out = REPLACE(blob_out, "\line", "\par", 0)
            tlen     = TEXTLEN(blob_out)
            stat_rtf = uar_rtf2(blob_out, tlen, rtf_out, CB.BLOB_LENGTH, bsize, 0)
        ELSE
            rtf_out = blob_out
            bsize   = tlen
        ENDIF
    ENDIF

    IF (bsize > 0)
        vCleanText = REPLACE(SUBSTRING(1, bsize, rtf_out), CHAR(0), " ", 0)
    ENDIF

    IF (TEXTLEN(TRIM(vCleanText)) <= 1)
        vCleanText = "-- No narrative note found --"
    ELSE
        ; Normalise line endings to plain \n only ??? no HTML injection
        ; JSON consumers (SPA shell parseBlobText) split on \n directly
        vCleanText = REPLACE(vCleanText, concat(CHAR(13), CHAR(10)), CHAR(10), 0)
        vCleanText = REPLACE(vCleanText, CHAR(13), CHAR(10), 0)
        vCleanText = REPLACE(vCleanText, CHAR(11), CHAR(10), 0)

        ; Consolidate runs of blank lines (3+ newlines ??? 2)
        vCleanText = REPLACE(vCleanText, concat(CHAR(10), CHAR(10), CHAR(10), CHAR(10)), concat(CHAR(10), CHAR(10)), 0)
        vCleanText = REPLACE(vCleanText, concat(CHAR(10), CHAR(10), CHAR(10)),           concat(CHAR(10), CHAR(10)), 0)

        vCleanText = TRIM(vCleanText, 3)
    ENDIF

    rec_blob->list[nCnt].blob_text = vCleanText

WITH NOCOUNTER, RDBARRAYFETCH=1

; =============================================================================
; POPULATE REPLY RECORD
; =============================================================================
SET reply->meta.module        = "01_meds_pharm_anvs:group1"
SET reply->meta.title         = "GP Medications"
SET reply->meta.patient_id    = CNVTREAL($pid)
SET reply->meta.encntr_id     = CNVTREAL($eid)
SET reply->meta.pid_raw       = CNVTSTRING($pid)
SET reply->meta.total_records = size(rec_blob->list, 5)

IF (size(rec_blob->list, 5) = 0)
    SET reply->status.code    = "no_data"
    SET reply->status.message = "No GP Medication Details available for this patient."
ELSE
    SET reply->status.code    = "ok"
    SET reply->status.message = "ok"
ENDIF

; Populate diagnostic event code list
SET stat = alterlist(reply->diag_event_codes, size(rec_diag->list, 5))
SET x = 1
WHILE (x <= size(rec_diag->list, 5))
    SET reply->diag_event_codes[x].event_cd      = rec_diag->list[x].event_cd
    SET reply->diag_event_codes[x].event_cd_disp = rec_diag->list[x].event_cd_disp
    SET reply->diag_event_codes[x].row_count     = rec_diag->list[x].row_count
    SET x = x + 1
ENDWHILE
FREE RECORD rec_diag

SET stat = alterlist(reply->medications, size(rec_blob->list, 5))

SET x = 1
WHILE (x <= size(rec_blob->list, 5))
    SET reply->medications[x].event_id  = rec_blob->list[x].event_id
    SET reply->medications[x].dt_tm     = rec_blob->list[x].dt_tm
    SET reply->medications[x].prsnl     = rec_blob->list[x].prsnl
    SET reply->medications[x].blob_text = rec_blob->list[x].blob_text
    SET x = x + 1
ENDWHILE

FREE RECORD rec_blob

SET _memory_reply_string = CNVTRECTOJSON(reply)

END
GO
