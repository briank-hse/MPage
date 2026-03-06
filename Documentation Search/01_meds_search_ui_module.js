// =============================================================================
// FILE: 01_meds_search_ui_module.js
// PURPOSE: Modular frontend UI for Global Chart Search (Edge WebView2)
// =============================================================================

var SearchModule = (function() {
    // Preserve all legacy constants from the parent MPage scope
    var containerId = 'content-frame'; 
    var isEdge = (typeof XMLCclRequest === 'undefined' && window.external && 'XMLCclRequest' in window.external);

    function renderSearchInterface(targetElementId) {
        var container = document.getElementById(targetElementId);
        if (!container) return;

        var html = `
            <div class="search-header" style="padding: 10px; background: #fff; border-bottom: 1px solid #ddd;">
                <input type="text" id="global-search-input" placeholder="Search clinical notes, powernotes, and sticky notes..." style="width: 300px; padding: 5px;">
                <button id="btn-run-search" class="tool-btn">Search Chart</button>
                <span id="search-status-indicator" style="margin-left: 10px; font-size: 12px; color: #666;"></span>
            </div>
            <div class="search-layout" style="display: flex; height: calc(100vh - 100px);">
                <div class="search-sidebar" id="search-results-sidebar" style="width: 250px; border-right: 1px solid #ddd; overflow-y: auto; background: #f8f9fa;">
                    </div>
                <div class="search-viewer" id="search-document-viewer" style="flex: 1; padding: 15px; overflow-y: auto; background: #fff;">
                    <p style="color: #888; text-align: center; margin-top: 20px;">Select a document to view.</p>
                </div>
            </div>
        `;
        
        container.innerHTML = html;
        bindEvents();
    }

    function bindEvents() {
        var btn = document.getElementById('btn-run-search');
        if (btn) {
            btn.addEventListener('click', function() {
                var term = document.getElementById('global-search-input').value;
                if (term.length < 3) {
                    alert('Please enter at least 3 characters.');
                    return;
                }
                executeSearch(term);
            });
        }
    }

    function executeSearch(searchTerm) {
        var status = document.getElementById('search-status-indicator');
        if (status) status.textContent = 'Querying database...';
        
        // This will interface with the XCR promise wrapper 
        // to call the new CCL backend we are about to build.
        console.log('Search initiated for:', searchTerm);
    }

    return {
        init: renderSearchInterface
    };
})();