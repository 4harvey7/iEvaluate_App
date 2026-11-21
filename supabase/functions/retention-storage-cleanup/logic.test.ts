// node --test supabase/functions/retention-storage-cleanup/logic.test.ts   (Node >= 22.18)
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { parsePlan, secretMatches, DEFAULT_DAYS } from './logic.ts'

test('dry run unless the body explicitly says dry_run: false', () => {
  for (const body of [undefined, null, {}, [], 'x', { dry_run: true }, { dry_run: 'false' }, { dry_run: 0 }]) {
    assert.deepEqual(parsePlan(body), { dryRun: true, days: DEFAULT_DAYS })
  }
  assert.deepEqual(parsePlan({ dry_run: false }), { dryRun: false, days: 90 })
})

test('days: default 90, minimum 30, whole numbers only', () => {
  assert.deepEqual(parsePlan({ days: 30 }), { dryRun: true, days: 30 })
  assert.deepEqual(parsePlan({ dry_run: false, days: 120 }), { dryRun: false, days: 120 })
  for (const days of [29, 0, -5, 30.5, '90', 99999]) assert.ok('error' in parsePlan({ days }))
})

test('secret check', async () => {
  const s = 'a'.repeat(40)
  assert.equal(await secretMatches(s, s), true)
  assert.equal(await secretMatches('a'.repeat(39), s), false)
  assert.equal(await secretMatches(null, s), false)
  assert.equal(await secretMatches('', s), false)
  assert.equal(await secretMatches('short', 'short'), false) // a weak configured secret fails closed
})
