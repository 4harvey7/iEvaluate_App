import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    const authHeader = req.headers.get('Authorization')
    if (!authHeader) throw new Error('Unauthorized')

    const { data: { user: caller }, error: userError } = await supabaseAdmin.auth.getUser(authHeader.replace('Bearer ', ''))
    if (userError || !caller) throw new Error('Unauthorized')

    const { userId } = await req.json()

    // Safety: Users can only delete themselves, unless it's a SAO_ADMIN (optional, for now just self-delete)
    if (caller.id !== userId) {
        // Check if caller is admin
        const { data: adminCheck } = await supabaseAdmin
          .from('Sao_users')
          .select('roles!inner(Roles)')
          .eq('user_id', caller.id)
          .single()

        if ((adminCheck as any)?.roles?.Roles !== 'SAO_ADMIN') {
            throw new Error('Forbidden: You can only delete your own account.')
        }
    }

    // 1. Soft Delete: Update user_info status to 'deleted'
    const { error: updateError } = await supabaseAdmin
        .from('user_info')
        .update({ account_status: 'deleted' })
        .eq('id', userId)
    
    if (updateError) throw updateError

    // 2. Ban the user in auth so they cannot log in again
    // We set a very long ban duration to effectively disable the account
    const { error: banError } = await supabaseAdmin.auth.admin.updateUserById(
      userId,
      { ban_duration: '87600h' } // 10 years ban
    )
    if (banError) throw banError

    // 2. Audit Log
    await supabaseAdmin.from('audit_logs').insert({
      user_id: caller.id,
      action: 'USER_DELETED',
      metadata: { deleted_user: userId }
    })

    return new Response(JSON.stringify({ message: 'User deleted successfully' }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 200,
    })
  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 400,
    })
  }
})
