#!/usr/bin/env python3
"""Validate native Converse shapes using only a built Lambda artifact's SDK.

Run with Python 3.12 and ``-I -S`` to exclude host site packages and Python
environment paths. This script creates no clients and makes no provider calls.
"""

import argparse
import json
from pathlib import Path
import sys
from typing import get_args


PINNED_SDK_VERSION = "1.43.91"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("artifact", type=Path, help="Built Lambda function directory")
    arguments = parser.parse_args()
    if not sys.flags.isolated or not sys.flags.no_site:
        parser.error("Run this verifier with python -I -S to exclude the host SDK.")
    artifact = arguments.artifact.resolve(strict=True)
    if not artifact.is_dir():
        parser.error("The artifact path must be a directory.")
    sys.path.insert(0, str(artifact))

    import boto3
    import botocore
    from botocore.loaders import Loader
    from botocore.model import ServiceModel
    from botocore.validate import validate_parameters
    import native_output_contracts

    for package in (boto3, botocore, native_output_contracts):
        module_path = Path(package.__file__).resolve()
        if not module_path.is_relative_to(artifact):
            raise RuntimeError(f"{package.__name__} was imported outside the artifact.")
    for package in (boto3, botocore):
        if package.__version__ != PINNED_SDK_VERSION:
            raise RuntimeError(
                f"{package.__name__} must be {PINNED_SDK_VERSION}; "
                f"artifact contains {package.__version__}."
            )

    # Exclude ~/.aws/models and the host SDK's bundled data as well as site
    # packages. The service model must come from the delivered artifact.
    model_directory = artifact / "botocore" / "data"
    loader = Loader(
        extra_search_paths=[str(model_directory)],
        include_default_search_paths=False,
    )
    service_data = loader.load_service_model("bedrock-runtime", "service-2")
    shape = ServiceModel(service_data, service_name="bedrock-runtime").operation_model(
        "Converse"
    ).input_shape
    contracts = get_args(native_output_contracts.Contract)
    if len(contracts) != 6:
        raise RuntimeError("Expected the six versioned native stage contracts.")
    for contract in contracts:
        request = {
            "modelId": "us.anthropic.claude-sonnet-4-6",
            "messages": [{"role": "user", "content": [{
                "text": "synthetic artifact qualification",
            }]}],
            "system": [{"text": "synthetic rules"}],
            "inferenceConfig": {"maxTokens": 6000, "temperature": 0.2},
            "outputConfig": native_output_contracts.native_output_config(contract),
        }
        validate_parameters(request, shape)
    print(json.dumps({
        "artifact": str(artifact),
        "boto3_version": boto3.__version__,
        "boto3_path": boto3.__file__,
        "botocore_version": botocore.__version__,
        "botocore_path": botocore.__file__,
        "service_model_search_paths": loader.search_paths,
        "validated_contracts": contracts,
        "sdk_request_shapes_validated": len(contracts),
        "live_provider_calls": 0,
    }, indent=2))


if __name__ == "__main__":
    main()
