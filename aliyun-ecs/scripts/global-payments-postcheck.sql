\set ON_ERROR_STOP on

SELECT "market", "status", "currency", COUNT(*) AS orders, SUM("amountCents") AS amount_cents
FROM "BillingOrder"
GROUP BY "market", "status", "currency"
ORDER BY "market", "status", "currency";

SELECT "market", "currency", "basePriceCents", "active", "defaultPaymentProvider"
FROM "MembershipOffer"
ORDER BY "market";

SELECT COUNT(*) FILTER (WHERE "offerId" IS NULL) AS orders_without_offer
FROM "BillingOrder";

SELECT COUNT(*) FILTER (WHERE "sourceOrderId" IS NOT NULL) AS linked_entitlements,
       COUNT(*) AS all_entitlements
FROM "UserMembership";
