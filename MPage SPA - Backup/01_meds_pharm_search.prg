DROP PROGRAM 01_meds_pharm_search:group1 GO
CREATE PROGRAM 01_meds_pharm_search:group1

PROMPT "Output to File/Printer/MINE" = "MINE", "User Id" = 0, "Patient ID" = 0, "Encounter Id" = 0
WITH OUTDEV, user_id, pid, eid

; =============================================================================
; Legacy behavior preserved from 01_meds_pharm_search_edge:
; - patient-level note/blob extraction with strict blob requirement
; - active patient sticky notes
; - original ordering (notes first in query order, then sticky notes)
; - category/date filter metadata for SPA rendering
; - high-risk medication flags moved from client-side JS into backend fields
; =============================================================================

DECLARE RUN_STICKY     = i2 WITH NOCONSTANT(1)
DECLARE RUN_NOTES      = i2 WITH NOCONSTANT(1)
DECLARE RUN_FORMS      = i2 WITH NOCONSTANT(0)
DECLARE RUN_IVIEW_TEXT = i2 WITH NOCONSTANT(0)

RECORD rec_docs (
  1 list[*]
    2 source_type = vc
    2 category    = vc
    2 event_id    = f8
    2 title       = vc
    2 dt_tm       = vc
    2 prsnl       = vc
    2 doc_text    = vc
)

RECORD rec_debug (
  1 list[*]
    2 event_id    = f8
    2 title       = vc
    2 dt_tm       = vc
    2 prsnl       = vc
    2 source_type = vc
    2 blob_len    = i4
    2 text_len    = i4
    2 status      = vc
    2 reason      = vc
)

RECORD reply (
    1 status
        2 code    = vc
        2 message = vc
    1 meta
        2 module              = vc
        2 title               = vc
        2 patient_id          = f8
        2 encntr_id           = f8
        2 search_scope        = vc
        2 lookback_days       = i4
        2 result_count        = i4
        2 encounter_scoped    = i2
        2 doc_class_cd        = f8
        2 form_class_cd       = f8
        2 auth_status_cd      = f8
        2 modified_status_cd  = f8
    1 summary
        2 total_results            = i4
        2 notes                    = i4
        2 sticky_notes             = i4
        2 displayed_debug             = i4
        2 dropped_debug               = i4
        2 candidate_all_events        = i4
        2 candidate_note_events       = i4
        2 candidate_note_payloads     = i4
        2 candidate_sticky_notes      = i4
    1 filters[*]
        2 filter_type = vc
        2 code        = vc
        2 label       = vc
        2 count       = i4
        2 days        = i4
        2 is_default  = i2
    1 results[*]
        2 result_index      = i4
        2 event_id          = f8
        2 category          = vc
        2 source_type       = vc
        2 title             = vc
        2 event_dt_tm       = vc
        2 authored_by       = vc
        2 doc_text          = vc
        2 text_length       = i4
        2 high_risk_labels  = vc
        2 high_risk_count   = i4
        2 action_type       = vc
        2 action_label      = vc
    1 debug[*]
        2 event_id     = f8
        2 title        = vc
        2 event_dt_tm  = vc
        2 authored_by  = vc
        2 source_type  = vc
        2 blob_length  = i4
        2 text_length  = i4
        2 status       = vc
        2 reason       = vc
)

DECLARE dCnt            = i4 WITH NOCONSTANT(0)
DECLARE nCnt            = i4 WITH NOCONSTANT(0)
DECLARE i               = i4 WITH NOCONSTANT(0)
DECLARE iFilter         = i4 WITH NOCONSTANT(0)
DECLARE iDisplayedCount      = i4 WITH NOCONSTANT(0)
DECLARE iDroppedCount        = i4 WITH NOCONSTANT(0)
DECLARE iNoteCount           = i4 WITH NOCONSTANT(0)
DECLARE iStickyCount         = i4 WITH NOCONSTANT(0)
DECLARE iHighRiskCount       = i4 WITH NOCONSTANT(0)
DECLARE iCandidateAllEventCount = i4 WITH NOCONSTANT(0)
DECLARE iCandidateNoteCount     = i4 WITH NOCONSTANT(0)
DECLARE iCandidateBlobCount     = i4 WITH NOCONSTANT(0)
DECLARE iCandidateStickyCount   = i4 WITH NOCONSTANT(0)

DECLARE OcfCD           = f8 WITH NOCONSTANT(0.0)
DECLARE docClassCd      = f8 WITH NOCONSTANT(0.0)
DECLARE formClassCd     = f8 WITH NOCONSTANT(0.0)
DECLARE authStatusCd    = f8 WITH NOCONSTANT(0.0)
DECLARE modifiedStatusCd = f8 WITH NOCONSTANT(0.0)
DECLARE stat            = i4 WITH NOCONSTANT(0)
DECLARE stat_rtf        = i4 WITH NOCONSTANT(0)
DECLARE tlen            = i4 WITH NOCONSTANT(0)
DECLARE bsize           = i4 WITH NOCONSTANT(0)
DECLARE totlen          = i4 WITH NOCONSTANT(0)
DECLARE bloblen         = i4 WITH NOCONSTANT(0)
DECLARE out_len         = i4 WITH NOCONSTANT(0)
DECLARE rtf_idx         = i4 WITH NOCONSTANT(0)
DECLARE blob_in         = vc WITH NOCONSTANT(" ")
DECLARE blob_out        = vc WITH NOCONSTANT(" ")
DECLARE rtf_out         = vc WITH NOCONSTANT(" ")
DECLARE vCleanText      = vc WITH NOCONSTANT(" ")
DECLARE sLowerText      = vc WITH NOCONSTANT(" ")
DECLARE sHighRiskLabels = vc WITH NOCONSTANT(" ")

SET reply->status.code = "error"
SET reply->status.message = "Patient ID is required."
SET reply->meta.module = "01_meds_pharm_search:group1"
SET reply->meta.title = "Chart Search"
SET reply->meta.patient_id = CNVTREAL($pid)
SET reply->meta.encntr_id = CNVTREAL($eid)
SET reply->meta.search_scope = "patient"
SET reply->meta.lookback_days = 730
SET reply->meta.result_count = 0
SET reply->meta.encounter_scoped = 0

IF (CNVTREAL($pid) > 0)
    SET stat = UAR_GET_MEANING_BY_CODESET(120, "OCFCOMP", 1, OcfCD)
    SET docClassCd = UAR_GET_CODE_BY("MEANING", 53, "DOC")
    SET formClassCd = UAR_GET_CODE_BY("MEANING", 53, "FORM")
    SET authStatusCd = UAR_GET_CODE_BY("MEANING", 8, "AUTH")
    SET modifiedStatusCd = UAR_GET_CODE_BY("MEANING", 8, "MODIFIED")

    SET reply->meta.doc_class_cd = docClassCd
    SET reply->meta.form_class_cd = formClassCd
    SET reply->meta.auth_status_cd = authStatusCd
    SET reply->meta.modified_status_cd = modifiedStatusCd

    SELECT INTO "NL:"
    FROM CLINICAL_EVENT CE
    PLAN CE WHERE CE.PERSON_ID = CNVTREAL($pid)
        AND CE.EVENT_END_DT_TM >= CNVTDATETIME(CURDATE-730, CURTIME3)
        AND CE.VALID_UNTIL_DT_TM > CNVTDATETIME(CURDATE, CURTIME3)
    DETAIL
        iCandidateAllEventCount = iCandidateAllEventCount + 1
    WITH NOCOUNTER, FORMAT, UR

    SELECT INTO "NL:"
    FROM CLINICAL_EVENT CE
    PLAN CE WHERE CE.PERSON_ID = CNVTREAL($pid)
        AND CE.EVENT_END_DT_TM >= CNVTDATETIME(CURDATE-730, CURTIME3)
        AND CE.VALID_UNTIL_DT_TM > CNVTDATETIME(CURDATE, CURTIME3)
        AND CE.EVENT_CLASS_CD IN (
            VALUE(docClassCd),
            VALUE(formClassCd)
        )
        AND CE.RESULT_STATUS_CD IN (
            VALUE(authStatusCd),
            VALUE(modifiedStatusCd)
        )
    DETAIL
        iCandidateNoteCount = iCandidateNoteCount + 1
    WITH NOCOUNTER, FORMAT, UR

    SELECT INTO "NL:"
    FROM CLINICAL_EVENT CE
        , CE_BLOB CB
    PLAN CE WHERE CE.PERSON_ID = CNVTREAL($pid)
        AND CE.EVENT_END_DT_TM >= CNVTDATETIME(CURDATE-730, CURTIME3)
        AND CE.VALID_UNTIL_DT_TM > CNVTDATETIME(CURDATE, CURTIME3)
        AND CE.EVENT_CLASS_CD IN (
            VALUE(docClassCd),
            VALUE(formClassCd)
        )
        AND CE.RESULT_STATUS_CD IN (
            VALUE(authStatusCd),
            VALUE(modifiedStatusCd)
        )
    JOIN CB WHERE CB.EVENT_ID = CE.EVENT_ID
        AND CB.VALID_UNTIL_DT_TM > CNVTDATETIME(CURDATE, CURTIME3)
    DETAIL
        iCandidateBlobCount = iCandidateBlobCount + 1
    WITH NOCOUNTER, FORMAT, UR

    SELECT INTO "NL:"
    FROM STICKY_NOTE SN
    PLAN SN WHERE SN.PARENT_ENTITY_ID = CNVTREAL($pid)
        AND SN.PARENT_ENTITY_NAME = "PERSON"
        AND SN.BEG_EFFECTIVE_DT_TM <= CNVTDATETIME(CURDATE, CURTIME3)
        AND SN.END_EFFECTIVE_DT_TM > CNVTDATETIME(CURDATE, CURTIME3)
    DETAIL
        iCandidateStickyCount = iCandidateStickyCount + 1
    WITH NOCOUNTER, FORMAT, UR

    IF (RUN_NOTES = 1)
        SELECT INTO "NL:"
        FROM CLINICAL_EVENT CE
            , CE_BLOB CB
            , CLINICAL_EVENT PARENT_CE
            , PRSNL PR
        PLAN CE WHERE CE.PERSON_ID = CNVTREAL($pid)
            AND CE.EVENT_END_DT_TM >= CNVTDATETIME(CURDATE-730, CURTIME3)
            AND CE.VALID_UNTIL_DT_TM > CNVTDATETIME(CURDATE, CURTIME3)
            AND CE.EVENT_CLASS_CD IN (
                VALUE(docClassCd),
                VALUE(formClassCd)
            )
            AND CE.RESULT_STATUS_CD IN (
                VALUE(authStatusCd),
                VALUE(modifiedStatusCd)
            )
        JOIN CB WHERE CB.EVENT_ID = CE.EVENT_ID
            AND CB.VALID_UNTIL_DT_TM > CNVTDATETIME(CURDATE, CURTIME3)
        JOIN PARENT_CE WHERE PARENT_CE.EVENT_ID = OUTERJOIN(CE.PARENT_EVENT_ID)
        JOIN PR WHERE PR.PERSON_ID = OUTERJOIN(CE.VERIFIED_PRSNL_ID)
        ORDER BY CE.EVENT_END_DT_TM DESC

        DETAIL
            vCleanText = " "
            bloblen = 0
            tlen = 0
            bsize = 0
            rtf_idx = 0
            out_len = 0

            IF (CB.EVENT_ID > 0 AND CB.VALID_UNTIL_DT_TM > CNVTDATETIME(CURDATE, CURTIME3))
                bloblen = BLOBGETLEN(CB.BLOB_CONTENTS)
                IF (bloblen > 0)
                    out_len = CB.BLOB_LENGTH
                    IF (out_len < bloblen)
                        out_len = bloblen
                    ENDIF

                    stat = MEMREALLOC(blob_in, 1, BUILD("C", bloblen))
                    totlen = BLOBGET(blob_in, 0, CB.BLOB_CONTENTS)
                    stat = MEMREALLOC(blob_out, 1, BUILD("C", out_len))

                    IF (CB.COMPRESSION_CD = OcfCD)
                        CALL UAR_OCF_UNCOMPRESS(blob_in, TEXTLEN(blob_in), blob_out, out_len, tlen)
                    ELSE
                        blob_out = blob_in
                        tlen = TEXTLEN(blob_out)
                    ENDIF

                    IF (tlen > 0)
                        rtf_idx = FINDSTRING("{\rtf", CNVTLOWER(blob_out), 1, 0)
                        IF (rtf_idx > 0)
                            blob_out = SUBSTRING(rtf_idx, tlen - rtf_idx + 1, blob_out)
                            tlen = TEXTLEN(blob_out)
                            stat = MEMREALLOC(rtf_out, 1, BUILD("C", out_len))
                            blob_out = REPLACE(blob_out, "\line", "\par", 0)
                            tlen = TEXTLEN(blob_out)
                            stat_rtf = UAR_RTF2(blob_out, tlen, rtf_out, out_len, bsize, 0)
                            vCleanText = REPLACE(SUBSTRING(1, bsize, rtf_out), CHAR(0), " ", 0)
                        ELSE
                            vCleanText = blob_out
                        ENDIF
                    ENDIF
                ENDIF
            ELSEIF (CE.EVENT_CLASS_CD != VALUE(UAR_GET_CODE_BY("MEANING", 53, "DOC")) AND CE.EVENT_CLASS_CD != VALUE(formClassCd))
                vCleanText = TRIM(CE.RESULT_VAL, 3)
            ELSE
                vCleanText = ""
            ENDIF

            IF (TEXTLEN(TRIM(vCleanText, 3)) > 1)
                vCleanText = REPLACE(vCleanText, CONCAT(CHAR(13), CHAR(10)), CHAR(10), 0)
                vCleanText = REPLACE(vCleanText, CHAR(13), CHAR(10), 0)
                vCleanText = TRIM(vCleanText, 3)

                nCnt = SIZE(rec_docs->list, 5) + 1
                stat = ALTERLIST(rec_docs->list, nCnt)

                rec_docs->list[nCnt].category = "Notes"
                rec_docs->list[nCnt].source_type = UAR_GET_CODE_DISPLAY(CE.EVENT_CLASS_CD)
                rec_docs->list[nCnt].event_id = CE.EVENT_ID

                IF (PARENT_CE.EVENT_ID > 0 AND TRIM(PARENT_CE.EVENT_TITLE_TEXT, 3) != "")
                    rec_docs->list[nCnt].title = TRIM(PARENT_CE.EVENT_TITLE_TEXT, 3)
                ELSEIF (TRIM(CE.EVENT_TITLE_TEXT, 3) != "")
                    rec_docs->list[nCnt].title = TRIM(CE.EVENT_TITLE_TEXT, 3)
                ELSE
                    rec_docs->list[nCnt].title = UAR_GET_CODE_DISPLAY(CE.EVENT_CD)
                ENDIF

                rec_docs->list[nCnt].dt_tm = REPLACE(FORMAT(CE.EVENT_END_DT_TM, "DD/MM/YYYY HH:MM"), " 00:00", "", 0)

                IF (PR.PERSON_ID > 0)
                    rec_docs->list[nCnt].prsnl = TRIM(PR.NAME_FULL_FORMATTED, 3)
                ELSE
                    rec_docs->list[nCnt].prsnl = "System Process"
                ENDIF

                rec_docs->list[nCnt].doc_text = vCleanText
            ENDIF

            dCnt = SIZE(rec_debug->list, 5) + 1
            stat = ALTERLIST(rec_debug->list, dCnt)
            rec_debug->list[dCnt].event_id = CE.EVENT_ID
            rec_debug->list[dCnt].blob_len = bloblen
            rec_debug->list[dCnt].text_len = TEXTLEN(TRIM(vCleanText, 3))
            rec_debug->list[dCnt].source_type = UAR_GET_CODE_DISPLAY(CE.EVENT_CLASS_CD)
            rec_debug->list[dCnt].dt_tm = REPLACE(FORMAT(CE.EVENT_END_DT_TM, "DD/MM/YYYY HH:MM"), " 00:00", "", 0)

            IF (PARENT_CE.EVENT_ID > 0 AND TRIM(PARENT_CE.EVENT_TITLE_TEXT, 3) != "")
                rec_debug->list[dCnt].title = TRIM(PARENT_CE.EVENT_TITLE_TEXT, 3)
            ELSEIF (TRIM(CE.EVENT_TITLE_TEXT, 3) != "")
                rec_debug->list[dCnt].title = TRIM(CE.EVENT_TITLE_TEXT, 3)
            ELSE
                rec_debug->list[dCnt].title = UAR_GET_CODE_DISPLAY(CE.EVENT_CD)
            ENDIF

            IF (PR.PERSON_ID > 0)
                rec_debug->list[dCnt].prsnl = TRIM(PR.NAME_FULL_FORMATTED, 3)
            ELSE
                rec_debug->list[dCnt].prsnl = "System Process"
            ENDIF

            IF (TEXTLEN(TRIM(vCleanText, 3)) > 1)
                rec_debug->list[dCnt].status = "DISPLAYED"
                rec_debug->list[dCnt].reason = ""
            ELSEIF (bloblen = 0)
                rec_debug->list[dCnt].status = "DROPPED"
                rec_debug->list[dCnt].reason = "Zero blob length"
            ELSEIF (tlen = 0)
                rec_debug->list[dCnt].status = "DROPPED"
                rec_debug->list[dCnt].reason = "Decompress/extract 0 bytes"
            ELSE
                rec_debug->list[dCnt].status = "DROPPED"
                rec_debug->list[dCnt].reason = "Empty after processing"
            ENDIF
        WITH NOCOUNTER, FORMAT, UR, MAXREC = 150
    ENDIF

    IF (RUN_STICKY = 1)
        SELECT INTO "NL:"
        FROM STICKY_NOTE SN
            , PRSNL P
        PLAN SN WHERE SN.PARENT_ENTITY_ID = CNVTREAL($pid)
            AND SN.PARENT_ENTITY_NAME = "PERSON"
            AND SN.BEG_EFFECTIVE_DT_TM <= CNVTDATETIME(CURDATE, CURTIME3)
            AND SN.END_EFFECTIVE_DT_TM > CNVTDATETIME(CURDATE, CURTIME3)
        JOIN P WHERE P.PERSON_ID = OUTERJOIN(SN.UPDT_ID)
        ORDER BY SN.BEG_EFFECTIVE_DT_TM DESC

        DETAIL
            vCleanText = TRIM(SN.STICKY_NOTE_TEXT, 3)
            vCleanText = REPLACE(vCleanText, CONCAT(CHAR(13), CHAR(10)), CHAR(10), 0)
            vCleanText = REPLACE(vCleanText, CHAR(13), CHAR(10), 0)

            nCnt = SIZE(rec_docs->list, 5) + 1
            stat = ALTERLIST(rec_docs->list, nCnt)

            rec_docs->list[nCnt].category = "Sticky Notes"
            rec_docs->list[nCnt].source_type = "STICKY NOTE"
            rec_docs->list[nCnt].event_id = SN.STICKY_NOTE_ID
            rec_docs->list[nCnt].title = "Patient Sticky Note"
            rec_docs->list[nCnt].dt_tm = REPLACE(FORMAT(SN.BEG_EFFECTIVE_DT_TM, "DD/MM/YYYY HH:MM"), " 00:00", "", 0)

            IF (P.PERSON_ID > 0)
                rec_docs->list[nCnt].prsnl = TRIM(P.NAME_FULL_FORMATTED, 3)
            ELSE
                rec_docs->list[nCnt].prsnl = "System Process"
            ENDIF

            rec_docs->list[nCnt].doc_text = vCleanText

            dCnt = SIZE(rec_debug->list, 5) + 1
            stat = ALTERLIST(rec_debug->list, dCnt)
            rec_debug->list[dCnt].event_id = SN.STICKY_NOTE_ID
            rec_debug->list[dCnt].title = "Patient Sticky Note"
            rec_debug->list[dCnt].dt_tm = REPLACE(FORMAT(SN.BEG_EFFECTIVE_DT_TM, "DD/MM/YYYY HH:MM"), " 00:00", "", 0)
            rec_debug->list[dCnt].source_type = "STICKY NOTE"
            rec_debug->list[dCnt].blob_len = 0
            rec_debug->list[dCnt].text_len = TEXTLEN(TRIM(SN.STICKY_NOTE_TEXT, 3))
            rec_debug->list[dCnt].status = "DISPLAYED"
            rec_debug->list[dCnt].reason = ""

            IF (P.PERSON_ID > 0)
                rec_debug->list[dCnt].prsnl = TRIM(P.NAME_FULL_FORMATTED, 3)
            ELSE
                rec_debug->list[dCnt].prsnl = "System Process"
            ENDIF
        WITH NOCOUNTER, FORMAT, UR, MAXREC = 50
    ENDIF

    FOR (i = 1 TO SIZE(rec_docs->list, 5))
        SET reply->meta.result_count = reply->meta.result_count + 1
        SET reply->summary.total_results = reply->summary.total_results + 1
        SET stat = ALTERLIST(reply->results, reply->meta.result_count)

        SET sLowerText = CNVTLOWER(rec_docs->list[i].doc_text)
        SET sHighRiskLabels = ""
        SET iHighRiskCount = 0

        IF (
            FINDSTRING("tinzaparin", sLowerText, 1, 0) > 0 OR
            FINDSTRING("enoxaparin", sLowerText, 1, 0) > 0 OR
            FINDSTRING("dalteparin", sLowerText, 1, 0) > 0 OR
            FINDSTRING("heparin", sLowerText, 1, 0) > 0 OR
            FINDSTRING("fragmin", sLowerText, 1, 0) > 0 OR
            FINDSTRING("innohep", sLowerText, 1, 0) > 0 OR
            FINDSTRING("clexane", sLowerText, 1, 0) > 0
        )
            SET iHighRiskCount = iHighRiskCount + 1
            SET sHighRiskLabels = "LMWH"
        ENDIF

        IF (
            FINDSTRING("warfarin", sLowerText, 1, 0) > 0 OR
            FINDSTRING("apixaban", sLowerText, 1, 0) > 0 OR
            FINDSTRING("rivaroxaban", sLowerText, 1, 0) > 0 OR
            FINDSTRING("dabigatran", sLowerText, 1, 0) > 0 OR
            FINDSTRING("edoxaban", sLowerText, 1, 0) > 0 OR
            FINDSTRING("coumadin", sLowerText, 1, 0) > 0 OR
            FINDSTRING("xarelto", sLowerText, 1, 0) > 0 OR
            FINDSTRING("eliquis", sLowerText, 1, 0) > 0 OR
            FINDSTRING("pradaxa", sLowerText, 1, 0) > 0 OR
            FINDSTRING("lixiana", sLowerText, 1, 0) > 0
        )
            SET iHighRiskCount = iHighRiskCount + 1
            IF (sHighRiskLabels = "")
                SET sHighRiskLabels = "ANTICOAG"
            ELSE
                SET sHighRiskLabels = BUILD2(sHighRiskLabels, ",ANTICOAG")
            ENDIF
        ENDIF

        IF (
            FINDSTRING("valproate", sLowerText, 1, 0) > 0 OR
            FINDSTRING("sodium valproate", sLowerText, 1, 0) > 0 OR
            FINDSTRING("valproic", sLowerText, 1, 0) > 0 OR
            FINDSTRING("epilim", sLowerText, 1, 0) > 0 OR
            FINDSTRING("depakote", sLowerText, 1, 0) > 0 OR
            FINDSTRING("convulex", sLowerText, 1, 0) > 0
        )
            SET iHighRiskCount = iHighRiskCount + 1
            IF (sHighRiskLabels = "")
                SET sHighRiskLabels = "VALPROATE"
            ELSE
                SET sHighRiskLabels = BUILD2(sHighRiskLabels, ",VALPROATE")
            ENDIF
        ENDIF

        IF (FINDSTRING("topiramate", sLowerText, 1, 0) > 0 OR FINDSTRING("topamax", sLowerText, 1, 0) > 0)
            SET iHighRiskCount = iHighRiskCount + 1
            IF (sHighRiskLabels = "")
                SET sHighRiskLabels = "TOPIRAMATE"
            ELSE
                SET sHighRiskLabels = BUILD2(sHighRiskLabels, ",TOPIRAMATE")
            ENDIF
        ENDIF

        IF (
            FINDSTRING("levetiracetam", sLowerText, 1, 0) > 0 OR
            FINDSTRING("carbamazepine", sLowerText, 1, 0) > 0 OR
            FINDSTRING("phenytoin", sLowerText, 1, 0) > 0 OR
            FINDSTRING("lamotrigine", sLowerText, 1, 0) > 0 OR
            FINDSTRING("keppra", sLowerText, 1, 0) > 0 OR
            FINDSTRING("tegretol", sLowerText, 1, 0) > 0 OR
            FINDSTRING("epanutin", sLowerText, 1, 0) > 0 OR
            FINDSTRING("lamictal", sLowerText, 1, 0) > 0 OR
            FINDSTRING("phenobarbitone", sLowerText, 1, 0) > 0 OR
            FINDSTRING("phenobarbital", sLowerText, 1, 0) > 0
        )
            SET iHighRiskCount = iHighRiskCount + 1
            IF (sHighRiskLabels = "")
                SET sHighRiskLabels = "AED"
            ELSE
                SET sHighRiskLabels = BUILD2(sHighRiskLabels, ",AED")
            ENDIF
        ENDIF

        IF (
            FINDSTRING("methotrexate", sLowerText, 1, 0) > 0 OR
            FINDSTRING("azathioprine", sLowerText, 1, 0) > 0 OR
            FINDSTRING("mycophenolate", sLowerText, 1, 0) > 0 OR
            FINDSTRING("ciclosporin", sLowerText, 1, 0) > 0 OR
            FINDSTRING("tacrolimus", sLowerText, 1, 0) > 0 OR
            FINDSTRING("sirolimus", sLowerText, 1, 0) > 0 OR
            FINDSTRING("everolimus", sLowerText, 1, 0) > 0 OR
            FINDSTRING("imurel", sLowerText, 1, 0) > 0 OR
            FINDSTRING("cellcept", sLowerText, 1, 0) > 0 OR
            FINDSTRING("neoral", sLowerText, 1, 0) > 0 OR
            FINDSTRING("prograf", sLowerText, 1, 0) > 0
        )
            SET iHighRiskCount = iHighRiskCount + 1
            IF (sHighRiskLabels = "")
                SET sHighRiskLabels = "IMMUNOSUPP"
            ELSE
                SET sHighRiskLabels = BUILD2(sHighRiskLabels, ",IMMUNOSUPP")
            ENDIF
        ENDIF

        IF (
            FINDSTRING("lithium", sLowerText, 1, 0) > 0 OR
            FINDSTRING("priadel", sLowerText, 1, 0) > 0 OR
            FINDSTRING("liskonum", sLowerText, 1, 0) > 0
        )
            SET iHighRiskCount = iHighRiskCount + 1
            IF (sHighRiskLabels = "")
                SET sHighRiskLabels = "LITHIUM"
            ELSE
                SET sHighRiskLabels = BUILD2(sHighRiskLabels, ",LITHIUM")
            ENDIF
        ENDIF

        IF (
            FINDSTRING("clozapine", sLowerText, 1, 0) > 0 OR
            FINDSTRING("clozaril", sLowerText, 1, 0) > 0 OR
            FINDSTRING("denzapine", sLowerText, 1, 0) > 0
        )
            SET iHighRiskCount = iHighRiskCount + 1
            IF (sHighRiskLabels = "")
                SET sHighRiskLabels = "CLOZAPINE"
            ELSE
                SET sHighRiskLabels = BUILD2(sHighRiskLabels, ",CLOZAPINE")
            ENDIF
        ENDIF

        IF (
            FINDSTRING("isotretinoin", sLowerText, 1, 0) > 0 OR
            FINDSTRING("roaccutane", sLowerText, 1, 0) > 0 OR
            FINDSTRING("accutane", sLowerText, 1, 0) > 0
        )
            SET iHighRiskCount = iHighRiskCount + 1
            IF (sHighRiskLabels = "")
                SET sHighRiskLabels = "ISOTRET"
            ELSE
                SET sHighRiskLabels = BUILD2(sHighRiskLabels, ",ISOTRET")
            ENDIF
        ENDIF

        IF (
            FINDSTRING("thalidomide", sLowerText, 1, 0) > 0 OR
            FINDSTRING("lenalidomide", sLowerText, 1, 0) > 0 OR
            FINDSTRING("pomalidomide", sLowerText, 1, 0) > 0 OR
            FINDSTRING("revlimid", sLowerText, 1, 0) > 0 OR
            FINDSTRING("imnovid", sLowerText, 1, 0) > 0
        )
            SET iHighRiskCount = iHighRiskCount + 1
            IF (sHighRiskLabels = "")
                SET sHighRiskLabels = "THALID"
            ELSE
                SET sHighRiskLabels = BUILD2(sHighRiskLabels, ",THALID")
            ENDIF
        ENDIF

        IF (FINDSTRING("amiodarone", sLowerText, 1, 0) > 0 OR FINDSTRING("cordarone", sLowerText, 1, 0) > 0)
            SET iHighRiskCount = iHighRiskCount + 1
            IF (sHighRiskLabels = "")
                SET sHighRiskLabels = "AMIODARONE"
            ELSE
                SET sHighRiskLabels = BUILD2(sHighRiskLabels, ",AMIODARONE")
            ENDIF
        ENDIF

        IF (FINDSTRING("digoxin", sLowerText, 1, 0) > 0 OR FINDSTRING("lanoxin", sLowerText, 1, 0) > 0)
            SET iHighRiskCount = iHighRiskCount + 1
            IF (sHighRiskLabels = "")
                SET sHighRiskLabels = "DIGOXIN"
            ELSE
                SET sHighRiskLabels = BUILD2(sHighRiskLabels, ",DIGOXIN")
            ENDIF
        ENDIF

        IF (
            FINDSTRING("insulin", sLowerText, 1, 0) > 0 OR
            FINDSTRING("novorapid", sLowerText, 1, 0) > 0 OR
            FINDSTRING("lantus", sLowerText, 1, 0) > 0 OR
            FINDSTRING("humalog", sLowerText, 1, 0) > 0 OR
            FINDSTRING("levemir", sLowerText, 1, 0) > 0 OR
            FINDSTRING("tresiba", sLowerText, 1, 0) > 0 OR
            FINDSTRING("toujeo", sLowerText, 1, 0) > 0 OR
            FINDSTRING("apidra", sLowerText, 1, 0) > 0 OR
            FINDSTRING("humulin", sLowerText, 1, 0) > 0 OR
            FINDSTRING("mixtard", sLowerText, 1, 0) > 0 OR
            FINDSTRING("novomix", sLowerText, 1, 0) > 0
        )
            SET iHighRiskCount = iHighRiskCount + 1
            IF (sHighRiskLabels = "")
                SET sHighRiskLabels = "INSULIN"
            ELSE
                SET sHighRiskLabels = BUILD2(sHighRiskLabels, ",INSULIN")
            ENDIF
        ENDIF

        IF (rec_docs->list[i].category = "Notes")
            SET iNoteCount = iNoteCount + 1
            SET reply->summary.notes = iNoteCount
        ELSEIF (rec_docs->list[i].category = "Sticky Notes")
            SET iStickyCount = iStickyCount + 1
            SET reply->summary.sticky_notes = iStickyCount
        ENDIF

        SET reply->results[reply->meta.result_count].result_index = reply->meta.result_count
        SET reply->results[reply->meta.result_count].event_id = rec_docs->list[i].event_id
        SET reply->results[reply->meta.result_count].category = rec_docs->list[i].category
        SET reply->results[reply->meta.result_count].source_type = rec_docs->list[i].source_type
        SET reply->results[reply->meta.result_count].title = rec_docs->list[i].title
        SET reply->results[reply->meta.result_count].event_dt_tm = rec_docs->list[i].dt_tm
        SET reply->results[reply->meta.result_count].authored_by = rec_docs->list[i].prsnl
        SET reply->results[reply->meta.result_count].doc_text = rec_docs->list[i].doc_text
        SET reply->results[reply->meta.result_count].text_length = TEXTLEN(TRIM(rec_docs->list[i].doc_text, 3))
        SET reply->results[reply->meta.result_count].high_risk_labels = sHighRiskLabels
        SET reply->results[reply->meta.result_count].high_risk_count = iHighRiskCount
        SET reply->results[reply->meta.result_count].action_type = "view_document"
        SET reply->results[reply->meta.result_count].action_label = "View Document"
    ENDFOR

    FOR (i = 1 TO SIZE(rec_debug->list, 5))
        SET stat = ALTERLIST(reply->debug, i)
        SET reply->debug[i].event_id = rec_debug->list[i].event_id
        SET reply->debug[i].title = rec_debug->list[i].title
        SET reply->debug[i].event_dt_tm = rec_debug->list[i].dt_tm
        SET reply->debug[i].authored_by = rec_debug->list[i].prsnl
        SET reply->debug[i].source_type = rec_debug->list[i].source_type
        SET reply->debug[i].blob_length = rec_debug->list[i].blob_len
        SET reply->debug[i].text_length = rec_debug->list[i].text_len
        SET reply->debug[i].status = rec_debug->list[i].status
        SET reply->debug[i].reason = rec_debug->list[i].reason

        IF (rec_debug->list[i].status = "DISPLAYED")
            SET iDisplayedCount = iDisplayedCount + 1
        ELSE
            SET iDroppedCount = iDroppedCount + 1
        ENDIF
    ENDFOR

    SET reply->summary.displayed_debug = iDisplayedCount
    SET reply->summary.dropped_debug = iDroppedCount
    SET reply->summary.candidate_all_events = iCandidateAllEventCount
    SET reply->summary.candidate_note_events = iCandidateNoteCount
    SET reply->summary.candidate_note_payloads = iCandidateBlobCount
    SET reply->summary.candidate_sticky_notes = iCandidateStickyCount

    SET stat = ALTERLIST(reply->filters, 6)

    SET reply->filters[1].filter_type = "category"
    SET reply->filters[1].code = "ALL"
    SET reply->filters[1].label = "All"
    SET reply->filters[1].count = reply->meta.result_count
    SET reply->filters[1].days = 0
    SET reply->filters[1].is_default = 1

    SET reply->filters[2].filter_type = "category"
    SET reply->filters[2].code = "Notes"
    SET reply->filters[2].label = "Notes"
    SET reply->filters[2].count = iNoteCount
    SET reply->filters[2].days = 0
    SET reply->filters[2].is_default = 0

    SET reply->filters[3].filter_type = "category"
    SET reply->filters[3].code = "Sticky Notes"
    SET reply->filters[3].label = "Sticky Notes"
    SET reply->filters[3].count = iStickyCount
    SET reply->filters[3].days = 0
    SET reply->filters[3].is_default = 0

    SET reply->filters[4].filter_type = "date_range"
    SET reply->filters[4].code = "ALL"
    SET reply->filters[4].label = "All Time"
    SET reply->filters[4].count = reply->meta.result_count
    SET reply->filters[4].days = 0
    SET reply->filters[4].is_default = 1

    SET reply->filters[5].filter_type = "date_range"
    SET reply->filters[5].code = "7"
    SET reply->filters[5].label = "Last 7 Days"
    SET reply->filters[5].count = 0
    SET reply->filters[5].days = 7
    SET reply->filters[5].is_default = 0

    SET reply->filters[6].filter_type = "date_range"
    SET reply->filters[6].code = "30"
    SET reply->filters[6].label = "Last 30 Days"
    SET reply->filters[6].count = 0
    SET reply->filters[6].days = 30
    SET reply->filters[6].is_default = 0

    IF (reply->meta.result_count > 0)
        SET reply->status.code = "success"
        SET reply->status.message = "Chart Search data loaded."
    ELSE
        SET reply->status.code = "no_results"
        IF (iCandidateNoteCount > 0 AND iCandidateBlobCount = 0)
            SET reply->status.message = "No chart documents found after strict payload filtering."
        ELSEIF (iCandidateBlobCount > 0)
            SET reply->status.message = "Candidate chart documents were found but produced no displayable text."
        ELSE
            SET reply->status.message = "No chart documents found."
        ENDIF
    ENDIF
ENDIF

SET _memory_reply_string = CNVTRECTOJSON(reply)

FREE RECORD rec_debug
FREE RECORD rec_docs
END GO





