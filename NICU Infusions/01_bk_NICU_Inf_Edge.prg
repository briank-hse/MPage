DROP PROGRAM   01_bk_NICU_Inf_Edge  GO
CREATE PROGRAM  01_bk_NICU_Inf_Edge

/**
 * PROGRAM: 01_bk_NICU_Inf_Edge
 *
 * Converted from 01_bk_NICU_Inf_HTML_v1_5 for Edge/WebView2 compatibility.
 *
 * OUTPUT: _memory_reply_string (required for XCR srcdoc injection via
 * the Pharmacist MPage shell).
 * SELECT INTO $OUTDEV / row +1 is not valid when called via XMLCclRequest.
 *
 * PRINT LABELS: CCLLINK() calls in the iframe srcdoc are honoured by
 * Cerner's WebView2 runtime because the output includes:
 * <meta name='discern' content='CCLLINK'/>
 * This triggers the popup label viewer, preserving existing behaviour.
 *
 * PARAMS (positional):
 * 1 - OUTDEV    (MINE)
 * 2 - PERSONID  (patient person_id as f8)
 */

prompt
    "Output to File/Printer/MINE" = "MINE"
    , "PERSONID" = 0

with OUTDEV, PERSONID

; -------------------------------------------------------------------------
; 1. DECLARE VARIABLES
; -------------------------------------------------------------------------
declare sCategory  = c1
declare sMnem      = vc
declare sCapMnem   = vc
declare sSysMnem   = vc
declare sFirstWord = vc
declare sCleanName = vc
declare iSpace     = i4
declare iBracket   = i4
declare iUnit      = i4
declare v_html     = vc   ; working HTML fragment
declare i          = i4   ; loop counter
declare v_pid      = vc with noconstant(trim(cnvtstring($PERSONID)))

; -------------------------------------------------------------------------
; 2. DEFINE RECORD STRUCTURES
; -------------------------------------------------------------------------
FREE RECORD INF_DATA
RECORD INF_DATA (
  1 cnt = i4
  1 list[*]
    2 order_id      = f8
    2 start_dt_tm   = dq8
    2 mnemonic      = vc
    2 ordered_as    = vc
    2 cat_sort      = c1   ; 1=SCI, 3=Fluid, 4=PN
    2 display_name  = vc
    2 sort_name     = vc
)

FREE RECORD INF_SORTED
RECORD INF_SORTED (
  1 cnt = i4
  1 list[*]
    2 order_id      = f8
    2 start_dt_tm   = dq8
    2 ordered_as    = vc
    2 cat_sort      = c1
    2 display_name  = vc
)

; -------------------------------------------------------------------------
; 3. GATHER DATA (Sort by ORDER_ID)
; -------------------------------------------------------------------------
SELECT INTO "nl:"
    O_ORDER_ID = O.ORDER_ID

FROM
    ORDERS         O
    , PERSON       P
    , PERSON_ALIAS PA
    , ALIAS_POOL   A
    , ENCOUNTER    E
    , ENCNTR_ALIAS EA
    , ORDER_DETAIL OD_ROUTE
    , ORDER_DETAIL OD_FORM

PLAN P WHERE P.PERSON_ID = CNVTREAL($PERSONID)
JOIN O WHERE P.PERSON_ID = O.PERSON_ID
    AND O.CURRENT_START_DT_TM >= CNVTLOOKBEHIND("100,D", CNVTDATETIME(CURDATE,curtime))
    AND O.CURRENT_START_DT_TM <= CNVTDATETIME(CURDATE,2359)
    AND O.clinical_display_line != "*Treatment of Neonatal Hyperkalaemia*"
    AND O.ORDER_STATUS_CD = 2550.00   ; Ordered
    AND O.IV_IND = 1                  ; Must be IV
    AND O.template_order_id = 0
JOIN PA WHERE PA.PERSON_ID = P.PERSON_ID
    AND PA.PERSON_ALIAS_TYPE_CD = 10.00   ; MRN
    AND PA.END_EFFECTIVE_DT_TM > SYSDATE
JOIN A WHERE A.ALIAS_POOL_CD = PA.ALIAS_POOL_CD
JOIN E WHERE E.ENCNTR_ID = O.ENCNTR_ID
JOIN EA WHERE EA.ENCNTR_ID = O.ENCNTR_ID
    AND EA.ENCNTR_ALIAS_TYPE_CD = 1077.00   ; FIN
JOIN OD_ROUTE WHERE outerjoin(O.ORDER_ID) = OD_ROUTE.ORDER_ID
    AND OD_ROUTE.OE_FIELD_MEANING_ID = outerjoin(2050)
JOIN OD_FORM WHERE outerjoin(O.ORDER_ID) = OD_FORM.ORDER_ID
    AND OD_FORM.OE_FIELD_MEANING_ID = outerjoin(2014)
    AND OD_FORM.OE_FIELD_DISPLAY_VALUE = "infusion"

ORDER BY
    O.ORDER_ID

HEAD O.ORDER_ID
    sCategory = "0"
    sMnem     = O.ORDERED_AS_MNEMONIC
    sCapMnem  = CNVTUPPER(sMnem)
    sSysMnem  = O.ORDER_MNEMONIC

    iSpace = FINDSTRING(" ", sCapMnem)
    if (iSpace > 0)
        sFirstWord = SUBSTRING(1, iSpace-1, sCapMnem)
    else
        sFirstWord = sCapMnem
    endif

    ; --- Categorisation ---
    if (sCapMnem = "PN*" OR sCapMnem = "PARENTERAL*")
        sCategory = "4"
    elseif (sFirstWord in (
            "ACTRAPID", "ADRENALINE", "ARGIPRESSIN", "DINOPROSTONE", "DOBUTAMINE", "DOPAMINE",
            "FENTANYL", "HEPARIN", "INSULIN", "MIDAZOLAM", "MILRINONE", "MORPHINE",
            "NORADRENALINE", "SILDENAFIL"
        ))
        sCategory = "1"
    elseif (sFirstWord in ("GLUCOSE", "SODIUM", "MAINTELYTE"))
        sCategory = "3"
    endif

    ; --- Add to list ---
    if (sCategory in ("1", "3", "4"))
        INF_DATA->cnt = INF_DATA->cnt + 1
        stat = alterlist(INF_DATA->list, INF_DATA->cnt)

        INF_DATA->list[INF_DATA->cnt].order_id    = O.ORDER_ID
        INF_DATA->list[INF_DATA->cnt].start_dt_tm = O.CURRENT_START_DT_TM
        INF_DATA->list[INF_DATA->cnt].ordered_as  = O.ORDERED_AS_MNEMONIC
        INF_DATA->list[INF_DATA->cnt].cat_sort    = sCategory

        if (sCategory = "1")
            if (findstring("[", O.ORDER_MNEMONIC) > 0)
                sCleanName = SUBSTRING(1, FINDSTRING("[",O.ORDER_MNEMONIC,1,0)-2, O.ORDER_MNEMONIC)
            else
                sCleanName = O.ORDER_MNEMONIC
            endif
        elseif (sCategory = "3")
            if (findstring("1 unit", O.ORDER_MNEMONIC) > 0)
                sCleanName = SUBSTRING(1, FINDSTRING("1 unit",O.ORDER_MNEMONIC,1,0)-2, O.ORDER_MNEMONIC)
            else
                sCleanName = O.ORDER_MNEMONIC
            endif
        elseif (sCategory = "4")
            if (findstring("[", O.ORDERED_AS_MNEMONIC) > 9)
                sCleanName = SUBSTRING(1, FINDSTRING("[",O.ORDERED_AS_MNEMONIC,1,0)-9, O.ORDERED_AS_MNEMONIC)
            else
                sCleanName = O.ORDERED_AS_MNEMONIC
            endif
        else
            sCleanName = sMnem
        endif

        INF_DATA->list[INF_DATA->cnt].display_name = TRIM(sCleanName)
        INF_DATA->list[INF_DATA->cnt].sort_name    = CNVTUPPER(O.ORDER_MNEMONIC)
    endif

WITH NOCOUNTER

; -------------------------------------------------------------------------
; 4. SORT THE DATA (Category -> Name)
; -------------------------------------------------------------------------
if (INF_DATA->cnt > 0)
    SELECT INTO "nl:"
        CAT  = INF_DATA->list[d.seq].cat_sort
        , NAME = INF_DATA->list[d.seq].sort_name
    FROM
        (DUMMYT D WITH SEQ = INF_DATA->cnt)
    ORDER BY
        CAT
        , NAME
    DETAIL
        INF_SORTED->cnt = INF_SORTED->cnt + 1
        stat = alterlist(INF_SORTED->list, INF_SORTED->cnt)

        INF_SORTED->list[INF_SORTED->cnt].order_id    = INF_DATA->list[d.seq].order_id
        INF_SORTED->list[INF_SORTED->cnt].start_dt_tm = INF_DATA->list[d.seq].start_dt_tm
        INF_SORTED->list[INF_SORTED->cnt].ordered_as  = INF_DATA->list[d.seq].ordered_as
        INF_SORTED->list[INF_SORTED->cnt].cat_sort    = INF_DATA->list[d.seq].cat_sort
        INF_SORTED->list[INF_SORTED->cnt].display_name = INF_DATA->list[d.seq].display_name
    WITH NOCOUNTER
endif

; -------------------------------------------------------------------------
; 5. BUILD HTML OUTPUT via _memory_reply_string
; -------------------------------------------------------------------------
set _memory_reply_string = ""

; -- Head ------------------------------------------------------------------
set _memory_reply_string = concat(_memory_reply_string,
    "<!DOCTYPE html><html lang='en'><head>",
    "<meta charset='utf-8'/>",
    ~<meta name='discern' content='CCLLINK'/>~,
    "<title>NICU Infusion Orders</title>")

; -- Styles ----------------------------------------------------------------
set _memory_reply_string = concat(_memory_reply_string, "<style>")
set _memory_reply_string = concat(_memory_reply_string,
    "*, *::before, *::after { box-sizing: border-box; }")
set _memory_reply_string = concat(_memory_reply_string,
    "body { font-family: 'Segoe UI', Tahoma, sans-serif; font-size: 12px; color: #333; margin: 0; padding: 0; }")
set _memory_reply_string = concat(_memory_reply_string,
    "table { width: 850px; border-collapse: collapse; border: 1px solid #cccccc; }")
set _memory_reply_string = concat(_memory_reply_string,
    "th { background-color: #F2F2F2; color: #333333; font-weight: bold; text-align: left; padding: 8px; border: 1px solid #cccccc; }")
set _memory_reply_string = concat(_memory_reply_string,
    "td { padding: 8px; border: 1px solid #e0e0e0; vertical-align: middle; }")
set _memory_reply_string = concat(_memory_reply_string,
    ".hdr-main { background-color: #2D5F8B; color: #FFFFFF; font-size: 14px; font-weight: bold; padding: 10px; border: 1px solid #2D5F8B; }")
set _memory_reply_string = concat(_memory_reply_string,
    ".hdr-sub { background-color: #EFF6F9; color: #555555; font-weight: bold; border: 1px solid #cccccc; }")
set _memory_reply_string = concat(_memory_reply_string,
    ".no-data { background-color: #ffffff; color: #555; font-style: italic; text-align: center; padding: 20px; }")
set _memory_reply_string = concat(_memory_reply_string,
    ".btn-print { display: inline-block; background-color: #FFFFFF; color: #333; border: 1px solid #999;",
    " padding: 5px 15px; text-decoration: none; font-weight: bold; font-size: 11px; cursor: pointer; vertical-align: middle; margin-left: 5px; }")
set _memory_reply_string = concat(_memory_reply_string,
    ".btn-print:hover { background-color: #e6f7ff; border-color: #0066CC; text-decoration: none; }")
set _memory_reply_string = concat(_memory_reply_string,
    "input { font-family: 'Courier New', monospace; border: 1px solid #999; padding: 4px; height: 26px; vertical-align: middle; }")
; -- Modal styles
set _memory_reply_string = concat(_memory_reply_string,
    "#myModalOverlay { display: none; position: fixed; top: 0; left: 0; width: 100%; height: 100%;",
    " background-color: #000000; opacity: 0.4; z-index: 9998; }")
set _memory_reply_string = concat(_memory_reply_string,
    "#myModalBox { display: none; position: fixed; top: 30%; left: 50%; width: 350px; margin-left: -175px;",
    " background-color: #fefefe; border: 1px solid #888; z-index: 9999;",
    " font-family: 'Segoe UI', Tahoma, sans-serif; box-shadow: 2px 2px 10px #aaa; }")
set _memory_reply_string = concat(_memory_reply_string,
    ".modal-header { padding: 8px 10px; background-color: #f0f0f0; border-bottom: 1px solid #ddd; }")
set _memory_reply_string = concat(_memory_reply_string,
    ".modal-title { font-weight: bold; font-size: 14px; color: #333; }")
set _memory_reply_string = concat(_memory_reply_string,
    ".modal-body { padding: 15px 10px; font-size: 13px; color: #333; }")
set _memory_reply_string = concat(_memory_reply_string,
    ".modal-footer { padding: 8px 10px; text-align: right; background-color: #f0f0f0; border-top: 1px solid #ddd; }")
set _memory_reply_string = concat(_memory_reply_string,
    ".btn-ok { padding: 3px 20px; cursor: pointer; font-family: 'Segoe UI', Tahoma, sans-serif; font-size: 12px; }")
set _memory_reply_string = concat(_memory_reply_string, "</style>")

; -- JavaScript ------------------------------------------------------------
set _memory_reply_string = concat(_memory_reply_string, "<script type='text/javascript'>")
set _memory_reply_string = concat(_memory_reply_string,
    "var lastInputId = '';")
set _memory_reply_string = concat(_memory_reply_string,
    "function showErrorModal(inputId){",
    " lastInputId = inputId;",
    " document.getElementById('myModalOverlay').style.display = 'block';",
    " document.getElementById('myModalBox').style.display = 'block';",
    " document.getElementById('modalOkBtn').focus(); }")
set _memory_reply_string = concat(_memory_reply_string,
    "function closeErrorModal(){",
    " document.getElementById('myModalOverlay').style.display = 'none';",
    " document.getElementById('myModalBox').style.display = 'none';",
    " if (lastInputId !== '') {",
    "   var el = document.getElementById(lastInputId);",
    "   if (el) { el.value = ''; el.focus(); }",
    " } }")
set _memory_reply_string = concat(_memory_reply_string,
    "function inputFocus(el) {",
    " if (el.value === 'Scan Code') { el.value = ''; el.style.color = '#000000'; el.style.fontStyle = 'normal'; } }")
set _memory_reply_string = concat(_memory_reply_string,
    "function inputBlur(el) {",
    " if (el.value === '') { el.value = 'Scan Code'; el.style.color = '#999999'; el.style.fontStyle = 'italic'; } }")
set _memory_reply_string = concat(_memory_reply_string,
    "function pnScanAndPrint(inputId, program, args, flags, expectedCode) {",
    " var el = document.getElementById(inputId);",
    " if (!el) { alert('Scan box not found.'); return false; }",
    " var scan = el.value || '';",
    " if (scan === 'Scan Code') { scan = ''; }",
    " scan = scan.replace(/[^A-Za-z0-9]/g, '').toUpperCase();",
    " var expected = (expectedCode || '').replace(/[^A-Za-z0-9]/g, '').toUpperCase();",
    " if (scan === expected || scan.indexOf(expected) === 0) { window.parent.CCLLINK(program, args, flags); return false; }",
    " showErrorModal(inputId);",
    " return false; }")
set _memory_reply_string = concat(_memory_reply_string, "</script>")

set _memory_reply_string = concat(_memory_reply_string, "</head><body>")

; -- Modal markup ----------------------------------------------------------
set _memory_reply_string = concat(_memory_reply_string,
    "<div id='myModalOverlay'></div>",
    "<div id='myModalBox'>",
    "  <div class='modal-header'><span class='modal-title'>Incorrect Code Scanned</span></div>",
    "  <div class='modal-body'>Scan does not match expected code.</div>",
    "  <div class='modal-footer'><button id='modalOkBtn' class='btn-ok' onclick='closeErrorModal()'>OK</button></div>",
    "</div>")

; -- Table header ----------------------------------------------------------
set _memory_reply_string = concat(_memory_reply_string,
    "<table cellspacing='0' cellpadding='0'>",
    "<tr><td class='hdr-main' colspan='3'>MN-CMS NICU Infusion Labels</td></tr>",
    "<tr><td class='hdr-sub' colspan='3'>Active Infusions</td></tr>",
    "<tr>",
    "<th style='width:20%'>Start Date/Time</th>",
    "<th style='width:55%'>Infusion</th>",
    "<th style='width:25%;text-align:center;'>Print Label</th>",
    "</tr>")

; -- Table rows ------------------------------------------------------------
if (INF_SORTED->cnt = 0)
    set _memory_reply_string = concat(_memory_reply_string,
        "<tr><td class='no-data' colspan='3'>No Active Infusions Found</td></tr>")
else
    for (i = 1 to INF_SORTED->cnt)

        set _memory_reply_string = concat(_memory_reply_string, "<tr>")

        ; -- Start Date/Time cell ------------------------------------------
        if (INF_SORTED->list[i].cat_sort = "1")
            set _memory_reply_string = concat(_memory_reply_string,
                ~<td bgcolor="#E8F8F5">~,
                format(INF_SORTED->list[i].start_dt_tm, "DD/MM/YYYY hh:mm;;Q"),
                "</td>")
        elseif (INF_SORTED->list[i].cat_sort = "3")
            set _memory_reply_string = concat(_memory_reply_string,
                ~<td bgcolor="#F4ECF7">~,
                format(INF_SORTED->list[i].start_dt_tm, "DD/MM/YYYY hh:mm;;Q"),
                "</td>")
        elseif (INF_SORTED->list[i].cat_sort = "4")
            set _memory_reply_string = concat(_memory_reply_string,
                ~<td bgcolor="#FEF9E7">~,
                format(INF_SORTED->list[i].start_dt_tm, "DD/MM/YYYY hh:mm;;Q"),
                "</td>")
        endif

        ; -- Mnemonic cell -------------------------------------------------
        if (INF_SORTED->list[i].cat_sort = "1")
            set _memory_reply_string = concat(_memory_reply_string,
                ~<td bgcolor="#E8F8F5"><strong>~, INF_SORTED->list[i].display_name, "</strong></td>")
        elseif (INF_SORTED->list[i].cat_sort = "3")
            set _memory_reply_string = concat(_memory_reply_string,
                ~<td bgcolor="#F4ECF7"><strong>~, INF_SORTED->list[i].display_name, "</strong></td>")
        elseif (INF_SORTED->list[i].cat_sort = "4")
            set _memory_reply_string = concat(_memory_reply_string,
                ~<td bgcolor="#FEF9E7"><strong>~, INF_SORTED->list[i].display_name, "</strong></td>")
        endif

        ; -- Print Label cell -------------------------------------------------------
        if (INF_SORTED->list[i].cat_sort = "1")
            ; SCI label — direct CCLLINK, no scan required
            set _memory_reply_string = concat(_memory_reply_string,
                ~<td bgcolor="#E8F8F5" align="center">~,
                ~<a class='btn-print' href='#'~,
                ~ onclick="window.parent.CCLLINK('01_BK_NICU_INF_FFL_FLIP_NEW:Group1', 'MINE, ~,
                v_pid, ~, ~, trim(cnvtstring(INF_SORTED->list[i].order_id), 3),
                ~', 0); return false;">Print SCI Label</a>~,
                "</td>")

        elseif (INF_SORTED->list[i].cat_sort = "3")
            ; Fluid label — direct CCLLINK, no scan required
            set _memory_reply_string = concat(_memory_reply_string,
                ~<td bgcolor="#F4ECF7" align="center">~,
                ~<a class='btn-print' href='#'~,
                ~ onclick="window.parent.CCLLINK('01_BK_NICU_FLUID_FFL_FLIPPED:Group1', 'MINE, ~,
                v_pid, ~, ~, trim(cnvtstring(INF_SORTED->list[i].order_id), 3),
                ~', 0); return false;">Print Fluid Label</a>~,
                "</td>")

        elseif (INF_SORTED->list[i].cat_sort = "4")
            ; PN label — scan verification required for cSPN1 / cSPN2 bags
            if (findstring("cSPN1", INF_SORTED->list[i].ordered_as) > 0)
                set _memory_reply_string = concat(_memory_reply_string,
                    ~<td bgcolor="#FEF9E7" align="center" style="white-space:nowrap;">~,
                    ~<input id="pn_scan_~, trim(cnvtstring(INF_SORTED->list[i].order_id), 3),
                    ~" type="text" size="12" value="Scan Code" style="color:#999;font-style:italic;"~,
                    ~ onfocus="inputFocus(this)" onblur="inputBlur(this)" />~,
                    ~ <a class='btn-print' href='#'~,
                    ~ onclick="return pnScanAndPrint('pn_scan_~, trim(cnvtstring(INF_SORTED->list[i].order_id), 3),
                    ~', '01_BK_NICU_PN_FFL_FLIPPED:Group1', 'MINE, ~,
                    v_pid, ~, ~, trim(cnvtstring(INF_SORTED->list[i].order_id), 3),
                    ~', 0, 'FDCN20019');">Print Label</a>~,
                    "</td>")

            elseif (findstring("cSPN2", INF_SORTED->list[i].ordered_as) > 0)
                set _memory_reply_string = concat(_memory_reply_string,
                    ~<td bgcolor="#FEF9E7" align="center" style="white-space:nowrap;">~,
                    ~<input id="pn_scan_~, trim(cnvtstring(INF_SORTED->list[i].order_id), 3),
                    ~" type="text" size="12" value="Scan Code" style="color:#999;font-style:italic;"~,
                    ~ onfocus="inputFocus(this)" onblur="inputBlur(this)" />~,
                    ~ <a class='btn-print' href='#'~,
                    ~ onclick="return pnScanAndPrint('pn_scan_~, trim(cnvtstring(INF_SORTED->list[i].order_id), 3),
                    ~', '01_BK_NICU_PN_FFL_FLIPPED:Group1', 'MINE, ~,
                    v_pid, ~, ~, trim(cnvtstring(INF_SORTED->list[i].order_id), 3),
                    ~', 0, 'FDCN20018');">Print Label</a>~,
                    "</td>")

            else
                ; PN without scan requirement
                set _memory_reply_string = concat(_memory_reply_string,
                    ~<td bgcolor="#FEF9E7" align="center">~,
                    ~<a class='btn-print' href='#'~,
                    ~ onclick="window.parent.CCLLINK('01_BK_NICU_PN_FFL_FLIPPED:Group1', 'MINE, ~,
                    v_pid, ~, ~, trim(cnvtstring(INF_SORTED->list[i].order_id), 3),
                    ~', 0); return false;">Print Label</a>~,
                    "</td>")
            endif
        endif

        set _memory_reply_string = concat(_memory_reply_string, "</tr>")

    endfor
endif

; -- Close table and document ----------------------------------------------
set _memory_reply_string = concat(_memory_reply_string,
    "</table>",
    "</body></html>")

end
go