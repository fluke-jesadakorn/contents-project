// Quick smoke test of the policy engine (compiled by Next during dev/build).
// We import from the .ts source via the next/typescript path — instead, copy the
// logic inline for the standalone test.
import { _matches, pickPolicy, nextStageFromChain } from '../src/lib/policy/engine.ts';

const policies = [
  {
    id: 1, name: 'small', priority: 10, is_active: true, target_type: 'expense',
    conditions_json: { all_of: [{ field: 'total_amount', op: 'lte', value: 5000 }] },
    action_json: { approver_chain: [], auto_approve: true },
  },
  {
    id: 2, name: 'mid', priority: 20, is_active: true, target_type: 'expense',
    conditions_json: { all_of: [{ field: 'total_amount', op: 'between', value: [5001, 50000] }] },
    action_json: { approver_chain: ['head_of_department'], auto_approve: false },
  },
  {
    id: 3, name: 'big', priority: 30, is_active: true, target_type: 'expense',
    conditions_json: { all_of: [{ field: 'total_amount', op: 'gt', value: 200000 }] },
    action_json: { approver_chain: ['head_of_department','accounting_manager','cfo'], auto_approve: false },
  },
];

const tests = [
  { ctx: { targetType: 'expense', totalAmount: 3500 }, want: 'small' },
  { ctx: { targetType: 'expense', totalAmount: 25000 }, want: 'mid' },
  { ctx: { targetType: 'expense', totalAmount: 250000 }, want: 'big' },
  { ctx: { targetType: 'pr', totalAmount: 3500 }, want: null }, // target mismatch
];

let pass = 0, fail = 0;
for (const t of tests) {
  const got = pickPolicy(policies, t.ctx);
  const gotName = got?.name || null;
  if (gotName === t.want) { pass++; console.log('✓', t.ctx.totalAmount, '->', gotName); }
  else { fail++; console.log('✗', t.ctx.totalAmount, 'want', t.want, 'got', gotName); }
}

// Stage progression
const chain = ['head_of_department','accounting_manager','cfo'];
console.log('chain stage walk:');
let idx = 0;
for (let i = 0; i < chain.length; i++) {
  const n = nextStageFromChain(chain, idx);
  console.log('  step', i, '->', n.next, 'nextIdx=', n.nextIndex, 'final=', n.final);
  idx = n.nextIndex;
  if (n.final) break;
}

console.log(`\nResult: ${pass} pass, ${fail} fail`);
process.exit(fail > 0 ? 1 : 0);
