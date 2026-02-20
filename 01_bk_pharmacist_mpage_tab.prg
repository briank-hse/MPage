DROP PROGRAM 01_bk_pharmacist_mpage_tab GO
CREATE PROGRAM 01_bk_pharmacist_mpage_tab

PROMPT
    "Output to File/Printer/MINE" = "MINE"
    , "User Id" = 0
    , "Patient ID" = 0
    , "Encounter Id" = 0
WITH OUTDEV, user_id, patient_id, encounter_id

; =============================================================================
; 1. GET MOST RECENT WEIGHT DOSING
; =============================================================================
DECLARE sWeightDisp = vc WITH noconstant("No weight dosing measured")

SELECT INTO "NL:"
FROM CLINICAL_EVENT CE
PLAN CE WHERE CE.PERSON_ID = CNVTREAL($patient_id)
    AND CE.EVENT_CD = 14516898.00
    AND CE.VALID_UNTIL_DT_TM > CNVTDATETIME(CURDATE, curtime)
    AND CE.RESULT_STATUS_CD IN (25, 34, 35)
ORDER BY
    CE.EVENT_END_DT_TM DESC
    , CE.CLINSIG_UPDT_DT_TM DESC
HEAD REPORT
    sWeightDisp = CONCAT(
        TRIM(CE.RESULT_VAL), " ",
        UAR_GET_CODE_DISPLAY(CE.RESULT_UNITS_CD),
        " (", FORMAT(CE.EVENT_END_DT_TM, "DD/MM/YY"), ")"
    )
WITH NOCOUNTER, MAXREC=1

; =============================================================================
; 2. GP MEDICATION DETAILS - BLOBGET + MEMREALLOC, DETAIL LOOP FOR MULTI-RECORD
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
    
    ; Strip default 00:00 midnight times to clean up the display
    rec_blob->list[nCnt].dt_tm    = REPLACE(FORMAT(CE.PERFORMED_DT_TM, "DD/MM/YYYY HH:MM"), " 00:00", "", 0)
    
    rec_blob->list[nCnt].prsnl    = PR.NAME_FULL_FORMATTED

    tlen       = 0
    bsize      = 0
    vCleanText = " "

    ; Step 1: BLOBGET - fetches full gc32768 content past vc truncation limit
    bloblen = blobgetlen(CB.BLOB_CONTENTS)
    stat    = memrealloc(blob_in, 1, build("C", bloblen))
    totlen  = blobget(blob_in, 0, CB.BLOB_CONTENTS)

    ; Step 2: Decompress - output buffer sized to uncompressed length
    stat = memrealloc(blob_out, 1, build("C", CB.BLOB_LENGTH))
    call uar_ocf_uncompress(blob_in, textlen(blob_in), blob_out, CB.BLOB_LENGTH, tlen)

    ; Step 3: RTF to plain text - output buffer sized to uncompressed length
    IF (tlen > 0)
        stat = memrealloc(rtf_out, 1, build("C", CB.BLOB_LENGTH))
        
        ; Verify if the blob is actually RTF before trusting uar_rtf2
        IF (FINDSTRING("{\rtf", blob_out, 1, 0) > 0)
            ; Pre-process RTF: replace \line with \par, as uar_rtf2 often ignores \line
            blob_out = REPLACE(blob_out, "\line", "\par", 0)
            tlen = TEXTLEN(blob_out)
            stat_rtf = uar_rtf2(blob_out, tlen, rtf_out, CB.BLOB_LENGTH, bsize, 0)
        ELSE
            ; Not RTF (Plain Text). Bypass uar_rtf2 completely to prevent it from stripping linebreaks!
            rtf_out = blob_out
            bsize = tlen
        ENDIF
    ENDIF

    ; Step 4: Clean text
    IF (bsize > 0)
        vCleanText = REPLACE(SUBSTRING(1, bsize, rtf_out), CHAR(0), " ", 0)
    ENDIF

    IF (TEXTLEN(TRIM(vCleanText)) <= 1)
        vCleanText = "<i>-- No narrative note found --</i>"
    ELSE
        ; HTML-escape BEFORE adding <br /> tags
        vCleanText = REPLACE(vCleanText, "&",     "&amp;", 0)
        vCleanText = REPLACE(vCleanText, "<",     "&lt;",  0)
        vCleanText = REPLACE(vCleanText, ">",     "&gt;",  0)
        
        ; Convert CRLF (\r\n) to <br /> - must replace combined sequence first
        vCleanText = REPLACE(vCleanText, concat(CHAR(13), CHAR(10)), "<br />", 0)
        vCleanText = REPLACE(vCleanText, CHAR(13), "<br />", 0)
        vCleanText = REPLACE(vCleanText, CHAR(10), "<br />", 0)
        vCleanText = REPLACE(vCleanText, CHAR(11), "<br />", 0) ; Catch vertical tabs (soft returns)
        
        ; Strip excessive consecutive returns to reduce whitespace between sections
        ; Collapses 3 or more returns down to 2 (creating exactly 1 visual blank line)
        vCleanText = REPLACE(vCleanText, "<br /><br /><br /><br /><br /><br />", "<br /><br />", 0)
        vCleanText = REPLACE(vCleanText, "<br /><br /><br /><br /><br />", "<br /><br />", 0)
        vCleanText = REPLACE(vCleanText, "<br /><br /><br /><br />", "<br /><br />", 0)
        vCleanText = REPLACE(vCleanText, "<br /><br /><br />", "<br /><br />", 0)
        
        vCleanText = TRIM(vCleanText, 3)
    ENDIF

    rec_blob->list[nCnt].blob_text = vCleanText

WITH NOCOUNTER, RDBARRAYFETCH=1

; =============================================================================
; 3. MAIN MEDICATION QUERY
; =============================================================================
SELECT DISTINCT INTO $OUTDEV
    P_NAME   = P.NAME_FULL_FORMATTED
    , MRN    = PA.ALIAS
    , ORDER_ID   = O.ORDER_ID
    , MNEMONIC   = O.ORDER_MNEMONIC
    , CDL        = O.CLINICAL_DISPLAY_LINE
    , START_DT   = FORMAT(O.CURRENT_START_DT_TM, "DD/MM/YYYY HH:MM")
    , DISP_CAT   = NULLVAL(OD_CAT.OE_FIELD_DISPLAY_VALUE, " ")
    , ORDER_FORM = NULLVAL(OD_FORM.OE_FIELD_DISPLAY_VALUE, " ")
FROM
    DUMMYT D
    , PERSON P
    , PERSON_ALIAS PA
    , ORDERS O
    , ORDER_DETAIL OD_CAT
    , ORDER_DETAIL OD_FORM

PLAN D
JOIN P WHERE P.PERSON_ID = outerjoin(CNVTREAL($patient_id))

JOIN PA WHERE PA.PERSON_ID = outerjoin(P.PERSON_ID)
    AND PA.PERSON_ALIAS_TYPE_CD = outerjoin(10.00)
    AND PA.END_EFFECTIVE_DT_TM > outerjoin(SYSDATE)

JOIN O WHERE O.PERSON_ID = outerjoin(P.PERSON_ID)
    AND O.ORDER_STATUS_CD = outerjoin(2550.00)
    AND O.ACTIVE_IND = outerjoin(1)
    AND O.ORIG_ORDER_DT_TM > outerjoin(CNVTLOOKBEHIND("400,D", CNVTDATETIME(CURDATE,curtime)))
    AND O.TEMPLATE_ORDER_ID = outerjoin(0)

JOIN OD_CAT WHERE OD_CAT.ORDER_ID = outerjoin(O.ORDER_ID)
    AND OD_CAT.OE_FIELD_MEANING_ID = outerjoin(2007)

JOIN OD_FORM WHERE OD_FORM.ORDER_ID = outerjoin(O.ORDER_ID)
    AND OD_FORM.OE_FIELD_MEANING_ID = outerjoin(2014)

ORDER BY
    D.SEQ
    , O.ORDER_MNEMONIC

; =============================================================================
; 4. HTML OUTPUT - IE5 QUIRKS MODE COMPATIBLE
; =============================================================================
HEAD REPORT
    ROW + 1 call print(^<!DOCTYPE html>^)
    ROW + 1 call print(^<html><head>^)
    ROW + 1 call print(^<meta http-equiv='X-UA-Compatible' content='IE=edge'>^)
    ROW + 1 call print(^<META content='CCLLINK' name='discern'>^)

    ROW + 1 call print(^<script>^)
    ROW + 1 call print(concat(^var totalBlobs = ^, TRIM(CNVTSTRING(size(rec_blob->list, 5))), ^;^))
    ROW + 1 call print(^var currentBlob = 1;^)
    
    ; Dynamic Resizer for IE5 Quirks Mode
    ROW + 1 call print(^function resizeLayout() {^)
    ROW + 1 call print(^  var h = document.body.clientHeight - 90;^)
    ROW + 1 call print(^  if (h < 300) h = 300;^)
    ROW + 1 call print(^  var side = document.getElementById('scroll-side');^)
    ROW + 1 call print(^  var main = document.getElementById('scroll-main');^)
    ROW + 1 call print(^  var table = document.getElementById('gp-table');^)
    ROW + 1 call print(^  if(table) table.style.height = h + 'px';^)
    ROW + 1 call print(^  if(side) side.style.height = h + 'px';^)
    ROW + 1 call print(^  if(main) main.style.height = (h - 32) + 'px';^)
    ROW + 1 call print(^}^)
    ROW + 1 call print(^window.onresize = resizeLayout;^)

    ROW + 1 call print(^function goToBlob(idx) {^)
    ROW + 1 call print(^  if (idx < 1 || idx > totalBlobs) return;^)
    ROW + 1 call print(^  currentBlob = idx;^)
    ROW + 1 call print(^  for (var i = 1; i <= totalBlobs; i++) {^)
    ROW + 1 call print(^    var navItem = document.getElementById('nav-' + i);^)
    ROW + 1 call print(^    if (navItem) {^)
    ROW + 1 call print(^      if (i == idx) { navItem.className = 'gp-nav-item active-nav'; }^)
    ROW + 1 call print(^      else { navItem.className = 'gp-nav-item'; }^)
    ROW + 1 call print(^    }^)
    ROW + 1 call print(^  }^)
    ROW + 1 call print(^  window.location.hash = 'blob-' + idx;^)
    ROW + 1 call print(^}^)
    
    ROW + 1 call print(^function nextBlob() { goToBlob(currentBlob + 1); }^)
    ROW + 1 call print(^function prevBlob() { goToBlob(currentBlob - 1); }^)

    ROW + 1 call print(^function showRestricted() {^)
    ROW + 1 call print(^  document.getElementById('med-list').className = 'list-view mode-restricted';^)
    ROW + 1 call print(^  document.getElementById('header-row-inf').style.display = 'none';^)
    ROW + 1 call print(^  document.getElementById('gp-blob-view').style.display = 'none';^)
    ROW + 1 call print(^  document.getElementById('med-container').style.display = 'block';^)
    ROW + 1 call print(^  document.getElementById('btn1').className = 'tab-btn active';^)
    ROW + 1 call print(^  document.getElementById('btn2').className = 'tab-btn';^)
    ROW + 1 call print(^  document.getElementById('btn3').className = 'tab-btn';^)
    ROW + 1 call print(^  document.getElementById('btn4').className = 'tab-btn';^)
    ROW + 1 call print(^  document.getElementById('btn5').className = 'tab-btn';^)
    ROW + 1 call print(^}^)

    ROW + 1 call print(^function showAll() {^)
    ROW + 1 call print(^  document.getElementById('med-list').className = 'list-view mode-all';^)
    ROW + 1 call print(^  document.getElementById('header-row-inf').style.display = 'none';^)
    ROW + 1 call print(^  document.getElementById('gp-blob-view').style.display = 'none';^)
    ROW + 1 call print(^  document.getElementById('med-container').style.display = 'block';^)
    ROW + 1 call print(^  document.getElementById('btn1').className = 'tab-btn';^)
    ROW + 1 call print(^  document.getElementById('btn2').className = 'tab-btn active';^)
    ROW + 1 call print(^  document.getElementById('btn3').className = 'tab-btn';^)
    ROW + 1 call print(^  document.getElementById('btn4').className = 'tab-btn';^)
    ROW + 1 call print(^  document.getElementById('btn5').className = 'tab-btn';^)
    ROW + 1 call print(^}^)

    ROW + 1 call print(^function showInfusions() {^)
    ROW + 1 call print(^  document.getElementById('med-list').className = 'list-view mode-infusion';^)
    ROW + 1 call print(^  document.getElementById('header-row-inf').style.display = 'block';^)
    ROW + 1 call print(^  document.getElementById('gp-blob-view').style.display = 'none';^)
    ROW + 1 call print(^  document.getElementById('med-container').style.display = 'block';^)
    ROW + 1 call print(^  document.getElementById('btn1').className = 'tab-btn';^)
    ROW + 1 call print(^  document.getElementById('btn2').className = 'tab-btn';^)
    ROW + 1 call print(^  document.getElementById('btn3').className = 'tab-btn active';^)
    ROW + 1 call print(^  document.getElementById('btn4').className = 'tab-btn';^)
    ROW + 1 call print(^  document.getElementById('btn5').className = 'tab-btn';^)
    ROW + 1 call print(^}^)

    ROW + 1 call print(^function showGP() {^)
    ROW + 1 call print(^  document.getElementById('med-list').className = 'list-view mode-hidden';^)
    ROW + 1 call print(^  document.getElementById('header-row-inf').style.display = 'none';^)
    ROW + 1 call print(^  document.getElementById('med-container').style.display = 'none';^)
    ROW + 1 call print(^  document.getElementById('gp-blob-view').style.display = 'block';^)
    ROW + 1 call print(^  document.getElementById('btn1').className = 'tab-btn';^)
    ROW + 1 call print(^  document.getElementById('btn2').className = 'tab-btn';^)
    ROW + 1 call print(^  document.getElementById('btn3').className = 'tab-btn';^)
    ROW + 1 call print(^  document.getElementById('btn4').className = 'tab-btn active';^)
    ROW + 1 call print(^  document.getElementById('btn5').className = 'tab-btn';^)
    ROW + 1 call print(^  resizeLayout();^)
    ROW + 1 call print(^}^)

    ROW + 1 call print(^function showHolder2() {^)
    ROW + 1 call print(^  document.getElementById('med-list').className = 'list-view mode-hidden';^)
    ROW + 1 call print(^  document.getElementById('header-row-inf').style.display = 'none';^)
    ROW + 1 call print(^  document.getElementById('gp-blob-view').style.display = 'none';^)
    ROW + 1 call print(^  document.getElementById('med-container').style.display = 'block';^)
    ROW + 1 call print(^  document.getElementById('btn1').className = 'tab-btn';^)
    ROW + 1 call print(^  document.getElementById('btn2').className = 'tab-btn';^)
    ROW + 1 call print(^  document.getElementById('btn3').className = 'tab-btn';^)
    ROW + 1 call print(^  document.getElementById('btn4').className = 'tab-btn';^)
    ROW + 1 call print(^  document.getElementById('btn5').className = 'tab-btn active';^)
    ROW + 1 call print(^}^)
    ROW + 1 call print(^</script>^)

    ROW + 1 call print(^<style>^)
    ROW + 1 call print(^body { font-family: Arial, sans-serif; background: #f4f4f4; padding: 6px 10px; color:#333; margin: 0; overflow: hidden; }^)
    ROW + 1 call print(^.pat-header { background: #fff; padding: 6px 10px; font-size: 14px; border: 1px solid #ddd; margin-bottom: 8px; box-shadow: 0 1px 2px rgba(0,0,0,0.05); }^)
    ROW + 1 call print(^.wt-val { color: #0076a8; font-weight: bold; }^)
    ROW + 1 call print(^.wt-label { font-weight: bold; color: #555; }^)
    ROW + 1 call print(^.tab-row { overflow: hidden; border-bottom: 2px solid #ddd; margin-bottom: 8px; width: 100%; }^)
    ROW + 1 call print(^.tab-btn { float: left; padding: 6px 15px; margin-right: 5px; cursor: pointer; background: transparent; border: none; border-bottom: 3px solid transparent; color: #666; font-size: 13px; }^)
    ROW + 1 call print(^.tab-btn:hover { background: #e9ecef; color: #333; }^)
    ROW + 1 call print(^.tab-btn.active { border-bottom: 3px solid #0076a8; color: #000; font-weight: bold; background: transparent; }^)
    ROW + 1 call print(^.content-box { clear: both; background: #fff; padding: 0; border: 1px solid #ddd; height: 500px; overflow-y: auto; }^)
    ROW + 1 call print(^.order-item { padding: 10px; border-bottom: 1px solid #eee; margin: 10px; }^)
    ROW + 1 call print(^.is-restricted { background-color: #fff0f0; border-left: 4px solid #dc3545; }^)
    ROW + 1 call print(^.is-normal { border-left: 4px solid #009668; }^)
    ROW + 1 call print(^.inf-header { display: none; background-color: #f8f9fa; color: #333; padding: 10px; font-weight: bold; border-bottom: 2px solid #ddd; margin: 10px; }^)
    ROW + 1 call print(^.inf-row { background-color: #fff; border-bottom: 1px solid #eee; padding: 10px; overflow: hidden; margin: 0 10px; }^)
    ROW + 1 call print(^.inf-col { float: left; padding: 5px; font-size: 13px; }^)
    ROW + 1 call print(^.print-link { color: #0076a8; text-decoration: none; cursor: pointer; font-weight: bold; }^)
    ROW + 1 call print(^.print-link:hover { text-decoration: underline; }^)
    ROW + 1 call print(^.type-badge { font-size:10px; font-weight:bold; padding:3px 8px; color:white; }^)
    
    ; --- LEGACY TABLE PANE CSS WITH NAVIGATION ---
    ROW + 1 call print(^.gp-sidebar { background: #f8f9fa; border-right: 1px solid #ddd; vertical-align: top; width: 130px; }^)
    ROW + 1 call print(^.gp-content { vertical-align: top; background: #fff; border: 1px solid #ddd; }^)
    ROW + 1 call print(^.gp-content-header { background: #f4f6f8; padding: 3px 8px; border-bottom: 1px solid #ddd; text-align: right; }^)
    ROW + 1 call print(^.nav-btn { background: #fff; border: 1px solid #ccc; padding: 4px 0; cursor: pointer; font-size: 12px; margin-left: 5px; color: #333; font-weight: bold; width: 100px; text-align: center; }^)
    ROW + 1 call print(^.nav-btn:hover { background: #e9ecef; }^)
    ROW + 1 call print(^.gp-scroll-side { overflow-y: auto; overflow-x: hidden; width: 100%; border: 1px solid #ddd; border-right: none; }^)
    ROW + 1 call print(^.gp-scroll-main { overflow-y: auto; overflow-x: hidden; width: 100%; padding: 15px; }^)
    ROW + 1 call print(^.gp-nav-item { display: block; padding: 8px 10px; color: #333; text-decoration: none; font-size: 13px; border-bottom: 1px solid #eee; }^)
    ROW + 1 call print(^.gp-nav-item:hover { background: #e2e6ea; color: #0076a8; }^)
    ROW + 1 call print(^.active-nav { background: #0076a8 !important; color: #fff !important; font-weight: bold; }^)
    ROW + 1 call print(^.blob-record { border: 1px solid #ddd; margin-bottom: 30px; padding: 15px; border-left: 4px solid #6f42c1; background: #fff; }^)
    ROW + 1 call print(^.blob-meta { background: #f4f6f8; padding: 8px 12px; font-size: 12px; margin-bottom: 10px; font-weight: bold; color: #444; }^)
    ROW + 1 call print(^.blob-text { white-space: pre-wrap; font-family: Arial, sans-serif; font-size: 13px; line-height: 1.6; color: #222; margin-top: 0; }^)
    
    ROW + 1 call print(^.mode-restricted .is-normal { display: none; }^)
    ROW + 1 call print(^.mode-restricted .is-infusion { display: none; }^)
    ROW + 1 call print(^.mode-all .is-infusion { display: none; }^)
    ROW + 1 call print(^.mode-infusion .is-restricted { display: none; }^)
    ROW + 1 call print(^.mode-infusion .is-normal { display: none; }^)
    ROW + 1 call print(^.mode-hidden { display: none; }^)
    ROW + 1 call print(^</style>^)
    ROW + 1 call print(^</head>^)

    ROW + 1 call print(^<body onload='showRestricted(); resizeLayout();'>^)

    ROW + 1 call print(^<div class='pat-header'>^)
    ROW + 1 call print(concat(^<div style='float:left;'><b>^, NULLVAL(P_NAME, "Patient Not Found"), ^</b> | MRN: ^, NULLVAL(MRN, "N/A"), ^</div>^))
    ROW + 1 call print(concat(^<div style='float:right;'><span class='wt-label'>Last Dosing Weight:</span> <span class='wt-val'>^, sWeightDisp, ^</span></div>^))
    ROW + 1 call print(^<div style='clear:both;'></div>^)
    ROW + 1 call print(^</div>^)

    ROW + 1 call print(^<div class='tab-row'>^)
    ROW + 1 call print(^<div id='btn1' class='tab-btn' onclick='showRestricted()'>Antibiotics</div>^)
    ROW + 1 call print(^<div id='btn2' class='tab-btn' onclick='showAll()'>All Medications</div>^)
    ROW + 1 call print(^<div id='btn3' class='tab-btn' onclick='showInfusions()'>Infusions &amp; Labels</div>^)
    ROW + 1 call print(^<div id='btn4' class='tab-btn' onclick='showGP()'>Medication Details (GP)</div>^)
    ROW + 1 call print(^<div id='btn5' class='tab-btn' onclick='showHolder2()'>Holder 2</div>^)
    ROW + 1 call print(^</div>^)

    ; =========================================================================
    ; GP Blob View - IE5 Table Split Pane UI with Navigation
    ; =========================================================================
    ROW + 1 call print(^<div id='gp-blob-view' style='display:none;'>^)
    ROW + 1 call print(^<table id="gp-table" width="100%" border="0" cellpadding="0" cellspacing="0" style="height:500px;"><tr>^)
    
    ; Sidebar Navigation Loop
    ROW + 1 call print(^<td class="gp-sidebar"><div id="scroll-side" class="gp-scroll-side">^)
    FOR (x = 1 TO size(rec_blob->list, 5))
        IF (x = 1)
            ROW + 1 call print(concat(^<a id="nav-^, TRIM(CNVTSTRING(x)), ^" class="gp-nav-item active-nav" href="javascript:goToBlob(^, TRIM(CNVTSTRING(x)), ^)">&#128196; ^, rec_blob->list[x].dt_tm, ^</a>^))
        ELSE
            ROW + 1 call print(concat(^<a id="nav-^, TRIM(CNVTSTRING(x)), ^" class="gp-nav-item" href="javascript:goToBlob(^, TRIM(CNVTSTRING(x)), ^)">&#128196; ^, rec_blob->list[x].dt_tm, ^</a>^))
        ENDIF
    ENDFOR
    IF (size(rec_blob->list, 5) = 0)
        ROW + 1 call print(^<div class="gp-nav-item">No records</div>^)
    ENDIF
    ROW + 1 call print(^</div></td>^) ; End sidebar

    ; Main Content Loop
    ROW + 1 call print(^<td class="gp-content">^)
    
    ; Sticky Header for Navigation Buttons
    ROW + 1 call print(^<div class="gp-content-header">^)
    ROW + 1 call print(^  <button class="nav-btn" onclick="prevBlob()">&laquo; Previous</button>^)
    ROW + 1 call print(^  <button class="nav-btn" onclick="nextBlob()">Next &raquo;</button>^)
    ROW + 1 call print(^</div>^)
    
    ROW + 1 call print(^<div id="scroll-main" class="gp-scroll-main">^)
    FOR (x = 1 TO size(rec_blob->list, 5))
        ; IE5 relies on name attribute, not id, for anchor jumps
        ROW + 1 call print(concat(^<a name="blob-^, TRIM(CNVTSTRING(x)), ^"></a>^))
        ROW + 1 call print(^<div class="blob-record">^)
        ROW + 1 call print(concat(^<div class="blob-meta">Performed: ^, rec_blob->list[x].dt_tm, ^ by ^, rec_blob->list[x].prsnl, ^</div>^) )
        ROW + 1 call print(^<div class="blob-text">^)

        vLen  = textlen(rec_blob->list[x].blob_text)
        bsize = 1
        WHILE (bsize <= vLen)
            call print(substring(bsize, 500, rec_blob->list[x].blob_text))
            bsize = bsize + 500
        ENDWHILE

        ROW + 1 call print(^</div></div>^)
    ENDFOR
    IF (size(rec_blob->list, 5) = 0)
        ROW + 1 call print(^<p>No GP Medication Details found for this patient.</p>^)
    ENDIF
    
    ; Invisible spacer ensures the final item can scroll cleanly to the top
    ROW + 1 call print(^<div style="height: 500px; width: 100%;"></div>^)
    
    ROW + 1 call print(^</div></td>^) ; End content pane
    
    ROW + 1 call print(^</tr></table></div>^) ; End gp-container & gp-blob-view
    ; =========================================================================

    ROW + 1 call print(^<div id='med-container' class='content-box'>^)
    ROW + 1 call print(^<div id='header-row-inf' class='inf-header'>^)
    ROW + 1 call print(^<div style='float:left; width:120px;'>Start Date</div>^)
    ROW + 1 call print(^<div style='float:left; width:250px;'>Infusion Name</div>^)
    ROW + 1 call print(^<div style='float:left; width:80px;'>Type</div>^)
    ROW + 1 call print(^<div style='float:left; width:150px;'>Action</div>^)
    ROW + 1 call print(^<div style='clear:both;'></div>^)
    ROW + 1 call print(^</div>^)

    ROW + 1 call print(^<div id='med-list' class='list-view'>^)

DETAIL
    IF (ORDER_ID > 0)
        IF (
               FINDSTRING("Linezolid",    MNEMONIC) > 0
            OR FINDSTRING("Ertapenem",    MNEMONIC) > 0
            OR FINDSTRING("Meropenem",    MNEMONIC) > 0
            OR FINDSTRING("Vancomycin",   MNEMONIC) > 0
            OR FINDSTRING("Gentamicin",   MNEMONIC) > 0
            OR FINDSTRING("Amikacin",     MNEMONIC) > 0
            OR FINDSTRING("Piperacillin", MNEMONIC) > 0
            OR FINDSTRING("Tazobactam",   MNEMONIC) > 0
            OR FINDSTRING("Cefotaxime",   MNEMONIC) > 0
        )
            ROW + 1 call print(^<div class='order-item is-restricted'>^)
            call print(concat(^<b>^, MNEMONIC, ^</b> <span style='color:red; font-size:10px; border:1px solid red; padding:0 3px;'>RESTRICTED</span>^))
        ELSE
            ROW + 1 call print(^<div class='order-item is-normal'>^)
            call print(concat(^<b>^, MNEMONIC, ^</b>^))
        ENDIF

        call print(concat(^<div style='font-size:12px; color:#555;'>^, CDL, ^</div>^))
        call print(concat(^<div style='font-size:11px; color:#999;'>Started: ^, START_DT, ^</div>^))
        call print(^</div>^)

        IF (
               FINDSTRING("CONTINUOUS",   CNVTUPPER(DISP_CAT)) > 0
            OR FINDSTRING("CONTINUOUS",   CNVTUPPER(ORDER_FORM)) > 0
            OR FINDSTRING("INFUSION",     CNVTUPPER(ORDER_FORM)) > 0
            OR FINDSTRING("ML/HR",        CNVTUPPER(CDL)) > 0
            OR FINDSTRING("INTERMITTENT", CNVTUPPER(DISP_CAT)) > 0
            OR FINDSTRING("UD",           CNVTUPPER(DISP_CAT)) > 0
        )
            IF (
                (FINDSTRING("CONTINUOUS", CNVTUPPER(DISP_CAT)) > 0 OR FINDSTRING("INFUSION", CNVTUPPER(ORDER_FORM)) > 0)
                AND
                (FINDSTRING("Glucose", MNEMONIC) > 0 OR FINDSTRING("Sodium", MNEMONIC) > 0 OR FINDSTRING("Maintelyte", MNEMONIC) > 0)
            )
                ROW + 1 call print(^<div class='inf-row is-infusion'>^)
                call print(concat(^<div class='inf-col' style='width:120px;'>^, START_DT, ^</div>^))
                call print(concat(^<div class='inf-col' style='width:250px;'><b>^, MNEMONIC, ^</b></div>^))
                call print(^<div class='inf-col' style='width:80px;'><span class='type-badge' style='background:#17a2b8;'>FLUID</span></div>^)
                call print(^<div class='inf-col' style='width:150px;'>^)
                call print(concat(
                    ~<a class='print-link' href='javascript:CCLLINK("01_BK_NICU_FLUID_FFL_FLIPPED:Group1", "MINE, ~,
                    TRIM(CNVTSTRING($patient_id)), ~, ~, TRIM(CNVTSTRING(ORDER_ID)), ~" ,0)'>Print Fluid Label</a>~
                ))
                call print(^</div><div style='clear:both;'></div></div>^)

            ELSEIF (FINDSTRING("INTERMITTENT", CNVTUPPER(DISP_CAT)) > 0)
                ROW + 1 call print(^<div class='inf-row is-infusion'>^)
                call print(concat(^<div class='inf-col' style='width:120px;'>^, START_DT, ^</div>^))
                call print(concat(^<div class='inf-col' style='width:250px;'><b>^, MNEMONIC, ^</b></div>^))
                call print(^<div class='inf-col' style='width:80px;'><span class='type-badge' style='background:#ffc107; color:black;'>INTERM</span></div>^)
                call print(^<div class='inf-col' style='width:150px;'>^)
                call print(concat(
                    ~<a class='print-link' href='javascript:CCLLINK("01_BK_NICU_INTER_FFL_FLIPPED:Group1", "MINE, ~,
                    TRIM(CNVTSTRING($patient_id)), ~, ~, TRIM(CNVTSTRING(ORDER_ID)), ~" ,0)'>Print Intermittent Label</a>~
                ))
                call print(^</div><div style='clear:both;'></div></div>^)

            ELSEIF (FINDSTRING("UD", CNVTUPPER(DISP_CAT)) > 0)
                ROW + 1 call print(^<div class='inf-row is-infusion'>^)
                call print(concat(^<div class='inf-col' style='width:120px;'>^, START_DT, ^</div>^))
                call print(concat(^<div class='inf-col' style='width:250px;'><b>^, MNEMONIC, ^</b></div>^))
                call print(^<div class='inf-col' style='width:80px;'><span class='type-badge' style='background:#6c757d;'>PN / UD</span></div>^)
                call print(^<div class='inf-col' style='width:150px;'>^)
                call print(concat(
                    ~<a class='print-link' href='javascript:CCLLINK("01_BK_NICU_PN_FFL_FLIPPED:Group1", "MINE, ~,
                    TRIM(CNVTSTRING($patient_id)), ~, ~, TRIM(CNVTSTRING(ORDER_ID)), ~" ,0)'>Print PN Label</a>~
                ))
                call print(^</div><div style='clear:both;'></div></div>^)

            ELSE
                ROW + 1 call print(^<div class='inf-row is-infusion'>^)
                call print(concat(^<div class='inf-col' style='width:120px;'>^, START_DT, ^</div>^))
                call print(concat(^<div class='inf-col' style='width:250px;'><b>^, MNEMONIC, ^</b></div>^))
                call print(^<div class='inf-col' style='width:80px;'><span class='type-badge' style='background:#28a745;'>SCI</span></div>^)
                call print(^<div class='inf-col' style='width:150px;'>^)
                call print(concat(
                    ~<a class='print-link' href='javascript:CCLLINK("01_BK_NICU_INF_FFL_FLIPPED:Group1", "MINE, ~,
                    TRIM(CNVTSTRING($patient_id)), ~, ~, TRIM(CNVTSTRING(ORDER_ID)), ~" ,0)'>Print SCI Label</a>~
                ))
                call print(^</div><div style='clear:both;'></div></div>^)
            ENDIF
        ENDIF
    ENDIF

FOOT REPORT
    IF (ORDER_ID = 0)
        ROW + 1 call print(^<div style='padding: 15px; color: #666;'>No active orders found for this patient.</div>^)
    ENDIF
    ROW + 1 call print(^</div></div>^)
    ROW + 1 call print(^</body></html>^)

WITH NOCOUNTER, SEPARATOR=" ", MAXCOL=32000, FORMAT, LANDSCAPE

FREE RECORD rec_blob

END
GO