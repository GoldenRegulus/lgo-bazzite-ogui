// Binary entry point for `legion-go-ogui-controller`.
//
// This binary accepts exactly one command from the fixed allowlist and
// prints compact bounded JSON to stdout.  All privileged writes happen
// through the root-required mutation layer in the controller module.

#[path = "../controller.rs"]
mod controller;

use controller::{
    process_effective_uid_is_root, ControllerBackend, ControllerCommand, ControllerError,
};
use std::process::ExitCode;

fn main() -> ExitCode {
    let arguments: Vec<String> = std::env::args().skip(1).collect();
    let command = match ControllerCommand::parse_args(&arguments) {
        Ok(cmd) => cmd,
        Err(error) => {
            print_failure("unknown", error);
            return ExitCode::from(error.exit_code() as u8);
        }
    };

    let backend = ControllerBackend::production();
    let is_root = process_effective_uid_is_root();

    match command {
        ControllerCommand::Status => match backend.status() {
            Ok(status) => {
                println!(
                    concat!(
                        "{{\"ok\":true,\"command\":\"status\",",
                        "\"code\":\"ok\",\"message\":\"ok\",",
                        "\"name\":\"Legion Go Controller\",",
                        "\"swap_requested\":\"{}\",",
                        "\"left_joystick_status\":\"{}\",",
                        "\"left_joystick_error\":\"{}\",",
                        "\"left_joystick_index\":\"{}\",",
                        "\"left_trigger_status\":\"{}\",",
                        "\"left_trigger_error\":\"{}\",",
                        "\"left_trigger_index\":\"{}\",",
                        "\"left_gyro_status\":\"{}\",",
                        "\"left_gyro_error\":\"{}\",",
                        "\"left_gyro_index\":\"{}\",",
                        "\"right_joystick_status\":\"{}\",",
                        "\"right_joystick_error\":\"{}\",",
                        "\"right_joystick_index\":\"{}\",",
                        "\"right_trigger_status\":\"{}\",",
                        "\"right_trigger_error\":\"{}\",",
                        "\"right_trigger_index\":\"{}\",",
                        "\"right_gyro_status\":\"{}\",",
                        "\"right_gyro_error\":\"{}\",",
                        "\"right_gyro_index\":\"{}\"}}"
                    ),
                    status.swap_requested,
                    status.left_joystick_status,
                    status.left_joystick_error,
                    status.left_joystick_index,
                    status.left_trigger_status,
                    status.left_trigger_error,
                    status.left_trigger_index,
                    status.left_gyro_status,
                    status.left_gyro_error,
                    status.left_gyro_index,
                    status.right_joystick_status,
                    status.right_joystick_error,
                    status.right_joystick_index,
                    status.right_trigger_status,
                    status.right_trigger_error,
                    status.right_trigger_index,
                    status.right_gyro_status,
                    status.right_gyro_error,
                    status.right_gyro_index,
                );
                ExitCode::SUCCESS
            }
            Err(error) => {
                print_failure(command.name(), error);
                ExitCode::from(error.exit_code() as u8)
            }
        },

        ControllerCommand::SwapEnable => match backend.swap_enable(is_root) {
            Ok(()) => {
                println!(
                        "{{\"ok\":true,\"command\":\"swap-enable\",\"code\":\"ok\",\"message\":\"ok\"}}"
                    );
                ExitCode::SUCCESS
            }
            Err(error) => {
                print_failure(command.name(), error);
                ExitCode::from(error.exit_code() as u8)
            }
        },

        ControllerCommand::SwapDisable => match backend.swap_disable(is_root) {
            Ok(()) => {
                println!(
                        "{{\"ok\":true,\"command\":\"swap-disable\",\"code\":\"ok\",\"message\":\"ok\"}}"
                    );
                ExitCode::SUCCESS
            }
            Err(error) => {
                print_failure(command.name(), error);
                ExitCode::from(error.exit_code() as u8)
            }
        },

        // All calibration commands delegate to the calibrate helper.
        cmd => {
            if let Some((side, kind, action)) = cmd.calibration_triple() {
                match backend.calibrate(side, kind, action, is_root) {
                    Ok(()) => {
                        println!(
                            "{{\"ok\":true,\"command\":\"{}\",\"code\":\"ok\",\"message\":\"ok\"}}",
                            cmd.name()
                        );
                        ExitCode::SUCCESS
                    }
                    Err(error) => {
                        print_failure(cmd.name(), error);
                        ExitCode::from(error.exit_code() as u8)
                    }
                }
            } else {
                // Should never happen — all non-status/non-swap commands
                // are calibration commands.
                print_failure(cmd.name(), ControllerError::Usage);
                ExitCode::from(ControllerError::Usage.exit_code() as u8)
            }
        }
    }
}

fn print_failure(command: &str, error: ControllerError) {
    println!(
        "{{\"ok\":false,\"command\":\"{}\",\"code\":\"{}\",\"message\":\"{}\"}}",
        command,
        error.code(),
        error.message()
    );
}
