//! The WebAssembly of the image builder page (`/start/`, ADR 0051 §4).
//!
//! A thin layer of `wasm-bindgen` over [`wyrm_image`]: each function the page calls turns JS
//! values into the types of `wyrm-image`, calls it, and turns the result back. The choices,
//! the files and the region are made by [`wyrm_image::Choices::files`] and
//! [`wyrm_image::region`], the same calls `wyr image build --choices` makes, so the page and
//! `wyr` write the same region for the same choices and setup bytes.
//!
//! Nothing here does I/O. The setup code is made of random bytes the page gives
//! (`crypto.getRandomValues`), and only its hash goes into the region.
//!
//! Each binding has a plain Rust function under it ([`offered`], [`setup_from`], [`region_of`],
//! [`check`]): the native tests call those, since a `JsValue` or a `JsError` exists only in
//! a WebAssembly build.

use std::array::TryFromSliceError;

use qrcode::{Color, EcLevel, QrCode};
use wasm_bindgen::prelude::*;
use wyrm_core::hex;
use wyrm_core::setup::{self, CODE_BYTES};
use wyrm_image::{
    region, Catalog, Choices, ChoicesError, ConfigFiles, ImageEntry, ImageError, Index,
};
use zeroize::{Zeroize, Zeroizing};

/// Why the page's call is refused. The bindings hand the message to the page as a `JsError`;
/// a refusal of `wyrm-image` keeps its own sentence.
#[derive(Debug, thiserror::Error)]
pub enum WebError {
    /// The random bytes of a setup code are not [`CODE_BYTES`] (the number
    /// is how many came).
    #[error("a setup code is made of {CODE_BYTES} random bytes, not {0}")]
    SetupBytes(usize),
    /// The setup hash is not 64 hex digits.
    #[error("the setup hash is not 64 hex digits")]
    SetupHash,
    /// The image entry is not the JSON of one entry of the index.
    #[error("the image entry cannot be read: {0}")]
    Entry(serde_json::Error),
    /// The catalog is not the JSON of a catalog of links.
    #[error("the catalog of links cannot be read: {0}")]
    Catalog(serde_json::Error),
    /// The choices are refused.
    #[error(transparent)]
    Choices(#[from] ChoicesError),
    /// The index or the files are refused.
    #[error(transparent)]
    Image(#[from] ImageError),
    /// The QR code of the setup code cannot be made.
    #[error("the QR code of the setup code cannot be made: {0}")]
    Qr(qrcode::types::QrError),
}

/// A new setup code, as the page shows it once.
#[wasm_bindgen(getter_with_clone)]
pub struct Setup {
    /// The code a person types: groups of four base32 characters joined by `-`.
    pub code: String,
    /// The SHA-256 of the code, 64 lower-case hex digits: what [`region_for`] takes.
    pub hash_hex: String,
    /// The code as a QR code: an SVG with a `viewBox` and no size, dark modules in
    /// `currentColor`.
    pub qr_svg: String,
}

impl Drop for Setup {
    /// When the page frees the setup (`setup.free()`), this struct's own copy of the code
    /// is wiped. Only that copy: the strings handed to JavaScript by the `code` getter
    /// and the QR code (`qr_svg`) are not wiped, and neither is anything the page made
    /// of them.
    fn drop(&mut self) {
        self.code.zeroize();
    }
}

/// The images the page may offer: the entries of the checked index ([`Index::parse`]) that
/// have a `download`, in the order of the index. The index carries no `listed` of
/// `boards.json`: an image without a download is one the page cannot fetch.
pub fn offered(index: &str) -> Result<Vec<ImageEntry>, WebError> {
    let index = Index::parse(index)?;
    Ok(index
        .images
        .into_iter()
        .filter(|image| image.download.is_some())
        .collect())
}

/// The setup code made of `random`, exactly [`CODE_BYTES`] bytes from the page's
/// `crypto.getRandomValues`, by [`setup::code_of`] (as `wyrmd setup-code` and
/// `wyr image build --new-setup-code` make one), with its hash and its QR code.
pub fn setup_from(random: &[u8]) -> Result<Setup, WebError> {
    let bytes: Zeroizing<[u8; CODE_BYTES]> = Zeroizing::new(
        random
            .try_into()
            .map_err(|_e: TryFromSliceError| WebError::SetupBytes(random.len()))?,
    );
    let (code, hash) = setup::code_of(&bytes);
    let qr_svg = qr_svg(&code)?;
    Ok(Setup {
        code,
        hash_hex: hex::encode(hash),
        qr_svg,
    })
}

/// The modules of white around a QR code that its readers need.
const QUIET_ZONE: usize = 4;

/// `text` as a QR code of error correction M: an SVG in modules, the quiet zone included,
/// with a `viewBox` and no size (CSS sizes it) and one path of dark modules in
/// `currentColor` (the light ones are the page's background).
fn qr_svg(text: &str) -> Result<String, WebError> {
    let qr = QrCode::with_error_correction_level(text, EcLevel::M).map_err(WebError::Qr)?;
    let width = qr.width();
    let side = width + 2 * QUIET_ZONE;
    let mut path = String::new();
    for (y, row) in qr.to_colors().chunks(width.max(1)).enumerate() {
        for (x, color) in row.iter().enumerate() {
            if *color == Color::Dark {
                let (x, y) = (x + QUIET_ZONE, y + QUIET_ZONE);
                path.push_str(&format!("M{x} {y}h1v1h-1z"));
            }
        }
    }
    Ok(format!(
        "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 {side} {side}\" \
         shape-rendering=\"crispEdges\"><path fill=\"currentColor\" d=\"{path}\"/></svg>"
    ))
}

/// The files of the choices (`wyrm-choices/1`) on the board of `entry` (one entry of the
/// index, as [`offered`] gives it), with the links of `catalog`: [`Choices::files`], as
/// `wyr image build --choices` reads them.
fn files_of(
    choices: &str,
    entry: &str,
    catalog: &str,
    setup_hash: &[u8; 32],
) -> Result<ConfigFiles, WebError> {
    let choices = Choices::parse(choices)?;
    let entry: ImageEntry = serde_json::from_str(entry).map_err(WebError::Entry)?;
    let catalog: Catalog = serde_json::from_str(catalog).map_err(WebError::Catalog)?;
    Ok(choices.files(&entry, &catalog, setup_hash)?)
}

/// The config region for the choices on the board of `entry`, with the links of `catalog`
/// and the setup hash (64 hex digits, [`Setup::hash_hex`]): [`Choices::files`], then
/// [`region`]. Exactly [`wyrm_image::CONFIG_SIZE`] bytes.
pub fn region_of(
    choices: &str,
    entry: &str,
    catalog: &str,
    setup_hash_hex: &str,
) -> Result<Vec<u8>, WebError> {
    let hash = Zeroizing::new(hex::decode_array::<32>(setup_hash_hex).ok_or(WebError::SetupHash)?);
    Ok(region(&files_of(choices, entry, catalog, &hash)?)?)
}

/// The checks of [`region_of`] without a setup hash, for the form while the person
/// chooses. The hash only fills `setup`, and any 32 bytes pass there, so a placeholder
/// takes its place: what this refuses, [`region_of`] refuses with the same sentence.
pub fn check(choices: &str, entry: &str, catalog: &str) -> Result<(), WebError> {
    files_of(choices, entry, catalog, &[0; 32]).map(drop)
}

#[wasm_bindgen]
extern "C" {
    /// `JSON.parse`: the entries reach the page as plain objects.
    #[wasm_bindgen(js_namespace = JSON, js_name = parse, catch)]
    fn json_parse(text: &str) -> Result<JsValue, JsValue>;
}

/// Parses and checks the index of images, and returns the entries the page may offer
/// ([`offered`]) as plain objects, each as the index has it.
#[wasm_bindgen]
pub fn check_index(text: &str) -> Result<JsValue, JsError> {
    let json = serde_json::to_string(&offered(text)?)?;
    json_parse(&json)
        .map_err(|_e: JsValue| JsError::new("the index could not be handed to the page"))
}

/// A new setup code made of `random` (16 bytes of `crypto.getRandomValues`): [`setup_from`].
#[wasm_bindgen]
pub fn new_setup(random: &[u8]) -> Result<Setup, JsError> {
    Ok(setup_from(random)?)
}

/// The 4 MiB config region for the choices: [`region_of`].
#[wasm_bindgen]
pub fn region_for(
    choices_json: &str,
    entry_json: &str,
    catalog_json: &str,
    setup_hash_hex: &str,
) -> Result<Vec<u8>, JsError> {
    Ok(region_of(
        choices_json,
        entry_json,
        catalog_json,
        setup_hash_hex,
    )?)
}

/// The checks of [`region_for`] without a setup hash: [`check`].
#[wasm_bindgen]
pub fn check_choices(
    choices_json: &str,
    entry_json: &str,
    catalog_json: &str,
) -> Result<(), JsError> {
    Ok(check(choices_json, entry_json, catalog_json)?)
}
