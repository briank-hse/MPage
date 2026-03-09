/**
 * PROGRAM: 01_meds_pharm_anvs:group1
 *
 * SPA JSON BACKEND - GP Medications (ANVS blob extraction)
 * Returns JSON via CNVTRECTOJSON(reply).
 * Phase 2A adds optional static UI fragments in reply.ui:
 *   reply.ui.html_parts[*].text
 *   reply.ui.css_parts[*].text
 * No executable JS is returned from the backend.
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
    1 ui
        2 html_parts[*]
            3 text = vc
        2 css_parts[*]
            3 text = vc
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

SET stat = ALTERLIST(reply->ui.html_parts, 4)
SET reply->ui.html_parts[1].text = BUILD2(
    "<section class='panel module-shell module-anvs'><div class='gp-container'>"
    , "<div id='anvs-nav' class='gp-sidebar'></div><div class='gp-content'>"
    , "<div class='gp-content-header'><span id='anvs-counter' class='gp-counter'></span>"
    , "<button id='btn-prev' class='nav-btn' type='button'>&laquo; Previous</button>"
    , "<button id='btn-next' class='nav-btn' type='button'>Next &raquo;</button>"
    , "<div class='header-sep'></div>"
)
SET reply->ui.html_parts[2].text = BUILD2(
    "<button id='btn-diff' class='tool-btn' type='button'>Diff</button>"
    , "<button id='btn-compare' class='tool-btn' type='button'>Compare</button>"
    , "<div class='header-sep'></div>"
    , "<input id='anvs-search-box' class='search-box' type='search' placeholder='Search medications...' />"
    , "<span id='anvs-search-info' class='search-info'></span></div>"
)
SET reply->ui.html_parts[3].text = BUILD2(
    "<div id='compare-banner' class='compare-banner'></div>"
    , "<div id='anvs-compare-pane' class='compare-pane'>"
    , "<div class='compare-col'><div id='compare-header-a' class='compare-col-header'></div><div id='compare-col-a'></div></div>"
    , "<div class='compare-col'><div id='compare-header-b' class='compare-col-header'></div><div id='compare-col-b'></div></div>"
    , "</div>"
)
SET reply->ui.html_parts[4].text = BUILD2(
    "<div id='anvs-scroll-main' class='gp-scroll-main'></div>"
    , "</div></div></section>"
)

SET stat = ALTERLIST(reply->ui.css_parts, 4)
SET reply->ui.css_parts[1].text = BUILD2(
    ".module-anvs{max-width:100%;height:100%}"
    , ".gp-container{display:flex;height:100%;border:1px solid #ddd;background:#fff}"
    , ".gp-sidebar{width:160px;min-width:160px;background:#f8f9fa;border-right:1px solid #ddd;overflow-y:auto;display:flex;flex-direction:column}"
    , ".gp-nav-item{display:block;padding:9px 12px;color:#333;font-size:12px;border-bottom:1px solid #eee;cursor:pointer;line-height:1.3;position:relative;user-select:none}"
    , ".gp-nav-item:hover{background:#e2e6ea;color:#006f99}"
    , ".gp-nav-item.active-nav{background:#006f99;color:#fff}"
    , ".gp-nav-item.active-nav .nav-rel{color:#cce4f0}"
    , ".nav-date{font-weight:600;display:block}"
    , ".nav-rel{font-size:11px;color:#888;display:block;margin-top:2px}"
    , ".nav-flags{display:flex;gap:3px;margin-top:4px;flex-wrap:wrap}"
    , ".nav-flag{font-size:9px;padding:1px 4px;border-radius:3px;font-weight:700;letter-spacing:.3px}"
    , ".nav-flag-highrisk{background:#fde8e8;color:#c0392b;border:1px solid #f5c6c6}"
    , ".nav-flag-search{background:#fff3cd;color:#856404;border:1px solid #ffc107}"
    , ".nav-flag-compare{background:#d4edda;color:#155724;border:1px solid #c3e6cb}"
    , ".compare-sel{outline:3px solid #28a745 !important;background:#f0fff4 !important}"
)
SET reply->ui.css_parts[2].text = BUILD2(
    ".gp-content{flex:1;display:flex;flex-direction:column;overflow:hidden;min-width:0}"
    , ".gp-content-header{background:#f4f6f8;padding:6px 12px;border-bottom:1px solid #ddd;display:flex;align-items:center;gap:8px;flex-shrink:0;flex-wrap:wrap;position:sticky;top:0;z-index:2}"
    , ".gp-counter{font-size:12px;color:#666;white-space:nowrap;margin-right:4px}"
    , ".gp-content-header .nav-btn,.tool-btn,.match-nav .nav-btn{background:#fff;border:1px solid #ccc;padding:5px 10px;cursor:pointer;font-size:12px;color:#333;border-radius:3px;white-space:nowrap;bottom:auto;position:static;margin-right:0}"
    , ".gp-content-header .nav-btn:hover,.tool-btn:hover,.match-nav .nav-btn:hover{background:#e9ecef;color:#333}"
    , ".gp-content-header .nav-btn:disabled,.match-nav .nav-btn:disabled{opacity:.4;cursor:default}"
    , ".tool-btn.active{background:#006f99;color:#fff;border-color:#005a7a}"
    , ".tool-btn.active:hover{background:#005a7a;color:#fff}"
    , ".gp-content-header .search-box{width:180px}"
    , ".search-info{font-size:11px;color:#666;white-space:nowrap}"
    , ".header-sep{width:1px;height:20px;background:#ddd;margin:0 2px}"
    , ".compare-banner{background:#d4edda;border-bottom:1px solid #c3e6cb;padding:5px 12px;font-size:12px;color:#155724;display:none;align-items:center;gap:8px;flex-shrink:0}"
    , ".compare-banner.visible{display:flex}"
    , ".gp-scroll-main{flex:1;overflow-y:auto;padding:20px;padding-bottom:80vh;background:#fff}"
)
SET reply->ui.css_parts[3].text = BUILD2(
    ".compare-pane{display:none;flex:1;overflow:hidden;background:#fff}"
    , ".compare-pane.visible{display:flex}"
    , ".compare-col{flex:1;overflow-y:auto;padding:16px;border-right:1px solid #ddd}"
    , ".compare-col:last-child{border-right:none}"
    , ".compare-col-header{font-size:12px;font-weight:700;color:#006f99;margin-bottom:12px;padding-bottom:6px;border-bottom:2px solid #006f99}"
    , ".blob-record{border:1px solid #ddd;margin-bottom:24px;padding:20px;border-left:4px solid #6f42c1;background:#fff;border-radius:3px;box-shadow:0 1px 3px rgba(0,0,0,.05)}"
    , ".blob-meta{background:#f8f9fa;padding:10px 15px;font-size:13px;margin-bottom:15px;font-weight:600;color:#444;border:1px solid #eee;border-radius:3px}"
    , ".med-section{margin-bottom:16px}"
    , ".med-section-heading{font-size:12px;font-weight:700;text-transform:uppercase;letter-spacing:.5px;color:#555;padding:4px 0;margin-bottom:6px;border-bottom:1px solid #eee}"
    , ".med-section-heading.sec-prescribed{color:#006f99;border-color:#006f99}"
    , ".med-section-heading.sec-discontinued{color:#c0392b;border-color:#c0392b}"
    , ".med-section-heading.sec-vaccination{color:#27ae60;border-color:#27ae60}"
    , ".med-section-heading.sec-other{color:#666;border-color:#ccc}"
    , ".med-section-empty{font-size:12px;color:#aaa;font-style:italic;padding:2px 0 4px}"
)
SET reply->ui.css_parts[4].text = BUILD2(
    ".med-row{display:flex;align-items:baseline;gap:6px;padding:3px 6px;border-radius:3px;font-size:13px;line-height:1.5;color:#222;margin-bottom:2px}"
    , ".med-row:hover{background:#f5f5f5}"
    , ".med-row.non-dated{padding-left:6px;color:#555}"
    , ".med-date{font-size:11px;color:#888;white-space:nowrap;flex-shrink:0}"
    , ".med-text{flex:1}"
    , ".highrisk-pill{display:inline-block;font-size:9px;font-weight:700;padding:1px 5px;border-radius:3px;background:#fde8e8;color:#c0392b;border:1px solid #f5c6c6;margin-left:5px;vertical-align:middle;letter-spacing:.3px}"
    , ".search-hit{background:#fff3cd;border-left:3px solid #ffc107 !important}"
    , ".diff-added{background:#eafaf1 !important;border-left:3px solid #27ae60}"
    , ".diff-removed{background:#fdf3f2 !important;border-left:3px solid #e74c3c;text-decoration:line-through;color:#999 !important}"
    , ".diff-changed{background:#fef9ec !important;border-left:3px solid #f39c12}"
    , ".diff-tag{font-size:10px;font-weight:700;padding:1px 5px;border-radius:3px;margin-left:4px;flex-shrink:0}"
    , ".diff-tag-added{background:#27ae60;color:#fff}"
    , ".diff-tag-removed{background:#e74c3c;color:#fff}"
    , ".diff-tag-changed{background:#f39c12;color:#fff}"
    , "@media (max-width:1100px){.gp-container{flex-direction:column}.gp-sidebar{width:100%;min-width:0;max-height:220px;border-right:0;border-bottom:1px solid #ddd}.compare-pane.visible{flex-direction:column}.compare-col{border-right:0;border-bottom:1px solid #ddd}.gp-scroll-main{padding:12px}}"
)

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
