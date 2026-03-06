DROP PROGRAM 01_meds_pharm_NICU_Inf:group1 GO
CREATE PROGRAM 01_meds_pharm_NICU_Inf:group1

PROMPT "Output to File/Printer/MINE" = "MINE", "PatientID" = 0, "EncntrID" = 0
WITH OUTDEV, pid, eid

DECLARE sCategory     = c1
DECLARE sMnem         = vc
DECLARE sCapMnem      = vc
DECLARE sFirstWord    = vc
DECLARE sCleanName    = vc
DECLARE sCategoryLbl  = vc
DECLARE sCategoryClr  = vc
DECLARE sPrintProgram = vc
DECLARE sPrintLabel   = vc
DECLARE sScanCode     = vc
DECLARE iSpace        = i4
DECLARE i             = i4
DECLARE stat          = i4
DECLARE vPid          = vc WITH NOCONSTANT(TRIM(CNVTSTRING($pid), 3))

FREE RECORD inf_data
RECORD inf_data (
    1 cnt = i4
    1 list[*]
        2 order_id     = f8
        2 start_dt_tm  = dq8
        2 ordered_as   = vc
        2 cat_sort     = c1
        2 display_name = vc
        2 sort_name    = vc
)

FREE RECORD inf_sorted
RECORD inf_sorted (
    1 cnt = i4
    1 list[*]
        2 order_id     = f8
        2 start_dt_tm  = dq8
        2 ordered_as   = vc
        2 cat_sort     = c1
        2 display_name = vc
)

RECORD reply (
    1 status
        2 code     = vc
        2 message  = vc
    1 meta
        2 module     = vc
        2 title      = vc
        2 patient_id = f8
        2 encntr_id  = f8
        2 item_count = i4
    1 infusions[*]
        2 order_id           = f8
        2 start_dt_tm        = vc
        2 ordered_as         = vc
        2 display_name       = vc
        2 category_code      = vc
        2 category_label     = vc
        2 category_color     = vc
        2 requires_scan      = i2
        2 expected_scan_code = vc
        2 print_program      = vc
        2 print_label        = vc
        2 print_args         = vc
        2 print_flags        = i4
)

SET reply->status.code = "success"
SET reply->status.message = "NICU infusion data loaded."
SET reply->meta.module = "01_meds_pharm_NICU_Inf:group1"
SET reply->meta.title = "NICU Infusions"
SET reply->meta.patient_id = CNVTREAL($pid)
SET reply->meta.encntr_id = CNVTREAL($eid)
SET reply->meta.item_count = 0

SELECT INTO "nl:"
    O_ORDER_ID = O.ORDER_ID
FROM
    ORDERS O
    , PERSON P
    , PERSON_ALIAS PA
    , ALIAS_POOL A
    , ENCOUNTER E
    , ENCNTR_ALIAS EA
    , ORDER_DETAIL OD_ROUTE
    , ORDER_DETAIL OD_FORM
PLAN P
    WHERE P.PERSON_ID = CNVTREAL($pid)
JOIN O
    WHERE P.PERSON_ID = O.PERSON_ID
    AND (CNVTREAL($eid) = 0 OR O.ENCNTR_ID = CNVTREAL($eid))
    AND O.CURRENT_START_DT_TM >= CNVTLOOKBEHIND("100,D", CNVTDATETIME(CURDATE, CURTIME))
    AND O.CURRENT_START_DT_TM <= CNVTDATETIME(CURDATE, 2359)
    AND O.CLINICAL_DISPLAY_LINE != "*Treatment of Neonatal Hyperkalaemia*"
    AND O.ORDER_STATUS_CD = 2550.00
    AND O.IV_IND = 1
    AND O.TEMPLATE_ORDER_ID = 0
JOIN PA
    WHERE PA.PERSON_ID = P.PERSON_ID
    AND PA.PERSON_ALIAS_TYPE_CD = 10.00
    AND PA.END_EFFECTIVE_DT_TM > SYSDATE
JOIN A
    WHERE A.ALIAS_POOL_CD = PA.ALIAS_POOL_CD
JOIN E
    WHERE E.ENCNTR_ID = O.ENCNTR_ID
JOIN EA
    WHERE EA.ENCNTR_ID = O.ENCNTR_ID
    AND EA.ENCNTR_ALIAS_TYPE_CD = 1077.00
JOIN OD_ROUTE
    WHERE OUTERJOIN(O.ORDER_ID) = OD_ROUTE.ORDER_ID
    AND OD_ROUTE.OE_FIELD_MEANING_ID = OUTERJOIN(2050)
JOIN OD_FORM
    WHERE OUTERJOIN(O.ORDER_ID) = OD_FORM.ORDER_ID
    AND OD_FORM.OE_FIELD_MEANING_ID = OUTERJOIN(2014)
    AND OD_FORM.OE_FIELD_DISPLAY_VALUE = "infusion"
ORDER BY
    O.ORDER_ID

HEAD O.ORDER_ID
    sCategory = "0"
    sMnem = O.ORDERED_AS_MNEMONIC
    sCapMnem = CNVTUPPER(sMnem)

    iSpace = FINDSTRING(" ", sCapMnem)
    IF (iSpace > 0)
        sFirstWord = SUBSTRING(1, iSpace - 1, sCapMnem)
    ELSE
        sFirstWord = sCapMnem
    ENDIF

    IF (sCapMnem = "PN*" OR sCapMnem = "PARENTERAL*")
        sCategory = "4"
    ELSEIF (sFirstWord IN (
            "ACTRAPID", "ADRENALINE", "ARGIPRESSIN", "DINOPROSTONE", "DOBUTAMINE", "DOPAMINE",
            "FENTANYL", "HEPARIN", "INSULIN", "MIDAZOLAM", "MILRINONE", "MORPHINE",
            "NORADRENALINE", "SILDENAFIL"
        ))
        sCategory = "1"
    ELSEIF (sFirstWord IN ("GLUCOSE", "SODIUM", "MAINTELYTE"))
        sCategory = "3"
    ENDIF

    IF (sCategory IN ("1", "3", "4"))
        inf_data->cnt = inf_data->cnt + 1
        stat = ALTERLIST(inf_data->list, inf_data->cnt)

        inf_data->list[inf_data->cnt].order_id = O.ORDER_ID
        inf_data->list[inf_data->cnt].start_dt_tm = O.CURRENT_START_DT_TM
        inf_data->list[inf_data->cnt].ordered_as = O.ORDERED_AS_MNEMONIC
        inf_data->list[inf_data->cnt].cat_sort = sCategory

        IF (sCategory = "1")
            IF (FINDSTRING("[", O.ORDER_MNEMONIC) > 0)
                sCleanName = SUBSTRING(1, FINDSTRING("[", O.ORDER_MNEMONIC, 1, 0) - 2, O.ORDER_MNEMONIC)
            ELSE
                sCleanName = O.ORDER_MNEMONIC
            ENDIF
        ELSEIF (sCategory = "3")
            IF (FINDSTRING("1 unit", O.ORDER_MNEMONIC) > 0)
                sCleanName = SUBSTRING(1, FINDSTRING("1 unit", O.ORDER_MNEMONIC, 1, 0) - 2, O.ORDER_MNEMONIC)
            ELSE
                sCleanName = O.ORDER_MNEMONIC
            ENDIF
        ELSEIF (sCategory = "4")
            IF (FINDSTRING("[", O.ORDERED_AS_MNEMONIC) > 9)
                sCleanName = SUBSTRING(1, FINDSTRING("[", O.ORDERED_AS_MNEMONIC, 1, 0) - 9, O.ORDERED_AS_MNEMONIC)
            ELSE
                sCleanName = O.ORDERED_AS_MNEMONIC
            ENDIF
        ELSE
            sCleanName = sMnem
        ENDIF

        inf_data->list[inf_data->cnt].display_name = TRIM(sCleanName)
        inf_data->list[inf_data->cnt].sort_name = CNVTUPPER(O.ORDER_MNEMONIC)
    ENDIF
WITH NOCOUNTER

IF (inf_data->cnt > 0)
    SELECT INTO "nl:"
        cat = inf_data->list[d.seq].cat_sort
        , name = inf_data->list[d.seq].sort_name
    FROM
        (DUMMYT D WITH SEQ = inf_data->cnt)
    ORDER BY
        cat
        , name
    DETAIL
        inf_sorted->cnt = inf_sorted->cnt + 1
        stat = ALTERLIST(inf_sorted->list, inf_sorted->cnt)

        inf_sorted->list[inf_sorted->cnt].order_id = inf_data->list[d.seq].order_id
        inf_sorted->list[inf_sorted->cnt].start_dt_tm = inf_data->list[d.seq].start_dt_tm
        inf_sorted->list[inf_sorted->cnt].ordered_as = inf_data->list[d.seq].ordered_as
        inf_sorted->list[inf_sorted->cnt].cat_sort = inf_data->list[d.seq].cat_sort
        inf_sorted->list[inf_sorted->cnt].display_name = inf_data->list[d.seq].display_name
    WITH NOCOUNTER
ENDIF

IF (inf_sorted->cnt = 0)
    SET reply->status.message = "No active infusions found."
ELSE
    FOR (i = 1 TO inf_sorted->cnt)
        SET sCategoryLbl = ""
        SET sCategoryClr = "#e8f3f8"
        SET sPrintProgram = ""
        SET sPrintLabel = "Print Label"
        SET sScanCode = ""

        IF (inf_sorted->list[i].cat_sort = "1")
            SET sCategoryLbl = "SCI"
            SET sCategoryClr = "#E8F8F5"
            SET sPrintProgram = "01_BK_NICU_INF_FFL_FLIP_NEW:Group1"
            SET sPrintLabel = "Print SCI Label"
        ELSEIF (inf_sorted->list[i].cat_sort = "3")
            SET sCategoryLbl = "Fluid"
            SET sCategoryClr = "#F4ECF7"
            SET sPrintProgram = "01_BK_NICU_FLUID_FFL_FLIPPED:Group1"
            SET sPrintLabel = "Print Fluid Label"
        ELSEIF (inf_sorted->list[i].cat_sort = "4")
            SET sCategoryLbl = "PN"
            SET sCategoryClr = "#FEF9E7"
            SET sPrintProgram = "01_BK_NICU_PN_FFL_FLIPPED:Group1"
            SET sPrintLabel = "Print Label"

            IF (FINDSTRING("cSPN1", inf_sorted->list[i].ordered_as) > 0)
                SET sScanCode = "FDCN20019"
            ELSEIF (FINDSTRING("cSPN2", inf_sorted->list[i].ordered_as) > 0)
                SET sScanCode = "FDCN20018"
            ENDIF
        ENDIF

        SET reply->meta.item_count = reply->meta.item_count + 1
        SET stat = ALTERLIST(reply->infusions, reply->meta.item_count)

        SET reply->infusions[reply->meta.item_count].order_id = inf_sorted->list[i].order_id
        SET reply->infusions[reply->meta.item_count].start_dt_tm = FORMAT(inf_sorted->list[i].start_dt_tm, "DD/MM/YYYY hh:mm;;Q")
        SET reply->infusions[reply->meta.item_count].ordered_as = inf_sorted->list[i].ordered_as
        SET reply->infusions[reply->meta.item_count].display_name = inf_sorted->list[i].display_name
        SET reply->infusions[reply->meta.item_count].category_code = inf_sorted->list[i].cat_sort
        SET reply->infusions[reply->meta.item_count].category_label = sCategoryLbl
        SET reply->infusions[reply->meta.item_count].category_color = sCategoryClr
        IF (TRIM(sScanCode) > "")
            SET reply->infusions[reply->meta.item_count].requires_scan = 1
        ELSE
            SET reply->infusions[reply->meta.item_count].requires_scan = 0
        ENDIF
        SET reply->infusions[reply->meta.item_count].expected_scan_code = sScanCode
        SET reply->infusions[reply->meta.item_count].print_program = sPrintProgram
        SET reply->infusions[reply->meta.item_count].print_label = sPrintLabel
        SET reply->infusions[reply->meta.item_count].print_args = BUILD2("MINE, ", vPid, ", ", TRIM(CNVTSTRING(inf_sorted->list[i].order_id), 3))
        SET reply->infusions[reply->meta.item_count].print_flags = 0
    ENDFOR
ENDIF

SET _memory_reply_string = CNVTRECTOJSON(reply)
END GO





