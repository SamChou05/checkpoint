"""One read-only configuration snapshot; no invocation, deployment, or package download."""

from datetime import datetime, timezone
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess

from botocore.config import Config

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SERVICE = ROOT / 'backend/bedrock-question-service'
PRIOR = ROOT / 'docs/evidence/reviewer-release-20260922/deployment-current.json'
HELPER = SERVICE / 'evals/bounded_bedrock_capture.py'
spec = importlib.util.spec_from_file_location('read_only_capture_helper', HELPER)
safe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(safe)
PARAMETERS = (
    'BedrockModelArn', 'BedrockInvokeResourceArns', 'QuestionBankWorkerModelArn',
    'QuestionBankWorkerInvokeResourceArns', 'SkillMapModelArn', 'SkillMapInvokeResourceArns',
    'BedrockVerificationModelArn', 'BedrockVerificationInvokeResourceArns', 'BedrockFallbackModelArn',
    'BedrockStructuredOutputMode', 'QuestionBankWorkerStructuredOutputMode',
    'QuestionAuthorMode', 'QuestionBankWorkerAuthorMode', 'QuestionBankWorkerFeedbackContract',
    'BedrockMaxTokens', 'BedrockThinkingMaxTokens', 'BedrockKimiThinking',
    'BedrockClaudeThinking', 'QuestionBankWorkerClaudeThinking', 'BedrockClaudeEffort',
    'BedrockReasoningEffort', 'QuestionBankWorkerReadTimeoutSeconds', 'MaxProviderCallsPerRequest',
    'GenerationAttempts', 'QuestionBankGenerationChunkSize', 'QuestionBankMaxReceiveCount',
    'QuestionBankMaxFailedGenerationJobs', 'MaxQuestionsPerBatch', 'ServiceMode',
    'ReservedConcurrency', 'QuestionBankWorkerReservedConcurrency', 'DeploymentEnvironment',
)
ENVIRONMENT = (
    'BEDROCK_MODEL_ID', 'SKILL_MAP_MODEL_ID', 'BEDROCK_VERIFICATION_MODEL_ID',
    'BEDROCK_FALLBACK_MODEL_ID', 'BEDROCK_STRUCTURED_OUTPUT_MODE', 'QUESTION_AUTHOR_MODE',
    'QUESTION_FEEDBACK_CONTRACT', 'BEDROCK_KIMI_THINKING', 'BEDROCK_CLAUDE_THINKING',
    'BEDROCK_REASONING_EFFORT', 'BEDROCK_MAX_TOKENS', 'BEDROCK_THINKING_MAX_TOKENS',
    'BEDROCK_CLAUDE_EFFORT', 'BEDROCK_READ_TIMEOUT_SECONDS', 'BEDROCK_CONNECT_TIMEOUT_SECONDS',
    'BEDROCK_TEMPERATURE', 'MAX_PROVIDER_CALLS_PER_REQUEST', 'GENERATION_ATTEMPTS',
    'QUESTION_BANK_GENERATION_CHUNK_SIZE', 'QUESTION_BANK_MAX_RECEIVE_COUNT',
    'QUESTION_BANK_MAX_FAILED_GENERATION_JOBS', 'MAX_QUESTIONS_PER_BATCH',
    'MIN_PROVIDER_REMAINING_MILLISECONDS', 'SERVICE_MODE', 'DEPLOYMENT_ENVIRONMENT',
)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    prior = json.loads(PRIOR.read_text())
    assert prior['stack'] == 'checkpoint-question-service-testflight' and prior['region'] == 'us-east-1'
    sources = [PRIOR, HELPER, Path(__file__).resolve(), SERVICE / 'template.yaml',
               ROOT / '.github/workflows/deploy-backend.yml', SERVICE / 'scripts/deploy-sam.sh',
               SERVICE / 'question_generation.py', SERVICE / 'question_verification.py',
               SERVICE / 'verification_policy.py', ROOT / 'Checkpoint/Models/QuestionModels.swift']
    pins = {str(path.relative_to(ROOT)): sha(path) for path in sources}
    snapshot = {
        'observedUTC': datetime.now(timezone.utc).isoformat(), 'stack': prior['stack'], 'region': prior['region'],
        'candidateCommit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
        'sourceSha256': pins, 'credentialLimits': {'seconds': safe.CREDENTIAL_TIMEOUT_SECONDS, 'bytes': safe.CREDENTIAL_MAX_BYTES},
        'scope': 'Only DescribeStacks, two DescribeStackResource, and two GetFunctionConfiguration calls. No provider, invocation, writes, deployment, package downloads, credentials, guardrail identifiers, or signed URLs retained.',
        'status': 'started', 'functions': [],
    }
    secrets = ()
    try:
        session, secrets = safe.credential_session()
        config = Config(connect_timeout=3, read_timeout=20, retries={'mode': 'standard', 'total_max_attempts': 1})
        cloudformation = session.client('cloudformation', region_name=prior['region'],
                                       endpoint_url='https://cloudformation.us-east-1.amazonaws.com', config=config)
        functions = session.client('lambda', region_name=prior['region'],
                                   endpoint_url='https://lambda.us-east-1.amazonaws.com', config=config)
        stack = cloudformation.describe_stacks(StackName=prior['stack'])['Stacks'][0]
        values = {entry['ParameterKey']: entry.get('ParameterValue') for entry in stack['Parameters']}
        snapshot.update(stackStatus=stack['StackStatus'],
                        stackLastUpdatedUTC=stack.get('LastUpdatedTime').isoformat() if stack.get('LastUpdatedTime') else None,
                        selectedStackParameters={key: safe.redact(values.get(key), secrets, maximum=4096) for key in PARAMETERS},
                        guardrailParameterPresence={key: bool(values.get(key)) for key in (
                            'BedrockGuardrailIdentifier', 'BedrockGuardrailVersion', 'BedrockGuardrailArn')})
        for logical in ('CheckpointQuestionFunction', 'QuestionBankWorkerFunction'):
            name = cloudformation.describe_stack_resource(StackName=prior['stack'], LogicalResourceId=logical)['StackResourceDetail']['PhysicalResourceId']
            current = functions.get_function_configuration(FunctionName=name)
            env = current.get('Environment', {}).get('Variables', {})
            snapshot['functions'].append({
                'logicalID': logical, 'functionName': safe.redact(current['FunctionName'], secrets, maximum=256),
                'lastModified': current['LastModified'], 'state': current.get('State'),
                'lastUpdateStatus': current.get('LastUpdateStatus'), 'runtime': current['Runtime'],
                'architectures': current.get('Architectures'), 'timeoutSeconds': current['Timeout'],
                'memoryMB': current['MemorySize'], 'packageSha256': current['CodeSha256'],
                'environmentReadErrorPresent': bool(current.get('Environment', {}).get('Error')),
                'settings': {key: safe.redact(env.get(key), secrets, maximum=4096) for key in ENVIRONMENT},
                'guardrailEnvironmentPresence': {key: bool(env.get(key)) for key in (
                    'BEDROCK_GUARDRAIL_IDENTIFIER', 'BEDROCK_GUARDRAIL_VERSION')},
            })
        assert all(sha(ROOT / path) == value for path, value in pins.items())
        snapshot['status'] = 'complete'
    except Exception as error:
        snapshot.update(status='failed', error=safe.safe_error(error, secrets))
    encoded = json.dumps(snapshot, indent=2, allow_nan=False) + '\n'
    assert not any(secret and secret in encoded for secret in secrets)
    with (HERE / 'deployment-current.json').open('x') as handle:
        handle.write(encoded)
    print(json.dumps({'status': snapshot['status'], 'functionCount': len(snapshot['functions']),
                      'snapshotSha256': hashlib.sha256(encoded.encode()).hexdigest()}))


if __name__ == '__main__':
    main()
