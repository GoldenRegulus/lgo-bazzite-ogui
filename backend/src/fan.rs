use std::fmt;
use std::fs;
use std::io::{self, Write};
use std::path::{Path, PathBuf};

const DMI_VENDOR: &str = "LENOVO";
const DMI_PRODUCT: &str = "83E1";
const DMI_VERSION: &str = "Legion Go 8APU1";
const HWMON_CLASS: &str = "sys/class/hwmon";
const HWMON_NAME: &str = "lenovo_wmi_other";
const FAN_RPM: &str = "fan1_input";
const WMI_DEVICES: &str = "sys/bus/wmi/devices";
const FAN_METHOD_GUID: &str = "92549549-4BDE-4F06-AC04-CE8BF898DBAA";
const OTHER_MODE_GUID: &str = "DC2A8805-3A8C-41BA-A6F7-092E0089CD3B";
const FAN_FULLSPEED: &str = "fan_fullspeed";
const FAN_CURVE: &str = "fan_curve";
pub const MIN_LEVEL: u8 = 0;
pub const MAX_LEVEL: u8 = 125;
const MINIMUM_LEVELS: [u8; 10] = [0, 0, 0, 0, 0, 0, 0, 79, 79, 100];
const HIGH_TEMPERATURE_EXCEPTIONS: [[u8; 10]; 2] = [
    [44, 48, 48, 48, 48, 48, 48, 48, 48, 48],
    [44, 48, 55, 60, 60, 60, 60, 60, 60, 60],
];

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum FanCommand {
    Status,
    SetFullSpeed(bool),
    SetCurve([u8; 10]),
}

impl FanCommand {
    pub fn parse_args(args: &[String]) -> Result<Self, FanError> {
        match args {
            [command] if command == "status" => Ok(Self::Status),
            [command, value] if command == "set-fullspeed" => parse_full_speed(value)
                .map(Self::SetFullSpeed)
                .map_err(|_| FanError::Usage),
            [command, values @ ..] if command == "set-curve" && values.len() == 10 => {
                let mut curve = [0_u8; 10];
                for (index, value) in values.iter().enumerate() {
                    curve[index] = parse_level(value).map_err(|_| FanError::Usage)?;
                }
                validate_curve(&curve)?;
                Ok(Self::SetCurve(curve))
            }
            _ => Err(FanError::Usage),
        }
    }

    pub fn name(&self) -> &'static str {
        match self {
            Self::Status => "status",
            Self::SetFullSpeed(_) => "set-fullspeed",
            Self::SetCurve(_) => "set-curve",
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum FanError {
    Usage,
    UnsupportedTarget,
    Unavailable,
    Privilege,
    Write,
    Readback,
}

impl FanError {
    pub fn code(self) -> &'static str {
        match self {
            Self::Usage => "usage",
            Self::UnsupportedTarget => "unsupported_target",
            Self::Unavailable => "fan_driver_unavailable",
            Self::Privilege => "privilege",
            Self::Write => "write",
            Self::Readback => "readback",
        }
    }

    pub fn message(self) -> &'static str {
        match self {
            Self::Usage => {
                "use status, set-fullspeed 0|1, or set-curve with ten valid firmware levels"
            }
            Self::UnsupportedTarget => "this helper supports original Lenovo Legion Go 83E1 only",
            Self::Unavailable => "the required Lenovo WMI fan interfaces are unavailable",
            Self::Privilege => "fan mutations require effective UID 0",
            Self::Write => "fan firmware write failed",
            Self::Readback => "fan state readback did not match the request",
        }
    }

    pub fn exit_code(self) -> i32 {
        match self {
            Self::Usage => 2,
            Self::UnsupportedTarget => 3,
            Self::Unavailable => 4,
            Self::Privilege => 5,
            Self::Write => 6,
            Self::Readback => 7,
        }
    }
}

impl fmt::Display for FanError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(self.message())
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct FanStatus {
    pub rpm: u32,
    pub full_speed: bool,
    pub curve: [u8; 10],
}

struct FanInterfaces {
    rpm: PathBuf,
    full_speed: PathBuf,
    curve: PathBuf,
}

pub struct FanBackend {
    root: PathBuf,
}

// Unprivileged, portable discovery and status layer.
impl FanBackend {
    pub fn production() -> Self {
        Self::for_root(Path::new("/"))
    }

    pub fn for_root(root: &Path) -> Self {
        Self {
            root: root.to_path_buf(),
        }
    }

    pub fn status(&self) -> Result<FanStatus, FanError> {
        self.validate_target()?;
        let interfaces = self.interfaces()?;
        self.read_status(&interfaces)
    }

    fn read_status(&self, interfaces: &FanInterfaces) -> Result<FanStatus, FanError> {
        let rpm =
            parse_rpm(&read_regular_trimmed(&interfaces.rpm).map_err(|_| FanError::Unavailable)?)?;
        let full_speed = parse_full_speed(
            &read_regular_trimmed(&interfaces.full_speed).map_err(|_| FanError::Unavailable)?,
        )?;
        let curve = parse_curve(
            &read_regular_trimmed(&interfaces.curve).map_err(|_| FanError::Unavailable)?,
        )?;
        Ok(FanStatus {
            rpm,
            full_speed,
            curve,
        })
    }

    pub fn validate_target(&self) -> Result<(), FanError> {
        let vendor = self.read_dmi("sys_vendor")?;
        let product = self.read_dmi("product_name")?;
        let version = self.read_dmi("product_version")?;
        if vendor == DMI_VENDOR && product == DMI_PRODUCT && version == DMI_VERSION {
            Ok(())
        } else {
            Err(FanError::UnsupportedTarget)
        }
    }

    fn read_dmi(&self, name: &str) -> Result<String, FanError> {
        read_regular_trimmed(&self.root.join("sys/class/dmi/id").join(name))
            .map_err(|_| FanError::UnsupportedTarget)
    }

    fn interfaces(&self) -> Result<FanInterfaces, FanError> {
        Ok(FanInterfaces {
            rpm: self.find_rpm_path()?,
            full_speed: self.wmi_attribute(OTHER_MODE_GUID, FAN_FULLSPEED)?,
            curve: self.wmi_attribute(FAN_METHOD_GUID, FAN_CURVE)?,
        })
    }

    fn find_rpm_path(&self) -> Result<PathBuf, FanError> {
        let entries =
            fs::read_dir(self.root.join(HWMON_CLASS)).map_err(|_| FanError::Unavailable)?;
        let mut matches = Vec::new();

        for entry in entries {
            let entry = entry.map_err(|_| FanError::Unavailable)?;
            let path = entry.path();
            let name = path.join("name");
            if !is_regular_file(&name) {
                continue;
            }
            if read_regular_trimmed(&name).map_err(|_| FanError::Unavailable)? != HWMON_NAME {
                continue;
            }
            let rpm = path.join(FAN_RPM);
            if !is_regular_file(&rpm) {
                return Err(FanError::Unavailable);
            }
            matches.push(rpm);
        }

        match matches.len() {
            1 => Ok(matches.remove(0)),
            _ => Err(FanError::Unavailable),
        }
    }

    fn wmi_attribute(&self, guid: &str, attribute: &str) -> Result<PathBuf, FanError> {
        let entries =
            fs::read_dir(self.root.join(WMI_DEVICES)).map_err(|_| FanError::Unavailable)?;
        let mut matches = Vec::new();

        for entry in entries {
            let entry = entry.map_err(|_| FanError::Unavailable)?;
            let name = entry.file_name();
            let Some(name) = name.to_str() else {
                continue;
            };
            if !is_wmi_instance(name, guid) {
                continue;
            }
            let directory = entry.path();
            if !is_expected_device_directory(&self.root, &directory, name) {
                return Err(FanError::Unavailable);
            }
            matches.push(directory);
        }

        if matches.len() != 1 {
            return Err(FanError::Unavailable);
        }
        let path = matches.remove(0).join(attribute);
        is_regular_file(&path)
            .then_some(path)
            .ok_or(FanError::Unavailable)
    }
}

// Root-required mutation layer. A native owner can port only this layer.
impl FanBackend {
    pub fn set_full_speed(&self, is_root: bool, full_speed: bool) -> Result<FanStatus, FanError> {
        if !is_root {
            return Err(FanError::Privilege);
        }
        self.validate_target()?;
        let interfaces = self.interfaces()?;
        let value = if full_speed { "1" } else { "0" };
        write_value(&interfaces.full_speed, value)?;
        let status = self.read_status(&interfaces)?;
        require_full_speed_readback(&status, full_speed)?;
        Ok(status)
    }

    pub fn set_curve(&self, is_root: bool, curve: &[u8; 10]) -> Result<FanStatus, FanError> {
        if !is_root {
            return Err(FanError::Privilege);
        }
        validate_curve(curve)?;
        self.validate_target()?;
        let interfaces = self.interfaces()?;
        let value = curve
            .iter()
            .map(u8::to_string)
            .collect::<Vec<_>>()
            .join(" ");
        write_value(&interfaces.curve, &value)?;
        let status = self.read_status(&interfaces)?;
        require_curve_readback(&status, curve)?;
        Ok(status)
    }
}

fn is_wmi_instance(name: &str, guid: &str) -> bool {
    name.strip_prefix(guid)
        .and_then(|suffix| suffix.strip_prefix('-'))
        .is_some_and(|instance| {
            !instance.is_empty() && instance.bytes().all(|byte| byte.is_ascii_digit())
        })
}

fn is_expected_device_directory(root: &Path, path: &Path, expected_name: &str) -> bool {
    let Ok(metadata) = fs::symlink_metadata(path) else {
        return false;
    };
    if metadata.file_type().is_dir() {
        return true;
    }
    if !metadata.file_type().is_symlink() {
        return false;
    }

    let Ok(target) = fs::canonicalize(path) else {
        return false;
    };
    let Ok(sys_devices) = fs::canonicalize(root.join("sys/devices")) else {
        return false;
    };
    target.starts_with(sys_devices) && target.file_name().is_some_and(|name| name == expected_name)
}

fn is_regular_file(path: &Path) -> bool {
    fs::symlink_metadata(path)
        .map(|metadata| metadata.file_type().is_file())
        .unwrap_or(false)
}

fn validate_curve(curve: &[u8; 10]) -> Result<(), FanError> {
    for index in 0..curve.len() {
        if curve[index] > MAX_LEVEL {
            return Err(FanError::Usage);
        }
        if index > 0 && curve[index] < curve[index - 1] {
            return Err(FanError::Usage);
        }
    }
    if HIGH_TEMPERATURE_EXCEPTIONS.contains(curve) {
        return Ok(());
    }
    for index in 0..curve.len() {
        if curve[index] < MINIMUM_LEVELS[index] {
            return Err(FanError::Usage);
        }
    }
    Ok(())
}

fn parse_rpm(text: &str) -> Result<u32, FanError> {
    parse_decimal(text).ok_or(FanError::Readback)
}

fn parse_level(text: &str) -> Result<u8, FanError> {
    parse_decimal(text)
        .and_then(|level| u8::try_from(level).ok())
        .ok_or(FanError::Readback)
}

fn parse_full_speed(text: &str) -> Result<bool, FanError> {
    match text {
        "0" => Ok(false),
        "1" => Ok(true),
        _ => Err(FanError::Readback),
    }
}

fn parse_curve(text: &str) -> Result<[u8; 10], FanError> {
    let values: Vec<&str> = text.split_whitespace().collect();
    if values.len() != 10 {
        return Err(FanError::Readback);
    }
    let mut curve = [0_u8; 10];
    for (index, value) in values.iter().enumerate() {
        curve[index] = parse_level(value)?;
    }
    validate_curve(&curve).map_err(|_| FanError::Readback)?;
    Ok(curve)
}

fn parse_decimal(text: &str) -> Option<u32> {
    (!text.is_empty() && text.bytes().all(|byte| byte.is_ascii_digit()))
        .then(|| text.parse().ok())
        .flatten()
}

fn require_full_speed_readback(status: &FanStatus, expected: bool) -> Result<(), FanError> {
    if status.full_speed == expected {
        Ok(())
    } else {
        Err(FanError::Readback)
    }
}

fn require_curve_readback(status: &FanStatus, expected: &[u8; 10]) -> Result<(), FanError> {
    if status.curve == *expected {
        Ok(())
    } else {
        Err(FanError::Readback)
    }
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

fn write_value(path: &Path, value: &str) -> Result<(), FanError> {
    if !is_regular_file(path) {
        return Err(FanError::Unavailable);
    }
    let mut file = fs::OpenOptions::new()
        .write(true)
        .truncate(true)
        .open(path)
        .map_err(|_| FanError::Write)?;
    let written = file.write(value.as_bytes()).map_err(|_| FanError::Write)?;
    if written == value.len() {
        Ok(())
    } else {
        Err(FanError::Write)
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

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::time::{SystemTime, UNIX_EPOCH};

    static NEXT_TEST_ROOT: AtomicUsize = AtomicUsize::new(0);

    struct TestRoot(PathBuf);

    impl TestRoot {
        fn new() -> Self {
            let sequence = NEXT_TEST_ROOT.fetch_add(1, Ordering::Relaxed);
            let path = std::env::temp_dir().join(format!(
                "legion-go-fan-{}-{}-{sequence}",
                std::process::id(),
                SystemTime::now()
                    .duration_since(UNIX_EPOCH)
                    .expect("system clock before Unix epoch")
                    .as_nanos()
            ));
            fs::create_dir(&path).expect("create temporary test root");
            let test = Self(path);
            test.write("sys/class/dmi/id/sys_vendor", "LENOVO\n");
            test.write("sys/class/dmi/id/product_name", "83E1\n");
            test.write("sys/class/dmi/id/product_version", "Legion Go 8APU1\n");
            test.add_hwmon("hwmon0", HWMON_NAME, Some("3250\n"));
            test.write_wmi(
                FAN_METHOD_GUID,
                FAN_CURVE,
                "44 48 55 60 71 79 87 87 100 100\n",
            );
            test.write_wmi(OTHER_MODE_GUID, FAN_FULLSPEED, "0\n");
            test
        }

        fn add_hwmon(&self, name: &str, device_name: &str, rpm: Option<&str>) {
            self.write(&format!("{HWMON_CLASS}/{name}/name"), device_name);
            if let Some(rpm) = rpm {
                self.write(&format!("{HWMON_CLASS}/{name}/{FAN_RPM}"), rpm);
            }
        }

        fn wmi_path(guid: &str, attribute: &str) -> String {
            format!("{WMI_DEVICES}/{guid}-0/{attribute}")
        }

        fn write_wmi(&self, guid: &str, attribute: &str, value: &str) {
            self.write(&Self::wmi_path(guid, attribute), value);
        }

        fn write(&self, relative: &str, value: &str) {
            let path = self.0.join(relative);
            fs::create_dir_all(path.parent().expect("test path parent"))
                .expect("create test directory");
            fs::write(path, value).expect("write test file");
        }

        fn read(&self, relative: &str) -> String {
            fs::read_to_string(self.0.join(relative)).expect("read test file")
        }

        fn backend(&self) -> FanBackend {
            FanBackend::for_root(&self.0)
        }
    }

    impl Drop for TestRoot {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }

    #[test]
    fn parser_accepts_only_the_raw_interface_shape() {
        assert_eq!(
            FanCommand::parse_args(&["status".into()]),
            Ok(FanCommand::Status)
        );
        assert_eq!(
            FanCommand::parse_args(&["set-fullspeed".into(), "0".into()]),
            Ok(FanCommand::SetFullSpeed(false))
        );
        assert_eq!(
            FanCommand::parse_args(&["set-fullspeed".into(), "1".into()]),
            Ok(FanCommand::SetFullSpeed(true))
        );
        let curve = "set-curve 44 48 55 60 71 79 87 87 100 100"
            .split_whitespace()
            .map(str::to_owned)
            .collect::<Vec<_>>();
        assert!(matches!(
            FanCommand::parse_args(&curve),
            Ok(FanCommand::SetCurve(_))
        ));
        for command in [
            "automatic",
            "quiet",
            "balanced",
            "performance",
            "custom",
            "full-speed",
        ] {
            assert_eq!(
                FanCommand::parse_args(&[command.into()]),
                Err(FanError::Usage)
            );
        }
        assert_eq!(
            FanCommand::parse_args(&["set-fullspeed".into(), "true".into()]),
            Err(FanError::Usage)
        );
        assert_eq!(
            FanCommand::parse_args(&["set-curve".into(), "44".into()]),
            Err(FanError::Usage)
        );
        let too_many_values = "set-curve 44 48 55 60 71 79 87 87 100 100 100"
            .split_whitespace()
            .map(str::to_owned)
            .collect::<Vec<_>>();
        assert_eq!(
            FanCommand::parse_args(&too_many_values),
            Err(FanError::Usage)
        );
    }

    #[test]
    fn curve_validation_requires_point_bounds_and_nondecreasing_order() {
        assert!(validate_curve(&[0, 0, 1, 2, 3, 4, 5, 79, 79, 100]).is_ok());
        assert!(validate_curve(&HIGH_TEMPERATURE_EXCEPTIONS[0]).is_ok());
        assert!(validate_curve(&HIGH_TEMPERATURE_EXCEPTIONS[1]).is_ok());
        assert!(validate_curve(&[44, 48, 48, 48, 48, 48, 48, 48, 48, 49]).is_err());
        assert!(validate_curve(&[0, 0, 1, 2, 3, 4, 5, 78, 79, 100]).is_err());
        assert!(validate_curve(&[0, 0, 1, 2, 3, 4, 5, 79, 99, 99]).is_err());
        assert!(validate_curve(&[0, 0, 1, 2, 3, 4, 80, 79, 100, 100]).is_err());
        assert!(validate_curve(&[0, 0, 1, 2, 3, 4, 5, 79, 100, 126]).is_err());
    }

    #[test]
    fn discovery_requires_each_fixed_owner_interface() {
        let paths = [
            format!("{HWMON_CLASS}/hwmon0/{FAN_RPM}"),
            TestRoot::wmi_path(FAN_METHOD_GUID, FAN_CURVE),
            TestRoot::wmi_path(OTHER_MODE_GUID, FAN_FULLSPEED),
        ];
        for path in paths {
            let root = TestRoot::new();
            fs::remove_file(root.0.join(path)).expect("remove owner attribute");
            assert_eq!(root.backend().status(), Err(FanError::Unavailable));
        }
    }

    #[test]
    fn wmi_discovery_requires_one_numeric_guid_instance() {
        assert!(is_wmi_instance(
            "92549549-4BDE-4F06-AC04-CE8BF898DBAA-16",
            FAN_METHOD_GUID
        ));
        for name in [
            FAN_METHOD_GUID,
            "92549549-4BDE-4F06-AC04-CE8BF898DBAA-",
            "92549549-4BDE-4F06-AC04-CE8BF898DBAA-x",
            "92549549-4BDE-4F06-AC04-CE8BF898DBA0-16",
        ] {
            assert!(!is_wmi_instance(name, FAN_METHOD_GUID));
        }

        let root = TestRoot::new();
        root.write(
            &format!("{WMI_DEVICES}/{FAN_METHOD_GUID}-1/{FAN_CURVE}"),
            "44 48 55 60 71 79 87 87 100 100\n",
        );
        assert_eq!(root.backend().status(), Err(FanError::Unavailable));
    }

    #[test]
    fn discovery_rejects_malformed_or_duplicate_hwmon_owners() {
        let root = TestRoot::new();
        root.write(&format!("{HWMON_CLASS}/hwmon0/name"), "wrong-owner\n");
        assert_eq!(root.backend().status(), Err(FanError::Unavailable));

        let root = TestRoot::new();
        root.add_hwmon("hwmon1", HWMON_NAME, Some("3200\n"));
        assert_eq!(root.backend().status(), Err(FanError::Unavailable));

        let root = TestRoot::new();
        root.add_hwmon("hwmon1", HWMON_NAME, None);
        assert_eq!(root.backend().status(), Err(FanError::Unavailable));
    }

    #[cfg(unix)]
    #[test]
    fn discovery_rejects_symlinked_owner_attributes() {
        use std::os::unix::fs::symlink;

        let root = TestRoot::new();
        let curve = root.0.join(TestRoot::wmi_path(FAN_METHOD_GUID, FAN_CURVE));
        fs::remove_file(&curve).expect("remove curve");
        symlink(root.0.join("outside"), &curve).expect("create curve symlink");
        assert_eq!(root.backend().status(), Err(FanError::Unavailable));
    }

    #[test]
    fn target_validation_requires_exact_dmi_values() {
        let root = TestRoot::new();
        assert_eq!(root.backend().validate_target(), Ok(()));
        root.write("sys/class/dmi/id/product_version", "Legion Go 8APU2\n");
        assert_eq!(
            root.backend().validate_target(),
            Err(FanError::UnsupportedTarget)
        );
    }

    #[test]
    fn mutations_require_root_before_any_write() {
        let root = TestRoot::new();
        let curve = [44, 48, 55, 60, 71, 79, 87, 87, 100, 100];
        let full_speed_path = TestRoot::wmi_path(OTHER_MODE_GUID, FAN_FULLSPEED);
        let curve_path = TestRoot::wmi_path(FAN_METHOD_GUID, FAN_CURVE);
        let original_full_speed = root.read(&full_speed_path);
        let original_curve = root.read(&curve_path);

        assert_eq!(
            root.backend().set_full_speed(false, true),
            Err(FanError::Privilege)
        );
        assert_eq!(
            root.backend().set_curve(false, &curve),
            Err(FanError::Privilege)
        );
        assert_eq!(root.read(&full_speed_path), original_full_speed);
        assert_eq!(root.read(&curve_path), original_curve);
    }

    #[test]
    fn writes_use_separate_owner_paths_and_confirm_readback() {
        let root = TestRoot::new();
        let status = root
            .backend()
            .set_full_speed(true, true)
            .expect("set full speed");
        assert_eq!(status.rpm, 3250);
        assert!(status.full_speed);
        assert_eq!(status.curve, [44, 48, 55, 60, 71, 79, 87, 87, 100, 100]);
        assert_eq!(
            root.read(&TestRoot::wmi_path(OTHER_MODE_GUID, FAN_FULLSPEED)),
            "1"
        );

        let curve = [44, 44, 55, 60, 71, 79, 87, 87, 100, 125];
        let status = root.backend().set_curve(true, &curve).expect("set curve");
        assert_eq!(status.curve, curve);
        assert_eq!(
            root.read(&TestRoot::wmi_path(FAN_METHOD_GUID, FAN_CURVE)),
            "44 44 55 60 71 79 87 87 100 125"
        );
        assert_eq!(
            root.read(&TestRoot::wmi_path(OTHER_MODE_GUID, FAN_FULLSPEED)),
            "1"
        );
    }

    #[test]
    fn readback_rejects_malformed_and_mismatched_values() {
        let root = TestRoot::new();
        root.write_wmi(OTHER_MODE_GUID, FAN_FULLSPEED, "2\n");
        assert_eq!(root.backend().status(), Err(FanError::Readback));
        root.write_wmi(OTHER_MODE_GUID, FAN_FULLSPEED, "0\n");
        root.write_wmi(FAN_METHOD_GUID, FAN_CURVE, "44 48 55\n");
        assert_eq!(root.backend().status(), Err(FanError::Readback));

        let mismatch = FanStatus {
            rpm: 3250,
            full_speed: false,
            curve: [44, 48, 55, 60, 71, 79, 87, 87, 100, 100],
        };
        assert_eq!(
            require_full_speed_readback(&mismatch, true),
            Err(FanError::Readback)
        );
        assert_eq!(
            require_curve_readback(&mismatch, &[44, 48, 55, 60, 71, 79, 87, 87, 100, 101]),
            Err(FanError::Readback)
        );
    }
}
