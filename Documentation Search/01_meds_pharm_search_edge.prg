/**
 * PROGRAM: 01_meds_pharm_search_edge
 *
 * ARCHITECTURE: 
 * Edge/WebView2 compatible read-only XCR extraction for global chart search.
 * Extracts Clinical Notes, iView narrative, Sticky Notes, and PowerForms.
 * SAFETIES: Implements the "Golden Query" strict payload extraction and Parent Title resolution.
 */

DROP PROGRAM 01_meds_pharm_search_edge GO
CREATE PROGRAM 01_meds_pharm_search_edge

PROMPT
    "Output to File/Printer/MINE" = "MINE"
    , "User Id"      = 0
    , "Patient ID"   = 0
    , "Encounter Id" = 0
    , "Cache Buster" = 0.0   ; Safely absorbs the raw Edge JS timestamp as a float
WITH OUTDEV, user_id, patient_id, encounter_id, cache_buster

; =============================================================================
; CONFIGURATION TOGGLES
; =============================================================================
DECLARE RUN_STICKY     = i2 WITH noconstant(1)
DECLARE RUN_NOTES      = i2 WITH noconstant(1)
DECLARE RUN_FORMS      = i2 WITH noconstant(0) ; Disabled - forms now route safely via Notes
DECLARE RUN_IVIEW_TEXT = i2 WITH noconstant(0) ; 0 = Hide TXT/STG/LT, 1 = Show

; =============================================================================
; 1. RECORD STRUCTURE & DECLARATIONS
; =============================================================================
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
    2 status      = vc   ; "DISPLAYED" or "DROPPED"
    2 reason      = vc
)

DECLARE dCnt       = i4  WITH noconstant(0)

DECLARE OcfCD      = f8  WITH noconstant(0.0)
DECLARE stat       = i4  WITH noconstant(0)
DECLARE stat_rtf   = i4  WITH noconstant(0)
DECLARE tlen       = i4  WITH noconstant(0)
DECLARE bsize      = i4  WITH noconstant(0)
DECLARE totlen     = i4  WITH noconstant(0)
DECLARE bloblen    = i4  WITH noconstant(0)
DECLARE out_len    = i4  WITH noconstant(0)
DECLARE nCnt       = i4  WITH noconstant(0)
DECLARE x          = i4  WITH noconstant(0)
DECLARE rtf_idx    = i4  WITH noconstant(0)
DECLARE vLen       = i4  WITH noconstant(0)
DECLARE bsz        = i4  WITH noconstant(0)
DECLARE blob_in    = vc  WITH noconstant(" ")
DECLARE blob_out   = vc  WITH noconstant(" ")
DECLARE rtf_out    = vc  WITH noconstant(" ")
DECLARE vCleanText = vc  WITH noconstant(" ")

SET stat = uar_get_meaning_by_codeset(120, "OCFCOMP", 1, OcfCD)

; =============================================================================
; 2. EXTRACT CLINICAL NOTES & POWERFORMS (STRICT INNER JOIN)
; =============================================================================
IF (RUN_NOTES = 1)
    SELECT INTO "NL:"
    FROM CLINICAL_EVENT CE
        , CE_BLOB CB           ; Removed OUTERJOIN to enforce strict payload requirement
        , CLINICAL_EVENT PARENT_CE
        , PRSNL PR
    PLAN CE WHERE CE.PERSON_ID = CNVTREAL($patient_id)
        AND CE.EVENT_END_DT_TM >= CNVTDATETIME(CURDATE-730, CURTIME3)
        AND CE.VALID_UNTIL_DT_TM > CNVTDATETIME(CURDATE, CURTIME3)
        AND CE.EVENT_CLASS_CD IN (
            VALUE(UAR_GET_CODE_BY("MEANING", 53, "DOC")),
            VALUE(UAR_GET_CODE_BY("MEANING", 53, "FORM"))
        )
        AND CE.RESULT_STATUS_CD IN (
            VALUE(UAR_GET_CODE_BY("MEANING", 8, "AUTH")),
            VALUE(UAR_GET_CODE_BY("MEANING", 8, "MODIFIED"))
        )
    /* This INNER JOIN is the magic filter: No Blob = No Result */
    JOIN CB WHERE CB.EVENT_ID = CE.EVENT_ID 
        AND CB.VALID_UNTIL_DT_TM > CNVTDATETIME(CURDATE, CURTIME3)
    JOIN PARENT_CE WHERE PARENT_CE.EVENT_ID = OUTERJOIN(CE.PARENT_EVENT_ID)
    JOIN PR WHERE PR.PERSON_ID = OUTERJOIN(CE.VERIFIED_PRSNL_ID)
    ORDER BY CE.EVENT_END_DT_TM DESC

    DETAIL
        vCleanText = " "

        ; STRICT BLOB FILTERING - Drops discrete question fragments
        IF (CB.EVENT_ID > 0 AND CB.VALID_UNTIL_DT_TM > CNVTDATETIME(CURDATE, CURTIME3))
            bloblen = blobgetlen(CB.BLOB_CONTENTS)
            IF (bloblen > 0)
                tlen = 0
                bsize = 0
                rtf_idx = 0
                out_len = CB.BLOB_LENGTH
                IF (out_len < bloblen)
                    out_len = bloblen
                ENDIF
                
                stat = memrealloc(blob_in, 1, build("C", bloblen))
                totlen = blobget(blob_in, 0, CB.BLOB_CONTENTS)
                stat = memrealloc(blob_out, 1, build("C", out_len))
                
                IF (CB.COMPRESSION_CD = OcfCD)
                    call uar_ocf_uncompress(blob_in, textlen(blob_in), blob_out, out_len, tlen)
                ELSE
                    blob_out = blob_in
                    tlen = TEXTLEN(blob_out)
                ENDIF

                IF (tlen > 0)
                    rtf_idx = FINDSTRING("{\rtf", cnvtlower(blob_out), 1, 0)
                    IF (rtf_idx > 0)
                        blob_out = SUBSTRING(rtf_idx, tlen - rtf_idx + 1, blob_out)
                        tlen = TEXTLEN(blob_out)
                        stat = memrealloc(rtf_out, 1, build("C", out_len))
                        blob_out = REPLACE(blob_out, "\line", "\par", 0)
                        tlen = TEXTLEN(blob_out)
                        stat_rtf = uar_rtf2(blob_out, tlen, rtf_out, out_len, bsize, 0)
                        vCleanText = REPLACE(SUBSTRING(1, bsize, rtf_out), CHAR(0), " ", 0)
                    ELSEIF (FINDSTRING("<html", cnvtlower(blob_out), 1, 0) > 0 OR FINDSTRING("<xml", cnvtlower(blob_out), 1, 0) > 0)
                        vCleanText = blob_out
                    ELSE
                        vCleanText = blob_out
                    ENDIF
                ENDIF
            ENDIF
        ELSEIF (CE.EVENT_CLASS_CD != VALUE(UAR_GET_CODE_BY("MEANING", 53, "DOC")) AND CE.EVENT_CLASS_CD != VALUE(UAR_GET_CODE_BY("MEANING", 53, "FORM")))
            ; Only iView TXT/STG classes are permitted to use RESULT_VAL
            vCleanText = TRIM(CE.RESULT_VAL, 3)
        ELSE
            ; If it is a DOC without a blob, it is a fragment. Force it empty.
            vCleanText = ""
        ENDIF

        ; ONLY POPULATE ARRAY IF A VALID PAYLOAD EXISTS
        IF (TEXTLEN(TRIM(vCleanText)) > 1)
            vCleanText = REPLACE(vCleanText, "&", "&amp;", 0)
            vCleanText = REPLACE(vCleanText, "<", "&lt;",  0)
            vCleanText = REPLACE(vCleanText, ">", "&gt;",  0)
            vCleanText = REPLACE(vCleanText, concat(CHAR(13), CHAR(10)), "<br />", 0)
            vCleanText = REPLACE(vCleanText, CHAR(13), "<br />", 0)
            vCleanText = REPLACE(vCleanText, CHAR(10), "<br />", 0)
            vCleanText = TRIM(vCleanText, 3)

            nCnt = size(rec_docs->list, 5) + 1
            stat = alterlist(rec_docs->list, nCnt)
            
            rec_docs->list[nCnt].category    = "Notes"
            rec_docs->list[nCnt].source_type = UAR_GET_CODE_DISPLAY(CE.EVENT_CLASS_CD)
            rec_docs->list[nCnt].event_id    = CE.EVENT_ID
            
            ; TITLE RESOLUTION: Steal the clean MDOC parent title if it exists
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

        ; ---- DEBUG CAPTURE (Notes) ----
        dCnt = size(rec_debug->list, 5) + 1
        stat = alterlist(rec_debug->list, dCnt)
        rec_debug->list[dCnt].event_id    = CE.EVENT_ID
        rec_debug->list[dCnt].blob_len    = bloblen
        rec_debug->list[dCnt].text_len    = TEXTLEN(TRIM(vCleanText))
        rec_debug->list[dCnt].source_type = UAR_GET_CODE_DISPLAY(CE.EVENT_CLASS_CD)
        rec_debug->list[dCnt].dt_tm       = REPLACE(FORMAT(CE.EVENT_END_DT_TM, "DD/MM/YYYY HH:MM"), " 00:00", "", 0)

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

        IF (TEXTLEN(TRIM(vCleanText)) > 1)
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

; =============================================================================
; 3. EXTRACT STICKY NOTES
; =============================================================================
IF (RUN_STICKY = 1)
    SELECT INTO "NL:"
    FROM STICKY_NOTE SN
        , PRSNL P
    PLAN SN WHERE SN.PARENT_ENTITY_ID = CNVTREAL($patient_id)
        AND SN.PARENT_ENTITY_NAME = "PERSON"
        AND SN.BEG_EFFECTIVE_DT_TM <= CNVTDATETIME(CURDATE, CURTIME3)
        AND SN.END_EFFECTIVE_DT_TM > CNVTDATETIME(CURDATE, CURTIME3)
    JOIN P WHERE P.PERSON_ID = OUTERJOIN(SN.UPDT_ID)
    ORDER BY SN.BEG_EFFECTIVE_DT_TM DESC

    DETAIL
        nCnt = size(rec_docs->list, 5) + 1
        stat = alterlist(rec_docs->list, nCnt)
        
        rec_docs->list[nCnt].category    = "Sticky Notes"
        rec_docs->list[nCnt].source_type = "STICKY NOTE"
        rec_docs->list[nCnt].event_id    = SN.STICKY_NOTE_ID
        rec_docs->list[nCnt].title       = "Patient Sticky Note"
        rec_docs->list[nCnt].dt_tm       = REPLACE(FORMAT(SN.BEG_EFFECTIVE_DT_TM, "DD/MM/YYYY HH:MM"), " 00:00", "", 0)
        
        IF (P.PERSON_ID > 0)
            rec_docs->list[nCnt].prsnl   = TRIM(P.NAME_FULL_FORMATTED, 3)
        ELSE
            rec_docs->list[nCnt].prsnl   = "System Process"
        ENDIF

        vCleanText = TRIM(SN.STICKY_NOTE_TEXT, 3)
        vCleanText = REPLACE(vCleanText, "&", "&amp;", 0)
        vCleanText = REPLACE(vCleanText, "<", "&lt;",  0)
        vCleanText = REPLACE(vCleanText, ">", "&gt;",  0)
        vCleanText = REPLACE(vCleanText, concat(CHAR(13), CHAR(10)), "<br />", 0)
        vCleanText = REPLACE(vCleanText, CHAR(13), "<br />", 0)
        vCleanText = REPLACE(vCleanText, CHAR(10), "<br />", 0)
        rec_docs->list[nCnt].doc_text = vCleanText

        ; ---- DEBUG CAPTURE (Sticky Note - always displayed) ----
        dCnt = size(rec_debug->list, 5) + 1
        stat = alterlist(rec_debug->list, dCnt)
        rec_debug->list[dCnt].event_id    = SN.STICKY_NOTE_ID
        rec_debug->list[dCnt].title       = "Patient Sticky Note"
        rec_debug->list[dCnt].dt_tm       = REPLACE(FORMAT(SN.BEG_EFFECTIVE_DT_TM, "DD/MM/YYYY HH:MM"), " 00:00", "", 0)
        rec_debug->list[dCnt].source_type = "STICKY NOTE"
        rec_debug->list[dCnt].blob_len    = 0
        rec_debug->list[dCnt].text_len    = TEXTLEN(TRIM(SN.STICKY_NOTE_TEXT, 3))
        rec_debug->list[dCnt].status      = "DISPLAYED"
        rec_debug->list[dCnt].reason      = ""
        IF (P.PERSON_ID > 0)
            rec_debug->list[dCnt].prsnl = TRIM(P.NAME_FULL_FORMATTED, 3)
        ELSE
            rec_debug->list[dCnt].prsnl = "System Process"
        ENDIF

    WITH NOCOUNTER, FORMAT, UR, MAXREC = 50
ENDIF

; =============================================================================
; 5. HTML OUTPUT VIA _memory_reply_string (BUILD2 APPLIED)
; =============================================================================
DECLARE v_doc_cnt_str = vc WITH noconstant("")
SET v_doc_cnt_str = TRIM(CNVTSTRING(SIZE(rec_docs->list, 5)))

SET _memory_reply_string = ""

SET _memory_reply_string = BUILD2(_memory_reply_string, "<!DOCTYPE html><html lang='en'><head><meta charset='utf-8'/>")
SET _memory_reply_string = BUILD2(_memory_reply_string, "<style>")
SET _memory_reply_string = BUILD2(_memory_reply_string, "*, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }")
SET _memory_reply_string = BUILD2(_memory_reply_string, "html, body { height: 100%; overflow: hidden; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; }")
SET _memory_reply_string = BUILD2(_memory_reply_string, ".gp-container { display: flex; flex-direction: column; height: 100vh; }")
SET _memory_reply_string = BUILD2(_memory_reply_string, ".search-header { padding: 12px; background: #f4f6f8; border-bottom: 1px solid #ddd; display: flex; flex-direction: column; gap: 8px; }")
SET _memory_reply_string = BUILD2(_memory_reply_string, ".search-row-1, .search-row-2 { display: flex; align-items: center; gap: 10px; }")
SET _memory_reply_string = BUILD2(_memory_reply_string, ".search-wrapper { position: relative; display: inline-flex; align-items: center; }")
SET _memory_reply_string = BUILD2(_memory_reply_string, ".search-box { padding: 6px 30px 6px 10px; width: 350px; border: 1px solid #ccc; border-radius: 3px; font-size: 13px; }")
SET _memory_reply_string = BUILD2(_memory_reply_string, ".search-box:focus { border-color: #006f99; outline: none; }")
SET _memory_reply_string = BUILD2(_memory_reply_string, ".clear-btn { position: absolute; right: 8px; background: transparent; border: none; font-size: 18px; font-weight: bold; color: #999; cursor: pointer; display: none; line-height: 1; padding: 0; }")
SET _memory_reply_string = BUILD2(_memory_reply_string, ".clear-btn:hover { color: #333; }")
SET _memory_reply_string = BUILD2(_memory_reply_string, ".filter-pill { padding: 4px 10px; font-size: 11px; border: 1px solid #ccc; border-radius: 12px; background: #fff; color: #555; cursor: pointer; user-select: none; }")
SET _memory_reply_string = BUILD2(_memory_reply_string, ".filter-pill.active { background: #006f99; color: #fff; border-color: #004c66; font-weight: 600; }")
SET _memory_reply_string = BUILD2(_memory_reply_string, ".date-dropdown { padding: 4px 6px; font-size: 11px; border: 1px solid #ccc; border-radius: 3px; outline: none; }")
SET _memory_reply_string = BUILD2(_memory_reply_string, ".workspace { display: flex; flex: 1; overflow: hidden; position: relative; }")
SET _memory_reply_string = BUILD2(_memory_reply_string, ".sidebar { width: 300px; background: #fafafa; border-right: 1px solid #ddd; overflow-y: auto; }")
SET _memory_reply_string = BUILD2(_memory_reply_string, ".doc-item { padding: 10px 12px; border-bottom: 1px solid #eee; cursor: pointer; }")
SET _memory_reply_string = BUILD2(_memory_reply_string, ".doc-item:hover { background: #e2e6ea; }")
SET _memory_reply_string = BUILD2(_memory_reply_string, ".doc-item.active { background: #006f99; color: #fff; }")
SET _memory_reply_string = BUILD2(_memory_reply_string, ".doc-item.hidden { display: none !important; }")
SET _memory_reply_string = BUILD2(_memory_reply_string, ".doc-meta { font-size: 11px; color: #666; margin-bottom: 3px; }")
SET _memory_reply_string = BUILD2(_memory_reply_string, ".doc-item.active .doc-meta { color: #cce4f0; }")
SET _memory_reply_string = BUILD2(_memory_reply_string, ".doc-title { font-size: 13px; font-weight: 600; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }")
SET _memory_reply_string = BUILD2(_memory_reply_string, ".nav-flags { display: flex; gap: 3px; margin-top: 4px; flex-wrap: wrap; }")
SET _memory_reply_string = BUILD2(_memory_reply_string, ".nav-flag-highrisk { font-size: 9px; padding: 1px 4px; border-radius: 3px; font-weight: 700; background: #fde8e8; color: #c0392b; border: 1px solid #f5c6c6; }")
SET _memory_reply_string = BUILD2(_memory_reply_string, ".viewer-container { flex: 1; display: flex; flex-direction: column; overflow: hidden; background: #fff; }")
SET _memory_reply_string = BUILD2(_memory_reply_string, ".match-nav { padding: 8px 15px; background: #e2f0f5; border-bottom: 1px solid #b3d4e0; display: flex; align-items: center; gap: 10px; font-size: 12px; }")
SET _memory_reply_string = BUILD2(_memory_reply_string, ".nav-btn { background: #fff; border: 1px solid #006f99; color: #006f99; border-radius: 3px; padding: 2px 8px; cursor: pointer; }")
SET _memory_reply_string = BUILD2(_memory_reply_string, ".viewer { flex: 1; padding: 20px; overflow-y: auto; line-height: 1.5; font-size: 13px; }")
SET _memory_reply_string = BUILD2(_memory_reply_string, "mark.search-match { background: #ffeb3b; color: #000; padding: 0 2px; border-radius: 2px; }")
SET _memory_reply_string = BUILD2(_memory_reply_string, "mark.active-match { background: #ff9800; border: 1px solid #e65100; color: #fff; }")
SET _memory_reply_string = BUILD2(_memory_reply_string, ".type-badge { display: inline-block; font-size: 9px; padding: 1px 4px; border-radius: 3px; background: #e0e0e0; color: #333; margin-right: 5px; }")
SET _memory_reply_string = BUILD2(_memory_reply_string, "</style></head><body>")

SET _memory_reply_string = BUILD2(_memory_reply_string, "<div class='gp-container'>")
SET _memory_reply_string = BUILD2(_memory_reply_string, "  <div class='search-header'>")
SET _memory_reply_string = BUILD2(_memory_reply_string, "    <div class='search-row-1'>")
SET _memory_reply_string = BUILD2(_memory_reply_string, "      <div class='search-wrapper'>")
SET _memory_reply_string = BUILD2(_memory_reply_string, "        <input type='text' id='search-input' class='search-box' placeholder='Search ", v_doc_cnt_str, " chart documents...'>")
SET _memory_reply_string = BUILD2(_memory_reply_string, "        <button id='clear-btn' class='clear-btn' title='Clear search'>&times;</button>")
SET _memory_reply_string = BUILD2(_memory_reply_string, "      </div>")
SET _memory_reply_string = BUILD2(_memory_reply_string, "      <span id='result-count' style='font-size: 12px; color: #666;'></span>")
SET _memory_reply_string = BUILD2(_memory_reply_string, "    </div>")
SET _memory_reply_string = BUILD2(_memory_reply_string, "    <div class='search-row-2'>")
SET _memory_reply_string = BUILD2(_memory_reply_string, "      <select id='date-filter' class='date-dropdown'>")
SET _memory_reply_string = BUILD2(_memory_reply_string, "        <option value='ALL'>All Time</option><option value='7'>Last 7 Days</option><option value='30'>Last 30 Days</option>")
SET _memory_reply_string = BUILD2(_memory_reply_string, "      </select>")
SET _memory_reply_string = BUILD2(_memory_reply_string, "      <span class='filter-pill active' data-val='ALL'>All</span>")
SET _memory_reply_string = BUILD2(_memory_reply_string, "      <span class='filter-pill' data-val='Notes'>Notes</span>")
SET _memory_reply_string = BUILD2(_memory_reply_string, "      <span class='filter-pill' data-val='Sticky Notes'>Sticky Notes</span>")
SET _memory_reply_string = BUILD2(_memory_reply_string, "    </div>")
SET _memory_reply_string = BUILD2(_memory_reply_string, "  </div>")
SET _memory_reply_string = BUILD2(_memory_reply_string, "  <div class='workspace'>")
SET _memory_reply_string = BUILD2(_memory_reply_string, "    <div class='sidebar' id='sidebar-list'>")

SET x = 1
WHILE (x <= SIZE(rec_docs->list, 5))
    SET _memory_reply_string = BUILD2(_memory_reply_string, 
        "<div class='doc-item' data-idx='", TRIM(CNVTSTRING(x)), "' data-cat='", rec_docs->list[x].category, "' data-dt='", rec_docs->list[x].dt_tm, "'>",
        "<div class='doc-meta'>", rec_docs->list[x].dt_tm, " | ", rec_docs->list[x].prsnl, "</div>",
        "<div class='doc-title'><span class='type-badge'>", rec_docs->list[x].source_type, "</span><span class='raw-title'>", rec_docs->list[x].title, "</span></div>",
        "</div>")
    SET x = x + 1
ENDWHILE

SET _memory_reply_string = BUILD2(_memory_reply_string, "    </div>")
SET _memory_reply_string = BUILD2(_memory_reply_string, "    <div class='viewer-container'>")
SET _memory_reply_string = BUILD2(_memory_reply_string, "      <div id='match-nav-bar' class='match-nav' style='display:none;'>")
SET _memory_reply_string = BUILD2(_memory_reply_string, "        <span><b id='match-idx'>0</b> of <span id='match-total'>0</span> matches</span>")
SET _memory_reply_string = BUILD2(_memory_reply_string, "        <button id='btn-prev-match' class='nav-btn'>&uparrow;</button>")
SET _memory_reply_string = BUILD2(_memory_reply_string, "        <button id='btn-next-match' class='nav-btn'>&downarrow;</button>")
SET _memory_reply_string = BUILD2(_memory_reply_string, "      </div>")
SET _memory_reply_string = BUILD2(_memory_reply_string, "      <div class='viewer' id='doc-viewer'><p style='color:#888; text-align:center; margin-top:40px;'>Select a document or type to search.</p></div>")
SET _memory_reply_string = BUILD2(_memory_reply_string, "    </div>")

SET _memory_reply_string = BUILD2(_memory_reply_string, "<div id='raw-data-store' style='display:none;'>")
SET x = 1
WHILE (x <= SIZE(rec_docs->list, 5))
    SET _memory_reply_string = BUILD2(_memory_reply_string, "<div id='raw-", TRIM(CNVTSTRING(x)), "'>")
    SET vLen = TEXTLEN(rec_docs->list[x].doc_text)
    SET bsz = 1
    WHILE (bsz <= vLen)
        SET _memory_reply_string = BUILD2(_memory_reply_string, SUBSTRING(bsz, 500, rec_docs->list[x].doc_text))
        SET bsz = bsz + 500
    ENDWHILE
    SET _memory_reply_string = BUILD2(_memory_reply_string, "</div>")
    SET x = x + 1
ENDWHILE
SET _memory_reply_string = BUILD2(_memory_reply_string, "</div></div></div>")

SET _memory_reply_string = BUILD2(_memory_reply_string, "<script>")
SET _memory_reply_string = BUILD2(_memory_reply_string, "var totalDocs = ", v_doc_cnt_str, "; var currentMatchIdx = -1; var matchElements = [];")
SET _memory_reply_string = BUILD2(_memory_reply_string, "var activeDocType = 'ALL'; var activeDateRange = 'ALL';")

SET _memory_reply_string = BUILD2(_memory_reply_string, "var HIGH_RISK_MEDS = [")
SET _memory_reply_string = BUILD2(_memory_reply_string, "{ label: 'LMWH', terms: ['tinzaparin','enoxaparin','dalteparin','heparin','fragmin','innohep','clexane'] },")
SET _memory_reply_string = BUILD2(_memory_reply_string, "{ label: 'ANTICOAG', terms: ['warfarin','apixaban','rivaroxaban','dabigatran','edoxaban','coumadin','xarelto','eliquis','pradaxa','lixiana'] },")
SET _memory_reply_string = BUILD2(_memory_reply_string, "{ label: 'VALPROATE', terms: ['valproate','sodium valproate','valproic','epilim','depakote','convulex'] },")
SET _memory_reply_string = BUILD2(_memory_reply_string, "{ label: 'TOPIRAMATE', terms: ['topiramate','topamax'] },")
SET _memory_reply_string = BUILD2(_memory_reply_string, "{ label: 'AED', terms: ['levetiracetam','carbamazepine','phenytoin','lamotrigine','keppra','tegretol','epanutin','lamictal','phenobarbitone','phenobarbital'] },")
SET _memory_reply_string = BUILD2(_memory_reply_string, "{ label: 'IMMUNOSUPP', terms: ['methotrexate','azathioprine','mycophenolate','ciclosporin','tacrolimus','sirolimus','everolimus','imurel','cellcept','neoral','prograf'] },")
SET _memory_reply_string = BUILD2(_memory_reply_string, "{ label: 'LITHIUM', terms: ['lithium','priadel','liskonum'] },")
SET _memory_reply_string = BUILD2(_memory_reply_string, "{ label: 'CLOZAPINE', terms: ['clozapine','clozaril','denzapine'] },")
SET _memory_reply_string = BUILD2(_memory_reply_string, "{ label: 'ISOTRET', terms: ['isotretinoin','roaccutane','accutane'] },")
SET _memory_reply_string = BUILD2(_memory_reply_string, "{ label: 'THALID', terms: ['thalidomide','lenalidomide','pomalidomide','revlimid','imnovid'] },")
SET _memory_reply_string = BUILD2(_memory_reply_string, "{ label: 'AMIODARONE', terms: ['amiodarone','cordarone'] },")
SET _memory_reply_string = BUILD2(_memory_reply_string, "{ label: 'DIGOXIN', terms: ['digoxin','lanoxin'] },")
SET _memory_reply_string = BUILD2(_memory_reply_string, "{ label: 'INSULIN', terms: ['insulin','novorapid','lantus','humalog','levemir','tresiba','toujeo','apidra','humulin','mixtard','novomix'] }")
SET _memory_reply_string = BUILD2(_memory_reply_string, "];")

SET _memory_reply_string = BUILD2(_memory_reply_string, "function buildHighRiskFlags() {")
SET _memory_reply_string = BUILD2(_memory_reply_string, "  for (var i=1; i<=totalDocs; i++){")
SET _memory_reply_string = BUILD2(_memory_reply_string, ~    var nav = document.querySelector(".doc-item[data-idx='" + i + "']"); if(!nav) continue;~)
SET _memory_reply_string = BUILD2(_memory_reply_string, "    var raw = document.getElementById('raw-'+i); if(!raw) continue;")
SET _memory_reply_string = BUILD2(_memory_reply_string, "    var text = (raw.textContent||raw.innerText||'').toLowerCase();")
SET _memory_reply_string = BUILD2(_memory_reply_string, "    var hits = [];")
SET _memory_reply_string = BUILD2(_memory_reply_string, "    for(var g=0; g<HIGH_RISK_MEDS.length; g++) {")
SET _memory_reply_string = BUILD2(_memory_reply_string, "      for(var t=0; t<HIGH_RISK_MEDS[g].terms.length; t++) {")
SET _memory_reply_string = BUILD2(_memory_reply_string, "        if(text.indexOf(HIGH_RISK_MEDS[g].terms[t]) > -1) { hits.push(HIGH_RISK_MEDS[g].label); break; }")
SET _memory_reply_string = BUILD2(_memory_reply_string, "      }")
SET _memory_reply_string = BUILD2(_memory_reply_string, "    }")
SET _memory_reply_string = BUILD2(_memory_reply_string, "    if(!hits.length) continue;")
SET _memory_reply_string = BUILD2(_memory_reply_string, "    var flags = document.createElement('div'); flags.className = 'nav-flags';")
SET _memory_reply_string = BUILD2(_memory_reply_string, "    for(var h=0; h<hits.length; h++){")
SET _memory_reply_string = BUILD2(_memory_reply_string, "      var sp = document.createElement('span'); sp.className='nav-flag-highrisk'; sp.textContent=hits[h]; flags.appendChild(sp);")
SET _memory_reply_string = BUILD2(_memory_reply_string, "    } nav.appendChild(flags);")
SET _memory_reply_string = BUILD2(_memory_reply_string, "  }")
SET _memory_reply_string = BUILD2(_memory_reply_string, "}")

SET _memory_reply_string = BUILD2(_memory_reply_string, "function filterDocs() {")
SET _memory_reply_string = BUILD2(_memory_reply_string, "  var term = document.getElementById('search-input').value.toLowerCase().trim();")
SET _memory_reply_string = BUILD2(_memory_reply_string, "  var matchCount = 0; var now = new Date();")
SET _memory_reply_string = BUILD2(_memory_reply_string, "  for(var i=1; i<=totalDocs; i++) {")
SET _memory_reply_string = BUILD2(_memory_reply_string, ~    var navItem = document.querySelector(".doc-item[data-idx='" + i + "']"); if(!navItem) continue;~)
SET _memory_reply_string = BUILD2(_memory_reply_string, "    var typeMatch = (activeDocType === 'ALL' || activeDocType === navItem.getAttribute('data-cat'));")
SET _memory_reply_string = BUILD2(_memory_reply_string, "    var dateMatch = true;")
SET _memory_reply_string = BUILD2(_memory_reply_string, "    if(activeDateRange !== 'ALL') {")
SET _memory_reply_string = BUILD2(_memory_reply_string, "      var parts = navItem.getAttribute('data-dt').split(' ')[0].split('/');")
SET _memory_reply_string = BUILD2(_memory_reply_string, "      var docDt = new Date(parts[2], parts[1]-1, parts[0]);")
SET _memory_reply_string = BUILD2(_memory_reply_string, "      var diffDays = (now - docDt) / 86400000;")
SET _memory_reply_string = BUILD2(_memory_reply_string, "      if(activeDateRange === '7' && diffDays > 7) dateMatch = false;")
SET _memory_reply_string = BUILD2(_memory_reply_string, "      if(activeDateRange === '30' && diffDays > 30) dateMatch = false;")
SET _memory_reply_string = BUILD2(_memory_reply_string, "    }")
SET _memory_reply_string = BUILD2(_memory_reply_string, "    var textMatch = false;")
SET _memory_reply_string = BUILD2(_memory_reply_string, "    if(term === '') textMatch = true; else {")
SET _memory_reply_string = BUILD2(_memory_reply_string, "      var rawText = document.getElementById('raw-' + i).innerText.toLowerCase();")
SET _memory_reply_string = BUILD2(_memory_reply_string, "      if(rawText.indexOf(term) > -1 || navItem.innerText.toLowerCase().indexOf(term) > -1) textMatch = true;")
SET _memory_reply_string = BUILD2(_memory_reply_string, "    }")
SET _memory_reply_string = BUILD2(_memory_reply_string, "    if(typeMatch && dateMatch && textMatch) { navItem.classList.remove('hidden'); matchCount++; }")
SET _memory_reply_string = BUILD2(_memory_reply_string, "    else { navItem.classList.add('hidden'); }")
SET _memory_reply_string = BUILD2(_memory_reply_string, "  }")
SET _memory_reply_string = BUILD2(_memory_reply_string, "  document.getElementById('result-count').innerText = term === '' ? '' : matchCount + ' matches';")
SET _memory_reply_string = BUILD2(_memory_reply_string, "  document.getElementById('clear-btn').style.display = term === '' ? 'none' : 'block';")
SET _memory_reply_string = BUILD2(_memory_reply_string, "}")

SET _memory_reply_string = BUILD2(_memory_reply_string, "function highlightCurrentMatch() {")
SET _memory_reply_string = BUILD2(_memory_reply_string, "  matchElements.forEach(function(m) { m.classList.remove('active-match'); });")
SET _memory_reply_string = BUILD2(_memory_reply_string, "  if(matchElements[currentMatchIdx]) {")
SET _memory_reply_string = BUILD2(_memory_reply_string, "    matchElements[currentMatchIdx].classList.add('active-match');")
SET _memory_reply_string = BUILD2(_memory_reply_string, "    matchElements[currentMatchIdx].scrollIntoView({behavior: 'smooth', block: 'center'});")
SET _memory_reply_string = BUILD2(_memory_reply_string, "    document.getElementById('match-idx').innerText = (currentMatchIdx + 1);")
SET _memory_reply_string = BUILD2(_memory_reply_string, "  }")
SET _memory_reply_string = BUILD2(_memory_reply_string, "}")

SET _memory_reply_string = BUILD2(_memory_reply_string, "function viewDoc(idx) {")
SET _memory_reply_string = BUILD2(_memory_reply_string, "  document.querySelectorAll('.doc-item').forEach(function(el) { el.classList.remove('active'); });")
SET _memory_reply_string = BUILD2(_memory_reply_string, ~  var navItem = document.querySelector(".doc-item[data-idx='" + idx + "']");~)
SET _memory_reply_string = BUILD2(_memory_reply_string, "  if(navItem) { navItem.classList.add('active'); }")
SET _memory_reply_string = BUILD2(_memory_reply_string, "  var rawText = document.getElementById('raw-' + idx).innerHTML;")
SET _memory_reply_string = BUILD2(_memory_reply_string, "  var term = document.getElementById('search-input').value.trim();")
SET _memory_reply_string = BUILD2(_memory_reply_string, "  if(term.length > 0) {")
SET _memory_reply_string = BUILD2(_memory_reply_string, "    var safeTerm = '';")
SET _memory_reply_string = BUILD2(_memory_reply_string, "    for(var i=0; i<term.length; i++) {")
SET _memory_reply_string = BUILD2(_memory_reply_string, "      var c = term.charAt(i); var code = c.charCodeAt(0);")
SET _memory_reply_string = BUILD2(_memory_reply_string, "      if ([46,42,43,63,94,36,123,125,40,41,124,91,93,92].indexOf(code) > -1) { safeTerm += String.fromCharCode(92) + c; } else { safeTerm += c; }")
SET _memory_reply_string = BUILD2(_memory_reply_string, "    }")
SET _memory_reply_string = BUILD2(_memory_reply_string, "    var re = new RegExp('(' + safeTerm + ')', 'gi');")
SET _memory_reply_string = BUILD2(_memory_reply_string, ~    rawText = rawText.replace(re, '<mark class="search-match">$1</mark>');~)
SET _memory_reply_string = BUILD2(_memory_reply_string, "  }")
SET _memory_reply_string = BUILD2(_memory_reply_string, "  document.getElementById('doc-viewer').innerHTML = rawText;")
SET _memory_reply_string = BUILD2(_memory_reply_string, "  matchElements = document.getElementById('doc-viewer').querySelectorAll('.search-match');")
SET _memory_reply_string = BUILD2(_memory_reply_string, "  var navBar = document.getElementById('match-nav-bar');")
SET _memory_reply_string = BUILD2(_memory_reply_string, "  if(matchElements.length > 0) {")
SET _memory_reply_string = BUILD2(_memory_reply_string, "    navBar.style.display = 'flex';")
SET _memory_reply_string = BUILD2(_memory_reply_string, "    document.getElementById('match-total').innerText = matchElements.length;")
SET _memory_reply_string = BUILD2(_memory_reply_string, "    currentMatchIdx = 0; highlightCurrentMatch();")
SET _memory_reply_string = BUILD2(_memory_reply_string, "  } else { navBar.style.display = 'none'; }")
SET _memory_reply_string = BUILD2(_memory_reply_string, "}")

SET _memory_reply_string = BUILD2(_memory_reply_string, "document.getElementById('sidebar-list').addEventListener('click', function(e) {")
SET _memory_reply_string = BUILD2(_memory_reply_string, "  var item = e.target.closest('.doc-item'); if (item) viewDoc(item.getAttribute('data-idx'));")
SET _memory_reply_string = BUILD2(_memory_reply_string, "});")

SET _memory_reply_string = BUILD2(_memory_reply_string, "document.getElementById('search-input').addEventListener('input', function() { filterDocs(); });")

SET _memory_reply_string = BUILD2(_memory_reply_string, "document.getElementById('clear-btn').addEventListener('click', function() {")
SET _memory_reply_string = BUILD2(_memory_reply_string, "  var input = document.getElementById('search-input'); input.value = ''; input.dispatchEvent(new Event('input')); input.focus();")
SET _memory_reply_string = BUILD2(_memory_reply_string, "});")

SET _memory_reply_string = BUILD2(_memory_reply_string, "document.getElementById('date-filter').addEventListener('change', function(e) {")
SET _memory_reply_string = BUILD2(_memory_reply_string, "  activeDateRange = e.target.value; filterDocs();")
SET _memory_reply_string = BUILD2(_memory_reply_string, "});")

SET _memory_reply_string = BUILD2(_memory_reply_string, "document.querySelectorAll('.filter-pill').forEach(function(pill) {")
SET _memory_reply_string = BUILD2(_memory_reply_string, "  pill.addEventListener('click', function(e) {")
SET _memory_reply_string = BUILD2(_memory_reply_string, "    document.querySelectorAll('.filter-pill').forEach(function(p) { p.classList.remove('active'); });")
SET _memory_reply_string = BUILD2(_memory_reply_string, "    e.target.classList.add('active');")
SET _memory_reply_string = BUILD2(_memory_reply_string, "    activeDocType = e.target.getAttribute('data-val');")
SET _memory_reply_string = BUILD2(_memory_reply_string, "    filterDocs();")
SET _memory_reply_string = BUILD2(_memory_reply_string, "  });")
SET _memory_reply_string = BUILD2(_memory_reply_string, "});")

SET _memory_reply_string = BUILD2(_memory_reply_string, "document.getElementById('btn-prev-match').addEventListener('click', function() {")
SET _memory_reply_string = BUILD2(_memory_reply_string, "  if(currentMatchIdx > 0) currentMatchIdx--; else currentMatchIdx = matchElements.length - 1;")
SET _memory_reply_string = BUILD2(_memory_reply_string, "  highlightCurrentMatch();")
SET _memory_reply_string = BUILD2(_memory_reply_string, "});")

SET _memory_reply_string = BUILD2(_memory_reply_string, "document.getElementById('btn-next-match').addEventListener('click', function() {")
SET _memory_reply_string = BUILD2(_memory_reply_string, "  if(currentMatchIdx < matchElements.length - 1) currentMatchIdx++; else currentMatchIdx = 0;")
SET _memory_reply_string = BUILD2(_memory_reply_string, "  highlightCurrentMatch();")
SET _memory_reply_string = BUILD2(_memory_reply_string, "});")

SET _memory_reply_string = BUILD2(_memory_reply_string, "buildHighRiskFlags();")
SET _memory_reply_string = BUILD2(_memory_reply_string, "</script>")

; =============================================================================
; 6. DEBUG PANEL
; =============================================================================
DECLARE vDbgDisplayed = i4 WITH noconstant(0)
DECLARE vDbgDropped   = i4 WITH noconstant(0)
DECLARE vDbgTotal     = i4 WITH noconstant(0)
SET vDbgTotal = SIZE(rec_debug->list, 5)

SET x = 1
WHILE (x <= vDbgTotal)
    IF (rec_debug->list[x].status = "DISPLAYED")
        SET vDbgDisplayed = vDbgDisplayed + 1
    ELSE
        SET vDbgDropped = vDbgDropped + 1
    ENDIF
    SET x = x + 1
ENDWHILE

SET _memory_reply_string = BUILD2(_memory_reply_string,
    "<div id='dbg-panel' style='position:fixed;bottom:0;left:0;right:0;font-family:monospace;font-size:11px;z-index:9999;max-height:22px;overflow:hidden;transition:max-height 0.3s ease;'>",
    "<div id='dbg-bar' style='padding:3px 10px;background:#333;color:#d4d4d4;cursor:pointer;display:flex;justify-content:space-between;align-items:center;user-select:none;'",
    ~ onclick="var p=document.getElementById('dbg-panel');var expanded=p.style.maxHeight~,
    ~!=='22px';p.style.maxHeight=expanded?'22px':'42vh';document.getElementById('dbg-caret')~,
    ~.textContent=expanded?String.fromCharCode(9650):String.fromCharCode(9660);">~,
    "<span>",
    "&#x1F50D; DEBUG &nbsp;|&nbsp; <b style='color:#4ec94e;'>", TRIM(CNVTSTRING(vDbgDisplayed)), " displayed</b>",
    " &nbsp;|&nbsp; <b style='color:#f48771;'>", TRIM(CNVTSTRING(vDbgDropped)), " dropped</b>",
    " &nbsp;|&nbsp; ", TRIM(CNVTSTRING(vDbgTotal)), " reached DETAIL",
    " &nbsp;|&nbsp; <span style='color:#9cdcfe;'>Pat:</span> ", TRIM(CNVTSTRING($patient_id, 14, 0)),
    " &nbsp;<span style='color:#9cdcfe;'>Enc:</span> ", TRIM(CNVTSTRING($encounter_id, 14, 0)),
    " &nbsp;<span style='color:#9cdcfe;'>Usr:</span> ", TRIM(CNVTSTRING($user_id, 14, 0)),
    "</span>",
    "<span style='display:flex;align-items:center;gap:8px;'>",
    "<button id='dbg-copy' style='font-size:10px;padding:1px 7px;background:#444;color:#ccc;",
    "border:1px solid #666;border-radius:3px;cursor:pointer;font-family:monospace;'>Copy</button>",
    "<span id='dbg-caret' style='font-size:9px;color:#888;'>&#x25B2;</span>",
    "</span></div>",
    "<div style='overflow-y:auto;max-height:calc(42vh - 22px);background:#1e1e1e;'>",
    "<table style='width:100%;border-collapse:collapse;color:#d4d4d4;'>",
    "<thead><tr style='background:#252526;position:sticky;top:0;'>",
    "<th style='padding:4px 8px;text-align:left;border-bottom:1px solid #444;white-space:nowrap;'>Event ID</th>",
    "<th style='padding:4px 8px;text-align:left;border-bottom:1px solid #444;'>Title</th>",
    "<th style='padding:4px 8px;text-align:left;border-bottom:1px solid #444;white-space:nowrap;'>Date</th>",
    "<th style='padding:4px 8px;text-align:left;border-bottom:1px solid #444;'>Author</th>",
    "<th style='padding:4px 8px;text-align:left;border-bottom:1px solid #444;'>Class</th>",
    "<th style='padding:4px 8px;text-align:right;border-bottom:1px solid #444;'>Blob</th>",
    "<th style='padding:4px 8px;text-align:right;border-bottom:1px solid #444;'>Text</th>",
    "<th style='padding:4px 8px;text-align:left;border-bottom:1px solid #444;'>Status</th>",
    "<th style='padding:4px 8px;text-align:left;border-bottom:1px solid #444;'>Reason</th>",
    "</tr></thead><tbody>")

SET x = 1
WHILE (x <= vDbgTotal)
    IF (rec_debug->list[x].status = "DISPLAYED")
        SET _memory_reply_string = BUILD2(_memory_reply_string, "<tr style='background:#1a2b1a;'>")
    ELSE
        SET _memory_reply_string = BUILD2(_memory_reply_string, "<tr style='background:#2b1a1a;'>")
    ENDIF

    SET _memory_reply_string = BUILD2(_memory_reply_string,
        "<td style='padding:3px 8px;border-bottom:1px solid #2a2a2a;color:#9cdcfe;white-space:nowrap;'>",
            TRIM(CNVTSTRING(rec_debug->list[x].event_id, 14, 0)), "</td>",
        "<td style='padding:3px 8px;border-bottom:1px solid #2a2a2a;max-width:220px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;' title='",
            rec_debug->list[x].title, "'>", rec_debug->list[x].title, "</td>",
        "<td style='padding:3px 8px;border-bottom:1px solid #2a2a2a;white-space:nowrap;'>", rec_debug->list[x].dt_tm, "</td>",
        "<td style='padding:3px 8px;border-bottom:1px solid #2a2a2a;white-space:nowrap;'>", rec_debug->list[x].prsnl, "</td>",
        "<td style='padding:3px 8px;border-bottom:1px solid #2a2a2a;'>", rec_debug->list[x].source_type, "</td>",
        "<td style='padding:3px 8px;border-bottom:1px solid #2a2a2a;text-align:right;'>",
            TRIM(CNVTSTRING(rec_debug->list[x].blob_len)), "</td>",
        "<td style='padding:3px 8px;border-bottom:1px solid #2a2a2a;text-align:right;'>",
            TRIM(CNVTSTRING(rec_debug->list[x].text_len)), "</td>")

    IF (rec_debug->list[x].status = "DISPLAYED")
        SET _memory_reply_string = BUILD2(_memory_reply_string,
            "<td style='padding:3px 8px;border-bottom:1px solid #2a2a2a;color:#4ec94e;font-weight:bold;'>DISPLAYED</td>")
    ELSE
        SET _memory_reply_string = BUILD2(_memory_reply_string,
            "<td style='padding:3px 8px;border-bottom:1px solid #2a2a2a;color:#f48771;font-weight:bold;'>DROPPED</td>")
    ENDIF

    SET _memory_reply_string = BUILD2(_memory_reply_string,
        "<td style='padding:3px 8px;border-bottom:1px solid #2a2a2a;color:#ce9178;'>",
            rec_debug->list[x].reason, "</td>",
        "</tr>")

    SET x = x + 1
ENDWHILE

SET _memory_reply_string = BUILD2(_memory_reply_string, "</tbody></table></div></div>")

SET _memory_reply_string = BUILD2(_memory_reply_string, "<script>")
SET _memory_reply_string = BUILD2(_memory_reply_string,
    ~document.getElementById('dbg-copy').addEventListener('click',function(){~,
    ~var rows=document.querySelectorAll('#dbg-panel table tr');~,
    ~var lines=[];~,
    ~for(var i=0;i<rows.length;i++){~,
    ~  var cells=rows[i].querySelectorAll('th,td');~,
    ~  var cols=[];~,
    ~  for(var j=0;j<cells.length;j++) cols.push(cells[j].innerText.trim());~,
    ~  lines.push(cols.join('\t'));~,
    ~}~,
    ~var txt='Pat: '+document.querySelector('#dbg-panel span:first-child').innerText+'\n\n'+lines.join('\n');~,
    ~navigator.clipboard.writeText(txt).then(function(){~,
    ~  var b=document.getElementById('dbg-copy');~,
    ~  b.textContent='Copied!';b.style.color='#4ec94e';~,
    ~  setTimeout(function(){b.textContent='Copy';b.style.color='#ccc';},2000);~,
    ~});~,
    ~});~)
SET _memory_reply_string = BUILD2(_memory_reply_string, "</script>")

SET _memory_reply_string = BUILD2(_memory_reply_string, "</body></html>")


FREE RECORD rec_debug
FREE RECORD rec_docs
END
GO
