use legion_go_ogui_helper::{
    charge_mode_name, process_effective_uid_is_root, Backend, Command, Error,
};
use std::process::ExitCode;

fn main() -> ExitCode {
    let arguments: Vec<String> = std::env::args().skip(1).collect();
    let command = match Command::parse_args(&arguments) {
        Ok(command) => command,
        Err(error) => {
            print_failure("unknown", error);
            return ExitCode::from(error.exit_code() as u8);
        }
    };

    let backend = Backend::production();
    let result = match command {
        Command::Status => backend.status(),
        Command::Enable => backend.enable(process_effective_uid_is_root()),
        Command::Disable => backend.disable(process_effective_uid_is_root()),
    };

    match result {
        Ok(threshold) => {
            println!(
                "{{\"ok\":true,\"command\":\"{}\",\"mode\":\"{}\",\"threshold\":{},\"code\":\"ok\",\"message\":\"ok\"}}",
                command.name(),
                charge_mode_name(threshold),
                threshold
            );
            ExitCode::SUCCESS
        }
        Err(error) => {
            print_failure(command.name(), error);
            ExitCode::from(error.exit_code() as u8)
        }
    }
}

fn print_failure(command: &str, error: Error) {
    println!(
        "{{\"ok\":false,\"command\":\"{command}\",\"mode\":\"unknown\",\"threshold\":null,\"code\":\"{}\",\"message\":\"{}\"}}",
        error.code(),
        error.message()
    );
}
