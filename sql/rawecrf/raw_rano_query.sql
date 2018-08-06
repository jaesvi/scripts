select patients.patientId,
RNTMRNYN, RNTMDT, RNTMTNR, RNTMTST, RNTMTLC, RNTMTMTHD, RNTMTTRGT1, RNTMTTRGT2, RNTMNWYN, RNTSER,
RNTSLC, RNTMSMTTL, RNDUMTMSUMTOTAL, RNTMTRGTT, RNTMNTNR, RNTMNTST, RNTMNTLC, RNTMNTMTHD, RNTMNTVL, RNTT2,
TERNTB, TERNCFB, TERNCFN, TERNOR, RNDNAD, RNCORTU, RNVRLL, RNRSPNTL, RNRSPTL
from
	(select distinct patientId from ecrf) patients
left join
   (select patientId, group_concat(itemValue separator ', ') as RNTMRNYN
    from ecrf where item = 'FLD.RNTMRNYN' group by patientId) rntmrnyn
on patients.patientId = rntmrnyn.patientId
left join
    (select patientId, group_concat(itemValue separator ', ') as RNTMDT
     from ecrf where item ='FLD.RNTMDT' group by patientId) rntmdt
on patients.patientId = rntmdt.patientId
left join
    (select patientId, group_concat(itemValue separator ', ') as RNTMTNR
     from ecrf where item ='FLD.RNTMTNR' group by patientId) rntmtnr
on patients.patientId = rntmtnr.patientId
left join
    (select patientId, group_concat(itemValue separator ', ') as RNTMTST
     from ecrf where item ='FLD.RNTMTST' group by patientId) rntmtst
on patients.patientId = rntmtst.patientId
left join
    (select patientId, group_concat(itemValue separator ', ') as RNTMTLC
     from ecrf where item ='FLD.RNTMTLC' group by patientId) rntmtlc
on patients.patientId = rntmtlc.patientId
left join
    (select patientId, group_concat(itemValue separator ', ') as RNTMTMTHD
    from ecrf where item ='FLD.RNTMTMTHD' group by patientId) rntmtmthd
on patients.patientId = rntmtmthd.patientId
left join
    (select patientId, group_concat(itemValue separator ', ') as RNTMTTRGT1
     from ecrf where item ='FLD.RNTMTTRGT1' group by patientId) rntmttrgt1
on patients.patientId = rntmttrgt1.patientId
left join
    (select patientId, group_concat(itemValue separator ', ') as RNTMTTRGT2
     from ecrf where item ='FLD.RNTMTTRGT2' group by patientId) rntmttrgt2
on patients.patientId = rntmttrgt2.patientId
left join
    (select patientId, group_concat(itemValue separator ', ') as RNTMNWYN
     from ecrf where item ='FLD.RNTMNWYN' group by patientId) rntmnwyn
on patients.patientId = rntmnwyn.patientId
left join
    (select patientId, group_concat(itemValue separator ', ') as RNTSER
     from ecrf where item ='FLD.RNTSER' group by patientId) rntser
on patients.patientId = rntser.patientId
left join
    (select patientId, group_concat(itemValue separator ', ') as RNTSLC
     from ecrf where item ='FLD.RNTSLC' group by patientId) rntslc
on patients.patientId = rntslc.patientId
left join
    (select patientId, group_concat(itemValue separator ', ') as RNTMSMTTL
     from ecrf where item ='FLD.RNTMSMTTL' group by patientId) rntmsmttl
on patients.patientId = rntmsmttl.patientId
left join
    (select patientId, group_concat(itemValue separator ', ') as RNDUMTMSUMTOTAL
     from ecrf where item ='FLD.RNDUMTMSUMTOTAL' group by patientId) rndumtmsumtotal
on patients.patientId = rndumtmsumtotal.patientId
left join
    (select patientId, group_concat(itemValue separator ', ') as RNTMTRGTT
     from ecrf where item ='FLD.RNTMTRGTT' group by patientId) rntmtrgtt
on patients.patientId = rntmtrgtt.patientId
left join
    (select patientId, group_concat(itemValue separator ', ') as RNTMNTNR
     from ecrf where item ='FLD.RNTMNTNR' group by patientId) rntmntnr
on patients.patientId = rntmntnr.patientId
left join
    (select patientId, group_concat(itemValue separator ', ') as RNTMNTST
     from ecrf where item ='FLD.RNTMNTST' group by patientId) rntmntst
on patients.patientId = rntmntst.patientId
left join
    (select patientId, group_concat(itemValue separator ', ') as RNTMNTLC
     from ecrf where item ='FLD.RNTMNTLC' group by patientId) rntmntlc
on patients.patientId = rntmntlc.patientId
left join
    (select patientId, group_concat(itemValue separator ', ') as RNTMNTMTHD
     from ecrf where item ='FLD.RNTMNTMTHD' group by patientId) rntmntmthd
on patients.patientId = rntmntmthd.patientId
left join
    (select patientId, group_concat(itemValue separator ', ') as RNTMNTVL
     from ecrf where item ='FLD.RNTMNTVL' group by patientId) rntmntvl
on patients.patientId = rntmntvl.patientId
left join
    (select patientId, group_concat(itemValue separator ', ') as RNTT2
     from ecrf where item ='FLD.RNTT2' group by patientId) rntt2
on patients.patientId = rntt2.patientId
left join
    (select patientId, group_concat(itemValue separator ', ') as TERNTB
     from ecrf where item ='FLD.TERNTB' group by patientId) terntb
on patients.patientId = terntb.patientId
left join
    (select patientId, group_concat(itemValue separator ', ') as TERNCFB
     from ecrf where item ='FLD.TERNCFB' group by patientId) terncbf
on patients.patientId = terncbf.patientId
left join
    (select patientId, group_concat(itemValue separator ', ') as TERNCFN
     from ecrf where item ='FLD.TERNCFN' group by patientId) terncfn
on patients.patientId = terncfn.patientId
left join
    (select patientId, group_concat(itemValue separator ', ') as TERNOR
     from ecrf where item ='FLD.TERNOR' group by patientId) ternor
on patients.patientId = ternor.patientId
left join
    (select patientId, group_concat(itemValue separator ', ') as RNDNAD
     from ecrf where item ='FLD.RNDNAD' group by patientId) rndnad
on patients.patientId = rndnad.patientId
left join
    (select patientId, group_concat(itemValue separator ', ') as RNCORTU
     from ecrf where item ='FLD.RNCORTU' group by patientId) rncortu
on patients.patientId = rncortu.patientId
left join
    (select patientId, group_concat(itemValue separator ', ') as RNVRLL
     from ecrf where item ='FLD.RNVRLL' group by patientId) rnvrll
on patients.patientId = rnvrll.patientId
left join
    (select patientId, group_concat(itemValue separator ', ') as RNRSPTL
     from ecrf where item ='FLD.RNRSPTL' group by patientId) rnrsplt
on patients.patientId = rnrsplt.patientId
left join
    (select patientId, group_concat(itemValue separator ', ') as RNRSPNTL
     from ecrf where item ='FLD.RNRSPNTL' group by patientId) rnrspntl
on patients.patientId = rnrspntl.patientId
where patients.patientId in (select distinct patientId from clinical) order by patients.patientId