import unittest

from schema import (
    encode_metadata,
    feature_names,
    label_identified_by_blank_metadata,
    metadata_dim,
    metadata_is_blank,
    parse_tone,
)


class MetadataContractTest(unittest.TestCase):
    def test_dimension_matches_named_features(self):
        self.assertEqual(metadata_dim(), 28)
        self.assertEqual(len(feature_names()), 28)

    def test_missing_fields_are_unknown_not_no(self):
        vector = encode_metadata()
        names = feature_names()
        self.assertEqual(vector[names.index("body:Unknown")], 1.0)
        self.assertEqual(vector[names.index("itch:unknown")], 1.0)
        self.assertEqual(vector[names.index("itch:no")], 0.0)
        self.assertTrue(metadata_is_blank(vector))

    def test_known_answers_use_the_app_order(self):
        vector = encode_metadata(
            body_site="Face",
            itch="yes",
            pain="no",
            swelling=None,
            changed="yes",
            duration="Less than a week",
        )
        names = feature_names()
        self.assertEqual(vector[names.index("body:Face")], 1.0)
        self.assertEqual(vector[names.index("itch:yes")], 1.0)
        self.assertEqual(vector[names.index("pain:no")], 1.0)
        self.assertEqual(vector[names.index("swelling:unknown")], 1.0)
        self.assertEqual(vector[names.index("changed:yes")], 1.0)
        self.assertEqual(vector[names.index("duration:Less than a week")], 1.0)
        self.assertEqual(sum(vector), 6.0)

    def test_blank_metadata_must_not_identify_one_label(self):
        self.assertEqual(
            label_identified_by_blank_metadata([True, True, False], ["healthy", "healthy", "melanoma"]),
            "healthy",
        )
        self.assertIsNone(label_identified_by_blank_metadata([True, False, True], ["healthy", "healthy", "melanoma"]))
        self.assertIsNone(label_identified_by_blank_metadata([True, True], ["healthy", "melanoma"]))

    def test_fitzpatrick_groups(self):
        self.assertEqual(parse_tone(5), ("FST V-VI", 5))
        self.assertEqual(parse_tone("II")[0], "FST I-II")
        self.assertEqual(parse_tone(None), ("Unknown", None))


if __name__ == "__main__":
    unittest.main()
