// =============================================================================
// GLOBAL STATE
// =============================================================================
var CHILD_DEBUG_MODE = true;

window.addEventListener('error', function(e) {
  if (!CHILD_DEBUG_MODE) return;
  var dbg = document.getElementById('gp-debug-box');
  if (!dbg) {
    dbg = document.createElement('div'); dbg.id = 'gp-debug-box';
    dbg.style.cssText = 'background:#f8d7da; border:1px solid #f5c6cb; color:#721c24; padding:12px; margin:10px; font-family:monospace; z-index:9999; flex-shrink:0;';
    var container = document.querySelector('.gp-container') || document.body;
    if (container) container.insertBefore(dbg, container.firstChild);
  }
  var msg = e.message || 'Unknown Error';
  dbg.innerHTML += '<strong>Global Parse Error:</strong> ' + msg + ' (Line ' + e.lineno + ', Col ' + e.colno + ')<br>';
}, true);

var totalBlobs = 0;
var currentBlob = 1;
var scrollSpyEnabled = true;
var diffMode = false;
var compareMode = false;
var compareSelected = [];
var lastSearchTerm = '';

window.blobDataRaw = [];
window.blobDataParsed = [];

// =============================================================================
// HIGH RISK MEDICATIONS
// =============================================================================
var HIGH_RISK_MEDS = [
  { label: 'LMWH',       terms: ['tinzaparin','enoxaparin','dalteparin','heparin','fragmin','innohep','clexane'] },
  { label: 'ANTICOAG',   terms: ['warfarin','apixaban','rivaroxaban','dabigatran','edoxaban','coumadin','xarelto','eliquis','pradaxa','lixiana'] },
  { label: 'VALPROATE',  terms: ['valproate','sodium valproate','valproic','epilim','depakote','convulex'] },
  { label: 'TOPIRAMATE', terms: ['topiramate','topamax'] },
  { label: 'AED',        terms: ['levetiracetam','carbamazepine','phenytoin','lamotrigine','keppra','tegretol','epanutin','lamictal','phenobarbitone','phenobarbital'] },
  { label: 'IMMUNOSUPP', terms: ['methotrexate','azathioprine','mycophenolate','ciclosporin','tacrolimus','sirolimus','everolimus','imurel','cellcept','neoral','prograf'] },
  { label: 'LITHIUM',    terms: ['lithium','priadel','liskonum'] },
  { label: 'CLOZAPINE',  terms: ['clozapine','clozaril','denzapine'] },
  { label: 'ISOTRET',    terms: ['isotretinoin','roaccutane','accutane'] },
  { label: 'THALID',     terms: ['thalidomide','lenalidomide','pomalidomide','revlimid','imnovid'] },
  { label: 'AMIODARONE', terms: ['amiodarone','cordarone'] },
  { label: 'DIGOXIN',    terms: ['digoxin','lanoxin'] },
  { label: 'INSULIN',    terms: ['insulin','novorapid','lantus','humalog','levemir','tresiba','toujeo','apidra','humulin','mixtard','novomix'] }
];

// =============================================================================
// HELPERS & UTILITIES
// =============================================================================
function escHtml(s) { 
  return s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;'); 
}

function getHighRiskMatches(text) {
  var lower = text.toLowerCase();
  var hits = [];
  for (var i = 0; i < HIGH_RISK_MEDS.length; i++) {
    var grp = HIGH_RISK_MEDS[i];
    for (var j = 0; j < grp.terms.length; j++) {
      if (lower.indexOf(grp.terms[j]) >= 0) { hits.push(grp.label); break; }
    }
  }
  return hits;
}

function relativeDate(ddmmyyyy) {
  if (!ddmmyyyy) return '';
  var parts = ddmmyyyy.split(' ')[0].split('/');
  if (parts.length < 3) return '';
  var d = new Date(parts[2], parts[1] - 1, parts[0]);
  var now = new Date();
  var diffDays = Math.floor((now - d) / 86400000);
  if (diffDays < 1)  return 'Today';
  if (diffDays < 7)  return diffDays + ' days ago';
  var diffWeeks = Math.floor(diffDays / 7);
  if (diffDays < 31) return diffWeeks + ' wks ago';
  var diffMonths = Math.round(diffDays / 30.5);
  if (diffDays < 365) return diffMonths + ' mos ago';
  var diffYears = Math.floor(diffDays / 365.25);
  return diffYears + ' yrs ago';
}

function highlightSearch(text, term) {
  if (!term) return escHtml(text);
  var safeTerm = term.replace(/[\-\[\]\/\{\}\(\)\*\+\?\.\\\^\$\|]/g, "\\$&");
  var re = new RegExp('(' + safeTerm + ')', 'gi');
  return escHtml(text).replace(re, '<mark>$1</mark>');
}

// =============================================================================
// PARSER (RESTORED TO HANDLE SECTIONS AND <br> TAGS)
// =============================================================================
var SECTION_PATTERNS = [
  { re: /prescribed med/i,   key: 'prescribed', label: 'Prescribed Medications',   cls: 'sec-prescribed' },
  { re: /discontinued med/i, key: 'discontinued', label: 'Discontinued Medications', cls: 'sec-discontinued' },
  { re: /vaccination/i,      key: 'vaccination',  label: 'Vaccination History',       cls: 'sec-vaccination' }
];

var DATE_RE = /^(\d{2}\/\d{2}\/\d{4})\s+(.+)$/;

function parseBlobText(rawHtml) {
  // Convert HTML breaks to real newlines and strip remaining tags
  var text = rawHtml.replace(/<br\s*\/?>/gi, '\n').replace(/<[^>]+>/g, '');
  var lines = text.split('\n');
  
  var sections = []; 
  var curSection = null;
  
  function flush() { if (curSection) sections.push(curSection); }
  
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].replace(/&amp;/g,'&').replace(/&lt;/g,'<').replace(/&gt;/g,'>').trim();
    if (!line) continue;
    
    // Clean out noise lines
    if (line.indexOf('(last 12 months)') >= 0) continue;
    if (line === 'CHANGED') continue;

    var isHead = false;
    for (var s = 0; s < SECTION_PATTERNS.length; s++) {
      if (SECTION_PATTERNS[s].re.test(line)) {
        flush(); 
        curSection = { key: SECTION_PATTERNS[s].key, label: SECTION_PATTERNS[s].label, cls: SECTION_PATTERNS[s].cls, rows: [] };
        isHead = true; 
        break;
      }
    }
    
    if (isHead) continue;
    if (!curSection) curSection = { key: 'other', label: '', cls: 'sec-other', rows: [] };
    
    var m = DATE_RE.exec(line);
    if (m) { 
        curSection.rows.push({ date: m[1], text: m[2], full: line }); 
    } else { 
        curSection.rows.push({ date: '', text: line, full: line }); 
    }
  }
  flush(); 
  return sections;
}

function initBlobData() {
  window.blobDataRaw = [];
  window.blobDataParsed = [];
  var elements = document.querySelectorAll('[id^="blob-raw-"]');
  elements.forEach(function(el) {
    var idx = parseInt(el.id.replace('blob-raw-', ''), 10);
    window.blobDataRaw[idx] = el.innerHTML;
    window.blobDataParsed[idx] = parseBlobText(el.innerHTML);
    if (idx > totalBlobs) totalBlobs = idx;
  });
}

// =============================================================================
// EXACT-MATCH DIFF ENGINE
// =============================================================================
function diffBlobs(idxOlder, idxNewer) {
  var diffOlder = {}; 
  var diffNewer = {}; 
  
  var secsOlder = window.blobDataParsed[idxOlder] || [];
  var secsNewer = window.blobDataParsed[idxNewer] || [];
  
function extractTextList(secs) {
    var list = [];
    for (var s = 0; s < secs.length; s++) {
      for (var r = 0; r < secs[s].rows.length; r++) {
        var rawText = secs[s].rows[r].text;
        // Normalize: lowercase, then remove ALL spaces, punctuation, and special characters
        var compKey = rawText.toLowerCase().replace(/[\W_]+/g, "");
        list.push({ secKey: secs[s].key, rIdx: r, compKey: compKey });
      }
    }
    return list;
  }
  
  var listOlder = extractTextList(secsOlder);
  var listNewer = extractTextList(secsNewer);
  
  // 1. Check what is in Newer but missing in Older (ADDED)
  for (var i = 0; i < listNewer.length; i++) {
     var foundNew = false;
     for (var j = 0; j < listOlder.length; j++) {
         if (listOlder[j].compKey === listNewer[i].compKey) { foundNew = true; break; }
     }
     if (!foundNew) {
         if (!diffNewer[listNewer[i].secKey]) diffNewer[listNewer[i].secKey] = {};
         diffNewer[listNewer[i].secKey][listNewer[i].rIdx] = { type: 'added' };
     }
  }
  
  // 2. Check what is in Older but missing in Newer (REMOVED)
  for (var k = 0; k < listOlder.length; k++) {
     var foundOld = false;
     for (var l = 0; l < listNewer.length; l++) {
         if (listNewer[l].compKey === listOlder[k].compKey) { foundOld = true; break; }
     }
     if (!foundOld) {
         if (!diffOlder[listOlder[k].secKey]) diffOlder[listOlder[k].secKey] = {};
         diffOlder[listOlder[k].secKey][listOlder[k].rIdx] = { type: 'removed' };
     }
  }
  
  return { diffOlder: diffOlder, diffNewer: diffNewer };
}

// =============================================================================
// RENDERING
// =============================================================================
function renderBlobSections(idx, diffInfoMap) {
  var sections = window.blobDataParsed[idx];
  if (!sections || !sections.length) return '<em style="color:#aaa">No content</em>';
  var html = '';
  
  for (var s = 0; s < sections.length; s++) {
    var sec = sections[s];
    html += '<div class="med-section">';
    if (sec.label) html += '<div class="med-section-heading ' + sec.cls + '">' + sec.label + '</div>';
    if (sec.rows.length === 0) html += '<div class="med-section-empty">None recorded</div>';
    
    for (var r = 0; r < sec.rows.length; r++) {
      var row = sec.rows[r];
      var diffInfo = (diffInfoMap && diffInfoMap[sec.key] && diffInfoMap[sec.key][r]) ? diffInfoMap[sec.key][r] : null;
      
      var rowCls = 'med-row' + (row.date ? '' : ' non-dated');
      if (diffInfo) rowCls += ' diff-' + diffInfo.type;
      
      var hrMatches = getHighRiskMatches(row.text);
      var hrHtml = '';
      for (var h = 0; h < hrMatches.length; h++) hrHtml += '<span class="highrisk-pill">' + hrMatches[h] + '</span>';
      
      var diffTagHtml = diffInfo ? '<span class="diff-tag diff-tag-' + diffInfo.type + '">' + diffInfo.type.toUpperCase() + '</span>' : '';
      var dispText = lastSearchTerm ? highlightSearch(row.text, lastSearchTerm) : escHtml(row.text);
      
      html += '<div class="' + rowCls + '">'; 
      if (row.date) html += '<span class="med-date">' + row.date + '</span>';
      html += '<span class="med-text">' + dispText + hrHtml + '</span>' + diffTagHtml + '</div>';
    }
    html += '</div>';
  }
  return html;
}

function renderAllBlobs(applyDiff) {
  for (var i = 1; i <= totalBlobs; i++) {
    var c = document.getElementById('blob-body-' + i); 
    if (!c) continue;
    
    var diffMap = null;
    if (applyDiff && i < totalBlobs) {
      // In main view diffing, compare current record (i) against the older one (i+1)
      var d = diffBlobs(i + 1, i); 
      diffMap = d.diffNewer;
    }
    c.innerHTML = renderBlobSections(i, diffMap);
  }
}

// =============================================================================
// SIDE-BY-SIDE COMPARE UI
// =============================================================================
function showCompareView(idxA, idxB) {
  var scroller = document.getElementById('scroll-main');
  var pane = document.getElementById('compare-pane');
  if (scroller) scroller.style.display = 'none';
  if (pane) pane.className = 'compare-pane visible';
  
  var newerIdx = Math.min(idxA, idxB);
  var olderIdx = Math.max(idxA, idxB);
  var diff = diffBlobs(olderIdx, newerIdx);
  
  var mA = document.getElementById('blob-meta-text-' + newerIdx);
  var mB = document.getElementById('blob-meta-text-' + olderIdx);
  
  var hA = document.getElementById('compare-header-a'); 
  if (hA) hA.textContent = mA ? mA.textContent : 'Record ' + newerIdx;
  
  var hB = document.getElementById('compare-header-b'); 
  if (hB) hB.textContent = mB ? mB.textContent : 'Record ' + olderIdx;
  
  var cA = document.getElementById('compare-col-a'); 
  if (cA) cA.innerHTML = renderBlobSections(newerIdx, diff.diffNewer);
  
  var cB = document.getElementById('compare-col-b'); 
  if (cB) cB.innerHTML = renderBlobSections(olderIdx, diff.diffOlder);
  
  var banner = document.getElementById('compare-banner');
  if (banner) banner.innerHTML = 'Comparing records ' + newerIdx + ' and ' + olderIdx + ' &nbsp; <button class="tool-btn" onclick="exitCompareView()">Exit Compare</button>';
}

function exitCompareView() {
  var sc = document.getElementById('scroll-main'); if (sc) sc.style.display = '';
  var pn = document.getElementById('compare-pane'); if (pn) pn.className = 'compare-pane';
  compareSelected = []; compareMode = false;
  var btn = document.getElementById('btn-compare'); if (btn) { btn.className='tool-btn'; btn.textContent='Compare'; }
  var banner = document.getElementById('compare-banner'); if (banner) banner.className = 'compare-banner';
  
  for (var i = 1; i <= totalBlobs; i++) {
    var n = document.getElementById('nav-' + i); 
    if (n) n.classList.remove('compare-sel');
  }
}

// =============================================================================
// EVENT HANDLERS & NAVIGATION
// =============================================================================
function goToBlob(idx) {
  if (compareMode) { handleCompareClick(idx); return; }
  if (idx < 1 || idx > totalBlobs) return;
  currentBlob = idx; scrollSpyEnabled = false;
  setActiveNav(idx); updateCounter(idx);
  var target = document.getElementById('blob-' + idx);
  if (target) {
    var scroller = document.getElementById('scroll-main');
    var sr = scroller.getBoundingClientRect();
    var tr = target.getBoundingClientRect();
    scroller.scrollTo({ top: scroller.scrollTop + (tr.top - sr.top) - 12, behavior: 'smooth' });
  }
  setTimeout(function() { scrollSpyEnabled = true; }, 600);
}

function nextBlob() { goToBlob(currentBlob + 1); }
function prevBlob() { goToBlob(currentBlob - 1); }

function toggleDiff() {
  diffMode = !diffMode;
  var btn = document.getElementById('btn-diff');
  if (btn) { 
    btn.className = diffMode ? 'tool-btn active' : 'tool-btn'; 
    btn.textContent = diffMode ? 'Diff ON' : 'Diff'; 
  }
  renderAllBlobs(diffMode);
}

function toggleCompare() {
  compareMode = !compareMode; compareSelected = [];
  var btn = document.getElementById('btn-compare');
  if (btn) { btn.className = compareMode ? 'tool-btn active' : 'tool-btn'; btn.textContent = compareMode ? 'Cancel' : 'Compare'; }
  var banner = document.getElementById('compare-banner');
  if (banner) { banner.className = compareMode ? 'compare-banner visible' : 'compare-banner'; banner.textContent = compareMode ? 'Compare mode: click two records in the sidebar' : ''; }
  
  if (!compareMode) {
    exitCompareView();
  }
}

function handleCompareClick(idx) {
  var n = document.getElementById('nav-' + idx);
  var pos = compareSelected.indexOf(idx);
  if (pos > -1) {
    compareSelected.splice(pos, 1);
    if (n) n.classList.remove('compare-sel');
  } else {
    compareSelected.push(idx);
    if (n) n.classList.add('compare-sel');
  }
  
  var banner = document.getElementById('compare-banner');
  if (compareSelected.length === 1 && banner) banner.textContent = 'Compare mode: 1 selected — click another record';
  if (compareSelected.length === 2) {
    showCompareView(compareSelected[0], compareSelected[1]);
  }
}

function applySearch(term) {
  lastSearchTerm = term ? term.toLowerCase() : '';
  renderAllBlobs(diffMode);
}

function onSearchInput(val) { 
  clearTimeout(window._st); 
  window._st = setTimeout(function(){ applySearch(val); }, 300); 
}

function updateCounter(idx) {
  var counterEl = document.getElementById('blob-counter');
  if (counterEl) counterEl.textContent = idx + " of " + totalBlobs;
  
  var p = document.getElementById('btn-prev'); var n = document.getElementById('btn-next');
  if (p) p.disabled = (idx <= 1); if (n) n.disabled = (idx >= totalBlobs);
}

function setActiveNav(idx) {
  for (var i = 1; i <= totalBlobs; i++) {
    var n = document.getElementById('nav-' + i); 
    if (n) n.classList.remove('active-nav');
  }
  var active = document.getElementById('nav-' + idx);
  if (active) {
    active.classList.add('active-nav');
    active.scrollIntoView({ block: 'nearest' });
  }
}

function buildSidebarFlags() {
  for (var i = 1; i <= totalBlobs; i++) {
    var raw = window.blobDataRaw[i] || "";
    var hits = getHighRiskMatches(raw.replace(/<[^>]+>/g, '')); 
    
    if (hits.length > 0) {
      var nav = document.getElementById('nav-' + i);
      if (!nav) continue;
      
      // Deduplicate hits
      var uniqueHits = [];
      for(var j=0; j<hits.length; j++) {
          if (uniqueHits.indexOf(hits[j]) === -1) uniqueHits.push(hits[j]);
      }
      
      var flags = document.createElement('div');
      flags.className = 'nav-flags';
      for(var k=0; k<uniqueHits.length; k++) {
        var sp = document.createElement('span');
        sp.className = 'nav-flag nav-flag-highrisk';
        sp.textContent = uniqueHits[k];
        flags.appendChild(sp);
      }
      nav.appendChild(flags);
    }
  }
}

// =============================================================================
// INITIALISATION
// =============================================================================
document.addEventListener('DOMContentLoaded', function() {
  if (window._gpInitialized) return;
  window._gpInitialized = true;

  initBlobData();
  renderAllBlobs(false);
  buildSidebarFlags();
  
  document.querySelectorAll('.nav-date').forEach(function(el) {
    var rel = document.createElement('span'); 
    rel.className = 'nav-rel'; 
    rel.textContent = relativeDate(el.textContent);
    el.parentNode.insertBefore(rel, el.nextSibling);
  });
  
  updateCounter(1);
  setActiveNav(1);
  
  var scroller = document.getElementById('scroll-main');
  if ('IntersectionObserver' in window) {
    var obs = new IntersectionObserver(function(entries) {
      if (!scrollSpyEnabled || diffMode || compareMode) return;
      entries.forEach(function(entry) {
        if (entry.isIntersecting) {
          var idx = parseInt(entry.target.getAttribute('data-idx'), 10);
          currentBlob = idx; 
          setActiveNav(idx); 
          updateCounter(idx);
        }
      });
    }, { root: scroller, rootMargin: '-10px 0px -85% 0px', threshold: 0 });

    document.querySelectorAll('.blob-record').forEach(function(el) { obs.observe(el); });
  }
});