SELECT
    patientId AS '#patientId',
    sampleId,
    setName,
    tumorPurity,
    hmfPatientId,
    hmfSampleId,
    primaryTumorLocation,
    cancerSubtype,
    biopsyDate,
    biopsySite,
    biopsyLocation,
    gender,
    birthYear,
    deathDate,
    hasSystemicPreTreatment,
    hasRadiotherapyPreTreatment,
    treatmentGiven,
    treatmentStartDate,
    treatmentEndDate,
    treatment,
    consolidatedTreatmentType as treatmentType,
    responseDate,
    responseMeasured,
    firstResponse
FROM datarequest;