DROP PROGRAM 01_meds_pharm_mpage GO
CREATE PROGRAM 01_meds_pharm_mpage
PROMPT "Output to File/Printer/MINE" = "MINE", "PatientID" = 0, "EncntrID" = 0
WITH OUTDEV, pid, eid

RECORD reply (
  1 text = vc
)

SET _memory_reply_string = BUILD2(
    "<!DOCTYPE html>",
    "<html><head>",
    "<meta name='discern' content='XMLCCLREQUEST,APPLINK,CCLLINK'/>",
    "<style>",
    "  body { font-family: Segoe UI, sans-serif; margin: 0; display: flex; flex-direction: column; height: 100vh; }",
    "  .nav-bar { background: #004b66; color: white; display: flex; padding: 0 10px; }",
    "  .nav-btn { padding: 12px 20px; cursor: pointer; border: none; background: none; color: #ccc; }",
    "  .nav-btn.active { color: white; border-bottom: 3px solid #00bad2; font-weight: bold; }",
    "  #app-root { flex: 1; overflow: auto; padding: 20px; }",
    "  .loading-spinner { border: 4px solid #f3f3f3; border-top: 4px solid #3498db; border-radius: 50%; width: 30px; height: 30px; animation: spin 2s linear infinite; }",
    "  @keyframes spin { 0% { transform: rotate(0deg); } 100% { transform: rotate(360deg); } }",
    "</style>",
    "</head><body>",

    "<div class='nav-bar'>",
    "  <button class='nav-btn' onclick='loadTab(\"ANVS\")'>GP Meds</button>",
    "  <button class='nav-btn' onclick='loadTab(\"SEARCH\")'>Search</button>",
    "  <button class='nav-btn' onclick='loadTab(\"MICRO\")'>Antimicrobial</button>",
    "  <button class='nav-btn' onclick='loadTab(\"NICU\")'>NICU Labels</button>",
    "</div>",

    "<div id='app-root'><h3>Select a tab to load clinical data.</h3></div>",

    "<script>",
    "var PATIENT_ID = ", $pid, ";",
    "var ENCNTR_ID = ", $eid, ";",

    "function loadTab(module) {",
         "var root = document.getElementById('app-root');",
         "root.innerHTML = '<div class=\"loading-spinner\"></div><p>Fetching data...</p>';",
         "var prog = '';",
         "switch(module) {",
         "  case 'ANVS':   prog = '01_meds_pharm_anvs'; break;",
         "  case 'SEARCH': prog = '01_meds_pharm_search'; break;",
         "  case 'MICRO':  prog = '01_meds_pharm_antimicrobial'; break;",
         "  case 'NICU':   prog = '01_meds_pharm_nicu_inf'; break;",
         "}",
         "callCCL(prog, root);",
    "}",

    "function callCCL(program, target) {",
    "  var xcr = window.external.XMLCclRequest();",
    "  xcr.open('GET', program, true);",
    "  xcr.onreadystatechange = function() {",
    "    if (xcr.readyState == 4 && xcr.status == 200) {",
    "      var data = JSON.parse(xcr.responseText);",
    "      renderUI(program, data, target);",
    "    }",
    "  };",
    "  xcr.send('^MINE^, ' + PATIENT_ID + ', ' + ENCNTR_ID);",
    "}",

    "function renderUI(prog, data, target) {",
    "  target.innerHTML = '<h1>' + prog + '</h1><pre>' + JSON.stringify(data, null, 2) + '</pre>';",
    "}",
    "</script>",
    "</body></html>"
)
END GO