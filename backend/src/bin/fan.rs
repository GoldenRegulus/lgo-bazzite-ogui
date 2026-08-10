#[path = "../fan.rs"]
mod fan;

use fan::{
    process_effective_uid_is_root, FanBackend, FanCommand, FanError, FanStatus, MAX_LEVEL,
    MIN_LEVEL,
};
use std::process::ExitCode;

fn main() -> ExitCode {
    let arguments: Vec<String> = std::env::args().skip(1).collect();
    let command = match FanCommand::parse_args(&arguments) {
        Ok(command) => command,
        Err(error) => {
            print_failure("unknown", error);
            return ExitCode::from(error.exit_code() as u8);
        }
    };

    let backend = FanBackend::production();
    let result = match &command {
        FanCommand::Status => backend.status(),
        FanCommand::SetFullSpeed(full_speed) => {
            backend.set_full_speed(process_effective_uid_is_root(), *full_speed)
        }
        FanCommand::SetCurve(curve) => backend.set_curve(process_effective_uid_is_root(), curve),
    };

    match result {
        Ok(status) => {
            print_success(command.name(), &status);
            ExitCode::SUCCESS
        }
        Err(error) => {
            print_failure(command.name(), error);
            ExitCode::from(error.exit_code() as u8)
        }
    }
}

fn print_success(command: &str, status: &FanStatus) {
    let curve = status
        .curve
        .iter()
        .map(u8::to_string)
        .collect::<Vec<_>>()
        .join(",");
    println!(
        "{{\"ok\":true,\"command\":\"{command}\",\"code\":\"ok\",\"message\":\"ok\",\"rpm\":{},\"full_speed\":{},\"curve_min\":{MIN_LEVEL},\"curve_max\":{MAX_LEVEL},\"curve\":[{curve}]}}",
        status.rpm, status.full_speed
    );
}

fn print_failure(command: &str, error: FanError) {
    println!(
        "{{\"ok\":false,\"command\":\"{command}\",\"code\":\"{}\",\"message\":\"{}\",\"rpm\":null,\"full_speed\":null,\"curve\":null}}",
        error.code(),
        error.message()
    );
}
