/**
 * PROGRAM: 01_meds_pharm_anvs_edge
 *
 * EDGE MIGRATION ARCHITECTURE:
 * Loaded into the parent MPage iframe via XMLCclRequest + srcdoc.
 * Output via _memory_reply_string — select into $outdev not valid in XCR.
 */

DROP PROGRAM 01_meds_pharm_anvs_edge GO
CREATE PROGRAM 01_meds_pharm_anvs_edge

PROMPT
    "Output to File/Printer/MINE" = "MINE"
    , "User Id"      = 0
    , "Patient ID"   = 0
    , "Encounter Id" = 0
WITH OUTDEV, user_id, patient_id, encounter_id

; =============================================================================
; 1. GP MEDICATION DETAILS (BLOB EXTRACTION)
; =============================================================================
RECORD rec_blob (
  1 list[*]
    2 event_id  = f8
    2 dt_tm     = vc
    2 prsnl     = vc
    2 blob_text = vc
)

DECLARE OcfCD      = f8  WITH noconstant(0.0)
DECLARE stat       = i4  WITH noconstant(0)
DECLARE stat_rtf   = i4  WITH noconstant(0)
DECLARE tlen       = i4  WITH noconstant(0)
DECLARE bsize      = i4  WITH noconstant(0)
DECLARE totlen     = i4  WITH noconstant(0)
DECLARE bloblen    = i4  WITH noconstant(0)
DECLARE vLen       = i4  WITH noconstant(0)
DECLARE nCnt       = i4  WITH noconstant(0)
DECLARE x          = i4  WITH noconstant(0)
DECLARE blob_in    = vc  WITH noconstant(" ")
DECLARE blob_out   = vc  WITH noconstant(" ")
DECLARE rtf_out    = vc  WITH noconstant(" ")
DECLARE vCleanText = vc  WITH noconstant(" ")

SET stat = uar_get_meaning_by_codeset(120, "OCFCOMP", 1, OcfCD)

SELECT INTO "NL:"
FROM CLINICAL_EVENT CE
    , CE_BLOB CB
    , PRSNL PR
PLAN CE WHERE CE.PERSON_ID = CNVTREAL($patient_id)
    AND CE.EVENT_CD = 25256529.00
    AND CE.VALID_UNTIL_DT_TM > SYSDATE
JOIN CB WHERE CB.EVENT_ID = CE.EVENT_ID
    AND CB.VALID_UNTIL_DT_TM > SYSDATE
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
            tlen = TEXTLEN(blob_out)
            stat_rtf = uar_rtf2(blob_out, tlen, rtf_out, CB.BLOB_LENGTH, bsize, 0)
        ELSE
            rtf_out = blob_out
            bsize = tlen
        ENDIF
    ENDIF

    IF (bsize > 0)
        vCleanText = REPLACE(SUBSTRING(1, bsize, rtf_out), CHAR(0), " ", 0)
    ENDIF

    IF (TEXTLEN(TRIM(vCleanText)) <= 1)
        vCleanText = "<i>-- No narrative note found --</i>"
    ELSE
        vCleanText = REPLACE(vCleanText, "&",     "&amp;", 0)
        vCleanText = REPLACE(vCleanText, "<",     "&lt;",  0)
        vCleanText = REPLACE(vCleanText, ">",     "&gt;",  0)
        vCleanText = REPLACE(vCleanText, concat(CHAR(13), CHAR(10)), "<br />", 0)
        vCleanText = REPLACE(vCleanText, CHAR(13), "<br />", 0)
        vCleanText = REPLACE(vCleanText, CHAR(10), "<br />", 0)
        vCleanText = REPLACE(vCleanText, CHAR(11), "<br />", 0) ; Added to handle vertical tabs
        
        ; Consolidated multiple line breaks to prevent excessive spacing
        vCleanText = REPLACE(vCleanText, "<br /><br /><br /><br />", "<br /><br />", 0)
        vCleanText = REPLACE(vCleanText, "<br /><br /><br />", "<br /><br />", 0)
        
        vCleanText = TRIM(vCleanText, 3)
    ENDIF
    
    rec_blob->list[nCnt].blob_text = vCleanText

WITH NOCOUNTER, RDBARRAYFETCH=1

; =============================================================================
; 1B. GET STATIC CONTENT URL
; =============================================================================
DECLARE v_content_url = vc WITH noconstant("")

SELECT INTO "NL:"
FROM dm_info d
WHERE d.info_domain = "INS"
  AND d.info_name = "CONTENT_SERVICE_URL"
DETAIL
  v_content_url = TRIM(d.info_char, 3)
WITH NOCOUNTER

IF (SUBSTRING(TEXTLEN(v_content_url), 1, v_content_url) = "/")
  SET v_content_url = SUBSTRING(1, TEXTLEN(v_content_url) - 1, v_content_url)
ENDIF

; =============================================================================
; 2. HTML OUTPUT VIA _memory_reply_string
; =============================================================================

declare v_blob_cnt_str = vc with noconstant("")
set v_blob_cnt_str = trim(cnvtstring(size(rec_blob->list, 5)))

set _memory_reply_string = ""

; -- Head & CSS ----------------------------------------------------------------
set _memory_reply_string = concat(_memory_reply_string, "<!DOCTYPE html><html lang='en'><head><meta charset='utf-8'/>")
set _memory_reply_string = concat(_memory_reply_string, "<style>")
set _memory_reply_string = concat(_memory_reply_string, "*, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }")
set _memory_reply_string = concat(_memory_reply_string, "html, body { height: 100%; overflow: hidden; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; background: #fff; }")
set _memory_reply_string = concat(_memory_reply_string, ".gp-container { display: flex; height: 100vh; }")

; -- Sidebar -------------------------------------------------------------------
set _memory_reply_string = concat(_memory_reply_string, ".gp-sidebar { width: 190px; min-width: 190px; background: #f8f9fa; border-right: 1px solid #ddd; overflow-y: auto; display: flex; flex-direction: column; }")
set _memory_reply_string = concat(_memory_reply_string, ".gp-nav-item { display: block; padding: 9px 12px; color: #333; font-size: 12px; border-bottom: 1px solid #eee; cursor: pointer; line-height: 1.3; position: relative; user-select: none; }")
set _memory_reply_string = concat(_memory_reply_string, ".gp-nav-item:hover { background: #e2e6ea; color: #006f99; }")
set _memory_reply_string = concat(_memory_reply_string, ".gp-nav-item .nav-date { font-weight: 600; display: block; }")
set _memory_reply_string = concat(_memory_reply_string, ".gp-nav-item .nav-rel { font-size: 11px; color: #888; display: block; margin-top: 2px; }")
set _memory_reply_string = concat(_memory_reply_string, ".active-nav { background: #006f99 !important; color: #fff !important; }")
set _memory_reply_string = concat(_memory_reply_string, ".active-nav .nav-rel { color: #cce4f0 !important; }")
set _memory_reply_string = concat(_memory_reply_string, ".nav-flags { display: flex; gap: 3px; margin-top: 4px; flex-wrap: wrap; }")
set _memory_reply_string = concat(_memory_reply_string, ".nav-flag { font-size: 9px; padding: 1px 4px; border-radius: 3px; font-weight: 700; letter-spacing: 0.3px; }")
set _memory_reply_string = concat(_memory_reply_string, ".nav-flag-highrisk { background: #fde8e8; color: #c0392b; border: 1px solid #f5c6c6; }")
set _memory_reply_string = concat(_memory_reply_string, ".nav-flag-search { background: #fff3cd; color: #856404; border: 1px solid #ffc107; }")
set _memory_reply_string = concat(_memory_reply_string, ".nav-flag-compare { background: #d4edda; color: #155724; border: 1px solid #c3e6cb; }")
set _memory_reply_string = concat(_memory_reply_string, ".compare-sel { outline: 3px solid #28a745 !important; background: #f0fff4 !important; }")

; -- Content area --------------------------------------------------------------
set _memory_reply_string = concat(_memory_reply_string, ".gp-content { flex: 1; display: flex; flex-direction: column; overflow: hidden; }")
set _memory_reply_string = concat(_memory_reply_string, ".gp-content-header { background: #f4f6f8; padding: 6px 12px; border-bottom: 1px solid #ddd; display: flex; align-items: center; gap: 8px; flex-shrink: 0; flex-wrap: wrap; }")
set _memory_reply_string = concat(_memory_reply_string, ".gp-counter { font-size: 12px; color: #666; white-space: nowrap; margin-right: 4px; }")
set _memory_reply_string = concat(_memory_reply_string, ".nav-btn { background: #fff; border: 1px solid #ccc; padding: 5px 10px; cursor: pointer; font-size: 12px; color: #333; font-weight: 500; border-radius: 3px; white-space: nowrap; }")
set _memory_reply_string = concat(_memory_reply_string, ".nav-btn:hover { background: #e9ecef; }")
set _memory_reply_string = concat(_memory_reply_string, ".nav-btn:disabled { opacity: 0.4; cursor: default; }")
set _memory_reply_string = concat(_memory_reply_string, ".tool-btn { background: #fff; border: 1px solid #ccc; padding: 5px 10px; cursor: pointer; font-size: 12px; color: #333; border-radius: 3px; white-space: nowrap; }")
set _memory_reply_string = concat(_memory_reply_string, ".tool-btn.active { background: #006f99; color: #fff; border-color: #005a7a; }")
set _memory_reply_string = concat(_memory_reply_string, ".tool-btn:hover { background: #e9ecef; }")
set _memory_reply_string = concat(_memory_reply_string, ".tool-btn.active:hover { background: #005a7a; }")
set _memory_reply_string = concat(_memory_reply_string, ".search-box { border: 1px solid #ccc; border-radius: 3px; padding: 4px 8px; font-size: 12px; width: 180px; outline: none; }")
set _memory_reply_string = concat(_memory_reply_string, ".search-box:focus { border-color: #006f99; box-shadow: 0 0 0 2px rgba(0,111,153,0.15); }")
set _memory_reply_string = concat(_memory_reply_string, ".search-info { font-size: 11px; color: #666; white-space: nowrap; }")
set _memory_reply_string = concat(_memory_reply_string, ".header-sep { width: 1px; height: 20px; background: #ddd; margin: 0 2px; }")
set _memory_reply_string = concat(_memory_reply_string, ".compare-banner { background: #d4edda; border-bottom: 1px solid #c3e6cb; padding: 5px 12px; font-size: 12px; color: #155724; display: none; align-items: center; gap: 8px; flex-shrink: 0; }")
set _memory_reply_string = concat(_memory_reply_string, ".compare-banner.visible { display: flex; }")

; -- Scroll areas --------------------------------------------------------------
set _memory_reply_string = concat(_memory_reply_string, ".gp-scroll-main { flex: 1; overflow-y: auto; padding: 20px; padding-bottom: 80vh; }")
set _memory_reply_string = concat(_memory_reply_string, ".compare-pane { display: none; flex: 1; overflow: hidden; }")
set _memory_reply_string = concat(_memory_reply_string, ".compare-pane.visible { display: flex; }")
set _memory_reply_string = concat(_memory_reply_string, ".compare-col { flex: 1; overflow-y: auto; padding: 16px; border-right: 1px solid #ddd; }")
set _memory_reply_string = concat(_memory_reply_string, ".compare-col:last-child { border-right: none; }")
set _memory_reply_string = concat(_memory_reply_string, ".compare-col-header { font-size: 12px; font-weight: 700; color: #006f99; margin-bottom: 12px; padding-bottom: 6px; border-bottom: 2px solid #006f99; }")

; -- Blob records --------------------------------------------------------------
set _memory_reply_string = concat(_memory_reply_string, ".blob-record { border: 1px solid #ddd; margin-bottom: 24px; padding: 20px; border-left: 4px solid #6f42c1; background: #fff; border-radius: 3px; box-shadow: 0 1px 3px rgba(0,0,0,0.05); }")
set _memory_reply_string = concat(_memory_reply_string, ".blob-meta { background: #f8f9fa; padding: 10px 15px; font-size: 13px; margin-bottom: 15px; font-weight: 600; color: #444; border: 1px solid #eee; border-radius: 3px; }")

; -- Section headings within blobs ---------------------------------------------
set _memory_reply_string = concat(_memory_reply_string, ".med-section { margin-bottom: 16px; }")
set _memory_reply_string = concat(_memory_reply_string, ".med-section-heading { font-size: 12px; font-weight: 700; text-transform: uppercase; letter-spacing: 0.5px; color: #555; padding: 4px 0; margin-bottom: 6px; border-bottom: 1px solid #eee; }")
set _memory_reply_string = concat(_memory_reply_string, ".med-section-heading.sec-prescribed { color: #006f99; border-color: #006f99; }")
set _memory_reply_string = concat(_memory_reply_string, ".med-section-heading.sec-discontinued { color: #c0392b; border-color: #c0392b; }")
set _memory_reply_string = concat(_memory_reply_string, ".med-section-heading.sec-vaccination { color: #27ae60; border-color: #27ae60; }")
set _memory_reply_string = concat(_memory_reply_string, ".med-section-heading.sec-other { color: #666; border-color: #ccc; }")
set _memory_reply_string = concat(_memory_reply_string, ".med-section-empty { font-size: 12px; color: #aaa; font-style: italic; padding: 2px 0 4px 0; }")

; -- Med rows ------------------------------------------------------------------
set _memory_reply_string = concat(_memory_reply_string, ".med-row { display: flex; align-items: baseline; gap: 6px; padding: 3px 6px; border-radius: 3px; font-size: 13px; line-height: 1.5; color: #222; margin-bottom: 2px; }")
set _memory_reply_string = concat(_memory_reply_string, ".med-row:hover { background: #f5f5f5; }")
set _memory_reply_string = concat(_memory_reply_string, ".med-date { font-size: 11px; color: #888; white-space: nowrap; flex-shrink: 0; }")
set _memory_reply_string = concat(_memory_reply_string, ".med-text { flex: 1; }")
set _memory_reply_string = concat(_memory_reply_string, ".med-row.non-dated { padding-left: 6px; color: #555; }")

; -- Diff colours --------------------------------------------------------------
set _memory_reply_string = concat(_memory_reply_string, ".diff-added { background: #eafaf1 !important; border-left: 3px solid #27ae60; }")
set _memory_reply_string = concat(_memory_reply_string, ".diff-removed { background: #fdf3f2 !important; border-left: 3px solid #e74c3c; text-decoration: line-through; color: #999 !important; }")
set _memory_reply_string = concat(_memory_reply_string, ".diff-changed { background: #fef9ec !important; border-left: 3px solid #f39c12; }")
set _memory_reply_string = concat(_memory_reply_string, ".diff-tag { font-size: 10px; font-weight: 700; padding: 1px 5px; border-radius: 3px; margin-left: 4px; flex-shrink: 0; }")
set _memory_reply_string = concat(_memory_reply_string, ".diff-tag-added { background: #27ae60; color: #fff; }")
set _memory_reply_string = concat(_memory_reply_string, ".diff-tag-removed { background: #e74c3c; color: #fff; }")
set _memory_reply_string = concat(_memory_reply_string, ".diff-tag-changed { background: #f39c12; color: #fff; }")

; -- High-risk med highlighting -------------------------------------------------
set _memory_reply_string = concat(_memory_reply_string, ".highrisk-pill { display: inline-block; font-size: 9px; font-weight: 700; padding: 1px 5px; border-radius: 3px; background: #fde8e8; color: #c0392b; border: 1px solid #f5c6c6; margin-left: 5px; vertical-align: middle; letter-spacing: 0.3px; }")

; -- Search highlighting --------------------------------------------------------
set _memory_reply_string = concat(_memory_reply_string, ".search-hit { background: #fff3cd; border-left: 3px solid #ffc107 !important; }")
set _memory_reply_string = concat(_memory_reply_string, "mark { background: #ffc107; color: #000; border-radius: 2px; padding: 0 2px; }")
set _memory_reply_string = concat(_memory_reply_string, "</style>")

; -- JavaScript ----------------------------------------------------------------
set _memory_reply_string = concat(_memory_reply_string, "<script>")
set _memory_reply_string = concat(_memory_reply_string, "var totalBlobs = ", v_blob_cnt_str, ";")
set _memory_reply_string = concat(_memory_reply_string, "</script>")

; Load external JavaScript file
set _memory_reply_string = concat(_memory_reply_string, 
    "<script src='", v_content_url, "/custom_mpage_content/mncms_meds/01_meds_pharm_anvs.js'></script>")

; -- HTML body -----------------------------------------------------------------
set _memory_reply_string = concat(_memory_reply_string, "</head><body>")
set _memory_reply_string = concat(_memory_reply_string, "<div class='gp-container'>")
set _memory_reply_string = concat(_memory_reply_string, "<div class='gp-sidebar'>")

; Sidebar nav items
set x = 1
while (x <= size(rec_blob->list, 5))
    if (x = 1)
        set _memory_reply_string = concat(_memory_reply_string,
            "<div id='nav-", trim(cnvtstring(x)), "' class='gp-nav-item active-nav' onclick='goToBlob(", trim(cnvtstring(x)), ")'>",
            "<span class='nav-date'>", rec_blob->list[x].dt_tm, "</span></div>")
    else
        set _memory_reply_string = concat(_memory_reply_string,
            "<div id='nav-", trim(cnvtstring(x)), "' class='gp-nav-item' onclick='goToBlob(", trim(cnvtstring(x)), ")'>",
            "<span class='nav-date'>", rec_blob->list[x].dt_tm, "</span></div>")
    endif
    set x = x + 1
endwhile

if (size(rec_blob->list, 5) = 0)
    set _memory_reply_string = concat(_memory_reply_string, "<div class='gp-nav-item' style='color:#888;'>No records found</div>")
endif

set _memory_reply_string = concat(_memory_reply_string, "</div>") ; end sidebar

; -- Content area --------------------------------------------------------------
set _memory_reply_string = concat(_memory_reply_string, "<div class='gp-content'>")

; Header bar: counter | prev/next | sep | diff | compare | sep | search | match info
set _memory_reply_string = concat(_memory_reply_string, "<div class='gp-content-header'>")
set _memory_reply_string = concat(_memory_reply_string, "  <span class='gp-counter' id='blob-counter'></span>")
set _memory_reply_string = concat(_memory_reply_string, "  <button id='btn-prev' class='nav-btn' onclick='prevBlob()'>&laquo; Previous</button>")
set _memory_reply_string = concat(_memory_reply_string, "  <button id='btn-next' class='nav-btn' onclick='nextBlob()'>Next &raquo;</button>")
set _memory_reply_string = concat(_memory_reply_string, "  <div class='header-sep'></div>")
set _memory_reply_string = concat(_memory_reply_string, "  <button id='btn-diff' class='tool-btn' onclick='toggleDiff()'>Diff</button>")
set _memory_reply_string = concat(_memory_reply_string, "  <button id='btn-compare' class='tool-btn' onclick='toggleCompare()'>Compare</button>")
set _memory_reply_string = concat(_memory_reply_string, "  <div class='header-sep'></div>")
set _memory_reply_string = concat(_memory_reply_string, "  <input id='search-box' class='search-box' type='text' placeholder='Search medications...' oninput='onSearchInput(this.value)' />")
set _memory_reply_string = concat(_memory_reply_string, "  <span id='search-info' class='search-info'></span>")
set _memory_reply_string = concat(_memory_reply_string, "</div>")

; Compare mode instruction banner
set _memory_reply_string = concat(_memory_reply_string, "<div id='compare-banner' class='compare-banner'></div>")

; Compare split-pane (hidden until compare triggered)
set _memory_reply_string = concat(_memory_reply_string, "<div id='compare-pane' class='compare-pane'>")
set _memory_reply_string = concat(_memory_reply_string, "  <div class='compare-col'>")
set _memory_reply_string = concat(_memory_reply_string, "    <div class='compare-col-header' id='compare-header-a'></div>")
set _memory_reply_string = concat(_memory_reply_string, "    <div id='compare-col-a'></div>")
set _memory_reply_string = concat(_memory_reply_string, "  </div>")
set _memory_reply_string = concat(_memory_reply_string, "  <div class='compare-col'>")
set _memory_reply_string = concat(_memory_reply_string, "    <div class='compare-col-header' id='compare-header-b'></div>")
set _memory_reply_string = concat(_memory_reply_string, "    <div id='compare-col-b'></div>")
set _memory_reply_string = concat(_memory_reply_string, "  </div>")
set _memory_reply_string = concat(_memory_reply_string, "</div>")

; Main scroll area
set _memory_reply_string = concat(_memory_reply_string, "<div id='scroll-main' class='gp-scroll-main'>")

; Blob records — raw hidden div for JS parsing + empty body div filled by JS
set x = 1
while (x <= size(rec_blob->list, 5))
    set _memory_reply_string = concat(_memory_reply_string,
        "<div id='blob-", trim(cnvtstring(x)), "' class='blob-record' data-idx='", trim(cnvtstring(x)), "'>")

    ; Meta header with hidden span for compare view title
    set _memory_reply_string = concat(_memory_reply_string,
        "<div class='blob-meta'>Performed: <span id='blob-meta-text-", trim(cnvtstring(x)), "'>",
        rec_blob->list[x].dt_tm, " by ", rec_blob->list[x].prsnl, "</span></div>")

    ; Hidden raw blob HTML for JS parser — display:none so it doesn't render
    set _memory_reply_string = concat(_memory_reply_string,
        "<div id='blob-raw-", trim(cnvtstring(x)), "' style='display:none;'>")

    set vLen  = textlen(rec_blob->list[x].blob_text)
    set bsize = 1
    while (bsize <= vLen)
        set _memory_reply_string = concat(_memory_reply_string, substring(bsize, 500, rec_blob->list[x].blob_text))
        set bsize = bsize + 500
    endwhile

    set _memory_reply_string = concat(_memory_reply_string, "</div>")

    ; Rendered body — populated by renderAllBlobs() on DOMContentLoaded
    set _memory_reply_string = concat(_memory_reply_string,
        "<div id='blob-body-", trim(cnvtstring(x)), "'></div>")

    set _memory_reply_string = concat(_memory_reply_string, "</div>")
    set x = x + 1
endwhile

if (size(rec_blob->list, 5) = 0)
    set _memory_reply_string = concat(_memory_reply_string,
        "<p style='color:#666; font-style:italic; padding:20px;'>No GP Medication Details available for this patient.</p>")
endif

set _memory_reply_string = concat(_memory_reply_string, "</div>") ; end scroll-main
set _memory_reply_string = concat(_memory_reply_string, "</div>") ; end gp-content
set _memory_reply_string = concat(_memory_reply_string, "</div>") ; end gp-container
set _memory_reply_string = concat(_memory_reply_string, "</body></html>")

FREE RECORD rec_blob
END
GO