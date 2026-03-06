DROP PROGRAM 01_meds_pharm_anvs:group1 GO
CREATE PROGRAM 01_meds_pharm_anvs:group1

PROMPT "Output to File/Printer/MINE" = "MINE", "PatientID" = 0, "EncntrID" = 0
WITH OUTDEV, pid, eid

RECORD reply (
    1 status
        2 code    = vc
        2 message = vc
    1 meta
        2 module     = vc
        2 title      = vc
        2 patient_id = f8
        2 encntr_id  = f8
)

SET reply->status.code = "prototype_pending"
SET reply->status.message = "GP Medications shell is wired, but the ANVS JSON backend has not been migrated yet."
SET reply->meta.module = "01_meds_pharm_anvs:group1"
SET reply->meta.title = "GP Medications"
SET reply->meta.patient_id = CNVTREAL($pid)
SET reply->meta.encntr_id = CNVTREAL($eid)

SET _memory_reply_string = CNVTRECTOJSON(reply)
END GO

