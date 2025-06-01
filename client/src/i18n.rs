use fluent::{FluentBundle, FluentResource};
use fluent_bundle::FluentArgs;
use std::sync::Mutex;
use unic_langid::LanguageIdentifier;

pub struct Localizer {
    bundle: Mutex<FluentBundle<FluentResource>>,
}

unsafe impl Sync for Localizer {}
unsafe impl Send for Localizer {}

impl Default for Localizer {
    fn default() -> Self {
        Self::new()
    }
}

impl Localizer {
    pub fn new() -> Self {
        let locale_content = include_str!(concat!(env!("OUT_DIR"), "/locale.ftl"));
        let resource = FluentResource::try_new(locale_content.to_string())
            .expect("Failed to parse locale resource");

        let langid: LanguageIdentifier = if cfg!(locale = "ru") {
            "ru".parse().expect("Failed to parse language identifier")
        } else {
            "en".parse().expect("Failed to parse language identifier")
        };

        let mut bundle = FluentBundle::new(vec![langid]);
        bundle.set_use_isolating(false); // Disable BiDi isolation
        bundle
            .add_resource(resource)
            .expect("Failed to add resource to bundle");

        Self {
            bundle: Mutex::new(bundle),
        }
    }

    pub fn get(&self, key: &str) -> String {
        self.get_with_args(key, None)
    }

    pub fn get_with_args(&self, key: &str, args: Option<&FluentArgs>) -> String {
        let bundle = self.bundle.lock().unwrap();
        let msg = bundle
            .get_message(key)
            .unwrap_or_else(|| panic!("Message '{}' not found", key));

        let pattern = msg
            .value()
            .unwrap_or_else(|| panic!("Message '{}' has no value", key));

        let mut errors = vec![];
        let formatted = bundle.format_pattern(pattern, args, &mut errors);

        if !errors.is_empty() {
            eprintln!("Localization errors for key '{}': {:?}", key, errors);
        }

        formatted.to_string()
    }
}

lazy_static::lazy_static! {
    pub static ref LOCALIZER: Localizer = Localizer::new();
}

// Convenience macros for localization
#[macro_export]
macro_rules! t {
    ($key:expr) => {
        $crate::i18n::LOCALIZER.get($key)
    };
    ($key:expr, $($arg_key:expr => $arg_value:expr),*) => {{
        let mut args = fluent_bundle::FluentArgs::new();
        $(
            args.set($arg_key, $arg_value);
        )*
        $crate::i18n::LOCALIZER.get_with_args($key, Some(&args))
    }};
}
