use anyhow::Result;
use std::path::PathBuf;

#[cfg(target_os = "windows")]
mod windows;
#[cfg(target_os = "windows")]
pub use windows::*;

#[cfg(target_os = "linux")]
mod linux;
#[cfg(target_os = "linux")]
pub use linux::*;

#[cfg(target_os = "macos")]
mod macos;
#[cfg(target_os = "macos")]
pub use macos::*;

// Common service trait
pub trait ServiceManager {
    fn install(&self) -> Result<()>;
    fn uninstall(&self) -> Result<()>;
    fn start(&self) -> Result<()>;
    fn stop(&self) -> Result<()>;
    fn status(&self) -> Result<ServiceStatus>;
}

#[allow(dead_code)]
pub enum ServiceStatus {
    Running,
    Stopped,
    NotInstalled,
    Unknown,
}

#[allow(dead_code)]
pub struct ServiceConfig {
    pub name: String,
    pub display_name: String,
    pub description: String,
    pub executable_path: PathBuf,
    pub args: Vec<String>,
    pub config_path: Option<PathBuf>,
}

pub fn create_service_manager(config: ServiceConfig) -> Box<dyn ServiceManager> {
    #[cfg(target_os = "windows")]
    {
        Box::new(WindowsServiceManager::new(config))
    }
    #[cfg(target_os = "linux")]
    {
        Box::new(LinuxServiceManager::new(config))
    }
    #[cfg(target_os = "macos")]
    {
        Box::new(MacOSServiceManager::new(config))
    }
    #[cfg(not(any(target_os = "windows", target_os = "linux", target_os = "macos")))]
    {
        panic!("Unsupported platform for service management");
    }
}
