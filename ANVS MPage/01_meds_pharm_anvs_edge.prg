/**
 * PROGRAM: 01_meds_pharm_gp_edge
 *
 * EDGE MIGRATION ARCHITECTURE:
 * Loaded into the parent MPage iframe via XMLCclRequest + srcdoc.
 * Output via _memory_reply_string — select into $outdev not valid in XCR.
 */

DROP PROGRAM 01_meds_pharm_gp_edge GO
CREATE PROGRAM 01_meds_pharm_gp_edge

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
        vCleanText = REPLACE(vCleanText, CHAR(11), "<br />", 0)
        vCleanText = REPLACE(vCleanText, "<br /><br /><br /><br /><br /><br />", "<br /><br />", 0)
        vCleanText = REPLACE(vCleanText, "<br /><br /><br /><br /><br />", "<br /><br />", 0)
        vCleanText = REPLACE(vCleanText, "<br /><br /><br /><br />", "<br /><br />", 0)
        vCleanText = REPLACE(vCleanText, "<br /><br /><br />", "<br /><br />", 0)
        vCleanText = TRIM(vCleanText, 3)
    ENDIF

    rec_blob->list[nCnt].blob_text = vCleanText

WITH NOCOUNTER, RDBARRAYFETCH=1

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
set _memory_reply_string = concat(_memory_reply_string, ".gp-sidebar { width: 190px; min-width: 190px; background: #f8f9fa; border-right: 1px solid #ddd; overflow-y: auto; display: flex; flex-direction: column; }")
set _memory_reply_string = concat(_memory_reply_string, ".gp-content { flex: 1; display: flex; flex-direction: column; overflow: hidden; }")
set _memory_reply_string = concat(_memory_reply_string, ".gp-content-header { background: #f4f6f8; padding: 8px 15px; border-bottom: 1px solid #ddd; display: flex; align-items: center; justify-content: space-between; flex-shrink: 0; }")
set _memory_reply_string = concat(_memory_reply_string, ".gp-counter { font-size: 12px; color: #666; }")
set _memory_reply_string = concat(_memory_reply_string, ".nav-btn { background: #fff; border: 1px solid #ccc; padding: 6px 12px; cursor: pointer; font-size: 13px; margin-left: 8px; color: #333; font-weight: 500; border-radius: 3px; }")
set _memory_reply_string = concat(_memory_reply_string, ".nav-btn:hover { background: #e9ecef; }")
set _memory_reply_string = concat(_memory_reply_string, ".nav-btn:disabled { opacity: 0.4; cursor: default; }")
set _memory_reply_string = concat(_memory_reply_string, ".gp-scroll-main { flex: 1; overflow-y: auto; padding: 20px; }")
set _memory_reply_string = concat(_memory_reply_string, ".gp-bottom-spacer { height: 85vh; width: 100%; }")
set _memory_reply_string = concat(_memory_reply_string, ".gp-nav-item { display: block; padding: 9px 12px; color: #333; font-size: 12px; border-bottom: 1px solid #eee; cursor: pointer; line-height: 1.3; }")
set _memory_reply_string = concat(_memory_reply_string, ".gp-nav-item:hover { background: #e2e6ea; color: #006f99; }")
set _memory_reply_string = concat(_memory_reply_string, ".gp-nav-item .nav-date { font-weight: 600; display: block; }")
set _memory_reply_string = concat(_memory_reply_string, ".gp-nav-item .nav-rel { font-size: 11px; color: #888; display: block; margin-top: 2px; }")
set _memory_reply_string = concat(_memory_reply_string, ".active-nav { background: #006f99 !important; color: #fff !important; }")
set _memory_reply_string = concat(_memory_reply_string, ".active-nav .nav-rel { color: #cce4f0 !important; }")
set _memory_reply_string = concat(_memory_reply_string, ".blob-record { border: 1px solid #ddd; margin-bottom: 24px; padding: 20px; border-left: 4px solid #6f42c1; background: #fff; border-radius: 3px; box-shadow: 0 1px 3px rgba(0,0,0,0.05); }")
set _memory_reply_string = concat(_memory_reply_string, ".blob-meta { background: #f8f9fa; padding: 10px 15px; font-size: 13px; margin-bottom: 15px; font-weight: 600; color: #444; border: 1px solid #eee; border-radius: 3px; }")
set _memory_reply_string = concat(_memory_reply_string, ".blob-text { white-space: pre-wrap; font-size: 14px; line-height: 1.6; color: #222; }")
set _memory_reply_string = concat(_memory_reply_string, "</style>")

; -- JavaScript ----------------------------------------------------------------
set _memory_reply_string = concat(_memory_reply_string, "<script>")
set _memory_reply_string = concat(_memory_reply_string, concat("var totalBlobs = ", v_blob_cnt_str, ";"))
set _memory_reply_string = concat(_memory_reply_string, "var currentBlob = 1;")
set _memory_reply_string = concat(_memory_reply_string, "var scrollSpyEnabled = true;")
set _memory_reply_string = concat(_memory_reply_string, "var scrollTimeout;")

; -- Relative date helper ------------------------------------------------------
set _memory_reply_string = concat(_memory_reply_string, "function relativeDate(ddmmyyyy) {")
set _memory_reply_string = concat(_memory_reply_string, "  var parts = ddmmyyyy.split('/');")
set _memory_reply_string = concat(_memory_reply_string, "  if (parts.length < 3) return '';")
set _memory_reply_string = concat(_memory_reply_string, "  var d = new Date(parts[2], parts[1] - 1, parts[0]);")
set _memory_reply_string = concat(_memory_reply_string, "  var now = new Date();")
set _memory_reply_string = concat(_memory_reply_string, "  var diffMs = now - d;")
set _memory_reply_string = concat(_memory_reply_string, "  var diffDays = Math.floor(diffMs / 86400000);")
set _memory_reply_string = concat(_memory_reply_string, "  if (diffDays < 1)  return 'Today';")
set _memory_reply_string = concat(_memory_reply_string, "  if (diffDays < 7)  return diffDays + ' day' + (diffDays === 1 ? '' : 's') + ' ago';")
set _memory_reply_string = concat(_memory_reply_string, "  var diffWeeks = Math.floor(diffDays / 7);")
set _memory_reply_string = concat(_memory_reply_string, "  if (diffDays < 31) return diffWeeks + ' week' + (diffWeeks === 1 ? '' : 's') + ' ago';")
set _memory_reply_string = concat(_memory_reply_string, "  var diffMonths = Math.round(diffDays / 30.5);")
set _memory_reply_string = concat(_memory_reply_string, "  if (diffDays < 365) return diffMonths + ' month' + (diffMonths === 1 ? '' : 's') + ' ago';")
set _memory_reply_string = concat(_memory_reply_string, "  var diffYears = Math.floor(diffDays / 365.25);")
set _memory_reply_string = concat(_memory_reply_string, "  var remMonths = Math.round((diffDays - diffYears * 365.25) / 30.5);")
set _memory_reply_string = concat(_memory_reply_string, "  if (remMonths === 0) return diffYears + ' yr' + (diffYears === 1 ? '' : 's') + ' ago';")
set _memory_reply_string = concat(_memory_reply_string, "  return diffYears + ' yr ' + remMonths + ' mo ago';")
set _memory_reply_string = concat(_memory_reply_string, "}")

; -- Counter update ------------------------------------------------------------
set _memory_reply_string = concat(_memory_reply_string, "function updateCounter(idx) {")
set _memory_reply_string = concat(_memory_reply_string, "  var el = document.getElementById('blob-counter');")
set _memory_reply_string = concat(_memory_reply_string, "  if (el) el.textContent = idx + ' of ' + totalBlobs;")
set _memory_reply_string = concat(_memory_reply_string, "  var btnPrev = document.getElementById('btn-prev');")
set _memory_reply_string = concat(_memory_reply_string, "  var btnNext = document.getElementById('btn-next');")
set _memory_reply_string = concat(_memory_reply_string, "  if (btnPrev) btnPrev.disabled = (idx <= 1);")
set _memory_reply_string = concat(_memory_reply_string, "  if (btnNext) btnNext.disabled = (idx >= totalBlobs);")
set _memory_reply_string = concat(_memory_reply_string, "}")

; -- Sidebar highlight ---------------------------------------------------------
set _memory_reply_string = concat(_memory_reply_string, "function setActiveNav(idx) {")
set _memory_reply_string = concat(_memory_reply_string, "  for (var i = 1; i <= totalBlobs; i++) {")
set _memory_reply_string = concat(_memory_reply_string, "    var n = document.getElementById('nav-' + i);")
set _memory_reply_string = concat(_memory_reply_string, "    if (n) n.className = (i === idx) ? 'gp-nav-item active-nav' : 'gp-nav-item';")
set _memory_reply_string = concat(_memory_reply_string, "  }")
set _memory_reply_string = concat(_memory_reply_string, "  var active = document.getElementById('nav-' + idx);")
set _memory_reply_string = concat(_memory_reply_string, "  if (active) active.scrollIntoView({ block: 'nearest' });")
set _memory_reply_string = concat(_memory_reply_string, "}")

; -- goToBlob: click nav or prev/next -----------------------------------------
set _memory_reply_string = concat(_memory_reply_string, "function goToBlob(idx) {")
set _memory_reply_string = concat(_memory_reply_string, "  if (idx < 1 || idx > totalBlobs) return;")
set _memory_reply_string = concat(_memory_reply_string, "  currentBlob = idx;")
set _memory_reply_string = concat(_memory_reply_string, "  scrollSpyEnabled = false;")
set _memory_reply_string = concat(_memory_reply_string, "  clearTimeout(scrollTimeout);")
set _memory_reply_string = concat(_memory_reply_string, "  setActiveNav(idx);")
set _memory_reply_string = concat(_memory_reply_string, "  updateCounter(idx);")
set _memory_reply_string = concat(_memory_reply_string, "  var target = document.getElementById('blob-' + idx);")
set _memory_reply_string = concat(_memory_reply_string, "  if (target) {")
set _memory_reply_string = concat(_memory_reply_string, "    var scroller = document.getElementById('scroll-main');")
set _memory_reply_string = concat(_memory_reply_string, "    var scrollerRect = scroller.getBoundingClientRect();")
set _memory_reply_string = concat(_memory_reply_string, "    var targetRect = target.getBoundingClientRect();")
set _memory_reply_string = concat(_memory_reply_string, "    scroller.scrollTo({ top: scroller.scrollTop + (targetRect.top - scrollerRect.top) - 12, behavior: 'smooth' });")
set _memory_reply_string = concat(_memory_reply_string, "  }")
set _memory_reply_string = concat(_memory_reply_string, "  scrollTimeout = setTimeout(function() { scrollSpyEnabled = true; }, 800);")
set _memory_reply_string = concat(_memory_reply_string, "}")
set _memory_reply_string = concat(_memory_reply_string, "function nextBlob() { goToBlob(currentBlob + 1); }")
set _memory_reply_string = concat(_memory_reply_string, "function prevBlob() { goToBlob(currentBlob - 1); }")

; -- Scroll-spy Tracker -------------------------------------------------------
set _memory_reply_string = concat(_memory_reply_string, "document.addEventListener('DOMContentLoaded', function() {")
set _memory_reply_string = concat(_memory_reply_string, "  var navDates = document.querySelectorAll('.nav-date');")
set _memory_reply_string = concat(_memory_reply_string, "  navDates.forEach(function(el) {")
set _memory_reply_string = concat(_memory_reply_string, "    var rel = document.createElement('span');")
set _memory_reply_string = concat(_memory_reply_string, "    rel.className = 'nav-rel';")
set _memory_reply_string = concat(_memory_reply_string, "    rel.textContent = relativeDate(el.textContent);")
set _memory_reply_string = concat(_memory_reply_string, "    el.parentNode.appendChild(rel);")
set _memory_reply_string = concat(_memory_reply_string, "  });")
set _memory_reply_string = concat(_memory_reply_string, "  updateCounter(1);")

set _memory_reply_string = concat(_memory_reply_string, "  var scroller = document.getElementById('scroll-main');")
set _memory_reply_string = concat(_memory_reply_string, "  scroller.addEventListener('scroll', function() {")
set _memory_reply_string = concat(_memory_reply_string, "    if (!scrollSpyEnabled) return;")
set _memory_reply_string = concat(_memory_reply_string, "    var scrollerRect = scroller.getBoundingClientRect();")
set _memory_reply_string = concat(_memory_reply_string, "    var blobs = document.querySelectorAll('.blob-record');")
set _memory_reply_string = concat(_memory_reply_string, "    var newIdx = currentBlob;")
set _memory_reply_string = concat(_memory_reply_string, "    for (var i = 0; i < blobs.length; i++) {")
set _memory_reply_string = concat(_memory_reply_string, "      var rect = blobs[i].getBoundingClientRect();")
set _memory_reply_string = concat(_memory_reply_string, "      if (rect.top - scrollerRect.top <= 25) {")
set _memory_reply_string = concat(_memory_reply_string, "        newIdx = i + 1;")
set _memory_reply_string = concat(_memory_reply_string, "      }")
set _memory_reply_string = concat(_memory_reply_string, "    }")
set _memory_reply_string = concat(_memory_reply_string, "    if (newIdx !== currentBlob) {")
set _memory_reply_string = concat(_memory_reply_string, "      currentBlob = newIdx;")
set _memory_reply_string = concat(_memory_reply_string, "      setActiveNav(newIdx);")
set _memory_reply_string = concat(_memory_reply_string, "      updateCounter(newIdx);")
set _memory_reply_string = concat(_memory_reply_string, "    }")
set _memory_reply_string = concat(_memory_reply_string, "  });")
set _memory_reply_string = concat(_memory_reply_string, "});")
set _memory_reply_string = concat(_memory_reply_string, "</script>")
set _memory_reply_string = concat(_memory_reply_string, "</head><body>")
set _memory_reply_string = concat(_memory_reply_string, "<div class='gp-container'>")
set _memory_reply_string = concat(_memory_reply_string, "<div class='gp-sidebar'>")

; -- Sidebar nav items — date + relative time ----------------------------------
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

set _memory_reply_string = concat(_memory_reply_string, "</div>")
set _memory_reply_string = concat(_memory_reply_string, "<div class='gp-content'>")
set _memory_reply_string = concat(_memory_reply_string, "<div class='gp-content-header'>")
set _memory_reply_string = concat(_memory_reply_string, "  <span class='gp-counter' id='blob-counter'></span>")
set _memory_reply_string = concat(_memory_reply_string, "  <div>")
set _memory_reply_string = concat(_memory_reply_string, "    <button id='btn-prev' class='nav-btn' onclick='prevBlob()'>&laquo; Previous</button>")
set _memory_reply_string = concat(_memory_reply_string, "    <button id='btn-next' class='nav-btn' onclick='nextBlob()'>Next &raquo;</button>")
set _memory_reply_string = concat(_memory_reply_string, "  </div>")
set _memory_reply_string = concat(_memory_reply_string, "</div>")
set _memory_reply_string = concat(_memory_reply_string, "<div id='scroll-main' class='gp-scroll-main'>")

; -- Blob records ---------------------------------------------------------------
set x = 1
while (x <= size(rec_blob->list, 5))
    set _memory_reply_string = concat(_memory_reply_string,
        "<div id='blob-", trim(cnvtstring(x)), "' class='blob-record' data-idx='", trim(cnvtstring(x)), "'>")
    set _memory_reply_string = concat(_memory_reply_string,
        "<div class='blob-meta'>Performed: ", rec_blob->list[x].dt_tm, " by ", rec_blob->list[x].prsnl, "</div>")
    set _memory_reply_string = concat(_memory_reply_string, "<div class='blob-text'>")

    set vLen  = textlen(rec_blob->list[x].blob_text)
    set bsize = 1
    while (bsize <= vLen)
        set _memory_reply_string = concat(_memory_reply_string, substring(bsize, 500, rec_blob->list[x].blob_text))
        set bsize = bsize + 500
    endwhile

    set _memory_reply_string = concat(_memory_reply_string, "</div></div>")
    set x = x + 1
endwhile

; Ensure final records can scroll entirely to the top 
set _memory_reply_string = concat(_memory_reply_string, "<div class='gp-bottom-spacer'></div>")

if (size(rec_blob->list, 5) = 0)
    set _memory_reply_string = concat(_memory_reply_string, "<p style='color:#666; font-style:italic; padding:20px;'>No GP Medication Details available for this patient.</p>")
endif

set _memory_reply_string = concat(_memory_reply_string, "</div></div></div></body></html>")

FREE RECORD rec_blob
END
GO