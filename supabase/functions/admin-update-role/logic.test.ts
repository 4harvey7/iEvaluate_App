// node --test supabase/functions/admin-update-role/logic.test.ts   (Node >= 22.18)
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { roleChangeNeedsCode, removesLastAdmin, isActiveAccount } from './logic.ts'

test('any change into or out of SAO_ADMIN needs a code, whatever isPromotion says', () => {
  for (const isPromotion of [undefined, false, true]) {
    assert.equal(roleChangeNeedsCode({ currentRole: 'SAO_ADMIN', newRole: 'SAO_STAFF', isPromotion }), true)
    assert.equal(roleChangeNeedsCode({ currentRole: 'SAO_STAFF', newRole: 'SAO_ADMIN', isPromotion }), true)
    assert.equal(roleChangeNeedsCode({ currentRole: 'SAO_ADMIN', newRole: null, isPromotion }), true) // unknown roleId fails closed
  }
})

test('no code for name-only edits or non-admin moves unless flagged as a promotion', () => {
  assert.equal(roleChangeNeedsCode({ currentRole: 'SAO_ADMIN', newRole: 'SAO_ADMIN', isPromotion: false }), false)
  assert.equal(roleChangeNeedsCode({ currentRole: 'SAO_STAFF', newRole: 'SAO_STAFF', isPromotion: undefined }), false)
  assert.equal(roleChangeNeedsCode({ currentRole: null, newRole: 'FULL-TIME', isPromotion: false }), false)
  assert.equal(roleChangeNeedsCode({ currentRole: null, newRole: 'DEPARTMENT_HEAD', isPromotion: true }), true)
  assert.equal(roleChangeNeedsCode({ currentRole: null, newRole: 'DEPARTMENT_HEAD', isPromotion: 'true' }), false)
})

test('the last active admin cannot be demoted', () => {
  assert.equal(removesLastAdmin({ currentRole: 'SAO_ADMIN', newRole: 'SAO_STAFF', otherActiveAdmins: 0 }), true)
  assert.equal(removesLastAdmin({ currentRole: 'SAO_ADMIN', newRole: 'SAO_STAFF', otherActiveAdmins: 1 }), false)
  assert.equal(removesLastAdmin({ currentRole: 'SAO_ADMIN', newRole: 'SAO_ADMIN', otherActiveAdmins: 0 }), false)
  assert.equal(removesLastAdmin({ currentRole: 'SAO_STAFF', newRole: 'SAO_STAFF', otherActiveAdmins: 0 }), false)
})

test('active account = approved and not disabled', () => {
  assert.equal(isActiveAccount({ account_status: 'Approved', disabled: false }), true)
  assert.equal(isActiveAccount({ account_status: 'approved', disabled: null }), true)
  assert.equal(isActiveAccount({ account_status: 'approved', disabled: true }), false)
  assert.equal(isActiveAccount({ account_status: 'pending' }), false)
  assert.equal(isActiveAccount(null), false)
})
