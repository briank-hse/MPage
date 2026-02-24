drop program 01_meds_pharm_mpage_rndr go
create program 01_meds_pharm_mpage_rndr

%i cust_script:01_meds_pharm_mpage_struct

declare safe_print(html_string = vc) = null
declare x = i4 with noconstant(0), protect
declare vLen = i4 with noconstant(0), protect
declare bsize = i4 with noconstant(0), protect

select distinct into mpage_data->req_info.outdev
from dummyt d
detail
    ROW + 1 call print(^<!DOCTYPE html>^)
    ROW + 1 call print(^<html><head>^)
    ROW + 1 call print(^<meta http-equiv='X-UA-Compatible' content='IE=edge'>^)
    ROW + 1 call print(^<META content='CCLLINK' name='discern'>^)

    ROW + 1 call print(^<script>^)
    ROW + 1 call print(concat(^var totalBlobs = ^, trim(cnvtstring(size(mpage_data->gp_meds, 5))), ^;^))
    ROW + 1 call print(^var currentBlob = 1;^)
    
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
    ROW + 1 call print(^  document.getElementById('dot-view').style.display = 'none';^)
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
    ROW + 1 call print(^  document.getElementById('dot-view').style.display = 'none';^)
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
    ROW + 1 call print(^  document.getElementById('dot-view').style.display = 'none';^)
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
    ROW + 1 call print(^  document.getElementById('dot-view').style.display = 'none';^)
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
    ROW + 1 call print(^  document.getElementById('med-container').style.display = 'none';^)
    ROW + 1 call print(^  document.getElementById('dot-view').style.display = 'block';^)
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

    ; --- EXACT CSS FROM PROVIDED DOT SCRIPT ---
    ROW + 1 call print(^.wrap *, .wrap *:before, .wrap *:after{box-sizing:border-box}^)
    ROW + 1 call print(^#dot-view {margin:0;font:13px/1.4 -apple-system,BlinkMacSystemFont,Segoe UI,Roboto,Arial,sans-serif;color:#111;background:#fff;padding:16px;}^)
    ROW + 1 call print(^.wrap{max-width:1200px;margin:0 auto;}^)
    ROW + 1 call print(^.wrap h1{font-size:18px;margin:0 0 8px;}^)
    ROW + 1 call print(^.wrap h2{font-size:15px;margin:16px 0 8px;padding-top:0;}^)
    ROW + 1 call print(^.sub{color:#444;margin:4px 0 16px;}^)
    ROW + 1 call print(^.legend{margin-top:6px;color:#555;font-size:12px}^)
    ROW + 1 call print(^.axisbar{display:flex;justify-content:space-between;margin:10px 0 8px calc(260px + 46px + 4px);color:#333;font-size:12px;}^)
    ROW + 1 call print(^.chart-wrap{overflow-x:auto;border:1px solid #ddd;background:#fff;margin-bottom:12px;}^)
    ROW + 1 call print(^table.chart-tbl{border-collapse:collapse;border-spacing:0;width:100%;}^)
    ROW + 1 call print(^col.med{width:260px}^)
    ROW + 1 call print(^col.dot{width:46px}^)
    ROW + 1 call print(^table.chart-tbl th, table.chart-tbl td{vertical-align:top;padding:0px 4px;text-align:left;font-size:12px;}^)
    ROW + 1 call print(^table.chart-tbl thead th{vertical-align:middle;}^)
    ROW + 1 call print(^table.data-tbl th {^)
    ROW + 1 call print(^  background:#e7eaee !important;^)
    ROW + 1 call print(^  color:#2f3c4b;^)
    ROW + 1 call print(^  border:1px solid #b5b5b5;^)
    ROW + 1 call print(^  padding:4px 8px !important;^)
    ROW + 1 call print(^  text-align:left;^)
    ROW + 1 call print(^  font-weight:600 !important;^)
    ROW + 1 call print(^  height:26px !important;^)
    ROW + 1 call print(^  line-height:1.2 !important;^)
    ROW + 1 call print(^  vertical-align:middle !important;^)
    ROW + 1 call print(^  font-size:12px !important;^)
    ROW + 1 call print(^}^)
    ROW + 1 call print(^table.chart-tbl thead th.label {^)
    ROW + 1 call print(^  background:#e7eaee !important;^)
    ROW + 1 call print(^  color:#2f3c4b;^)
    ROW + 1 call print(^  border:1px solid #b5b5b5;^)
    ROW + 1 call print(^  padding:4px 8px !important;^)
    ROW + 1 call print(^  text-align:left;^)
    ROW + 1 call print(^  font-weight:600 !important;^)
    ROW + 1 call print(^  height:26px !important;^)
    ROW + 1 call print(^  line-height:1.2 !important;^)
    ROW + 1 call print(^  vertical-align:middle !important;^)
    ROW + 1 call print(^  font-size:12px !important;^)
    ROW + 1 call print(^}^)
    ROW + 1 call print(^table.chart-tbl thead tr.ticks th{background:transparent;border:0;padding:0;color:#555;}^)
    ROW + 1 call print(^table.chart-tbl thead tr.ticks th.sticky-med, table.chart-tbl thead tr.ticks th.sticky-dot {border-right:1px solid #ccc;border-bottom:1px solid #b5b5b5;}^)
    ROW + 1 call print(^table.chart-tbl td.medname{font-size:14px !important;vertical-align:middle;padding:2px 6px;}^)
    ROW + 1 call print(^table.chart-tbl tbody td.label{vertical-align:middle;padding:2px 6px;}^)
    ROW + 1 call print(^.dot-val, table.data-tbl td.dot-val, table.chart-tbl td.dot-val{text-align:center !important;vertical-align:middle !important;}^)
    ROW + 1 call print(^table.chart-tbl tbody td.dot-val{background:#fff;}^)
    ROW + 1 call print(^table.chart-tbl tbody th.sticky-med, table.chart-tbl tbody td.sticky-med {position:sticky;left:0;background:#fff;z-index:10;border-right:1px solid #ccc;border-bottom:1px solid #d6d9dd;padding-left:8px;width:260px;}^)
    ROW + 1 call print(^table.chart-tbl tbody th.sticky-dot, table.chart-tbl tbody td.sticky-dot {position:sticky;left:260px;background:#fff;z-index:10;border-right:1px solid #ccc;border-bottom:1px solid #d6d9dd;width:46px;}^)
    ROW + 1 call print(^tr.even td.sticky-med, tr.even td.sticky-dot { background: #f5f5f5 !important; }^)
    ROW + 1 call print(^tr.even td.dot-val { background: #f5f5f5 !important; }^)
    ROW + 1 call print(^table.data-tbl tr.even td { background: #f5f5f5; }^)
    ROW + 1 call print(^table.chart-tbl tbody th.label{z-index:11;}^)
    ROW + 1 call print(^table.chart-tbl thead th.sticky-med {position:sticky;left:0;z-index:15;}^)
    ROW + 1 call print(^table.chart-tbl thead th.sticky-dot {position:sticky;left:260px;z-index:15;}^)
    ROW + 1 call print(^table.data-tbl{border-collapse:collapse;width:100%;margin-top:12px;font-size:12px;border:1px solid #b5b5b5;border-bottom:2px solid #a0a0a0;}^)
    ROW + 1 call print(^table.data-tbl td{border:1px solid #d6d9dd;padding:4px 6px;text-align:left;background:#fff;}^)
    ROW + 1 call print(^table.data-tbl tbody tr:last-child td{border-bottom:2px solid #a0a0a0;}^)
    ROW + 1 call print(^.strip{display:flex;gap:1px;align-items:center;padding:4px 0;font-size:0;white-space:nowrap;overflow:visible;}^)
    ROW + 1 call print(^.cell,.tick{flex:0 0 14px;width:14px;height:14px;display:inline-flex;align-items:center;justify-content:center;text-align:center;font-size:10px;}^)
    ROW + 1 call print(^.tick{color:#555;border:1px solid transparent;border-radius:3px;position:relative}^)
    ROW + 1 call print(^.ticks .strip{padding-top:20px}^)
    ROW + 1 call print(^.ticks .tick{overflow:visible;text-overflow:initial}^)
    ROW + 1 call print(^.tick .mo{position:absolute;top:-14px;left:50%;transform:translateX(-50%);font-size:10px;color:#555;white-space:nowrap;pointer-events:none}^)
    ROW + 1 call print(^.cell{border:1px solid #ccc;border-radius:3px;background:#fff}^)
    ROW + 1 call print(^.cell.on{background:#0086CE;border-color:#0D66A1;color:#fff;font-weight:600}^)
    ROW + 1 call print(^.cell.on:empty::before{content:"1"}^)
    ROW + 1 call print(^.cell.sum-yes{background:#ED1C24;border-color:#cc0000;}^)
    ROW + 1 call print(^.cell.sum-no{background:#A8D08D;border-color:#88b070;}^)
    ROW + 1 call print(^.summary-row td{border-top:1px solid #ccc;padding-top:4px;}^)
    ROW + 1 call print(^.ticks th{border-bottom:0;background:#fff}^)
    ROW + 1 call print(^.pill{display:inline-block;padding:2px 6px;border-radius:12px;background:#eef;color:#334;}^)
    ROW + 1 call print(^</style>^)
    ROW + 1 call print(^</head>^)

    ROW + 1 call print(^<body onload='showRestricted(); resizeLayout();'>^)

    ROW + 1 call print(^<div class='pat-header'>^)
    ROW + 1 call print(concat(^<div style='float:left;'><b>^, mpage_data->pat_info.name, ^</b> | MRN: ^, mpage_data->pat_info.mrn, ^</div>^))
    ROW + 1 call print(concat(^<div style='float:right;'><span class='wt-label'>Last Dosing Weight:</span> <span class='wt-val'>^, mpage_data->pat_info.weight_dosing, ^</span></div>^))
    ROW + 1 call print(^<div style='clear:both;'></div>^)
    ROW + 1 call print(^</div>^)

    ROW + 1 call print(^<div class='tab-row'>^)
    ROW + 1 call print(^<div id='btn1' class='tab-btn' onclick='showRestricted()'>Antibiotics</div>^)
    ROW + 1 call print(^<div id='btn2' class='tab-btn' onclick='showAll()'>All Medications</div>^)
    ROW + 1 call print(^<div id='btn3' class='tab-btn' onclick='showInfusions()'>Infusions &amp; Labels</div>^)
    ROW + 1 call print(^<div id='btn4' class='tab-btn' onclick='showGP()'>Medication Details (GP)</div>^)
    ROW + 1 call print(^<div id='btn5' class='tab-btn' onclick='showHolder2()'>Antimicrobial DOT</div>^)
    ROW + 1 call print(^</div>^)

    ; =========================================================================
    ; TAB 5: DOT Blob View
    ; =========================================================================
    ROW + 1 call print(^<div id='dot-view' style='display:none;' class='content-box'>^)
    ROW + 1 call print(^<div class="wrap">^)
    ROW + 1 call print(^<h1>Antimicrobial Administrations by Date</h1>^)
    ROW + 1 call print(^<div class="legend">Each blue square marks a <b>day</b> where the medication has been administered. A number indicates the count of administrations for that day.<br><b>Summary:</b> Red = Antimicrobial given, Green = No antimicrobial given.</div>^)
    ROW + 1 call print(mpage_data->dot.axis_html)
    
    ROW + 1 call print(^<div class="chart-wrap">^)
    ROW + 1 call print(^<table class="chart-tbl"><colgroup><col class="med"><col class="dot"><col></colgroup><thead>^)
    ROW + 1 call print(^<tr><th class="label sticky-med">Medication</th><th class="label sticky-dot">DOT</th><th class="label">Days</th></tr>^)
    if (textlen(mpage_data->dot.header_html) > 0)
        ROW + 1 call print(^<tr class="ticks"><th class="sticky-med"></th><th class="sticky-dot"></th><th><div class="strip">^)
        ROW + 1 call print(mpage_data->dot.header_html)
        ROW + 1 call print(^</div></th></tr>^)
    endif
    ROW + 1 call print(^</thead><tbody>^)

    call safe_print(mpage_data->dot.chart_rows)

    ROW + 1 call print(^</tbody></table></div>^) 

    ROW + 1 call print(^<h2>Antimicrobial Order Details</h2>^)
    ROW + 1 call print(^<table class="data-tbl">^)
    ROW + 1 call print(^<colgroup><col class="med"><col class="dot"></colgroup>^)
    ROW + 1 call print(^<thead><tr>^)
    ROW + 1 call print(^<th>Medication</th><th>DOT</th><th>Target Dose</th><th>Indication</th>^)
    ROW + 1 call print(^<th>Start Date</th><th>Latest Status</th><th>Status Date</th><th>Order ID</th>^)
    ROW + 1 call print(^</tr></thead>^)
    ROW + 1 call print(^<tbody>^)

    call safe_print(mpage_data->dot.table_rows)

    ROW + 1 call print(^</tbody></table>^)
    ROW + 1 call print(^<div class="legend" style="margin-top:8px;">Days of therapy (DOT) for antimicrobial orders which have been administered are included in this report.</div>^)
    ROW + 1 call print(^</div></div>^)

    ; =========================================================================
    ; GP Blob View
    ; =========================================================================
    ROW + 1 call print(^<div id='gp-blob-view' style='display:none;'>^)
    ROW + 1 call print(^<table id="gp-table" width="100%" border="0" cellpadding="0" cellspacing="0" style="height:500px;"><tr>^)
    
    ROW + 1 call print(^<td class="gp-sidebar"><div id="scroll-side" class="gp-scroll-side">^)
    FOR (x = 1 TO size(mpage_data->gp_meds, 5))
        IF (x = 1)
            ROW + 1 call print(concat(^<a id="nav-^, trim(cnvtstring(x)), ^" class="gp-nav-item active-nav" href="javascript:goToBlob(^, trim(cnvtstring(x)), ^)">&#128196; ^, mpage_data->gp_meds[x].dt_tm, ^</a>^))
        ELSE
            ROW + 1 call print(concat(^<a id="nav-^, trim(cnvtstring(x)), ^" class="gp-nav-item" href="javascript:goToBlob(^, trim(cnvtstring(x)), ^)">&#128196; ^, mpage_data->gp_meds[x].dt_tm, ^</a>^))
        ENDIF
    ENDFOR
    IF (size(mpage_data->gp_meds, 5) = 0)
        ROW + 1 call print(^<div class="gp-nav-item">No records</div>^)
    ENDIF
    ROW + 1 call print(^</div></td>^)

    ROW + 1 call print(^<td class="gp-content">^)
    ROW + 1 call print(^<div class="gp-content-header">^)
    ROW + 1 call print(^  <button class="nav-btn" onclick="prevBlob()">&laquo; Previous</button>^)
    ROW + 1 call print(^  <button class="nav-btn" onclick="nextBlob()">Next &raquo;</button>^)
    ROW + 1 call print(^</div>^)
    
    ROW + 1 call print(^<div id="scroll-main" class="gp-scroll-main">^)
    FOR (x = 1 TO size(mpage_data->gp_meds, 5))
        ROW + 1 call print(concat(^<a name="blob-^, trim(cnvtstring(x)), ^"></a>^))
        ROW + 1 call print(^<div class="blob-record">^)
        ROW + 1 call print(concat(^<div class="blob-meta">Performed: ^, mpage_data->gp_meds[x].dt_tm, ^ by ^, mpage_data->gp_meds[x].prsnl, ^</div>^) )
        ROW + 1 call print(^<div class="blob-text">^)

        vLen  = textlen(mpage_data->gp_meds[x].blob_text)
        bsize = 1
        WHILE (bsize <= vLen)
            call print(substring(bsize, 500, mpage_data->gp_meds[x].blob_text))
            bsize = bsize + 500
        ENDWHILE

        ROW + 1 call print(^</div></div>^)
    ENDFOR
    IF (size(mpage_data->gp_meds, 5) = 0)
        ROW + 1 call print(^<p>No GP Medication Details found for this patient.</p>^)
    ENDIF
    
    ROW + 1 call print(^<div style="height: 500px; width: 100%;"></div>^)
    ROW + 1 call print(^</div></td>^) 
    ROW + 1 call print(^</tr></table></div>^) 
    
    ; =========================================================================
    ; Main Medication View
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

    FOR (x = 1 TO size(mpage_data->orders, 5))
        IF (
               FINDSTRING("Linezolid",    mpage_data->orders[x].mnemonic) > 0
            OR FINDSTRING("Ertapenem",    mpage_data->orders[x].mnemonic) > 0
            OR FINDSTRING("Meropenem",    mpage_data->orders[x].mnemonic) > 0
            OR FINDSTRING("Vancomycin",   mpage_data->orders[x].mnemonic) > 0
            OR FINDSTRING("Gentamicin",   mpage_data->orders[x].mnemonic) > 0
            OR FINDSTRING("Amikacin",     mpage_data->orders[x].mnemonic) > 0
            OR FINDSTRING("Piperacillin", mpage_data->orders[x].mnemonic) > 0
            OR FINDSTRING("Tazobactam",   mpage_data->orders[x].mnemonic) > 0
            OR FINDSTRING("Cefotaxime",   mpage_data->orders[x].mnemonic) > 0
        )
            ROW + 1 call print(^<div class='order-item is-restricted'>^)
            call print(concat(^<b>^, mpage_data->orders[x].mnemonic, ^</b> <span style='color:red; font-size:10px; border:1px solid red; padding:0 3px;'>RESTRICTED</span>^))
        ELSE
            ROW + 1 call print(^<div class='order-item is-normal'>^)
            call print(concat(^<b>^, mpage_data->orders[x].mnemonic, ^</b>^))
        ENDIF

        call print(concat(^<div style='font-size:12px; color:#555;'>^, mpage_data->orders[x].cdl, ^</div>^))
        call print(concat(^<div style='font-size:11px; color:#999;'>Started: ^, mpage_data->orders[x].start_dt, ^</div>^))
        call print(^</div>^)

        IF (
               FINDSTRING("CONTINUOUS",   CNVTUPPER(mpage_data->orders[x].disp_cat)) > 0
            OR FINDSTRING("CONTINUOUS",   CNVTUPPER(mpage_data->orders[x].order_form)) > 0
            OR FINDSTRING("INFUSION",     CNVTUPPER(mpage_data->orders[x].order_form)) > 0
            OR FINDSTRING("ML/HR",        CNVTUPPER(mpage_data->orders[x].cdl)) > 0
            OR FINDSTRING("INTERMITTENT", CNVTUPPER(mpage_data->orders[x].disp_cat)) > 0
            OR FINDSTRING("UD",           CNVTUPPER(mpage_data->orders[x].disp_cat)) > 0
        )
            IF (
                (FINDSTRING("CONTINUOUS", CNVTUPPER(mpage_data->orders[x].disp_cat)) > 0 OR FINDSTRING("INFUSION", CNVTUPPER(mpage_data->orders[x].order_form)) > 0)
                AND
                (FINDSTRING("Glucose", mpage_data->orders[x].mnemonic) > 0 OR FINDSTRING("Sodium", mpage_data->orders[x].mnemonic) > 0 OR FINDSTRING("Maintelyte", mpage_data->orders[x].mnemonic) > 0)
            )
                ROW + 1 call print(^<div class='inf-row is-infusion'>^)
                call print(concat(^<div class='inf-col' style='width:120px;'>^, mpage_data->orders[x].start_dt, ^</div>^))
                call print(concat(^<div class='inf-col' style='width:250px;'><b>^, mpage_data->orders[x].mnemonic, ^</b></div>^))
                call print(^<div class='inf-col' style='width:80px;'><span class='type-badge' style='background:#17a2b8;'>FLUID</span></div>^)
                call print(^<div class='inf-col' style='width:150px;'>^)
                call print(concat(~<a class='print-link' href='javascript:CCLLINK("01_BK_NICU_FLUID_FFL_FLIPPED:Group1", "MINE, ~, trim(cnvtstring(mpage_data->req_info.patient_id)), ~, ~, trim(cnvtstring(mpage_data->orders[x].order_id)), ~" ,0)'>Print Fluid Label</a>~))
                call print(^</div><div style='clear:both;'></div></div>^)

            ELSEIF (FINDSTRING("INTERMITTENT", CNVTUPPER(mpage_data->orders[x].disp_cat)) > 0)
                ROW + 1 call print(^<div class='inf-row is-infusion'>^)
                call print(concat(^<div class='inf-col' style='width:120px;'>^, mpage_data->orders[x].start_dt, ^</div>^))
                call print(concat(^<div class='inf-col' style='width:250px;'><b>^, mpage_data->orders[x].mnemonic, ^</b></div>^))
                call print(^<div class='inf-col' style='width:80px;'><span class='type-badge' style='background:#ffc107; color:black;'>INTERM</span></div>^)
                call print(^<div class='inf-col' style='width:150px;'>^)
                call print(concat(~<a class='print-link' href='javascript:CCLLINK("01_BK_NICU_INTER_FFL_FLIPPED:Group1", "MINE, ~, trim(cnvtstring(mpage_data->req_info.patient_id)), ~, ~, trim(cnvtstring(mpage_data->orders[x].order_id)), ~" ,0)'>Print Intermittent Label</a>~))
                call print(^</div><div style='clear:both;'></div></div>^)

            ELSEIF (FINDSTRING("UD", CNVTUPPER(mpage_data->orders[x].disp_cat)) > 0)
                ROW + 1 call print(^<div class='inf-row is-infusion'>^)
                call print(concat(^<div class='inf-col' style='width:120px;'>^, mpage_data->orders[x].start_dt, ^</div>^))
                call print(concat(^<div class='inf-col' style='width:250px;'><b>^, mpage_data->orders[x].mnemonic, ^</b></div>^))
                call print(^<div class='inf-col' style='width:80px;'><span class='type-badge' style='background:#6c757d;'>PN / UD</span></div>^)
                call print(^<div class='inf-col' style='width:150px;'>^)
                call print(concat(~<a class='print-link' href='javascript:CCLLINK("01_BK_NICU_PN_FFL_FLIPPED:Group1", "MINE, ~, trim(cnvtstring(mpage_data->req_info.patient_id)), ~, ~, trim(cnvtstring(mpage_data->orders[x].order_id)), ~" ,0)'>Print PN Label</a>~))
                call print(^</div><div style='clear:both;'></div></div>^)

            ELSE
                ROW + 1 call print(^<div class='inf-row is-infusion'>^)
                call print(concat(^<div class='inf-col' style='width:120px;'>^, mpage_data->orders[x].start_dt, ^</div>^))
                call print(concat(^<div class='inf-col' style='width:250px;'><b>^, mpage_data->orders[x].mnemonic, ^</b></div>^))
                call print(^<div class='inf-col' style='width:80px;'><span class='type-badge' style='background:#28a745;'>SCI</span></div>^)
                call print(^<div class='inf-col' style='width:150px;'>^)
                call print(concat(~<a class='print-link' href='javascript:CCLLINK("01_BK_NICU_INF_FFL_FLIPPED:Group1", "MINE, ~, trim(cnvtstring(mpage_data->req_info.patient_id)), ~, ~, trim(cnvtstring(mpage_data->orders[x].order_id)), ~" ,0)'>Print SCI Label</a>~))
                call print(^</div><div style='clear:both;'></div></div>^)
            ENDIF
        ENDIF
    ENDFOR

    IF (size(mpage_data->orders, 5) = 0)
        ROW + 1 call print(^<div style='padding: 15px; color: #666;'>No active orders found for this patient.</div>^)
    ENDIF
    ROW + 1 call print(^</div></div>^)
    ROW + 1 call print(^</body></html>^)

WITH NOFORMAT, SEPARATOR=" ", MAXCOL=32000, LANDSCAPE

/* ====================================================================
 * SUBROUTINE: SAFE PRINT
 * Eliminates redundant printing loops and prevents chunking overflow
 * ==================================================================== */
subroutine safe_print(html_string)
    declare str_pos = i4 with noconstant(0), protect
    declare str_token = vc with constant("</tr>"), protect
    declare str_toklen = i4 with constant(5), protect
    
    set str_pos = findstring(str_token, html_string)
    while (str_pos > 0)
        row + 1 call print(substring(1, str_pos + str_toklen - 1, html_string))
        set html_string = substring(str_pos + str_toklen, textlen(html_string) - (str_pos + str_toklen - 1), html_string)
        set str_pos = findstring(str_token, html_string)
    endwhile
    
    if (textlen(html_string) > 0)
        row + 1 call print(html_string)
    endif
end

end
go