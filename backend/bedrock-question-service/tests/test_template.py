import re
import unittest
from pathlib import Path


TEMPLATE = Path(__file__).resolve().parents[1] / "template.yaml"
DEPLOY_WORKFLOW = Path(__file__).resolve().parents[3] / ".github" / "workflows" / "deploy-backend.yml"
CI_WORKFLOW = Path(__file__).resolve().parents[3] / ".github" / "workflows" / "ci.yml"


class BackendInfrastructureTemplateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.template = TEMPLATE.read_text(encoding="utf-8")
        cls.deploy_workflow = DEPLOY_WORKFLOW.read_text(encoding="utf-8")
        cls.ci_workflow = CI_WORKFLOW.read_text(encoding="utf-8")

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
        self.assertIn("QuestionBankWorkerModelArn", self.template)
        self.assertIn("QuestionBankWorkerInvokeResourceArns", self.template)
        self.assertIn("Resource: !Ref BedrockInvokeResourceArns", self.template)
        self.assertIn(
            "Resource: !Ref QuestionBankWorkerInvokeResourceArns",
            self.template,
        )
        self.assertIn("bedrock:InvokeModel", self.template)
        self.assertNotIn('bedrock:InvokeModel\n              Resource: "*"', self.template)
        self.assertNotIn("bedrock:InvokeModelWithResponseStream", self.template)

    def test_synchronous_and_worker_models_are_independently_scoped(self):
        api = self.template.split("  CheckpointQuestionFunction:", maxsplit=1)[1].split(
            "\n  CheckpointQuestionFunctionLogGroup:", maxsplit=1
        )[0]
        worker = self.template.split("  QuestionBankWorkerFunction:", maxsplit=1)[1].split(
            "\n  QuestionBankWorkerFunctionLogGroup:", maxsplit=1
        )[0]
        self.assertIn("BEDROCK_MODEL_ID: !Ref BedrockModelArn", api)
        self.assertIn("Resource: !Ref BedrockInvokeResourceArns", api)
        self.assertNotIn("QuestionBankWorkerModelArn", api)
        self.assertIn(
            "BEDROCK_MODEL_ID: !Ref QuestionBankWorkerModelArn",
            worker,
        )
        self.assertIn(
            "Resource: !Ref QuestionBankWorkerInvokeResourceArns",
            worker,
        )

    def test_gpt_56_reasoning_effort_is_wired_to_api_worker_and_deploy(self):
        parameter = self.template.split("  BedrockReasoningEffort:", maxsplit=1)[1].split(
            "\n  BedrockGuardrailIdentifier:",
            maxsplit=1,
        )[0]
        self.assertIn('Default: ""', parameter)
        self.assertIn('- ""', parameter)
        for effort in ["none", "low", "medium", "high", "xhigh", "max"]:
            self.assertIn(f'- "{effort}"', parameter)

        self.assertEqual(
            self.template.count(
                "BEDROCK_REASONING_EFFORT: !Ref BedrockReasoningEffort"
            ),
            2,
        )
        self.assertIn(
            "BEDROCK_REASONING_EFFORT: ${{ vars.BEDROCK_REASONING_EFFORT || 'low' }}",
            self.deploy_workflow,
        )
        self.assertIn(
            '"BedrockReasoningEffort=$BEDROCK_REASONING_EFFORT"',
            self.deploy_workflow,
        )

    def test_worker_read_timeout_is_bounded_and_not_applied_to_api(self):
        parameter = self.template.split(
            "  QuestionBankWorkerReadTimeoutSeconds:", maxsplit=1
        )[1].split("\n  QuestionBankMaxReceiveCount:", maxsplit=1)[0]
        self.assertIn("Default: 75", parameter)
        self.assertIn("MinValue: 20", parameter)
        self.assertIn("MaxValue: 100", parameter)
        self.assertEqual(
            self.template.count(
                "BEDROCK_READ_TIMEOUT_SECONDS: !Ref QuestionBankWorkerReadTimeoutSeconds"
            ),
            1,
        )
        worker = self.template.split(
            "  QuestionBankWorkerFunction:", maxsplit=1
        )[1].split("\n  QuestionBankWorkerFunctionLogGroup:", maxsplit=1)[0]
        self.assertIn(
            "BEDROCK_READ_TIMEOUT_SECONDS: !Ref QuestionBankWorkerReadTimeoutSeconds",
            worker,
        )
        self.assertIn(
            "QUESTION_BANK_WORKER_READ_TIMEOUT_SECONDS: "
            "${{ vars.QUESTION_BANK_WORKER_READ_TIMEOUT_SECONDS || '75' }}",
            self.deploy_workflow,
        )
        self.assertIn(
            '"QuestionBankWorkerReadTimeoutSeconds='
            '$QUESTION_BANK_WORKER_READ_TIMEOUT_SECONDS"',
            self.deploy_workflow,
        )

    def test_worker_generation_chunk_size_defaults_to_one_checkpoint(self):
        parameter = self.template.split(
            "  QuestionBankGenerationChunkSize:", maxsplit=1
        )[1].split("\n  QuestionBankMaxReceiveCount:", maxsplit=1)[0]
        self.assertIn("Default: 5", parameter)
        self.assertIn("MinValue: 1", parameter)
        self.assertIn("MaxValue: 20", parameter)
        self.assertEqual(
            self.template.count(
                "QUESTION_BANK_GENERATION_CHUNK_SIZE: !Ref QuestionBankGenerationChunkSize"
            ),
            1,
        )
        self.assertIn(
            "QUESTION_BANK_GENERATION_CHUNK_SIZE: "
            "${{ vars.QUESTION_BANK_GENERATION_CHUNK_SIZE || '5' }}",
            self.deploy_workflow,
        )
        self.assertIn(
            '"QuestionBankGenerationChunkSize=$QUESTION_BANK_GENERATION_CHUNK_SIZE"',
            self.deploy_workflow,
        )

    def test_list_streams_uses_its_required_wildcard_resource(self):
        self.assertIn(
            'dynamodb:ListStreams\n              Resource: "*"',
            self.template,
        )

    def test_quota_storage_requires_hmac_and_atomic_writes(self):
        self.assertIn("QuotaHashSecret", self.template)
        self.assertIn("QUOTA_HASH_SECRET", self.template)
        self.assertIn("REQUIRE_RATE_LIMITING: \"true\"", self.template)
        self.assertIn("dynamodb:ConditionCheckItem", self.template)
        self.assertIn("dynamodb:TransactWriteItems", self.template)

    def test_api_rate_limit_transaction_has_only_required_table_actions(self):
        api = self.template.split("  CheckpointQuestionFunction:", maxsplit=1)[1].split(
            "\n  CheckpointQuestionFunctionLogGroup:", maxsplit=1
        )[0]
        rate_limit_statement = api.split(
            "Resource: !GetAtt QuestionRateLimitTable.Arn", maxsplit=1
        )[0].rsplit("- Effect: Allow", maxsplit=1)[1]

        self.assertEqual(
            set(re.findall(r"- (dynamodb:[A-Za-z]+)", rate_limit_statement)),
            {"dynamodb:TransactWriteItems", "dynamodb:UpdateItem"},
        )

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
        self.assertIn("QuestionBankWorkerModelArn", workflow_overrides)
        self.assertIn("QuestionBankWorkerInvokeResourceArns", workflow_overrides)
        self.assertIn("BedrockReasoningEffort", workflow_overrides)
        self.assertNotIn("BedrockModelId", workflow_overrides)

    def test_ci_and_deploy_compile_question_bank_module(self):
        compile_command = r"python -m compileall -q [^\n]*question_bank\.py"
        self.assertRegex(self.ci_workflow, compile_command)
        self.assertRegex(self.deploy_workflow, compile_command)


if __name__ == "__main__":
    unittest.main()
