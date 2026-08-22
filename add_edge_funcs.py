import re

with open('README.md', 'r', encoding='utf-8') as f:
    content = f.read()

edge_functions_md = """
## Supabase Edge Functions

The backend relies on several Deno-based edge functions hosted in Supabase (supabase/functions/). These manage elevated-privilege operations and integrate with Brevo for transactional emails. 

Custom secrets (expected in the Supabase Dashboard, not the app's .env) used across these functions:
- BREVO_API_KEY: API key for Brevo SMTP.
- BREVO_SENDER_EMAIL: Authorized sender email address for outgoing alerts/invites.
- SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY: Native Supabase env vars used to bypass RLS for admin actions.

### 1. dmin-accept-user (supabase/functions/admin-accept-user/index.ts)
- **Purpose**: Approves pending user registrations and moves them to active status.
- **Trigger**: Called via unctions.invoke from dmin_dashboard.dart, personnel_management_screen.dart, and user_management_screen.dart.
- **Inputs**: { targetUserId: string }
- **External Services**: None directly.
- **Error Handling**: Verifies SAO_ADMIN role. Returns 401 Unauthorized or 400 Forbidden.

### 2. dmin-create-academic (supabase/functions/admin-create-academic/index.ts)
- **Purpose**: Provisions new academic personnel (Instructors, Dept Heads).
- **Trigger**: Called via unctions.invoke (assumed from admin forms).
- **Inputs**: { firstName, lastName, email, universityId, ... }
- **External Services**: Brevo (sends a magic-link password setup email via uth.admin.generateLink). Fails with an error if Brevo fails.
- **Error Handling**: Implements OTP (One Time Password) checks. Deletes verification data if OTP limits exceeded. Returns sanitized safe errors.

### 3. dmin-create-user (supabase/functions/admin-create-user/index.ts)
- **Purpose**: Provisions new SAO personnel with elevated roles.
- **Trigger**: Called via unctions.invoke.
- **Inputs**: { firstName, lastName, email, universityId, roleName, address, verificationCode }
- **External Services**: Brevo API. Sends an invitation email with a recovery link to securely set their password.
- **Error Handling**: Rejects invalid OTPs. Uses a strict rejection sampling algorithm for temp passwords. Sanitizes errors (e.g., OTP expired, Invalid OTP) to avoid leaking DB info.

### 4. dmin-update-role (supabase/functions/admin-update-role/index.ts)
- **Purpose**: Securely elevates or modifies a user's role.
- **Trigger**: Called via unctions.invoke from sao_admin_settings.dart and user_management_screen.dart.
- **Inputs**: { targetUserId, roleId, roleName, verificationCode, isAcademic, ... }
- **External Services**: Brevo API. Emails the target user notifying them of their role change.
- **Error Handling**: Strictly enforces MAX_OTP_ATTEMPTS. Logs audit records in udit_logs table.

### 5. delete-user (supabase/functions/delete-user/index.ts)
- **Purpose**: Deletes a user account.
- **Trigger**: Called via unctions.invoke from uth_service.dart.
- **Inputs**: { userId }
- **External Services**: None.
- **Error Handling**: Validates that the caller is deleting their own account (unless SAO_ADMIN). Returns User deleted successfully or error string.

### 6. send-admin-code (supabase/functions/send-admin-code/index.ts)
- **Purpose**: Generates and emails a secure OTP code to an SAO Admin for sensitive operations.
- **Trigger**: Called via unctions.invoke from user_management_screen.dart and sao_admin_settings.dart.
- **Inputs**: { email }
- **External Services**: Brevo API.
- **Error Handling**: Implements a 60-second rate limit. Swallows internal DB errors and returns sanitized strings.

### 7. send-intervention-email (supabase/functions/send-intervention-email/index.ts)
- **Purpose**: Emails an instructor an official notice when the Dept Head triggers an intervention report.
- **Trigger**: Called via unctions.invoke from lib/core/services/evaluation_service.dart.
- **Inputs**: { record }
- **External Services**: Brevo API.
- **Error Handling**: Verifies instructor email exists. Returns 400 with Brevo API error details if delivery fails.

### 8. update-system-settings (supabase/functions/update-system-settings/index.ts)
- **Purpose**: Updates global term/academic year settings and notifies admins.
- **Trigger**: Called via unctions.invoke from sao_admin_settings.dart.
- **Inputs**: { autoSync, semester, academicYear }
- **External Services**: Brevo API. Sends a system alert email to all SAO_ADMIN users.
- **Error Handling**: Logs action to udit_logs. Catches unauthorized access and returns sanitized errors.
"""

# Replace the External Resources > Supabase section with a cross reference,
# and insert the edge functions section before Testing.

new_supabase_section = """### Supabase (Database / Auth / Storage)
- **Project config:** .env.json (SUPABASE_URL, SUPABASE_ANON_KEY)
- **Migrations:** 6 SQL files in supabase/migrations/ defining schema, Row Level Security (RLS), and queues.
- **Edge Functions:** See [Supabase Edge Functions](#supabase-edge-functions) for details on transactional emails and admin actions.
- **Client init:** Supabase.initialize(url: Env.supabaseUrl, anonKey: Env.supabaseAnonKey) in lib/main.dart."""

content = re.sub(r"### Supabase \(Database \/ Auth \/ Storage\).*?Client init[^\n]+", new_supabase_section, content, flags=re.DOTALL)

# Insert the new section
content = content.replace("## Testing", edge_functions_md + "\n## Testing")

with open('README.md', 'w', encoding='utf-8') as f:
    f.write(content)
