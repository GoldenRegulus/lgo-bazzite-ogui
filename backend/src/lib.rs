use std::fmt;
use std::fs;
use std::io::{self, Write};
use std::path::{Path, PathBuf};

const DMI_VENDOR: &str = "LENOVO";
const DMI_PRODUCT: &str = "83E1";
const DMI_VERSION: &str = "Legion Go 8APU1";
const BATTERY_TYPE: &str = "Battery";
const CHARGE_TYPES_FILE: &str = "charge_types";
const STANDARD: &str = "Standard";
const LONG_LIFE: &str = "Long_Life";

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Command {
    Status,
    Enable,
    Disable,
}

impl Command {
    pub fn parse_args(args: &[String]) -> Result<Self, Error> {
        if args.len() != 1 {
            return Err(Error::Usage);
        }

        match args[0].as_str() {
            "status" => Ok(Self::Status),
            "enable" => Ok(Self::Enable),
            "disable" => Ok(Self::Disable),
            _ => Err(Error::Usage),
        }
    }

    pub fn name(self) -> &'static str {
        match self {
            Self::Status => "status",
            Self::Enable => "enable",
            Self::Disable => "disable",
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Error {
    Usage,
    UnsupportedTarget,
    Battery,
    ChargeTypes,
    Privilege,
    Write,
}

impl Error {
    pub fn code(self) -> &'static str {
        match self {
            Self::Usage => "usage",
            Self::UnsupportedTarget => "unsupported_target",
            Self::Battery => "battery",
            Self::ChargeTypes => "charge_types",
            Self::Privilege => "privilege",
            Self::Write => "write",
        }
    }

    pub fn message(self) -> &'static str {
        match self {
            Self::Usage => "use exactly one command: status, enable, or disable",
            Self::UnsupportedTarget => "this helper supports Lenovo Legion Go model 83E1 only",
            Self::Battery => "battery discovery did not find exactly one charge-types battery",
            Self::ChargeTypes => "battery charge types are missing or invalid",
            Self::Privilege => "enable and disable require effective UID 0",
            Self::Write => "battery charge type write or readback failed",
        }
    }

    pub fn exit_code(self) -> i32 {
        match self {
            Self::Usage => 2,
            Self::UnsupportedTarget => 3,
            Self::Battery => 4,
            Self::ChargeTypes => 5,
            Self::Privilege => 6,
            Self::Write => 7,
        }
    }
}

impl fmt::Display for Error {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(self.message())
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum ChargeMode {
    Standard,
    LongLife,
}

impl ChargeMode {
    fn attribute_value(self) -> &'static str {
        match self {
            Self::Standard => STANDARD,
            Self::LongLife => LONG_LIFE,
        }
    }

    fn status_value(self) -> u8 {
        match self {
            Self::Standard => 100,
            Self::LongLife => 80,
        }
    }
}

/// A filesystem root. Production uses `/`; tests can use a private temporary root.
#[derive(Clone, Debug)]
pub struct Backend {
    root: PathBuf,
}

// Unprivileged, portable discovery and status layer.
impl Backend {
    pub fn production() -> Self {
        Self::for_root(Path::new("/"))
    }

    pub fn for_root(root: &Path) -> Self {
        Self {
            root: root.to_path_buf(),
        }
    }

    /// Read and validate the global charge mode. This method does not need root.
    pub fn status(&self) -> Result<u8, Error> {
        self.validate_target()?;
        let battery = self.find_battery()?;
        Ok(self.read_charge_mode(&battery)?.status_value())
    }

    pub fn validate_target(&self) -> Result<(), Error> {
        let vendor = self
            .read_trimmed("sys/class/dmi/id/sys_vendor")
            .map_err(|_| Error::UnsupportedTarget)?;
        let product = self
            .read_trimmed("sys/class/dmi/id/product_name")
            .map_err(|_| Error::UnsupportedTarget)?;
        let version = self
            .read_trimmed("sys/class/dmi/id/product_version")
            .map_err(|_| Error::UnsupportedTarget)?;

        if vendor == DMI_VENDOR && product == DMI_PRODUCT && version == DMI_VERSION {
            Ok(())
        } else {
            Err(Error::UnsupportedTarget)
        }
    }

    pub fn find_battery(&self) -> Result<PathBuf, Error> {
        let supplies = self.root.join("sys/class/power_supply");
        let entries = fs::read_dir(supplies).map_err(|_| Error::Battery)?;
        let mut batteries = Vec::new();

        for entry in entries {
            let entry = entry.map_err(|_| Error::Battery)?;
            let path = entry.path();
            let type_path = path.join("type");
            let charge_types = path.join(CHARGE_TYPES_FILE);
            if !is_regular_file(&type_path) || !is_regular_file(&charge_types) {
                continue;
            }
            let power_type = read_regular_trimmed(&type_path).map_err(|_| Error::Battery)?;
            if power_type == BATTERY_TYPE {
                batteries.push(path);
            }
        }

        match batteries.len() {
            1 => Ok(batteries.remove(0)),
            _ => Err(Error::Battery),
        }
    }

    fn read_charge_mode(&self, battery: &Path) -> Result<ChargeMode, Error> {
        let text = read_regular_trimmed(&battery.join(CHARGE_TYPES_FILE))
            .map_err(|_| Error::ChargeTypes)?;
        parse_charge_types(&text).ok_or(Error::ChargeTypes)
    }

    fn read_trimmed(&self, relative_path: &str) -> io::Result<String> {
        read_regular_trimmed(&self.root.join(relative_path))
    }
}

// Root-required mutation layer. A native owner can port only this layer.
impl Backend {
    /// Enable fixed 80% Long Life mode. This method needs effective UID 0.
    pub fn enable(&self, effective_uid_is_root: bool) -> Result<u8, Error> {
        self.set_charge_mode_as_root(effective_uid_is_root, ChargeMode::LongLife)
    }

    /// Enable fixed 100% Standard mode. This method needs effective UID 0.
    pub fn disable(&self, effective_uid_is_root: bool) -> Result<u8, Error> {
        self.set_charge_mode_as_root(effective_uid_is_root, ChargeMode::Standard)
    }

    fn set_charge_mode_as_root(
        &self,
        effective_uid_is_root: bool,
        expected: ChargeMode,
    ) -> Result<u8, Error> {
        self.validate_target()?;
        let battery = self.find_battery()?;
        if !effective_uid_is_root {
            return Err(Error::Privilege);
        }
        self.read_charge_mode(&battery)?;
        self.write_and_verify(&battery, expected)?;
        Ok(expected.status_value())
    }

    fn write_and_verify(&self, battery: &Path, expected: ChargeMode) -> Result<(), Error> {
        let path = battery.join(CHARGE_TYPES_FILE);
        write_charge_type(&path, expected.attribute_value())?;
        verify_readback(&path, expected).map_err(|_| Error::Write)
    }
}

#[cfg(unix)]
unsafe extern "C" {
    fn geteuid() -> u32;
}

#[cfg(unix)]
pub fn process_effective_uid_is_root() -> bool {
    // `geteuid` has no failure result on supported Unix systems.
    unsafe { geteuid() == 0 }
}

#[cfg(not(unix))]
pub fn process_effective_uid_is_root() -> bool {
    false
}

pub fn charge_mode_name(status: u8) -> &'static str {
    match status {
        80 => "long-life",
        100 => "standard",
        _ => "unknown",
    }
}

fn parse_charge_types(text: &str) -> Option<ChargeMode> {
    let mut standard_count = 0;
    let mut long_life_count = 0;
    let mut active = None;

    for token in text.split_whitespace() {
        let (value, is_active) = if token.starts_with('[') || token.ends_with(']') {
            if !(token.starts_with('[') && token.ends_with(']')) || token.len() < 3 {
                return None;
            }
            (&token[1..token.len() - 1], true)
        } else {
            (token, false)
        };
        let mode = match value {
            STANDARD => {
                standard_count += 1;
                ChargeMode::Standard
            }
            LONG_LIFE => {
                long_life_count += 1;
                ChargeMode::LongLife
            }
            _ => return None,
        };
        if is_active && active.replace(mode).is_some() {
            return None;
        }
    }

    (standard_count == 1 && long_life_count == 1)
        .then_some(active)
        .flatten()
}

fn write_charge_type(path: &Path, value: &str) -> Result<(), Error> {
    if !is_regular_file(path) {
        return Err(Error::Write);
    }
    let mut charge_types = fs::OpenOptions::new()
        .write(true)
        .truncate(true)
        .open(path)
        .map_err(|_| Error::Write)?;
    charge_types
        .write_all(value.as_bytes())
        .map_err(|_| Error::Write)
}

fn verify_readback(path: &Path, expected: ChargeMode) -> Result<(), Error> {
    let text = read_regular_trimmed(path).map_err(|_| Error::Write)?;
    if parse_charge_types(&text) == Some(expected) {
        Ok(())
    } else {
        Err(Error::Write)
    }
}

fn is_regular_file(path: &Path) -> bool {
    fs::symlink_metadata(path)
        .map(|metadata| metadata.file_type().is_file())
        .unwrap_or(false)
}

fn read_regular_trimmed(path: &Path) -> io::Result<String> {
    if !is_regular_file(path) {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "path is not a regular file",
        ));
    }
    Ok(fs::read_to_string(path)?.trim().to_owned())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::time::{SystemTime, UNIX_EPOCH};

    static NEXT_TEST_ROOT: AtomicUsize = AtomicUsize::new(0);

    struct TestRoot {
        path: PathBuf,
    }

    impl TestRoot {
        fn new() -> Self {
            let sequence = NEXT_TEST_ROOT.fetch_add(1, Ordering::Relaxed);
            let nanos = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .expect("system clock before Unix epoch")
                .as_nanos();
            let path = std::env::temp_dir().join(format!(
                "legion-go-ogui-helper-test-{}-{nanos}-{sequence}",
                std::process::id()
            ));
            fs::create_dir(&path).expect("create temporary test root");
            Self { path }
        }

        fn backend(&self) -> Backend {
            Backend::for_root(&self.path)
        }

        fn write(&self, relative: &str, content: &str) {
            let path = self.path.join(relative);
            fs::create_dir_all(path.parent().expect("test path parent"))
                .expect("create test directory");
            fs::write(path, content).expect("write test file");
        }

        fn add_supply(&self, name: &str, power_type: &str, charge_types: Option<&str>) {
            self.write(&format!("sys/class/power_supply/{name}/type"), power_type);
            if let Some(charge_types) = charge_types {
                self.write(
                    &format!("sys/class/power_supply/{name}/{CHARGE_TYPES_FILE}"),
                    charge_types,
                );
            }
        }

        fn supported_target(&self) {
            self.write("sys/class/dmi/id/sys_vendor", " LENOVO\n");
            self.write("sys/class/dmi/id/product_name", "83E1 \n");
            self.write("sys/class/dmi/id/product_version", "Legion Go 8APU1\n");
        }
    }

    impl Drop for TestRoot {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.path);
        }
    }

    #[test]
    fn command_parser_accepts_only_one_known_command() {
        assert_eq!(
            Command::parse_args(&["status".to_owned()]),
            Ok(Command::Status)
        );
        assert_eq!(Command::parse_args(&[]), Err(Error::Usage));
        assert_eq!(
            Command::parse_args(&["enable".to_owned(), "extra".to_owned()]),
            Err(Error::Usage)
        );
    }

    #[test]
    fn target_validation_requires_exact_trimmed_values() {
        let root = TestRoot::new();
        root.supported_target();
        assert_eq!(root.backend().validate_target(), Ok(()));
        root.write("sys/class/dmi/id/product_name", "83E2\n");
        assert_eq!(
            root.backend().validate_target(),
            Err(Error::UnsupportedTarget)
        );
        root.write("sys/class/dmi/id/product_name", "83E1\n");
        root.write("sys/class/dmi/id/product_version", "Legion Go 8APU2\n");
        assert_eq!(
            root.backend().validate_target(),
            Err(Error::UnsupportedTarget)
        );
    }

    #[test]
    fn battery_discovery_requires_one_regular_charge_types_battery() {
        let root = TestRoot::new();
        root.add_supply("AC", "Mains\n", None);
        root.add_supply("BAT0", "Battery\n", Some("[Long_Life] Standard\n"));
        assert!(root.backend().find_battery().is_ok());
        root.add_supply("CONTROLLER", "Battery\n", None);
        assert!(root.backend().find_battery().is_ok());
        root.add_supply("BAT1", "Battery\n", Some("[Standard] Long_Life\n"));
        assert_eq!(root.backend().find_battery(), Err(Error::Battery));
    }

    #[test]
    fn battery_discovery_rejects_missing_or_non_regular_charge_types() {
        let root = TestRoot::new();
        root.add_supply("BAT0", "Battery\n", None);
        assert_eq!(root.backend().find_battery(), Err(Error::Battery));
        let attribute = root
            .path
            .join("sys/class/power_supply/BAT0")
            .join(CHARGE_TYPES_FILE);
        fs::create_dir(&attribute).expect("replace missing attribute with directory");
        assert_eq!(root.backend().find_battery(), Err(Error::Battery));
    }

    #[test]
    fn charge_types_require_one_supported_bracketed_active_value() {
        assert_eq!(
            parse_charge_types("[Standard] Long_Life"),
            Some(ChargeMode::Standard)
        );
        assert_eq!(
            parse_charge_types("Standard [Long_Life]"),
            Some(ChargeMode::LongLife)
        );
        for value in [
            "Standard Long_Life",
            "[Standard] [Long_Life]",
            "[Standard] Standard Long_Life",
            "[Standard] Long_Life Other",
            "[Standard Long_Life]",
        ] {
            assert_eq!(parse_charge_types(value), None, "{value}");
        }
    }

    #[test]
    fn status_maps_supported_charge_types_to_stable_values() {
        let root = TestRoot::new();
        root.supported_target();
        root.add_supply("BAT0", "Battery\n", Some("Standard [Long_Life]\n"));
        assert_eq!(root.backend().status(), Ok(80));
        root.write(
            "sys/class/power_supply/BAT0/charge_types",
            "[Standard] Long_Life\n",
        );
        assert_eq!(root.backend().status(), Ok(100));
        root.write(
            "sys/class/power_supply/BAT0/charge_types",
            "Standard Long_Life\n",
        );
        assert_eq!(root.backend().status(), Err(Error::ChargeTypes));
    }

    #[test]
    fn charge_modes_have_stable_status_values() {
        assert_eq!(charge_mode_name(80), "long-life");
        assert_eq!(charge_mode_name(100), "standard");
        assert_eq!(charge_mode_name(90), "unknown");
    }

    #[test]
    fn mutations_require_root_and_write_exact_charge_type_values() {
        let root = TestRoot::new();
        root.supported_target();
        root.add_supply("BAT0", "Battery\n", Some("[Standard] Long_Life\n"));
        assert_eq!(root.backend().enable(false), Err(Error::Privilege));

        let path = root.path.join("sys/class/power_supply/BAT0/charge_types");
        write_charge_type(&path, LONG_LIFE).expect("write Long Life");
        assert_eq!(fs::read_to_string(&path).expect("read write"), LONG_LIFE);
        root.write(
            "sys/class/power_supply/BAT0/charge_types",
            "Standard [Long_Life]\n",
        );
        assert_eq!(verify_readback(&path, ChargeMode::LongLife), Ok(()));

        write_charge_type(&path, STANDARD).expect("write Standard");
        assert_eq!(fs::read_to_string(&path).expect("read write"), STANDARD);
        root.write(
            "sys/class/power_supply/BAT0/charge_types",
            "[Standard] Long_Life\n",
        );
        assert_eq!(verify_readback(&path, ChargeMode::Standard), Ok(()));
    }

    #[test]
    fn readback_rejects_malformed_and_mismatched_active_values() {
        let root = TestRoot::new();
        let path = root.path.join("charge_types");
        fs::write(&path, "[Standard] Long_Life\n").expect("write supported state");
        assert_eq!(verify_readback(&path, ChargeMode::Standard), Ok(()));
        assert_eq!(
            verify_readback(&path, ChargeMode::LongLife),
            Err(Error::Write)
        );
        fs::write(&path, "Standard Long_Life\n").expect("write malformed state");
        assert_eq!(
            verify_readback(&path, ChargeMode::Standard),
            Err(Error::Write)
        );
    }
}
