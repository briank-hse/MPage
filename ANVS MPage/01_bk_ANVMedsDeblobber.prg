drop program 01_bk_ANVMedsDeblobber go
create program 01_bk_ANVMedsDeblobber

prompt 
	"Output to File/Printer/MINE" = "MINE"
	, "PAT_PersonId" = 12441103

with OUTDEV, PAT_PersonId

; Pre-fetch OCF compression code
SET OcfCD = 0.0
Set stat = uar_get_meaning_by_codeset(120,"OCFCOMP",1,OcfCD)

; Buffer management
set vBlobOut = fillstring(65536, ' ')
set vBlobNoRTF = fillstring(65536, ' ')
set vCleanText = fillstring(65536, ' ')
set bsize = 0
set out_len = 0
set trimmedOCFBlob = 0

SELECT INTO $outdev
	BlobIn = TRIM(cb.blob_contents)
	, textlen = TEXTLEN(TRIM(cb.blob_contents))
	, C.PERFORMED_DT_TM
	, cb.event_id
	, cb.blob_seq_num
	, cb.BLOB_LENGTH
	, cb.VALID_FROM_DT_TM
	, cb.VALID_UNTIL_DT_TM
	, NAME = TRIM(P.NAME_FULL_FORMATTED)
	, MRN = TRIM(PA.ALIAS)
	, FIN = TRIM(EA.ALIAS)
	, c.clinsig_updt_dt_tm "DD/MM/YYYY"
	, HOSPITAL = UAR_GET_CODE_DISPLAY(E.LOC_FACILITY_CD)
	, PR.NAME_FULL_FORMATTED

FROM
	ce_blob cb
	, CLINICAL_EVENT C
	, PERSON P
	, PERSON_ALIAS PA
	, ENCOUNTER E
	, ENCNTR_ALIAS EA
	, PRSNL PR

Plan P WHERE P.PERSON_ID = $PAT_PersonId

Join C WHERE P.PERSON_ID = C.PERSON_ID
	;WHERE C.PERFORMED_DT_TM BETWEEN CNVTDATETIME(CURDATE-2, CURTIME) AND CNVTDATETIME(CURDATE, CURTIME)
	AND C.EVENT_CD IN (25256529) ; Medication Details (GP)
	AND C.VALID_UNTIL_DT_TM > SYSDATE 

JOIN CB WHERE CB.EVENT_ID = C.EVENT_ID
	AND CB.VALID_UNTIL_DT_TM > SYSDATE

JOIN E WHERE C.ENCNTR_ID = E.ENCNTR_ID

JOIN PA WHERE PA.PERSON_ID = P.PERSON_ID
	AND PA.PERSON_ALIAS_TYPE_CD = 10.00 ; MRN
	AND PA.END_EFFECTIVE_DT_TM > SYSDATE 

JOIN EA WHERE E.ENCNTR_ID = EA.ENCNTR_ID
	AND EA.ENCNTR_ALIAS_TYPE_CD = 1077.00 ; FIN
	AND EA.END_EFFECTIVE_DT_TM > SYSDATE

JOIN PR WHERE C.PERFORMED_PRSNL_ID = PR.PERSON_ID

ORDER BY
	C.PERFORMED_DT_TM DESC

Head Report
SUBROUTINE CCL_text_wrap(X, Y, Z)
    eol = SIZE(TRIM(Z), 1)
    bseg = 1
    eseg = 1
    line = SUBSTRING(bseg, eol, Z)
    while(eseg <= eol )
        bseg = eseg
        eseg = eseg + y
        if(findstring(" ", substring(bseg, eseg-bseg, line)) > 0)
            while(substring(eseg -1, 1, line) != " " and eseg != bseg)
                eseg = eseg - 1
            endwhile
            segment = substring(bseg, (eseg - bseg) - 1, z)
        else
            segment = substring(bseg, (eseg - bseg), z)
        endif
        col x call print(substring(1, y, segment))
        row + 1
    endwhile
END

    cntr = 0

Detail
    ; Forces a new page for every record except the very first one
    if (cntr > 0)
        break
    endif

    cntr = cntr + 1
    
    ; Patient Header on every new page
    col 0 "Name: " , P.NAME_FULL_FORMATTED
    row + 1
    col 0 "MRN: " , PA.alias
    row + 1
    NoteType = UAR_GET_CODE_DISPLAY(C.EVENT_CD)
    col 0 "Note Type: ", NoteType
    row + 1
    col 0 "Hospital:  ", HOSPITAL
    row + 1
    col 0 "-----------------------------------------------------------------------------------------------------------------------"
    row + 1

    col 0 "Record:" , cntr
    col 20 "Performed Date Time: " , C.PERFORMED_DT_TM "DD/MM/YYYY;;D"
    col 60 "GP: " , PR.NAME_FULL_FORMATTED
    row + 2

    ; 1. Bulletproof Decompression
    if (cb.compression_cd IN (OcfCD, 728.00)) 
        stat = uar_ocf_uncompress(cb.blob_contents, cb.BLOB_LENGTH, vBlobOut, size(vBlobOut), out_len)
    else
        if (textlen > 9)
            trimmedOCFBlob = textlen - 9
            vBlobOut = substring(1, trimmedOCFBlob, BlobIn)
            out_len = trimmedOCFBlob
        else
            vBlobOut = BlobIn
            out_len = textlen
        endif
    endif

    ; 2. Convert to ASCII using exact out_len
    if (out_len > 0)
        stat = uar_rtf2(vBlobOut, out_len, vBlobNoRTF, size(vBlobNoRTF), bsize, 0)
    endif
    
    ; 3. Strip null bytes for safety
    if (bsize > 0)
        vCleanText = TRIM(SUBSTRING(1, bsize, vBlobNoRTF), 3)
    else
        vCleanText = TRIM(vBlobNoRTF, 3)
    endif
    
    col 0 call ccl_text_wrap(col, 450, vCleanText)

    row + 2
    col 0 "------------------------- END OF RECORD -------------------------"
    row + 1

    ; Clear buffers
    vBlobOut = fillstring(65536, ' ')
    vBlobNoRTF = fillstring(65536, ' ')
    vCleanText = fillstring(65536, ' ')
    bsize = 0
    out_len = 0
    trimmedOCFBlob = 0

WITH MAXREC = 50000, MAXCOL = 2000, TIME = 180, NOHEADING, FORMAT = VARIABLE, LANDSCAPE
end
go