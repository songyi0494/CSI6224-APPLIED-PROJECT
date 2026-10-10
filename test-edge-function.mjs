import { createClient } from "@supabase/supabase-js";

const supabase = createClient(
    'https://cwxxumfmvmspofouqxxh.supabase.co',
    'sb_publishable_yCRf_Gr1C4qGo9eG7XppoQ_MXV2meMO'
)

const { data: loginData, error: loginError } =
    await supabase.auth.signInWithPassword({
        email: 'clinician1@test.com',
        password: 'TestPassword123!'
    })

if (loginError) {
    console.error('LOGIN ERROR:', loginError)
    process.exit(1)
}

console.log('Logged in user ID:', loginData.user.id)

const { data: evaluationData, error: evaluationError } =
    await supabase.functions.invoke('evaluate_pathway', {
        body: {
            caseId: '8e1a0644-507a-492b-a5a7-78515780a28e'
        }
    })

if (evaluationError) {
    console.error('EVALUATION ERROR:', evaluationError)
    if (evaluationError.context) {
        console.error(
            'ERROR BODY:',
            await evaluationError.context.text()
        )
    }
    process.exit(1)
}

console.log('Evaluation result:', evaluationData)