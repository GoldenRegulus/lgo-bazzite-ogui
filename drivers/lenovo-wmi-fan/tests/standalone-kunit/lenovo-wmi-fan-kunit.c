// SPDX-License-Identifier: GPL-2.0-or-later
/* KUnit tests for pure helpers extracted from wmi-other.c. */

#include <kunit/test.h>
#include <linux/module.h>

static void lenovo_fan_dmi_test(struct kunit *test)
{
	const struct lenovo_handheld_dmi *entry;

	entry = lenovo_handheld_find("LENOVO", "83E1", "Legion Go 8APU1");
	KUNIT_ASSERT_NOT_NULL(test, entry);
	KUNIT_EXPECT_EQ(test, entry->curve_max, (u16)LENOVO_FAN_CURVE_GO_MAX);

	entry = lenovo_handheld_find("LENOVO", "83N0", "unknown");
	KUNIT_ASSERT_NOT_NULL(test, entry);
	KUNIT_EXPECT_EQ(test, entry->curve_max, (u16)LENOVO_FAN_CURVE_GO2_MAX);
	entry = lenovo_handheld_find("LENOVO", "83N1", "unknown");
	KUNIT_ASSERT_NOT_NULL(test, entry);
	KUNIT_EXPECT_EQ(test, entry->curve_max, (u16)LENOVO_FAN_CURVE_GO2_MAX);
	entry = lenovo_handheld_find("LENOVO", "unknown", "Legion Go 8ASP2");
	KUNIT_ASSERT_NOT_NULL(test, entry);
	KUNIT_EXPECT_EQ(test, entry->curve_max, (u16)LENOVO_FAN_CURVE_GO2_MAX);
	entry = lenovo_handheld_find("LENOVO", "unknown", "Legion Go 8AHP2");
	KUNIT_ASSERT_NOT_NULL(test, entry);
	KUNIT_EXPECT_EQ(test, entry->curve_max, (u16)LENOVO_FAN_CURVE_GO2_MAX);
	entry = lenovo_handheld_find("LENOVO", "83E1", "Legion Go 8ASP2");
	KUNIT_EXPECT_PTR_EQ(test, entry, NULL);
	entry = lenovo_handheld_find("LENOVO", "83N0", "Legion Go 8APU1");
	KUNIT_EXPECT_PTR_EQ(test, entry, NULL);
	entry = lenovo_handheld_find("LENOVO", "83E1", "unknown");
	KUNIT_EXPECT_PTR_EQ(test, entry, NULL);
	entry = lenovo_handheld_find("LENOVO", "unknown", "Legion Go S 8APU1");
	KUNIT_EXPECT_PTR_EQ(test, entry, NULL);
	entry = lenovo_handheld_find("OTHER", "83N0", "unknown");
	KUNIT_EXPECT_PTR_EQ(test, entry, NULL);
}

static void lenovo_fan_curve_reply_test(struct kunit *test)
{
	struct lenovo_fan_curve curve;
	u8 reply[LENOVO_FAN_CURVE_REPLY_SIZE] = {};
	int i;

	KUNIT_EXPECT_EQ(test, lenovo_fan_curve_parse_reply(NULL, sizeof(reply),
							   LENOVO_FAN_CURVE_GO_MAX, &curve),
			-ENODATA);
	KUNIT_EXPECT_EQ(test, lenovo_fan_curve_parse_reply(reply, sizeof(reply) - 1,
							   LENOVO_FAN_CURVE_GO_MAX, &curve),
			-ENODATA);
	put_unaligned_le32(9, reply);
	KUNIT_EXPECT_EQ(test, lenovo_fan_curve_parse_reply(reply, sizeof(reply),
							   LENOVO_FAN_CURVE_GO_MAX, &curve),
			-ERANGE);
	put_unaligned_le32(LENOVO_FAN_CURVE_POINTS, reply);
	put_unaligned_le32(9, reply + 44);
	KUNIT_EXPECT_EQ(test, lenovo_fan_curve_parse_reply(reply, sizeof(reply),
							   LENOVO_FAN_CURVE_GO_MAX, &curve),
			-ERANGE);
	put_unaligned_le32(LENOVO_FAN_CURVE_POINTS, reply + 44);
	for (i = 0; i < LENOVO_FAN_CURVE_POINTS; i++)
		put_unaligned_le32(i == 0 ? 0 : 44, reply + sizeof(u32) + i * sizeof(u32));
	KUNIT_EXPECT_EQ(test, lenovo_fan_curve_parse_reply(reply, sizeof(reply),
							   LENOVO_FAN_CURVE_GO_MAX, &curve), 0);
	KUNIT_EXPECT_EQ(test, curve.speed[0], (u16)0);
	put_unaligned_le32(LENOVO_FAN_CURVE_GO2_MAX + 1, reply + sizeof(u32));
	KUNIT_EXPECT_EQ(test, lenovo_fan_curve_parse_reply(reply, sizeof(reply),
							   LENOVO_FAN_CURVE_GO2_MAX, &curve),
			-ERANGE);
}

static void lenovo_fan_curve_serializer_test(struct kunit *test)
{
	struct lenovo_fan_curve curve = {
		.speed = { 44, 45, 46, 47, 48, 49, 50, 51, 52, 53 },
	};
	u8 expected[LENOVO_FAN_CURVE_WRITE_SIZE] = {
		0xff, 0x01, 0x0a, 0x00, 0x00, 0x00,
		0x2c, 0x00, 0x2d, 0x00, 0x2e, 0x00, 0x2f, 0x00,
		0x30, 0x00, 0x31, 0x00, 0x32, 0x00, 0x33, 0x00,
		0x34, 0x00, 0x35, 0x00,
		0x01, 0x0a, 0x00, 0x00, 0x00,
		0x0a, 0x00, 0x14, 0x00, 0x1e, 0x00, 0x28, 0x00,
		0x32, 0x00, 0x3c, 0x00, 0x46, 0x00, 0x50, 0x00,
		0x5a, 0x00, 0x64, 0x00,
		0x5a, 0x00, 0x64, 0x00, 0x00,
	};
	u8 buffer[LENOVO_FAN_CURVE_WRITE_SIZE] = {};

	lenovo_fan_curve_serialize(&curve, buffer);
	KUNIT_EXPECT_EQ(test, sizeof(buffer), (size_t)64);
	KUNIT_EXPECT_MEMEQ(test, buffer, expected, sizeof(buffer));
}

static void lenovo_fan_curve_validation_test(struct kunit *test)
{
	struct lenovo_fan_curve curve = {
		.speed = { 0, 0, 1, 2, 3, 4, 5, 79, 100, 115 },
	};

	KUNIT_EXPECT_TRUE(test, lenovo_fan_curve_user_valid(&curve, LENOVO_FAN_CURVE_GO2_MAX));
	curve.speed[0] = 115;
	KUNIT_EXPECT_FALSE(test, lenovo_fan_curve_user_valid(&curve, LENOVO_FAN_CURVE_GO2_MAX));
	curve.speed[0] = 0;
	curve.speed[8] = 114;
	curve.speed[9] = 113;
	KUNIT_EXPECT_FALSE(test, lenovo_fan_curve_user_valid(&curve, LENOVO_FAN_CURVE_GO2_MAX));
	curve.speed[9] = 116;
	KUNIT_EXPECT_FALSE(test, lenovo_fan_curve_user_valid(&curve, LENOVO_FAN_CURVE_GO2_MAX));
}

static void lenovo_fan_fullspeed_and_rpm_test(struct kunit *test)
{
	bool enabled;

	KUNIT_EXPECT_EQ(test, lenovo_fan_fullspeed_parse(0, &enabled), 0);
	KUNIT_EXPECT_FALSE(test, enabled);
	KUNIT_EXPECT_EQ(test, lenovo_fan_fullspeed_parse(1, &enabled), 0);
	KUNIT_EXPECT_TRUE(test, enabled);
	KUNIT_EXPECT_EQ(test, lenovo_fan_fullspeed_parse(2, &enabled), -ERANGE);
}

static struct kunit_case lenovo_wmi_fan_test_cases[] = {
	KUNIT_CASE(lenovo_fan_dmi_test),
	KUNIT_CASE(lenovo_fan_curve_reply_test),
	KUNIT_CASE(lenovo_fan_curve_serializer_test),
	KUNIT_CASE(lenovo_fan_curve_validation_test),
	KUNIT_CASE(lenovo_fan_fullspeed_and_rpm_test),
	{}
};

static struct kunit_suite lenovo_wmi_fan_test_suite = {
	.name = "lenovo-wmi-fan",
	.test_cases = lenovo_wmi_fan_test_cases,
};

kunit_test_suite(lenovo_wmi_fan_test_suite);

MODULE_DESCRIPTION("Lenovo WMI fan helper KUnit tests");
MODULE_LICENSE("GPL");
