//! The S3 link as a package binary (ADR 0011, 0021).

fn main() -> std::process::ExitCode {
    wyrm_link_sdk::process::main::<wyrm_link_s3::S3>()
}
