\set ON_ERROR_STOP on

SELECT 'users' AS metric, COUNT(*)::bigint AS value FROM "User"
UNION ALL
SELECT 'orders', COUNT(*)::bigint FROM "BillingOrder"
UNION ALL
SELECT 'paid_orders', COUNT(*)::bigint FROM "BillingOrder" WHERE "status" = 'PAID'
UNION ALL
SELECT 'transactions', COUNT(*)::bigint FROM "PaymentTransaction"
UNION ALL
SELECT 'active_entitlements', COUNT(*)::bigint FROM "UserMembership" WHERE "status" = 'ACTIVE'
ORDER BY metric;

SELECT "status", "currency", COUNT(*) AS orders, SUM("amountCents") AS amount_cents
FROM "BillingOrder"
GROUP BY "status", "currency"
ORDER BY "status", "currency";
