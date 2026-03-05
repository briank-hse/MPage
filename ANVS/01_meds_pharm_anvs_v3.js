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

var currentBlob = 1;
var scrollSpyEnabled = true;
var diffMode = false;
var compareMode = false;
var compareSelected = [];
var lastSearchTerm = '';

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
// HELPERS
// =============================================================================
function relativeDate(ddmmyyyy) {
  var parts = ddmmyyyy.split('/');
  if (parts.length < 3) return '';
  var d = new Date(parts[2], parts[1] - 1, parts[0]);
  var now = new Date();
  var diffMs = now - d;
  var diffDays = Math.floor(diffMs / 86400000);
  if (diffDays < 1)  return 'Today';
  if (diffDays < 7)  return diffDays + ' day' + (diffDays === 1 ? '' : 's') + ' ago';
  var diffWeeks = Math.floor(diffDays / 7);
  if (diffDays < 31) return diffWeeks + ' week' + (diffWeeks === 1 ? '' : 's') + ' ago';
  var diffMonths = Math.round(diffDays / 30.5);
  if (diffDays < 365) return diffMonths + ' month' + (diffMonths === 1 ? '' : 's') + ' ago';
  var diffYears = Math.floor(diffDays / 365.25);
  var remMonths = Math.round((diffDays - diffYears * 365.25) / 30.5);
  if (remMonths === 0) return diffYears + ' yr' + (diffYears === 1 ? '' : 's') + ' ago';
  return diffYears + ' yr ' + remMonths + ' mo ago';
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

function escHtml(s) { 
  return s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;'); 
}

function escAttr(s) { 
  return s.replace(/&/g,'&amp;').replace(/"/g,'&quot;').replace(/'/g,'&#39;'); 
}

function highlightSearch(text, term) {
  var esc = escHtml(text); 
  if (!term) return esc;
  var safeTerm = term.split('').map(function(c) { return '.*+?^${}()|[]\\'.indexOf(c) > -1 ? '\\' + c : c; }).join('');
  var re = new RegExp('(' + safeTerm + ')', 'gi');
  return esc.replace(re, '<mark>$1</mark>');
}

// =============================================================================
// PARSING & DATA
// =============================================================================
var SECTION_PATTERNS = [
  { re: /prescribed med/i,   key: 'prescribed', label: 'Prescribed Medications',   cls: 'sec-prescribed' },
  { re: /discontinued med/i, key: 'discontinued', label: 'Discontinued Medications', cls: 'sec-discontinued' },
  { re: /vaccination/i,      key: 'vaccination',  label: 'Vaccination History',       cls: 'sec-vaccination' }
];

var DATE_RE = /^(\d{2}\/\d{2}\/\d{4})\s+(.+)$/;

function decodeHtmlEntities(s) {
  return s.replace(/&amp;/g,'&').replace(/&lt;/g,'<').replace(/&gt;/g,'>').replace(/&quot;/g,'"').replace(/&#39;/g,"'");
}

function parseBlobText(rawHtml) {
  var lines = rawHtml.replace(/<br\s*\/?>/gi, '\n').replace(/<[^>]+>/g, '').split('\n');
  var sections = []; var curSection = null;
  function flush() { if (curSection) sections.push(curSection); }
  for (var i = 0; i < lines.length; i++) {
    var line = decodeHtmlEntities(lines[i].trim()); if (!line) continue;
    var isHead = false;
    for (var s = 0; s < SECTION_PATTERNS.length; s++) {
      if (SECTION_PATTERNS[s].re.test(line)) {
        flush(); curSection = { key: SECTION_PATTERNS[s].key, label: SECTION_PATTERNS[s].label, cls: SECTION_PATTERNS[s].cls, rows: [] };
        isHead = true; break;
      }
    }
    if (isHead) continue;
    if (!curSection) { curSection = { key: 'other', label: '', cls: 'sec-other', rows: [] }; }
    var m = DATE_RE.exec(line);
    if (m) { curSection.rows.push({ date: m[1], text: m[2] }); }
    else { curSection.rows.push({ date: '', text: line }); }
  }
  flush(); return sections;
}

var blobData = {};
function initBlobData() {
  for (var i = 1; i <= totalBlobs; i++) {
    var el = document.getElementById('blob-raw-' + i);
    if (el) blobData[i] = parseBlobText(el.innerHTML);
  }
}

// =============================================================================
// DIFF ENGINE & RENDERING
// =============================================================================
function extractDrugKey(text) {
  var t = text.toLowerCase().replace(/[^a-z0-9 ]/g,' ').trim();
  var tokens = t.split(/\s+/);
  var doseWords = ['mg','ml','mcg','ug','g','tablet','tablets','capsule','capsules','injection','solution','cream','ointment','patch','spray','inhaler','drops','puff','puffs','unit','units','iu'];
  var key = [];
  for (var i = 0; i < Math.min(tokens.length, 6); i++) {
    if (/^\d/.test(tokens[i]) || doseWords.indexOf(tokens[i]) >= 0) break;
    key.push(tokens[i]); if (key.length >= 3) break;
  }
  return key.join(' ');
}

function diffBlobs(idxA, idxB) {
  function getPrescribed(idx) { var secs = blobData[idx]||[]; for(var i=0;i<secs.length;i++){if(secs[i].key==='prescribed')return secs[i].rows;} return []; }
  var rowsA = getPrescribed(idxA); var rowsB = getPrescribed(idxB);
  
  // Store an array of texts for each drug key to handle duplicate prescriptions
  var keysA = {}; 
  for(var i=0;i<rowsA.length;i++){ 
      var k=extractDrugKey(rowsA[i].text); 
      if(!keysA[k]) keysA[k]=[]; 
      keysA[k].push(rowsA[i].text); 
  }
  var keysB = {}; 
  for(var i=0;i<rowsB.length;i++){ 
      var k=extractDrugKey(rowsB[i].text); 
      if(!keysB[k]) keysB[k]=[]; 
      keysB[k].push(rowsB[i].text); 
  }
  
  var diffA=[]; 
  for(var i=0;i<rowsA.length;i++){
      var k=extractDrugKey(rowsA[i].text);
      var type = !keysB[k] ? 'removed' : (keysB[k].indexOf(rowsA[i].text) < 0 ? 'changed' : 'unchanged');
      diffA.push({type: type, row:rowsA[i]});
  }
  
  var diffB=[]; 
  for(var i=0;i<rowsB.length;i++){
      var k=extractDrugKey(rowsB[i].text);
      var type = !keysA[k] ? 'added' : (keysA[k].indexOf(rowsB[i].text) < 0 ? 'changed' : 'unchanged');
      diffB.push({type: type, row:rowsB[i]});
  }
  
  return { diffA: diffA, diffB: diffB };
}

function renderBlobSections(idx, diffRows) {
  var sections = blobData[idx];
  if (!sections || !sections.length) return '<em style="color:#aaa">No content</em>';
  var html = '';
  for (var s = 0; s < sections.length; s++) {
    var sec = sections[s];
    html += '<div class="med-section">';
    if (sec.label) html += '<div class="med-section-heading ' + sec.cls + '">' + sec.label + '</div>';
    if (sec.rows.length === 0) html += '<div class="med-section-empty">None recorded</div>';
    for (var r = 0; r < sec.rows.length; r++) {
      var row = sec.rows[r];
      var diffInfo = (diffRows && sec.key === 'prescribed') ? (diffRows[r] || null) : null;
      var rowCls = 'med-row' + (row.date ? '' : ' non-dated');
      if (diffInfo) rowCls += ' diff-' + diffInfo.type;
      var hrMatches = getHighRiskMatches(row.text);
      var hrHtml = '';
      for (var h = 0; h < hrMatches.length; h++) hrHtml += '<span class="highrisk-pill">' + hrMatches[h] + '</span>';
      var diffTagHtml = (diffInfo && diffInfo.type !== 'unchanged') ? '<span class="diff-tag diff-tag-' + diffInfo.type + '">' + diffInfo.type.toUpperCase() + '</span>' : '';
      var dispText = lastSearchTerm ? highlightSearch(row.text, lastSearchTerm) : escHtml(row.text);
      html += '<div class="' + rowCls + '" data-medtext="' + escAttr(row.text) + '">'; 
      if (row.date) html += '<span class="med-date">' + row.date + '</span>';
      html += '<span class="med-text">' + dispText + hrHtml + '</span>' + diffTagHtml + '</div>';
    }
    html += '</div>';
  }
  return html;
}

function renderAllBlobs(applyDiff) {
  for (var i = 1; i <= totalBlobs; i++) {
    var c = document.getElementById('blob-body-' + i); if (!c) continue;
    var diffRows = null;
    if (applyDiff && i < totalBlobs) {
      var d = diffBlobs(i, i+1); diffRows = {};
      for (var r = 0; r < d.diffA.length; r++) diffRows[r] = { type: d.diffA[r].type };
    }
    c.innerHTML = renderBlobSections(i, diffRows);
  }
}

// =============================================================================
// UI INTERACTIONS
// =============================================================================
function updateCounter(idx) {
  var el = document.getElementById('blob-counter');
  if (el) el.textContent = idx + ' of ' + totalBlobs;
  var p = document.getElementById('btn-prev'); var n = document.getElementById('btn-next');
  if (p) p.disabled = (idx <= 1); if (n) n.disabled = (idx >= totalBlobs);
}

function setActiveNav(idx) {
  for (var i = 1; i <= totalBlobs; i++) {
    var n = document.getElementById('nav-' + i); if (!n) continue;
    if (i === idx) {
      n.classList.add('active-nav');
    } else {
      n.classList.remove('active-nav');
    }
  }
  var active = document.getElementById('nav-' + idx);
  if (active) active.scrollIntoView({ block: 'nearest' });
}

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
  if (btn) { btn.className = diffMode ? 'tool-btn active' : 'tool-btn'; btn.textContent = diffMode ? 'Diff ON' : 'Diff'; }
  renderAllBlobs(diffMode); applySearch(lastSearchTerm);
}

function toggleCompare() {
  compareMode = !compareMode; compareSelected = [];
  var btn = document.getElementById('btn-compare');
  if (btn) { btn.className = compareMode ? 'tool-btn active' : 'tool-btn'; btn.textContent = compareMode ? 'Select 2...' : 'Compare'; }
  var banner = document.getElementById('compare-banner');
  if (banner) { banner.className = compareMode ? 'compare-banner visible' : 'compare-banner'; banner.textContent = compareMode ? 'Compare mode: click two records in the sidebar' : ''; }
  if (!compareMode) exitCompareView();
  clearCompareHighlights();
}

function clearCompareHighlights() {
  for (var i=1;i<=totalBlobs;i++){
    var n=document.getElementById('nav-'+i); 
    if(n) n.classList.remove('compare-sel');
  }
}

function handleCompareClick(idx) {
  if (compareSelected.indexOf(idx) >= 0) return;
  compareSelected.push(idx);
  var n = document.getElementById('nav-' + idx);
  if (n) n.classList.add('compare-sel');
  var banner = document.getElementById('compare-banner');
  if (compareSelected.length === 1 && banner) banner.textContent = 'Compare mode: 1 selected — click another record';
  if (compareSelected.length === 2) showCompareView(compareSelected[0], compareSelected[1]);
}

function showCompareView(idxA, idxB) {
  var scroller = document.getElementById('scroll-main');
  var pane = document.getElementById('compare-pane');
  if (scroller) scroller.style.display = 'none';
  if (pane) pane.className = 'compare-pane visible';
  var diff = diffBlobs(idxA, idxB);
  var mA = document.getElementById('blob-meta-text-' + idxA);
  var mB = document.getElementById('blob-meta-text-' + idxB);
  var hA = document.getElementById('compare-header-a'); if (hA) hA.textContent = mA ? mA.textContent : 'Record ' + idxA;
  var hB = document.getElementById('compare-header-b'); if (hB) hB.textContent = mB ? mB.textContent : 'Record ' + idxB;
  var drA={}; for(var r=0;r<diff.diffA.length;r++) drA[r]={type:diff.diffA[r].type};
  var drB={}; for(var r=0;r<diff.diffB.length;r++) drB[r]={type:diff.diffB[r].type};
  var cA = document.getElementById('compare-col-a'); if (cA) cA.innerHTML = renderBlobSections(idxA, drA);
  var cB = document.getElementById('compare-col-b'); if (cB) cB.innerHTML = renderBlobSections(idxB, drB);
  var banner = document.getElementById('compare-banner');
  if (banner) banner.innerHTML = 'Comparing records ' + idxA + ' and ' + idxB + ' &nbsp; <button class="tool-btn" onclick="exitCompareView()">Exit Compare</button>';
}

function exitCompareView() {
  var sc = document.getElementById('scroll-main'); if (sc) sc.style.display = '';
  var pn = document.getElementById('compare-pane'); if (pn) pn.className = 'compare-pane';
  compareSelected = []; compareMode = false;
  var btn = document.getElementById('btn-compare'); if (btn) { btn.className='tool-btn'; btn.textContent='Compare'; }
  var banner = document.getElementById('compare-banner'); if (banner) banner.className = 'compare-banner';
  clearCompareHighlights();
}

function applySearch(term) {
  lastSearchTerm = term ? term.toLowerCase() : '';
  renderAllBlobs(diffMode);
  var matchCount = 0; var blobHits = [];
  for (var i = 1; i <= totalBlobs; i++) {
    var rows = document.querySelectorAll('#blob-' + i + ' .med-row');
    var blobMatch = false;
    for (var r = 0; r < rows.length; r++) {
      if (lastSearchTerm && (rows[r].getAttribute('data-medtext')||'').toLowerCase().indexOf(lastSearchTerm) >= 0) {
        rows[r].classList.add('search-hit'); matchCount++; blobMatch = true;
      }
    }
    var navItem = document.getElementById('nav-' + i);
    if (navItem) { var esf = navItem.querySelector('.nav-flag-search'); if (esf) esf.parentNode.removeChild(esf); }
    if (blobMatch && navItem) {
      blobHits.push(i);
      var flags = navItem.querySelector('.nav-flags'); if (!flags) { flags = document.createElement('div'); flags.className='nav-flags'; navItem.appendChild(flags); }
      var sf = document.createElement('span'); sf.className='nav-flag nav-flag-search'; sf.textContent='MATCH'; flags.appendChild(sf);
    }
  }
  var info = document.getElementById('search-info');
  if (info) info.textContent = lastSearchTerm ? (matchCount + ' match' + (matchCount===1?'':'es') + ' in ' + blobHits.length + ' record' + (blobHits.length===1?'':'s')) : '';
  if (blobHits.length > 0) goToBlob(blobHits[0]);
}

function onSearchInput(val) { clearTimeout(window._st); window._st = setTimeout(function(){applySearch(val);},300); }

function buildSidebarFlags() {
  for (var i=1;i<=totalBlobs;i++){
    var raw=document.getElementById('blob-raw-'+i); if(!raw) continue;
    var hits=getHighRiskMatches(raw.textContent||raw.innerText||''); if(!hits.length) continue;
    var nav=document.getElementById('nav-'+i); if(!nav) continue;
    var flags=document.createElement('div'); flags.className='nav-flags';
    for(var h=0;h<hits.length;h++){
      var sp=document.createElement('span');
      sp.className='nav-flag nav-flag-highrisk';
      sp.textContent=hits[h];
      flags.appendChild(sp);
    }
    nav.appendChild(flags);
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
    var rel = document.createElement('span'); rel.className='nav-rel'; rel.textContent=relativeDate(el.textContent);
    el.parentNode.insertBefore(rel, el.nextSibling);
  });
  
  updateCounter(1);
  setActiveNav(1);
  
  var scroller = document.getElementById('scroll-main');
  if ('IntersectionObserver' in window) {
    var obs = new IntersectionObserver(function(entries) {
      if (!scrollSpyEnabled) return;
      entries.forEach(function(entry) {
        if (entry.isIntersecting) {
          var idx = parseInt(entry.target.getAttribute('data-idx'),10);
          currentBlob=idx; setActiveNav(idx); updateCounter(idx);
        }
      });
    }, { root: scroller, rootMargin: '-10px 0px -85% 0px', threshold: 0 });
    document.querySelectorAll('.blob-record').forEach(function(el) { obs.observe(el); });
  }
});