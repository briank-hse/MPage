drop program 01_meds_pharm_mpage_meds go
create program 01_meds_pharm_mpage_meds

%i cust_script:01_meds_pharm_mpage_struct
/* ====================================================================
 * ACTIVE MEDICATIONS (ANTIBIOTICS, ALL MEDS, INFUSIONS)
 * ==================================================================== */
select distinct into "nl:"
from
    dummyt d
    , person p
    , person_alias pa
    , orders o
    , order_detail od_cat
    , order_detail od_form
plan d
join p where p.person_id = outerjoin(mpage_data->req_info.patient_id)
join pa where pa.person_id = outerjoin(p.person_id)
    and pa.person_alias_type_cd = outerjoin(10.00)
    and pa.end_effective_dt_tm > outerjoin(sysdate)
join o where o.person_id = outerjoin(p.person_id)
    and o.order_status_cd = outerjoin(2550.00)
    and o.active_ind = outerjoin(1)
    and o.orig_order_dt_tm > outerjoin(cnvtlookbehind("400,D", cnvtdatetime(curdate,curtime)))
    and o.template_order_id = outerjoin(0)
join od_cat where od_cat.order_id = outerjoin(o.order_id)
    and od_cat.oe_field_meaning_id = outerjoin(2007)
join od_form where od_form.order_id = outerjoin(o.order_id)
    and od_form.oe_field_meaning_id = outerjoin(2014)
order by
    d.seq
    , o.order_mnemonic
head report
    nCnt = 0
detail
    if (o.order_id > 0)
        nCnt = nCnt + 1
        stat = alterlist(mpage_data->orders, nCnt)
        
        mpage_data->orders[nCnt].order_id   = o.order_id
        mpage_data->orders[nCnt].mnemonic   = o.order_mnemonic
        mpage_data->orders[nCnt].cdl        = o.clinical_display_line
        mpage_data->orders[nCnt].start_dt   = format(o.current_start_dt_tm, "DD/MM/YYYY HH:MM")
        mpage_data->orders[nCnt].disp_cat   = nullval(od_cat.oe_field_display_value, " ")
        mpage_data->orders[nCnt].order_form = nullval(od_form.oe_field_display_value, " ")
    endif
with nocounter

end
go