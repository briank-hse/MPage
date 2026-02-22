drop program 01_bk_test_anvs_deblob go
create program 01_bk_test_anvs_deblob

prompt
  "Output to File/Printer/MINE" = "MINE"
, "Event ID" = 2208205590.00
with OUTDEV, event_id

select into $outdev
    cb.event_id
  , cb.blob_seq_num
  , cb.compression_cd
  , cb.blob_length
  , blob_contents_size = size(cb.blob_contents)
from ce_blob cb
plan cb where cb.event_id = $event_id
  and cb.valid_until_dt_tm > sysdate
order by cb.blob_seq_num

head report
  row + 1 call print("=======================================")
  row + 1 call print("CE_BLOB SEGMENTS FOR EVENT_ID")
  row + 1 call print(build("EVENT_ID: ", trim(cnvtstring($event_id))))
  row + 1 call print("=======================================")

detail
  row + 1 call print("---------------------------------------")
  row + 1 call print(build("SEQ: ", cb.blob_seq_num))
  row + 1 call print(build("COMPRESSION_CD: ", cb.compression_cd))
  row + 1 call print(build("BLOB_LENGTH: ", cb.blob_length))
  row + 1 call print(build("SIZE(BLOB_CONTENTS): ", blob_contents_size))
  row + 1 call print("RAW HEAD (first 40 chars):")
  row + 1 call print(substring(1, 40, cb.blob_contents))

foot report
  row + 1 call print("---------------------------------------")
  row + 1 call print("END")
  row + 1 call print("=======================================")

with nocounter, format=variable, noheading, maxcol=32000
end
go