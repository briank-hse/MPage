/**
 * PROGRAM: 01_meds_pharm_mpage_html_edge
 *
 * ARCHITECTURE: Lightweight async routing shell.
 *
 * Tab clicks call loadTab(program, params) which uses XMLCclRequest
 * to fetch the target CCL program's HTML output asynchronously.
 * The responseText is injected into an <iframe srcdoc> beneath the
 * persistent tab bar. The shell page never navigates away.
 *
 * EDGE NOTES:
 *   - Synchronous XMLCclRequest is not supported in Edge/WebView2.
 *     All calls use async = true (open() third param).
 *   - In Edge, XMLCclRequest lives on window.external, not as a
 *     global constructor. The shim below normalises this.
 *   - The META tag <META content="XMLCCLREQUEST" name="discern"/>
 *     triggers Cerner's runtime injection of the XMLCclRequest class.
 *   - Do NOT define your own XMLCclRequest — it overwrites Cerner's.
 *
 * STUB TEST MODE (current):
 *   01_meds_dot_date_comb_edge3:Group1 is currently a no-DB stub that
 *   confirms the XCR + srcdoc pipeline is working. Once confirmed,
 *   replace it with the real DOT program of the same name.
 *   No shell change required — the program name stays the same.
 *
 * PARAM CONSTRUCTION:
 *   ^ inside tilde-delimited strings causes CCL parse errors.
 *   All param strings are built with concat() before the select.
 */

DROP PROGRAM 01_meds_pharm_mpage_html_edge GO
CREATE PROGRAM 01_meds_pharm_mpage_html_edge

prompt
  "Output to File/Printer/MINE" = "MINE"
  , "User Id"      = 0
  , "Patient ID"   = 0
  , "Encounter Id" = 0

with OUTDEV, user_id, patient_id, encounter_id

; -- ID conversions ------------------------------------------------------------
declare v_pid    = vc with noconstant(trim(cnvtstring($patient_id)))
declare v_enc_id = vc with noconstant(trim(cnvtstring($encounter_id)))

; -- Program names -------------------------------------------------------------
; Points to 01_meds_dot_date_comb_edge3:Group1 — currently the stub,
; will be replaced in-place with the real program once pipeline is confirmed.
declare v_xcr_prog_dot = vc with noconstant("01_meds_dot_date_comb_edge3:Group1")
declare v_xcr_prog_gp  = vc with noconstant("01_meds_pharm_anvs_edge:Group1")

; -- Param strings -------------------------------------------------------------
; DOT prompts:  OUTDEV, PAT_PersonId, LOOKBACK
; GP prompts:   OUTDEV, user_id, patient_id, encounter_id
declare v_params_dot = vc with noconstant("")
declare v_params_gp  = vc with noconstant("")

set v_params_dot = concat("^MINE^,", v_pid, ".0,180.0")
set v_params_gp  = concat("^MINE^,", v_pid, ".0,", v_pid, ".0,", v_enc_id, ".0")

; -- JS variable declarations (pre-built for row +1 injection) -----------------
declare v_js_prog_dot   = vc with noconstant("")
declare v_js_params_dot = vc with noconstant("")
declare v_js_prog_gp    = vc with noconstant("")
declare v_js_params_gp  = vc with noconstant("")

set v_js_prog_dot   = build2("var PROG_DOT    = '", v_xcr_prog_dot, "';")
set v_js_params_dot = build2("var PARAMS_DOT  = '", v_params_dot,   "';")
set v_js_prog_gp    = build2("var PROG_GP     = '", v_xcr_prog_gp,  "';")
set v_js_params_gp  = build2("var PARAMS_GP   = '", v_params_gp,    "';")

select into $outdev
from dummyt d

detail

  row +1 "<!DOCTYPE html><html lang='en'><head>"
  row +1 "<meta charset='utf-8'/>"

  ; -- CRITICAL: triggers Cerner's runtime injection of XMLCclRequest --------
  row +1 "<meta name='discern' content='XMLCCLREQUEST'/>"

  row +1 "<title>Pharmacist MPage</title>"
  row +1 "<style>"

  ; -- Reset & base ------------------------------------------------------------
  row +1 "*, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }"
  row +1 "body {"
  row +1 "  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Arial, sans-serif;"
  row +1 "  font-size: 13px;"
  row +1 "  background: #f4f5f7;"
  row +1 "  color: #333;"
  row +1 "  display: flex;"
  row +1 "  flex-direction: column;"
  row +1 "  height: 100vh;"
  row +1 "  overflow: hidden;"
  row +1 "}"

  ; -- Page header removed — tab bar serves as the top chrome ------------------

  ; -- Ghost tabs (invisible, developer-accessible only) ------------------------
  row +1 ".tab-btn.ghost {"
  row +1 "  color: transparent;"
  row +1 "  cursor: default;"
  row +1 "  width: 24px;"
  row +1 "  min-width: 24px;"
  row +1 "  padding: 8px 4px;"
  row +1 "  pointer-events: auto;"
  row +1 "}"
  row +1 ".tab-btn.ghost:hover { background: transparent; }"
  row +1 "#dbg-bar {"
  row +1 "  background: #3a1a00;"
  row +1 "  color: #ffcc80;"
  row +1 "  padding: 4px 10px;"
  row +1 "  font-size: 11px;"
  row +1 "  font-family: monospace;"
  row +1 "  word-break: break-all;"
  row +1 "  white-space: pre-wrap;"
  row +1 "  flex-shrink: 0;"
  row +1 "  display: none;"
  row +1 "}"

  ; -- Tab bar ------------------------------------------------------------------
  row +1 ".tab-row {"
  row +1 "  display: flex;"
  row +1 "  align-items: flex-end;"
  row +1 "  background: #fff;"
  row +1 "  border-bottom: 2px solid #ddd;"
  row +1 "  padding: 0 8px;"
  row +1 "  flex-shrink: 0;"
  row +1 "}"
  row +1 ".tab-btn {"
  row +1 "  padding: 8px 16px;"
  row +1 "  margin-right: 4px;"
  row +1 "  cursor: pointer;"
  row +1 "  background: transparent;"
  row +1 "  border: none;"
  row +1 "  border-bottom: 3px solid transparent;"
  row +1 "  color: #666;"
  row +1 "  font-size: 13px;"
  row +1 "  font-family: inherit;"
  row +1 "  white-space: nowrap;"
  row +1 "  outline: none;"
  row +1 "  position: relative;"
  row +1 "  bottom: -2px;"
  row +1 "}"
  row +1 ".tab-btn:hover { background: #f0f4f8; color: #333; }"
  row +1 ".tab-btn.active {"
  row +1 "  border-bottom: 3px solid #006f99;"
  row +1 "  color: #006f99;"
  row +1 "  font-weight: 600;"
  row +1 "  background: #fff;"
  row +1 "}"
  row +1 ".tab-btn.placeholder { color: #aaa; cursor: default; pointer-events: none; }"

  ; -- Content iframe -----------------------------------------------------------
  row +1 "#content-frame {"
  row +1 "  flex: 1;"
  row +1 "  border: none;"
  row +1 "  width: 100%;"
  row +1 "  background: #fff;"
  row +1 "  display: none;"
  row +1 "}"

  ; -- Message area (loading / error / initial prompt) --------------------------
  row +1 "#frame-msg {"
  row +1 "  display: flex;"
  row +1 "  align-items: center;"
  row +1 "  justify-content: center;"
  row +1 "  flex: 1;"
  row +1 "  color: #888;"
  row +1 "  font-size: 14px;"
  row +1 "  background: #fff;"
  row +1 "}"

  row +1 ".placeholder-badge {"
  row +1 "  display: inline-block;"
  row +1 "  margin-left: 6px;"
  row +1 "  font-size: 10px;"
  row +1 "  background: #e0e0e0;"
  row +1 "  color: #888;"
  row +1 "  border-radius: 8px;"
  row +1 "  padding: 1px 6px;"
  row +1 "  vertical-align: middle;"
  row +1 "}"

  row +1 "</style>"

  ; -- JavaScript ---------------------------------------------------------------
  row +1 "<script>"

  ; Inject CCL-resolved values as JS constants
  row +1 v_js_prog_dot
  row +1 v_js_params_dot
  row +1 v_js_prog_gp
  row +1 v_js_params_gp

  ; -- Edge compatibility shim --------------------------------------------------
  ; In Edge/WebView2, XMLCclRequest lives on window.external.
  ; This shim creates a global constructor that matches the IE behaviour,
  ; but only if Cerner has not already injected it via the META tag above.
  row +1 "if (typeof XMLCclRequest === 'undefined' &&"
  row +1 "    window.external && 'XMLCclRequest' in window.external) {"
  row +1 "  window.XMLCclRequest = function() {"
  row +1 "    return window.external.XMLCclRequest();"
  row +1 "  };"
  row +1 "}"

  row +1 "var activeTabId = null;"
  row +1 ""

  ; -- activateTab: sets active class on clicked tab button --------------------
  row +1 "function activateTab(id) {"
  row +1 "  var tabs = document.querySelectorAll('.tab-btn');"
  row +1 "  for (var i = 0; i < tabs.length; i++) {"
  row +1 "    tabs[i].classList.remove('active');"
  row +1 "  }"
  row +1 "  var btn = document.getElementById(id);"
  row +1 "  if (btn) btn.classList.add('active');"
  row +1 "  activeTabId = id;"
  row +1 "}"
  row +1 ""

  ; -- showMsg: show text message, hide iframe ----------------------------------
  row +1 "function showMsg(msg) {"
  row +1 "  var msgDiv = document.getElementById('frame-msg');"
  row +1 "  var iframe = document.getElementById('content-frame');"
  row +1 "  if (msgDiv) { msgDiv.style.display = 'flex'; msgDiv.textContent = msg; }"
  row +1 "  if (iframe) iframe.style.display = 'none';"
  row +1 "}"
  row +1 ""

  ; -- showIframe: hide message area, show iframe -------------------------------
  row +1 "function showIframe() {"
  row +1 "  var msgDiv = document.getElementById('frame-msg');"
  row +1 "  var iframe = document.getElementById('content-frame');"
  row +1 "  if (msgDiv) msgDiv.style.display = 'none';"
  row +1 "  if (iframe) iframe.style.display = 'block';"
  row +1 "}"
  row +1 ""

  ; -- loadTab: core async loader ------------------------------------------------
  ; program : CCL program name string
  ; params  : ^-delimited param string
  ; tabId   : ID of the tab button to mark active
  row +1 "function loadTab(program, params, tabId) {"
  row +1 "  activateTab(tabId);"
  row +1 "  showMsg('Loading\u2026');"
  row +1 ""
  row +1 "  if (typeof XMLCclRequest === 'undefined') {"
  row +1 "    showMsg('ERROR: XMLCclRequest is not available in this environment.');"
  row +1 "    return;"
  row +1 "  }"
  row +1 ""
  row +1 "  var xcr = new XMLCclRequest();"
  row +1 ""
  row +1 "  xcr.onreadystatechange = function() {"
  row +1 "    if (xcr.readyState === 4) {"
  row +1 "      if (xcr.status === 200) {"
  row +1 "        var iframe = document.getElementById('content-frame');"
  row +1 "        if (iframe) {"
  row +1 "          iframe.srcdoc = xcr.responseText;"
  row +1 "          showIframe();"
  row +1 "        }"
  row +1 "      } else {"
  row +1 ~        var dbg = 'Status:' + xcr.status + ' | prog:' + program + ' | params:' + params + ' | resp:' + xcr.responseText;~
  row +1 "        var bar = document.getElementById('dbg-bar');"
  row +1 "        bar.textContent = dbg;"
  row +1 "        bar.style.display = 'block';"
  row +1 ~        showMsg('Error ' + xcr.status + ' - see debug bar above');~
  row +1 "      }"
  row +1 "    }"
  row +1 "  };"
  row +1 ""
  ; true = asynchronous — required for Edge; sync not supported
  row +1 "  xcr.open('GET', program, true);"
  row +1 "  xcr.send(params);"
  row +1 "}"
  row +1 ""

  ; -- Tab loader functions -----------------------------------------------------
  row +1 "function loadDOT() {"
  row +1 "  loadTab(PROG_DOT, PARAMS_DOT, 'tab-dot');"
  row +1 "}"
  row +1 ""
  row +1 "function loadGP() {"
  row +1 "  loadTab(PROG_GP, PARAMS_GP, 'tab-dev1');"
  row +1 "}"
  row +1 ""
  row +1 "function loadPlaceholder(tabId, label) {"
  row +1 "  activateTab(tabId);"
  row +1 ~  showMsg(label + ' \u2014 not yet available.');~
  row +1 "}"

  ; No window.onload — user must click a tab to trigger loading.

  row +1 "</script>"
  row +1 "</head>"

  ; -- Body ---------------------------------------------------------------------
  row +1 "<body>"

  row +1 "<div id='dbg-bar'></div>"

  row +1 "<div class='tab-row'>"
  row +1 "  <button id='tab-dot' class='tab-btn' onclick='loadDOT()'"
  row +1 "  >Antimicrobial Days of Therapy</button>"
  row +1 "  <div style='flex:1;'></div>"
  row +1 ~  <button id='tab-dev1' class='tab-btn ghost' onclick='loadGP()'>&nbsp;</button>~
  row +1 ~  <button id='tab-dev2' class='tab-btn ghost' onclick='loadPlaceholder("tab-dev2", "Dev 2")'>&nbsp;</button>~
  row +1 ~  <button id='tab-dev3' class='tab-btn ghost' onclick='loadPlaceholder("tab-dev3", "Dev 3")'>&nbsp;</button>~
  row +1 "</div>"

  row +1 "<div id='frame-msg'>Select a tab to load a report.</div>"

  ; sandbox="allow-scripts allow-same-origin" needed for srcdoc content
  ; that contains inline <script> tags (as the real DOT program does).
  row +1 "<iframe id='content-frame'"
  row +1 "  sandbox='allow-scripts allow-same-origin'></iframe>"

  row +1 "</body></html>"

with maxcol = 4000

end
go
