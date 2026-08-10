// SPDX-License-Identifier: GPL-2.0-or-later
/* KUnit tests for the Lenovo Legion Go command transport. */

#include <kunit/test.h>
#include <linux/completion.h>
#include <linux/errno.h>
#include <linux/module.h>
#include <linux/types.h>

#define GO_INPUT_REPORT_ID	0x04
#define GO_MCU_CONFIG_DATA	0x00
#define GO_CMD_GET_FEATURE	0x03
#define GO_FEATURE_IMU_ENABLE	0x05
#define GO_LEFT_CONTROLLER	0x03
#define GO_RIGHT_CONTROLLER	0x04

static void go_test_cmd_init(void)
{
	memset(&go_cmd, 0, sizeof(go_cmd));
	init_completion(&go_cmd.done);
	spin_lock_init(&go_cmd.lock);
}

static void go_completion_success_test(struct kunit *test)
{
	struct command_report report = {
		.report_id = GO_INPUT_REPORT_ID,
		.id = GO_MCU_CONFIG_DATA,
		.cmd = 0xa0,
		.sub_cmd = 0x02,
		.device_type = GO_LEFT_CONTROLLER,
		.data = { 0x02, 0x01, 0x00, 0x00 },
	};
	struct hid_go_calibration_result result = {};

	KUNIT_ASSERT_EQ(test,
			hid_go_decode_calibration_completion(&report, &result), 0);
	KUNIT_EXPECT_EQ(test, result.device, (u8)GO_LEFT_CONTROLLER);
	KUNIT_EXPECT_EQ(test, result.module, (u8)0x02);
	KUNIT_EXPECT_EQ(test, result.status, (u8)CAL_STAT_SUCCESS);
	KUNIT_EXPECT_EQ(test, result.error, (u16)0x0000);
}

static void go_completion_failure_test(struct kunit *test)
{
	struct command_report report = {
		.report_id = GO_INPUT_REPORT_ID,
		.id = GO_MCU_CONFIG_DATA,
		.cmd = 0xa0,
		.sub_cmd = 0x02,
		.device_type = GO_RIGHT_CONTROLLER,
		.data = { 0x01, 0x00, 0x02, 0x00 },
	};
	struct hid_go_calibration_result result = {};

	KUNIT_ASSERT_EQ(test,
			hid_go_decode_calibration_completion(&report, &result), 0);
	KUNIT_EXPECT_EQ(test, result.device, (u8)GO_RIGHT_CONTROLLER);
	KUNIT_EXPECT_EQ(test, result.module, (u8)0x01);
	KUNIT_EXPECT_EQ(test, result.status, (u8)CAL_STAT_FAILURE);
	KUNIT_EXPECT_EQ(test, result.error, (u16)0x0002);
}

static void go_completion_reject_test(struct kunit *test)
{
	struct command_report report = {
		.report_id = GO_INPUT_REPORT_ID,
		.id = GO_MCU_CONFIG_DATA,
		.cmd = 0xa0,
		.sub_cmd = 0x02,
		.device_type = GO_LEFT_CONTROLLER,
		.data = { 0x02, 0x01, 0x00, 0x00 },
	};
	struct hid_go_calibration_result result = {};
	u8 *bytes = (u8 *)&report;
	size_t i;
	u8 saved;

	for (i = 0; i < 7; i++) {
		saved = bytes[i];
		bytes[i] = 0xff;
		KUNIT_EXPECT_EQ(test,
				hid_go_decode_calibration_completion(&report,
								     &result),
				-EINVAL);
		bytes[i] = saved;
	}
}

static void go_expect_cal_report(struct kunit *test, u8 command,
				 enum dev_type device, u8 index, u8 action)
{
	u8 expected[GO_PACKET_SIZE] = {
		GO_OUTPUT_REPORT_ID, MCU_CONFIG_DATA, command, index, device, action,
	};
	u8 packet[GO_PACKET_SIZE];
	int ret;

	ret = hid_go_build_output_report(packet, MCU_CONFIG_DATA, command, index,
					 device, &action, 1);
	KUNIT_ASSERT_EQ(test, ret, 0);
	KUNIT_EXPECT_MEMEQ(test, packet, expected, sizeof(packet));
}

static void go_output_report_test(struct kunit *test)
{
	static const struct {
		u8 command;
		u8 index;
	} routes[] = {
		{ SET_TRIGGER_CFG, 0x04 },
		{ SET_JOYSTICK_CFG, 0x04 },
		{ SET_GYRO_CFG, 0x06 },
	};
	static const enum dev_type devices[] = {
		LEFT_CONTROLLER,
		RIGHT_CONTROLLER,
	};
	static const u8 actions[] = { 0x01, 0x02 };
	static const u8 dpi[] = { 0x20, 0x03, 0x00, 0x00 };
	u8 expected[GO_PACKET_SIZE];
	u8 packet[GO_PACKET_SIZE];
	int ret;
	size_t action;
	size_t device;
	size_t route;

	for (route = 0; route < ARRAY_SIZE(routes); route++) {
		for (device = 0; device < ARRAY_SIZE(devices); device++) {
			for (action = 0; action < ARRAY_SIZE(actions); action++)
				go_expect_cal_report(test, routes[route].command,
						     devices[device], routes[route].index,
						     actions[action]);
		}
	}

	memset(expected, 0, sizeof(expected));
	expected[0] = GO_OUTPUT_REPORT_ID;
	expected[2] = SET_DPI_CFG;
	expected[3] = FPS_MODE_DPI;
	memcpy(expected + 4, dpi, sizeof(dpi));
	ret = hid_go_build_output_report(packet, MCU_CONFIG_DATA, SET_DPI_CFG,
					 FPS_MODE_DPI, UNSPECIFIED, dpi,
					 sizeof(dpi));
	KUNIT_ASSERT_EQ(test, ret, 0);
	KUNIT_EXPECT_MEMEQ(test, packet, expected, sizeof(packet));
}

static void go_reply_ownership_test(struct kunit *test)
{
	u8 reply[GO_PACKET_SIZE] = {
		GO_INPUT_REPORT_ID, GO_MCU_CONFIG_DATA, GO_CMD_GET_FEATURE,
		GO_FEATURE_IMU_ENABLE, GO_LEFT_CONTROLLER,
	};

	go_test_cmd_init();
	hid_go_cmd_arm(GO_CMD_GET_FEATURE, GO_FEATURE_IMU_ENABLE);

	reply[2]++;
	hid_go_cmd_consume(reply[2], reply[3], 0);
	KUNIT_EXPECT_FALSE(test, try_wait_for_completion(&go_cmd.done));
	reply[2]--;
	reply[3]++;
	hid_go_cmd_consume(reply[2], reply[3], 0);
	KUNIT_EXPECT_FALSE(test, try_wait_for_completion(&go_cmd.done));
	reply[3]--;

	hid_go_cmd_consume(reply[2], reply[3], -EIO);
	KUNIT_EXPECT_TRUE(test, try_wait_for_completion(&go_cmd.done));
	hid_go_cmd_consume(reply[2], reply[3], 0);
	KUNIT_EXPECT_EQ(test, hid_go_cmd_finish(1L), -EIO);
}

static void go_wait_result_test(struct kunit *test)
{
	u8 reply[GO_PACKET_SIZE] = {
		GO_INPUT_REPORT_ID, GO_MCU_CONFIG_DATA, GO_CMD_GET_FEATURE,
		GO_FEATURE_IMU_ENABLE, GO_LEFT_CONTROLLER,
	};

	go_test_cmd_init();
	hid_go_cmd_arm(GO_CMD_GET_FEATURE, GO_FEATURE_IMU_ENABLE);
	hid_go_cmd_consume(reply[2], reply[3], 0);
	KUNIT_EXPECT_EQ(test, hid_go_cmd_finish(-EIO), 0);

	hid_go_cmd_arm(GO_CMD_GET_FEATURE, GO_FEATURE_IMU_ENABLE);
	hid_go_cmd_consume(reply[2], reply[3], -EIO);
	KUNIT_EXPECT_EQ(test, hid_go_cmd_finish(0L), -EIO);

	hid_go_cmd_arm(GO_CMD_GET_FEATURE, GO_FEATURE_IMU_ENABLE);
	KUNIT_EXPECT_EQ(test, hid_go_cmd_finish(0L), -ETIMEDOUT);
	KUNIT_EXPECT_FALSE(test, go_cmd.pending);

	hid_go_cmd_arm(GO_CMD_GET_FEATURE, GO_FEATURE_IMU_ENABLE);
	KUNIT_EXPECT_EQ(test, hid_go_cmd_finish(-EINTR), -EINTR);
	KUNIT_EXPECT_FALSE(test, go_cmd.pending);
}

static struct kunit_case hid_go_test_cases[] = {
	KUNIT_CASE(go_completion_success_test),
	KUNIT_CASE(go_completion_failure_test),
	KUNIT_CASE(go_completion_reject_test),
	KUNIT_CASE(go_output_report_test),
	KUNIT_CASE(go_reply_ownership_test),
	KUNIT_CASE(go_wait_result_test),
	{}
};

static struct kunit_suite hid_go_test_suite = {
	.name = "hid-lenovo-go",
	.test_cases = hid_go_test_cases,
};

kunit_test_suite(hid_go_test_suite);

MODULE_DESCRIPTION("KUnit tests for the Lenovo Legion Go command transport");
MODULE_LICENSE("GPL");
