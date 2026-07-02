import { loadActivePolicies, resolvePolicyForContext } from '../src/lib/policy/resolver.ts';

(async () => {
  const policies = await loadActivePolicies();
  console.log(`Loaded ${policies.length} active policies`);
  for (const p of policies) {
    console.log(`  #${p.priority} ${p.name} (${p.target_type}) chain=${p.action_json.approver_chain.join('->') || '(auto)'}`);
  }

  console.log('\n--- Resolution tests ---');
  const cases = [
    { label: 'staff small expense', ctx: { targetType: 'expense', totalAmount: 3500, department: 'Sales' } },
    { label: 'staff mid expense',  ctx: { targetType: 'expense', totalAmount: 25000, department: 'Engineering' } },
    { label: 'staff large',        ctx: { targetType: 'expense', totalAmount: 350000, department: 'Sales' } },
    { label: 'PR mid (Marketing)', ctx: { targetType: 'pr', totalAmount: 80000, department: 'Marketing' } },
    { label: 'PR tiny (auto)',     ctx: { targetType: 'pr', totalAmount: 4500, department: 'Development' } },
  ];
  for (const c of cases) {
    const m = await resolvePolicyForContext(c.ctx);
    console.log(`  ${c.label.padEnd(28)} -> ${m ? '#' + m.priority + ' ' + m.name : '(none, default)'}`);
  }
  process.exit(0);
})();
