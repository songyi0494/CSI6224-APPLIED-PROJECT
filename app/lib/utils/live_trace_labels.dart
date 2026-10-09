// Presentation metadata for Songyi P1/P2; routing stays in the rule engine.
const liveNodeLabels = <String, String>{
  'PATHWAY1:P1_DEMOGRAPHIC_ELIGIBILITY': 'Demographic eligibility',
  'PATHWAY1:MINIMAL_TRAUMA_KNOWN': 'Fracture mechanism is known',
  'PATHWAY1:MINIMAL_TRAUMA_FRACTURE': 'Fall from standing height or less',
  'PATHWAY1:FRACTURE_SITE_KNOWN': 'Fracture site is known',
  'PATHWAY1:FRACTURE_SITE_ELIGIBLE': 'Fracture site is eligible',
  'PATHWAY1:P1_ELIGIBILITY_NOT_MET': 'P1 entry criteria are not met',
  'PATHWAY1:P1_ELIGIBILITY_REVIEW': 'Confirm fracture information',
  'PATHWAY1:RENAL_DYSFUNCTION': 'Is the patient\'s eGFR 30 mL/min or higher?',
  'PATHWAY1:ON_OSTEOPOROSIS_TREATMENT':
      'Is the patient currently on osteoporosis treatment?',
  'PATHWAY1:RESIDENTIAL_OR_FRAILTY':
      'Residential care, severe frailty, or limited life expectancy',
  'PATHWAY1:ADHERENCE_CONCERN': 'Treatment adherence concern',
  'PATHWAY1:DXA_SCAN_AVAILABILITY':
      'Is the patient able to undergo a BMD DXA scan? (Select Yes if the patient has had a scan within prior 2 years)',
  'PATHWAY1:T_SCORE_CHECK': 'T-score ≤ -2.5 at any relevant site',
  'PATHWAY1:RECENT_MAJOR_FRACTURES':
      'Has the patient had a hip fracture, vertebral fracture, or fractures at 2 or more sites in last 24 months?',
  'PATHWAY1:HIGH_RISK_CHECK': 'Very-high-fracture-risk criteria met',
  'PATHWAY1:LEAF_RENAL_REFERRAL': 'Renal referral',
  'PATHWAY1:LEAF_REDIRECT_PATHWAY2': 'Current osteoporosis treatment',
  'PATHWAY1:LEAF_DENOSUMAB_GP': 'Denosumab gp',
  'PATHWAY1:LEAF_ZOLEDRONIC_OR_RISEDRONATE_GP': 'Zoledronic or risedronate gp',
  'PATHWAY1:LEAF_ZOLEDRONIC_OR_RISEDRONATE_OR_DENOSUMAB_GP':
      'Zoledronic or risedronate or denosumab gp',
  'PATHWAY1:LEAF_OSTEOANABOLIC_REFERRAL': 'Osteoanabolic referral',
  'PATHWAY1:LEAF_PRIVATELY_FUNDED_OSTEOANABOLIC_REFERRAL':
      'Privately funded osteoanabolic referral',
  'PATHWAY2:ON_ANTIRESORPTIVE_TREATMENT':
      'Is the patient currently on antiresorptive treatment?',
  'PATHWAY2:ANTIRESORPTIVE_TREATMENT_DURATION':
      'Has the patient used the current antiresorptive treatment for more than 12 months?',
  'PATHWAY2:TREATMENT_ADHERENCE':
      'Has the patient adhered to the treatment plan?',
  'PATHWAY2:SYMPTOMATIC_FRACTURE':
      'Has the patient had 1 or more symptomatic fractures in last 12 months?',
  'PATHWAY2:MULTIPLE_FRACTURES':
      'Has the patient had 2 or more fractures? (Check for occult vertebral fractures in previous chest or abdomen scan)',
  'PATHWAY2:CHECK_BMD':
      'Does the patient have a BMD T-score below -3.0 at any site?',
  'PATHWAY2:MI_OR_STROKE_HISTORY':
      'Does the patient have a history of myocardial infarction(MI) or stroke?',
  'PATHWAY2:SEQUENCING_WITH_HISTORY':
      'Is the patient transitioning from denosumab?',
  'PATHWAY2:SEQUENCING_NO_HISTORY':
      'Is the patient transitioning from denosumab?',
  'PATHWAY2:LEAF_REDIRECT_PATHWAY1': 'Current antiresorptive treatment',
  'PATHWAY2:LEAF_STANDARD_ANTIRESORPTIVE_OPTIONS':
      'Standard antiresorptive options',
  'PATHWAY2:LEAF_COMBINATION_THERAPY_REFERRAL': 'Combination therapy referral',
  'PATHWAY2:LEAF_TERIPARATIDE_REFERRAL': 'Teriparatide referral',
  'PATHWAY2:LEAF_RESTARTING_DENOSUMAB_REFERRAL':
      'Restarting denosumab referral',
  'PATHWAY2:LEAF_ROMOSOZUMAB_REFERRAL': 'Romosozumab referral',
};

const liveNodeConditions = <String, String>{
  'PATHWAY1:LEAF_REDIRECT_PATHWAY2':
      'Currently on osteoporosis treatment = Yes',
  'PATHWAY2:LEAF_REDIRECT_PATHWAY1':
      'Currently on antiresorptive treatment = No',
  'PATHWAY1:P1_DEMOGRAPHIC_ELIGIBILITY':
      'Postmenopausal woman OR man older than 50',
  'PATHWAY1:MINIMAL_TRAUMA_KNOWN': 'Fracture mechanism confirmed as Yes or No',
  'PATHWAY1:MINIMAL_TRAUMA_FRACTURE': 'Fall from standing height or less = Yes',
  'PATHWAY1:FRACTURE_SITE_KNOWN': 'Fracture site is confirmed',
  'PATHWAY1:FRACTURE_SITE_ELIGIBLE':
      'Fracture site excludes hand, foot, face and ankle',
  'PATHWAY1:RENAL_DYSFUNCTION': 'eGFR ≥30 mL/min = Yes',
  'PATHWAY1:ON_OSTEOPOROSIS_TREATMENT':
      'Currently on osteoporosis treatment = Yes',
  'PATHWAY1:RESIDENTIAL_OR_FRAILTY':
      'Residential care, severe frailty, or limited life expectancy = Yes',
  'PATHWAY1:ADHERENCE_CONCERN': 'Treatment-adherence concern = Yes',
  'PATHWAY1:DXA_SCAN_AVAILABILITY':
      'BMD DXA available or completed within two years = Yes',
  'PATHWAY1:T_SCORE_CHECK': 'T-score ≤ -2.5 at any relevant site = Yes',
  'PATHWAY1:RECENT_MAJOR_FRACTURES':
      'Hip, vertebral, or multiple fractures in the last 24 months = Yes',
  'PATHWAY1:HIGH_RISK_CHECK': 'Very-high-fracture-risk criteria met = Yes',
  'PATHWAY2:ON_ANTIRESORPTIVE_TREATMENT':
      'Currently on antiresorptive treatment = Yes',
  'PATHWAY2:ANTIRESORPTIVE_TREATMENT_DURATION':
      'Current antiresorptive treatment >12 months = Yes',
  'PATHWAY2:TREATMENT_ADHERENCE': 'Adhered to the treatment plan = Yes',
  'PATHWAY2:SYMPTOMATIC_FRACTURE':
      'Symptomatic fracture in the last 12 months = Yes',
  'PATHWAY2:MULTIPLE_FRACTURES': 'Two or more fractures = Yes',
  'PATHWAY2:CHECK_BMD': 'BMD T-score below -3.0 at any site = Yes',
  'PATHWAY2:MI_OR_STROKE_HISTORY':
      'History of myocardial infarction or stroke = Yes',
  'PATHWAY2:SEQUENCING_WITH_HISTORY': 'Sequencing from denosumab = Yes',
  'PATHWAY2:SEQUENCING_NO_HISTORY': 'Sequencing from denosumab = Yes',
};
