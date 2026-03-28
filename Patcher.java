import java.nio.file.*;

public class Patcher {
    public static void main(String[] args) throws Exception {
        String path = "src/main/java/com/sharefable/api/service/SubscriptionService.java";
        String content = Files.readString(Path.of(path));

        content = content.replace(
            "public void updateNoOfSeatInSubscription(Long orgId) {\n    try {",
            "public void updateNoOfSeatInSubscription(Long orgId) {\n    if (orgId == null) { log.debug(\"No orgId for seat update\"); return; }\n    try {"
        );
        content = content.replace(
            "Subscription subs = repo.getSubscriptionByOrgId(orgId);\n    String subsId = subs.getCbSubscriptionId();",
            "Subscription subs = repo.getSubscriptionByOrgId(orgId);\n    if (subs == null) { log.debug(\"No subscription for org {}\", orgId); return; }\n    String subsId = subs.getCbSubscriptionId();"
        );
        content = content.replace(
            "Subscription subs = repo.getSubscriptionByOrgId(orgId);\n      if (subs.getManagedBy()",
            "Subscription subs = repo.getSubscriptionByOrgId(orgId);\n      if (subs == null) { validationResult.setCardPresent(true); return validationResult; }\n      if (subs.getManagedBy()"
        );
        content = content.replace(
            "public RespSubscription setCreditsForOrg(Long orgId, int addedUser, boolean shouldResetUsage) {\n    Subscription subscription = repo.getSubscriptionByOrgId(orgId);",
            "public RespSubscription setCreditsForOrg(Long orgId, int addedUser, boolean shouldResetUsage) {\n    Subscription subscription = repo.getSubscriptionByOrgId(orgId);\n    if (subscription == null) { log.debug(\"No subscription for org {}\", orgId); return null; }"
        );
        content = content.replace(
            "public String createHostedPageForAiCredit(User user) {\n    Subscription subs = repo.getSubscriptionByOrgId(user.getBelongsToOrg());\n    Org org = orgRepo.findById(subs.getOrgId())",
            "public String createHostedPageForAiCredit(User user) {\n    Subscription subs = repo.getSubscriptionByOrgId(user.getBelongsToOrg());\n    if (subs == null) { log.debug(\"No subscription for AI credit\"); return null; }\n    Org org = orgRepo.findById(subs.getOrgId())"
        );
        content = content.replace(
            "public void resyncSubscription(com.chargebee.models.Subscription cbSubs, EventType eventType) {\n    Subscription subs = repo.getSubscriptionByCbSubscriptionId(cbSubs.id());\n    PaymentTerms.Plan beforePlan = subs.getPaymentPlan();",
            "public void resyncSubscription(com.chargebee.models.Subscription cbSubs, EventType eventType) {\n    Subscription subs = repo.getSubscriptionByCbSubscriptionId(cbSubs.id());\n    if (subs == null) { log.debug(\"No subscription for cb id {}\", cbSubs.id()); return; }\n    PaymentTerms.Plan beforePlan = subs.getPaymentPlan();"
        );
        content = content.replace(
            "val orgId = user.getBelongsToOrg();\n    Subscription subs = repo.getSubscriptionByOrgId(orgId);",
            "val orgId = user.getBelongsToOrg();\n    if (orgId == null) return null;\n    Subscription subs = repo.getSubscriptionByOrgId(orgId);\n    if (subs == null) return newSubscription(info, user);"
        );
        content = content.replace(
            "Subscription sub = pair.getValue0();\n    List<EntityConfigKV> entityConfigKVS = pair.getValue1();\n\n    SubscriptionInfo info = sub.getInfo();",
            "Subscription sub = pair.getValue0();\n    if (sub == null) { log.debug(\"No subscription for user {}\", user.getEmail()); throw new ResponseStatusException(HttpStatus.NOT_FOUND); }\n    List<EntityConfigKV> entityConfigKVS = pair.getValue1();\n\n    SubscriptionInfo info = sub.getInfo();"
        );
        content = content.replace(
            "Subscription subs = subscriptionWithCreditInfo.getValue0();\n    List<EntityConfigKV> creditDetails = subscriptionWithCreditInfo.getValue1();\n    EntityConfigKV fableCredit = creditDetails.stream()",
            "Subscription subs = subscriptionWithCreditInfo.getValue0();\n    if (subs == null) { log.debug(\"No subscription for credit deduction\"); return null; }\n    List<EntityConfigKV> creditDetails = subscriptionWithCreditInfo.getValue1();\n    if (creditDetails == null || creditDetails.isEmpty()) { return RespSubscription.from(subs, List.of()); }\n    EntityConfigKV fableCredit = creditDetails.stream()"
        );

        // Replace Chargebee subscription creation with self-hosted local creation
        String oldBlock = "try {\n" +
            "      final int numberOfMembersInOrg = orgService.getCountOfActiveUsersInOrg(org.getId());\n" +
            "\n" +
            "      // Create a customer object in chargebee\n" +
            "      Result cusomerResult = Customer.create()\n" +
            "        .firstName(user.getFirstName())\n" +
            "        .lastName(user.getLastName())\n" +
            "        .email(user.getEmail())\n" +
            "        .company(org.getDisplayName())\n" +
            "        .request();\n" +
            "      Customer customer = cusomerResult.customer();\n" +
            "\n" +
            "      // Create a subscription object in chargebee\n" +
            "      Result subsResult = com.chargebee.models.Subscription.createWithItems(customer.id())\n" +
            "        .subscriptionItemItemPriceId(0, planId)\n" +
            "        .subscriptionItemQuantity(0, numberOfMembersInOrg)\n" +
            "        .request();\n" +
            "      com.chargebee.models.Subscription cbSubs = subsResult.subscription();\n" +
            "\n" +
            "      Subscription subs = Subscription.builder()\n" +
            "        .paymentPlanId(planId)\n" +
            "        .paymentPlan(info.pricingPlan())\n" +
            "        .paymentInterval(info.pricingInterval())\n" +
            "        .cbSubscriptionId(cbSubs.id())\n" +
            "        .trialEndsOn(cbSubs.trialEnd())\n" +
            "        .trialStartedOn(cbSubs.trialStart())\n" +
            "        .managedBy(SubscriptionManagedBy.CHARGEBEE)\n" +
            "        .status(cbSubs.status())\n" +
            "        .orgId(org.getId())\n" +
            "        .cbCustomerId(customer.id())\n" +
            "        .build();\n" +
            "\n" +
            "      repo.save(subs);\n" +
            "      entityConfigKVS = setCreditsForOrg(subs, numberOfMembersInOrg);\n" +
            "      sendUserDetailsWithPlans(user, subs);\n" +
            "\n" +
            "      return RespSubscription.from(subs, entityConfigKVS);\n" +
            "    } catch (Exception e) {\n" +
            "      log.error(\"Can't create account subscription for user {}.  Error: {}\", user.getEmail(), e.getMessage());\n" +
            "      throw new ResponseStatusException(HttpStatus.INTERNAL_SERVER_ERROR, \"Something went wrong while creating subscription\");\n" +
            "    }";

        String newBlock = "try {\n" +
            "      final int numberOfMembersInOrg = orgService.getCountOfActiveUsersInOrg(org.getId());\n" +
            "\n" +
            "      // Self-hosted: create subscription locally without Chargebee\n" +
            "      Subscription subs = Subscription.builder()\n" +
            "        .paymentPlanId(\"self-hosted-plan\")\n" +
            "        .paymentPlan(PaymentTerms.Plan.BUSINESS)\n" +
            "        .paymentInterval(PaymentTerms.Interval.YEARLY)\n" +
            "        .cbSubscriptionId(\"self-hosted-\" + org.getId())\n" +
            "        .trialEndsOn(new java.sql.Timestamp(1893436200000L))\n" +
            "        .trialStartedOn(new java.sql.Timestamp(System.currentTimeMillis()))\n" +
            "        .managedBy(SubscriptionManagedBy.CHARGEBEE)\n" +
            "        .status(com.chargebee.models.Subscription.Status.ACTIVE)\n" +
            "        .orgId(org.getId())\n" +
            "        .cbCustomerId(\"self-hosted-\" + user.getEmail())\n" +
            "        .build();\n" +
            "\n" +
            "      repo.save(subs);\n" +
            "      entityConfigKVS = setCreditsForOrg(subs, numberOfMembersInOrg);\n" +
            "      sendUserDetailsWithPlans(user, subs);\n" +
            "\n" +
            "      return RespSubscription.from(subs, entityConfigKVS);\n" +
            "    } catch (Exception e) {\n" +
            "      log.error(\"Can't create account subscription for user {}.  Error: {}\", user.getEmail(), e.getMessage());\n" +
            "      throw new ResponseStatusException(HttpStatus.INTERNAL_SERVER_ERROR, \"Something went wrong while creating subscription\");\n" +
            "    }";

        content = content.replace(oldBlock, newBlock);

        Files.writeString(Path.of(path), content);
        System.out.println("All patches applied successfully");
    }
}
