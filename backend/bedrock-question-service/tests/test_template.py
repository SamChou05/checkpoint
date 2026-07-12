import re
import unittest
from pathlib import Path


TEMPLATE = Path(__file__).resolve().parents[1] / "template.yaml"
DEPLOY_WORKFLOW = Path(__file__).resolve().parents[3] / ".github" / "workflows" / "deploy-backend.yml"


class BackendInfrastructureTemplateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.template = TEMPLATE.read_text(encoding="utf-8")
        cls.deploy_workflow = DEPLOY_WORKFLOW.read_text(encoding="utf-8")

    def test_uses_throttled_http_api_instead_of_public_function_url(self):
        self.assertIn("Type: AWS::Serverless::HttpApi", self.template)
        self.assertIn("ThrottlingRateLimit", self.template)
        self.assertIn("ThrottlingBurstLimit", self.template)
        self.assertIn("ReservedConcurrentExecutions", self.template)
        self.assertNotIn("FunctionUrlConfig", self.template)

    def test_has_log_retention_alerting_and_optional_budget(self):
        self.assertIn("Type: AWS::Logs::LogGroup", self.template)
        self.assertIn("RetentionInDays", self.template)
        self.assertIn("Type: AWS::SNS::Topic", self.template)
        self.assertIn("Type: AWS::CloudWatch::Alarm", self.template)
        self.assertIn("Type: AWS::Budgets::Budget", self.template)

    def test_bedrock_permissions_are_scoped_to_explicit_invoke_resources(self):
        self.assertIn("BedrockModelArn", self.template)
        self.assertIn("BedrockInvokeResourceArns", self.template)
        self.assertIn("Resource: !Ref BedrockInvokeResourceArns", self.template)
        self.assertIn("bedrock:InvokeModel", self.template)
        self.assertNotIn('Resource: "*"', self.template)
        self.assertNotIn("bedrock:InvokeModelWithResponseStream", self.template)

    def test_quota_storage_requires_hmac_and_atomic_writes(self):
        self.assertIn("QuotaHashSecret", self.template)
        self.assertIn("QUOTA_HASH_SECRET", self.template)
        self.assertIn("REQUIRE_RATE_LIMITING: \"true\"", self.template)
        self.assertIn("dynamodb:TransactWriteItems", self.template)

    def test_guardrail_and_kill_switch_configuration_are_exposed(self):
        self.assertIn("BEDROCK_GUARDRAIL_IDENTIFIER", self.template)
        self.assertIn("BEDROCK_GUARDRAIL_VERSION", self.template)
        self.assertIn("bedrock:ApplyGuardrail", self.template)
        self.assertIn("SERVICE_MODE", self.template)

    def test_guardrail_rules_fail_closed_for_partial_and_unsafe_production_configuration(self):
        self.assertIn("GuardrailConfigurationAllOrNone:", self.template)
        self.assertIn("ProductionRequiresSafetyAndNotifications:", self.template)
        production_rule = self.template.split(
            "ProductionRequiresSafetyAndNotifications:",
            maxsplit=1,
        )[1].split("\nConditions:", maxsplit=1)[0]
        for parameter in [
            "BedrockGuardrailIdentifier",
            "BedrockGuardrailVersion",
            "BedrockGuardrailArn",
            "AlertEmail",
            "BudgetAlertEmail",
        ]:
            self.assertIn(parameter, production_rule)

    def test_deploy_workflow_override_keys_match_current_sam_parameters(self):
        parameter_section = self.template.split("Parameters:", maxsplit=1)[1].split(
            "\nRules:",
            maxsplit=1,
        )[0]
        template_parameters = set(
            re.findall(r"^  ([A-Z][A-Za-z0-9]+):$", parameter_section, flags=re.MULTILINE)
        )
        workflow_overrides = set(
            re.findall(
                r'^\s+"([A-Z][A-Za-z0-9]+)=',
                self.deploy_workflow,
                flags=re.MULTILINE,
            )
        )

        self.assertEqual(workflow_overrides, template_parameters)
        self.assertIn("BedrockModelArn", workflow_overrides)
        self.assertIn("BedrockInvokeResourceArns", workflow_overrides)
        self.assertNotIn("BedrockModelId", workflow_overrides)


if __name__ == "__main__":
    unittest.main()
