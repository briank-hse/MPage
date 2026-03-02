/**
 * PROGRAM: 01_meds_pharm_mpage_html_edge
 *
 * EDGE MIGRATION ARCHITECTURE NOTE FOR FUTURE LLMs/DEVELOPERS:
 * To ensure proper parsing by the CCL compiler and correct execution within the
 * Edge/WebView2 browser engine, dynamic JavaScript links (like CCLLINK) MUST be
 * constructed using the build2() function into a declared string variable BEFORE
 * the 'select' statement.
 *
 * Do NOT place multi-argument functions like build2() directly inside a
 * 'row +1' statement, as the CCL parser will throw an 'Unexpected symbol' error
 * on the commas.
 *
 * Do NOT pass raw, unquoted Patient IDs (e.g., 18800454) to JavaScript functions,
 * as Edge may lose precision on large integers. Always use single quotes around
 * the string-converted ID parameter.
 *
 * You must stick to this variable-building approach when updating or replicating
 * this program.
 */

DROP PROGRAM 01_meds_pharm_mpage_html_edge GO
CREATE PROGRAM 01_meds_pharm_mpage_html_edge

prompt
  "Output to File/Printer/MINE" = "MINE"
  , "User Id" = 0
  , "Patient ID" = 0
  , "Encounter Id" = 0

with OUTDEV, user_id, patient_id, encounter_id

; Safely store the string conversion of the patient ID
declare v_pid = vc with noconstant(trim(cnvtstring($patient_id)))

; Declare a variable to hold the fully constructed HTML link
declare v_link_html = vc with noconstant("")

; Build the link string securely before the select statement.
; This avoids any row +1 comma-parsing compiler errors while ensuring the
; Javascript parameters are perfectly formatted for the Edge engine.
set v_link_html = build2(~<a class="report-link" href="javascript:CCLLINK('01_meds_dot_date_comb_edge:Group1','^MINE^,~, v_pid, ~,200',1)">Antimicrobial Days of Therapy &ndash; By Date</a>~)

select into $outdev
from dummyt d

detail

  row +1 "<!DOCTYPE html><html lang='en'><head>"
  row +1 "<meta charset='utf-8'/>"
  row +1 "<title>Pharmacist MPage</title>"
  row +1 "<style>"
  row +1 "  body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; background-color: #f4f5f7; margin: 20px; color: #333; }"
  row +1 "  .container { max-width: 800px; background: #fff; border: 1px solid #dcdcdc; border-radius: 4px; overflow: hidden; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }"
  row +1 "  .header { background-color: #006f99; color: #ffffff; padding: 12px 16px; font-size: 18px; font-weight: 600; }"
  row +1 "  .subheader { background-color: #c0d5dc; color: #444; padding: 8px 16px; font-weight: 600; border-bottom: 1px solid #dcdcdc; font-size: 14px; }"
  row +1 "  .content { padding: 20px 16px; }"
  row +1 "  .report-link { display: inline-block; padding: 10px 14px; margin-bottom: 24px; color: #006f99; text-decoration: none; font-weight: 500; border: 1px solid #b3d4e0; border-radius: 4px; background-color: #f0f7fa; transition: background-color 0.2s ease; font-size: 14px; }"
  row +1 "  .report-link:hover { background-color: #e0f0f5; text-decoration: none; }"
  row +1 "  .footer-text { font-size: 13px; color: #666; padding-top: 16px; border-top: 1px solid #eee; line-height: 1.5; }"
  row +1 "</style>"
  row +1 "</head><body>"
  
  row +1 "<div class='container'>"
  row +1 "  <div class='header'>Pharmacist MPage</div>"
  row +1 "  <div class='subheader'>Antimicrobial Reports</div>"
  row +1 "  <div class='content'>"
  
  /* Output the dynamically built link variable securely */
  row +1 "    ", v_link_html
  
  row +1 "    <div class='footer-text'>"
  row +1 "      The navigation buttons at the top of the page (highlighted in red below) can be used to move between the reports and the main page."
  row +1 "    </div>"
  row +1 "  </div>"
  row +1 "</div>"
  
  row +1 "</body></html>"

with maxcol=4000

end
go