use std::fmt;
use std::fs::{self, File};
use std::io::{self, Write};
use std::path::{Path, PathBuf};

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const DMI_VENDOR: &str = "LENOVO";
const DMI_PRODUCT: &str = "83E1";
const SUPPORTED_HID_IDS: [&str; 4] = [
    "HID_ID=0003:000017EF:000061EB",
    "HID_ID=0003:000017EF:000061EC",
    "HID_ID=0003:000017EF:000061ED",
    "HID_ID=0003:000017EF:000061EE",
];
const STATE_FILE_NAME: &str = "controller-swap-state";

const SWAP_ENABLE_PAYLOAD: [u8; 7] = [0x05, 0x06, 0x69, 0x04, 0x01, 0x02, 0x01];
const SWAP_DISABLE_PAYLOAD: [u8; 7] = [0x05, 0x06, 0x69, 0x04, 0x01, 0x01, 0x01];

// ---------------------------------------------------------------------------
// Side, calibration kind, and calibration action helpers
// ---------------------------------------------------------------------------

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum Side {
    Left,
    Right,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum CalKind {
    Joystick,
    Trigger,
    Gyro,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum CalAction {
    Start,
    Stop,
}

impl Side {
    fn dir_name(self) -> &'static str {
        match self {
            Side::Left => "left_handle",
            Side::Right => "right_handle",
        }
    }
}

impl CalKind {
    fn name(self) -> &'static str {
        match self {
            CalKind::Joystick => "joystick",
            CalKind::Trigger => "trigger",
            CalKind::Gyro => "gyro",
        }
    }

    fn calibrate_attr(self) -> String {
        format!("calibrate_{}", self.name())
    }

    fn status_attr(self) -> String {
        format!("calibrate_{}_status", self.name())
    }

    fn index_attr(self) -> String {
        format!("calibrate_{}_index", self.name())
    }

    fn error_attr(self) -> String {
        format!("calibrate_{}_error", self.name())
    }
}

// ---------------------------------------------------------------------------
// ControllerCommand — the fixed allowlist
// ---------------------------------------------------------------------------

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ControllerCommand {
    Status,
    SwapEnable,
    SwapDisable,
    CalibrateLeftJoystickStart,
    CalibrateLeftJoystickStop,
    CalibrateLeftTriggerStart,
    CalibrateLeftTriggerStop,
    CalibrateLeftGyroStart,
    CalibrateLeftGyroStop,
    CalibrateRightJoystickStart,
    CalibrateRightJoystickStop,
    CalibrateRightTriggerStart,
    CalibrateRightTriggerStop,
    CalibrateRightGyroStart,
    CalibrateRightGyroStop,
}

impl ControllerCommand {
    pub fn parse_args(args: &[String]) -> Result<Self, ControllerError> {
        if args.len() != 1 {
            return Err(ControllerError::Usage);
        }
        match args[0].as_str() {
            "status" => Ok(Self::Status),
            "swap-enable" => Ok(Self::SwapEnable),
            "swap-disable" => Ok(Self::SwapDisable),
            "calibrate-left-joystick-start" => Ok(Self::CalibrateLeftJoystickStart),
            "calibrate-left-joystick-stop" => Ok(Self::CalibrateLeftJoystickStop),
            "calibrate-left-trigger-start" => Ok(Self::CalibrateLeftTriggerStart),
            "calibrate-left-trigger-stop" => Ok(Self::CalibrateLeftTriggerStop),
            "calibrate-left-gyro-start" => Ok(Self::CalibrateLeftGyroStart),
            "calibrate-left-gyro-stop" => Ok(Self::CalibrateLeftGyroStop),
            "calibrate-right-joystick-start" => Ok(Self::CalibrateRightJoystickStart),
            "calibrate-right-joystick-stop" => Ok(Self::CalibrateRightJoystickStop),
            "calibrate-right-trigger-start" => Ok(Self::CalibrateRightTriggerStart),
            "calibrate-right-trigger-stop" => Ok(Self::CalibrateRightTriggerStop),
            "calibrate-right-gyro-start" => Ok(Self::CalibrateRightGyroStart),
            "calibrate-right-gyro-stop" => Ok(Self::CalibrateRightGyroStop),
            _ => Err(ControllerError::Usage),
        }
    }

    pub fn name(self) -> &'static str {
        match self {
            Self::Status => "status",
            Self::SwapEnable => "swap-enable",
            Self::SwapDisable => "swap-disable",
            Self::CalibrateLeftJoystickStart => "calibrate-left-joystick-start",
            Self::CalibrateLeftJoystickStop => "calibrate-left-joystick-stop",
            Self::CalibrateLeftTriggerStart => "calibrate-left-trigger-start",
            Self::CalibrateLeftTriggerStop => "calibrate-left-trigger-stop",
            Self::CalibrateLeftGyroStart => "calibrate-left-gyro-start",
            Self::CalibrateLeftGyroStop => "calibrate-left-gyro-stop",
            Self::CalibrateRightJoystickStart => "calibrate-right-joystick-start",
            Self::CalibrateRightJoystickStop => "calibrate-right-joystick-stop",
            Self::CalibrateRightTriggerStart => "calibrate-right-trigger-start",
            Self::CalibrateRightTriggerStop => "calibrate-right-trigger-stop",
            Self::CalibrateRightGyroStart => "calibrate-right-gyro-start",
            Self::CalibrateRightGyroStop => "calibrate-right-gyro-stop",
        }
    }

    /// Extract (side, kind, action) from a calibration command, or None for
    /// non-calibration commands.
    pub fn calibration_triple(self) -> Option<(Side, CalKind, CalAction)> {
        match self {
            Self::CalibrateLeftJoystickStart => {
                Some((Side::Left, CalKind::Joystick, CalAction::Start))
            }
            Self::CalibrateLeftJoystickStop => {
                Some((Side::Left, CalKind::Joystick, CalAction::Stop))
            }
            Self::CalibrateLeftTriggerStart => {
                Some((Side::Left, CalKind::Trigger, CalAction::Start))
            }
            Self::CalibrateLeftTriggerStop => Some((Side::Left, CalKind::Trigger, CalAction::Stop)),
            Self::CalibrateLeftGyroStart => Some((Side::Left, CalKind::Gyro, CalAction::Start)),
            Self::CalibrateLeftGyroStop => Some((Side::Left, CalKind::Gyro, CalAction::Stop)),
            Self::CalibrateRightJoystickStart => {
                Some((Side::Right, CalKind::Joystick, CalAction::Start))
            }
            Self::CalibrateRightJoystickStop => {
                Some((Side::Right, CalKind::Joystick, CalAction::Stop))
            }
            Self::CalibrateRightTriggerStart => {
                Some((Side::Right, CalKind::Trigger, CalAction::Start))
            }
            Self::CalibrateRightTriggerStop => {
                Some((Side::Right, CalKind::Trigger, CalAction::Stop))
            }
            Self::CalibrateRightGyroStart => Some((Side::Right, CalKind::Gyro, CalAction::Start)),
            Self::CalibrateRightGyroStop => Some((Side::Right, CalKind::Gyro, CalAction::Stop)),
            _ => None,
        }
    }
}

// ---------------------------------------------------------------------------
// ControllerError
// ---------------------------------------------------------------------------

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ControllerError {
    Usage,
    UnsupportedTarget,
    Discovery,
    Calibration,
    Privilege,
    Write,
    State,
}

impl ControllerError {
    pub fn code(self) -> &'static str {
        match self {
            Self::Usage => "usage",
            Self::UnsupportedTarget => "unsupported_target",
            Self::Discovery => "discovery",
            Self::Calibration => "calibration",
            Self::Privilege => "privilege",
            Self::Write => "write",
            Self::State => "state",
        }
    }

    pub fn message(self) -> &'static str {
        match self {
            Self::Usage => "use exactly one command from the allowlist",
            Self::UnsupportedTarget => "this helper supports Lenovo Legion Go model 83E1 only",
            Self::Discovery => "controller discovery did not find exactly one Legion Go controller",
            Self::Calibration => "calibration attribute missing or unreadable",
            Self::Privilege => "controller mutations require effective UID 0",
            Self::Write => "controller hidraw or calibration write failed",
            Self::State => "controller swap-state file read or write failed",
        }
    }

    pub fn exit_code(self) -> i32 {
        match self {
            Self::Usage => 2,
            Self::UnsupportedTarget => 3,
            Self::Discovery => 4,
            Self::Calibration => 5,
            Self::Privilege => 6,
            Self::Write => 7,
            Self::State => 8,
        }
    }
}

impl fmt::Display for ControllerError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(self.message())
    }
}

// ---------------------------------------------------------------------------
// ControllerStatus — structured output for the status command
// ---------------------------------------------------------------------------

#[derive(Clone, Debug)]
pub struct ControllerStatus {
    pub swap_requested: String,
    pub left_joystick_status: String,
    pub left_joystick_error: String,
    pub left_joystick_index: String,
    pub left_trigger_status: String,
    pub left_trigger_error: String,
    pub left_trigger_index: String,
    pub left_gyro_status: String,
    pub left_gyro_error: String,
    pub left_gyro_index: String,
    pub right_joystick_status: String,
    pub right_joystick_error: String,
    pub right_joystick_index: String,
    pub right_trigger_status: String,
    pub right_trigger_error: String,
    pub right_trigger_index: String,
    pub right_gyro_status: String,
    pub right_gyro_error: String,
    pub right_gyro_index: String,
}

impl ControllerStatus {
    fn unknown() -> Self {
        let u = "unknown".to_owned();
        Self {
            swap_requested: u.clone(),
            left_joystick_status: u.clone(),
            left_joystick_error: u.clone(),
            left_joystick_index: u.clone(),
            left_trigger_status: u.clone(),
            left_trigger_error: u.clone(),
            left_trigger_index: u.clone(),
            left_gyro_status: u.clone(),
            left_gyro_error: u.clone(),
            left_gyro_index: u.clone(),
            right_joystick_status: u.clone(),
            right_joystick_error: u.clone(),
            right_joystick_index: u.clone(),
            right_trigger_status: u.clone(),
            right_trigger_error: u.clone(),
            right_trigger_index: u.clone(),
            right_gyro_status: u.clone(),
            right_gyro_error: u.clone(),
            right_gyro_index: u,
        }
    }
}

// ---------------------------------------------------------------------------
// Calibration attribute kind
// ---------------------------------------------------------------------------

enum AttrKind {
    Status,
    Error,
    Index,
}

// ---------------------------------------------------------------------------
// Type alias for the optional test-level hidraw writer
// ---------------------------------------------------------------------------

type HidrawWriterFn = Box<dyn Fn(&Path, &[u8]) -> io::Result<()>>;

// ---------------------------------------------------------------------------
// ControllerBackend
// ---------------------------------------------------------------------------

pub struct ControllerBackend {
    root: PathBuf,
    state_root: PathBuf,
    test_hidraw_writer: Option<HidrawWriterFn>,
}

// -- constructors -----------------------------------------------------------

impl ControllerBackend {
    /// Production backend: sysfs at `/`, state at `/var/lib/legion-go-ogui`.
    pub fn production() -> Self {
        Self {
            root: PathBuf::from("/"),
            state_root: PathBuf::from("/var/lib/legion-go-ogui"),
            test_hidraw_writer: None,
        }
    }

    /// Test backend with explicit roots.
    pub fn for_roots(root: &Path, state_root: &Path) -> Self {
        Self {
            root: root.to_path_buf(),
            state_root: state_root.to_path_buf(),
            test_hidraw_writer: None,
        }
    }

    /// Inject a test hidraw writer (test builds only).
    #[cfg(test)]
    pub fn with_hidraw_writer<F>(mut self, writer: F) -> Self
    where
        F: Fn(&Path, &[u8]) -> io::Result<()> + 'static,
    {
        self.test_hidraw_writer = Some(Box::new(writer));
        self
    }
}

// ---------------------------------------------------------------------------
// Unprivileged discovery and status layer
// ---------------------------------------------------------------------------

impl ControllerBackend {
    // -- DMI target validation ------------------------------------------------

    pub fn validate_target(&self) -> Result<(), ControllerError> {
        let vendor = self
            .read_trimmed("sys/class/dmi/id/sys_vendor")
            .map_err(|_| ControllerError::UnsupportedTarget)?;
        let product = self
            .read_trimmed("sys/class/dmi/id/product_name")
            .map_err(|_| ControllerError::UnsupportedTarget)?;

        if vendor == DMI_VENDOR && product == DMI_PRODUCT {
            Ok(())
        } else {
            Err(ControllerError::UnsupportedTarget)
        }
    }

    // -- HID device discovery ------------------------------------------------

    /// Search `/sys/bus/hid/devices` for exactly one device whose uevent
    /// contains the exact `HID_ID` line **and** that has both `left_handle`
    /// and `right_handle` child directories.
    pub fn discover_device(&self) -> Result<PathBuf, ControllerError> {
        let hid_root = self.root.join("sys/bus/hid/devices");
        let entries = fs::read_dir(&hid_root).map_err(|_| ControllerError::Discovery)?;

        let mut found: Option<PathBuf> = None;

        for entry in entries {
            let entry = entry.map_err(|_| ControllerError::Discovery)?;
            let dev_path = entry.path();

            // Read uevent and look for the exact target HID_ID line.
            let uevent_path = dev_path.join("uevent");
            let uevent = match fs::read_to_string(&uevent_path) {
                Ok(uevent) => uevent,
                Err(_) => continue,
            };
            let has_target = uevent
                .lines()
                .any(|line| SUPPORTED_HID_IDS.contains(&line.trim()));

            let has_left = dev_path.join("left_handle").is_dir();
            let has_right = dev_path.join("right_handle").is_dir();

            if has_target && has_left && has_right {
                if found.is_some() {
                    // Ambiguity — more than one matching device.
                    return Err(ControllerError::Discovery);
                }
                found = Some(dev_path);
            }
        }

        found.ok_or(ControllerError::Discovery)
    }

    // -- hidraw discovery ----------------------------------------------------

    /// Find exactly one hidraw child of `device` and return its name
    /// (e.g. `hidraw3`).
    pub fn discover_hidraw(&self, device: &Path) -> Result<String, ControllerError> {
        let hidraw_dir = device.join("hidraw");
        let entries = fs::read_dir(&hidraw_dir).map_err(|_| ControllerError::Discovery)?;

        let mut names: Vec<String> = Vec::new();
        for entry in entries {
            let entry = entry.map_err(|_| ControllerError::Discovery)?;
            let name = entry.file_name().to_string_lossy().to_string();
            if name.starts_with("hidraw") {
                names.push(name);
            }
        }

        match names.len() {
            1 => Ok(names.remove(0)),
            _ => Err(ControllerError::Discovery),
        }
    }

    // -- status ---------------------------------------------------------------

    /// Run the full unprivileged status read and return structured data.
    /// This method performs DMI validation, device discovery, reads every
    /// calibration status/error/index group, and reads the persisted
    /// swap-requested state file (missing means unknown).
    pub fn status(&self) -> Result<ControllerStatus, ControllerError> {
        self.validate_target()?;
        let device = self.discover_device()?;

        let swap_requested = self.read_swap_state();
        let mut status = ControllerStatus::unknown();
        status.swap_requested = swap_requested;

        for side in [Side::Left, Side::Right] {
            for kind in [CalKind::Joystick, CalKind::Trigger, CalKind::Gyro] {
                let status_text = self
                    .read_calibration_attr(&device, side, kind, AttrKind::Status)
                    .unwrap_or_else(|_| "unknown".to_owned());
                let error_text = self
                    .read_calibration_attr(&device, side, kind, AttrKind::Error)
                    .unwrap_or_else(|_| "unknown".to_owned());
                let index_text = self
                    .read_calibration_attr(&device, side, kind, AttrKind::Index)
                    .unwrap_or_else(|_| "unknown".to_owned());

                Self::set_status_field(
                    &mut status,
                    side,
                    kind,
                    status_text,
                    error_text,
                    index_text,
                );
            }
        }

        Ok(status)
    }

    fn set_status_field(
        status: &mut ControllerStatus,
        side: Side,
        kind: CalKind,
        status_text: String,
        error_text: String,
        index_text: String,
    ) {
        match (side, kind) {
            (Side::Left, CalKind::Joystick) => {
                status.left_joystick_status = status_text;
                status.left_joystick_error = error_text;
                status.left_joystick_index = index_text;
            }
            (Side::Left, CalKind::Trigger) => {
                status.left_trigger_status = status_text;
                status.left_trigger_error = error_text;
                status.left_trigger_index = index_text;
            }
            (Side::Left, CalKind::Gyro) => {
                status.left_gyro_status = status_text;
                status.left_gyro_error = error_text;
                status.left_gyro_index = index_text;
            }
            (Side::Right, CalKind::Joystick) => {
                status.right_joystick_status = status_text;
                status.right_joystick_error = error_text;
                status.right_joystick_index = index_text;
            }
            (Side::Right, CalKind::Trigger) => {
                status.right_trigger_status = status_text;
                status.right_trigger_error = error_text;
                status.right_trigger_index = index_text;
            }
            (Side::Right, CalKind::Gyro) => {
                status.right_gyro_status = status_text;
                status.right_gyro_error = error_text;
                status.right_gyro_index = index_text;
            }
        }
    }

    // -- calibration attribute read helpers ----------------------------------

    fn read_calibration_attr(
        &self,
        device: &Path,
        side: Side,
        kind: CalKind,
        attr: AttrKind,
    ) -> Result<String, ControllerError> {
        let file_name = match attr {
            AttrKind::Status => kind.status_attr(),
            AttrKind::Error => kind.error_attr(),
            AttrKind::Index => kind.index_attr(),
        };
        let path = device.join(side.dir_name()).join(&file_name);
        let text = fs::read_to_string(&path).map_err(|_| ControllerError::Calibration)?;
        Ok(Self::sanitize_status_value(text.trim()))
    }

    fn sanitize_status_value(value: &str) -> String {
        const MAX_LEN: usize = 32;
        if value.is_empty()
            || value.len() > MAX_LEN
            || !value.bytes().all(|byte| {
                byte.is_ascii_alphanumeric() || matches!(byte, b'_' | b'-' | b'.' | b' ')
            })
        {
            return "invalid".to_owned();
        }
        value.to_owned()
    }

    // -- swap state file read ------------------------------------------------

    fn read_swap_state(&self) -> String {
        let path = self.state_root.join(STATE_FILE_NAME);
        match fs::read_to_string(&path) {
            Ok(content) => {
                let trimmed = content.trim();
                if trimmed == "enabled" || trimmed == "disabled" {
                    trimmed.to_owned()
                } else {
                    "unknown".to_owned()
                }
            }
            Err(_) => "unknown".to_owned(),
        }
    }

    // -- general helpers -----------------------------------------------------

    fn read_trimmed(&self, relative: &str) -> io::Result<String> {
        Ok(fs::read_to_string(self.root.join(relative))?
            .trim()
            .to_owned())
    }
}

// ---------------------------------------------------------------------------
// Root-required mutation layer
// ---------------------------------------------------------------------------

impl ControllerBackend {
    // -- calibration write ---------------------------------------------------

    /// Write literal `start` or `stop` to the `calibrate_{kind}` attribute
    /// for the given side and kind. Reads the adjacent status file after
    /// writing but does **not** fail if the status is unexpected (firmware
    /// completion is asynchronous).
    pub fn calibrate(
        &self,
        side: Side,
        kind: CalKind,
        action: CalAction,
        is_root: bool,
    ) -> Result<(), ControllerError> {
        if !is_root {
            return Err(ControllerError::Privilege);
        }

        self.validate_target()?;
        let device = self.discover_device()?;
        let word = match action {
            CalAction::Start => "start",
            CalAction::Stop => "stop",
        };

        // Require the complete asynchronous ABI before a write. Older driver
        // revisions can expose the command file without completion errors.
        self.read_calibration_attr(&device, side, kind, AttrKind::Status)?;
        self.read_calibration_attr(&device, side, kind, AttrKind::Error)?;
        let actions = self.read_calibration_attr(&device, side, kind, AttrKind::Index)?;
        if !actions.split_ascii_whitespace().any(|value| value == word) {
            return Err(ControllerError::Calibration);
        }

        let attr_path = device.join(side.dir_name()).join(kind.calibrate_attr());
        let mut file = File::options()
            .write(true)
            .truncate(true)
            .open(&attr_path)
            .map_err(|_| ControllerError::Calibration)?;
        file.write_all(word.as_bytes())
            .map_err(|_| ControllerError::Calibration)?;

        // Read the adjacent status (best-effort; do not require success).
        let _ = self.read_calibration_attr(&device, side, kind, AttrKind::Status);

        Ok(())
    }

    // -- swap enable / disable -----------------------------------------------

    pub fn swap_enable(&self, is_root: bool) -> Result<(), ControllerError> {
        self.swap_impl(is_root, &SWAP_ENABLE_PAYLOAD, "enabled")
    }

    pub fn swap_disable(&self, is_root: bool) -> Result<(), ControllerError> {
        self.swap_impl(is_root, &SWAP_DISABLE_PAYLOAD, "disabled")
    }

    fn swap_impl(
        &self,
        is_root: bool,
        payload: &[u8; 7],
        state_label: &str,
    ) -> Result<(), ControllerError> {
        if !is_root {
            return Err(ControllerError::Privilege);
        }

        self.validate_target()?;
        let device = self.discover_device()?;
        let hidraw_name = self.discover_hidraw(&device)?;
        let dev_path = PathBuf::from("/dev").join(&hidraw_name);

        // If a test writer is injected, delegate the I/O to it.
        if let Some(ref writer) = self.test_hidraw_writer {
            writer(&dev_path, payload).map_err(|_| ControllerError::Write)?;
        } else {
            let mut file = File::options()
                .write(true)
                .open(&dev_path)
                .map_err(|_| ControllerError::Write)?;
            let written = file.write(payload).map_err(|_| ControllerError::Write)?;
            if written != 7 {
                return Err(ControllerError::Write);
            }
            file.flush().map_err(|_| ControllerError::Write)?;
        }

        // Atomically persist the requested state.
        self.write_swap_state(state_label)?;

        Ok(())
    }

    // -- atomic swap-state file write ----------------------------------------

    fn write_swap_state(&self, label: &str) -> Result<(), ControllerError> {
        let dir = &self.state_root;
        fs::create_dir_all(dir).map_err(|_| ControllerError::State)?;

        let tmp_path = dir.join(format!(".{}.tmp", STATE_FILE_NAME));
        let final_path = dir.join(STATE_FILE_NAME);

        let mut file = File::create(&tmp_path).map_err(|_| ControllerError::State)?;

        // Restrictive permissions: 0o644.
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            file.set_permissions(fs::Permissions::from_mode(0o644))
                .map_err(|_| ControllerError::State)?;
        }

        let content = format!("{}\n", label);
        file.write_all(content.as_bytes())
            .map_err(|_| ControllerError::State)?;
        file.sync_all().map_err(|_| ControllerError::State)?;

        fs::rename(&tmp_path, &final_path).map_err(|_| ControllerError::State)?;

        // Sync the parent directory.
        let dir_file = File::open(dir).map_err(|_| ControllerError::State)?;
        dir_file.sync_all().map_err(|_| ControllerError::State)?;

        Ok(())
    }
}

// ---------------------------------------------------------------------------
// process-effective-UID check (Unix / fallback)
// ---------------------------------------------------------------------------

#[cfg(unix)]
unsafe extern "C" {
    fn geteuid() -> u32;
}

#[cfg(unix)]
pub fn process_effective_uid_is_root() -> bool {
    unsafe { geteuid() == 0 }
}

#[cfg(not(unix))]
pub fn process_effective_uid_is_root() -> bool {
    false
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::time::{SystemTime, UNIX_EPOCH};

    // -- test root helpers ---------------------------------------------------

    static NEXT_TEST_ROOT: AtomicUsize = AtomicUsize::new(0);

    struct TestRoots {
        sys: PathBuf,   // fake sysfs root
        state: PathBuf, // fake state root
    }

    impl TestRoots {
        fn new() -> Self {
            let sequence = NEXT_TEST_ROOT.fetch_add(1, Ordering::Relaxed);
            let nanos = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .expect("system clock before Unix epoch")
                .as_nanos();
            let base = std::env::temp_dir().join(format!(
                "lgo-ctrl-test-{}-{nanos}-{sequence}",
                std::process::id()
            ));
            let sys = base.join("sys");
            let state = base.join("state");
            fs::create_dir_all(&sys).expect("create test sys root");
            fs::create_dir_all(&state).expect("create test state root");
            Self { sys, state }
        }

        fn backend(&self) -> ControllerBackend {
            ControllerBackend::for_roots(&self.sys, &self.state)
        }

        /// Write content into `self.sys/relative`.
        fn write_sys(&self, relative: &str, content: &str) {
            let path = self.sys.join(relative);
            fs::create_dir_all(path.parent().expect("test path parent"))
                .expect("create test sys dir");
            fs::write(path, content).expect("write test sys file");
        }

        /// Write content into `self.state/filename`.
        fn write_state(&self, filename: &str, content: &str) {
            let path = self.state.join(filename);
            fs::write(path, content).expect("write test state file");
        }

        /// Add a DMI identity that passes target validation.
        fn supported_target(&self) {
            self.write_sys("sys/class/dmi/id/sys_vendor", " LENOVO\n");
            self.write_sys("sys/class/dmi/id/product_name", "83E1 \n");
        }

        /// Add a HID device with left/right handle directories.
        fn add_hid_device_with_uevent(&self, hid_name: &str, uevent: &str) {
            let dev = format!("sys/bus/hid/devices/{hid_name}");
            self.write_sys(&format!("{dev}/uevent"), uevent);
            // Create handle directories (just as empty dirs).
            fs::create_dir_all(self.sys.join(&dev).join("left_handle"))
                .expect("create left_handle");
            fs::create_dir_all(self.sys.join(&dev).join("right_handle"))
                .expect("create right_handle");
        }

        /// Add a matching HID device with a selected protocol PID.
        fn add_hid_device_with_pid(&self, hid_name: &str, pid: &str) {
            let uevent = format!("HID_ID=0003:000017EF:{pid}\nHID_NAME=Test\n");
            self.add_hid_device_with_uevent(hid_name, &uevent);
        }

        /// Add a matching HID device with the default XInput PID.
        fn add_matching_hid_device(&self, hid_name: &str) {
            self.add_hid_device_with_pid(hid_name, "000061EB");
        }

        /// Add calibration files for a side/kind pair.
        fn add_calibration_files(
            &self,
            hid_name: &str,
            side: Side,
            kind: CalKind,
            status: &str,
            index: &str,
        ) {
            let dev = format!("sys/bus/hid/devices/{hid_name}");
            let handle = side.dir_name();
            self.write_sys(&format!("{dev}/{handle}/{}", kind.status_attr()), status);
            self.write_sys(&format!("{dev}/{handle}/{}", kind.error_attr()), "none");
            self.write_sys(&format!("{dev}/{handle}/{}", kind.index_attr()), index);
            // Also create the calibrate attribute so writes succeed.
            self.write_sys(&format!("{dev}/{handle}/{}", kind.calibrate_attr()), "");
        }

        fn set_calibration_error(&self, hid_name: &str, side: Side, kind: CalKind, error: &str) {
            let dev = format!("sys/bus/hid/devices/{hid_name}");
            self.write_sys(
                &format!("{dev}/{}/{}", side.dir_name(), kind.error_attr()),
                error,
            );
        }

        /// Add a hidraw child so swap discovery works.
        fn add_hidraw(&self, hid_name: &str, hidraw_name: &str) {
            let dev = format!("sys/bus/hid/devices/{hid_name}");
            let hidraw_dir = format!("{dev}/hidraw/{hidraw_name}");
            fs::create_dir_all(self.sys.join(&hidraw_dir)).expect("create hidraw dir");
        }
    }

    impl Drop for TestRoots {
        fn drop(&mut self) {
            // Remove the shared parent (temp base) so both roots are cleaned.
            if let Some(parent) = self.sys.parent() {
                let _ = fs::remove_dir_all(parent);
            }
        }
    }

    // -- command parsing -----------------------------------------------------

    #[test]
    fn calibration_attribute_names_match_kernel_abi() {
        for (kind, name) in [
            (CalKind::Joystick, "joystick"),
            (CalKind::Trigger, "trigger"),
            (CalKind::Gyro, "gyro"),
        ] {
            assert_eq!(kind.calibrate_attr(), format!("calibrate_{name}"));
            assert_eq!(kind.status_attr(), format!("calibrate_{name}_status"));
            assert_eq!(kind.error_attr(), format!("calibrate_{name}_error"));
            assert_eq!(kind.index_attr(), format!("calibrate_{name}_index"));
        }
    }

    #[test]
    fn command_parser_accepts_allowlist_exactly_one_arg() {
        assert_eq!(
            ControllerCommand::parse_args(&["status".to_owned()]),
            Ok(ControllerCommand::Status)
        );
        assert_eq!(
            ControllerCommand::parse_args(&["swap-enable".to_owned()]),
            Ok(ControllerCommand::SwapEnable)
        );
        assert_eq!(
            ControllerCommand::parse_args(&["swap-disable".to_owned()]),
            Ok(ControllerCommand::SwapDisable)
        );
        assert_eq!(
            ControllerCommand::parse_args(&["calibrate-left-joystick-start".to_owned()]),
            Ok(ControllerCommand::CalibrateLeftJoystickStart)
        );
        assert_eq!(
            ControllerCommand::parse_args(&["calibrate-left-joystick-stop".to_owned()]),
            Ok(ControllerCommand::CalibrateLeftJoystickStop)
        );
        assert_eq!(
            ControllerCommand::parse_args(&["calibrate-left-trigger-start".to_owned()]),
            Ok(ControllerCommand::CalibrateLeftTriggerStart)
        );
        assert_eq!(
            ControllerCommand::parse_args(&["calibrate-left-trigger-stop".to_owned()]),
            Ok(ControllerCommand::CalibrateLeftTriggerStop)
        );
        assert_eq!(
            ControllerCommand::parse_args(&["calibrate-left-gyro-start".to_owned()]),
            Ok(ControllerCommand::CalibrateLeftGyroStart)
        );
        assert_eq!(
            ControllerCommand::parse_args(&["calibrate-left-gyro-stop".to_owned()]),
            Ok(ControllerCommand::CalibrateLeftGyroStop)
        );
        assert_eq!(
            ControllerCommand::parse_args(&["calibrate-right-joystick-start".to_owned()]),
            Ok(ControllerCommand::CalibrateRightJoystickStart)
        );
        assert_eq!(
            ControllerCommand::parse_args(&["calibrate-right-joystick-stop".to_owned()]),
            Ok(ControllerCommand::CalibrateRightJoystickStop)
        );
        assert_eq!(
            ControllerCommand::parse_args(&["calibrate-right-trigger-start".to_owned()]),
            Ok(ControllerCommand::CalibrateRightTriggerStart)
        );
        assert_eq!(
            ControllerCommand::parse_args(&["calibrate-right-trigger-stop".to_owned()]),
            Ok(ControllerCommand::CalibrateRightTriggerStop)
        );
        assert_eq!(
            ControllerCommand::parse_args(&["calibrate-right-gyro-start".to_owned()]),
            Ok(ControllerCommand::CalibrateRightGyroStart)
        );
        assert_eq!(
            ControllerCommand::parse_args(&["calibrate-right-gyro-stop".to_owned()]),
            Ok(ControllerCommand::CalibrateRightGyroStop)
        );
    }

    #[test]
    fn command_parser_rejects_unknown_and_extra_args() {
        assert_eq!(
            ControllerCommand::parse_args(&[]),
            Err(ControllerError::Usage)
        );
        assert_eq!(
            ControllerCommand::parse_args(&["status".to_owned(), "extra".to_owned()]),
            Err(ControllerError::Usage)
        );
        assert_eq!(
            ControllerCommand::parse_args(&["garbage".to_owned()]),
            Err(ControllerError::Usage)
        );
    }

    #[test]
    fn command_name_is_stable() {
        assert_eq!(ControllerCommand::Status.name(), "status");
        assert_eq!(ControllerCommand::SwapEnable.name(), "swap-enable");
        assert_eq!(ControllerCommand::SwapDisable.name(), "swap-disable");
        assert_eq!(
            ControllerCommand::CalibrateLeftJoystickStart.name(),
            "calibrate-left-joystick-start"
        );
    }

    #[test]
    fn calibration_triple_extracts_correct_side_kind_action() {
        assert_eq!(
            ControllerCommand::CalibrateLeftJoystickStart.calibration_triple(),
            Some((Side::Left, CalKind::Joystick, CalAction::Start))
        );
        assert_eq!(
            ControllerCommand::CalibrateRightTriggerStop.calibration_triple(),
            Some((Side::Right, CalKind::Trigger, CalAction::Stop))
        );
        assert_eq!(
            ControllerCommand::CalibrateLeftGyroStart.calibration_triple(),
            Some((Side::Left, CalKind::Gyro, CalAction::Start))
        );
        assert_eq!(
            ControllerCommand::CalibrateRightGyroStop.calibration_triple(),
            Some((Side::Right, CalKind::Gyro, CalAction::Stop))
        );
        // Non-calibration commands return None.
        assert_eq!(ControllerCommand::Status.calibration_triple(), None);
        assert_eq!(ControllerCommand::SwapEnable.calibration_triple(), None);
    }

    // -- DMI validation ------------------------------------------------------

    #[test]
    fn target_validation_requires_exact_trimmed_dmi() {
        let roots = TestRoots::new();
        roots.supported_target();
        assert_eq!(roots.backend().validate_target(), Ok(()));

        // Wrong product.
        roots.write_sys("sys/class/dmi/id/product_name", "83E2\n");
        assert_eq!(
            roots.backend().validate_target(),
            Err(ControllerError::UnsupportedTarget)
        );

        // Missing file entirely.
        let roots2 = TestRoots::new();
        assert_eq!(
            roots2.backend().validate_target(),
            Err(ControllerError::UnsupportedTarget)
        );
    }

    // -- device discovery ----------------------------------------------------

    #[test]
    fn device_discovery_finds_exactly_one_matching_hid_device() {
        let roots = TestRoots::new();
        roots.supported_target();

        // No devices.
        assert_eq!(
            roots.backend().discover_device(),
            Err(ControllerError::Discovery)
        );

        // One matching device.
        roots.add_matching_hid_device("0003:17EF:61EB.0001");
        let dev = roots.backend().discover_device().expect("discover device");
        assert!(dev.ends_with("0003:17EF:61EB.0001"));

        // Two matching owner paths are ambiguous, even with different PIDs.
        roots.add_hid_device_with_pid("0003:17EF:61EC.0002", "000061EC");
        assert_eq!(
            roots.backend().discover_device(),
            Err(ControllerError::Discovery)
        );
    }

    #[test]
    fn device_discovery_accepts_all_supported_protocol_pids() {
        for pid in ["000061EB", "000061EC", "000061ED", "000061EE"] {
            let roots = TestRoots::new();
            roots.supported_target();
            let hid_name = format!("0003:17EF:{pid}.0001");
            roots.add_hid_device_with_pid(&hid_name, pid);

            let dev = roots.backend().discover_device().expect("discover device");
            assert!(dev.ends_with(hid_name.as_str()), "PID {pid} was not found");
        }
    }

    #[test]
    fn device_discovery_rejects_adjacent_other_and_malformed_hid_ids() {
        let cases = [
            (
                "adjacent lower PID",
                "HID_ID=0003:000017EF:000061EA\nHID_NAME=Test\n",
            ),
            (
                "adjacent higher PID",
                "HID_ID=0003:000017EF:000061EF\nHID_NAME=Test\n",
            ),
            (
                "other Lenovo PID",
                "HID_ID=0003:000017EF:000061F0\nHID_NAME=Test\n",
            ),
            (
                "non-Lenovo VID",
                "HID_ID=0003:00001234:000061EB\nHID_NAME=Test\n",
            ),
            ("malformed HID_ID", "HID_ID=not-a-hid-id\nHID_NAME=Test\n"),
            ("missing HID_ID", "HID_NAME=Test\n"),
        ];

        for (label, uevent) in cases {
            let roots = TestRoots::new();
            roots.supported_target();
            roots.add_hid_device_with_uevent("0003:17EF:0000.0001", uevent);
            assert_eq!(
                roots.backend().discover_device(),
                Err(ControllerError::Discovery),
                "{label} must not be discovered"
            );
        }
    }

    #[test]
    fn device_discovery_requires_left_and_right_handle_dirs() {
        let roots = TestRoots::new();
        roots.supported_target();

        // Device with correct HID_ID but no handle directories.
        let dev = "sys/bus/hid/devices/0003:17EF:61EB.0001";
        roots.write_sys(&format!("{dev}/uevent"), "HID_ID=0003:000017EF:000061EB\n");
        // No left_handle / right_handle dirs.
        assert_eq!(
            roots.backend().discover_device(),
            Err(ControllerError::Discovery)
        );

        // Add only left_handle.
        fs::create_dir_all(roots.sys.join(dev).join("left_handle")).expect("create left_handle");
        assert_eq!(
            roots.backend().discover_device(),
            Err(ControllerError::Discovery)
        );

        // Add right_handle → now it passes.
        fs::create_dir_all(roots.sys.join(dev).join("right_handle")).expect("create right_handle");
        assert!(roots.backend().discover_device().is_ok());
    }

    #[test]
    fn device_discovery_requires_exact_hid_id_line() {
        let roots = TestRoots::new();
        roots.supported_target();

        let dev = "sys/bus/hid/devices/0003:17EF:61EC.0001";
        // A supported HID_ID with extra data is not an exact match.
        roots.write_sys(
            &format!("{dev}/uevent"),
            "HID_ID=0003:000017EF:000061EC extra\n",
        );
        fs::create_dir_all(roots.sys.join(dev).join("left_handle")).expect("create left_handle");
        fs::create_dir_all(roots.sys.join(dev).join("right_handle")).expect("create right_handle");

        assert_eq!(
            roots.backend().discover_device(),
            Err(ControllerError::Discovery)
        );
    }

    // -- hidraw discovery ----------------------------------------------------

    #[test]
    fn hidraw_discovery_requires_exactly_one_hidraw_child() {
        let roots = TestRoots::new();
        roots.supported_target();
        let hid_name = "0003:17EF:61EB.0001";
        roots.add_matching_hid_device(hid_name);

        let dev_path = roots.sys.join("sys/bus/hid/devices").join(hid_name);
        let backend = roots.backend();

        // No hidraw directory.
        assert_eq!(
            backend.discover_hidraw(&dev_path),
            Err(ControllerError::Discovery)
        );

        // Empty hidraw directory.
        fs::create_dir_all(dev_path.join("hidraw")).expect("create hidraw dir");
        assert_eq!(
            backend.discover_hidraw(&dev_path),
            Err(ControllerError::Discovery)
        );

        // One hidraw child.
        fs::create_dir_all(dev_path.join("hidraw/hidraw3")).expect("create hidraw3");
        assert_eq!(backend.discover_hidraw(&dev_path).unwrap(), "hidraw3");

        // Two hidraw children → ambiguity.
        fs::create_dir_all(dev_path.join("hidraw/hidraw4")).expect("create hidraw4");
        assert_eq!(
            backend.discover_hidraw(&dev_path),
            Err(ControllerError::Discovery)
        );
    }

    // -- status --------------------------------------------------------------

    #[test]
    fn status_reads_all_calibration_attributes() {
        let roots = TestRoots::new();
        roots.supported_target();
        let hid_name = "0003:17EF:61EB.0001";
        roots.add_matching_hid_device(hid_name);

        // Populate calibration files with distinct values.
        roots.add_calibration_files(hid_name, Side::Left, CalKind::Joystick, "ready", "1");
        roots.add_calibration_files(hid_name, Side::Left, CalKind::Trigger, "running", "2");
        roots.add_calibration_files(hid_name, Side::Left, CalKind::Gyro, "idle", "0");
        roots.add_calibration_files(hid_name, Side::Right, CalKind::Joystick, "ready", "1");
        roots.add_calibration_files(hid_name, Side::Right, CalKind::Trigger, "failed", "3");
        roots.add_calibration_files(hid_name, Side::Right, CalKind::Gyro, "idle", "0");
        roots.set_calibration_error(hid_name, Side::Left, CalKind::Joystick, "e1");
        roots.set_calibration_error(hid_name, Side::Left, CalKind::Trigger, "e2");
        roots.set_calibration_error(hid_name, Side::Left, CalKind::Gyro, "e3");
        roots.set_calibration_error(hid_name, Side::Right, CalKind::Joystick, "e4");
        roots.set_calibration_error(hid_name, Side::Right, CalKind::Trigger, "e5");
        roots.set_calibration_error(hid_name, Side::Right, CalKind::Gyro, "e6");

        let status = roots.backend().status().expect("status");
        assert_eq!(status.swap_requested, "unknown");
        assert_eq!(status.left_joystick_status, "ready");
        assert_eq!(status.left_joystick_error, "e1");
        assert_eq!(status.left_joystick_index, "1");
        assert_eq!(status.left_trigger_status, "running");
        assert_eq!(status.left_trigger_error, "e2");
        assert_eq!(status.left_trigger_index, "2");
        assert_eq!(status.left_gyro_status, "idle");
        assert_eq!(status.left_gyro_error, "e3");
        assert_eq!(status.left_gyro_index, "0");
        assert_eq!(status.right_joystick_status, "ready");
        assert_eq!(status.right_joystick_error, "e4");
        assert_eq!(status.right_joystick_index, "1");
        assert_eq!(status.right_trigger_status, "failed");
        assert_eq!(status.right_trigger_error, "e5");
        assert_eq!(status.right_trigger_index, "3");
        assert_eq!(status.right_gyro_status, "idle");
        assert_eq!(status.right_gyro_error, "e6");
        assert_eq!(status.right_gyro_index, "0");
    }

    #[test]
    fn status_missing_calibration_files_are_unknown() {
        let roots = TestRoots::new();
        roots.supported_target();
        roots.add_matching_hid_device("0003:17EF:61EB.0001");
        // No calibration files added.

        let status = roots.backend().status().expect("status");
        assert_eq!(status.left_joystick_status, "unknown");
        assert_eq!(status.left_joystick_error, "unknown");
        assert_eq!(status.left_joystick_index, "unknown");
        assert_eq!(status.right_gyro_status, "unknown");
        assert_eq!(status.right_gyro_error, "unknown");
        assert_eq!(status.right_gyro_index, "unknown");
    }

    #[test]
    fn status_replaces_unsafe_sysfs_text() {
        let roots = TestRoots::new();
        roots.supported_target();
        let hid_name = "0003:17EF:61EB.0001";
        roots.add_matching_hid_device(hid_name);
        roots.add_calibration_files(
            hid_name,
            Side::Left,
            CalKind::Joystick,
            "bad\"status",
            "start stop",
        );

        roots.set_calibration_error(hid_name, Side::Left, CalKind::Joystick, "bad\"error");

        let status = roots.backend().status().expect("status");
        assert_eq!(status.left_joystick_status, "invalid");
        assert_eq!(status.left_joystick_error, "invalid");
        assert_eq!(status.left_joystick_index, "start stop");
    }

    // -- swap requested state ------------------------------------------------

    #[test]
    fn swap_state_missing_is_unknown() {
        let roots = TestRoots::new();
        roots.supported_target();
        roots.add_matching_hid_device("0003:17EF:61EB.0001");

        let status = roots.backend().status().expect("status");
        assert_eq!(status.swap_requested, "unknown");
    }

    #[test]
    fn swap_state_reads_enabled_and_disabled() {
        let roots = TestRoots::new();
        roots.supported_target();
        roots.add_matching_hid_device("0003:17EF:61EB.0001");

        roots.write_state(STATE_FILE_NAME, "enabled\n");
        assert_eq!(roots.backend().status().unwrap().swap_requested, "enabled");

        roots.write_state(STATE_FILE_NAME, "disabled\n");
        assert_eq!(roots.backend().status().unwrap().swap_requested, "disabled");
    }

    #[test]
    fn swap_state_rejects_unrecognized_content() {
        let roots = TestRoots::new();
        roots.supported_target();
        roots.add_matching_hid_device("0003:17EF:61EB.0001");

        roots.write_state(STATE_FILE_NAME, "garbage\n");
        assert_eq!(roots.backend().status().unwrap().swap_requested, "unknown");

        // Whitespace-only.
        roots.write_state(STATE_FILE_NAME, "  \n");
        assert_eq!(roots.backend().status().unwrap().swap_requested, "unknown");
    }

    // -- privilege enforcement -----------------------------------------------

    #[test]
    fn calibration_requires_root() {
        let roots = TestRoots::new();
        roots.supported_target();
        roots.add_matching_hid_device("0003:17EF:61EB.0001");

        assert_eq!(
            roots
                .backend()
                .calibrate(Side::Left, CalKind::Joystick, CalAction::Start, false),
            Err(ControllerError::Privilege)
        );
    }

    #[test]
    fn swap_requires_root() {
        let roots = TestRoots::new();
        roots.supported_target();
        roots.add_matching_hid_device("0003:17EF:61EB.0001");

        assert_eq!(
            roots.backend().swap_enable(false),
            Err(ControllerError::Privilege)
        );
        assert_eq!(
            roots.backend().swap_disable(false),
            Err(ControllerError::Privilege)
        );
    }

    // -- calibration write file/value selection ------------------------------

    /// Helper: get the text written to the calibrate attribute.
    fn read_calibrate_file(roots: &TestRoots, hid_name: &str, side: Side, kind: CalKind) -> String {
        let path = roots.sys.join(format!(
            "sys/bus/hid/devices/{hid_name}/{}/{}",
            side.dir_name(),
            kind.calibrate_attr()
        ));
        fs::read_to_string(&path).unwrap_or_default()
    }

    #[test]
    fn calibration_rejects_an_incomplete_or_unsupported_abi() {
        let roots = TestRoots::new();
        roots.supported_target();
        let hid_name = "0003:17EF:61EB.0001";
        roots.add_matching_hid_device(hid_name);

        assert_eq!(
            roots
                .backend()
                .calibrate(Side::Left, CalKind::Joystick, CalAction::Start, true),
            Err(ControllerError::Calibration)
        );
        roots.add_calibration_files(hid_name, Side::Left, CalKind::Joystick, "unknown", "stop");
        assert_eq!(
            roots
                .backend()
                .calibrate(Side::Left, CalKind::Joystick, CalAction::Start, true),
            Err(ControllerError::Calibration)
        );
    }

    #[test]
    fn calibration_writes_start_and_stop_to_correct_attribute() {
        let roots = TestRoots::new();
        roots.supported_target();
        let hid_name = "0003:17EF:61EB.0001";
        roots.add_matching_hid_device(hid_name);

        // Create the complete asynchronous calibration ABI.
        for side in [Side::Left, Side::Right] {
            for kind in [CalKind::Joystick, CalKind::Trigger, CalKind::Gyro] {
                roots.add_calibration_files(hid_name, side, kind, "idle", "start stop");
            }
        }

        let backend = roots.backend();

        // Left joystick start.
        backend
            .calibrate(Side::Left, CalKind::Joystick, CalAction::Start, true)
            .unwrap();
        assert_eq!(
            read_calibrate_file(&roots, hid_name, Side::Left, CalKind::Joystick),
            "start"
        );

        // Left joystick stop.
        backend
            .calibrate(Side::Left, CalKind::Joystick, CalAction::Stop, true)
            .unwrap();
        assert_eq!(
            read_calibrate_file(&roots, hid_name, Side::Left, CalKind::Joystick),
            "stop"
        );

        // Right trigger start.
        backend
            .calibrate(Side::Right, CalKind::Trigger, CalAction::Start, true)
            .unwrap();
        assert_eq!(
            read_calibrate_file(&roots, hid_name, Side::Right, CalKind::Trigger),
            "start"
        );

        // Right gyro stop.
        backend
            .calibrate(Side::Right, CalKind::Gyro, CalAction::Stop, true)
            .unwrap();
        assert_eq!(
            read_calibrate_file(&roots, hid_name, Side::Right, CalKind::Gyro),
            "stop"
        );

        // Left gyro start.
        backend
            .calibrate(Side::Left, CalKind::Gyro, CalAction::Start, true)
            .unwrap();
        assert_eq!(
            read_calibrate_file(&roots, hid_name, Side::Left, CalKind::Gyro),
            "start"
        );

        // Left trigger stop.
        backend
            .calibrate(Side::Left, CalKind::Trigger, CalAction::Stop, true)
            .unwrap();
        assert_eq!(
            read_calibrate_file(&roots, hid_name, Side::Left, CalKind::Trigger),
            "stop"
        );

        // Right joystick start.
        backend
            .calibrate(Side::Right, CalKind::Joystick, CalAction::Start, true)
            .unwrap();
        assert_eq!(
            read_calibrate_file(&roots, hid_name, Side::Right, CalKind::Joystick),
            "start"
        );
    }

    // -- swap payloads -------------------------------------------------------

    #[test]
    fn swap_enable_writes_exact_seven_byte_payload() {
        let roots = TestRoots::new();
        roots.supported_target();
        let hid_name = "0003:17EF:61EB.0001";
        roots.add_matching_hid_device(hid_name);
        roots.add_hidraw(hid_name, "hidraw3");

        // Use a fake writer to capture the payload.
        let captured = std::rc::Rc::new(std::cell::RefCell::new(None::<Vec<u8>>));
        let writer = {
            let captured = std::rc::Rc::clone(&captured);
            move |_path: &Path, data: &[u8]| {
                *captured.borrow_mut() = Some(data.to_vec());
                Ok(())
            }
        };

        let backend = roots.backend().with_hidraw_writer(writer);
        backend.swap_enable(true).unwrap();

        let written = captured.borrow().clone().unwrap();
        assert_eq!(written.len(), 7);
        assert_eq!(written, SWAP_ENABLE_PAYLOAD.to_vec());

        // Check state file was written.
        let state_content =
            fs::read_to_string(roots.state.join(STATE_FILE_NAME)).expect("state file");
        assert_eq!(state_content, "enabled\n");
    }

    #[test]
    fn swap_disable_writes_exact_seven_byte_payload() {
        let roots = TestRoots::new();
        roots.supported_target();
        let hid_name = "0003:17EF:61EB.0001";
        roots.add_matching_hid_device(hid_name);
        roots.add_hidraw(hid_name, "hidraw3");

        let captured = std::rc::Rc::new(std::cell::RefCell::new(None::<Vec<u8>>));
        let writer = {
            let captured = std::rc::Rc::clone(&captured);
            move |_path: &Path, data: &[u8]| {
                *captured.borrow_mut() = Some(data.to_vec());
                Ok(())
            }
        };

        let backend = roots.backend().with_hidraw_writer(writer);
        backend.swap_disable(true).unwrap();

        let written = captured.borrow().clone().unwrap();
        assert_eq!(written, SWAP_DISABLE_PAYLOAD.to_vec());

        let state_content =
            fs::read_to_string(roots.state.join(STATE_FILE_NAME)).expect("state file");
        assert_eq!(state_content, "disabled\n");
    }

    #[test]
    fn swap_partial_write_is_reported_as_error() {
        let roots = TestRoots::new();
        roots.supported_target();
        let hid_name = "0003:17EF:61EB.0001";
        roots.add_matching_hid_device(hid_name);
        roots.add_hidraw(hid_name, "hidraw3");

        // Writer that simulates a partial write.
        let writer =
            |_path: &Path, _data: &[u8]| Err(io::Error::new(io::ErrorKind::Other, "partial write"));

        let backend = roots.backend().with_hidraw_writer(writer);
        assert_eq!(backend.swap_enable(true), Err(ControllerError::Write));

        // State file must NOT be created on a failed write.
        assert!(!roots.state.join(STATE_FILE_NAME).exists());
    }

    // -- calibration for every side/kind/action class ------------------------

    #[test]
    fn all_twelve_calibration_commands_write_correct_file_and_value() {
        let roots = TestRoots::new();
        roots.supported_target();
        let hid_name = "0003:17EF:61EB.0001";
        roots.add_matching_hid_device(hid_name);

        // Pre-create all calibrate files.
        for side in [Side::Left, Side::Right] {
            for kind in [CalKind::Joystick, CalKind::Trigger, CalKind::Gyro] {
                roots.add_calibration_files(hid_name, side, kind, "idle", "start stop");
            }
        }

        let backend = roots.backend();

        // Test every combination.
        let cases: &[(Side, CalKind, CalAction, &str)] = &[
            (Side::Left, CalKind::Joystick, CalAction::Start, "start"),
            (Side::Left, CalKind::Joystick, CalAction::Stop, "stop"),
            (Side::Left, CalKind::Trigger, CalAction::Start, "start"),
            (Side::Left, CalKind::Trigger, CalAction::Stop, "stop"),
            (Side::Left, CalKind::Gyro, CalAction::Start, "start"),
            (Side::Left, CalKind::Gyro, CalAction::Stop, "stop"),
            (Side::Right, CalKind::Joystick, CalAction::Start, "start"),
            (Side::Right, CalKind::Joystick, CalAction::Stop, "stop"),
            (Side::Right, CalKind::Trigger, CalAction::Start, "start"),
            (Side::Right, CalKind::Trigger, CalAction::Stop, "stop"),
            (Side::Right, CalKind::Gyro, CalAction::Start, "start"),
            (Side::Right, CalKind::Gyro, CalAction::Stop, "stop"),
        ];

        for (side, kind, action, expected_word) in cases {
            // Reset the file to empty so we can verify it was overwritten.
            let file_path = roots.sys.join(format!(
                "sys/bus/hid/devices/{hid_name}/{}/{}",
                side.dir_name(),
                kind.calibrate_attr()
            ));
            fs::write(&file_path, "").expect("reset calibrate file");

            backend.calibrate(*side, *kind, *action, true).unwrap();

            let content = fs::read_to_string(&file_path).expect("read calibrate file");
            assert_eq!(
                content, *expected_word,
                "mismatch for {side:?}/{kind:?}/{action:?}"
            );
        }
    }

    // -- error codes and display ---------------------------------------------

    #[test]
    fn controller_error_codes_are_stable() {
        assert_eq!(ControllerError::Usage.code(), "usage");
        assert_eq!(
            ControllerError::UnsupportedTarget.code(),
            "unsupported_target"
        );
        assert_eq!(ControllerError::Discovery.code(), "discovery");
        assert_eq!(ControllerError::Calibration.code(), "calibration");
        assert_eq!(ControllerError::Privilege.code(), "privilege");
        assert_eq!(ControllerError::Write.code(), "write");
        assert_eq!(ControllerError::State.code(), "state");
    }

    #[test]
    fn controller_error_exit_codes_are_stable_and_distinct() {
        let codes: Vec<i32> = [
            ControllerError::Usage,
            ControllerError::UnsupportedTarget,
            ControllerError::Discovery,
            ControllerError::Calibration,
            ControllerError::Privilege,
            ControllerError::Write,
            ControllerError::State,
        ]
        .iter()
        .map(|e| e.exit_code())
        .collect();
        // All should be distinct and in range 2..=8.
        let mut sorted = codes.clone();
        sorted.sort();
        sorted.dedup();
        assert_eq!(sorted.len(), codes.len(), "exit codes must be distinct");
        assert!(codes.iter().all(|c| *c >= 2 && *c <= 8));
    }

    #[test]
    fn controller_error_display_is_non_empty() {
        for err in [
            ControllerError::Usage,
            ControllerError::UnsupportedTarget,
            ControllerError::Discovery,
            ControllerError::Calibration,
            ControllerError::Privilege,
            ControllerError::Write,
            ControllerError::State,
        ] {
            assert!(!err.to_string().is_empty());
        }
    }
}
