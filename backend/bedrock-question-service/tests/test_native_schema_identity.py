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
            (True, False, "question_author_constructed_mapped_agreement_v3_n5",
             "5fde195cf2fffeff4b0b6f5035def6a68a497e12b0a2f6d09cd4ad7c1a774c47"),
            (True, True, "question_author_constructed_mapped_families_v4_n5",
             "ea9ebbe2e1cf7e594371991dd16059b0251938649db966c4d5fb334fde8058cc"),
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
