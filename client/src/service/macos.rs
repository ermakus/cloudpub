use crate::service::{ServiceConfig, ServiceManager, ServiceStatus};
use anyhow::{Context, Result};
use std::fs;
use std::path::PathBuf;
use std::process::Command;

pub struct MacOSServiceManager {
    config: ServiceConfig,
}

impl MacOSServiceManager {
    pub fn new(config: ServiceConfig) -> Self {
        Self { config }
    }

    fn plist_path(&self) -> PathBuf {
        PathBuf::from(format!("/Library/LaunchDaemons/{}.plist", self.config.name))
    }

    fn create_plist_file(&self) -> Result<()> {
        let executable = self.config.executable_path.to_string_lossy();

        // Convert args to XML array elements
        let args_xml = self
            .config
            .args
            .iter()
            .map(|arg| format!("\t\t<string>{}</string>", arg))
            .collect::<Vec<_>>()
            .join("\n");

        let program_args = format!("\t\t<string>{}</string>\n{}", executable, args_xml);

        let plist_content = format!(
            r#"<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>{}</string>
    <key>ProgramArguments</key>
    <array>
{}
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardErrorPath</key>
    <string>/tmp/{}.err</string>
    <key>StandardOutPath</key>
    <string>/tmp/{}.out</string>
</dict>
</plist>"#,
            self.config.name, program_args, self.config.name, self.config.name
        );

        fs::write(self.plist_path(), plist_content)
            .context("Failed to write LaunchDaemon plist file")
    }
}

impl ServiceManager for MacOSServiceManager {
    fn install(&self) -> Result<()> {
        // Create the plist file
        self.create_plist_file()?;

        // Set the correct permissions
        Command::new("chmod")
            .args(["644", self.plist_path().to_str().unwrap()])
            .status()
            .context("Failed to set permissions on plist file")?;

        // Load the service
        Command::new("launchctl")
            .args(["load", self.plist_path().to_str().unwrap()])
            .status()
            .context("Failed to load service")?;

        Ok(())
    }

    fn uninstall(&self) -> Result<()> {
        // Unload the service if it exists
        if self.plist_path().exists() {
            let _ = Command::new("launchctl")
                .args(["unload", self.plist_path().to_str().unwrap()])
                .status();
        }

        // Remove the plist file
        if self.plist_path().exists() {
            fs::remove_file(self.plist_path()).context("Failed to remove plist file")?;
        }

        Ok(())
    }

    fn start(&self) -> Result<()> {
        Command::new("launchctl")
            .args(["start", &self.config.name])
            .status()
            .context("Failed to start service")?;
        Ok(())
    }

    fn stop(&self) -> Result<()> {
        Command::new("launchctl")
            .args(["stop", &self.config.name])
            .status()
            .context("Failed to stop service")?;
        Ok(())
    }

    fn status(&self) -> Result<ServiceStatus> {
        if !self.plist_path().exists() {
            return Ok(ServiceStatus::NotInstalled);
        }

        let output = Command::new("launchctl")
            .args(["list"])
            .output()
            .context("Failed to list services")?;

        let output_str = String::from_utf8_lossy(&output.stdout);

        if output_str.contains(&self.config.name) {
            Ok(ServiceStatus::Running)
        } else {
            Ok(ServiceStatus::Stopped)
        }
    }
}
