"""Offline checks of mapped five-slot native schema identity."""

import hashlib
import unittest

from native_output_contracts import (
    AuthorSlotContract, _contract_schema, contract_metadata, native_output_config,
)


class NativeSchemaIdentityTests(unittest.TestCase):
    def test_mapped_five_schema_identity_is_stable_across_request_metadata(self):
        first = (
            ("math-a", "objective-a", "Math A", "Calculate A", 3),
            ("english-a", "objective-b", "English A", "Use A", 2),
        )
        second = (
            ("math-b", "objective-c", "Math B", "Calculate B", 3),
            ("english-b", "objective-d", "English B", "Use B", 2),
        )
        names = set()
        for agreement, families, expected_name, expected_hash in (
            (False, False, "question_author_constructed_mapped_compact_v1_n5",
             "eee8c873b7892a8b96e510777fe9ffbbc8d10cf70846644ea0993946c9c2bb3c"),
            (True, False, "question_author_constructed_mapped_agreement_v4_n5",
             "d9d26fd3b54af91ff2aeac048924f4098e3382d2f8a6062634804c884d221ab2"),
            (True, True, "question_author_constructed_mapped_families_v5_n5",
             "be8391e81587d8dca861f46cfdb0f1a89e18d88ad19a3417105affab016f2d99"),
        ):
            with self.subTest(agreement=agreement, families=families):
                original = AuthorSlotContract(5, "constructed_quantitative", first,
                                              "math-a", 2, agreement, families)
                refill = AuthorSlotContract(5, "constructed_quantitative", second,
                                            "math-b", 4, agreement, families)
                self.assertEqual(original.transport_name, expected_name)
                self.assertNotEqual(original.name, refill.name)
                original_config = native_output_config(original)
                self.assertEqual(original_config, native_output_config(refill))
                self.assertEqual(original_config["textFormat"]["structure"]["jsonSchema"]["name"],
                                 expected_name)
                schema = original_config["textFormat"]["structure"]["jsonSchema"]["schema"]
                self.assertEqual(hashlib.sha256(schema.encode()).hexdigest(), expected_hash)
                self.assertEqual(_contract_schema(original), _contract_schema(refill))
                self.assertNotEqual(contract_metadata(original)["name"],
                                    contract_metadata(refill)["name"])
                self.assertEqual(contract_metadata(original)["sha256"],
                                 contract_metadata(refill)["sha256"])
                names.add(original.transport_name)
        self.assertEqual(len(names), 3)


if __name__ == "__main__":
    unittest.main()
