# ==============================================================================
# Fable API Server - Self-Hosted (Real AWS S3 + SQS)
# Only patches: Chargebee bypass, Sentry null-safe, Firehose no-op
# S3 and SQS use real AWS - NO patches needed
# ==============================================================================

FROM maven:3.8.3-openjdk-17 AS builder

WORKDIR /tmp/api

COPY pom.xml ./pom.xml
RUN mvn -B dependency:go-offline

COPY src ./src

# ==============================================================================
# PATCH 1: No-op FirehoseConfig (no Kinesis Firehose)
# ==============================================================================
RUN printf 'package com.sharefable.api.config;\n\
\n\
import lombok.AllArgsConstructor;\n\
import lombok.Data;\n\
import lombok.NoArgsConstructor;\n\
import lombok.extern.slf4j.Slf4j;\n\
import org.springframework.boot.context.properties.ConfigurationProperties;\n\
import org.springframework.context.annotation.Configuration;\n\
\n\
@Configuration\n\
@ConfigurationProperties(prefix = "com.sharefable.api.firehose")\n\
@NoArgsConstructor\n\
@AllArgsConstructor\n\
@Data\n\
@Slf4j\n\
public class FirehoseConfig {\n\
    private String streamPrefix;\n\
    private String region;\n\
}\n' > src/main/java/com/sharefable/api/config/FirehoseConfig.java

# ==============================================================================
# PATCH 2: No-op FirehoseService
# ==============================================================================
RUN printf 'package com.sharefable.api.service;\n\
\n\
import com.sharefable.api.config.FirehoseConfig;\n\
import lombok.RequiredArgsConstructor;\n\
import lombok.extern.slf4j.Slf4j;\n\
import org.springframework.stereotype.Service;\n\
\n\
@Service\n\
@Slf4j\n\
@RequiredArgsConstructor\n\
public class FirehoseService {\n\
    private final FirehoseConfig firehoseConfig;\n\
\n\
    public void sendEventsToFirehose(String prefix, String sub, String userEventLogs) {\n\
        log.debug("Firehose disabled");\n\
    }\n\
\n\
    public void sendEventsToFirehose(String sub, String userEventLogs) {\n\
        log.debug("Firehose disabled");\n\
    }\n\
}\n' > src/main/java/com/sharefable/api/service/FirehoseService.java

# ==============================================================================
# PATCH 3: Null-safe SentryUserInfoConfig
# ==============================================================================
RUN printf 'package com.sharefable.api.config;\n\
\n\
import com.sharefable.api.service.UserService;\n\
import io.sentry.protocol.User;\n\
import io.sentry.spring.jakarta.SentryUserProvider;\n\
import lombok.extern.slf4j.Slf4j;\n\
import org.springframework.security.core.context.SecurityContextHolder;\n\
import org.springframework.security.oauth2.jwt.Jwt;\n\
import org.springframework.stereotype.Component;\n\
\n\
@Component\n\
@Slf4j\n\
public class SentryUserInfoConfig implements SentryUserProvider {\n\
    private final UserService userService;\n\
\n\
    public SentryUserInfoConfig(UserService userService) {\n\
        this.userService = userService;\n\
    }\n\
\n\
    public User provideUser() {\n\
        try {\n\
            if (SecurityContextHolder.getContext().getAuthentication() != null\n\
                && SecurityContextHolder.getContext().getAuthentication().getPrincipal() instanceof Jwt) {\n\
                Jwt jwt = (Jwt) SecurityContextHolder.getContext().getAuthentication().getPrincipal();\n\
                UserService.UserClaimFromAuth0 fableUser = userService.getUserClaimsFromAuth0(jwt);\n\
                if (fableUser != null) {\n\
                    User sentryUser = new User();\n\
                    sentryUser.setEmail(fableUser.email());\n\
                    return sentryUser;\n\
                }\n\
            }\n\
        } catch (Exception e) {\n\
            log.debug("Could not resolve user for Sentry: {}", e.getMessage());\n\
        }\n\
        return null;\n\
    }\n\
}\n' > src/main/java/com/sharefable/api/config/SentryUserInfoConfig.java

# ==============================================================================
# PATCH 4: PaymentConfig - skip Chargebee init, add self-hosted plan
# ==============================================================================
RUN printf 'package com.sharefable.api.config;\n\
\n\
import com.chargebee.Environment;\n\
import com.sharefable.api.transport.PaymentTerms;\n\
import jakarta.annotation.PostConstruct;\n\
import lombok.AllArgsConstructor;\n\
import lombok.Data;\n\
import lombok.NoArgsConstructor;\n\
import lombok.extern.slf4j.Slf4j;\n\
import org.apache.commons.lang3.StringUtils;\n\
import org.javatuples.Pair;\n\
import org.springframework.boot.context.properties.ConfigurationProperties;\n\
import org.springframework.context.annotation.Configuration;\n\
\n\
import java.util.Map;\n\
\n\
@Configuration\n\
@ConfigurationProperties(prefix = "com.sharefable.payment")\n\
@NoArgsConstructor\n\
@AllArgsConstructor\n\
@Data\n\
@Slf4j\n\
public class PaymentConfig {\n\
  public static final Map<String, CreditValue> PLAN_DEFAULT_AI_CREDIT = Map.ofEntries(\n\
    Map.entry("IN_TRIAL", new CreditValue(1000, false)),\n\
    Map.entry("self-hosted-plan", new CreditValue(99999, false)),\n\
    Map.entry("solo-4-USD-Yearly", new CreditValue(1000, false)),\n\
    Map.entry("solo-4-USD-Monthly", new CreditValue(1000, false)),\n\
    Map.entry("solo-3-USD-Yearly", new CreditValue(1000, false)),\n\
    Map.entry("solo-3-USD-Monthly", new CreditValue(1000, false)),\n\
    Map.entry("startup-1-USD-Monthly", new CreditValue(2000, true)),\n\
    Map.entry("startup-1-USD-Yearly", new CreditValue(2000, true)),\n\
    Map.entry("business-3-USD-Monthly", new CreditValue(5000, true)),\n\
    Map.entry("business-3-USD-Yearly", new CreditValue(5000, true)),\n\
    Map.entry("tier-1-USD-lifetime", new CreditValue(200, false)),\n\
    Map.entry("tier-2-USD-lifetime", new CreditValue(500, false)),\n\
    Map.entry("tier-3-USD-lifetime", new CreditValue(1000, false)),\n\
    Map.entry("tier-4-USD-lifetime", new CreditValue(2000, false)),\n\
    Map.entry("tier-5-USD-lifetime", new CreditValue(5000, false))\n\
  );\n\
  private static final Map<PaymentTerms.Plan, Map<PaymentTerms.Interval, String>> PAYMENT_TERMS_PLAN = Map.of(\n\
    PaymentTerms.Plan.SOLO, Map.of(PaymentTerms.Interval.MONTHLY, "solo-4-USD-Monthly", PaymentTerms.Interval.YEARLY, "solo-4-USD-Yearly"),\n\
    PaymentTerms.Plan.STARTUP, Map.of(PaymentTerms.Interval.MONTHLY, "startup-1-USD-Monthly", PaymentTerms.Interval.YEARLY, "startup-1-USD-Yearly"),\n\
    PaymentTerms.Plan.BUSINESS, Map.of(PaymentTerms.Interval.MONTHLY, "business-3-USD-Monthly", PaymentTerms.Interval.YEARLY, "business-3-USD-Yearly"),\n\
    PaymentTerms.Plan.LIFETIME_TIER1, Map.of(PaymentTerms.Interval.LIFETIME, "tier-1-USD-lifetime"),\n\
    PaymentTerms.Plan.LIFETIME_TIER2, Map.of(PaymentTerms.Interval.LIFETIME, "tier-2-USD-lifetime"),\n\
    PaymentTerms.Plan.LIFETIME_TIER3, Map.of(PaymentTerms.Interval.LIFETIME, "tier-3-USD-lifetime"),\n\
    PaymentTerms.Plan.LIFETIME_TIER4, Map.of(PaymentTerms.Interval.LIFETIME, "tier-4-USD-lifetime"),\n\
    PaymentTerms.Plan.LIFETIME_TIER5, Map.of(PaymentTerms.Interval.LIFETIME, "tier-5-USD-lifetime")\n\
  );\n\
  private String cbSiteName;\n\
  private String cbApiKey;\n\
  private String aiChargeId;\n\
\n\
  @PostConstruct\n\
  public void configure() {\n\
    if (StringUtils.isNotBlank(cbSiteName) && !StringUtils.equalsIgnoreCase(cbSiteName, "disabled")) {\n\
      Environment.configure(cbSiteName, cbApiKey);\n\
    } else {\n\
      log.info("Chargebee disabled - self-hosted mode");\n\
    }\n\
  }\n\
\n\
  public String getPlanId(PaymentTerms.Plan plan, PaymentTerms.Interval interval) {\n\
    Map<PaymentTerms.Interval, String> plans = PAYMENT_TERMS_PLAN.get(plan);\n\
    return plans == null ? null : plans.get(interval);\n\
  }\n\
\n\
  public Pair<PaymentTerms.Plan, PaymentTerms.Interval> getPlanItemsById(String planId) {\n\
    for (Map.Entry<PaymentTerms.Plan, Map<PaymentTerms.Interval, String>> item : PAYMENT_TERMS_PLAN.entrySet()) {\n\
      for (Map.Entry<PaymentTerms.Interval, String> item2 : item.getValue().entrySet()) {\n\
        if (StringUtils.equals(item2.getValue(), planId)) {\n\
          return Pair.with(item.getKey(), item2.getKey());\n\
        }\n\
      }\n\
    }\n\
    return null;\n\
  }\n\
\n\
  public record CreditValue(int value, boolean isCreditPerUser) {}\n\
}\n' > src/main/java/com/sharefable/api/config/PaymentConfig.java

# ==============================================================================
# PATCH 5: Null-safe SubscriptionService + self-hosted subscription creation
# ==============================================================================
COPY Patcher.java /tmp/Patcher.java
RUN javac /tmp/Patcher.java -d /tmp && java -cp /tmp Patcher

RUN mvn -B clean package -Dmaven.test.skip=true

# ==============================================================================
# Runtime
# ==============================================================================
FROM openjdk:17.0.1-jdk-slim

RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

EXPOSE 8080

COPY --from=builder /tmp/api/target/api-*.jar /usr/local/fable/api.jar
RUN mkdir -p /usr/local/fable/config

WORKDIR /usr/local/fable

ENTRYPOINT ["java", "-jar", "api.jar"]
